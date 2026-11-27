# Personal, capa 3: pestaña Vacantes (formulario a la izquierda; vacantes con tarjetas de candidatos a la derecha).
extends "res://scripts/ui/staff/staff_panel_employees.gd"


func _build_hiring(view: HBoxContainer) -> void:
	var form_scroll := ScrollContainer.new()
	form_scroll.custom_minimum_size.x = FORM_WIDTH
	form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.add_child(form_scroll)
	var form_panel: PanelContainer = _card_panel()
	form_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll.add_child(form_panel)
	_hire_form = VBoxContainer.new()
	_hire_form.add_theme_constant_override("separation", 8)
	form_panel.add_child(_hire_form)
	var rows: VBoxContainer = _hire_form
	_section(rows, "Nueva vacante")

	# Las listas son el modelo (las pruebas las usan); a la vista hay chips y botones que las reflejan.
	_role_option = OptionButton.new()
	for role: String in StaffCatalog.get_role_ids():
		_role_option.add_item(StaffCatalog.get_role_name(role))
	_role_option.item_selected.connect(func(_index: int) -> void: _reset_salary())
	_role_option.visible = false
	rows.add_child(_role_option)
	_level_option = OptionButton.new()
	for level: String in StaffCatalog.get_level_ids():
		_level_option.add_item(StaffCatalog.get_level_name(level))
	_level_option.select(1)
	_level_option.item_selected.connect(func(_index: int) -> void: _reset_salary())
	_level_option.visible = false
	rows.add_child(_level_option)

	rows.add_child(_caption("Cargo"))
	var roles := HFlowContainer.new()
	roles.add_theme_constant_override("h_separation", 6)
	roles.add_theme_constant_override("v_separation", 6)
	rows.add_child(roles)
	var role_ids: Array[String] = StaffCatalog.get_role_ids()
	for index: int in range(role_ids.size()):
		var chip: Button = _button(StaffCatalog.get_role_name(role_ids[index]), &"SpeedButton")
		chip.toggle_mode = true
		chip.icon = _dot(_role_color(role_ids[index]))
		chip.pressed.connect(func() -> void:
			_role_option.select(index)
			_reset_salary())
		roles.add_child(chip)
		_role_buttons.append(chip)

	rows.add_child(_caption("Nivel"))
	var levels := HBoxContainer.new()
	levels.add_theme_constant_override("separation", 4)
	rows.add_child(levels)
	var level_ids: Array[String] = StaffCatalog.get_level_ids()
	for index: int in range(level_ids.size()):
		var segment: Button = _button(StaffCatalog.get_level_name(level_ids[index]), &"SpeedButton")
		segment.toggle_mode = true
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.pressed.connect(func() -> void:
			_level_option.select(index)
			_reset_salary())
		levels.add_child(segment)
		_level_buttons.append(segment)

	rows.add_child(_caption("Sueldo ofrecido"))
	var salary_row := HBoxContainer.new()
	salary_row.add_theme_constant_override("separation", 6)
	rows.add_child(salary_row)
	_salary_down = _step_button("−", "Bajar el sueldo ofrecido")
	_salary_down.pressed.connect(func() -> void: _change_salary(-1))
	salary_row.add_child(_salary_down)
	_salary_label = Label.new()
	_salary_label.theme_type_variation = &"StrongLabel"
	_salary_label.custom_minimum_size = Vector2(140, 0)
	_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	salary_row.add_child(_salary_label)
	_salary_up = _step_button("+", "Subir el sueldo ofrecido")
	_salary_up.pressed.connect(func() -> void: _change_salary(1))
	salary_row.add_child(_salary_up)
	_table_label = _caption("")
	salary_row.add_child(_table_label)

	var outlook_box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.HEADER
	style.border_color = UiTheme.INFO
	style.border_width_left = 3
	style.set_content_margin_all(8)
	outlook_box.add_theme_stylebox_override("panel", style)
	rows.add_child(outlook_box)
	var outlook_rows := VBoxContainer.new()
	outlook_box.add_child(outlook_rows)
	var outlook_title: Label = _caption("Pronóstico")
	outlook_title.add_theme_color_override("font_color", UiTheme.INFO)
	outlook_rows.add_child(outlook_title)
	_outlook_label = _muted_label("")
	outlook_rows.add_child(_outlook_label)

	_publicity_check = CheckBox.new()
	_publicity_check.text = "Con publicidad: %s, más candidatos durante %d días" % [
		MoneyFormat.format(int(StaffCatalog.get_hiring("publicity_cost"))), int(StaffCatalog.get_hiring("publicity_days"))]
	_publicity_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_publicity_check.focus_mode = Control.FOCUS_NONE
	rows.add_child(_publicity_check)
	_publish_button = _button("Publicar vacante", &"PrimaryButton")
	_publish_button.pressed.connect(_on_publish_pressed)
	rows.add_child(_publish_button)

	_vacancy_scroll = ScrollContainer.new()
	_vacancy_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vacancy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.add_child(_vacancy_scroll)
	_vacancy_list = VBoxContainer.new()
	_vacancy_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vacancy_list.add_theme_constant_override("separation", 10)
	_vacancy_scroll.add_child(_vacancy_list)
	_vacancy_scroll.resized.connect(_fit_candidate_columns)
	_refresh_role_locks()


