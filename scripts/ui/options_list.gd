# Controles de las opciones del jugador (hito 60): casillas de sí o no, la velocidad al
# empezar, el tamaño de la interfaz (hito 65) y «Valores por defecto». Los usan el panel de Ajustes de la partida y el menú
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
	"smooth_camera": "Cámara suave",
	"edge_pan": "Mover la cámara con el borde de la pantalla",
}

var _toggles: Dictionary[String, CheckBox] = {}
var _speed_button: OptionButton
var _scale_button: OptionButton
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
	_speed_button.tooltip_text = "Velocidad del reloj al empezar una partida"
	for speed: float in GameConstants.CLOCK_SPEEDS:
		_speed_button.add_item("%dx" % roundi(speed))
	_speed_button.item_selected.connect(func(index: int) -> void: Settings.set_value("start_speed", index))
	speed_row.add_child(_speed_button)
	# Escala de la interfaz (hito 65).
	var scale_row := HBoxContainer.new()
	add_child(scale_row)
	var scale_label := Label.new()
	scale_label.text = "Tamaño de la interfaz"
	scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(scale_label)
	_scale_button = OptionButton.new()
	_scale_button.tooltip_text = "Tamaño de los textos, botones y paneles"
	for percent: int in Settings.get_ui_scales():
		_scale_button.add_item("%d %%" % percent)
	_scale_button.item_selected.connect(func(index: int) -> void:
		Settings.set_value("ui_scale", Settings.get_ui_scales()[index]))
	scale_row.add_child(_scale_button)
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
	_scale_button.select(Settings.get_ui_scales().find(int(Settings.get_value("ui_scale"))))


func get_scale_button() -> OptionButton:
	return _scale_button


func get_toggle(key: String) -> CheckBox:
	return _toggles[key]


func get_speed_button() -> OptionButton:
	return _speed_button


func get_reset_button() -> Button:
	return _reset_button
