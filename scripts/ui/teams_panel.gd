# Menú Equipos (diseño, 6 y 12.3): crear equipos, elegir sus miembros, su turno (hora de
# entrada y días; la salida la marca la jornada de 8 horas más el almuerzo) y el
# contrato que llevan. También qué contrato lleva el CEO y quién está sin equipo.
# Desde el hito 31 cada equipo muestra su líder (un líder de equipo añadido entra como
# líder) y, desde Startup, si rinde menos por no tener a su líder presente. Desde el
# hito 34 el turno suma horas extra (ShiftEditor) y marca a quien tiene horario propio.
# Desde el hito 35 se llama Horarios y tiene tres vistas: Equipos (cada uno sigue una
# plantilla o tiene turno propio), Plantillas (nombre y turno; cambiarla cambia todos sus
# equipos) y Agenda (un día a la vez: quién trabaja cada hora y los huecos sin líder).
#
# No pausa el tiempo. Ocupa el lado izquierdo, como Personal y Proyectos (abrir uno
# cierra los otros; lo hace la escena de juego). Se construye en código y solo se
# rehace cuando cambia algo que muestra, para no cerrar una lista desplegable abierta
# cada hora de juego.
class_name TeamsPanel
extends CanvasLayer

## Se abrió (true) o se cerró (false) el panel.
signal teams_mode_changed(active: bool)

const PANEL_WIDTH: float = 560.0
const MARGIN: float = 16.0
const MARGIN_TOP: float = 100.0
const MARGIN_BOTTOM: float = 76.0
const TITLE_FONT_SIZE: int = 24
const SECTION_FONT_SIZE: int = 18
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const DAY_BUTTON_WIDTH: float = 52.0
const VIEW_TEAMS: String = "teams"
const VIEW_TEMPLATES: String = "templates"
const VIEW_AGENDA: String = "agenda"
const VIEW_NAMES: Dictionary[String, String] = {VIEW_TEAMS: "Equipos", VIEW_TEMPLATES: "Plantillas", VIEW_AGENDA: "Agenda"}
const AGENDA_LABEL_WIDTH: float = 104.0
const AGENDA_CELL_SIZE := Vector2(16, 22)
const AGENDA_COLORS: Dictionary[String, Color] = {
	Staff.AGENDA_OFF: Color(1.0, 1.0, 1.0, 0.08), Staff.AGENDA_WORK: Color("4a7fc1"),
	Staff.AGENDA_LUNCH: Color("8a8f98"), Staff.AGENDA_GAP: Color("f2c14e"),
}
const AGENDA_STATE_NAMES: Dictionary[String, String] = {
	Staff.AGENDA_OFF: "libre", Staff.AGENDA_WORK: "trabaja", Staff.AGENDA_LUNCH: "almuerzo", Staff.AGENDA_GAP: "hueco",
}

var _open_button: Button
var _panel: PanelContainer
var _status_label: Label
var _list: VBoxContainer
var _shown_signature: String = ""
# Controles de cada equipo por id (para las pruebas).
var _controls: Dictionary[int, Dictionary] = {}
var _ceo_project: OptionButton
var _create_button: Button
var _view: String = VIEW_TEAMS
var _view_buttons: Dictionary[String, Button] = {}
## Día que muestra la agenda (0 = lunes).
var _agenda_day: int = 0
var _agenda_day_buttons: Array[Button] = []
var _agenda_gaps: Array[String] = []
# Controles de cada plantilla por id (para las pruebas).
var _template_controls: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	_open_button = Button.new()
	_open_button.text = "Horarios"
	_open_button.custom_minimum_size = Hud.MENU_BUTTON_SIZE
	_open_button.focus_mode = Control.FOCUS_NONE
	_open_button.pressed.connect(func() -> void: set_open(not is_open()))

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	root.add_child(_panel)
	_panel.anchor_bottom = 1.0
	_panel.offset_left = MARGIN
	_panel.offset_right = MARGIN + PANEL_WIDTH
	_panel.offset_top = MARGIN_TOP
	_panel.offset_bottom = -MARGIN_BOTTOM
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	_panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := Label.new()
	title.text = "Horarios"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	header.add_child(title)
	_create_button = Button.new()
	_create_button.text = "Crear equipo"
	_create_button.pressed.connect(_create)
	header.add_child(_create_button)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.pressed.connect(func() -> void: set_open(false))
	header.add_child(close_button)
	var tabs := HBoxContainer.new()
	rows.add_child(tabs)
	var group := ButtonGroup.new()
	for view: String in VIEW_NAMES:
		var tab := Button.new()
		tab.text = VIEW_NAMES[view]
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = view == _view
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(func() -> void: set_view(view))
		tabs.add_child(tab)
		_view_buttons[view] = tab
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", MUTED_COLOR)
	rows.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_panel.visible = false
	EventBus.staff_changed.connect(_refresh)
	EventBus.projects_changed.connect(_refresh)
	EventBus.products_changed.connect(_refresh)