func _selected_role() -> String:
	return StaffCatalog.get_role_ids()[_role_option.selected]


func _selected_level() -> String:
	return StaffCatalog.get_level_ids()[_level_option.selected]


# Cargos que aún no existen en esta etapa: en gris, con la etapa en la que llegan.
func _refresh_role_locks() -> void:
	var roles: Array[String] = StaffCatalog.get_role_ids()
	for index: int in range(roles.size()):
		var problem: String = Staff.role_problem(roles[index])
		var suffix: String = "" if problem.is_empty() else " (%s)" % Company.get_stage_name(StaffCatalog.get_role_min_stage(roles[index]))
		_role_option.set_item_disabled(index, not problem.is_empty())
		_role_option.set_item_tooltip(index, problem)
		_role_option.set_item_text(index, StaffCatalog.get_role_name(roles[index]) + suffix)
		_role_buttons[index].disabled = not problem.is_empty()
		_role_buttons[index].tooltip_text = problem
		_role_buttons[index].text = StaffCatalog.get_role_name(roles[index]) + suffix
	if _role_option.is_item_disabled(_role_option.selected):
		_role_option.select(0)
		_reset_salary()
	_sync_form_buttons()


# Los chips de cargo y los botones de nivel muestran lo elegido en las listas.
func _sync_form_buttons() -> void:
	for index: int in range(_role_buttons.size()):
		_role_buttons[index].set_pressed_no_signal(index == _role_option.selected)
	for index: int in range(_level_buttons.size()):
		_level_buttons[index].set_pressed_no_signal(index == _level_option.selected)
		_level_buttons[index].disabled = _level_option.disabled
	if _level_option.disabled:
		for button: Button in _level_buttons:
			button.tooltip_text = "Este cargo no tiene niveles."
	else:
		for button: Button in _level_buttons:
			button.tooltip_text = ""


# Al cambiar cargo o nivel el sueldo vuelve al de la tabla; un cargo sin niveles deshabilita la lista.
func _reset_salary() -> void:
	_level_option.disabled = not StaffCatalog.has_levels(_selected_role())
	_salary = StaffCatalog.get_salary(_selected_role(), _selected_level())
	_table_label.text = "tabla: %s" % MoneyFormat.format(_salary)
	_update_salary()
	_sync_form_buttons()


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
	_set_status(result["message"])
	if result["ok"]:
		_publicity_check.button_pressed = false


func _refresh_vacancies() -> void:
	for child: Node in _vacancy_list.get_children():
		_vacancy_list.remove_child(child)
		child.queue_free()
	_candidate_grids.clear()
	_vacancy_close_buttons.clear()
	_discard_buttons.clear()
	_interview_buttons.clear()
	_delegate_buttons.clear()
	_offer_buttons.clear()
	_offer_step_buttons.clear()
	_counter_buttons.clear()
	_section(_vacancy_list, "Vacantes abiertas (%d) · %d %s" % [Staff.vacancies.size(), Staff.get_waiting_count(),
		"candidato" if Staff.get_waiting_count() == 1 else "candidatos"])
	if Staff.vacancies.is_empty():
		_vacancy_list.add_child(_muted_label("No hay vacantes abiertas. Publica una con el formulario: los candidatos llegan cada día a las %02d:00." % int(
			StaffCatalog.get_hiring("arrival_hour"))))
	for vacancy: Dictionary in Staff.vacancies:
		_add_vacancy(vacancy)
	# Olvida las ofertas de los candidatos que ya no están.
	for candidate_id: int in _offers.keys():
		if not _offer_buttons.has(candidate_id):
			_offers.erase(candidate_id)
	_fit_candidate_columns()


func _fit_candidate_columns() -> void:
	var columns: int = _columns_for(_vacancy_scroll.size.x - 40.0, CANDIDATE_MIN_WIDTH, 8.0)
	for grid: GridContainer in _candidate_grids:
		grid.columns = columns


