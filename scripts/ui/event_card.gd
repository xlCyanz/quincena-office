# Tarjeta de evento (diseño 10 y 12; hito 43): a la derecha, bajo el reloj, plegable. Muestra
# el título, el texto, una opción por botón con lo que hace y la cuenta atrás. Elegir llama
# a Events.choose; si se acaba el tiempo, Events elige al azar. Se construye en código.
class_name EventCard
extends CanvasLayer

const PANEL_WIDTH: float = 360.0
const MARGIN: float = 12.0
const MARGIN_TOP: float = 132.0
const TITLE_FONT_SIZE: int = 18
const MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const URGENT_SECONDS: float = 30.0
const URGENT_COLOR := Color(1.0, 0.55, 0.4)

var _panel: PanelContainer
var _header: Label
var _fold_button: Button
var _body: VBoxContainer
var _title: Label
var _text: Label
var _options: VBoxContainer
var _option_buttons: Array[Button] = []
var _folded: bool = false
var _shown_event: String = ""


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
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	_panel.add_child(rows)
	var top := HBoxContainer.new()
	rows.add_child(top)
	_header = Label.new()
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	_fold_button = Button.new()
	_fold_button.focus_mode = Control.FOCUS_NONE
	_fold_button.pressed.connect(func() -> void: set_folded(not _folded))
	top.add_child(_fold_button)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	rows.add_child(_body)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_title)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_color_override("font_color", MUTED_COLOR)
	_body.add_child(_text)
	_options = VBoxContainer.new()
	_body.add_child(_options)
	EventBus.event_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if _panel.visible:
		_update_header()


## Pliega (solo la cabecera con la cuenta atrás) o despliega la tarjeta.
func set_folded(folded: bool) -> void:
	_folded = folded
	_refresh()


func is_folded() -> bool:
	return _folded


func is_showing() -> bool:
	return _panel.visible


## Botones de las opciones, en orden (para las pruebas).
func get_option_buttons() -> Array[Button]:
	return _option_buttons


func get_fold_button() -> Button:
	return _fold_button


func get_text() -> String:
	return "%s\n%s\n%s" % [_header.text, _title.text, _text.text]


func _refresh() -> void:
	if _panel == null:
		return
	var card: Dictionary = Events.card
	_panel.visible = not card.is_empty()
	if card.is_empty():
		_shown_event = ""
		return
	# Un evento nuevo llega desplegado.
	var key: String = "%s:%s" % [card["event_id"], card["text"]]
	if key != _shown_event:
		_shown_event = key
		_folded = false
	_body.visible = not _folded
	_fold_button.text = "+" if _folded else "−"
	_title.text = card["title"]
	_text.text = card["text"]
	for child: Node in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	_option_buttons.clear()
	for index: int in range((card["options"] as Array).size()):
		var option: Dictionary = card["options"][index]
		var button := Button.new()
		var effects: String = Events.describe_effects(option["effects"])
		button.text = option["label"] if effects.is_empty() else "%s (%s)" % [option["label"], effects]
		button.focus_mode = Control.FOCUS_NONE
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(func() -> void: Events.choose(index))
		_options.add_child(button)
		_option_buttons.append(button)
	_update_header()


func _update_header() -> void:
	if Events.card.is_empty():
		return
	var running: bool = GameClock.is_processing() and not GameClock.is_paused
	_header.text = "Evento · elige en %s%s" % [Events.describe_countdown(), "" if running else " (en pausa)"]
	var urgent: bool = float(Events.card["seconds_left"]) <= URGENT_SECONDS
	if urgent:
		_header.add_theme_color_override("font_color", URGENT_COLOR)
	else:
		_header.remove_theme_color_override("font_color")
	if _folded:
		_header.text += " · " + String(Events.card["title"])
