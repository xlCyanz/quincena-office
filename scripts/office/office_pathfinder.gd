# Caminos con AStarGrid2D, solo en las cuatro direcciones de la cuadrícula. A doble resolución:
# la casilla (x, y) es el punto (2x+1, 2y+1) y cada borde el punto intermedio, que la pared bloquea.
class_name OfficePathfinder
extends RefCounted

var _astar := AStarGrid2D.new()
var _lot := Lot.new()
var _origin := Vector2i.ZERO


## Prepara la cuadrícula: el local es transitable salvo blocked y los bordes con pared
## (edges: GridEdge → pieza, como en OfficeState). El contorno está cerrado.
func build(lot: Lot, blocked_cells: Array[Vector2i], edges: Dictionary[Vector3i, String] = {}) -> void:
	_lot = lot
	var bounds: Rect2i = lot.get_bounds()
	_origin = bounds.position
	_astar.region = Rect2i(Vector2i.ZERO, bounds.size * 2 + Vector2i.ONE)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()
	# Rearmado al mismo tamaño, update() no borra lo bloqueado antes.
	_astar.fill_solid_region(_astar.region, false)
	var size: Vector2i = _astar.region.size
	for x: int in range(size.x):
		for y: int in range(size.y):
			var on_corner: bool = x % 2 == 0 and y % 2 == 0
			var on_outline: bool = x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1
			if on_corner or on_outline:
				_astar.set_point_solid(Vector2i(x, y), true)
	# Las casillas del rectángulo fuera del local (local en L) no se pisan.
	for x: int in range(bounds.position.x, bounds.end.x):
		for y: int in range(bounds.position.y, bounds.end.y):
			if not lot.has_point(Vector2i(x, y)):
				_astar.set_point_solid(_cell_point(Vector2i(x, y)), true)
	for cell: Vector2i in blocked_cells:
		if lot.has_point(cell):
			_astar.set_point_solid(_cell_point(cell), true)
	for edge: Vector3i in edges:
		if not ConstructionCatalog.is_door(edges[edge]) and _edge_inside(edge):
			_astar.set_point_solid(_edge_point(edge), true)


## Indica si se puede pisar una casilla.
func is_walkable(cell: Vector2i) -> bool:
	return _lot.has_point(cell) and not _astar.is_point_solid(_cell_point(cell))


## Indica si se puede pasar de una casilla a su vecina.
func can_cross(a: Vector2i, b: Vector2i) -> bool:
	var edge: Vector3i = GridEdge.between(a, b)
	return _edge_inside(edge) and not _astar.is_point_solid(_edge_point(edge))


## Camino de from a to, ambas incluidas; vacío si no hay. Se puede llegar a un destino bloqueado
## (una silla) sin atravesarlo. avoid se trata como bloqueado solo en esta búsqueda.
func find_path(from: Vector2i, to: Vector2i, avoid: Array[Vector2i] = []) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _lot.has_point(from) or not _lot.has_point(to):
		return result
	var avoided: Array[Vector2i] = []
	for cell: Vector2i in avoid:
		var point: Vector2i = _cell_point(cell)
		if cell != from and cell != to and _lot.has_point(cell) and not _astar.is_point_solid(point):
			_astar.set_point_solid(point, true)
			avoided.append(point)
	var from_point: Vector2i = _cell_point(from)
	var to_point: Vector2i = _cell_point(to)
	var to_was_solid: bool = _astar.is_point_solid(to_point)
	var from_was_solid: bool = _astar.is_point_solid(from_point)
	_astar.set_point_solid(to_point, false)
	_astar.set_point_solid(from_point, false)
	var points: Array[Vector2i] = _astar.get_id_path(from_point, to_point)
	_astar.set_point_solid(to_point, to_was_solid)
	_astar.set_point_solid(from_point, from_was_solid)
	for point: Vector2i in avoided:
		_astar.set_point_solid(point, false)
	# Solo los puntos de casilla (los dos valores impares).
	for point: Vector2i in points:
		if point.x % 2 == 1 and point.y % 2 == 1:
			@warning_ignore("integer_division")
			result.append(_origin + (point - Vector2i.ONE) / 2)
	return result


## Casillas alcanzables caminando desde from (incluida); vacío si from no se pisa.
func get_reachable(from: Vector2i) -> Dictionary[Vector2i, bool]:
	var reached: Dictionary[Vector2i, bool] = {}
	if not is_walkable(from):
		return reached
	reached[from] = true
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = cell + direction
			if not reached.has(next) and is_walkable(next) and can_cross(cell, next):
				reached[next] = true
				queue.append(next)
	return reached


func _cell_point(cell: Vector2i) -> Vector2i:
	return (cell - _origin) * 2 + Vector2i.ONE


# Solo los bordes entre dos casillas del local tienen punto.
func _edge_inside(edge: Vector3i) -> bool:
	var cells: Array[Vector2i] = GridEdge.get_cells(edge)
	return _lot.has_point(cells[0]) and _lot.has_point(cells[1])


func _edge_point(edge: Vector3i) -> Vector2i:
	var cells: Array[Vector2i] = GridEdge.get_cells(edge)
	return _cell_point(cells[0]) + (cells[1] - cells[0])
