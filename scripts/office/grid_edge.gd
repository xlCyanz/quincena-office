# Bordes entre casillas, donde van las paredes y las puertas (no ocupan casilla).
# Un borde es un Vector3i(x, y, eje): eje AXIS_X es el borde entre (x, y) y (x+1, y);
# eje AXIS_Y, el borde entre (x, y) y (x, y+1). Se usa por su nombre de clase.
class_name GridEdge
extends RefCounted

const AXIS_X: int = 0
const AXIS_Y: int = 1


static func make(cell: Vector2i, axis: int) -> Vector3i:
	return Vector3i(cell.x, cell.y, axis)


## Las dos casillas que separa el borde.
static func get_cells(edge: Vector3i) -> Array[Vector2i]:
	var a := Vector2i(edge.x, edge.y)
	var b: Vector2i = a + (Vector2i(1, 0) if edge.z == AXIS_X else Vector2i(0, 1))
	return [a, b]


## Borde entre dos casillas vecinas (en las cuatro direcciones).
static func between(a: Vector2i, b: Vector2i) -> Vector3i:
	var low := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	return make(low, AXIS_X if a.y == b.y else AXIS_Y)


## Extremos del borde en coordenadas de cuadrícula con decimales (las esquinas de las casillas).
static func get_endpoints(edge: Vector3i) -> Array[Vector2]:
	if edge.z == AXIS_X:
		return [Vector2(edge.x + 0.5, edge.y - 0.5), Vector2(edge.x + 0.5, edge.y + 0.5)]
	return [Vector2(edge.x - 0.5, edge.y + 0.5), Vector2(edge.x + 0.5, edge.y + 0.5)]


## Indica si el borde toca el local (al menos una de sus casillas está dentro).
static func touches_lot(edge: Vector3i, lot: Rect2i) -> bool:
	var cells: Array[Vector2i] = get_cells(edge)
	return lot.has_point(cells[0]) or lot.has_point(cells[1])


## Indica si el borde está en el contorno del local (una casilla dentro y otra fuera).
static func is_exterior(edge: Vector3i, lot: Rect2i) -> bool:
	var cells: Array[Vector2i] = get_cells(edge)
	return lot.has_point(cells[0]) != lot.has_point(cells[1])


## Todos los bordes del contorno del local.
static func get_lot_outline(lot: Rect2i) -> Array[Vector3i]:
	var edges: Array[Vector3i] = []
	for x: int in range(lot.position.x, lot.end.x):
		edges.append(make(Vector2i(x, lot.position.y - 1), AXIS_Y))
		edges.append(make(Vector2i(x, lot.end.y - 1), AXIS_Y))
	for y: int in range(lot.position.y, lot.end.y):
		edges.append(make(Vector2i(lot.position.x - 1, y), AXIS_X))
		edges.append(make(Vector2i(lot.end.x - 1, y), AXIS_X))
	return edges


## Borde más cercano a un punto de la cuadrícula con decimales.
static func nearest(grid_position: Vector2) -> Vector3i:
	var cell := Vector2i(floori(grid_position.x + 0.5), floori(grid_position.y + 0.5))
	var u: float = grid_position.x + 0.5 - cell.x
	var v: float = grid_position.y + 0.5 - cell.y
	var best: float = minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
	if best == u:
		return make(cell + Vector2i(-1, 0), AXIS_X)
	if best == 1.0 - u:
		return make(cell, AXIS_X)
	if best == v:
		return make(cell + Vector2i(0, -1), AXIS_Y)
	return make(cell, AXIS_Y)


## Distancia (en casillas) de un punto de la cuadrícula a la línea de un borde.
static func distance_to(edge: Vector3i, grid_position: Vector2) -> float:
	var ends: Array[Vector2] = get_endpoints(edge)
	return Geometry2D.get_closest_point_to_segment(grid_position, ends[0], ends[1]).distance_to(grid_position)


## Convierte a [x, y, "x"|"y"] para guardarlo en JSON.
static func to_data(edge: Vector3i) -> Array:
	return [edge.x, edge.y, "x" if edge.z == AXIS_X else "y"]


## Convierte desde [x, y, "x"|"y"].
static func from_data(data: Array) -> Vector3i:
	return Vector3i(int(data[0]), int(data[1]), AXIS_X if String(data[2]) == "x" else AXIS_Y)
