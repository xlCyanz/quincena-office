# Ficha de empleado (derecha, bajo el reloj; no pausa y se actualiza sola): cabecera con su foto, nivel, qué
# hace (status_provider) y rasgos; estado y habilidades, historial, datos, avisos y las filas Aumento, Ascender,
# Horario propio y Despedir. Si no entra en pantalla, todo se desplaza.
class_name EmployeeCard
extends CanvasLayer

const PANEL_WIDTH: float = 460.0
const MARGIN: float = 16.0
const MARGIN_TOP: float = 140.0
## Espacio que se deja abajo para la barra de botones.
const TITLE_FONT_SIZE: int = 22
const MUTED_COLOR := UiTheme.MUTED
const ALERT_COLOR := Color("f2c14e")
## Barras de la ficha: clave en el empleado y nombre para el jugador.
const BARS: Dictionary[String, String] = {"energy": "Energía", "mood": "Ánimo", "stress": "Estrés"}
const BAR_COLORS: Dictionary[String, Color] = {
	"energy": UiTheme.POSITIVE, "mood": UiTheme.INFO, "stress": UiTheme.NEGATIVE,
}
## Foto de la cabecera, alto de las barras y columnas de nombres de barras y habilidades.
const PHOTO_SIZE: float = 96.0
const METER_HEIGHT: float = 8.0
const BAR_NAME_WIDTH: float = 62.0
const SKILL_NAME_WIDTH: float = 96.0
const VALUE_WIDTH: float = 28.0
const SKILL_COLOR := UiTheme.FAINT
## Casillas del historial: clave (ver _history_values) y nombre.
const HISTORY: Dictionary[String, String] = {
	"projects": "Contratos", "bugs": "Errores", "late": "Tardanzas", "absent": "Ausencias", "punctuality": "Puntual",
}
## Datos de la ficha en dos columnas: clave y título.
const FACTS: Dictionary[String, String] = {"team": "EQUIPO", "schedule": "HORARIO", "salary": "SUELDO", "days": "EN LA EMPRESA"}

## Cambió el empleado de la ficha (0 al cerrarla).
signal employee_changed(employee_id: int)

## Devuelve qué está haciendo un empleado ("Trabajando", …) a partir de su id.
var status_provider: Callable = Callable()

