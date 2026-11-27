# Personal, capa 4: pestaña Organigrama (departamentos con su ejecutivo y árbol CEO → gerentes → líderes → equipos).
extends "res://scripts/ui/staff/staff_panel_hiring.gd"

## Sangría de los líderes bajo su gerente (por ahí pasa la línea).
const LEADER_INDENT: float = 22.0
const COLUMN_WIDTH: float = 300.0


func _build_org(view: HBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_child(scroll)
	_org_list = VBoxContainer.new()
	_org_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_org_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_org_list)


# Solo hay organigrama con líderes, gerentes, ejecutivos o departamentos.
func _has_org_chart() -> bool:
	return not (Staff.get_leaders().is_empty() and Staff.get_managers().is_empty() and Staff.get_executives().is_empty()
		and not Staff.departments_apply())


func _refresh_org() -> void:
	for child: Node in _org_list.get_children():
		_org_list.remove_child(child)
		child.queue_free()
	_department_choices.clear()
	_boss_choices.clear()
	_org_links.clear()
	_org_tree = null
	if not _has_org_chart():
		return
	_section(_org_list, "Organigrama")
	_add_departments(Staff.get_executives())
	_add_tree()


# Departamentos: quién dirige cada uno y cuánto rinde; cada ejecutivo elige el suyo.
func _add_departments(executives: Array[Dictionary]) -> void:
	_org_list.add_child(_strong("Departamentos"))
	var departments: Array[String] = Staff.get_departments()
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 8)
	cards.add_theme_constant_override("v_separation", 8)
	_org_list.add_child(cards)
	for department: String in departments:
		var executive: Dictionary = Staff.get_executive_of(department)
		var factor: float = Staff.get_department_factor(department)
		var size: int = Staff.get_department_size(department)
		var card: PanelContainer = _card_panel()
		card.custom_minimum_size.x = 300.0
		cards.add_child(card)
		var rows := HBoxContainer.new()
		rows.add_theme_constant_override("separation", 8)
		card.add_child(rows)
		rows.add_child(_ceo_photo(36.0) if executive.is_empty() else _photo(executive, 36.0))
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(texts)
		var label: Label = _muted_label("%s · %d %s · lo dirige %s · rinde %d %%" % [StaffCatalog.get_department_name(department),
			size, "persona" if size == 1 else "personas", "el CEO" if executive.is_empty() else executive["name"],
			roundi(factor * 100.0)])
		label.custom_minimum_size.x = 230.0
		label.add_theme_color_override("font_color", UiTheme.TEXT)
		texts.add_child(label)
		texts.add_child(Bar.new(factor * 100.0 / 1.5, UiTheme.POSITIVE if factor >= 1.0 else UiTheme.ACCENT, 5.0))
	if departments.is_empty():
		_org_list.add_child(_muted_label("Todavía no hay departamentos: existen desde que tienen un empleado."))
	elif not Staff.departments_apply():
		_org_list.add_child(_muted_label("Desde %s el CEO rinde menos cuantos más departamentos dirige." % Company.get_stage_name(
			int(StaffCatalog.get_departments("from_stage")))))
	if executives.is_empty():
		return
	var rows := HFlowContainer.new()
	rows.add_theme_constant_override("h_separation", 8)
	rows.add_theme_constant_override("v_separation", 8)
	_org_list.add_child(rows)
	for executive: Dictionary in executives:
		var card: PanelContainer = _card_panel()
		rows.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		row.add_child(_photo(executive, 36.0))
		var label: Label = _strong("Ejecutivo %s" % executive["name"])
		row.add_child(label)
		var choice := OptionButton.new()
		choice.focus_mode = Control.FOCUS_NONE
		var ids: Array[String] = StaffCatalog.get_department_ids()
		for index: int in range(ids.size()):
			var other: Dictionary = Staff.get_executive_of(ids[index])
			choice.add_item("Dirige %s" % StaffCatalog.get_department_name(ids[index]), index)
			choice.set_item_disabled(index, not other.is_empty() and other != executive)
			if executive.get("department", "") == ids[index]:
				choice.select(index)
		if String(executive.get("department", "")).is_empty():
			choice.add_item("Sin departamento", ids.size())
			choice.set_item_disabled(ids.size(), true)
			choice.select(ids.size())
		var executive_id: int = executive["id"]
		choice.item_selected.connect(func(index: int) -> void:
			if index < ids.size():
				_set_status(Staff.set_executive_department(executive_id, ids[index])["message"])
			_refresh.call_deferred())
		row.add_child(choice)
		_department_choices[executive_id] = choice


