# Menú Personal (ancho, entre el dinero y la barra de menús; no pausa), en pestañas: Empleados (avisos, filtros y
# tarjetas por equipo; la ficha se abre en la columna derecha), Vacantes (formulario y candidatos en tarjetas) y,
# con líderes, gerentes o departamentos, Organigrama. Capas en scripts/ui/staff/.
class_name StaffPanel
extends "res://scripts/ui/staff/staff_panel_org.gd"



func _ready() -> void:
	_open_button = Button.new()
	Hud.style_bar_button(_open_button, "staff")
	_open_button.pressed.connect(func() -> void: set_open(not is_open()))

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	root.add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit()
	EventBus.ui_layout_changed.connect(_fit)
	# Con la interfaz grande o una pantalla chica el contenido puede no caber: se desplaza entero.
	var scroll := ScrollContainer.new()
	_panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	rows.add_child(_build_header())
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	_status_label.visible = false
	rows.add_child(_status_label)

	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_body)
	for tab: int in range(TAB_NAMES.size()):
		var view := HBoxContainer.new()
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		view.add_theme_constant_override("separation", 12)
		_body.add_child(view)
		_views.append(view)
	_build_employees(_views[TAB_EMPLOYEES] as HBoxContainer)
	_build_hiring(_views[TAB_HIRING] as HBoxContainer)
	_build_org(_views[TAB_ORG] as HBoxContainer)
	_ficha_column.custom_minimum_size.x = EmployeeCard.PANEL_WIDTH - _panel.get_theme_stylebox("panel").get_margin(SIDE_RIGHT)

	_reset_salary()
	_panel.visible = false
	show_tab(TAB_EMPLOYEES)
	EventBus.staff_changed.connect(_refresh)
	EventBus.office_changed.connect(_refresh)
	EventBus.hour_changed.connect(func(_hour: int) -> void: _refresh())
	_refresh()


