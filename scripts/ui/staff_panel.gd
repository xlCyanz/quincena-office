# Menú Personal (diseño, 12.3) con vacantes, candidatos y empleados (5.2): publicar
# una vacante (cargo, nivel, sueldo ofrecido y publicidad), ver las abiertas con sus
# candidatos, cerrarlas, descartar, entrevistar y hacer ofertas, y ver los empleados
# con los puestos de trabajo libres. La oferta de cada candidato empieza en el sueldo
# de su vacante y se sube o se baja de a salary_step.
#
# No pausa el tiempo: los candidatos llegan mientras está abierto. Ocupa el lado
# izquierdo para que la oficina siga a la vista. Se construye en código; su botón va
# en la barra de menús (attach_button) y muestra cuántos candidatos esperan.
#
# Desde el hito 32, con líderes o gerentes, muestra el organigrama: el CEO y cada gerente
# con los líderes que dirigen, y para cada líder una lista para elegir quién lo dirige.
class_name StaffPanel
extends CanvasLayer

## Se abrió (true) o se cerró (false) el panel.
signal staff_mode_changed(active: bool)
## Se pidió ver la ficha de un empleado.
signal employee_selected(employee_id: int)

const PANEL_WIDTH: float = 560.0
const MARGIN: float = 16.0
## Espacio que se deja arriba (dinero) y abajo (barra de menús).
const MARGIN_TOP: float = 100.0
const MARGIN_BOTTOM: float = 76.0
const TITLE_FONT_SIZE: int = 24
const SECTION_FONT_SIZE: int = 18
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.7)

# Botón «?» de ayuda (hito 64).
var _help_button: Button
var _open_button: Button
var _panel: PanelContainer
var _role_option: OptionButton
var _level_option: OptionButton
var _salary_label: Label
var _table_label: Label
var _salary_down: Button
var _salary_up: Button
var _publicity_check: CheckBox
var _outlook_label: Label
var _publish_button: Button
var _status_label: Label
var _list: VBoxContainer
var _salary: int = 0
var _vacancy_close_buttons: Dictionary[int, Button] = {}
var _discard_buttons: Dictionary[int, Button] = {}
var _interview_buttons: Dictionary[int, Button] = {}
var _delegate_buttons: Dictionary[int, Button] = {}
## Lista del departamento que dirige cada ejecutivo en el organigrama (por id).
var _department_choices: Dictionary[int, OptionButton] = {}
var _offer_buttons: Dictionary[int, Button] = {}
var _offer_step_buttons: Dictionary[int, Array] = {}
var _counter_buttons: Dictionary[int, Button] = {}
var _card_buttons: Dictionary[int, Button] = {}
## Lista "A cargo de" de cada líder en el organigrama (por id del líder).
var _boss_choices: Dictionary[int, OptionButton] = {}
## Sueldo que se le va a ofrecer a cada candidato (por id).
var _offers: Dictionary[int, int] = {}