## Pone el botón "Horarios" en la barra de menús.
func attach_button(menu_bar: Container) -> void:
	menu_bar.add_child(_open_button)


func set_open(open: bool) -> void:
	if open == is_open():
		return
	_panel.visible = open
	if open:
		_status_label.text = ""
		_shown_signature = ""
		_agenda_day = GameClock.get_weekday()
		_refresh()
	teams_mode_changed.emit(open)


func is_open() -> bool:
	return _panel.visible


## Cambia de vista: VIEW_TEAMS, VIEW_TEMPLATES o VIEW_AGENDA.
func set_view(view: String) -> void:
	_view = view
	# Con el grupo de botones, marcar uno suelta los otros.
	_view_buttons[view].button_pressed = true
	_status_label.text = ""
	_refresh()


func get_view() -> String:
	return _view


func get_view_button(view: String) -> Button:
	return _view_buttons.get(view)


## Cambia el día que muestra la agenda (0 = lunes).
func set_agenda_day(day: int) -> void:
	_agenda_day = day
	_refresh()


func get_agenda_day_button(day: int) -> Button:
	return _agenda_day_buttons[day] if day < _agenda_day_buttons.size() else null


## Huecos que muestra la agenda del día elegido.
func get_agenda_gaps() -> Array[String]:
	return _agenda_gaps


## Control de una plantilla: "name", "delete", "info" o los del turno ("earlier", …).
func get_template_control(template_id: int, control: String) -> Control:
	return _template_controls.get(template_id, {}).get(control)


func get_open_button() -> Button:
	return _open_button


func get_create_button() -> Button:
	return _create_button


func get_status_text() -> String:
	return _status_label.text


## Control de un equipo: "delete", "earlier", "later", "add", "add_choice", "project",
## "day_0" … "day_6", "remove_<id del empleado>", "leader_label" o "remove_leader". null
## si no existe.
func get_team_control(team_id: int, control: String) -> Control:
	return _controls.get(team_id, {}).get(control)


## Lista de contratos para el CEO.
func get_ceo_project_choice() -> OptionButton:
	return _ceo_project


## Todo el texto del panel (para las pruebas).
func get_list_text() -> String:
	var texts: Array[String] = []
	for label: Node in _list.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return "\n".join(texts)


# Resumen de todo lo que muestra el panel: si no cambió, no hace falta rehacerlo.
func _signature() -> String:
	var people: Array[String] = []
	for employee: Dictionary in Staff.employees:
		people.append("%d:%s:%s:%d:%s" % [employee["id"], employee["name"], employee["role"], int(employee.get("manager_id", 0)),
			Staff.get_schedule(employee).describe() if Staff.has_own_schedule(employee) else ""])
	var owners: Array[String] = []
	for contract: Dictionary in Projects.contracts:
		owners.append("%d:%d" % [contract["id"], contract["team_id"]])
	for product: Dictionary in Products.get_in_development():
		owners.append("p%d:%d" % [product["id"], product["team_id"]])
	# Si el líder está presente cambia lo que se muestra solo al empezar o terminar su turno.
	var presence: Array[bool] = [Staff.leaders_required()]
	for team: Dictionary in Staff.teams:
		presence.append(Staff.is_leader_present(team, Staff.get_absolute_hour()))
		presence.append(Staff.is_manager_present(team, Staff.get_absolute_hour()))
	return JSON.stringify([Staff.teams, people, owners, presence, Staff.shift_templates, _view, _agenda_day])