# Árbol: el CEO arriba, una columna por gerente con sus líderes y una del CEO con los que dirige él.
func _add_tree() -> void:
	var leaders: Array[Dictionary] = Staff.get_leaders()
	var managers: Array[Dictionary] = Staff.get_managers()
	_org_list.add_child(_strong("Quién dirige a quién"))
	_org_tree = VBoxContainer.new()
	_org_tree.add_theme_constant_override("separation", 28)
	_org_tree.draw.connect(_draw_org_links)
	_org_list.add_child(_org_tree)

	var ceo_row := HBoxContainer.new()
	ceo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_org_tree.add_child(ceo_row)
	var ceo_card: PanelContainer = _boss_card(_ceo_photo(BOSS_PHOTO), "CEO · dirige %d de %d líderes con equipo" % [
		Staff.get_ceo_leaders().size(), Staff.get_leader_cap(0)])
	ceo_row.add_child(ceo_card)

	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 16)
	_org_tree.add_child(columns)
	for manager: Dictionary in managers:
		var present: bool = Staff.is_expected_now(Staff.employee_key(manager["id"]))
		var column: VBoxContainer = _tree_column(columns)
		var line: String = "Gerente %s · dirige %d de %d líderes (%s) · sus equipos rinden +%d %% mientras está presente" % [
			manager["name"], Staff.get_leaders_of(manager["id"]).size(), Staff.get_leader_cap(manager["id"]),
			"presente" if present else "fuera de turno", roundi(float(StaffCatalog.get_management("manager_bonus")) * 100.0)]
		var card: PanelContainer = _boss_card(_photo(manager, BOSS_PHOTO), line)
		column.add_child(card)
		_org_links.append([ceo_card, card, true])
		for leader: Dictionary in leaders:
			if int(leader.get("manager_id", 0)) == int(manager["id"]):
				_org_links.append([card, _add_leader(column, leader, managers), false])
	var direct: Array[Dictionary] = []
	for leader: Dictionary in leaders:
		if int(leader.get("manager_id", 0)) == 0:
			direct.append(leader)
	if not direct.is_empty():
		var column: VBoxContainer = _tree_column(columns)
		var head: Label = _caption("A cargo directo del CEO")
		column.add_child(head)
		_org_links.append([ceo_card, head, true])
		for leader: Dictionary in direct:
			_org_links.append([head, _add_leader(column, leader, managers), false])
	if leaders.is_empty() and managers.is_empty():
		_org_tree.add_child(_muted_label("Todavía no hay líderes de equipo: un Senior asciende a líder desde su ficha."))


func _tree_column(parent: Container) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = COLUMN_WIDTH
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)
	return column


# Tarjeta del CEO o de un gerente: foto y la línea que dice a cuántos líderes dirige.
func _boss_card(photo: EmployeePortrait, line: String) -> PanelContainer:
	var card: PanelContainer = _card_panel()
	card.custom_minimum_size.x = COLUMN_WIDTH
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(photo)
	var label: Label = _strong(line)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = COLUMN_WIDTH - BOSS_PHOTO - 40.0
	row.add_child(label)
	return card


# Tarjeta de un líder con su lista «A cargo de» y las caras de su equipo.
func _add_leader(column: VBoxContainer, leader: Dictionary, managers: Array[Dictionary]) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(LEADER_INDENT))
	column.add_child(margin)
	var card: PanelContainer = _card_panel()
	margin.add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	card.add_child(rows)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	rows.add_child(top)
	top.add_child(_photo(leader, LEADER_PHOTO))
	var team: Dictionary = Staff.get_team_of(leader["id"])
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(texts)
	var label: Label = _strong("Líder %s" % leader["name"])
	texts.add_child(label)
	texts.add_child(_caption(String(team["name"]) if not team.is_empty() else "sin equipo"))

	var choice := OptionButton.new()
	choice.focus_mode = Control.FOCUS_NONE
	choice.add_item("A cargo del CEO", 0)
	for manager: Dictionary in managers:
		choice.add_item("A cargo de %s" % manager["name"], manager["id"])
		if int(leader.get("manager_id", 0)) == int(manager["id"]):
			choice.select(choice.item_count - 1)
	if int(leader.get("manager_id", 0)) == 0:
		choice.select(0)
	choice.disabled = managers.is_empty()
	choice.tooltip_text = "Contrata o asciende un gerente para repartir los líderes." if managers.is_empty() else ""
	var leader_id: int = leader["id"]
	choice.item_selected.connect(func(index: int) -> void:
		_set_status(Staff.set_manager(leader_id, choice.get_item_id(index))["message"])
		_refresh.call_deferred())
	rows.add_child(choice)
	_boss_choices[leader_id] = choice

	if not team.is_empty():
		var faces := HBoxContainer.new()
		faces.add_theme_constant_override("separation", 2)
		rows.add_child(faces)
		var members: Array = team["members"]
		for index: int in range(mini(members.size(), TEAM_FACES)):
			var member: Dictionary = Staff.get_employee(int(members[index]))
			if not member.is_empty():
				var face: EmployeePortrait = _photo(member, MEMBER_PHOTO)
				face.tooltip_text = member["name"]
				faces.add_child(face)
		if members.size() > TEAM_FACES:
			faces.add_child(_caption("+%d" % (members.size() - TEAM_FACES)))
		if members.is_empty():
			faces.add_child(_caption("Equipo sin miembros"))
	return card


# Líneas del árbol: de arriba abajo en codo (CEO → columnas) o por el costado (gerente → líderes).
func _draw_org_links() -> void:
	if _org_tree == null:
		return
	var origin: Vector2 = _org_tree.get_global_rect().position
	for link: Array in _org_links:
		var parent: Control = link[0]
		var child: Control = link[1]
		if not is_instance_valid(parent) or not is_instance_valid(child):
			continue
		var from: Rect2 = Rect2(parent.get_global_rect().position - origin, parent.get_global_rect().size)
		var to: Rect2 = Rect2(child.get_global_rect().position - origin, child.get_global_rect().size)
		if bool(link[2]):
			var start := Vector2(from.get_center().x, from.end.y)
			var finish := Vector2(to.get_center().x, to.position.y)
			var middle: float = (start.y + finish.y) / 2.0
			_org_tree.draw_polyline(PackedVector2Array([start, Vector2(start.x, middle), Vector2(finish.x, middle), finish]),
				LINE_COLOR, LINE_WIDTH)
		else:
			var spine: float = from.position.x + LEADER_INDENT / 2.0
			var y: float = to.get_center().y
			_org_tree.draw_polyline(PackedVector2Array([Vector2(spine, from.end.y), Vector2(spine, y), Vector2(to.position.x, y)]),
				LINE_COLOR, LINE_WIDTH)
