# El local: conjunto de casillas de la empresa; crece con terreno (puede quedar en L o T).
# has_point como Rect2i.
class_name Lot
extends RefCounted

var _cells: Dictionary[Vector2i, bool] = {}
var _bounds := Rect2i()


static func from_rect(rect: Rect2i) -> Lot:
	var lot := Lot.new()
	for x: int in range(rect.position.x, rect.end.x):
		for y: int in range(rect.position.y, rect.end.y):
			lot._cells[Vector2i(x, y)] = true
	lot._bounds = rect
	return lot


static func from_cells(cells: Array[Vector2i]) -> Lot:
	var lot := Lot.new()
	lot.add_cells(cells)
	return lot


## Suma casillas al local.
func add_cells(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		if _cells.is_empty():
			_bounds = Rect2i(cell, Vector2i.ONE)
		_cells[cell] = true
		_bounds = _bounds.merge(Rect2i(cell, Vector2i.ONE))


## Indica si la casilla es del local.
func has_point(cell: Vector2i) -> bool:
	return _cells.has(cell)


func has_area() -> bool:
	return not _cells.is_empty()


## Metros cuadrados del local (una casilla = 1 m²).
func get_area() -> int:
	return _cells.size()


## Rectángulo más chico que encierra todo el local.
func get_bounds() -> Rect2i:
	return _bounds


## Casillas del local, ordenadas.
func get_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = _cells.keys()
	cells.sort()
	return cells


## Copia con más casillas.
func with_cells(cells: Array[Vector2i]) -> Lot:
	var copy := Lot.from_cells(get_cells())
	copy.add_cells(cells)
	return copy


## Copia sin esas casillas.
func without_cells(cells: Array[Vector2i]) -> Lot:
	var copy := Lot.new()
	var removed: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		removed[cell] = true
	var kept: Array[Vector2i] = []
	for cell: Vector2i in get_cells():
		if not removed.has(cell):
			kept.append(cell)
	copy.add_cells(kept)
	return copy


## Indica si todas las casillas están unidas por sus lados (un local vacío no lo está).
func is_joined() -> bool:
	if _cells.is_empty():
		return false
	var first: Vector2i = _cells.keys()[0]
	var found: Dictionary[Vector2i, bool] = {first: true}
	var queue: Array[Vector2i] = [first]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = cell + direction
			if _cells.has(next) and not found.has(next):
				found[next] = true
				queue.append(next)
	return found.size() == _cells.size()


## Bordes del contorno (una casilla dentro y otra fuera).
func get_outline() -> Array[Vector3i]:
	var edges: Array[Vector3i] = []
	for cell: Vector2i in get_cells():
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			if not _cells.has(cell + direction):
				edges.append(GridEdge.between(cell, cell + direction))
	return edges


## Indica si el local es igual a otro.
func equals(other: Lot) -> bool:
	return get_cells() == other.get_cells()


## Para guardar: [[x, y], ...].
func to_data() -> Array:
	var data: Array = []
	for cell: Vector2i in get_cells():
		data.append([cell.x, cell.y])
	return data