func _ready() -> void:
	_open_button = Button.new()
	_open_button.custom_minimum_size = Hud.MENU_BUTTON_SIZE
	_open_button.pressed.connect(func() -> void: set_open(not is_open()))

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	root.add_child(_panel)
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = MARGIN
	_panel.offset_right = MARGIN + PANEL_WIDTH
	_panel.offset_top = MARGIN_TOP
	_panel.offset_bottom = -MARGIN_BOTTOM
	# Ancho y alto según la pantalla y la barra de menús (hito 65).
	UiLayout.fit_left_panel(_panel, PANEL_WIDTH)
	EventBus.ui_layout_changed.connect(func() -> void: UiLayout.fit_left_panel(_panel, PANEL_WIDTH))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	_panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := Label.new()
	title.text = "Personal"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.pressed.connect(func() -> void: set_open(false))
	_help_button = HelpButton.create("staff")
	header.add_child(_help_button)
	header.add_child(close_button)
	# Bajo la cabecera todo se desplaza junto, para que quepa con la interfaz grande (hito 65).
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)

	_add_section(rows, "Nueva vacante")
	var choice_row := HBoxContainer.new()
	rows.add_child(choice_row)
	_role_option = OptionButton.new()
	for role: String in StaffCatalog.get_role_ids():
		_role_option.add_item(StaffCatalog.get_role_name(role))
	_role_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_role_option.item_selected.connect(func(_index: int) -> void: _reset_salary())
	_refresh_role_locks()
	choice_row.add_child(_role_option)
	_level_option = OptionButton.new()
	for level: String in StaffCatalog.get_level_ids():
		_level_option.add_item(StaffCatalog.get_level_name(level))
	_level_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_option.select(1)
	_level_option.item_selected.connect(func(_index: int) -> void: _reset_salary())
	choice_row.add_child(_level_option)

	var salary_row := HBoxContainer.new()
	rows.add_child(salary_row)
	var salary_title := Label.new()
	salary_title.text = "Sueldo ofrecido:"
	salary_row.add_child(salary_title)
	_salary_down = Button.new()
	_salary_down.text = "−"
	_salary_down.tooltip_text = "Bajar el sueldo ofrecido"
	_salary_down.custom_minimum_size = Vector2(36, 0)
	_salary_down.pressed.connect(func() -> void: _change_salary(-1))
	salary_row.add_child(_salary_down)
	_salary_label = Label.new()
	_salary_label.custom_minimum_size = Vector2(130, 0)
	_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	salary_row.add_child(_salary_label)
	_salary_up = Button.new()
	_salary_up.text = "+"
	_salary_up.tooltip_text = "Subir el sueldo ofrecido"
	_salary_up.custom_minimum_size = Vector2(36, 0)
	_salary_up.pressed.connect(func() -> void: _change_salary(1))
	salary_row.add_child(_salary_up)
	_table_label = Label.new()
	_table_label.add_theme_color_override("font_color", MUTED_COLOR)
	salary_row.add_child(_table_label)

	_outlook_label = Label.new()
	_outlook_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outlook_label.add_theme_color_override("font_color", MUTED_COLOR)
	rows.add_child(_outlook_label)
	_publicity_check = CheckBox.new()
	_publicity_check.text = "Con publicidad: %s, más candidatos durante %d días" % [
		MoneyFormat.format(int(StaffCatalog.get_hiring("publicity_cost"))), int(StaffCatalog.get_hiring("publicity_days"))]
	rows.add_child(_publicity_check)
	_publish_button = Button.new()
	_publish_button.text = "Publicar vacante"
	_publish_button.pressed.connect(_on_publish_pressed)
	rows.add_child(_publish_button)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", MUTED_COLOR)
	rows.add_child(_status_label)

	rows.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	rows.add_child(_list)

	_reset_salary()
	_panel.visible = false
	EventBus.staff_changed.connect(_refresh)
	EventBus.office_changed.connect(_refresh)
	EventBus.hour_changed.connect(func(_hour: int) -> void: _refresh())
	_refresh()


## Pone el botón "Personal" en la barra de menús.
func attach_button(menu_bar: Container) -> void:
	menu_bar.add_child(_open_button)


func set_open(open: bool) -> void:
	if open == is_open():
		return
	_panel.visible = open
	if open:
		_status_label.text = ""
		_refresh()
	staff_mode_changed.emit(open)


func is_open() -> bool:
	return _panel.visible


## Elige cargo y nivel en el formulario (como si se eligieran en las listas).
func select_role_and_level(role: String, level: String) -> void:
	_role_option.select(StaffCatalog.get_role_ids().find(role))
	_level_option.select(StaffCatalog.get_level_ids().find(level))
	_reset_salary()


func get_salary_offer() -> int:
	return _salary


func get_open_button() -> Button:
	return _open_button


func get_outlook_label() -> Label:
	return _outlook_label


func get_salary_buttons() -> Array[Button]:
	return [_salary_down, _salary_up]


func get_publicity_check() -> CheckBox:
	return _publicity_check


func get_publish_button() -> Button:
	return _publish_button


func get_status_text() -> String:
	return _status_label.text


## Botón "Cerrar vacante" de una vacante, o null.
func get_vacancy_close_button(vacancy_id: int) -> Button:
	return _vacancy_close_buttons.get(vacancy_id)


