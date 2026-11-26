# Lotes de la herramienta Terreno sobre el piso, bajo paredes y muebles: los que se compran rellenos y
# los propios con su borde punteado (el de bajo el ratón, relleno). Los precios los pone BuildController
# encima de todo. Los datos los da BuildController.set_land_overlay.
class_name LandOverlay
extends Node2D

## Colores: comprable, no comprable, comprable bajo el ratón; borde de un lote propio y propio bajo el ratón.
const PLOT_OK := Color(0.4, 1.0, 0.5, 0.16)
const PLOT_BAD := Color(1.0, 0.35, 0.3, 0.14)
const PLOT_HOVER := Color(0.4, 1.0, 0.5, 0.38)
const PLOT_OWNED_LINE := Color(1.0, 0.8, 0.35, 0.95)
const PLOT_SELL_HOVER := Color(1.0, 0.75, 0.3, 0.3)
## Borde punteado de un lote propio, en px de pantalla.
const LINE_WIDTH_PX: float = 2.0
const DASH_PX: float = 6.0

var _grid: OfficeGrid
var _plots: Array[Dictionary] = []
var _hover: int = -1


func setup(grid: OfficeGrid) -> void:
	_grid = grid


## Lotes (los de Builder.get_land_plots) y el que está bajo el ratón (-1 ninguno).
func set_plots(plots: Array[Dictionary], hover: int) -> void:
	_plots = plots
	_hover = hover
	queue_redraw()


func get_plots() -> Array[Dictionary]:
	return _plots


func _draw() -> void:
	if _grid == null or _plots.is_empty():
		return
	var zoom: float = maxf(get_canvas_transform().get_scale().x, 0.01)
	for index: int in range(_plots.size()):
		var plot: Dictionary = _plots[index]
		var hovered: bool = index == _hover
		var selling: bool = plot["action"] == "sell"
		if selling:
			var rect: Rect2i = plot["rect"]
			var corners: PackedVector2Array = IsoBox.grid_rect_corners(_grid, Vector2(rect.position) - Vector2(0.5, 0.5),
				Vector2(rect.end) - Vector2(0.5, 0.5))
			for i: int in range(corners.size()):
				draw_dashed_line(corners[i], corners[(i + 1) % corners.size()], PLOT_OWNED_LINE, LINE_WIDTH_PX / zoom, DASH_PX / zoom)
			if not hovered:
				continue
		var fill: Color
		if selling:
			fill = PLOT_SELL_HOVER if plot["ok"] else PLOT_BAD
		else:
			fill = PLOT_HOVER if hovered and plot["ok"] else (PLOT_OK if plot["ok"] else PLOT_BAD)
		for cell: Vector2i in plot["marked"]:
			draw_colored_polygon(IsoBox.grid_rect_corners(_grid, Vector2(cell) - Vector2(0.47, 0.47), Vector2(cell) + Vector2(0.47, 0.47)), fill)