func _refresh() -> void:
	if _list == null or not is_open():
		return
	var signature: String = _signature()
	if signature == _shown_signature:
		return
	_shown_signature = signature
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_controls.clear()
	_template_controls.clear()
	_agenda_day_buttons.clear()
	_create_button.visible = _view != VIEW_AGENDA
	_create_button.text = "Crear plantilla" if _view == VIEW_TEMPLATES else "Crear equipo"
	if _view == VIEW_TEMPLATES:
		_add_templates()
		return
	if _view == VIEW_AGENDA:
		_add_agenda()
		return

	_add_section("CEO")
	var ceo_row := HBoxContainer.new()
	_list.add_child(ceo_row)
	var ceo_label := _row_label("Trabaja solo en su contrato:")
	ceo_row.add_child(ceo_label)
	_ceo_project = _project_choice(Projects.CEO_TEAM)
	ceo_row.add_child(_ceo_project)
	_list.add_child(HSeparator.new())

	_add_section("Equipos (%d)" % Staff.teams.size())
	if Staff.teams.is_empty():
		_list.add_child(_muted_label("No hay equipos. Cada equipo con miembros lleva un contrato con su propio turno."))
	for team: Dictionary in Staff.teams:
		_add_team(team)

	_add_section("Sin equipo")
	var loose: Array[String] = []
	for employee: Dictionary in Staff.get_employees_without_team():
		loose.append("%s (%s)" % [employee["name"], Staff.get_schedule(employee).describe()])
	_list.add_child(_muted_label("Nadie: todos están en un equipo." if loose.is_empty() and not Staff.employees.is_empty()
		else ("Sin empleados todavía." if loose.is_empty() else "Con el horario de su cargo o el suyo: " + ", ".join(loose) + ".")))


