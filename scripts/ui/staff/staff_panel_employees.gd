# Personal, capa 2: pestaña Empleados (avisos, filtros, tarjetas por equipo y lugar para la ficha).
extends "res://scripts/ui/staff/staff_panel_base.gd"


# Columna izquierda con la lista y columna derecha donde se pone la ficha (EmployeeCard).
func _build_employees(view: HBoxContainer) -> void:
	_employees_list = VBoxContainer.new()
	_employees_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_employees_list.add_theme_constant_override("separation", 8)
	view.add_child(_employees_list)
	_employees_header = _section(_employees_list, "")
	_alerts_box = VBoxContainer.new()
	_alerts_box.add_theme_constant_override("separation", 6)
	_employees_list.add_child(_alerts_box)

	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 6)
	filters.add_theme_constant_override("v_separation", 6)
	_employees_list.add_child(filters)
	var group := ButtonGroup.new()
	_add_area_chip(filters, group, AREA_ALL, "Todos", UiTheme.MUTED)
	for area: String in AREAS:
		var roles: Array = AREAS[area][1]
		_add_area_chip(filters, group, area, AREAS[area][0], _role_color(String(roles[0])))
	_area_buttons[AREA_ALL].button_pressed = true

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	_employees_list.add_child(tools)
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar por nombre o cargo"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String) -> void: _refresh_employees())
	tools.add_child(_search)
	_sort_option = OptionButton.new()
	for sort_name: String in SORT_NAMES:
		_sort_option.add_item(sort_name)
	_sort_option.focus_mode = Control.FOCUS_NONE
	_sort_option.item_selected.connect(func(_index: int) -> void: _refresh_employees())
	tools.add_child(_sort_option)

	_groups_scroll = ScrollContainer.new()
	_groups_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_groups_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_employees_list.add_child(_groups_scroll)
	_groups_box = VBoxContainer.new()
	_groups_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_groups_box.add_theme_constant_override("separation", 10)
	_groups_scroll.add_child(_groups_box)
	_groups_scroll.resized.connect(_fit_card_columns)

	_ficha_column = _card_panel()
	_ficha_column.custom_minimum_size.x = EmployeeCard.PANEL_WIDTH
	view.add_child(_ficha_column)
	_ficha_hint = _muted_label("Haz clic en alguien para ver su ficha.")
	_ficha_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ficha_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ficha_column.add_child(_ficha_hint)


func _add_area_chip(parent: Container, group: ButtonGroup, area: String, text: String, color: Color) -> void:
	var chip: Button = _button(text, &"SpeedButton")
	chip.toggle_mode = true
	chip.button_group = group
	if area != AREA_ALL:
		chip.icon = _dot(color)
	chip.toggled.connect(func(on: bool) -> void:
		if on:
			_area = area
			_refresh_employees())
	parent.add_child(chip)
	_area_buttons[area] = chip


func _refresh_employees() -> void:
	if _groups_box == null:
		return
	var free: int = Staff.get_free_workstations().size()
	_employees_header.text = "Empleados (%d) · puestos libres: %d" % [Staff.employees.size(), free]
	_refresh_alerts()
	for child: Node in _groups_box.get_children():
		_groups_box.remove_child(child)
		child.queue_free()
	_card_buttons.clear()
	_card_grids.clear()
	if Staff.employees.is_empty():
		_groups_box.add_child(_muted_label("Todavía no hay empleados. Para contratar hace falta un puesto de trabajo libre: escritorio con computadora y silla delante, dentro de un Área de trabajo que funcione."))
		return
	var shown: Array[Dictionary] = _filtered_employees()
	if shown.is_empty():
		_groups_box.add_child(_muted_label("Nadie coincide con el filtro."))
		return
	_sort_employees(shown)
	if _sort_option.selected == SORT_TEAM:
		var groups: Dictionary[String, Array] = {}
		for employee: Dictionary in shown:
			var team: Dictionary = Staff.get_team_of(employee["id"])
			var title: String = String(team["name"]) if not team.is_empty() else "Sin equipo"
			if not groups.has(title):
				groups[title] = []
			groups[title].append(employee)
		for title: String in groups:
			_add_group(title, groups[title])
	else:
		_add_group("", shown)
	_fit_card_columns()


# Empleados que pasan el área y la búsqueda.
func _filtered_employees() -> Array[Dictionary]:
	var query: String = _search.text.strip_edges().to_lower()
	var shown: Array[Dictionary] = []
	for employee: Dictionary in Staff.employees:
		if _area != AREA_ALL and _area_of(employee["role"]) != _area:
			continue
		var haystack: String = "%s %s" % [employee["name"], StaffCatalog.describe_title(employee["role"], employee["level"])]
		if not query.is_empty() and not haystack.to_lower().contains(query):
			continue
		shown.append(employee)
	return shown


func _sort_employees(list: Array[Dictionary]) -> void:
	var roles: Array[String] = StaffCatalog.get_role_ids()
	match _sort_option.selected:
		SORT_ROLE:
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return roles.find(a["role"]) < roles.find(b["role"]))
		SORT_SALARY:
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["salary"]) > int(b["salary"]))
		SORT_MOOD:
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["mood"]) < int(b["mood"]))
		SORT_ENERGY:
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["energy"]) < int(b["energy"]))


func _add_group(title: String, members: Array) -> void:
	if not title.is_empty():
		var head := HBoxContainer.new()
		_groups_box.add_child(head)
		var label: Label = _strong(title)
		head.add_child(label)
		head.add_child(_caption("· %d %s" % [members.size(), "persona" if members.size() == 1 else "personas"]))
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_groups_box.add_child(grid)
	_card_grids.append(grid)
	for employee: Dictionary in members:
		grid.add_child(_make_employee_card(employee))


