# Tarjeta del tutorial (hito 63): arriba, entre los paneles de la izquierda y el reloj,
# muestra el paso actual de Tutorial con «Saltar», y resalta lo que el paso pide con un
# marco y una flecha que se mueve. Lo resaltado lo da target_provider (main.gd: un botón o
# el local en pantalla); de la lista del paso se usa lo primero que se vea. No atrapa clics
# fuera de la tarjeta: el resto de la interfaz sigue igual.
class_name TutorialPanel
extends CanvasLayer

const LAYER: int = 5
const PANEL_WIDTH: float = 420.0
## Dónde empieza la tarjeta respecto del centro de la pantalla (deja libre el panel izquierdo).
const OFFSET_FROM_CENTER: float = -47.0
const MARGIN_TOP: float = 8.0
const TEXT_WIDTH: float = PANEL_WIDTH - 32.0
const HIGHLIGHT_COLOR := Color(1.0, 0.82, 0.25)
const FRAME_GROW: float = 6.0
const FRAME_WIDTH: int = 3
const ARROW_SIZE := Vector2(28.0, 22.0)
const ARROW_GAP: float = 10.0
const ARROW_BOB: float = 6.0

## Rectángulo en pantalla de lo que se resalta (clave de data/tutorial.json), o Rect2() si no se ve.
var target_provider: Callable = func(_key: String) -> Rect2: return Rect2()

var _panel: PanelContainer
var _header: Label
var _text: Label
var _skip_button: Button
var _frame: Panel
var _arrow: Polygon2D
var _target_key: String = ""
var _time: float = 0.0


func _ready() -> void:
	layer = LAYER
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_frame = Panel.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.draw_center = false
	frame_style.border_color = HIGHLIGHT_COLOR
	frame_style.set_border_width_all(FRAME_WIDTH)
	frame_style.set_corner_radius_all(6)
	_frame.add_theme_stylebox_override("panel", frame_style)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_frame)
	_arrow = Polygon2D.new()
	_arrow.color = HIGHLIGHT_COLOR
	# Apunta hacia abajo, con la punta en (0, 0).
	_arrow.polygon = PackedVector2Array([Vector2(-ARROW_SIZE.x / 2.0, -ARROW_SIZE.y), Vector2(ARROW_SIZE.x / 2.0, -ARROW_SIZE.y),
		Vector2.ZERO])
	add_child(_arrow)

	_panel = Hud.make_panel()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = OFFSET_FROM_CENTER
	_panel.offset_right = OFFSET_FROM_CENTER + PANEL_WIDTH
	_panel.offset_top = MARGIN_TOP
	root.add_child(_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	_panel.add_child(rows)
	var header_row := HBoxContainer.new()
	rows.add_child(header_row)
	_header = Label.new()
	_header.add_theme_color_override("font_color", HIGHLIGHT_COLOR)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_header)
	_skip_button = Button.new()
	_skip_button.text = "Saltar"
	_skip_button.tooltip_text = "Cierra el tutorial; se retoma desde Ajustes."
	_skip_button.custom_minimum_size = Vector2(96, 44)
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.pressed.connect(func() -> void: Tutorial.skip())
	header_row.add_child(_skip_button)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	rows.add_child(_text)
	EventBus.tutorial_changed.connect(refresh)
	refresh()


## Vuelve a leer el paso actual.
func refresh() -> void:
	var step: Dictionary = Tutorial.get_current_step()
	_panel.visible = not step.is_empty()
	if step.is_empty():
		_target_key = ""
		_update_highlight()
		return
	_header.text = "Tutorial · paso %d de %d" % [Tutorial.step_index + 1, Tutorial.get_steps().size()]
	_text.text = String(step.get("text", ""))
	_panel.reset_size()
	_update_highlight()


func _process(delta: float) -> void:
	_time += delta
	_update_highlight()


# Busca lo primero que se vea de la lista del paso y pone el marco y la flecha.
func _update_highlight() -> void:
	var rect := Rect2()
	_target_key = ""
	for key: Variant in Tutorial.get_current_step().get("highlight", []):
		rect = target_provider.call(String(key))
		if rect.has_area():
			_target_key = String(key)
			break
	_frame.visible = rect.has_area()
	_arrow.visible = rect.has_area()
	if not rect.has_area():
		return
	var framed: Rect2 = rect.grow(FRAME_GROW)
	_frame.position = framed.position
	_frame.size = framed.size
	# La flecha va del lado con más espacio: arriba de lo que está abajo y al revés.
	var screen_height: float = get_viewport().get_visible_rect().size.y
	var bob: float = sin(_time * 5.0) * ARROW_BOB
	if framed.get_center().y > screen_height / 2.0:
		_arrow.rotation = 0.0
		_arrow.position = Vector2(framed.get_center().x, framed.position.y - ARROW_GAP - bob)
	else:
		_arrow.rotation = PI
		_arrow.position = Vector2(framed.get_center().x, framed.end.y + ARROW_GAP + bob)


func is_showing() -> bool:
	return _panel.visible


func get_text() -> String:
	return _text.text


func get_header() -> String:
	return _header.text


func get_skip_button() -> Button:
	return _skip_button


## Clave de lo resaltado ("" si nada se ve).
func get_target_key() -> String:
	return _target_key


## Rectángulo del marco en pantalla (vacío si no se ve).
func get_frame_rect() -> Rect2:
	return _frame.get_global_rect() if _frame.visible else Rect2()


## Rectángulo de la tarjeta en pantalla.
func get_panel_rect() -> Rect2:
	return _panel.get_global_rect()
