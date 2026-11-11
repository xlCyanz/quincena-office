# Dibujo provisional de un mueble sobre las casillas que ocupa, según su forma en el
# catálogo: escritorio (caja con la computadora encima, si tiene), silla (asiento con
# respaldo detrás), planta (maceta y hojas). Va dentro de la capa ordenada por Y.
#
# El respaldo de una silla es una pieza aparte (part = PART_BACKREST) con su propio
# punto de orden: si queda del lado de quien mira, se dibuja delante de quien se sienta.
class_name FurnitureView
extends Node2D

## Cuánto se adelanta hacia atrás el punto de orden del mueble: así un personaje en la
## misma casilla (por ejemplo, sentado en una silla) siempre se dibuja delante.
const SORT_BIAS_PX: float = 1.0
## Grosor del respaldo de la silla y alto extra sobre el asiento, en casillas y píxeles.
const BACKREST_DEPTH: float = 0.18
const BACKREST_HEIGHT_PX: float = 18.0
## Medidas de la computadora sobre el escritorio (en casillas) y del frente marcado.
const MONITOR_WIDTH: float = 0.5
const MONITOR_DEPTH: float = 0.12
const FRONT_MARK_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const POT_COLOR := Color("8a5a3c")
const POT_SIZE: float = 0.4
## Margen del asiento de la silla respecto a su casilla, en casillas.
const SEAT_INSET: float = 0.15

const PART_MAIN: String = ""
const PART_BACKREST: String = "backrest"

var item_id: String = ""
var footprint: Array[Vector2i] = []
var rotation_index: int = 0
var computer_id: String = ""
var part: String = PART_MAIN

var _grid: OfficeGrid
var _info: Dictionary = {}
var _low := Vector2.ZERO  # esquinas de la base en la cuadrícula
var _high := Vector2.ZERO


## Coloca el mueble a partir de su entrada en OfficeState.furniture. piece elige qué
## pieza dibuja este nodo (PART_MAIN o, en una silla, PART_BACKREST).
func setup(grid: OfficeGrid, item: Dictionary, piece: String = PART_MAIN) -> void:
	_grid = grid
	part = piece
	item_id = item["id"]
	rotation_index = item["rotation"]
	computer_id = item.get("computer", "")
	_info = FurnitureCatalog.get_item(item_id)
	footprint = FurnitureCatalog.get_footprint(item_id, item["cell"], rotation_index)
	_low = Vector2(footprint[0])
	_high = Vector2(footprint[0])
	for cell: Vector2i in footprint:
		_low = _low.min(Vector2(cell))
		_high = _high.max(Vector2(cell))
	_low -= Vector2(0.5, 0.5)
	_high += Vector2(0.5, 0.5)
	if String(_info.get("shape", "")) == "chair":
		_low += Vector2(SEAT_INSET, SEAT_INSET)
		_high -= Vector2(SEAT_INSET, SEAT_INSET)
	var sort_point: Vector2 = (_low + _high) / 2.0
	if part == PART_BACKREST:
		var back: Array[Vector2] = _strip(-Vector2(FurnitureCatalog.get_front(rotation_index)), BACKREST_DEPTH)
		sort_point = (back[0] + back[1]) / 2.0
	position = grid.grid_to_world(sort_point) - Vector2(0.0, SORT_BIAS_PX)
	queue_redraw()


## Indica si este mueble necesita además una pieza de respaldo.
static func has_backrest(item_id_to_check: String) -> bool:
	return String(FurnitureCatalog.get_item(item_id_to_check).get("shape", "")) == "chair"


func _draw() -> void:
	var height: float = _info.get("height", 16.0)
	var color: Color = _info.get("color", Color.WHITE)
	var front := Vector2(FurnitureCatalog.get_front(rotation_index))
	match String(_info.get("shape", "desk")):
		"chair":
			if part == PART_BACKREST:
				# Respaldo en el lado contrario al frente.
				var back: Array[Vector2] = _strip(-front, BACKREST_DEPTH)
				_draw_box_raised(back[0], back[1], height, BACKREST_HEIGHT_PX, color.darkened(0.15))
			else:
				IsoBox.draw(self, _corners(_low, _high), height, color)
		"plant":
			var center: Vector2 = (_low + _high) / 2.0
			var half := Vector2(POT_SIZE, POT_SIZE) / 2.0
			IsoBox.draw(self, _corners(center - half, center + half), height, POT_COLOR)
			var top: Vector2 = _local(center) - Vector2(0.0, height + 10.0)
			draw_circle(top, 12.0, color)
			draw_circle(top + Vector2(-7.0, 4.0), 8.0, color.darkened(0.15))
			draw_circle(top + Vector2(7.0, 3.0), 8.0, color.lightened(0.1))
		_:
			IsoBox.draw(self, _corners(_low, _high), height, color)
			# Una franja clara marca el frente (donde se sienta quien lo usa).
			var mark: Array[Vector2] = _strip(front, 0.1)
			var lift := Vector2(0.0, -height - 0.5)
			var points: PackedVector2Array = _corners(mark[0], mark[1])
			for i: int in range(points.size()):
				points[i] += lift
			draw_colored_polygon(points, FRONT_MARK_COLOR)
			if not computer_id.is_empty():
				_draw_computer(front, height)


func _draw_computer(front: Vector2, desk_height: float) -> void:
	var computer: Dictionary = FurnitureCatalog.get_item(computer_id)
	var center: Vector2 = (_low + _high) / 2.0 - front * 0.2
	var across := Vector2(absf(front.y), absf(front.x))  # eje a lo ancho del escritorio
	var size: Vector2 = across * MONITOR_WIDTH + Vector2(absf(front.x), absf(front.y)) * MONITOR_DEPTH
	_draw_box_raised(center - size / 2.0, center + size / 2.0, desk_height,
		float(computer.get("height", 12.0)), computer.get("color", Color.BLACK))


# Franja de la base pegada al lado indicado por direction, con depth casillas de fondo.
func _strip(direction: Vector2, depth: float) -> Array[Vector2]:
	var low: Vector2 = _low
	var high: Vector2 = _high
	if direction.x > 0.0:
		low.x = high.x - depth
	elif direction.x < 0.0:
		high.x = low.x + depth
	elif direction.y > 0.0:
		low.y = high.y - depth
	else:
		high.y = low.y + depth
	return [low, high]


# Caja cuya base está a base_height píxeles sobre el piso.
func _draw_box_raised(low: Vector2, high: Vector2, base_height: float, height: float, color: Color) -> void:
	var corners: PackedVector2Array = _corners(low, high)
	for i: int in range(corners.size()):
		corners[i] += Vector2(0.0, -base_height)
	IsoBox.draw(self, corners, height, color)


func _corners(low: Vector2, high: Vector2) -> PackedVector2Array:
	var corners: PackedVector2Array = IsoBox.grid_rect_corners(_grid, low, high)
	for i: int in range(corners.size()):
		corners[i] -= position
	return corners


func _local(grid_position: Vector2) -> Vector2:
	return _grid.grid_to_world(grid_position) - position