func _fit_card_columns() -> void:
	var columns: int = _columns_for(_groups_scroll.size.x - 12.0, CARD_MIN_WIDTH, 8.0)
	for grid: GridContainer in _card_grids:
		grid.columns = columns


# Avisos arriba de la lista: ofertas de otras empresas (con Igualar / Dejar ir) y cuántos andan mal.
func _refresh_alerts() -> void:
	for child: Node in _alerts_box.get_children():
		_alerts_box.remove_child(child)
		child.queue_free()
	var today: int = GameClock.get_day_count()
	var counts: Dictionary[String, int] = {}
	var promotable: int = 0
	for employee: Dictionary in Staff.employees:
		var offer: Dictionary = employee.get("outside_offer", {})
		if not offer.is_empty():
			_add_offer_alert(employee, int(offer["salary"]), int(offer["until_day"]) - today)
		var icon: String = Staff.get_status_icon(employee)
		if not icon.is_empty():
			counts[icon] = counts.get(icon, 0) + 1
		var progress: Dictionary = Staff.get_promotion_progress(employee)
		if bool(progress["ready"]) and not (String(progress["next_level"]).is_empty() and String(progress["next_role"]).is_empty()):
			promotable += 1
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	for icon: String in counts:
		chips.add_child(_alert_chip("%d %s" % [counts[icon], STATUS_PLURALS.get(icon, icon)], UiTheme.ACCENT))
	if promotable > 0:
		chips.add_child(_alert_chip("%d puede%s ascender" % [promotable, "" if promotable == 1 else "n"], UiTheme.POSITIVE))
	if chips.get_child_count() > 0:
		_alerts_box.add_child(chips)
	else:
		chips.free()


func _add_offer_alert(employee: Dictionary, salary: int, days_left: int) -> void:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.ALERT_BG
	style.border_color = UiTheme.NEGATIVE
	style.set_border_width_all(0)
	style.border_width_left = 4
	style.set_content_margin_all(8)
	box.add_theme_stylebox_override("panel", style)
	_alerts_box.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(_photo(employee, 32.0))
	var text: Label = _muted_label("%s tiene una oferta de otra empresa: %s al mes · %s" % [employee["name"],
		MoneyFormat.format(salary), "se va hoy" if days_left <= 0 else ("se va mañana" if days_left == 1 else "se va en %d días" % days_left)])
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_color_override("font_color", UiTheme.TEXT)
	row.add_child(text)
	var employee_id: int = employee["id"]
	var match_button: Button = _button("Igualar", &"PrimaryButton")
	match_button.tooltip_text = "Le sube el sueldo a %s para que se quede." % MoneyFormat.format(salary)
	match_button.pressed.connect(func() -> void: _set_status(Staff.match_offer(employee_id)["message"]))
	row.add_child(match_button)
	var go_button: Button = _button("Dejar ir", &"DangerButton")
	go_button.tooltip_text = "Se va hoy; cobra lo ganado y lo debido."
	go_button.pressed.connect(func() -> void: _set_status(Staff.let_go(employee_id)["message"]))
	row.add_child(go_button)


func _alert_chip(text: String, color: Color) -> Label:
	var chip: Label = _caption(text)
	chip.add_theme_color_override("font_color", color)
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.CARD
	style.border_color = color.darkened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("normal", style)
	return chip


# Tarjeta de un empleado: foto, nombre, cargo, barras de ánimo, energía y estrés y, si algo anda mal, su globo.
func _make_employee_card(employee: Dictionary) -> Button:
	var employee_id: int = employee["id"]
	var card := Button.new()
	card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.theme_type_variation = &"CardButton"
	card.focus_mode = Control.FOCUS_NONE
	card.toggle_mode = true
	card.button_pressed = employee_id == _selected_id
	card.pressed.connect(func() -> void: employee_selected.emit(employee_id))
	_card_buttons[employee_id] = card
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(_photo(employee, CARD_PHOTO))
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var name_label: Label = _strong(employee["name"])
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(name_label)
	var role_label: Label = _caption(StaffCatalog.describe_title(employee["role"], employee["level"]))
	role_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(role_label)
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 4)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(bars)
	var values: Array[String] = []
	for key: String in ["mood", "energy", "stress"]:
		bars.add_child(Bar.new(float(employee[key]), EmployeeCard.BAR_COLORS[key], 5.0))
		values.append("%s %d" % [EmployeeCard.BARS[key], int(employee[key])])

	var problems: Array[String] = []
	if int(employee["owed"]) > 0:
		problems.append("Se le deben %s de nómina." % MoneyFormat.format(employee["owed"]))
	if not Staff.has_working_station(employee):
		problems.append("Su puesto de trabajo ya no funciona.")
	var icon: String = Staff.get_status_icon(employee)
	if not icon.is_empty():
		problems.push_front(STATUS_NAMES.get(icon, ""))
		var sprite: String = SpriteLibrary.get_status_icon_sprite(icon)
		if not sprite.is_empty():
			var globe := TextureRect.new()
			globe.texture = SpriteLibrary.get_texture(sprite)
			globe.custom_minimum_size = CARD_ICON
			globe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			globe.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			globe.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			globe.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			globe.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(globe)
	var tip: Array[String] = ["Abrir la ficha de %s" % employee["name"], " · ".join(values)]
	if not problems.is_empty():
		tip.append(" · ".join(problems))
	card.tooltip_text = "\n".join(tip)
	return card


## Marca la tarjeta del empleado cuya ficha está abierta (0 = ninguna).
func set_selected_employee(employee_id: int) -> void:
	_selected_id = employee_id
	_ficha_hint.visible = employee_id == 0
	for id: int in _card_buttons:
		_card_buttons[id].set_pressed_no_signal(id == employee_id)
