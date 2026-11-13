# Controles de las opciones del jugador (hito 60): casillas de sí o no, la velocidad al
# empezar y «Valores por defecto». Los usan el panel de Ajustes de la partida y el menú
# principal (hito 61). Cada cambio va directo a Settings; los controles siguen a Settings
# cuando cambia desde otro lado.
class_name OptionsList
extends VBoxContainer

## Opciones de sí o no, en orden, con su texto.
const TOGGLES: Dictionary[String, String] = {
	"fullscreen": "Pantalla completa",
	"autosave": "Guardar solo al empezar cada día",
	"pause_on_build": "Pausar al construir",
	"pause_on_focus_loss": "Pausar cuando la ventana pierde el foco",
}

var _toggles: Dictionary[String, CheckBox] = {}
var _speed_button: OptionButton
var _reset_button: Button


func _init() -> void:
	add_theme_constant_override("separation", 6)
	for key: String in TOGGLES:
		var check := CheckBox.new()
		check.text = TOGGLES[key]
		check.custom_minimum_size = Vector2(0, 36)
		check.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
		add_child(check)
		_toggles[key] = check
	var speed_row := HBoxContainer.new()
	add_child(speed_row)
	var speed_label := Label.new()
	speed_label.text = "Velocidad al empezar una partida"
	speed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(speed_label)
	_speed_button = OptionButton.new()
	for speed: float in GameConstants.CLOCK_SPEEDS:
		_speed_button.add_item("%dx" % roundi(speed))
	_speed_button.item_selected.connect(func(index: int) -> void: Settings.set_value("start_speed", index))
	speed_row.add_child(_speed_button)
	_reset_button = Button.new()
	_reset_button.text = "Valores por defecto"
	_reset_button.pressed.connect(Settings.reset_to_defaults)
	add_child(_reset_button)


func _ready() -> void:
	EventBus.settings_changed.connect(func(_key: String) -> void: refresh())
	refresh()


## Pone los controles como están las opciones (sin volver a guardarlas).
func refresh() -> void:
	for key: String in _toggles:
		_toggles[key].set_pressed_no_signal(bool(Settings.get_value(key)))
	_speed_button.select(int(Settings.get_value("start_speed")))


func get_toggle(key: String) -> CheckBox:
	return _toggles[key]


func get_speed_button() -> OptionButton:
	return _speed_button


func get_reset_button() -> Button:
	return _reset_button
