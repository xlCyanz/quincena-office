# Pantalla de fin de partida: el embargo no cubrió la deuda. Muestra por qué se perdió,
# las estadísticas y un botón al menú; tapa todo el juego.
class_name GameOverScreen
extends CanvasLayer

## Se pulsó «Volver al menú».
signal menu_requested

const LAYER: int = 20
const PANEL_WIDTH: float = 520.0
const TITLE_FONT_SIZE: int = 32
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.7)

var _cover: ColorRect
var _title: Label
var _reason: Label
var _stats: Label
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
	_title.text = "La empresa quebró"
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_color", Hud.NEGATIVE_COLOR)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_title)
	_reason = Label.new()
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_reason)
	_stats = Label.new()
	rows.add_child(_stats)
	_menu_button = Button.new()
	_menu_button.text = "Volver al menú"
	_menu_button.custom_minimum_size = Vector2(0, 44)
	_menu_button.pressed.connect(func() -> void: menu_requested.emit())
	rows.add_child(_menu_button)
	_cover.visible = false


## Muestra la pantalla con las estadísticas de EventBus.game_over.
func show_stats(stats: Dictionary) -> void:
	_reason.text = "Tres meses sin pagar las cuotas: el banco embargó la empresa. Lo que valen tus muebles (%s) no alcanza para la deuda (%s)." % [
		MoneyFormat.format(int(stats.get("assets", 0))), MoneyFormat.format(int(stats.get("debt", 0)))]
	_stats.text = "\n".join([
		"Días jugados: %d" % int(stats.get("days", 0)),
		"Empleados contratados: %d" % int(stats.get("hired", 0)),
		"Contratos entregados: %d" % int(stats.get("delivered", 0)),
		"Mejor reputación: %s" % ProjectsPanel.describe_reputation(float(stats.get("best_reputation", 1.0))),
	])
	_cover.visible = true


func is_open() -> bool:
	return _cover.visible


func get_text() -> String:
	return "\n".join([_title.text, _reason.text, _stats.text])


func get_menu_button() -> Button:
	return _menu_button
