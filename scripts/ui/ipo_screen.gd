# Pantalla de cierre al salir a bolsa: estadísticas finales con «Seguir jugando» (modo libre)
# y «Volver al menú». Tapa el juego.
class_name IpoScreen
extends CanvasLayer

## Se pulsó «Seguir jugando».
signal continue_requested
## Se pulsó «Volver al menú».
signal menu_requested

const LAYER: int = 20
const PANEL_WIDTH: float = 520.0
const TITLE_FONT_SIZE: int = 32
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.7)
const TITLE_COLOR := UiTheme.POSITIVE

var _cover: ColorRect
var _title: Label
var _subtitle: Label
var _stats: Label
var _continue_button: Button
var _menu_button: Button


func _ready() -> void:
	layer = LAYER
	_cover = ColorRect.new()
	_cover.color = DIM_COLOR
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Atrapa los clics para que no se toque el juego de atrás.
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(center)
	var panel: PanelContainer = Hud.make_panel()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	panel.add_child(rows)
	_title = Label.new()
	_title.text = "¡Salida a bolsa!"
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_title)
	_subtitle = Label.new()
	_subtitle.text = "La empresa cotiza en bolsa: llegaste a la meta final."
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_subtitle)
	_stats = Label.new()
	rows.add_child(_stats)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	rows.add_child(buttons)
	_continue_button = Button.new()
	_continue_button.text = "Seguir jugando"
	_continue_button.custom_minimum_size = Vector2(0, 44)
	_continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_button.pressed.connect(func() -> void:
		_cover.visible = false
		continue_requested.emit())
	buttons.add_child(_continue_button)
	_menu_button = Button.new()
	_menu_button.text = "Volver al menú"
	_menu_button.custom_minimum_size = Vector2(0, 44)
	_menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_button.pressed.connect(func() -> void: menu_requested.emit())
	buttons.add_child(_menu_button)
	_cover.visible = false


## Muestra la pantalla con las estadísticas de EventBus.went_public.
func show_stats(stats: Dictionary) -> void:
	_stats.text = "\n".join([
		"Días jugados: %d" % int(stats.get("days", 0)),
		"Empleados contratados: %d (hoy %d)" % [int(stats.get("hired", 0)), int(stats.get("employees", 0))],
		"Contratos entregados: %d" % int(stats.get("delivered", 0)),
		"Productos lanzados: %d" % int(stats.get("launched", 0)),
		"Valor de la empresa: %s" % MoneyFormat.format(int(stats.get("value", 0))),
		"Mejor reputación: %s" % ProjectsPanel.describe_reputation(float(stats.get("best_reputation", 1.0))),
	])
	_cover.visible = true


func is_open() -> bool:
	return _cover.visible


func get_text() -> String:
	return "\n".join([_title.text, _subtitle.text, _stats.text])


func get_continue_button() -> Button:
	return _continue_button


func get_menu_button() -> Button:
	return _menu_button
