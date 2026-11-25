# Sombra de las paredes altas en el piso: una franja en la casilla de adentro, pegada al borde (sprites
# wall_tall_<eje>_shadow). Va sobre el piso y debajo de muebles y personas.
class_name WallShadowOverlay
extends Node2D

var _grid: OfficeGrid
# [casilla, sprite] de cada sombra.
var _shadows: Array[Array] = []


func setup(grid: OfficeGrid) -> void:
	_grid = grid


## Pone una sombra en la casilla de mayor x o y de cada borde alto que la tenga dentro del local.
func set_edges(tall_edges: Array[Vector3i], lot: Lot) -> void:
	_shadows.clear()
	for edge: Vector3i in tall_edges:
		var inside: Vector2i = GridEdge.get_cells(edge)[1]
		var sprite: String = SpriteLibrary.get_wall_shadow_sprite(edge.z)
		if lot.has_point(inside) and not sprite.is_empty():
			_shadows.append([inside, sprite])
	queue_redraw()


## Sombras dibujadas: [[casilla, sprite], …] (para pruebas).
func get_shadows() -> Array[Array]:
	return _shadows


func _draw() -> void:
	for shadow: Array in _shadows:
		SpriteLibrary.draw_shadow(self, shadow[1], _grid.grid_to_world(Vector2(shadow[0])))
