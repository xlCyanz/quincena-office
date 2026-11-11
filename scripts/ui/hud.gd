# Interfaz superpuesta mínima (diseño, 12.2): arriba a la izquierda el dinero y arriba
# a la derecha el reloj, con la fecha, la cuenta atrás de la próxima nómina, la pausa y
# las velocidades. El botón Construir está en BuildPanel, abajo al centro. Se construye
# en código; los botones avisan con señales y la escena de juego decide qué hacer.
class_name Hud
extends CanvasLayer

## Se pulsó el botón de pausa.
signal pause_pressed
## Se eligió una velocidad (índice en GameConstants.CLOCK_SPEEDS).
signal speed_pressed(index: int)

const MARGIN: float = 12.0
const WEEKDAY_NAMES: Array[String] = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]
const NEGATIVE_COLOR := Color(1.0, 0.45, 0.4)
const MONEY_FONT_SIZE: int = 24
const PANEL_COLOR := Color(0.12, 0.12, 0.14, 0.88)
const PANEL_PADDING: float = 8.0
const PANEL_RADIUS: int = 6

var _balance_label: Label
var _date_label: Label
var _time_label: Label
var _payroll_label: Label
var _pause_button: Button
var _speed_buttons: Array[Button] = []
var _controls_enabled: bool = true


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Dinero, arriba a la izquierda.
	var money_panel: PanelContainer = make_panel()
	root.add_child(money_panel)
	money_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	_balance_label = Label.new()
	_balance_label.add_theme_font_size_override("font_size", MONEY_FONT_SIZE)
	money_panel.add_child(_balance_label)

	# Reloj, arriba a la derecha.
	var clock_panel: PanelContainer = make_panel()
	root.add_child(clock_panel)
	var clock_rows := VBoxContainer.new()
	clock_panel.add_child(clock_rows)
	var time_row := HBoxContainer.new()
	clock_rows.add_child(time_row)
	_date_label = Label.new()
	_date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(_date_label)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", MONEY_FONT_SIZE)
	time_row.add_child(_time_label)
	_payroll_label = Label.new()
	clock_rows.add_child(_payroll_label)
	_payroll_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.75))
	var speed_row := HBoxContainer.new()
	clock_rows.add_child(speed_row)
	_pause_button = _add_toggle(speed_row, "Pausa")
	_pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	for index: int in range(GameConstants.CLOCK_SPEEDS.size()):
		var button: Button = _add_toggle(speed_row, "%dx" % int(GameConstants.CLOCK_SPEEDS[index]))
		button.pressed.connect(func() -> void: speed_pressed.emit(index))
		_speed_buttons.append(button)
	clock_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	clock_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	EventBus.balance_changed.connect(_on_balance_changed)
	_on_balance_changed(Economy.balance)
	_update_clock()


func _process(_delta: float) -> void:
	# El reloj no avisa de cada minuto ni de los cambios de velocidad: se lee cada fotograma.
	_update_clock()


## Activa o desactiva la pausa y las velocidades (en modo construcción el tiempo queda
## en pausa).
func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	_update_clock()


func get_pause_button() -> Button:
	return _pause_button


func get_speed_button(index: int) -> Button:
	return _speed_buttons[index]


func get_balance_text() -> String:
	return _balance_label.text


func get_clock_text() -> String:
	return "%s %s · %s" % [_date_label.text, _time_label.text, _payroll_label.text]


## Días que faltan para la próxima nómina contando desde day (0 si es hoy).
static func days_until_payroll(day: int) -> int:
	for payroll_day: int in GameConstants.PAYROLL_DAYS:
		if payroll_day >= day:
			return payroll_day - day
	return GameConstants.DAYS_PER_MONTH - day + GameConstants.PAYROLL_DAYS[0]


func _update_clock() -> void:
	_date_label.text = "%s %d · Mes %d" % [WEEKDAY_NAMES[GameClock.get_weekday()], GameClock.get_day(),
		GameClock.get_month()]
	_time_label.text = "%02d:%02d" % [GameClock.get_hour(), GameClock.get_minute()]
	var days: int = days_until_payroll(GameClock.get_day())
	match days:
		0:
			_payroll_label.text = "Nómina: hoy"
		1:
			_payroll_label.text = "Nómina: mañana"
		_:
			_payroll_label.text = "Nómina en %d días" % days
	_pause_button.set_pressed_no_signal(GameClock.is_paused)
	_pause_button.disabled = not _controls_enabled
	for index: int in range(_speed_buttons.size()):
		_speed_buttons[index].set_pressed_no_signal(not GameClock.is_paused and GameClock.speed_index == index)
		_speed_buttons[index].disabled = not _controls_enabled


## Panel semitransparente con margen interior y esquinas redondeadas (lo usan también
## otros paneles de la interfaz).
static func make_panel() -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(PANEL_RADIUS)
	style.set_content_margin_all(PANEL_PADDING)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _add_toggle(parent: Container, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(52, 32)
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button


func _on_balance_changed(balance: int) -> void:
	_balance_label.text = MoneyFormat.format(balance)
	if balance < 0:
		_balance_label.add_theme_color_override("font_color", NEGATIVE_COLOR)
	else:
		_balance_label.remove_theme_color_override("font_color")
