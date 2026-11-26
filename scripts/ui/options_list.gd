# Controles de las opciones (Ajustes y menú principal): sí/no, velocidad inicial, escala, volúmenes y
# «Valores por defecto». Cada cambio va a Settings y los controles siguen sus cambios.
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
	"console_overlay": "Mostrar la consola de desarrollo sobre el juego",
}
## Volúmenes (0 a 100 %), en orden, con su texto.
const VOLUMES: Dictionary[String, String] = {
	"master_volume": "Volumen general",
	"music_volume": "Música",
	"sfx_volume": "Efectos",
}
const VOLUME_STEP: float = 5.0
const VOLUME_SLIDER_WIDTH: float = 180.0
const VOLUME_VALUE_WIDTH: float = 52.0
## Opciones que solo existen con la consola de desarrollo.
const DEV_TOGGLES: Array[String] = ["console_overlay"]

var _toggles: Dictionary[String, CheckBox] = {}
var _speed_button: OptionButton
var _scale_button: OptionButton
var _reset_button: Button
var _volume_sliders: Dictionary[String, HSlider] = {}
var _volume_labels: Dictionary[String, Label] = {}


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
	# Escala de la interfaz.
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
	for key: String in VOLUMES:
		_add_volume_row(key)
	_reset_button = Button.new()
	_reset_button.text = "Valores por defecto"
	_reset_button.pressed.connect(Settings.reset_to_defaults)
	add_child(_reset_button)


func _add_volume_row(key: String) -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = VOLUMES[key]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = VOLUME_STEP
	slider.custom_minimum_size = Vector2(VOLUME_SLIDER_WIDTH, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = "%s: 0 es silencio" % VOLUMES[key]
	slider.value_changed.connect(func(value: float) -> void: Settings.set_value(key, roundi(value)))
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = VOLUME_VALUE_WIDTH
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_volume_sliders[key] = slider
	_volume_labels[key] = value_label


func _ready() -> void:
	# Sin consola (una exportación) su opción no se muestra.
	var has_console: bool = OS.is_debug_build() and get_tree().root.has_node("Panku")
	for key: String in DEV_TOGGLES:
		_toggles[key].visible = has_console
	EventBus.settings_changed.connect(func(_key: String) -> void: refresh())
	refresh()


## Pone los controles según las opciones, sin guardarlas.
func refresh() -> void:
	for key: String in _toggles:
		_toggles[key].set_pressed_no_signal(bool(Settings.get_value(key)))
	_speed_button.select(int(Settings.get_value("start_speed")))
	_scale_button.select(Settings.get_ui_scales().find(int(Settings.get_value("ui_scale"))))
	for key: String in _volume_sliders:
		var value: int = int(Settings.get_value(key))
		_volume_sliders[key].set_value_no_signal(value)
		_volume_labels[key].text = "%d %%" % value


func get_scale_button() -> OptionButton:
	return _scale_button


func get_toggle(key: String) -> CheckBox:
	return _toggles[key]


func get_speed_button() -> OptionButton:
	return _speed_button


func get_volume_slider(key: String) -> HSlider:
	return _volume_sliders[key]


func get_reset_button() -> Button:
	return _reset_button