## Botón "Descartar" de un candidato, o null.
func get_discard_button(candidate_id: int) -> Button:
	return _discard_buttons.get(candidate_id)


## Botón "Entrevistar" de un candidato, o null.
func get_interview_button(candidate_id: int) -> Button:
	return _interview_buttons.get(candidate_id)


## Botón «Delegar» (entrevista el ejecutivo de Administración), o null si no hay.
func get_delegate_button(candidate_id: int) -> Button:
	return _delegate_buttons.get(candidate_id)


## Lista del departamento de un ejecutivo en el organigrama, o null.
func get_department_choice(executive_id: int) -> OptionButton:
	return _department_choices.get(executive_id)


## Botón "Ofrecer" de un candidato, o null.
func get_offer_button(candidate_id: int) -> Button:
	return _offer_buttons.get(candidate_id)


## Botones − y + de la oferta a un candidato (vacío si no está en la lista).
func get_offer_step_buttons(candidate_id: int) -> Array[Button]:
	var buttons: Array[Button] = []
	buttons.assign(_offer_step_buttons.get(candidate_id, []))
	return buttons


## Botón para aceptar la contraoferta de un candidato, o null si no hizo ninguna.
func get_counter_button(candidate_id: int) -> Button:
	return _counter_buttons.get(candidate_id)


## Botón "Ficha" de un empleado, o null.
func get_card_button(employee_id: int) -> Button:
	return _card_buttons.get(employee_id)


## Sueldo que se le ofrecería ahora a un candidato.
func get_offer(candidate_id: int) -> int:
	return _offers.get(candidate_id, 0)


## Todo el texto de la lista de empleados y vacantes (para las pruebas).
func get_list_text() -> String:
	var texts: Array[String] = []
	for label: Node in _list.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return "\n".join(texts)


