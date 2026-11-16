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

## Hacia dónde apunta el +x del modelo de un sprite (el largo de un escritorio) en cada rotación.
const MODEL_X_SIDES: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0), Vector2(0.0, -1.0)]
## Lo más que se corre de lado quien se sienta para quedar frente al teclado, en casillas.
const SEAT_SHIFT_MAX: float = 0.5

## Sprite de un objeto de pared en una pared baja: se achica a esta escala y baja hasta
## quedar pegado al piso (LOW_WALL_ITEM_BASE_PX).
const LOW_WALL_SPRITE_SCALE: float = 0.5
const SALT_WALL_ITEM: int = 71

## Una silla delante del frente de un escritorio o mostrador se dibuja arrimada a él esto
## (en casillas) y mirándolo, con quien se sienta (OfficeCharacter usa lo mismo).
const SEAT_TUCK: float = 0.3

## Grupo de las piezas de las sillas: se redibujan cuando alguien se sienta o se levanta.
const CHAIR_GROUP: String = "chair_views"

const PART_MAIN: String = ""
const PART_BACKREST: String = "backrest"
## Tira de un mueble largo (de 1 casilla de ancho y varias de largo) con sprite: cada casilla
## dibuja su tira del sprite con su propio punto de orden, así una pared o una persona al lado
## de una punta no queda mal ordenada con el mueble entero. La pieza principal es la tira 0.
const PART_SLICE: String = "slice"

var item_id: String = ""
var footprint: Array[Vector2i] = []
var rotation_index: int = 0
var computer_id: String = ""
## Pantalla extra del escritorio ("" si no tiene; hito 46) y cuántas tiene (fase 8).
var monitor_id: String = ""
var monitor_count: int = 0
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
# Punto de apoyo del sprite en la cuadrícula (centro de la casilla de anclaje o del cuarto).
var _anchor := Vector2.ZERO
# En una silla: el respaldo queda detrás del asiento (se dibuja antes y lleva la sombra).
var _back_first: bool = false
# Tira que dibuja esta pieza y cuántas tiene el mueble (1 = se dibuja entero).
# Rotación con la que se dibuja (la silla arrimada a un escritorio lo mira).
var _sprite_rotation: int = 0
var _slice: int = 0
var _slices: int = 1


## Coloca el mueble a partir de su entrada en OfficeState.furniture. piece elige qué
## pieza dibuja este nodo (PART_MAIN o, en una silla, PART_BACKREST).
func setup(grid: OfficeGrid, item: Dictionary, piece: String = PART_MAIN, slice: int = 0) -> void:
	_grid = grid
	part = piece
	_slice = slice
	_slices = get_slice_count(item)
	item_id = item["id"]
	rotation_index = item["rotation"]
	computer_id = item.get("computer", "")
	monitor_id = item.get("monitor", "")
	monitor_count = FurnitureCatalog.get_monitor_count(item)
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
	_anchor = _low
	_low -= Vector2(0.5, 0.5)
	_high += Vector2(0.5, 0.5)
	_sprite_rotation = rotation_index
	if has_backrest(item_id):
		add_to_group(CHAIR_GROUP)
		var desk: Dictionary = OfficeState.get_desk_facing(footprint[0])
		if not desk.is_empty() and not get_sprite().is_empty():
			_sprite_rotation = int(desk["direction"])
			var tuck: Vector2 = Vector2(FurnitureCatalog.get_front(_sprite_rotation)) * SEAT_TUCK + get_seat_shift(footprint[0])
			_anchor += tuck
			_low += tuck
			_high += tuck
	quarter = FurnitureCatalog.get_quarter(item)
	_scale = 1.0
	if quarter >= 0:
		var center: Vector2 = Vector2(footprint[0]) + FurnitureCatalog.get_quarter_offset(quarter)
		_anchor = center
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
	var back: Array[Vector2] = _strip(-Vector2(FurnitureCatalog.get_front(_sprite_rotation)), BACKREST_DEPTH)
	var back_point: Vector2 = (back[0] + back[1]) / 2.0
	_back_first = back_point.x + back_point.y < sort_point.x + sort_point.y
	if part == PART_BACKREST:
		sort_point = back_point
	if _slices > 1:
		sort_point = Vector2(footprint[clampi(_slice, 0, footprint.size() - 1)])
	position = grid.grid_to_world(sort_point) - Vector2(0.0, SORT_BIAS_PX)
	queue_redraw()