func _add_vacancy(vacancy: Dictionary) -> void:
	var card: PanelContainer = _card_panel()
	_vacancy_list.add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	card.add_child(rows)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	rows.add_child(header)
	var dot := TextureRect.new()
	dot.texture = _dot(_role_color(vacancy["role"]))
	dot.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	header.add_child(dot)
	var title: Label = Label.new()
	title.theme_type_variation = &"StrongLabel"
	title.text = Staff.describe_vacancy(vacancy)
	var publicity_left: int = Staff.publicity_days_left(vacancy)
	if publicity_left > 0:
		title.text += " · publicidad %d %s" % [publicity_left, "día" if publicity_left == 1 else "días"]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title)
	var close_button: Button = _button("Cerrar vacante")
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vacancy_id: int = vacancy["id"]
	close_button.pressed.connect(func() -> void: Staff.close_vacancy(vacancy_id))
	header.add_child(close_button)
	_vacancy_close_buttons[vacancy_id] = close_button

	var candidates: Array[Dictionary] = vacancy["candidates"]
	if candidates.is_empty():
		rows.add_child(_muted_label("Sin candidatos todavía. Llegan cada día a las %02d:00." % int(
			StaffCatalog.get_hiring("arrival_hour"))))
		return
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	rows.add_child(grid)
	_candidate_grids.append(grid)
	for candidate: Dictionary in candidates:
		grid.add_child(_make_candidate_card(candidate, int(vacancy["salary"])))


# Tarjeta de candidato: foto, edad, lo que pide y cuándo se va; habilidades (rango hasta entrevistarlo),
# rasgos conocidos, la cita, la oferta y los botones.
func _make_candidate_card(candidate: Dictionary, vacancy_salary: int) -> PanelContainer:
	var candidate_id: int = candidate["id"]
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.HEADER
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.x = CANDIDATE_MIN_WIDTH
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	card.add_child(rows)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	rows.add_child(top)
	top.add_child(_candidate_photo(candidate, CANDIDATE_PHOTO))
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 0)
	top.add_child(who)
	var name_label: Label = _strong(candidate["name"])
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_child(name_label)
	who.add_child(_caption("%d años · pide %s" % [candidate["age"], MoneyFormat.format(candidate["asked_salary"])]))
	var days_left: int = Staff.candidate_days_left(candidate)
	var leaving: String = "se va hoy" if days_left == 0 else ("se va mañana" if days_left == 1 else "se va en %d días" % days_left)
	var appointment: Dictionary = Staff.get_appointment(candidate_id)
	if not appointment.is_empty():
		leaving = "espera su entrevista"
	var expiry: Label = _alert_chip(leaving, UiTheme.INFO if not appointment.is_empty() else (
		UiTheme.NEGATIVE if days_left <= 1 else UiTheme.MUTED))
	expiry.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(expiry)

	_add_skill_bars(rows, candidate)
	var known: String = Staff.describe_known_traits(candidate)
	if not known.is_empty():
		var traits: Label = _caption(known)
		traits.add_theme_color_override("font_color", UiTheme.ACCENT)
		traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(traits)
	var note: String = _describe_interview(candidate_id, appointment)
	if not note.is_empty():
		var label: Label = _muted_label(note)
		label.add_theme_color_override("font_color", UiTheme.INFO)
		rows.add_child(label)
	var counter: int = int(candidate.get("counter_offer", 0))
	if counter > 0:
		rows.add_child(_muted_label("Contraoferta: aceptaría %s al mes." % MoneyFormat.format(counter)))

	if not _offers.has(candidate_id):
		_offers[candidate_id] = vacancy_salary
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	var offer_row := HBoxContainer.new()
	offer_row.add_theme_constant_override("separation", 6)
	rows.add_child(offer_row)
	offer_row.add_child(_caption("Oferta"))
	var down: Button = _step_button("−", "Bajar la oferta")
	down.disabled = _offers[candidate_id] <= step
	down.pressed.connect(func() -> void: _change_offer(candidate_id, -1))
	offer_row.add_child(down)
	var offer_label: Label = _strong(MoneyFormat.format(_offers[candidate_id]))
	offer_label.custom_minimum_size = Vector2(80, 0)
	offer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	offer_row.add_child(offer_label)
	var up: Button = _step_button("+", "Subir la oferta")
	up.pressed.connect(func() -> void: _change_offer(candidate_id, 1))
	offer_row.add_child(up)
	_offer_step_buttons[candidate_id] = [down, up]
	var hint: Label = _caption(_offer_hint(_offers[candidate_id], int(candidate["asked_salary"])))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	offer_row.add_child(hint)

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	rows.add_child(actions)
	var interview_button: Button = _button("Entrevistar")
	var problem: String = Staff.appointment_problem(candidate_id)
	interview_button.disabled = not problem.is_empty()
	interview_button.tooltip_text = problem if not problem.is_empty() else "Lo cita para el próximo día del CEO: ocupa %d minutos suyos y revela un rasgo y los valores reales." % int(StaffCatalog.get_hiring("interview_minutes"))
	interview_button.pressed.connect(func() -> void: _set_status(Staff.schedule_interview(candidate_id)["message"]))
	actions.add_child(interview_button)
	_interview_buttons[candidate_id] = interview_button
	var interviewer: Dictionary = Staff.get_interviewer()
	if not interviewer.is_empty():
		var delegate: Button = _button("Delegar")
		var delegate_problem: String = Staff.appointment_problem(candidate_id, true)
		delegate.disabled = not delegate_problem.is_empty()
		delegate.tooltip_text = delegate_problem if not delegate_problem.is_empty() else \
			"Lo cita con %s (ejecutivo) en su próxima jornada: %d minutos suyos, el CEO sigue trabajando." % [interviewer["name"], int(StaffCatalog.get_hiring("interview_minutes"))]
		delegate.pressed.connect(func() -> void: _set_status(Staff.schedule_interview(candidate_id, true)["message"]))
		actions.add_child(delegate)
		_delegate_buttons[candidate_id] = delegate
	var offer_button: Button = _button("Ofrecer", &"PrimaryButton")
	offer_button.pressed.connect(func() -> void: _set_status(Staff.make_offer(candidate_id, _offers[candidate_id])["message"]))
	actions.add_child(offer_button)
	_offer_buttons[candidate_id] = offer_button
	if counter > 0:
		var counter_button: Button = _button("Aceptar %s" % MoneyFormat.format(counter), &"PrimaryButton")
		counter_button.pressed.connect(func() -> void: _set_status(Staff.accept_counter_offer(candidate_id)["message"]))
		actions.add_child(counter_button)
		_counter_buttons[candidate_id] = counter_button
	var discard: Button = _button("Descartar", &"DangerButton")
	discard.pressed.connect(func() -> void: Staff.discard_candidate(candidate_id))
	actions.add_child(discard)
	_discard_buttons[candidate_id] = discard
	return card


