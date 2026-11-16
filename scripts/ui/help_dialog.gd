# Cuadro de ayuda con título y texto de data/help.json (lo abren los botones «?»).
# No pausa; se cierra con «Entendido» o Esc.
class_name HelpDialog
extends CanvasLayer

const HELP_PATH: String = "res://data/help.json"
const LAYER: int = 12
const PANEL_WIDTH: float = 480.0
const TEXT_WIDTH: float = PANEL_WIDTH - 32.0
const TITLE_FONT_SIZE: int = 24

var _panel: PanelContainer
var _title: Label
var _text: Label
var _close_button: Button
var _topic: String = ""
var _data: Dictionary = {}


func _ready() -> void:
	layer = LAYER
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = Hud.make_panel()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	root.add_child(_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_panel.add_child(rows)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	rows.add_child(_title)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	rows.add_child(_text)
	_close_button = Button.new()
	_close_button.text = "Entendido"
	_close_button.custom_minimum_size = Vector2(0, 44)
	_close_button.pressed.connect(close)
	rows.add_child(_close_button)
	_panel.visible = false
	EventBus.help_requested.connect(show_topic)


## Muestra la ayuda de un tema; un tema desconocido no hace nada.
func show_topic(topic: String) -> void:
	var entry: Dictionary = get_topics().get(topic, {})
	if entry.is_empty():
		return
	_topic = topic
	_title.text = String(entry.get("title", ""))
	_text.text = String(entry.get("text", ""))
	_panel.visible = true
	_fit()
	_fit.call_deferred()


func _fit() -> void:
	_panel.reset_size()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func close() -> void:
	_panel.visible = false
	_topic = ""


func is_open() -> bool:
	return _panel.visible


## Tema abierto ("" si está cerrada).
func get_topic() -> String:
	return _topic


func get_title() -> String:
	return _title.text


func get_text() -> String:
	return _text.text


func get_close_button() -> Button:
	return _close_button


## Rectángulo del cuadro en pantalla (para comprobar que cabe).
func get_panel_rect() -> Rect2:
	return _panel.get_global_rect()


## Temas de data/help.json: clave → {"title", "text"}.
func get_topics() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HELP_PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data.get("topics", {})