# Un objeto de pared es una placa delgada pegada a la cara de la pared, del lado de su
# casilla (la pared queda detrás de su frente).
func _setup_wall_item(cell: Vector2i) -> void:
	_on_low_wall = not _grid.is_tall_edge(FurnitureCatalog.get_wall_edge(cell, rotation_index))
	var front := Vector2(FurnitureCatalog.get_front(rotation_index))
	var center: Vector2 = Vector2(cell) - front * 0.5 + front * (EdgePieceView.THICKNESS / 2.0 + WALL_ITEM_DEPTH / 2.0)
	var across := Vector2(absf(front.y), absf(front.x))
	var half: Vector2 = across * (WALL_ITEM_WIDTH / 2.0) + Vector2(absf(front.x), absf(front.y)) * (WALL_ITEM_DEPTH / 2.0)
	_low = center - half
	_high = center + half
	# El sprite se apoya en el punto medio del borde, en el piso.
	_anchor = Vector2(cell) - front * 0.5
	position = _grid.grid_to_world(center + front * 0.1)
	queue_redraw()


## Indica si este mueble necesita además una pieza de respaldo.
static func has_backrest(item_id_to_check: String) -> bool:
	return String(FurnitureCatalog.get_item(item_id_to_check).get("shape", "")) == "chair"


## En cuántas tiras se dibuja un mueble: una por casilla si es largo (1×N) y tiene sprite.
static func get_slice_count(item: Dictionary) -> int:
	var id: String = item["id"]
	if FurnitureCatalog.is_wall_mounted(id) or SpriteLibrary.get_furniture_sprite(id, item["rotation"]).is_empty():
		return 1
	var cells: Array[Vector2i] = FurnitureCatalog.get_footprint(id, item["cell"], item["rotation"])
	if cells.size() < 2:
		return 1
	var span: Vector2i = cells[-1] - cells[0]
	return cells.size() if span.x == 0 or span.y == 0 else 1


## Rotación con la que se dibuja (distinta de rotation_index en una silla arrimada a un escritorio).
func get_sprite_rotation() -> int:
	return _sprite_rotation


## Cuánto se corre de lado (en casillas) quien se sienta en seat_cell para quedar frente al
## teclado del escritorio que tiene delante: el sprite del escritorio (o de su computadora) dice
## dónde está. Cero si no hay escritorio o no se sabe.
static func get_seat_shift(seat_cell: Vector2i) -> Vector2:
	var facing: Dictionary = OfficeState.get_desk_facing(seat_cell)
	if facing.is_empty():
		return Vector2.ZERO
	var desk: Dictionary = OfficeState.furniture[int(facing["index"])]
	var rotation: int = posmod(int(desk["rotation"]), 4)
	var cells: Array[Vector2i] = FurnitureCatalog.get_footprint(desk["id"], desk["cell"], rotation)
	var computer: String = String(desk.get("computer", ""))
	# Dónde queda el teclado a lo largo del modelo, desde su punta −x.
	var along: float = SpriteLibrary.get_seat_x(SpriteLibrary.get_desk_set_base(desk["id"], computer, FurnitureCatalog.get_monitor_count(desk)))
	if along < 0.0 and not SpriteLibrary.get_furniture_sprite(desk["id"], rotation).is_empty():
		var own: float = SpriteLibrary.get_seat_x(SpriteLibrary.get_furniture_base(computer))
		if own >= 0.0:
			# La computadora suelta va sobre el centro del mueble.
			along = (cells.size() - 1) / 2.0 + own
		elif computer.is_empty():
			along = SpriteLibrary.get_seat_x(SpriteLibrary.get_furniture_base(desk["id"]))
	if along < 0.0:
		return Vector2.ZERO
	var side: Vector2 = MODEL_X_SIDES[rotation]
	var axis: Vector2 = side.abs()
	# Del modelo a la cuadrícula: desde el centro de la casilla de anclaje, a lo largo del mueble.
	var place: float = along - 0.5 if side.x + side.y > 0.0 else cells.size() - along - 0.5
	var front: Vector2i = FurnitureCatalog.FRONT_DIRECTIONS[int(facing["direction"])]
	var index: float = Vector2(seat_cell + front - Vector2i(desk["cell"])).dot(axis)
	return axis * clampf(place - index, -SEAT_SHIFT_MAX, SEAT_SHIFT_MAX)


