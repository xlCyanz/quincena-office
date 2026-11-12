# Menú Equipos (diseño, 6 y 12.3): crear equipos, elegir sus miembros, su turno (hora de
# entrada y días; la salida la marca la jornada de 8 horas más el almuerzo) y el
# contrato que llevan. También qué contrato lleva el CEO y quién está sin equipo.
# Desde el hito 31 cada equipo muestra su líder (un líder de equipo añadido entra como
# líder) y, desde Startup, si rinde menos por no tener a su líder presente.
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

var _open_button: Button
var _panel: PanelContainer
var _status_label: Label
var _list: VBoxContainer
var _shown_signature: String = ""
# Controles de cada equipo por id (para las pruebas).
var _controls: Dictionary[int, Dictionary] = {}
var _ceo_project: OptionButton
var _create_button: Button


func _ready() -> void:
	_open_button = Button.new()
	_open_button.text = "Equipos"
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
	title.text = "Equipos"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	header.add_child(title)
	_create_button = Button.new()
	_create_button.text = "Crear equipo"
	_create_button.pressed.connect(func() -> void:
		var team: Dictionary = Staff.create_team()
		_status_label.text = "Creaste %s. Añade miembros y elige su turno." % team["name"])
	header.add_child(_create_button)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.pressed.connect(func() -> void: set_open(false))
	header.add_child(close_button)
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


## Pone el botón "Equipos" en la barra de menús.
func attach_button(menu_bar: Container) -> void:
	menu_bar.add_child(_open_button)


func set_open(open: bool) -> void:
	if open == is_open():
		return
	_panel.visible = open
	if open:
		_status_label.text = ""
		_shown_signature = ""
		_refresh()
	teams_mode_changed.emit(open)


func is_open() -> bool:
	return _panel.visible


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
		people.append("%d:%s:%s:%d" % [employee["id"], employee["name"], employee["role"], int(employee.get("manager_id", 0))])
	var owners: Array[String] = []
	for contract: Dictionary in Projects.contracts:
		owners.append("%d:%d" % [contract["id"], contract["team_id"]])
	# Si el líder está presente cambia lo que se muestra solo al empezar o terminar su turno.
	var presence: Array[bool] = [Staff.leaders_required()]
	for team: Dictionary in Staff.teams:
		presence.append(Staff.is_leader_present(team, Staff.get_absolute_hour()))
		presence.append(Staff.is_manager_present(team, Staff.get_absolute_hour()))
	return JSON.stringify([Staff.teams, people, owners, presence])


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
		else ("Sin empleados todavía." if loose.is_empty() else "Con el horario de su cargo: " + ", ".join(loose) + ".")))


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

	var shift_label := Label.new()
	shift_label.text = "Turno: %s · almuerzo %d:00" % [schedule.describe(), schedule.get_lunch_hour()]
	_list.add_child(shift_label)
	var shift_row := HBoxContainer.new()
	_list.add_child(shift_row)
	shift_row.add_child(_row_label("Entrada"))
	var earlier := Button.new()
	earlier.text = "−"
	earlier.custom_minimum_size = Vector2(36, 0)
	earlier.pressed.connect(func() -> void: _set_shift(team_id, posmod(schedule.start_hour - 1, GameConstants.HOURS_PER_DAY), schedule.days))
	shift_row.add_child(earlier)
	controls["earlier"] = earlier
	var later := Button.new()
	later.text = "+"
	later.custom_minimum_size = Vector2(36, 0)
	later.pressed.connect(func() -> void: _set_shift(team_id, (schedule.start_hour + 1) % GameConstants.HOURS_PER_DAY, schedule.days))
	shift_row.add_child(later)
	controls["later"] = later
	var days_row := HBoxContainer.new()
	_list.add_child(days_row)
	for day: int in range(GameConstants.DAYS_PER_WEEK):
		var toggle := Button.new()
		toggle.text = WorkSchedule.DAY_NAMES[day]
		toggle.toggle_mode = true
		toggle.button_pressed = schedule.days.has(day)
		toggle.custom_minimum_size = Vector2(DAY_BUTTON_WIDTH, 0)
		toggle.pressed.connect(func() -> void:
			var days: Array[int] = schedule.days.duplicate()
			if days.has(day):
				days.erase(day)
			else:
				days.append(day)
			_set_shift(team_id, schedule.start_hour, days))
		days_row.add_child(toggle)
		controls["day_%d" % day] = toggle

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
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Quitar"
		var member_id: int = int(member)
		remove.pressed.connect(func() -> void:
			Staff.remove_from_team(member_id)
			_status_label.text = "%s sale de %s y vuelve al horario de su cargo." % [employee["name"], team["name"]])
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


# Lista desplegable con los contratos en curso para un equipo (o el CEO). Elegir uno se
# lo da; "Ninguno" lo deja sin contrato.
func _project_choice(team_id: int) -> OptionButton:
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.clip_text = true
	choice.add_item("Ninguno", Projects.NO_TEAM)
	var current: Dictionary = Projects.get_contract_of(team_id)
	for contract: Dictionary in Projects.contracts:
		choice.add_item("%s · %s" % [ContractCatalog.get_type_name(contract["type"]), contract["client"]], contract["id"])
		if not current.is_empty() and contract["id"] == current["id"]:
			choice.select(choice.item_count - 1)
	if current.is_empty():
		choice.select(0)
	choice.item_selected.connect(func(index: int) -> void:
		var contract_id: int = choice.get_item_id(index)
		if contract_id == Projects.NO_TEAM:
			var previous: Dictionary = Projects.get_contract_of(team_id)
			if not previous.is_empty():
				_status_label.text = Projects.assign(previous["id"], Projects.NO_TEAM)["message"]
		else:
			_status_label.text = Projects.assign(contract_id, team_id)["message"])
	return choice


func _set_shift(team_id: int, start_hour: int, days: Array[int]) -> void:
	_status_label.text = Staff.set_team_shift(team_id, start_hour, days)["message"]


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
