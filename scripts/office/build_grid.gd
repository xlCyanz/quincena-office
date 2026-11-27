# Bloques de construcción: paredes, puertas, ventanas, pisos y terreno van en bloques de BUILD_BLOCK×BUILD_BLOCK
# casillas (que empiezan en coordenadas múltiplo de BUILD_BLOCK); muebles y personajes siguen en casillas.
# El modelo no cambia (bordes de 1 m de GridEdge): un tramo de bloque son BUILD_BLOCK bordes en línea.
class_name BuildGrid
extends RefCounted


static func size() -> int:
	return GameConstants.BUILD_BLOCK


## Bloque de una casilla (en coordenadas de bloque).
static func block_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / size()), floori(float(cell.y) / size()))


## Casillas de un bloque.
static func block_cells(block: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(size()):
		for x: int in range(size()):
			cells.append(block * size() + Vector2i(x, y))
	return cells


## Indica si el borde está en una línea de bloque (entre dos bloques).
static func is_block_edge(edge: Vector3i) -> bool:
	var coordinate: int = edge.x if edge.z == GridEdge.AXIS_X else edge.y
	return posmod(coordinate + 1, size()) == 0


## Bordes de 1 m del tramo de bloque al que pertenece edge, de menor a mayor x o y.
static func block_segment(edge: Vector3i) -> Array[Vector3i]:
	var step := Vector3i(0, 1, 0) if edge.z == GridEdge.AXIS_X else Vector3i(1, 0, 0)
	var along: int = edge.y if edge.z == GridEdge.AXIS_X else edge.x
	var first: Vector3i = edge - step * posmod(along, size())
	var segment: Array[Vector3i] = []
	for index: int in range(size()):
		segment.append(first + step * index)
	return segment


## Borde de línea de bloque más cercano a un punto de la cuadrícula con decimales.
static func nearest_block_edge(grid_position: Vector2) -> Vector3i:
	# Líneas de bloque: x = k·size − 0.5 (bordes en x) e y = k·size − 0.5 (bordes en y).
	var line_x: float = roundf((grid_position.x + 0.5) / size()) * size() - 0.5
	var line_y: float = roundf((grid_position.y + 0.5) / size()) * size() - 0.5
	var cell := Vector2i(floori(grid_position.x + 0.5), floori(grid_position.y + 0.5))
	if absf(grid_position.x - line_x) <= absf(grid_position.y - line_y):
		return GridEdge.make(Vector2i(roundi(line_x - 0.5), cell.y), GridEdge.AXIS_X)
	return GridEdge.make(Vector2i(cell.x, roundi(line_y - 0.5)), GridEdge.AXIS_Y)


## Rectángulo de casillas agrandado hasta cubrir bloques enteros.
static func snap_rect_to_blocks(rect: Rect2i) -> Rect2i:
	var low: Vector2i = block_of(rect.position) * size()
	var high: Vector2i = (block_of(rect.end - Vector2i.ONE) + Vector2i.ONE) * size()
	return Rect2i(low, high - low)


## Indica si un conjunto de casillas está hecho de bloques enteros.
static func covers_whole_blocks(cells: Array[Vector2i]) -> bool:
	var set: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		set[cell] = true
	for cell: Vector2i in cells:
		for other: Vector2i in block_cells(block_of(cell)):
			if not set.has(other):
				return false
	return true
