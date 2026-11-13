# Reglas comunes para que la interfaz quepa en pantalla con cualquier escala (hito 65).
# BuildPanel mide la barra de menús de abajo y guarda en bottom_space cuánto alto reserva;
# los paneles de los lados se acomodan con fit_side_panel al recibir EventBus.ui_layout_changed.
class_name UiLayout
extends RefCounted

## Margen entre los paneles y el borde de la pantalla.
const MARGIN: float = 16.0
## Separación entre un panel y la barra de menús.
const BAR_GAP: float = 8.0

## Alto que hay que dejar libre abajo para la barra de menús (y su margen).
static var bottom_space: float = 76.0
## Alto que ocupan arriba el dinero y el reloj (Hud), con su separación.
static var top_space: float = 100.0


## Ancho de un panel lateral: el que quiere, sin pasar del ancho de la pantalla.
static func side_width(viewport_size: Vector2, wanted: float) -> float:
	return minf(wanted, viewport_size.x - MARGIN * 2.0)


## Pone un panel lateral izquierdo (anclado arriba y abajo) a su ancho y sobre la barra.
static func fit_left_panel(panel: Control, wanted_width: float) -> void:
	panel.offset_right = panel.offset_left + side_width(panel.get_viewport_rect().size, wanted_width)
	panel.offset_bottom = -bottom_space


## Alto que queda para un panel que empieza en top sin tapar la barra de menús.
static func available_height(viewport_size: Vector2, top: float) -> float:
	return viewport_size.y - top - bottom_space
