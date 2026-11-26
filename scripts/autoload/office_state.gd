# Estado de la oficina en coordenadas de cuadrícula: local, pisos, bordes, muebles y habitaciones.
# Solo guarda datos: comprar y vender lo hace Builder.
extends Node

## Oficina con la que empieza toda partida nueva.
const STARTING_OFFICE_PATH: String = "res://data/starting_office.json"
## Ningún borde (p. ej. sin puerta de vidrio doble).
const NO_EDGE := Vector3i(-1000000, -1000000, 0)
## Mueble quitado (el escritorio amplio): las partidas viejas lo cambian por uno sencillo.
const REMOVED_WIDE_DESK: String = "wide_desk"
const REMOVED_MID_COMPUTER: String = "mid_computer"
## Tipo de la Sala de servidores (data/rooms.json).
const SERVER_ROOM: String = "server_room"
const EXECUTIVE_OFFICE: String = "executive_office"
## Baño: sus inodoros dan la capacidad.
const BATHROOM: String = "bathroom"
## Sala de descanso: almuerzo dentro y pausas.
const BREAK_ROOM: String = "break_room"

## Casillas del local (crece al comprar terreno; puede no ser un rectángulo).
var lot := Lot.new()

## Rectángulo que encierra el local. Asignarlo deja el local con ese rectángulo.
var lot_rect: Rect2i:
	get:
		return lot.get_bounds()
	set(value):
		lot = Lot.from_rect(value)

## Casillas del solar: el mapa fijo con el local en el centro.
var site_rect := Rect2i()
## Solo para pruebas: false deja la entrada como venga, sin la puerta de vidrio doble. No se guarda.
var double_door_enabled: bool = true

# Consultas pedidas muchas veces por hora (habitaciones que funcionan, mesas, Sala de descanso,
# inodoros). Solo vale con GameClock.in_hour_tick; se borra al cambiar oficina u hora y al empezar o cargar.
var _query_cache: Dictionary[String, Variant] = {}

## Tipo de piso de cada casilla del local (ver ConstructionCatalog).
var floors: Dictionary[Vector2i, String] = {}

## Piezas en los bordes: GridEdge → pieza de ConstructionCatalog; un borde que no está, libre.
var edges: Dictionary[Vector3i, String] = {}

## Habitaciones: {"type", "cells": Array[Vector2i], "dirt"} (dirt 0..cleaning.max_dirt; si falta, 0).
var rooms: Array[Dictionary] = []

## Muebles: {"id", "cell" (anclaje), "rotation", "assigned_to" (quién lo usa o ""), "computer",
## "monitor" (en un escritorio; "" si no tiene, puede faltar)}. Los cambia Builder.
var furniture: Array[Dictionary] = []

# Casilla → índice de habitación (get_room_index_map), con el hash de las casillas con que se armó.
var _room_map: Dictionary[Vector2i, int] = {}
var _room_map_key: int = 0

## Lo que se pagó por el terreno comprado (cuenta en el valor de la empresa).
var land_paid: int = 0
## Semilla con que se parte el solar en lotes (LandPlots); al azar en cada partida nueva.
var land_seed: int = 0
# Lotes ya partidos (get_land_plots) y la semilla y el solar con que se partieron.
var _land_plots: Array[Rect2i] = []
var _land_plots_key: String = ""

## Casilla del borde del local por la que se entra y se sale.
var entrance := Vector2i.ZERO



## Local con que empieza toda partida; no es de ningún lote y no se vende.
static func get_base_rect() -> Rect2i:
	return Rect2i(Vector2i.ZERO, GameConstants.STARTING_LOT_SIZE)


## Lotes del solar (rectángulos, ver LandPlots), partidos con land_seed.
func get_land_plots() -> Array[Rect2i]:
	var sides: Vector2i = ConstructionCatalog.get_land_plot_sides()
	var key: String = "%d|%s|%s" % [land_seed, site_rect, sides]
	if key != _land_plots_key:
		_land_plots = LandPlots.partition(site_rect, get_base_rect(), land_seed, sides.x, sides.y)
		_land_plots_key = key
	return _land_plots


## Lote (rectángulo) que contiene la casilla; Rect2i() si es del local inicial o está fuera del solar.
func get_land_plot_at(cell: Vector2i) -> Rect2i:
	for plot: Rect2i in get_land_plots():
		if plot.has_point(cell):
			return plot
	return Rect2i()