func _add_team(team: Dictionary) -> void:
	var team_id: int = team["id"]
	var controls: Dictionary = {}
	_controls[team_id] = controls
	var schedule: WorkSchedule = WorkSchedule.from_dict(team["schedule"])
	var members: Array = team["members"]

	var header := HBoxContainer.new()
	_list.add_child(header)
	var name_label := Label.new()
	var leader: Dictionary = Staff.get_team_leader(team)
	name_label.text = "%s · %d %s%s" % [team["name"], members.size(), "persona" if members.size() == 1 else "personas",
		" + líder" if not leader.is_empty() else ""]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	header.add_child(name_label)
	var delete := Button.new()
	delete.text = "Borrar"
	delete.pressed.connect(func() -> void:
		Staff.delete_team(team_id)
		_status_label.text = "Borraste %s; sus miembros vuelven al horario de su cargo." % team["name"])
	header.add_child(delete)
	controls["delete"] = delete

	var template: Dictionary = Staff.get_template_of(team)
	var shift_label := Label.new()
	shift_label.text = "Turno: %s · almuerzo %d:00" % [schedule.describe(), schedule.get_lunch_hour()]
	_list.add_child(shift_label)
	var template_row := HBoxContainer.new()
	_list.add_child(template_row)
	template_row.add_child(_row_label("Plantilla:"))
	var template_choice := OptionButton.new()
	template_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	template_choice.clip_text = true
	for item: Dictionary in Staff.shift_templates:
		template_choice.add_item(item["name"], item["id"])
		if not template.is_empty() and item["id"] == template["id"]:
			template_choice.select(template_choice.item_count - 1)
	template_choice.add_item("Turno propio", Staff.NO_TEMPLATE)
	if template.is_empty():
		template_choice.select(template_choice.item_count - 1)
	template_choice.item_selected.connect(func(index: int) -> void:
		_status_label.text = Staff.set_team_template(team_id, template_choice.get_item_id(index))["message"])
	template_row.add_child(template_choice)
	controls["template"] = template_choice
	if not template.is_empty():
		template_row.add_child(_row_label("(el turno edita la plantilla)"))
	var editor := ShiftEditor.new(DAY_BUTTON_WIDTH)
	editor.set_schedule(schedule)
	editor.changed.connect(func(start_hour: int, days: Array[int], overtime: int) -> void:
		if template.is_empty():
			_set_shift(team_id, start_hour, days, overtime)
		else:
			_status_label.text = Staff.set_template_shift(template["id"], start_hour, days, overtime)["message"])
	_list.add_child(editor)
	controls.merge(editor.get_controls())

	var project_row := HBoxContainer.new()
	_list.add_child(project_row)
	project_row.add_child(_row_label("Contrato:"))
	var project := _project_choice(team_id)
	project_row.add_child(project)
	controls["project"] = project

	var leader_row := HBoxContainer.new()
	_list.add_child(leader_row)
	var leader_label := Label.new()
	leader_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leader_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leader_row.add_child(leader_label)
	controls["leader_label"] = leader_label
	var present: bool = Staff.is_leader_present(team, Staff.get_absolute_hour())
	if leader.is_empty():
		leader_label.text = "Líder: ninguno"
	else:
		leader_label.text = "Líder: %s (%s)" % [leader["name"], "presente" if present else "fuera de turno"]
		var manager: Dictionary = Staff.get_manager_of(leader)
		if not manager.is_empty():
			leader_label.text += " · gerente %s%s" % [manager["name"], " presente: +%d %%" % roundi(
				float(StaffCatalog.get_management("manager_bonus")) * 100.0) if Staff.is_manager_present(team, Staff.get_absolute_hour()) else ""]
		var leader_id: int = leader["id"]
		var remove_leader := Button.new()
		remove_leader.text = "Quitar"
		remove_leader.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		remove_leader.pressed.connect(func() -> void:
			Staff.remove_from_team(leader_id)
			_status_label.text = "%s deja de liderar %s; sigue siendo líder de equipo." % [leader["name"], team["name"]])
		leader_row.add_child(remove_leader)
		controls["remove_leader"] = remove_leader
	if Staff.leaders_required() and not present:
		leader_label.text += " · rinde %d %% sin su líder presente" % roundi(float(StaffCatalog.get_teams("no_leader_factor")) * 100.0)
		leader_label.add_theme_color_override("font_color", Color("f2c14e"))

	for member: Variant in members:
		var employee: Dictionary = Staff.get_employee(int(member))
		var row := HBoxContainer.new()
		_list.add_child(row)
		var label := Label.new()
		label.text = "%s · %s" % [employee["name"], Staff.describe_employee(employee)]
		if Staff.has_own_schedule(employee):
			label.text += " · horario propio"
			label.tooltip_text = Staff.get_schedule(employee).describe()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Quitar"
		var member_id: int = int(member)
		remove.pressed.connect(func() -> void:
			Staff.remove_from_team(member_id)
			_status_label.text = "%s sale de %s." % [employee["name"], team["name"]])
		row.add_child(remove)
		controls["remove_%d" % member_id] = remove

	var add_row := HBoxContainer.new()
	_list.add_child(add_row)
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.clip_text = true
	for employee: Dictionary in Staff.employees:
		var current: Dictionary = Staff.get_team_of(employee["id"])
		if int(current.get("id", 0)) == team_id or Staff.is_manager(employee) or Staff.is_executive(employee):
			continue
		var where: String = "sin equipo" if current.is_empty() else "en %s" % current["name"]
		choice.add_item("%s (%s, %s)" % [employee["name"], StaffCatalog.get_role_name(employee["role"]), where], employee["id"])
	add_row.add_child(choice)
	controls["add_choice"] = choice
	var add := Button.new()
	add.text = "Añadir"
	add.disabled = choice.item_count == 0
	add.tooltip_text = "No hay más empleados para añadir." if choice.item_count == 0 else ""
	add.pressed.connect(func() -> void:
		if choice.selected >= 0:
			_status_label.text = Staff.add_to_team(team_id, choice.get_item_id(choice.selected))["message"])
	add_row.add_child(add)
	controls["add"] = add
	_list.add_child(HSeparator.new())