var _panel: PanelContainer
## Borde de arriba de la ficha (ver set_top).
var _top: float = MARGIN_TOP
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _title: Label
var _info: Label
var _details: Label
var _bars: Dictionary[String, ProgressBar] = {}
var _bar_values: Dictionary[String, Label] = {}
var _employee_id: int = 0
var _fire_button: Button
var _confirm_row: HBoxContainer
var _confirm_label: Label
var _confirm_button: Button
var _alert: Label
var _request_row: HBoxContainer
var _offer_row: HBoxContainer
var _match_button: Button
var _let_go_button: Button
var _accept_button: Button
var _deny_button: Button
var _raise_label: Label
var _raise_minus: Button
var _raise_plus: Button
var _raise_button: Button
## Aumento elegido en la fila Aumento (se reinicia al abrir la ficha).
var _raise_amount: int = 0
var _promotion_label: Label
var _promote_row: HBoxContainer
var _promote_minus: Button
var _promote_salary_label: Label
var _promote_plus: Button
var _promote_button: Button
## Sueldo elegido para el ascenso (0 = el sugerido; se reinicia al abrir la ficha).
var _promote_salary: int = 0
var _own_label: Label
var _own_button: Button
var _shift_editor: ShiftEditor
var _photo: EmployeePortrait
var _level_badge: Label
var _subtitle: Label
var _now: Label
var _traits: HFlowContainer
var _skill_bars: Dictionary[String, ProgressBar] = {}
var _skill_values: Dictionary[String, Label] = {}
var _skill_names: Dictionary[String, Label] = {}
var _history_values: Dictionary[String, Label] = {}
var _facts: Dictionary[String, Label] = {}
var _promotion_bar: ProgressBar
# Texto completo de los datos y detalles (get_text); en pantalla se reparten en secciones.
var _info_text: String = ""
var _details_text: String = ""


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	root.add_child(_panel)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -MARGIN - PANEL_WIDTH
	_panel.offset_right = -MARGIN
	_panel.offset_top = _top
	# Con la interfaz grande el contenido puede pedir más ancho: crece hacia la izquierda.
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	EventBus.ui_layout_changed.connect(_fit)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(rows)
	_rows = rows
	# La cabecera también se desplaza: con la interfaz grande no queda alto para dejarla fija.
	rows.add_child(_build_header())

	rows.add_child(_build_stats())
	rows.add_child(_build_history())
	rows.add_child(_build_facts())
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.theme_type_variation = &"MutedLabel"
	rows.add_child(_info)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_color_override("font_color", MUTED_COLOR)
	rows.add_child(_details)

	_alert = Label.new()
	_alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_alert.add_theme_color_override("font_color", ALERT_COLOR)
	rows.add_child(_alert)
	_request_row = HBoxContainer.new()
	rows.add_child(_request_row)
	_accept_button = Button.new()
	_accept_button.text = "Dar el aumento"
	_accept_button.pressed.connect(_accept_request)
	_request_row.add_child(_accept_button)
	_deny_button = Button.new()
	_deny_button.text = "Negar"
	_deny_button.pressed.connect(func() -> void: Staff.deny_raise(_employee_id))
	_request_row.add_child(_deny_button)
	# Oferta de otra empresa: igualarla o dejarlo ir.
	_offer_row = HBoxContainer.new()
	rows.add_child(_offer_row)
	_match_button = Button.new()
	_match_button.pressed.connect(func() -> void: Staff.match_offer(_employee_id))
	_offer_row.add_child(_match_button)
	_let_go_button = Button.new()
	_let_go_button.text = "Dejar ir"
	_let_go_button.pressed.connect(func() -> void:
		Staff.let_go(_employee_id)
		close())
	_offer_row.add_child(_let_go_button)

	var raise_row := HBoxContainer.new()
	rows.add_child(raise_row)
	_raise_minus = Button.new()
	_raise_minus.text = "−"
	_raise_minus.tooltip_text = "Bajar el aumento"
	_raise_minus.pressed.connect(func() -> void: _change_raise(-1))
	raise_row.add_child(_raise_minus)
	_raise_label = Label.new()
	_raise_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_raise_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	raise_row.add_child(_raise_label)
	_raise_plus = Button.new()
	_raise_plus.text = "+"
	_raise_plus.tooltip_text = "Subir el aumento"
	_raise_plus.pressed.connect(func() -> void: _change_raise(1))
	raise_row.add_child(_raise_plus)
	_raise_button = Button.new()
	_raise_button.text = "Dar aumento"
	_raise_button.pressed.connect(func() -> void:
		var employee: Dictionary = Staff.get_employee(_employee_id)
		if not employee.is_empty():
			Staff.give_raise(_employee_id, int(employee["salary"]) + _raise_amount))
	raise_row.add_child(_raise_button)
	# Ascenso: qué le falta y una barra de avance.
	var promotion_box := PanelContainer.new()
	promotion_box.add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.BG, 8.0))
	rows.add_child(promotion_box)
	var promotion_rows := VBoxContainer.new()
	promotion_rows.add_theme_constant_override("separation", 4)
	promotion_box.add_child(promotion_rows)
	_promotion_label = Label.new()
	_promotion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	promotion_rows.add_child(_promotion_label)
	_promotion_bar = _make_meter(UiTheme.ACCENT)
	promotion_rows.add_child(_promotion_bar)
	_promote_row = HBoxContainer.new()
	rows.add_child(_promote_row)
	_promote_minus = Button.new()
	_promote_minus.text = "−"
	_promote_minus.tooltip_text = "Bajar el sueldo del ascenso"
	_promote_minus.pressed.connect(func() -> void: _change_promote_salary(-1))
	_promote_row.add_child(_promote_minus)
	_promote_salary_label = Label.new()
	_promote_salary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_promote_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_promote_row.add_child(_promote_salary_label)
	_promote_plus = Button.new()
	_promote_plus.text = "+"
	_promote_plus.tooltip_text = "Subir el sueldo del ascenso"
	_promote_plus.pressed.connect(func() -> void: _change_promote_salary(1))
	_promote_row.add_child(_promote_plus)
	_promote_button = Button.new()
	_promote_button.text = "Ascender"
	_promote_button.pressed.connect(func() -> void:
		Staff.promote(_employee_id, _promote_salary)
		_promote_salary = 0)
	_promote_row.add_child(_promote_button)

	var own_row := HBoxContainer.new()
	rows.add_child(own_row)
	_own_label = Label.new()
	_own_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_own_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	own_row.add_child(_own_label)
	_own_button = Button.new()
	_own_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_own_button.pressed.connect(_toggle_own_schedule)
	own_row.add_child(_own_button)
	_shift_editor = ShiftEditor.new(40.0, true)
	_shift_editor.changed.connect(func(start_hour: int, days: Array[int], overtime: int) -> void:
		var result: Dictionary = Staff.set_own_schedule(_employee_id, start_hour, days, overtime)
		if not bool(result["ok"]):
			EventBus.notice.emit(result["message"]))
	rows.add_child(_shift_editor)
	# Avisos y aumento antes de las habilidades: es lo urgente.
	rows.move_child(_details, rows.get_child_count() - 1)

	_fire_button = Button.new()
	_fire_button.text = "Despedir"
	_fire_button.pressed.connect(_ask_fire)
	rows.add_child(_fire_button)
	_confirm_row = HBoxContainer.new()
	rows.add_child(_confirm_row)
	_confirm_label = Label.new()
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_row.add_child(_confirm_label)
	_confirm_button = Button.new()
	_confirm_button.text = "Sí, despedir"
	_confirm_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_confirm_button.pressed.connect(func() -> void: Staff.fire(_employee_id))
	_confirm_row.add_child(_confirm_button)
	var cancel := Button.new()
	cancel.text = "No"
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_cancel_fire)
	_confirm_row.add_child(cancel)
	_confirm_row.visible = false

	_panel.visible = false
	EventBus.staff_changed.connect(_refresh)
	EventBus.hour_changed.connect(func(_hour: int) -> void: _refresh())


