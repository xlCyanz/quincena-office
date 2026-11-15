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
## Segundo monitor: ancho y cuánto se aparta del centro del escritorio.
const SECOND_MONITOR_WIDTH: float = 0.3
const SECOND_MONITOR_OFFSET: float = 0.3
const FRONT_MARK_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const POT_COLOR := Color("8a5a3c")
const POT_SIZE: float = 0.4
## Margen del asiento de la silla respecto a su casilla, en casillas.
const SEAT_INSET: float = 0.15
## Objetos de pared (hito 45): ancho a lo largo de la pared y fondo, en casillas, y a qué
## altura de la pared empiezan, en píxeles.
const WALL_ITEM_WIDTH: float = 0.5
const WALL_ITEM_DEPTH: float = 0.06
const WALL_ITEM_BASE_PX: float = 24.0
## En una pared baja el objeto se dibuja pegado abajo y no más alto que la pared.
const LOW_WALL_ITEM_BASE_PX: float = 1.0
## Lámpara de pie: grosor del poste (en casillas) y radio de la pantalla (en píxeles).
const LAMP_POLE: float = 0.08
const LAMP_SHADE_RADIUS: float = 9.0
const LAMP_POLE_COLOR := Color("5a5148")

## Muebles chicos: ocupan un cuarto de su casilla y sus hojas y pantallas se dibujan a esta escala.
const SMALL_SCALE: float = 0.6

const PART_MAIN: String = ""
const PART_BACKREST: String = "backrest"

var item_id: String = ""
var footprint: Array[Vector2i] = []
var rotation_index: int = 0
var computer_id: String = ""
## Segundo monitor del escritorio ("" si no tiene; hito 46).
var monitor_id: String = ""
var part: String = PART_MAIN
## Cuarto de la casilla de un mueble chico (0–3), o -1.
var quarter: int = -1

var _grid: OfficeGrid
var _info: Dictionary = {}
var _low := Vector2.ZERO  # esquinas de la base en la cuadrícula
var _high := Vector2.ZERO
var _scale: float = 1.0
# Objeto de pared en una pared baja (no de atrás).
var _on_low_wall: bool = false


## Coloca el mueble a partir de su entrada en OfficeState.furniture. piece elige qué
## pieza dibuja este nodo (PART_MAIN o, en una silla, PART_BACKREST).
func setup(grid: OfficeGrid, item: Dictionary, piece: String = PART_MAIN) -> void:
	_grid = grid
	part = piece
	item_id = item["id"]
	rotation_index = item["rotation"]
	computer_id = item.get("computer", "")
	monitor_id = item.get("monitor", "")
	_info = FurnitureCatalog.get_item(item_id)
	footprint = FurnitureCatalog.get_footprint(item_id, item["cell"], rotation_index)
	if FurnitureCatalog.is_wall_mounted(item_id):
		_setup_wall_item(item["cell"])
		return
	_low = Vector2(footprint[0])
	_high = Vector2(footprint[0])
	for cell: Vector2i in footprint:
		_low = _low.min(Vector2(cell))
		_high = _high.max(Vector2(cell))
	_low -= Vector2(0.5, 0.5)
	_high += Vector2(0.5, 0.5)
	quarter = FurnitureCatalog.get_quarter(item)
	_scale = 1.0
	if quarter >= 0:
		var center: Vector2 = Vector2(footprint[0]) + FurnitureCatalog.get_quarter_offset(quarter)
		_low = center - Vector2(0.25, 0.25)
		_high = center + Vector2(0.25, 0.25)
		_scale = SMALL_SCALE
	if String(_info.get("shape", "")) == "chair":
		_low += Vector2(SEAT_INSET, SEAT_INSET)
		_high -= Vector2(SEAT_INSET, SEAT_INSET)
	var sort_point: Vector2 = (_low + _high) / 2.0
	if String(_info.get("shape", "")) == "rug":
		# Se pisa: se dibuja antes que quien camina encima.
		sort_point = _low
	if part == PART_BACKREST:
		var back: Array[Vector2] = _strip(-Vector2(FurnitureCatalog.get_front(rotation_index)), BACKREST_DEPTH)
		sort_point = (back[0] + back[1]) / 2.0
	position = grid.grid_to_world(sort_point) - Vector2(0.0, SORT_BIAS_PX)
	queue_redraw()


