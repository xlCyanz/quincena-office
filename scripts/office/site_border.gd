# Línea discontinua que marca el límite del solar (el mapa que se puede comprar). Va
# sobre el piso y debajo de muebles y personajes.
class_name SiteBorder
extends Node2D

var _corners := PackedVector2Array()
var _color := Color.WHITE
var _width: float = 2.0
var _dash: float = 16.0


## Toma el solar y lo dibuja con la orientación actual de la cuadrícula.
func setup(grid: OfficeGrid, site: Rect2i) -> void:
	var data: Dictionary = MapDecor.get_data().get("border", {})
	_color = Color(String(data.get("color", "ffffff")), float(data.get("alpha", 0.6)))
	_width = float(data.get("width", 2.0))
	_dash = float(data.get("dash_cells", 0.5)) * GameConstants.TILE_SIZE.x / 2.0
	_corners = PackedVector2Array()
	if site.size != Vector2i.ZERO:
		var low: Vector2 = Vector2(site.position) - Vector2(0.5, 0.5)
		var high: Vector2 = Vector2(site.end) - Vector2(0.5, 0.5)
		_corners = IsoBox.grid_rect_corners(grid, low, high)
	queue_redraw()


## Esquinas del borde en píxeles del mundo (para las pruebas).
func get_corners() -> PackedVector2Array:
	return _corners


func _draw() -> void:
	if _corners.size() != 4:
		return
	for i: int in range(4):
		draw_dashed_line(_corners[i], _corners[(i + 1) % 4], _color, _width, _dash)