# Lista desplegable con los contratos en curso y los productos en desarrollo para un
# equipo (o el CEO). Elegir uno se lo da; "Ninguno" lo deja sin proyecto. Cada opción
# guarda en su metadata {"kind": "contract"/"product", "id"}.
func _project_choice(team_id: int) -> OptionButton:
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.clip_text = true
	choice.add_item("Ninguno")
	choice.set_item_metadata(0, {})
	var current_contract: Dictionary = Projects.get_contract_of(team_id)
	var current_product: Dictionary = Products.get_product_of(team_id)
	choice.select(0)
	for contract: Dictionary in Projects.contracts:
		choice.add_item("%s · %s" % [ContractCatalog.get_type_name(contract["type"]), contract["client"]])
		choice.set_item_metadata(choice.item_count - 1, {"kind": "contract", "id": contract["id"]})
		if not current_contract.is_empty() and contract["id"] == current_contract["id"]:
			choice.select(choice.item_count - 1)
	for product: Dictionary in Products.get_in_development():
		choice.add_item("Producto: %s" % Products.describe_title(product))
		choice.set_item_metadata(choice.item_count - 1, {"kind": "product", "id": product["id"]})
		if not current_product.is_empty() and product["id"] == current_product["id"]:
			choice.select(choice.item_count - 1)
	choice.item_selected.connect(func(index: int) -> void:
		var picked: Dictionary = choice.get_item_metadata(index)
		if picked.is_empty():
			var previous: Dictionary = Projects.get_contract_of(team_id)
			if not previous.is_empty():
				_status_label.text = Projects.assign(previous["id"], Projects.NO_TEAM)["message"]
			var previous_product: Dictionary = Products.get_product_of(team_id)
			if not previous_product.is_empty():
				_status_label.text = Products.assign(previous_product["id"], Projects.NO_TEAM)["message"]
		elif picked["kind"] == "product":
			_status_label.text = Products.assign(picked["id"], team_id)["message"]
		else:
			_status_label.text = Projects.assign(picked["id"], team_id)["message"])
	return choice


func _create() -> void:
	if _view == VIEW_TEMPLATES:
		var template: Dictionary = Staff.create_template()
		_status_label.text = "Creaste la plantilla %s. Elige su nombre y su turno." % template["name"]
	else:
		var team: Dictionary = Staff.create_team()
		_status_label.text = "Creaste %s. Añade miembros y elige su turno." % team["name"]


# Vista Plantillas: nombre, turno y cuántos equipos la siguen.
func _add_templates() -> void:
	_add_section("Plantillas (%d)" % Staff.shift_templates.size())
	if Staff.shift_templates.is_empty():
		_list.add_child(_muted_label("No hay plantillas. Una plantilla da el mismo turno a varios equipos."))
	for template: Dictionary in Staff.shift_templates:
		var template_id: int = template["id"]
		var controls: Dictionary = {}
		_template_controls[template_id] = controls
		var schedule: WorkSchedule = WorkSchedule.from_dict(template["schedule"])
		var header := HBoxContainer.new()
		_list.add_child(header)
		var name_edit := LineEdit.new()
		name_edit.text = template["name"]
		name_edit.max_length = int(StaffCatalog.get_teams("max_template_name"))
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.text_submitted.connect(func(text: String) -> void:
			_status_label.text = Staff.rename_template(template_id, text)["message"])
		name_edit.focus_exited.connect(func() -> void:
			if name_edit.text != String(Staff.get_template(template_id).get("name", name_edit.text)):
				_status_label.text = Staff.rename_template(template_id, name_edit.text)["message"])
		header.add_child(name_edit)
		controls["name"] = name_edit
		var delete := Button.new()
		delete.text = "Borrar"
		delete.pressed.connect(func() -> void: _status_label.text = Staff.delete_template(template_id)["message"])
		header.add_child(delete)
		controls["delete"] = delete
		var users: Array[String] = []
		for team: Dictionary in Staff.get_teams_with_template(template_id):
			users.append(team["name"])
		var info := _muted_label("%s · almuerzo %d:00 · %s" % [schedule.describe(), schedule.get_lunch_hour(),
			"ningún equipo" if users.is_empty() else "la siguen " + ", ".join(users)])
		_list.add_child(info)
		controls["info"] = info
		var editor := ShiftEditor.new(DAY_BUTTON_WIDTH)
		editor.set_schedule(schedule)
		editor.changed.connect(func(start_hour: int, days: Array[int], overtime: int) -> void:
			_status_label.text = Staff.set_template_shift(template_id, start_hour, days, overtime)["message"])
		_list.add_child(editor)
		controls.merge(editor.get_controls())
		_list.add_child(HSeparator.new())


