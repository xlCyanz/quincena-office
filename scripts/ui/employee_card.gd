# Ficha de empleado (diseño, 12.4): nombre, cargo, nivel, equipo, horario, qué está
# haciendo, barras de energía, ánimo y estrés, habilidades, rasgos conocidos y sueldo.
# Tiene el botón Despedir (hito 13), que pide confirmar con el costo, y desde el hito 19
# avisa si renuncia o pide aumento: un pedido se acepta o se niega, y la fila Aumento
# sube el sueldo cuando el jugador quiera (de a salary_step). Desde el hito 30 muestra
# cómo va hacia el nivel siguiente y, cuando cumple, la fila Ascender con el sueldo
# nuevo (mayor que el actual; sugerido el de su nivel nuevo). Desde el hito 34 tiene
# la fila Horario propio: un turno suyo (entrada, días y horas extra) que reemplaza el
# de su equipo o su cargo, y muestra las horas extra y el recargo nocturno sin pagar.
#
# Se abre con un clic en el empleado o desde Personal, no pausa el tiempo y se
# actualiza sola. Va a la derecha, debajo del reloj; si no entra en la pantalla, el
# contenido (menos el título) se desplaza. Lo que el empleado está haciendo
# lo sabe la escena de juego, que lo da con status_provider.
class_name EmployeeCard
extends CanvasLayer

const PANEL_WIDTH: float = 360.0
const MARGIN: float = 16.0
const MARGIN_TOP: float = 140.0
## Espacio que se deja abajo para la barra de botones.
const MARGIN_BOTTOM: float = 76.0
const TITLE_FONT_SIZE: int = 22
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const ALERT_COLOR := Color("f2c14e")
## Barras de la ficha: clave en el empleado y nombre para el jugador.
const BARS: Dictionary[String, String] = {"energy": "Energía", "mood": "Ánimo", "stress": "Estrés"}
const BAR_COLORS: Dictionary[String, Color] = {
	"energy": Color("5aa84f"), "mood": Color("4a7fc1"), "stress": Color("c9553f"),
}

## Devuelve qué está haciendo un empleado ("Trabajando", …) a partir de su id.
var status_provider: Callable = Callable()

var _panel: PanelContainer
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
	_panel.offset_top = MARGIN_TOP
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_title)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(close)
	header.add_child(close_button)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(rows)
	_rows = rows

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_info)
	for bar: String in BARS:
		var line := HBoxContainer.new()
		rows.add_child(line)
		var name_label := Label.new()
		name_label.text = BARS[bar]
		name_label.custom_minimum_size = Vector2(80, 0)
		line.add_child(name_label)
		var progress := ProgressBar.new()
		progress.min_value = 0.0
		progress.max_value = 100.0
		progress.show_percentage = false
		progress.custom_minimum_size = Vector2(0, 18)
		progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = BAR_COLORS[bar]
		fill.set_corner_radius_all(3)
		progress.add_theme_stylebox_override("fill", fill)
		line.add_child(progress)
		var value := Label.new()
		value.custom_minimum_size = Vector2(40, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		_bars[bar] = progress
		_bar_values[bar] = value
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

	var raise_row := HBoxContainer.new()
	rows.add_child(raise_row)
	_raise_minus = Button.new()
	_raise_minus.text = "−"
	_raise_minus.pressed.connect(func() -> void: _change_raise(-1))
	raise_row.add_child(_raise_minus)
	_raise_label = Label.new()
	_raise_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_raise_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	raise_row.add_child(_raise_label)
	_raise_plus = Button.new()
	_raise_plus.text = "+"
	_raise_plus.pressed.connect(func() -> void: _change_raise(1))
	raise_row.add_child(_raise_plus)
	_raise_button = Button.new()
	_raise_button.text = "Dar aumento"
	_raise_button.pressed.connect(func() -> void:
		var employee: Dictionary = Staff.get_employee(_employee_id)
		if not employee.is_empty():
			Staff.give_raise(_employee_id, int(employee["salary"]) + _raise_amount))
	raise_row.add_child(_raise_button)
	_promotion_label = Label.new()
	_promotion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_promotion_label)
	_promote_row = HBoxContainer.new()
	rows.add_child(_promote_row)
	_promote_minus = Button.new()
	_promote_minus.text = "−"
	_promote_minus.pressed.connect(func() -> void: _change_promote_salary(-1))
	_promote_row.add_child(_promote_minus)
	_promote_salary_label = Label.new()
	_promote_salary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_promote_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_promote_row.add_child(_promote_salary_label)
	_promote_plus = Button.new()
	_promote_plus.text = "+"
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
	# Los avisos y el aumento van antes de las habilidades: es lo urgente.
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


## Abre la ficha de un empleado (o la cambia a otro).
func open_employee(employee_id: int) -> void:
	_employee_id = employee_id
	_raise_amount = 0
	_promote_salary = 0
	_cancel_fire()
	_panel.visible = true
	_refresh()


func close() -> void:
	_panel.visible = false


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


## Desplaza la ficha hasta que se vea un control (para las pruebas y los botones de abajo).
func reveal(control: Control) -> void:
	_scroll.ensure_control_visible(control)


## Valor de una barra ("energy", "mood" o "stress").
func get_bar_value(bar: String) -> float:
	return _bars[bar].value


## Todo el texto de la ficha (para las pruebas).
func get_text() -> String:
	var texts: Array[String] = [_title.text, _info.text]
	for bar: String in BARS:
		texts.append("%s %s" % [BARS[bar], _bar_values[bar].text])
	texts.append(_details.text)
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


## Vuelve a leer los datos (también lo hace sola al cambiar el personal o la hora).
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
	var schedule: WorkSchedule = Staff.get_schedule(employee)
	var lunch: int = schedule.get_lunch_hour()
	var team: Dictionary = Staff.get_team_of(employee["id"])
	_info.text = "\n".join([
		"%s, %d años" % [Staff.describe_employee(employee), employee["age"]],
		"Equipo: %s" % _describe_team(employee, team),
		"Horario: %s · almuerzo %d:00–%d:00" % [schedule.describe(), lunch, (lunch + 1) % GameConstants.HOURS_PER_DAY],
		_describe_pay(employee),
		"Ahora: %s" % (String(status_provider.call(_employee_id)) if status_provider.is_valid() else "—"),
	])
	var boss: String = _describe_boss(employee)
	if not boss.is_empty():
		_info.text += "\n" + boss
	var performance: String = describe_performance(employee)
	if not performance.is_empty():
		_info.text += "\n" + performance
	for bar: String in BARS:
		var value: int = int(employee[bar])
		_bars[bar].value = value
		_bar_values[bar].text = str(value)
	var details: Array[String] = ["Habilidades: %s" % Staff.describe_skills(employee)]
	var known: String = Staff.describe_known_traits(employee)
	details.append(known if not known.is_empty() else "Rasgos: ninguno conocido todavía")
	_details.text = "\n".join(details)
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


# Fila Horario propio: el botón para tenerlo o volver al del equipo (o del cargo) y,
# si lo tiene, sus controles.
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
	var available: float = _panel.get_viewport_rect().size.y - MARGIN_TOP - MARGIN_BOTTOM \
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
	var new_salary: int = 0
	if not next_role.is_empty():
		# Un Senior asciende de cargo (a líder de equipo) desde la etapa de ese cargo.
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
