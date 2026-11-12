# El local: el conjunto de casillas que la empresa tiene (hito 25). Empieza como un
# rectángulo y crece al comprar terreno, así que puede quedar con forma de L o de T.
# Tiene has_point como Rect2i para que los sistemas pregunten igual si una casilla es
# del local.
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


## Una copia con más casillas.
func with_cells(cells: Array[Vector2i]) -> Lot:
	var copy := Lot.from_cells(get_cells())
	copy.add_cells(cells)
	return copy


## Bordes del contorno: los que tienen una casilla dentro del local y otra fuera.
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