# Cabecera: foto con su nivel, nombre, cargo, qué hace y rasgos; Cerrar arriba a la derecha.
func _build_header() -> Control:
	var band := PanelContainer.new()
	band.theme_type_variation = &"HeaderPanel"
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	band.add_child(top)
	var photo_column := VBoxContainer.new()
	photo_column.add_theme_constant_override("separation", -10)
	top.add_child(photo_column)
	_photo = EmployeePortrait.new()
	_photo.custom_minimum_size = Vector2(PHOTO_SIZE, PHOTO_SIZE)
	photo_column.add_child(_photo)
	_level_badge = Label.new()
	_level_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_level_badge.theme_type_variation = &"CaptionLabel"
	_level_badge.add_theme_color_override("font_color", UiTheme.BG)
	var badge := StyleBoxFlat.new()
	badge.bg_color = UiTheme.ACCENT
	badge.border_color = UiTheme.OUTLINE
	badge.set_border_width_all(2)
	badge.content_margin_left = 8.0
	badge.content_margin_right = 8.0
	badge.content_margin_top = 1.0
	badge.content_margin_bottom = 1.0
	_level_badge.add_theme_stylebox_override("normal", badge)
	photo_column.add_child(_level_badge)
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_constant_override("separation", 2)
	top.add_child(who)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.add_child(_title)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"MutedLabel"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.add_child(_subtitle)
	_now = Label.new()
	_now.theme_type_variation = &"MutedLabel"
	_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.add_child(_now)
	_traits = HFlowContainer.new()
	_traits.add_theme_constant_override("h_separation", 4)
	_traits.add_theme_constant_override("v_separation", 4)
	who.add_child(_traits)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(close)
	top.add_child(close_button)
	return band


# Estado (energía, ánimo, estrés) y habilidades, lado a lado.
func _build_stats() -> Control:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	var state := _section("ESTADO")
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(state)
	for bar: String in BARS:
		var parts: Array = _meter_row(state, BARS[bar], BAR_NAME_WIDTH, BAR_COLORS[bar])
		_bars[bar] = parts[0]
		_bar_values[bar] = parts[1]
	var skills := _section("HABILIDADES")
	skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills.size_flags_stretch_ratio = 1.2
	columns.add_child(skills)
	for skill: String in StaffCatalog.get_skill_ids():
		var parts: Array = _meter_row(skills, StaffCatalog.get_skill_name(skill), SKILL_NAME_WIDTH, SKILL_COLOR)
		_skill_bars[skill] = parts[0]
		_skill_values[skill] = parts[1]
		_skill_names[skill] = parts[2]
	return columns


# Historial en casillas: contratos, errores, tardanzas, ausencias y puntualidad.
func _build_history() -> Control:
	var section := _section("HISTORIAL")
	var grid := GridContainer.new()
	grid.columns = HISTORY.size()
	grid.add_theme_constant_override("h_separation", 6)
	section.add_child(grid)
	for key: String in HISTORY:
		var tile := PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_stylebox_override("panel", UiTheme.flat_box(UiTheme.BG, 4.0))
		grid.add_child(tile)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 0)
		tile.add_child(stack)
		var value := Label.new()
		value.theme_type_variation = &"SectionLabel"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(value)
		var caption := Label.new()
		caption.text = HISTORY[key]
		caption.theme_type_variation = &"MutedLabel"
		caption.add_theme_font_size_override("font_size", 11)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(caption)
		_history_values[key] = value
	return section