## Tira que dibuja esta pieza (0 si el mueble va entero).
func get_slice() -> int:
	return _slice


## Nombre del sprite que dibuja esta pieza ("" si usa el dibujo provisional).
func get_sprite() -> String:
	if FurnitureCatalog.is_wall_mounted(item_id):
		# Solo hay dibujo de las caras que se ven de frente (las que miran a +x o a +y).
		var facing: Vector2i = FurnitureCatalog.get_front(rotation_index)
		if facing.x + facing.y < 0:
			return ""
		var cell := Vector2i((_anchor + Vector2(facing) * 0.5).round())
		var pick: int = int(MapDecor.noise(cell, SALT_WALL_ITEM) * 1000.0)
		return SpriteLibrary.get_wall_item_sprite(item_id, FurnitureCatalog.get_wall_edge(cell, rotation_index).z, pick)
	if has_backrest(item_id):
		return SpriteLibrary.get_furniture_sprite(item_id, _sprite_rotation, "back" if part == PART_BACKREST else "seat")
	var whole: String = SpriteLibrary.get_desk_set_sprite(item_id, computer_id, monitor_count, rotation_index)
	return whole if not whole.is_empty() else SpriteLibrary.get_furniture_sprite(item_id, rotation_index)


# Dibuja la pieza con sus sprites (sombra, mueble y lo que lleva encima). Devuelve false
# si no hay sprite para este mueble.
func _draw_sprites() -> bool:
	var sprite: String = get_sprite()
	if sprite.is_empty():
		return false
	var at: Vector2 = _local(_anchor)
	if has_backrest(item_id) and OfficeCharacter.draws_chair_at(footprint[0]):
		# Quien está sentado ahí se dibuja junto con la silla: aquí queda solo la sombra.
		if (part == PART_BACKREST) == _back_first:
			SpriteLibrary.draw_shadow(self, SpriteLibrary.get_furniture_sprite(item_id, _sprite_rotation, "shadow"), at)
		return true
	if FurnitureCatalog.is_wall_mounted(item_id):
		if not _on_low_wall:
			return SpriteLibrary.draw(self, sprite, at)
		var drop: float = SpriteLibrary.get_wall_item_base(item_id) * LOW_WALL_SPRITE_SCALE - LOW_WALL_ITEM_BASE_PX
		return SpriteLibrary.draw_scaled(self, sprite, at + Vector2(0.0, drop), LOW_WALL_SPRITE_SCALE)
	if _slices > 1:
		# Tira de su casilla: de mitad a mitad con las vecinas; las puntas llegan al borde del sprite.
		var step: float = (_local(Vector2(footprint[1])) - _local(Vector2(footprint[0]))).x * SpriteLibrary.get_scale()
		var from: float = step * (_slice - 0.5) if _slice > 0 else -INF * signf(step)
		var to: float = step * (_slice + 0.5) if _slice < _slices - 1 else INF * signf(step)
		if _slice == 0:
			SpriteLibrary.draw_shadow(self, sprite + "_shadow", at)
		SpriteLibrary.draw_strip(self, sprite, at, minf(from, to), maxf(from, to))
		if _slice < _slices - 1:
			return true
	else:
		if not has_backrest(item_id) or (part == PART_BACKREST) == _back_first:
			SpriteLibrary.draw_shadow(self, SpriteLibrary.get_furniture_sprite(item_id, _sprite_rotation, "shadow"), at)
		SpriteLibrary.draw(self, sprite, at)
	if not computer_id.is_empty() and SpriteLibrary.get_desk_set_base(item_id, computer_id, monitor_count).is_empty():
		# La computadora va sobre el centro del escritorio (el sprite ya trae la altura). Un
		# escritorio con conjuntos (el largo) ya la trae dibujada en su propio sprite.
		var center: Vector2 = (_low + _high) / 2.0
		SpriteLibrary.draw_shadow(self, SpriteLibrary.get_furniture_sprite(computer_id, rotation_index, "shadow"), _local(center))
		SpriteLibrary.draw(self, SpriteLibrary.get_furniture_sprite(computer_id, rotation_index), _local(center))
	return true


func _draw() -> void:
	if _draw_sprites() or part == PART_SLICE:
		return
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