# Vista Agenda: un día; una fila por equipo y por persona con horario propio, una
# columna por hora, y debajo los huecos.
func _add_agenda() -> void:
	var days_row := HBoxContainer.new()
	_list.add_child(days_row)
	var group := ButtonGroup.new()
	for day: int in range(GameConstants.DAYS_PER_WEEK):
		var button := Button.new()
		button.text = WorkSchedule.DAY_NAMES[day]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = day == _agenda_day
		button.custom_minimum_size = Vector2(DAY_BUTTON_WIDTH, 0)
		button.pressed.connect(func() -> void: set_agenda_day(day))
		days_row.add_child(button)
		_agenda_day_buttons.append(button)
	var rows: Array[Dictionary] = Staff.get_agenda(_agenda_day)
	_agenda_gaps = Staff.get_agenda_gaps(_agenda_day)
	if rows.is_empty():
		_list.add_child(_muted_label("No hay equipos ni personas con horario propio. Quien sigue el horario de su cargo no sale en la agenda."))
		return
	var grid := GridContainer.new()
	grid.columns = GameConstants.HOURS_PER_DAY + 1
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 3)
	_list.add_child(grid)
	grid.add_child(Control.new())
	for hour: int in range(GameConstants.HOURS_PER_DAY):
		var hour_label := Label.new()
		hour_label.text = str(hour) if hour % 3 == 0 else ""
		hour_label.custom_minimum_size = Vector2(AGENDA_CELL_SIZE.x, 0)
		hour_label.add_theme_font_size_override("font_size", 11)
		hour_label.add_theme_color_override("font_color", MUTED_COLOR)
		grid.add_child(hour_label)
	for row: Dictionary in rows:
		var name_label := Label.new()
		name_label.text = row["label"]
		name_label.clip_text = true
		name_label.custom_minimum_size = Vector2(AGENDA_LABEL_WIDTH, 0)
		if row["kind"] == "employee":
			name_label.add_theme_color_override("font_color", MUTED_COLOR)
		grid.add_child(name_label)
		var cells: Array = row["cells"]
		for hour: int in range(cells.size()):
			var cell := ColorRect.new()
			cell.color = AGENDA_COLORS[cells[hour]]
			cell.custom_minimum_size = AGENDA_CELL_SIZE
			cell.tooltip_text = "%s · %d:00 · %s" % [row["label"], hour, AGENDA_STATE_NAMES[cells[hour]]]
			grid.add_child(cell)
	var legend := HBoxContainer.new()
	_list.add_child(legend)
	for state: String in [Staff.AGENDA_WORK, Staff.AGENDA_LUNCH, Staff.AGENDA_GAP]:
		var swatch := ColorRect.new()
		swatch.color = AGENDA_COLORS[state]
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(swatch)
		var state_name: String = AGENDA_STATE_NAMES[state]
		legend.add_child(_row_label(state_name.left(1).to_upper() + state_name.substr(1) + "   "))
	if _agenda_gaps.is_empty():
		_list.add_child(_muted_label("Sin huecos este día." if Staff.leaders_required()
			else "Sin huecos: en %s los equipos rinden igual sin líder." % Company.get_stage_name(Company.stage)))
	else:
		var gaps := Label.new()
		gaps.text = "Huecos: %s." % "; ".join(_agenda_gaps)
		if "".join(_agenda_gaps).contains("sin líder"):
			gaps.text += " Sin su líder un equipo rinde %d %%." % roundi(float(StaffCatalog.get_teams("no_leader_factor")) * 100.0)
		if "".join(_agenda_gaps).contains("Recepción"):
			gaps.text += " Sin recepcionista los clientes se van."
		gaps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gaps.add_theme_color_override("font_color", AGENDA_COLORS[Staff.AGENDA_GAP])
		_list.add_child(gaps)


func _set_shift(team_id: int, start_hour: int, days: Array[int], overtime: int) -> void:
	_status_label.text = Staff.set_team_shift(team_id, start_hour, days, overtime)["message"]


func _add_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	_list.add_child(label)


# Etiqueta corta dentro de una fila: sin cortar líneas, para que no quede de ancho 0.
func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label
