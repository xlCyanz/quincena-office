# Opciones del jugador: ConfigFile aparte de las partidas, con valores por defecto en
# data/settings.json (un valor roto vuelve al suyo). Aplica pantalla completa, escala de la
# interfaz, alto mínimo de los botones y el tema (UiTheme); lo demás (como los volúmenes, que aplica
# Audio) lo leen los sistemas con get_value.
extends Node

const DATA_PATH: String = "res://data/settings.json"
const SECTION: String = "options"

## Archivo de opciones; las pruebas usan otro para no tocar el del jugador.
var path: String = "user://settings.cfg"

var _defaults: Dictionary = {}
var _values: Dictionary = {}
var _data: Dictionary = {}


func _ready() -> void:
	UiTheme.apply()
	load_settings()
	get_tree().node_added.connect(_on_node_added)


## Escalas de la interfaz que se pueden elegir, en % (data/settings.json, ui_scales).
func get_ui_scales() -> Array[int]:
	var scales: Array[int] = []
	for value: Variant in _settings_data().get("ui_scales", [100]):
		scales.append(int(value))
	return scales


## Alto mínimo de un botón en píxeles de la interfaz (data/settings.json).
func get_min_button_height() -> float:
	return float(_settings_data().get("min_button_height", 44))


# Todo botón que entra al árbol mide al menos min_button_height (salvo los de Panku).
func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null or String(button.get_path()).contains("/Panku"):
		return
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, get_min_button_height())


## Valores por defecto (de data/settings.json).
func get_defaults() -> Dictionary:
	if _defaults.is_empty():
		_defaults = _settings_data().get("defaults", {})
	return _defaults


func _settings_data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(DATA_PATH, FileAccess.READ)
		var data: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		if data is Dictionary:
			_data = data
	return _data


## Valor actual de una opción (null si no existe).
func get_value(key: String) -> Variant:
	if _values.is_empty():
		_values = get_defaults().duplicate()
	return _values.get(key)


## Indica si un valor sirve: del tipo del de defecto y, la velocidad, la escala y los volúmenes, entre los que hay.
func is_valid(key: String, value: Variant) -> bool:
	var defaults: Dictionary = get_defaults()
	if not defaults.has(key):
		return false
	var default: Variant = defaults[key]
	if default is bool:
		return value is bool
	if default is float or default is int:
		if not (value is int or value is float) or float(value) != floorf(float(value)):
			return false
		if key == "start_speed":
			return int(value) >= 0 and int(value) < GameConstants.CLOCK_SPEEDS.size()
		if key == "ui_scale":
			return get_ui_scales().has(int(value))
		if key.ends_with("_volume"):
			return int(value) >= 0 and int(value) <= 100
		return true
	return typeof(value) == typeof(default)


## Cambia una opción, la aplica y la guarda. Devuelve false si el valor no sirve.
func set_value(key: String, value: Variant) -> bool:
	if not is_valid(key, value):
		return false
	if get_defaults()[key] is float or get_defaults()[key] is int:
		value = int(value)
	get_value(key)
	_values[key] = value
	_apply(key)
	save_settings()
	EventBus.settings_changed.emit(key)
	return true


## Lee el archivo de opciones (lo que falta o no sirve, por defecto) y las aplica todas.
func load_settings() -> void:
	var defaults: Dictionary = get_defaults()
	_values = defaults.duplicate()
	var config := ConfigFile.new()
	if config.load(path) == OK:
		for key: String in defaults:
			var value: Variant = config.get_value(SECTION, key, defaults[key])
			if is_valid(key, value):
				_values[key] = int(value) if defaults[key] is float or defaults[key] is int else value
	for key: String in _values:
		_apply(key)


## Escribe las opciones actuales. Devuelve false si no se pudo.
func save_settings() -> bool:
	var config := ConfigFile.new()
	for key: String in get_defaults():
		config.set_value(SECTION, key, get_value(key))
	return config.save(path) == OK


## Vuelve todas las opciones a su valor por defecto y las guarda.
func reset_to_defaults() -> void:
	_values = get_defaults().duplicate()
	for key: String in _values:
		_apply(key)
	save_settings()
	for key: String in _values:
		EventBus.settings_changed.emit(key)


func _apply(key: String) -> void:
	if key == "ui_scale":
		# Antes de entrar al árbol se aplica en _ready (load_settings).
		if is_inside_tree():
			get_tree().root.content_scale_factor = float(_values[key]) / 100.0
		return
	if key == "fullscreen":
		# Sin ventana (pruebas) no hay modo que cambiar: queda solo el valor.
		if DisplayServer.get_name() == "headless":
			return
		var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if bool(_values[key]) \
			else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
