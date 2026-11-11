# Caminos sobre la cuadrícula lógica con AStarGrid2D. Solo se mueve en las cuatro
# direcciones de la cuadrícula (sin diagonales), que en pantalla son las diagonales
# isométricas. Se recalcula cada vez que cambia la oficina.
class_name OfficePathfinder
extends RefCounted

var _astar := AStarGrid2D.new()


## Prepara la cuadrícula: el local entero es transitable salvo las casillas bloqueadas.
func build(lot_rect: Rect2i, blocked_cells: Array[Vector2i]) -> void:
	_astar.region = lot_rect
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()
	for cell: Vector2i in blocked_cells:
		if lot_rect.has_point(cell):
			_astar.set_point_solid(cell, true)


## Indica si se puede pisar una casilla.
func is_walkable(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell)


## Camino de casillas desde from hasta to, ambas incluidas. Devuelve una lista vacía si
## no hay camino. El destino puede estar bloqueado (por ejemplo, una silla): se permite
## llegar a él, pero no atravesarlo.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _astar.is_in_boundsv(from) or not _astar.is_in_boundsv(to):
		return result
	var to_was_solid: bool = _astar.is_point_solid(to)
	var from_was_solid: bool = _astar.is_point_solid(from)
	_astar.set_point_solid(to, false)
	_astar.set_point_solid(from, false)
	result.assign(_astar.get_id_path(from, to))
	_astar.set_point_solid(to, to_was_solid)
	_astar.set_point_solid(from, from_was_solid)
	return result