## Indica si hay una partida cargada (nueva o guardada).
func has_game() -> bool:
	return lot.has_area()


func _ready() -> void:
	EventBus.office_changed.connect(func() -> void: _query_cache.clear())
	EventBus.hour_changed.connect(func(_hour: int) -> void: _query_cache.clear())


## Prepara la oficina de una partida nueva con lo que dice STARTING_OFFICE_PATH.
func new_game() -> void:
	_query_cache.clear()
	lot = Lot.from_rect(Rect2i(Vector2i.ZERO, GameConstants.STARTING_LOT_SIZE))
	land_paid = 0
	# Con un generador propio, para no correr la secuencia del azar global que usan otros sistemas.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	land_seed = rng.randi()
	site_rect = site_around(lot.get_bounds())
	rooms.clear()
	furniture.clear()
	floors.clear()
	edges.clear()
	var data: Dictionary = _load_json(STARTING_OFFICE_PATH)
	var base_floor: String = String(data.get("floor", ConstructionCatalog.BARE_FLOOR))
	for cell: Vector2i in lot.get_cells():
		floors[cell] = base_floor
	for area_data: Dictionary in data.get("floor_areas", []):
		var area := Rect2i(_to_cell(area_data["position"]), _to_cell(area_data["size"]))
		for x: int in range(area.position.x, area.end.x):
			for y: int in range(area.position.y, area.end.y):
				floors[Vector2i(x, y)] = String(area_data["type"])
	if bool(data.get("exterior_walls", false)):
		for edge: Vector3i in GridEdge.get_lot_outline(lot):
			edges[edge] = ConstructionCatalog.WALL
	for edge_data: Array in data.get("walls", []):
		edges[GridEdge.from_data(edge_data)] = ConstructionCatalog.WALL
	for edge_data: Array in data.get("doors", []):
		edges[GridEdge.from_data(edge_data)] = ConstructionCatalog.DOOR
	for room_data: Dictionary in data.get("rooms", []):
		var area := Rect2i(_to_cell(room_data["position"]), _to_cell(room_data["size"]))
		var cells: Array[Vector2i] = []
		for x: int in range(area.position.x, area.end.x):
			for y: int in range(area.position.y, area.end.y):
				cells.append(Vector2i(x, y))
		rooms.append({"type": String(room_data["type"]), "cells": cells})
	for item: Dictionary in data.get("furniture", []):
		furniture.append(_furniture_from_data(item))
	entrance = _to_cell(data.get("entrance", [0, 0]))
	place_double_door(edges, lot, get_entrance_edge())


## Solar de tamaño GameConstants.MAX_SITE_SIZE con el local en el centro.
static func site_around(lot: Rect2i) -> Rect2i:
	@warning_ignore("integer_division")
	var offset: Vector2i = (GameConstants.MAX_SITE_SIZE - lot.size) / 2
	return Rect2i(lot.position - offset, GameConstants.MAX_SITE_SIZE)


## Primer mueble asignado a alguien (por ejemplo, "ceo"), o {}.
func find_furniture_assigned_to(who: String) -> Dictionary:
	for item: Dictionary in furniture:
		if item["assigned_to"] == who:
			return item
	return {}


## Todas las casillas ocupadas por los muebles de la oficina.
func get_furniture_cells() -> Array[Vector2i]:
	return cells_of_furniture(furniture)