# Equipo, horario, sueldo y dónde trabaja, en dos columnas.
func _build_facts() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	for key: String in FACTS:
		var fact := VBoxContainer.new()
		fact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fact.add_theme_constant_override("separation", 0)
		grid.add_child(fact)
		var caption := Label.new()
		caption.text = FACTS[key]
		caption.theme_type_variation = &"CaptionLabel"
		fact.add_child(caption)
		var value := Label.new()
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fact.add_child(value)
		_facts[key] = value
	return grid


func _section(title: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	var caption := Label.new()
	caption.text = title
	caption.theme_type_variation = &"CaptionLabel"
	section.add_child(caption)
	return section


# Fila nombre · barra · valor; devuelve [barra, valor, nombre].
func _meter_row(parent: Container, title: String, name_width: float, color: Color) -> Array:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var name_label := Label.new()
	name_label.text = title
	name_label.custom_minimum_size = Vector2(name_width, 0)
	name_label.add_theme_font_size_override("font_size", 14)
	line.add_child(name_label)
	var meter: ProgressBar = _make_meter(color)
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(meter)
	var value := Label.new()
	value.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.theme_type_variation = &"StrongLabel"
	line.add_child(value)
	return [meter, value, name_label]


func _make_meter(color: Color) -> ProgressBar:
	var meter := ProgressBar.new()
	meter.min_value = 0.0
	meter.max_value = 100.0
	meter.show_percentage = false
	meter.custom_minimum_size = Vector2(0, METER_HEIGHT)
	meter.add_theme_stylebox_override("background", UiTheme.flat_fill(UiTheme.OUTLINE))
	meter.add_theme_stylebox_override("fill", UiTheme.flat_fill(color))
	return meter


## Pone el borde de arriba de la ficha (bajo el reloj, o en la columna de Personal); negativo vuelve al de siempre.
func set_top(top: float) -> void:
	_top = MARGIN_TOP if top < 0.0 else top
	_panel.offset_top = _top
	_fit()


## Abre la ficha de un empleado (o la cambia a otro).
func open_employee(employee_id: int) -> void:
	_employee_id = employee_id
	_raise_amount = 0
	_promote_salary = 0
	_cancel_fire()
	_panel.visible = true
	_refresh()
	employee_changed.emit(employee_id)


func close() -> void:
	if _panel.visible:
		_panel.visible = false
		employee_changed.emit(0)


func is_open() -> bool:
	return _panel.visible


## Id del empleado de la ficha abierta.
func get_employee_id() -> int:
	return _employee_id


## Botón Despedir (pide confirmación).
func get_fire_button() -> Button:
	return _fire_button


## Botón que confirma el despido (solo visible después de pulsar Despedir).
func get_confirm_fire_button() -> Button:
	return _confirm_button


## Botón que acepta el aumento que pidió el empleado.
func get_accept_raise_button() -> Button:
	return _accept_button


## Botones de la oferta de otra empresa: «Igualar ($X)» y «Dejar ir».
func get_match_offer_button() -> Button:
	return _match_button


func get_let_go_button() -> Button:
	return _let_go_button


## Botón que niega el aumento que pidió el empleado.
func get_deny_raise_button() -> Button:
	return _deny_button


## Botones de la fila Aumento: «−», «+» y «Dar aumento».
func get_raise_minus_button() -> Button:
	return _raise_minus


func get_raise_plus_button() -> Button:
	return _raise_plus


func get_raise_button() -> Button:
	return _raise_button


## Aumento elegido en la fila Aumento.
func get_raise_amount() -> int:
	return _raise_amount


## Botones de la fila Ascender: «−», «+» y «Ascender» (la fila solo se ve si cumple).
func get_promote_minus_button() -> Button:
	return _promote_minus


func get_promote_plus_button() -> Button:
	return _promote_plus


func get_promote_button() -> Button:
	return _promote_button


## Indica si se ve la fila Ascender.
func is_promote_visible() -> bool:
	return _promote_row.visible


## Sueldo elegido para el ascenso.
func get_promote_salary() -> int:
	return _promote_salary


## Desplaza la ficha hasta que se vea un control.
func reveal(control: Control) -> void:
	_scroll.ensure_control_visible(control)


## Valor de una barra ("energy", "mood" o "stress").
func get_bar_value(bar: String) -> float:
	return _bars[bar].value


## Todo el texto de la ficha (para las pruebas).
func get_text() -> String:
	var texts: Array[String] = [_title.text, _info_text]
	for bar: String in BARS:
		texts.append("%s %s" % [BARS[bar], _bar_values[bar].text])
	texts.append(_details_text)
	if _alert.visible:
		texts.append(_alert.text)
	texts.append(_raise_label.text)
	texts.append(_promotion_label.text)
	texts.append(_own_label.text)
	if _promote_row.visible:
		texts.append(_promote_salary_label.text)
	if _confirm_row.visible:
		texts.append(_confirm_label.text)
	return "\n".join(texts)


## Vuelve a leer los datos (lo hace sola al cambiar el personal o la hora).
func refresh() -> void:
	_refresh()


func _refresh() -> void:
	if _panel == null or not is_open():
		return
	var employee: Dictionary = Staff.get_employee(_employee_id)
	if employee.is_empty():
		close()
		return
	_title.text = employee["name"]
	_photo.set_employee(employee)
	var role: String = employee["role"]
	_level_badge.visible = StaffCatalog.has_levels(role)
	_level_badge.text = StaffCatalog.get_level_name(employee["level"]).to_upper()
	var days: int = GameClock.get_day_count() - int(employee["hired_day"])
	_subtitle.text = "%s · %d años" % [StaffCatalog.get_role_name(role), employee["age"]]
	var now: String = String(status_provider.call(_employee_id)) if status_provider.is_valid() else "—"
	_now.text = "Ahora: %s" % now
	_refresh_traits(employee)
	var schedule: WorkSchedule = Staff.get_schedule(employee)
	var lunch: int = schedule.get_lunch_hour()
	var team: Dictionary = Staff.get_team_of(employee["id"])
	var schedule_text: String = "%s · almuerzo %d:00–%d:00" % [schedule.describe(), lunch, (lunch + 1) % GameConstants.HOURS_PER_DAY]
	var room: Dictionary = Staff.get_workplace_room(Staff.employee_key(employee["id"]))
	_facts["team"].text = _describe_team(employee, team)
	_facts["schedule"].text = schedule_text
	_facts["salary"].text = "%s al mes" % MoneyFormat.format(employee["salary"])
	_facts["days"].text = "%d %s" % [days, "día" if days == 1 else "días"]
	# En pantalla quedan aparte lo que no tiene su casilla: lo ganado, quién lo dirige y cuánto rinde.
	var extra: Array[String] = [_describe_pay(employee)]
	var boss: String = _describe_boss(employee)
	if not boss.is_empty():
		extra.append(boss)
	var performance: String = describe_performance(employee)
	if not performance.is_empty():
		extra.append(performance)
	_info.text = "\n".join(extra)
	_info_text = "\n".join(["%s, %d años" % [Staff.describe_employee(employee), employee["age"]],
		"Equipo: %s" % _describe_team(employee, team), "Horario: %s" % schedule_text, "Ahora: %s" % now] + extra)
	for bar: String in BARS:
		var value: int = int(employee[bar])
		_bars[bar].value = value
		_bar_values[bar].text = str(value)
	var main_skill: String = StaffCatalog.get_main_skill(role)
	for skill: String in StaffCatalog.get_skill_ids():
		var value: int = int(employee["skills"][skill])
		var main: bool = skill == main_skill
		_skill_bars[skill].value = value
		_skill_bars[skill].add_theme_stylebox_override("fill", UiTheme.flat_fill(UiTheme.ACCENT if main else SKILL_COLOR))
		_skill_values[skill].text = str(value)
		for label: Label in [_skill_names[skill], _skill_values[skill]]:
			if main:
				label.add_theme_color_override("font_color", UiTheme.ACCENT)
			else:
				label.remove_theme_color_override("font_color")
	_refresh_history(employee)
	var shown: Array[String] = []
	# Qué hace cada rasgo conocido.
	for trait_id: String in employee.get("known_traits", []):
		var effect: String = Staff.describe_trait(trait_id)
		if not effect.is_empty():
			shown.append("· %s: %s" % [StaffCatalog.get_trait_name(trait_id), effect])
	if Staff.is_waiting_promotion(employee):
		shown.append("Quiere un ascenso: ya puede ascender y no se lo dan.")
	if Staff.is_missing(employee, GameClock.get_weekday(), GameClock.get_hour()):
		shown.append("Hoy faltó." if int(employee["missing_until"]) - int(employee["missing_from"]) > 1 else "Llegó tarde: viene a la próxima hora.")
	if not room.is_empty():
		shown.append("Trabaja en: %s · %s" % [RoomCatalog.get_display_name(room["type"]),
			Ambiance.describe(room, OfficeState.furniture, OfficeState.count_room_windows(room),
				OfficeState.get_room_door_ambiance(room))])
	_details.text = "\n".join(shown)
	_details.visible = not shown.is_empty()
	var known: String = Staff.describe_known_traits(employee)
	_details_text = "\n".join(["Habilidades: %s" % Staff.describe_skills(employee),
		known if not known.is_empty() else "Rasgos: ninguno conocido todavía", Staff.describe_history(employee)] + shown)
	_refresh_raise(employee)
	_refresh_promotion(employee)
	_refresh_own_schedule(employee, team)
	_fit.call_deferred()
	if _confirm_row.visible:
		_confirm_label.text = "¿Despedir a %s? Cuesta %s y baja el ánimo de sus compañeros." % [
			employee["name"], MoneyFormat.format(Staff.get_firing_cost(employee))]


## "Rinde 85 % (desanimado)" si la energía o el ánimo le bajan la producción, o "".
static func describe_performance(employee: Dictionary) -> String:
	var energy: float = Production.get_energy_factor(float(employee["energy"]))
	var mood: float = Production.get_mood_factor(float(employee["mood"]))
	if energy * mood >= 1.0 - Production.EPSILON:
		return ""
	var causes: Array[String] = []
	if energy < 1.0:
		causes.append("cansado")
	if mood < 1.0:
		causes.append("desanimado")
	return "Rinde %d %% (%s)" % [roundi(energy * mood * 100.0), " y ".join(causes)]


# Rasgos conocidos como etiquetas, más cuántos faltan por descubrir.
func _refresh_traits(employee: Dictionary) -> void:
	for child: Node in _traits.get_children():
		_traits.remove_child(child)
		child.queue_free()
	var known: Array = employee.get("known_traits", [])
	for trait_id: String in known:
		_traits.add_child(_chip(StaffCatalog.get_trait_name(trait_id), UiTheme.SOFT))
	var hidden: int = (employee.get("traits", []) as Array).size() - known.size()
	if hidden > 0:
		var chip: Label = _chip("? %d %s" % [hidden, "oculto" if hidden == 1 else "ocultos"], UiTheme.FAINT)
		chip.tooltip_text = "Se descubren trabajando con él."
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		_traits.add_child(chip)


func _chip(text: String, color: Color) -> Label:
	var chip := Label.new()
	chip.text = text
	chip.add_theme_font_size_override("font_size", 13)
	chip.add_theme_color_override("font_color", color)
	var box: StyleBoxFlat = UiTheme.flat_box(Color(UiTheme.OUTLINE, 0.35), 0.0)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 1.0
	box.content_margin_bottom = 1.0
	chip.add_theme_stylebox_override("normal", box)
	return chip


func _refresh_history(employee: Dictionary) -> void:
	var bugs: int = int(employee.get("bugs_caused", 0))
	var punctuality: int = Staff.get_punctuality(employee)
	_history_values["projects"].text = str(int(employee.get("projects_worked", 0)))
	_history_values["bugs"].text = str(bugs)
	_history_values["late"].text = str(int(employee.get("late_count", 0)))
	_history_values["absent"].text = str(int(employee.get("absent_count", 0)))
	_history_values["punctuality"].text = "—" if punctuality < 0 else "%d%%" % punctuality
	_history_values["projects"].add_theme_color_override("font_color", UiTheme.POSITIVE)
	if bugs > 0:
		_history_values["bugs"].add_theme_color_override("font_color", UiTheme.NEGATIVE)
	else:
		_history_values["bugs"].remove_theme_color_override("font_color")


# Fila Horario propio: el botón para tenerlo o volver al del equipo o cargo y, si lo tiene, sus controles.
func _refresh_own_schedule(employee: Dictionary, team: Dictionary) -> void:
	var own: bool = Staff.has_own_schedule(employee)
	_own_label.text = "Horario propio" if own else ("Sigue el turno de su equipo" if not team.is_empty() else "Sigue el horario de su cargo")
	_own_button.text = ("Usar el del equipo" if not team.is_empty() else "Usar el del cargo") if own else "Usar uno propio"
	_shift_editor.visible = own
	if own:
		_shift_editor.set_schedule(Staff.get_schedule(employee))


func _toggle_own_schedule() -> void:
	var employee: Dictionary = Staff.get_employee(_employee_id)
	if employee.is_empty():
		return
	if Staff.has_own_schedule(employee):
		Staff.clear_own_schedule(_employee_id)
	else:
		# Empieza con la entrada y los días que ya tiene.
		var schedule: WorkSchedule = Staff.get_schedule(employee)
		Staff.set_own_schedule(_employee_id, schedule.start_hour, schedule.days, schedule.overtime)


## Botón para tener horario propio o volver al del equipo o el cargo.
func get_own_schedule_button() -> Button:
	return _own_button


## Controles del horario propio.
func get_shift_editor() -> ShiftEditor:
	return _shift_editor


# Ajusta el alto: lo que pide el contenido, sin pasar de la pantalla.
func _fit() -> void:
	if not is_open():
		return
	var available: float = UiLayout.available_height(_panel.get_viewport_rect().size, _top) \
		- (_panel.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y)
	_scroll.custom_minimum_size.y = minf(_rows.get_combined_minimum_size().y, maxf(available, 100.0))
	_panel.offset_bottom = _panel.offset_top


# Avisos de renuncia y pedido de aumento, y la fila Aumento.
func _refresh_raise(employee: Dictionary) -> void:
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	var salary: int = employee["salary"]
	if _raise_amount <= 0:
		# Por defecto, lo justo para retener a quien renuncia.
		var ratio: float = StaffCatalog.get_morale("retain_raise_ratio")
		_raise_amount = maxi(step, ceili(salary * ratio / step) * step)
	var alerts: Array[String] = []
	var days: int = Staff.quit_days_left(employee)
	if days >= 0:
		alerts.append("Renuncia: se va en %d %s. Un aumento de %d%% o más lo retiene." % [
			days, "día" if days == 1 else "días", roundi(StaffCatalog.get_morale("retain_raise_ratio") * 100.0)])
	var request: Dictionary = employee["raise_request"]
	if not request.is_empty():
		var left: int = maxi(0, int(request["until_day"]) - GameClock.get_day_count())
		alerts.append("Pide un aumento de %s (%d %s para responder)." % [
			MoneyFormat.format(int(request["amount"])), left, "día" if left == 1 else "días"])
	var offer: Dictionary = employee.get("outside_offer", {})
	if not offer.is_empty():
		var offer_left: int = maxi(0, int(offer["until_day"]) - GameClock.get_day_count())
		alerts.append("Otra empresa le ofrece %s al mes: se va en %d %s si no igualas la oferta." % [
			MoneyFormat.format(int(offer["salary"])), offer_left, "día" if offer_left == 1 else "días"])
		_match_button.text = "Igualar (%s)" % MoneyFormat.format(int(offer["salary"]))
	_offer_row.visible = not offer.is_empty()
	if Staff.works_in_dirty_room(Staff.employee_key(employee["id"])):
		alerts.append("Su lugar de trabajo está sucio: le baja el ánimo. Contrata personal de limpieza.")
	_alert.text = "\n".join(alerts)
	_alert.visible = not alerts.is_empty()
	_request_row.visible = not request.is_empty()
	_raise_minus.disabled = _raise_amount <= step
	_raise_label.text = "Aumento +%s → %s" % [MoneyFormat.format(_raise_amount), MoneyFormat.format(salary + _raise_amount)]


# Cómo va hacia el nivel siguiente y la fila Ascender cuando cumple.
func _refresh_promotion(employee: Dictionary) -> void:
	var progress: Dictionary = Staff.get_promotion_progress(employee)
	var next_level: String = progress["next_level"]
	var next_role: String = progress["next_role"]
	var salary: int = employee["salary"]
	var ready: bool = bool(progress["ready"])
	_promote_row.visible = ready
	# Barra: lo que lleva de contratos y días (llena si ya puede); sin siguiente cargo no se ve.
	var parts: Array[float] = []
	for key: String in ["projects", "days"]:
		var needed: int = int(progress[key + "_needed"])
		if needed > 0:
			parts.append(minf(1.0, float(progress[key]) / needed))
	var fraction: float = 1.0
	if not ready and not parts.is_empty():
		fraction = (parts.reduce(func(total: float, part: float) -> float: return total + part, 0.0) as float) / parts.size()
	_promotion_bar.value = fraction * 100.0
	_promotion_bar.visible = not (next_level.is_empty() and next_role.is_empty()) and progress["blocker"] != "stage"
	var new_salary: int = 0
	if not next_role.is_empty():
		# Un Senior asciende a líder de equipo desde la etapa de ese cargo.
		var role_name: String = StaffCatalog.get_role_name(next_role)
		new_salary = StaffCatalog.get_salary(next_role, employee["level"])
		if progress["blocker"] == "stage":
			_promotion_label.text = "Ascenso a %s: desde %s." % [role_name,
				Company.get_stage_name(StaffCatalog.get_role_min_stage(next_role))]
			return
		if not ready:
			_promotion_label.text = "Ascenso a %s: %s" % [role_name, Staff.get_station_problem(next_role)]
			return
		_promotion_label.text = "Puede ascender a %s. Sueldo de ese cargo: %s." % [role_name, MoneyFormat.format(new_salary)]
	elif next_level.is_empty():
		_promotion_label.text = "Ascenso: ya está en el cargo más alto."
		return
	else:
		var level_name: String = StaffCatalog.get_level_name(next_level)
		var counted: String = "ventas cerradas" if employee["role"] == Staff.SALES_ROLE else "contratos trabajados"
		var needs: String = "%s %d/%d · días en la empresa %d/%d" % [counted,
			mini(int(progress["projects"]), int(progress["projects_needed"])), progress["projects_needed"],
			mini(int(progress["days"]), int(progress["days_needed"])), progress["days_needed"]]
		if not ready:
			_promotion_label.text = "Ascenso a %s: %s." % [level_name, needs]
			return
		new_salary = StaffCatalog.get_salary(employee["role"], next_level)
		_promotion_label.text = "Puede ascender a %s (%s). Sueldo de ese nivel: %s." % [level_name, needs,
			MoneyFormat.format(new_salary)]
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	if _promote_salary <= salary:
		_promote_salary = maxi(salary + step, new_salary)
	_promote_minus.disabled = _promote_salary - step <= salary
	_promote_salary_label.text = "Sueldo nuevo %s" % MoneyFormat.format(_promote_salary)


func _change_promote_salary(direction: int) -> void:
	var employee: Dictionary = Staff.get_employee(_employee_id)
	if employee.is_empty():
		return
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	_promote_salary = maxi(int(employee["salary"]) + step, _promote_salary + direction * step)
	_refresh()


func _change_raise(direction: int) -> void:
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	_raise_amount = maxi(step, _raise_amount + direction * step)
	_refresh()


func _accept_request() -> void:
	var employee: Dictionary = Staff.get_employee(_employee_id)
	if employee.is_empty() or (employee["raise_request"] as Dictionary).is_empty():
		return
	Staff.give_raise(_employee_id, int(employee["salary"]) + int(employee["raise_request"]["amount"]))


# Quién dirige a un líder o a cuántos dirige un gerente; "" para los demás.
func _describe_boss(employee: Dictionary) -> String:
	if Staff.is_leader(employee):
		var manager: Dictionary = Staff.get_manager_of(employee)
		return "Lo dirige: %s" % ("el CEO" if manager.is_empty() else "%s (gerente)" % manager["name"])
	if Staff.is_executive(employee):
		var department: String = employee.get("department", "")
		if department.is_empty():
			return "No dirige ningún departamento: elígelo en el organigrama (Personal)."
		return "Dirige %s (rinde %d %%)" % [StaffCatalog.get_department_name(department),
			roundi(Staff.get_department_factor(department) * 100.0)]
	var own: String = StaffCatalog.get_role_department(employee["role"])
	if not own.is_empty():
		var factor: float = Staff.get_department_factor(own)
		if not is_equal_approx(factor, 1.0):
			var executive: Dictionary = Staff.get_executive_of(own)
			return "Departamento: %s, lo dirige %s (rinde %d %%)" % [StaffCatalog.get_department_name(own),
				"el CEO" if executive.is_empty() else executive["name"], roundi(factor * 100.0)]
	if Staff.is_manager(employee):
		var names: Array[String] = []
		for leader: Dictionary in Staff.get_leaders_of(employee["id"]):
			names.append(leader["name"])
		return "Dirige %d de %d líderes%s" % [names.size(), Staff.get_leader_cap(employee["id"]),
			": " + ", ".join(names) if not names.is_empty() else ""]
	return ""


# "Equipo 1", "Equipo 1 (lo lidera)" o sin equipo.
func _describe_team(employee: Dictionary, team: Dictionary) -> String:
	if team.is_empty():
		return "sin equipo (horario de su cargo)"
	if int(team.get("leader_id", 0)) == int(employee["id"]):
		return "%s (lo lidera)" % team["name"]
	return team["name"]


func _describe_pay(employee: Dictionary) -> String:
	var text: String = "Ganado desde el último pago: %s" % MoneyFormat.format(Staff.get_earned(employee))
	var extra: int = Staff.get_extra_earned(employee)
	if extra > 0:
		text += " + %s de horas extra y noche" % MoneyFormat.format(extra)
	var owed: int = int(employee["owed"])
	if owed > 0:
		text += " · se le deben %s" % MoneyFormat.format(owed)
	return text


func _ask_fire() -> void:
	_fire_button.visible = false
	_confirm_row.visible = true
	_refresh()


func _cancel_fire() -> void:
	_fire_button.visible = true
	_confirm_row.visible = false