# Título, pestañas, resumen (nómina, puestos libres, ánimo medio), ayuda y Volver al mapa.
func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Personal"
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	header.add_child(title)
	var group := ButtonGroup.new()
	for tab: int in range(TAB_NAMES.size()):
		var button: Button = _button(TAB_NAMES[tab])
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(func() -> void: show_tab(tab))
		header.add_child(button)
		_tab_buttons.append(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_payroll_label = _summary(header, "Nómina", "Lo que suman los sueldos de todos al mes.")
	_free_label = _summary(header, "Puestos libres", "Puestos de trabajo que funcionan y nadie usa.")
	_mood_label = _summary(header, "Ánimo medio", "Promedio del ánimo de los empleados (0–100).")
	_help_button = HelpButton.create("staff")
	header.add_child(_help_button)
	_close_button = _button("Volver al mapa")
	_close_button.pressed.connect(func() -> void: set_open(false))
	header.add_child(_close_button)
	return header


# Dato del resumen: título chico arriba, valor abajo.
func _summary(parent: Container, title: String, tooltip: String) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.tooltip_text = tooltip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(box)
	box.add_child(_caption(title))
	var value: Label = _strong("")
	box.add_child(value)
	return value


# Ocupa la pantalla entre el dinero (o la tarjeta del tutorial) y la barra de menús.
func _fit() -> void:
	var avoid: Rect2 = avoid_provider.call()
	_panel.offset_left = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_top = maxf(UiLayout.top_space, avoid.end.y + UiLayout.BAR_GAP) if avoid.has_area() else UiLayout.top_space
	_panel.offset_bottom = -UiLayout.bottom_space


func _process(_delta: float) -> void:
	if not is_open():
		return
	_fit()
	var top: float = get_body_top()
	if not is_equal_approx(top, _body_top):
		_body_top = top
		body_moved.emit()
	if _current_tab == TAB_ORG and _org_tree != null:
		_org_tree.queue_redraw()


## Pone el botón "Personal" en la barra de menús.
func attach_button(menu_bar: Container) -> void:
	menu_bar.add_child(_open_button)


func set_open(open: bool) -> void:
	if open == is_open():
		return
	_panel.visible = open
	if open:
		_set_status("")
		# Sin empleados lo primero es contratar.
		show_tab(TAB_HIRING if Staff.employees.is_empty() else TAB_EMPLOYEES)
		_refresh()
	staff_mode_changed.emit(open)


func is_open() -> bool:
	return _panel.visible


## Elige cargo y nivel en el formulario como si se eligieran en las listas.
func select_role_and_level(role: String, level: String) -> void:
	_role_option.select(StaffCatalog.get_role_ids().find(role))
	_level_option.select(StaffCatalog.get_level_ids().find(level))
	_reset_salary()


func _refresh() -> void:
	var waiting: int = Staff.get_waiting_count()
	_open_button.text = "Personal (%d)" % waiting if waiting > 0 else "Personal"
	if _body == null or not is_open():
		return
	_refresh_summary()
	_refresh_role_locks()
	_update_salary()
	_refresh_employees()
	_refresh_vacancies()
	_refresh_org()
	_tab_buttons[TAB_EMPLOYEES].text = "Empleados (%d)" % Staff.employees.size()
	_tab_buttons[TAB_HIRING].text = "Vacantes (%d)" % Staff.vacancies.size()
	_tab_buttons[TAB_ORG].visible = _has_org_chart()
	if not _tab_buttons[_current_tab].visible:
		show_tab(TAB_EMPLOYEES)


func _refresh_summary() -> void:
	var payroll: int = 0
	var mood: int = 0
	for employee: Dictionary in Staff.employees:
		payroll += int(employee["salary"])
		mood += int(employee["mood"])
	_payroll_label.text = "%s/mes" % MoneyFormat.format(payroll)
	_free_label.text = str(Staff.get_free_workstations().size())
	if Staff.employees.is_empty():
		_mood_label.text = "—"
		_mood_label.remove_theme_color_override("font_color")
	else:
		var average: int = roundi(float(mood) / Staff.employees.size())
		_mood_label.text = "%d / 100" % average
		_mood_label.add_theme_color_override("font_color", UiTheme.POSITIVE if average >= 60 else (
			UiTheme.ACCENT if average >= 40 else UiTheme.NEGATIVE))


## Muestra una pestaña (TAB_EMPLOYEES, TAB_HIRING o TAB_ORG).
func show_tab(tab: int) -> void:
	_current_tab = tab
	for index: int in range(_views.size()):
		_views[index].visible = index == tab
		_tab_buttons[index].set_pressed_no_signal(index == tab)
	tab_shown.emit(tab)


func get_current_tab() -> int:
	return _current_tab


## Alto (en pantalla) donde empieza el contenido de las pestañas: ahí va la ficha.
func get_body_top() -> float:
	return _body.get_global_rect().position.y


## Rectángulo de la cabecera del panel (el tutorial se pone debajo).
func get_header_rect() -> Rect2:
	var rect: Rect2 = _panel.get_global_rect()
	return Rect2(rect.position, Vector2(rect.size.x, get_body_top() - rect.position.y))


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


## Elige el cargo de la vacante (para las pruebas; a la vista están los chips).
func get_role_option() -> OptionButton:
	return _role_option


## Lista de niveles de la vacante (deshabilitada para cargos sin niveles).
func get_level_option() -> OptionButton:
	return _level_option


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


## Sueldo que se le ofrecería ahora a un candidato.
func get_offer(candidate_id: int) -> int:
	return _offers.get(candidate_id, 0)


## Tarjeta de un empleado (abre su ficha), o null.
func get_card_button(employee_id: int) -> Button:
	return _card_buttons.get(employee_id)


## Lista del departamento de un ejecutivo en el organigrama, o null.
func get_department_choice(executive_id: int) -> OptionButton:
	return _department_choices.get(executive_id)


## Lista "A cargo de" de un líder en el organigrama, o null.
func get_boss_choice(leader_id: int) -> OptionButton:
	return _boss_choices.get(leader_id)


## Todo el texto de empleados, vacantes y organigrama (para las pruebas).
func get_list_text() -> String:
	var texts: Array[String] = []
	for list: Control in [_employees_list, _vacancy_list, _org_list]:
		for label: Node in list.find_children("*", "Label", true, false):
			texts.append((label as Label).text)
	return "\n".join(texts)


## Rectángulo de lo que hay que pulsar para publicar: el botón, o la pestaña Vacantes si no se ve.
func get_publish_target_rect() -> Rect2:
	if _publish_button.is_visible_in_tree():
		return _publish_button.get_global_rect()
	if _tab_buttons[TAB_HIRING].is_visible_in_tree():
		return _tab_buttons[TAB_HIRING].get_global_rect()
	return Rect2()


## Botón «?» que abre la ayuda del panel.
func get_help_button() -> Button:
	return _help_button