# Una fila por habilidad: rango sin entrevistar, valor exacto después.
func _add_skill_bars(parent: Container, candidate: Dictionary) -> void:
	var interviewed: bool = bool(candidate.get("interviewed", false))
	var width: int = StaffCatalog.get_skill_range_width()
	var main_skill: String = StaffCatalog.get_main_skill(candidate["role"])
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)
	for skill: String in StaffCatalog.get_skill_ids():
		var name_label: Label = _caption(StaffCatalog.get_skill_name(skill))
		name_label.custom_minimum_size.x = EmployeeCard.SKILL_NAME_WIDTH
		if skill == main_skill:
			name_label.add_theme_color_override("font_color", UiTheme.TEXT)
		grid.add_child(name_label)
		var color: Color = _role_color(candidate["role"]) if skill == main_skill else UiTheme.FAINT
		var value_text: String
		if interviewed:
			var value: int = int(candidate["skills"][skill])
			grid.add_child(Bar.new(value, color, 6.0))
			value_text = str(value)
		else:
			var low: int = int(candidate["skill_low"][skill])
			grid.add_child(Bar.new(low + width, color, 6.0, low))
			value_text = "%d–%d" % [low, low + width]
		var value_label: Label = _caption(value_text)
		value_label.custom_minimum_size.x = 52
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value_label)


func _describe_interview(candidate_id: int, appointment: Dictionary) -> String:
	var now: Dictionary = Staff.get_interviewed_now()
	if now.get("id", -1) == candidate_id:
		var by: String = String(Staff.interview.get("by", "ceo"))
		var who: String = "el CEO" if by == "ceo" else Staff.get_employee_by_key(by).get("name", "?")
		if not Staff.is_interview_started():
			return "Entrando a la entrevista con %s." % who
		return "En entrevista con %s hasta las %s." % [who, Staff.format_clock_minute(int(Staff.interview["ends_at"]))]
	if not appointment.is_empty():
		var by_key: String = String(appointment["by"])
		return "Entrevista citada %s con %s." % [Staff.describe_appointment_time(int(appointment["at"])),
			"el CEO" if by_key == "ceo" else Staff.get_employee_by_key(by_key).get("name", "?")]
	return ""


# Qué pasaría con esa oferta: la acepta, contraoferta o se va.
func _offer_hint(offer: int, asked: int) -> String:
	if offer >= asked:
		return "La acepta." if offer == asked else "Más de lo que pide: la acepta."
	if offer >= asked * float(StaffCatalog.get_hiring("counter_offer_ratio")):
		return "Menos de lo que pide: hará una contraoferta."
	return "Muy baja: la rechaza y se va."


func _change_offer(candidate_id: int, direction: int) -> void:
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	_offers[candidate_id] = maxi(step, _offers[candidate_id] + direction * step)
	_refresh_vacancies()
