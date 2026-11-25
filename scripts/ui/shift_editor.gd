# Controles de un turno: entrada y horas extra con −/+ y un botón por día.
# Solo avisa con changed; quien lo usa le pide el cambio a Staff.
class_name ShiftEditor
extends VBoxContainer

## El jugador pidió otro turno: hora de entrada, días y horas extra.
signal changed(start_hour: int, days: Array[int], overtime: int)

const MUTED_COLOR := UiTheme.MUTED
const STEP_BUTTON_WIDTH: float = 36.0

var _schedule: WorkSchedule = WorkSchedule.new()
var _controls: Dictionary[String, Control] = {}
var _start_label: Label
var _overtime_label: Label


## Con split las horas extra van en otra fila (paneles angostos como la ficha).
func _init(day_button_width: float = 44.0, split: bool = false) -> void:
	add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	add_child(row)
	row.add_child(_muted("Entrada"))
	_add_step(row, "earlier", "−", "Entrar una hora antes", func() -> void: _emit(posmod(_schedule.start_hour - 1, GameConstants.HOURS_PER_DAY), _schedule.days, _schedule.overtime))
	_start_label = Label.new()
	_start_label.custom_minimum_size = Vector2(52, 0)
	_start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_start_label)
	_add_step(row, "later", "+", "Entrar una hora después", func() -> void: _emit((_schedule.start_hour + 1) % GameConstants.HOURS_PER_DAY, _schedule.days, _schedule.overtime))
	if split:
		row = HBoxContainer.new()
		add_child(row)
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(12, 0)
		row.add_child(gap)
	row.add_child(_muted("Horas extra"))
	_add_step(row, "less_overtime", "−", "Una hora extra menos", func() -> void: _emit(_schedule.start_hour, _schedule.days, _schedule.overtime - 1))
	_overtime_label = Label.new()
	_overtime_label.custom_minimum_size = Vector2(28, 0)
	_overtime_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_overtime_label)
	_add_step(row, "more_overtime", "+", "Una hora extra más", func() -> void: _emit(_schedule.start_hour, _schedule.days, _schedule.overtime + 1))
	var days_row := HBoxContainer.new()
	add_child(days_row)
	for day: int in range(GameConstants.DAYS_PER_WEEK):
		var toggle := Button.new()
		toggle.text = WorkSchedule.DAY_NAMES[day]
		toggle.toggle_mode = true
		toggle.custom_minimum_size = Vector2(day_button_width, 0)
		toggle.pressed.connect(func() -> void:
			var days: Array[int] = _schedule.days.duplicate()
			if days.has(day):
				days.erase(day)
			else:
				days.append(day)
			_emit(_schedule.start_hour, days, _schedule.overtime))
		days_row.add_child(toggle)
		_controls["day_%d" % day] = toggle


## Muestra un turno sin avisar de cambios.
func set_schedule(schedule: WorkSchedule) -> void:
	_schedule = schedule
	_start_label.text = "%d:00" % schedule.start_hour
	_overtime_label.text = str(schedule.overtime)
	var max_hours: int = int(StaffCatalog.get_overtime("max_hours"))
	(_controls["less_overtime"] as Button).disabled = schedule.overtime <= 0
	(_controls["more_overtime"] as Button).disabled = schedule.overtime >= max_hours
	for day: int in range(GameConstants.DAYS_PER_WEEK):
		(_controls["day_%d" % day] as Button).set_pressed_no_signal(schedule.days.has(day))


## Control por nombre: "earlier", "later", "less_overtime", "more_overtime" o "day_N".
func get_control(control: String) -> Control:
	return _controls.get(control)


## Todos los controles por nombre (para las pruebas).
func get_controls() -> Dictionary[String, Control]:
	return _controls


func _add_step(row: HBoxContainer, key: String, text: String, tooltip: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(STEP_BUTTON_WIDTH, 0)
	button.pressed.connect(action)
	row.add_child(button)
	_controls[key] = button


func _emit(start_hour: int, days: Array[int], overtime: int) -> void:
	changed.emit(start_hour, days, overtime)


func _muted(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label