func _add_section(parent: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	parent.add_child(label)


func _selected_role() -> String:
	return StaffCatalog.get_role_ids()[_role_option.selected]


func _selected_level() -> String:
	return StaffCatalog.get_level_ids()[_level_option.selected]


# Cargos que todavía no existen en esta etapa (el líder de equipo antes de Startup):
# en gris, con la etapa en la que llegan.
func _refresh_role_locks() -> void:
	var roles: Array[String] = StaffCatalog.get_role_ids()
	for index: int in range(roles.size()):
		var problem: String = Staff.role_problem(roles[index])
		_role_option.set_item_disabled(index, not problem.is_empty())
		_role_option.set_item_tooltip(index, problem)
		_role_option.set_item_text(index, StaffCatalog.get_role_name(roles[index]) +
			("" if problem.is_empty() else " (%s)" % Company.get_stage_name(StaffCatalog.get_role_min_stage(roles[index]))))
	if _role_option.is_item_disabled(_role_option.selected):
		_role_option.select(0)
		_reset_salary()


## Elige el cargo de la vacante (para las pruebas).
func get_role_option() -> OptionButton:
	return _role_option


## Lista de niveles de la vacante (deshabilitada para cargos sin niveles).
func get_level_option() -> OptionButton:
	return _level_option


# Al cambiar cargo o nivel, el sueldo vuelve al de la tabla. Un cargo sin niveles
# deshabilita la lista de niveles.
func _reset_salary() -> void:
	_level_option.disabled = not StaffCatalog.has_levels(_selected_role())
	_salary = StaffCatalog.get_salary(_selected_role(), _selected_level())
	_table_label.text = "(tabla: %s)" % MoneyFormat.format(_salary)
	_update_salary()


func _change_salary(direction: int) -> void:
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	_salary = maxi(step, _salary + direction * step)
	_update_salary()


func _update_salary() -> void:
	_salary_label.text = "%s al mes" % MoneyFormat.format(_salary)
	_salary_down.disabled = _salary <= int(StaffCatalog.get_hiring("salary_step"))
	_outlook_label.text = Staff.describe_hiring_outlook(_selected_role(), _selected_level(), _salary)


func _on_publish_pressed() -> void:
	var result: Dictionary = Staff.open_vacancy(_selected_role(), _selected_level(), _salary,
		_publicity_check.button_pressed)
	_status_label.text = result["message"]
	if result["ok"]:
		_publicity_check.button_pressed = false


func _refresh() -> void:
	var waiting: int = Staff.get_waiting_count()
	_open_button.text = "Personal (%d)" % waiting if waiting > 0 else "Personal"
	if _list == null or not is_open():
		return
	_refresh_role_locks()
	_update_salary()
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_vacancy_close_buttons.clear()
	_discard_buttons.clear()
	_interview_buttons.clear()
	_delegate_buttons.clear()
	_department_choices.clear()
	_offer_buttons.clear()
	_offer_step_buttons.clear()
	_counter_buttons.clear()
	_card_buttons.clear()
	_boss_choices.clear()
	_add_employees()
	_add_org_chart()
	_list.add_child(HSeparator.new())
	_add_section(_list, "Vacantes abiertas")
	if Staff.vacancies.is_empty():
		_list.add_child(_muted_label("No hay vacantes abiertas."))
	for vacancy: Dictionary in Staff.vacancies:
		_add_vacancy(vacancy)
	# Olvida las ofertas de los candidatos que ya no están.
	for candidate_id: int in _offers.keys():
		if not _offer_buttons.has(candidate_id):
			_offers.erase(candidate_id)


func _add_employees() -> void:
	var free: int = Staff.get_free_workstations().size()
	_add_section(_list, "Empleados (%d) · puestos libres: %d" % [Staff.employees.size(), free])
	if Staff.employees.is_empty():
		_list.add_child(_muted_label("Todavía no hay empleados. Para contratar hace falta un puesto de trabajo libre: escritorio con computadora y silla delante, dentro de un Área de trabajo que funcione."))
	for employee: Dictionary in Staff.employees:
		var lines: Array[String] = ["%s, %d años · %s" % [employee["name"], employee["age"], Staff.describe_employee(employee)],
			Staff.describe_skills(employee)]
		var known: String = Staff.describe_known_traits(employee)
		if not known.is_empty():
			lines.append(known)
		if int(employee["owed"]) > 0:
			lines.append("Se le deben %s de nómina." % MoneyFormat.format(employee["owed"]))
		if not Staff.has_working_station(employee):
			lines.append("Su puesto de trabajo ya no funciona.")
		var row := HBoxContainer.new()
		_list.add_child(row)
		var info := Label.new()
		info.text = "\n".join(lines)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var card_button := Button.new()
		card_button.text = "Ficha"
		card_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var employee_id: int = employee["id"]
		card_button.pressed.connect(func() -> void: employee_selected.emit(employee_id))
		row.add_child(card_button)
		_card_buttons[employee_id] = card_button


# Organigrama (hito 32): quién dirige a quién, solo si hay líderes o gerentes.
func _add_org_chart() -> void:
	var leaders: Array[Dictionary] = Staff.get_leaders()
	var managers: Array[Dictionary] = Staff.get_managers()
	var executives: Array[Dictionary] = Staff.get_executives()
	if leaders.is_empty() and managers.is_empty() and executives.is_empty() and not Staff.departments_apply():
		return
	_list.add_child(HSeparator.new())
	_add_section(_list, "Organigrama")
	_add_departments(executives)
	_list.add_child(_muted_label("CEO · dirige %d de %d líderes con equipo" % [Staff.get_ceo_leaders().size(), Staff.get_leader_cap(0)]))
	for manager: Dictionary in managers:
		var present: bool = Staff.is_expected_now(Staff.employee_key(manager["id"]))
		_list.add_child(_muted_label("Gerente %s · dirige %d de %d líderes (%s) · sus equipos rinden +%d %% mientras está presente" % [
			manager["name"], Staff.get_leaders_of(manager["id"]).size(), Staff.get_leader_cap(manager["id"]),
			"presente" if present else "fuera de turno",
			roundi(float(StaffCatalog.get_management("manager_bonus")) * 100.0)]))
	for leader: Dictionary in leaders:
		var row := HBoxContainer.new()
		_list.add_child(row)
		var team: Dictionary = Staff.get_team_of(leader["id"])
		var label := Label.new()
		label.text = "Líder %s · %s" % [leader["name"], team["name"] if not team.is_empty() else "sin equipo"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var choice := OptionButton.new()
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
			_status_label.text = Staff.set_manager(leader_id, choice.get_item_id(index))["message"]
			_refresh.call_deferred())
		row.add_child(choice)
		_boss_choices[leader_id] = choice


# Departamentos (hito 33): quién dirige cada uno y cuánto rinde; cada ejecutivo elige
# el suyo.
func _add_departments(executives: Array[Dictionary]) -> void:
	var departments: Array[String] = Staff.get_departments()
	for department: String in departments:
		var executive: Dictionary = Staff.get_executive_of(department)
		var factor: float = Staff.get_department_factor(department)
		var size: int = Staff.get_department_size(department)
		_list.add_child(_muted_label("%s · %d %s · lo dirige %s · rinde %d %%" % [StaffCatalog.get_department_name(department),
			size, "persona" if size == 1 else "personas", "el CEO" if executive.is_empty() else executive["name"],
			roundi(factor * 100.0)]))
	if departments.is_empty():
		_list.add_child(_muted_label("Todavía no hay departamentos: existen desde que tienen un empleado."))
	elif not Staff.departments_apply():
		_list.add_child(_muted_label("Desde %s el CEO rinde menos cuantos más departamentos dirige." % Company.get_stage_name(
			int(StaffCatalog.get_departments("from_stage")))))
	for executive: Dictionary in executives:
		var row := HBoxContainer.new()
		_list.add_child(row)
		var label := Label.new()
		label.text = "Ejecutivo %s" % executive["name"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var choice := OptionButton.new()
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
				_status_label.text = Staff.set_executive_department(executive_id, ids[index])["message"]
			_refresh.call_deferred())
		row.add_child(choice)
		_department_choices[executive_id] = choice


## Lista "A cargo de" de un líder en el organigrama, o null.
func get_boss_choice(leader_id: int) -> OptionButton:
	return _boss_choices.get(leader_id)


func _add_vacancy(vacancy: Dictionary) -> void:
	var header := HBoxContainer.new()
	_list.add_child(header)
	var title := Label.new()
	title.text = Staff.describe_vacancy(vacancy)
	var publicity_left: int = Staff.publicity_days_left(vacancy)
	if publicity_left > 0:
		title.text += " · publicidad %d %s" % [publicity_left, "día" if publicity_left == 1 else "días"]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Cerrar vacante"
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vacancy_id: int = vacancy["id"]
	close_button.pressed.connect(func() -> void: Staff.close_vacancy(vacancy_id))
	header.add_child(close_button)
	_vacancy_close_buttons[vacancy_id] = close_button

	var candidates: Array[Dictionary] = vacancy["candidates"]
	if candidates.is_empty():
		_list.add_child(_muted_label("Sin candidatos todavía. Llegan cada día a las %02d:00." % int(
			StaffCatalog.get_hiring("arrival_hour"))))
	for candidate: Dictionary in candidates:
		_add_candidate(candidate)
	_list.add_child(HSeparator.new())


func _add_candidate(candidate: Dictionary) -> void:
	var row := HBoxContainer.new()
	_list.add_child(row)
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var days_left: int = Staff.candidate_days_left(candidate)
	var leaving: String = "se va hoy" if days_left == 0 else ("se va mañana" if days_left == 1 else "se va en %d días" % days_left)
	var lines: Array[String] = ["%s, %d años · pide %s · %s" % [candidate["name"], candidate["age"],
		MoneyFormat.format(candidate["asked_salary"]), leaving], Staff.describe_skills(candidate)]
	var known: String = Staff.describe_known_traits(candidate)
	if not known.is_empty():
		lines.append(known)
	var candidate_id: int = candidate["id"]
	if Staff.get_interviewed_now().get("id", -1) == candidate_id:
		var by: String = String(Staff.interview.get("by", "ceo"))
		lines.append("En entrevista con %s hasta las %s." % ["el CEO" if by == "ceo" else Staff.get_employee_by_key(by).get("name", "?"),
			Staff.format_clock_minute(int(Staff.interview["ends_at"]))])
	var counter: int = int(candidate.get("counter_offer", 0))
	if counter > 0:
		lines.append("Contraoferta: aceptaría %s al mes." % MoneyFormat.format(counter))
	info.text = "\n".join(lines)
	row.add_child(info)

	var actions := HBoxContainer.new()
	_list.add_child(actions)
	var interview_button := Button.new()
	interview_button.text = "Entrevistar"
	var problem: String = Staff.interview_problem(candidate_id)
	interview_button.disabled = not problem.is_empty()
	interview_button.tooltip_text = problem if not problem.is_empty() else "Ocupa %d minutos del CEO y revela un rasgo y los valores reales." % int(StaffCatalog.get_hiring("interview_minutes"))
	interview_button.pressed.connect(func() -> void: _status_label.text = Staff.start_interview(candidate_id)["message"])
	actions.add_child(interview_button)
	_interview_buttons[candidate_id] = interview_button
	var interviewer: Dictionary = Staff.get_interviewer()
	if not interviewer.is_empty():
		var delegate := Button.new()
		delegate.text = "Delegar"
		var delegate_problem: String = Staff.interview_problem(candidate_id, true)
		delegate.disabled = not delegate_problem.is_empty()
		delegate.tooltip_text = delegate_problem if not delegate_problem.is_empty() else \
			"Entrevista %s (ejecutivo): %d minutos suyos, el CEO sigue trabajando." % [interviewer["name"], int(StaffCatalog.get_hiring("interview_minutes"))]
		delegate.pressed.connect(func() -> void: _status_label.text = Staff.start_interview(candidate_id, true)["message"])
		actions.add_child(delegate)
		_delegate_buttons[candidate_id] = delegate

	if not _offers.has(candidate_id):
		_offers[candidate_id] = int(Staff.get_vacancy(_vacancy_of(candidate_id))["salary"])
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	var down := Button.new()
	down.text = "−"
	down.tooltip_text = "Bajar la oferta"
	down.custom_minimum_size = Vector2(36, 0)
	down.disabled = _offers[candidate_id] <= step
	down.pressed.connect(func() -> void: _change_offer(candidate_id, -1))
	actions.add_child(down)
	var offer_label := Label.new()
	offer_label.text = MoneyFormat.format(_offers[candidate_id])
	offer_label.custom_minimum_size = Vector2(80, 0)
	offer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	actions.add_child(offer_label)
	var up := Button.new()
	up.text = "+"
	up.tooltip_text = "Subir la oferta"
	up.custom_minimum_size = Vector2(36, 0)
	up.pressed.connect(func() -> void: _change_offer(candidate_id, 1))
	actions.add_child(up)
	_offer_step_buttons[candidate_id] = [down, up]
	var offer_button := Button.new()
	offer_button.text = "Ofrecer"
	offer_button.pressed.connect(func() -> void: _status_label.text = Staff.make_offer(candidate_id, _offers[candidate_id])["message"])
	actions.add_child(offer_button)
	_offer_buttons[candidate_id] = offer_button
	if counter > 0:
		var counter_button := Button.new()
		counter_button.text = "Aceptar %s" % MoneyFormat.format(counter)
		counter_button.pressed.connect(func() -> void: _status_label.text = Staff.accept_counter_offer(candidate_id)["message"])
		actions.add_child(counter_button)
		_counter_buttons[candidate_id] = counter_button
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	var discard := Button.new()
	discard.text = "Descartar"
	discard.pressed.connect(func() -> void: Staff.discard_candidate(candidate_id))
	actions.add_child(discard)
	_discard_buttons[candidate_id] = discard


func _change_offer(candidate_id: int, direction: int) -> void:
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	_offers[candidate_id] = maxi(step, _offers[candidate_id] + direction * step)
	_refresh()


func _vacancy_of(candidate_id: int) -> int:
	for vacancy: Dictionary in Staff.vacancies:
		for candidate: Dictionary in vacancy["candidates"]:
			if candidate["id"] == candidate_id:
				return vacancy["id"]
	return 0


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label


## Botón «?» que abre la ayuda del panel.
func get_help_button() -> Button:
	return _help_button