## Todas las casillas ocupadas por una lista de muebles.
func cells_of_furniture(items: Array[Dictionary]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for item: Dictionary in items:
		cells.append_array(FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"]))
	return cells


## Casillas que tapan el paso: las de los muebles menos los que se pisan (la alfombra).
func get_blocking_cells() -> Array[Vector2i]:
	return blocking_cells_of(furniture)


func blocking_cells_of(items: Array[Dictionary]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for item: Dictionary in items:
		if FurnitureCatalog.blocks_passage(item["id"]):
			cells.append_array(FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"]))
	return cells


## Índice del objeto de pared colgado en esa cara (casilla y rotación que deja la pared detrás), o -1.
func find_wall_item(cell: Vector2i, rotation: int) -> int:
	return find_wall_item_in(furniture, cell, rotation)


static func find_wall_item_in(items: Array[Dictionary], cell: Vector2i, rotation: int) -> int:
	for index: int in range(items.size()):
		var item: Dictionary = items[index]
		if FurnitureCatalog.is_wall_mounted(item["id"]) and item["cell"] == cell and posmod(int(item["rotation"]), 4) == posmod(rotation, 4):
			return index
	return -1


## Índices de los objetos colgados en un borde, de cualquiera de sus dos lados.
func wall_items_on(edge: Vector3i) -> Array[int]:
	var found: Array[int] = []
	for index: int in range(furniture.size()):
		var item: Dictionary = furniture[index]
		if FurnitureCatalog.is_wall_mounted(item["id"]) and FurnitureCatalog.get_wall_edge(item["cell"], item["rotation"]) == edge:
			found.append(index)
	return found


## Escritorio o mostrador con el frente hacia esa casilla: {direction (0–3, hacia el mueble),
## computer, index}, o {}. Con varios prefiere el que tiene computadora.
func get_desk_facing(cell: Vector2i) -> Dictionary:
	var found: Dictionary = {}
	for direction: int in range(FurnitureCatalog.FRONT_DIRECTIONS.size()):
		var step: Vector2i = FurnitureCatalog.FRONT_DIRECTIONS[direction]
		var index: int = find_furniture_at(cell + step)
		if index < 0:
			continue
		var desk: Dictionary = furniture[index]
		var info: Dictionary = FurnitureCatalog.get_item(desk["id"])
		if not bool(info.get("accepts_computer", false)) and not bool(info.get("is_counter", false)):
			continue
		if FurnitureCatalog.get_front(int(desk["rotation"])) != -step:
			continue
		var has_computer: bool = not String(desk.get("computer", "")).is_empty()
		if found.is_empty() or (has_computer and not bool(found["computer"])):
			found = {"direction": direction, "computer": has_computer, "index": index}
	return found


## Índice del mueble en una casilla, o -1. Con quarter (0–3) prefiere el chico de ese cuarto.
func find_furniture_at(cell: Vector2i, quarter: int = -1) -> int:
	var found: int = -1
	for index: int in range(furniture.size()):
		var item: Dictionary = furniture[index]
		if FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"]).has(cell):
			if quarter < 0 or FurnitureCatalog.get_quarter(item) == quarter:
				return index
			if found < 0:
				found = index
	return found


## Pieza en un borde: ConstructionCatalog.WALL, DOOR, WINDOW o "" si está libre.
func get_edge(edge: Vector3i) -> String:
	return edges.get(edge, "")


## Pone una pieza en un borde, o lo deja libre con kind = "".
func set_edge(edge: Vector3i, kind: String) -> void:
	if kind.is_empty():
		edges.erase(edge)
	else:
		edges[edge] = kind


## Tipo de piso de una casilla.
func get_floor(cell: Vector2i) -> String:
	return floors.get(cell, ConstructionCatalog.BARE_FLOOR)


## Cambia el tipo de piso de una casilla.
func set_floor(cell: Vector2i, floor_type: String) -> void:
	floors[cell] = floor_type


## Indica si el borde cierra el paso (puertas y bordes libres no).
func blocks_passage(edge: Vector3i) -> bool:
	var kind: String = get_edge(edge)
	return kind == ConstructionCatalog.WALL or kind == ConstructionCatalog.WINDOW


## Puntos de ambiente de la puerta de vidrio (sencilla o doble): cuentan para la habitación con la casilla de entrada.
func get_room_door_ambiance(room: Dictionary) -> int:
	var kind: String = get_edge(get_entrance_edge())
	if not ConstructionCatalog.is_glass_door(kind):
		return 0
	var cells: Array = room["cells"]
	return ConstructionCatalog.get_glass_door_ambiance(kind) if cells.has(entrance) else 0


## Tramo que acompaña a la puerta de vidrio doble de la entrada (el de al lado con la misma pieza), o
## NO_EDGE si la entrada no la tiene. on_edges vacío = los bordes de la oficina.
func get_double_door_partner(on_edges: Dictionary = {}) -> Vector3i:
	if on_edges.is_empty():
		on_edges = edges
	var door: Vector3i = get_entrance_edge()
	if String(on_edges.get(door, "")) != ConstructionCatalog.GLASS_DOOR_DOUBLE:
		return NO_EDGE
	for side: Vector3i in GridEdge.get_line_neighbors(door):
		if String(on_edges.get(side, "")) == ConstructionCatalog.GLASS_DOOR_DOUBLE:
			return side
	return NO_EDGE


## Pone en la entrada (door) la puerta de vidrio doble, que va siempre ahí, con un tramo del contorno de al
## lado: el que ya la tenía; si no, una pared sin nada colgado (primero la de arriba); si no, cualquier pared
## o ventana. Otro tramo suelto vuelve a pared. Sin tramo posible queda la de vidrio sencilla. Devuelve el tramo.
func place_double_door(on_edges: Dictionary[Vector3i, String], on_lot: Lot, door: Vector3i) -> Vector3i:
	if not double_door_enabled:
		return NO_EDGE
	var kind: String = ConstructionCatalog.GLASS_DOOR_DOUBLE
	var sides: Array[Vector3i] = GridEdge.get_line_neighbors(door)
	sides.reverse()
	var partner: Vector3i = NO_EDGE
	for pass_index: int in range(3):
		for side: Vector3i in sides:
			if partner != NO_EDGE or not GridEdge.is_exterior(side, on_lot):
				continue
			var current: String = String(on_edges.get(side, ""))
			var fits: bool = current == kind
			if pass_index == 1:
				fits = current == ConstructionCatalog.WALL and wall_items_on(side).is_empty()
			elif pass_index == 2:
				fits = current == ConstructionCatalog.WALL or current == ConstructionCatalog.WINDOW
			if fits:
				partner = side
	for edge: Vector3i in on_edges.keys():
		if on_edges[edge] == kind and edge != door and edge != partner:
			on_edges[edge] = ConstructionCatalog.WALL
	on_edges[door] = kind if partner != NO_EDGE else ConstructionCatalog.GLASS_DOOR
	if partner != NO_EDGE:
		on_edges[partner] = kind
	_query_cache.clear()
	return partner


## Borde de la puerta de entrada (entre la casilla de entrada y la de afuera).
func get_entrance_edge() -> Vector3i:
	return GridEdge.between(entrance, get_outside_of_entrance())


## Ventanas que tocan alguna casilla de la habitación.
func count_room_windows(room: Dictionary) -> int:
	var count: int = 0
	var cells: Array = room["cells"]
	for edge: Vector3i in edges:
		if edges[edge] != ConstructionCatalog.WINDOW:
			continue
		for cell: Vector2i in GridEdge.get_cells(edge):
			if cells.has(cell):
				count += 1
				break
	return count


## Casilla de fuera a la que se sale por la entrada: la vecina tras la puerta (sin puerta, la primera de fuera).
func get_outside_of_entrance() -> Vector2i:
	var fallback := Vector2i(-1, -1)
	for direction: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		var outside: Vector2i = entrance + direction
		if lot.has_point(outside):
			continue
		if ConstructionCatalog.is_door(get_edge(GridEdge.between(entrance, outside))):
			return outside
		if fallback == Vector2i(-1, -1):
			fallback = outside
	return fallback


## Primera habitación del tipo indicado, o {}.
func find_room(room_type: String) -> Dictionary:
	for room: Dictionary in rooms:
		if room["type"] == room_type:
			return room
	return {}


## Suciedad de una habitación.
static func get_room_dirt(room: Dictionary) -> float:
	return float(room.get("dirt", 0.0))


## Índice de la habitación que contiene una casilla, o -1.
func get_room_index_at(cell: Vector2i) -> int:
	return RoomRules.room_index_at(rooms, cell)


## Índice de habitación de cada casilla (para buscar muchas a la vez). Guardado mientras las casillas
## no cambien; no modificar el resultado.
func get_room_index_map() -> Dictionary[Vector2i, int]:
	var parts: Array = []
	for room: Dictionary in rooms:
		parts.append(room["cells"])
	var key: int = parts.hash()
	if key != _room_map_key or (_room_map.is_empty() and not rooms.is_empty()):
		_room_map = {}
		# Al revés: con casillas repetidas gana la primera, como en get_room_index_at.
		for index: int in range(rooms.size() - 1, -1, -1):
			for cell: Vector2i in rooms[index]["cells"]:
				_room_map[cell] = index
		_room_map_key = key
	return _room_map


## Indica si una habitación está tan sucia que baja el ánimo de quienes trabajan ahí.
static func is_room_dirty(room: Dictionary) -> bool:
	return get_room_dirt(room) >= float(StaffCatalog.get_cleaning("dirty_from"))


## La Sala de servidores si existe y funciona (rack y aire acondicionado), o vacío.
func get_server_room() -> Dictionary:
	for room: Dictionary in rooms:
		if room["type"] == SERVER_ROOM and RoomRules.function_problems(room, furniture).is_empty():
			return room
	return {}


## Racks dentro de una habitación.
func count_racks(room: Dictionary) -> int:
	var cells: Array[Vector2i] = room["cells"]
	var count: int = 0
	for item: Dictionary in furniture:
		if FurnitureCatalog.is_server_rack(item["id"]) and cells.has(item["cell"]):
			count += 1
	return count


## Capacidad para productos: racks de la Sala de servidores que funciona (1 rack = 1 unidad).
func get_server_capacity() -> int:
	var room: Dictionary = get_server_room()
	return 0 if room.is_empty() else count_racks(room)


## Primera habitación de ese tipo que funciona ({} si no hay).
func get_working_room(room_type: String) -> Dictionary:
	var key: String = "room:" + room_type
	if not GameClock.in_hour_tick:
		return _find_working_room(room_type)
	if not _query_cache.has(key):
		_query_cache[key] = _find_working_room(room_type)
	return _query_cache[key]


func _find_working_room(room_type: String) -> Dictionary:
	for room: Dictionary in rooms:
		if room["type"] == room_type and RoomRules.function_problems(room, furniture).is_empty():
			return room
	return {}


## Mesas de comedor de la Sala de descanso que funciona si también tiene nevera y microondas; si no, vacío.
func get_lunch_tables() -> Array[Dictionary]:
	if not GameClock.in_hour_tick:
		return _find_lunch_tables()
	if not _query_cache.has("get_lunch_tables"):
		_query_cache["get_lunch_tables"] = _find_lunch_tables()
	return _query_cache["get_lunch_tables"]


func _find_lunch_tables() -> Array[Dictionary]:
	var tables: Array[Dictionary] = []
	var room: Dictionary = get_working_room(BREAK_ROOM)
	if room.is_empty():
		return tables
	var cells: Array[Vector2i] = room["cells"]
	var parts: Dictionary[String, bool] = {}
	for item: Dictionary in furniture:
		var part: String = FurnitureCatalog.get_lunch_part(item["id"])
		if not part.is_empty() and cells.has(item["cell"]):
			parts[part] = true
			if part == "table":
				tables.append(item)
	if not parts.has("fridge") or not parts.has("microwave"):
		tables.clear()
	return tables


## Asientos para almorzar dentro (4 por mesa).
func get_lunch_seats() -> int:
	var seats: int = 0
	for table: Dictionary in get_lunch_tables():
		seats += FurnitureCatalog.get_dining_seats(table["id"])
	return seats


## Casillas libres junto a las mesas de comedor, en orden (puede haber menos que asientos).
func get_lunch_spots() -> Array[Vector2i]:
	return _spots_near(get_lunch_tables())


## Muebles dentro de la Sala de descanso que funciona.
func get_break_room_items() -> Array[Dictionary]:
	if not GameClock.in_hour_tick:
		return _find_break_room_items()
	if not _query_cache.has("get_break_room_items"):
		_query_cache["get_break_room_items"] = _find_break_room_items()
	return _query_cache["get_break_room_items"]


func _find_break_room_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var room: Dictionary = get_working_room(BREAK_ROOM)
	if room.is_empty():
		return items
	var cells: Array[Vector2i] = room["cells"]
	for item: Dictionary in furniture:
		if cells.has(item["cell"]):
			items.append(item)
	return items


## Suma de un campo (break_mood, distraction, vending_income) de la Sala de descanso, uno por tipo.
func get_break_room_effect(field: String) -> float:
	var total: float = 0.0
	var counted: Dictionary[String, bool] = {}
	for item: Dictionary in get_break_room_items():
		if not counted.has(item["id"]):
			counted[item["id"]] = true
			total += FurnitureCatalog.get_number(item["id"], field)
	return total


## Sofás de la Sala de descanso que funciona.
func get_sofas() -> Array[Dictionary]:
	return get_break_room_items().filter(func(item: Dictionary) -> bool:
		return FurnitureCatalog.get_number(item["id"], "rest_places") > 0.0)


## Lugares para tomar una pausa (2 por sofá).
func get_rest_places() -> int:
	var places: int = 0
	for sofa: Dictionary in get_sofas():
		places += int(FurnitureCatalog.get_number(sofa["id"], "rest_places"))
	return places


## Casillas libres junto a los sofás, adonde caminan los que toman una pausa.
func get_rest_spots() -> Array[Vector2i]:
	return _spots_near(get_sofas())


# Casillas libres de la Sala de descanso alrededor de esos muebles, en orden.
func _spots_near(items: Array[Dictionary]) -> Array[Vector2i]:
	var spots: Array[Vector2i] = []
	var room: Dictionary = get_working_room(BREAK_ROOM)
	if room.is_empty():
		return spots
	var cells: Array[Vector2i] = room["cells"]
	var taken: Array[Vector2i] = get_blocking_cells()
	for table: Dictionary in items:
		for cell: Vector2i in FurnitureCatalog.get_footprint(table["id"], table["cell"], int(table["rotation"])):
			for step: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var spot: Vector2i = cell + step
				if cells.has(spot) and not taken.has(spot) and not spots.has(spot) and spot != entrance:
					spots.append(spot)
	return spots


## Inodoros dentro de los Baños que funcionan.
func count_working_toilets() -> int:
	if not GameClock.in_hour_tick:
		return _count_working_toilets()
	if not _query_cache.has("count_working_toilets"):
		_query_cache["count_working_toilets"] = _count_working_toilets()
	return _query_cache["count_working_toilets"]


func _count_working_toilets() -> int:
	var count: int = 0
	for room: Dictionary in rooms:
		if room["type"] != BATHROOM or not RoomRules.function_problems(room, furniture).is_empty():
			continue
		var cells: Array[Vector2i] = room["cells"]
		for item: Dictionary in furniture:
			if FurnitureCatalog.is_toilet(item["id"]) and cells.has(item["cell"]):
				count += 1
	return count


## Costo mensual de los muebles que lo tienen (los racks, estén donde estén), sin descuentos.
func get_furniture_monthly_cost() -> int:
	var total: int = 0
	for item: Dictionary in furniture:
		total += FurnitureCatalog.get_monthly_cost(item["id"])
	return total


## Indica si una habitación tiene zafacón.
func has_trash_can(room: Dictionary) -> bool:
	var cells: Array[Vector2i] = room["cells"]
	for item: Dictionary in furniture:
		if bool(FurnitureCatalog.get_item(item["id"]).get("trash_can", false)) and cells.has(item["cell"]):
			return true
	return false


## Suma la suciedad de people_hours horas-persona a la habitación (la mitad con zafacón), hasta el máximo.
func add_dirt(room_index: int, people_hours: float) -> void:
	if room_index < 0 or room_index >= rooms.size():
		return
	var room: Dictionary = rooms[room_index]
	var amount: float = people_hours * float(StaffCatalog.get_cleaning("dirt_per_person_hour"))
	if has_trash_can(room):
		amount *= float(StaffCatalog.get_cleaning("trash_can_factor"))
	room["dirt"] = minf(get_room_dirt(room) + amount, float(StaffCatalog.get_cleaning("max_dirt")))


## Quita suciedad de una habitación (sin bajar de 0).
func clean_room(room_index: int, amount: float) -> void:
	if room_index >= 0 and room_index < rooms.size():
		rooms[room_index]["dirt"] = maxf(0.0, get_room_dirt(rooms[room_index]) - amount)


## Deja todas las habitaciones limpias (evento de limpieza externa).
func clean_all() -> void:
	for room: Dictionary in rooms:
		room["dirt"] = 0.0
	EventBus.dirt_changed.emit()


## Indica si hay al menos un mueble de ese tipo en la oficina.
func has_furniture(id: String) -> bool:
	return furniture.any(func(item: Dictionary) -> bool: return item["id"] == id)


## Habitación más sucia (la primera si empatan), o -1 si todas están limpias.
func get_dirtiest_room() -> int:
	var best: int = -1
	for index: int in range(rooms.size()):
		if get_room_dirt(rooms[index]) > 0.0 and (best < 0 or get_room_dirt(rooms[index]) > get_room_dirt(rooms[best])):
			best = index
	return best


## Casilla libre de una habitación para pararse (sin muebles ni la entrada), o la primera.
func get_room_spot(room_index: int) -> Vector2i:
	var cells: Array[Vector2i] = rooms[room_index]["cells"]
	var taken: Array[Vector2i] = get_blocking_cells()
	for cell: Vector2i in cells:
		if not taken.has(cell) and cell != entrance:
			return cell
	return cells[0]


## Devuelve el estado de la oficina para guardarlo; las casillas van como [x, y] para JSON.
func export_state() -> Dictionary:
	var saved_rooms: Array = []
	for room: Dictionary in rooms:
		var cells: Array = []
		for cell: Vector2i in room["cells"]:
			cells.append([cell.x, cell.y])
		saved_rooms.append({"type": room["type"], "cells": cells, "dirt": get_room_dirt(room)})
	var saved_furniture: Array = []
	for item: Dictionary in furniture:
		var cell: Vector2i = item["cell"]
		saved_furniture.append({"id": item["id"], "cell": [cell.x, cell.y], "rotation": item["rotation"],
			"assigned_to": item["assigned_to"], "computer": item["computer"], "monitor": String(item.get("monitor", "")),
			"monitors": FurnitureCatalog.get_monitor_count(item), "quarter": FurnitureCatalog.get_quarter(item)})
	var saved_floors: Array = []
	for cell: Vector2i in floors:
		saved_floors.append([cell.x, cell.y, floors[cell]])
	var saved_edges: Array = []
	for edge: Vector3i in edges:
		saved_edges.append(GridEdge.to_data(edge) + [edges[edge]])
	return {
		"lot": [lot_rect.position.x, lot_rect.position.y, lot_rect.size.x, lot_rect.size.y],
		"lot_cells": lot.to_data(),
		"land_paid": land_paid,
		"land_seed": land_seed,
		"site": [site_rect.position.x, site_rect.position.y, site_rect.size.x, site_rect.size.y],
		"floors": saved_floors,
		"edges": saved_edges,
		"rooms": saved_rooms,
		"furniture": saved_furniture,
		"entrance": [entrance.x, entrance.y],
	}


## Restaura el estado de la oficina desde una partida guardada.
func import_state(state: Dictionary) -> void:
	_query_cache.clear()
	# Partidas viejas: el local era solo un rectángulo ("lot").
	if state.has("lot_cells"):
		var cells: Array[Vector2i] = []
		for pair: Array in state["lot_cells"]:
			cells.append(_to_cell(pair))
		lot = Lot.from_cells(cells)
	else:
		var saved_lot: Array = state.get("lot", [0, 0, 0, 0])
		lot = Lot.from_rect(Rect2i(int(saved_lot[0]), int(saved_lot[1]), int(saved_lot[2]), int(saved_lot[3])))
	land_paid = int(state.get("land_paid", 0))
	land_seed = int(state.get("land_seed", 0))
	var site: Array = state.get("site", [])
	site_rect = Rect2i(int(site[0]), int(site[1]), int(site[2]), int(site[3])) if site.size() == 4 else site_around(lot_rect)
	floors.clear()
	for entry: Array in state.get("floors", []):
		floors[Vector2i(int(entry[0]), int(entry[1]))] = String(entry[2])
	edges.clear()
	for entry: Array in state.get("edges", []):
		edges[GridEdge.from_data(entry)] = String(entry[3])
	rooms.clear()
	for room: Dictionary in state.get("rooms", []):
		var cells: Array[Vector2i] = []
		for cell: Array in room["cells"]:
			cells.append(_to_cell(cell))
		rooms.append({"type": String(room["type"]), "cells": cells, "dirt": float(room.get("dirt", 0.0))})
	furniture.clear()
	for item: Dictionary in state.get("furniture", []):
		furniture.append(_furniture_from_data(item))
	_replace_removed_furniture()
	entrance = _to_cell(state.get("entrance", [0, 0]))
	# Partidas viejas: la entrada tenía puerta normal o de vidrio sencilla.
	place_double_door(edges, lot, get_entrance_edge())
	_hang_wall_items()


# Escritorio amplio de una partida vieja → escritorio sencillo con su computadora, en la casilla con
# un asiento delante (sigue siendo puesto) o en la de anclaje.
func _replace_removed_furniture() -> void:
	for item: Dictionary in furniture:
		if String(item["id"]) != REMOVED_WIDE_DESK:
			continue
		var rotation: int = int(item["rotation"])
		var front: Vector2i = FurnitureCatalog.get_front(rotation)
		var other: Vector2i = item["cell"] + (Vector2i(0, 1) if rotation % 2 == 1 else Vector2i(1, 0))
		item["id"] = "simple_desk"
		if not _has_seat_at(item["cell"] + front) and _has_seat_at(other + front):
			item["cell"] = other
	for item: Dictionary in furniture:
		# La computadora media ya no existe: pasa a básica.
		if String(item["computer"]) == REMOVED_MID_COMPUTER:
			item["computer"] = "basic_computer"
		# Las pantallas extra que ya no caben (escritorio largo con pro) se quitan devolviendo lo pagado.
		var count: int = FurnitureCatalog.get_monitor_count(item)
		if count <= 0:
			continue
		var allowed: int = FurnitureCatalog.get_max_monitors(item["id"]) if FurnitureCatalog.allows_monitors(item["computer"]) else 0
		if count > allowed:
			var price: int = FurnitureCatalog.get_price(item["monitor"]) * (count - allowed)
			item["monitors"] = allowed
			if allowed <= 0:
				item["monitor"] = ""
			# Economy se importa después: el reembolso va al terminar de cargar.
			Economy.earn.call_deferred(price, Builder.CONCEPT_FURNITURE)


# Indica si en una casilla hay un asiento (para _replace_removed_furniture).
func _has_seat_at(cell: Vector2i) -> bool:
	for item: Dictionary in furniture:
		if item["cell"] == cell and bool(FurnitureCatalog.get_item(item["id"]).get("is_seat", false)):
			return true
	return false


# Cuelga cada objeto de pared que no está en una cara libre en la más cercana de su habitación
# (partidas viejas); si no hay, lo quita devolviendo lo pagado.
func _hang_wall_items() -> void:
	var removed: Array[Dictionary] = []
	var placed: Array[Dictionary] = []
	for item: Dictionary in furniture.duplicate():
		if not FurnitureCatalog.is_wall_mounted(item["id"]):
			continue
		var cell: Vector2i = item["cell"]
		var slot: Array = _free_wall_slot(cell, int(item["rotation"]), placed)
		if slot.is_empty():
			furniture.erase(item)
			removed.append(item)
			continue
		item["cell"] = slot[0]
		item["rotation"] = slot[1]
		placed.append(item)
	for item: Dictionary in removed:
		var price: int = FurnitureCatalog.get_price(item["id"])
		# Economy se importa después: el reembolso va al terminar de cargar.
		Economy.earn.call_deferred(price, Builder.CONCEPT_FURNITURE)
		EventBus.notice.emit.call_deferred("%s quitado: no había pared donde colgarlo. Se devolvieron $%d." % [
			FurnitureCatalog.get_item(item["id"])["name"], price])


# [casilla, rotación] de la cara de pared libre más cercana para un objeto de pared, o [].
func _free_wall_slot(cell: Vector2i, rotation: int, placed: Array[Dictionary]) -> Array:
	var room_index: int = get_room_index_at(cell)
	var cells: Array[Vector2i] = [cell]
	if room_index >= 0:
		cells = (rooms[room_index]["cells"] as Array[Vector2i]).duplicate()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a - cell).length_squared() < (b - cell).length_squared())
	for candidate: Vector2i in cells:
		var rotations: Array[int] = [0, 1, 2, 3]
		if candidate == cell:
			rotations.push_front(rotation)
		for side: int in rotations:
			if get_edge(FurnitureCatalog.get_wall_edge(candidate, side)) == ConstructionCatalog.WALL \
					and find_wall_item_in(placed, candidate, side) < 0:
				return [candidate, posmod(side, 4)]
	return []


func _furniture_from_data(item: Dictionary) -> Dictionary:
	return {
		"id": String(item["id"]),
		"cell": _to_cell(item["cell"]),
		"rotation": int(item.get("rotation", 0)),
		"assigned_to": String(item.get("assigned_to", "")),
		"computer": String(item.get("computer", "")),
		"monitor": String(item.get("monitor", "")),
		"monitors": int(item.get("monitors", 0 if String(item.get("monitor", "")).is_empty() else 1)),
		# Los chicos guardan su cuarto; las partidas viejas los ponen en el primero.
		"quarter": int(item.get("quarter", 0 if FurnitureCatalog.is_small(String(item["id"])) else -1)),
	}


# JSON guarda los números como decimales: vuelven a casillas enteras.
func _to_cell(pair: Array) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))


func _load_json(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("No se pudo leer %s" % path)
	return {}