# Un objeto de pared es una placa delgada pegada a la cara de la pared, del lado de su
# casilla (la pared queda detrás de su frente).
func _setup_wall_item(cell: Vector2i) -> void:
	_on_low_wall = not _grid.is_back_edge(FurnitureCatalog.get_wall_edge(cell, rotation_index))
	var front := Vector2(FurnitureCatalog.get_front(rotation_index))
	var center: Vector2 = Vector2(cell) - front * 0.5 + front * (EdgePieceView.THICKNESS / 2.0 + WALL_ITEM_DEPTH / 2.0)
	var across := Vector2(absf(front.y), absf(front.x))
	var half: Vector2 = across * (WALL_ITEM_WIDTH / 2.0) + Vector2(absf(front.x), absf(front.y)) * (WALL_ITEM_DEPTH / 2.0)
	_low = center - half
	_high = center + half
	position = _grid.grid_to_world(center + front * 0.1)
	queue_redraw()


## Indica si este mueble necesita además una pieza de respaldo.
static func has_backrest(item_id_to_check: String) -> bool:
	return String(FurnitureCatalog.get_item(item_id_to_check).get("shape", "")) == "chair"


func _draw() -> void:
	var height: float = _info.get("height", 16.0)
	var color: Color = _info.get("color", Color.WHITE)
	var front := Vector2(FurnitureCatalog.get_front(rotation_index))
	if FurnitureCatalog.is_wall_mounted(item_id):
		if _on_low_wall:
			var cap: float = ConstructionCatalog.get_low_wall_height() - LOW_WALL_ITEM_BASE_PX - 1.0
			_draw_box_raised(_low, _high, LOW_WALL_ITEM_BASE_PX, minf(height, cap), color)
		else:
			_draw_box_raised(_low, _high, WALL_ITEM_BASE_PX, height, color)
		return
	match String(_info.get("shape", "desk")):
		"chair":
			if part == PART_BACKREST:
				# Respaldo en el lado contrario al frente.
				var back: Array[Vector2] = _strip(-front, BACKREST_DEPTH)
				_draw_box_raised(back[0], back[1], height, BACKREST_HEIGHT_PX, color.darkened(0.15))
			else:
				IsoBox.draw(self, _corners(_low, _high), height, color)
		"rug":
			IsoBox.draw(self, _corners(_low + Vector2(0.1, 0.1), _high - Vector2(0.1, 0.1)), height, color)
		"lamp":
			var middle: Vector2 = (_low + _high) / 2.0
			var pole := Vector2(LAMP_POLE, LAMP_POLE) / 2.0
			IsoBox.draw(self, _corners(middle - pole, middle + pole), height, LAMP_POLE_COLOR)
			draw_circle(_local(middle) - Vector2(0.0, height), LAMP_SHADE_RADIUS * _scale, color)
		"plant":
			var center: Vector2 = (_low + _high) / 2.0
			var half := Vector2(POT_SIZE, POT_SIZE) / 2.0 * (0.5 if quarter >= 0 else 1.0)
			IsoBox.draw(self, _corners(center - half, center + half), height, POT_COLOR)
			var s: float = _scale
			var top: Vector2 = _local(center) - Vector2(0.0, height + 10.0 * s)
			draw_circle(top, 12.0 * s, color)
			draw_circle(top + Vector2(-7.0, 4.0) * s, 8.0 * s, color.darkened(0.15))
			draw_circle(top + Vector2(7.0, 3.0) * s, 8.0 * s, color.lightened(0.1))
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
	var depth: Vector2 = Vector2(absf(front.x), absf(front.y)) * MONITOR_DEPTH
	if not monitor_id.is_empty():
		# Con segundo monitor, la computadora se corre a un lado y el monitor va al otro.
		var monitor: Dictionary = FurnitureCatalog.get_item(monitor_id)
		var monitor_center: Vector2 = center + across * SECOND_MONITOR_OFFSET
		var monitor_size: Vector2 = across * SECOND_MONITOR_WIDTH + depth
		center -= across * SECOND_MONITOR_OFFSET * 0.5
		_draw_box_raised(monitor_center - monitor_size / 2.0, monitor_center + monitor_size / 2.0, desk_height,
			float(monitor.get("height", 10.0)), monitor.get("color", Color.BLACK))
	var size: Vector2 = across * MONITOR_WIDTH + depth
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
