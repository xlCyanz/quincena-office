# Estado de la oficina: casillas, paredes, muebles y habitaciones, en coordenadas de cuadrícula.
# Pisos y bordes (paredes y puertas) desde el hito 5; muebles en el 6 y detección de
# habitaciones en el 7. Este autoload solo guarda datos: comprar y vender lo hace Builder.
extends Node

## Oficina con la que empieza toda partida nueva.
const STARTING_OFFICE_PATH: String = "res://data/starting_office.json"
## Mueble quitado del juego (el escritorio amplio): las partidas viejas lo cambian por uno sencillo.
const REMOVED_WIDE_DESK: String = "wide_desk"
const REMOVED_MID_COMPUTER: String = "mid_computer"
## Tipo de la Sala de servidores (data/rooms.json).
const SERVER_ROOM: String = "server_room"
const EXECUTIVE_OFFICE: String = "executive_office"
## Baño: sus inodoros dan la capacidad (hito 52).
const BATHROOM: String = "bathroom"
## Sala de descanso: almuerzo dentro (hito 53).
const BREAK_ROOM: String = "break_room"

## Casillas que ocupa el local (hito 25: crece al comprar terreno y puede no ser un rectángulo).
var lot := Lot.new()

## Rectángulo que encierra el local. Asignarlo deja el local con ese rectángulo.
var lot_rect: Rect2i:
	get:
		return lot.get_bounds()
	set(value):
		lot = Lot.from_rect(value)

## Casillas del solar: el mapa fijo que rodea al local, con el local en el centro.
var site_rect := Rect2i()

# Habitaciones que funcionan, mesas, muebles de la Sala de descanso e inodoros: los piden
# varias veces por hora los baños, el almuerzo, las pausas y la producción. Solo se usa
# mientras el reloj procesa una hora (GameClock.in_hour_tick); se borra al cambiar la
# oficina o la hora, y al empezar o cargar una partida.
var _query_cache: Dictionary[String, Variant] = {}

## Tipo de piso de cada casilla del local (ver ConstructionCatalog).
var floors: Dictionary[Vector2i, String] = {}

## Piezas en los bordes: GridEdge → ConstructionCatalog.WALL, DOOR o WINDOW. Un borde que no
## está en el diccionario está libre.
var edges: Dictionary[Vector3i, String] = {}

## Habitaciones: cada una es {"type": String, "cells": Array[Vector2i], "dirt": float}
## (dirt = suciedad de 0 a cleaning.max_dirt, hito 37; puede faltar y vale 0).
var rooms: Array[Dictionary] = []

## Muebles: cada uno es {"id": String, "cell": Vector2i, "rotation": int,
## "assigned_to": String, "computer": String, "monitor": String}. cell es la casilla de
## anclaje, assigned_to dice quién lo usa ("" si nadie), computer la computadora
## instalada en un escritorio y monitor su segundo monitor ("" si no tiene; puede faltar). Comprar, girar y vender lo hace Builder.
var furniture: Array[Dictionary] = []

# Casilla → índice de habitación (get_room_index_map), con el hash de las casillas de
# las habitaciones con que se armó.
var _room_map: Dictionary[Vector2i, int] = {}
var _room_map_key: int = 0

## Lo que se pagó por el terreno comprado (cuenta en el valor de la empresa).
var land_paid: int = 0

## Casilla del borde del local por la que se entra y se sale.
var entrance := Vector2i.ZERO



## Indica si hay una partida cargada (nueva o guardada).
func has_game() -> bool:
	return lot.has_area()


func _ready() -> void:
	EventBus.office_changed.connect(func() -> void: _query_cache.clear())
	EventBus.hour_changed.connect(func(_hour: int) -> void: _query_cache.clear())


## Prepara la oficina de una partida nueva: el local inicial y lo que dice
## STARTING_OFFICE_PATH.
func new_game() -> void:
	_query_cache.clear()
	lot = Lot.from_rect(Rect2i(Vector2i.ZERO, GameConstants.STARTING_LOT_SIZE))
	land_paid = 0
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


## Solar de tamaño GameConstants.MAX_SITE_SIZE con el local en el centro.
static func site_around(lot: Rect2i) -> Rect2i:
	@warning_ignore("integer_division")
	var offset: Vector2i = (GameConstants.MAX_SITE_SIZE - lot.size) / 2
	return Rect2i(lot.position - offset, GameConstants.MAX_SITE_SIZE)


## Devuelve el primer mueble asignado a alguien (por ejemplo, "ceo"), o un diccionario vacío.
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


## Casillas que tapan el paso: las de los muebles menos las de los que se pisan (la
## alfombra, hito 45).
func get_blocking_cells() -> Array[Vector2i]:
	return blocking_cells_of(furniture)


func blocking_cells_of(items: Array[Dictionary]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for item: Dictionary in items:
		if FurnitureCatalog.blocks_passage(item["id"]):
			cells.append_array(FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"]))
	return cells


## Índice del objeto de pared colgado en esa cara (su casilla y la rotación que deja la
## pared detrás), o -1.
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


## Escritorio o mostrador que tiene su frente hacia una casilla (quien se sienta ahí queda
## delante de él): {direction (0–3, hacia el mueble, como las rotaciones), computer (si tiene
## computadora), index (el mueble en furniture)}. Vacío si no hay ninguno. Con varios, prefiere el que tiene computadora.
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


## Índice en furniture del mueble que ocupa una casilla, o -1 si está libre. Con quarter
## (0–3) prefiere el mueble chico de ese cuarto; si no hay, el primero de la casilla.
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


## Indica si una pared cierra el paso por un borde (las puertas y los bordes libres no).
func blocks_passage(edge: Vector3i) -> bool:
	var kind: String = get_edge(edge)
	return kind == ConstructionCatalog.WALL or kind == ConstructionCatalog.WINDOW


## Puntos de ambiente de la puerta de vidrio para una habitación (hito 69): solo va en la
## entrada, así que cuenta para la habitación que tiene la casilla de entrada.
func get_room_door_ambiance(room: Dictionary) -> int:
	if get_edge(get_entrance_edge()) != ConstructionCatalog.GLASS_DOOR:
		return 0
	var cells: Array = room["cells"]
	return ConstructionCatalog.get_glass_door_ambiance() if cells.has(entrance) else 0


## Borde de la puerta de entrada (entre la casilla de entrada y la de afuera).
func get_entrance_edge() -> Vector3i:
	return GridEdge.between(entrance, get_outside_of_entrance())


## Ventanas que dan a una habitación: bordes con ventana que tocan alguna de sus casillas.
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


## Casilla de fuera del local a la que se sale por la entrada: la vecina fuera del
## local cuyo borde tiene la puerta (o, si no hay puerta, la primera vecina de fuera).
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


## Devuelve la primera habitación del tipo indicado, o un diccionario vacío.
func find_room(room_type: String) -> Dictionary:
	for room: Dictionary in rooms:
		if room["type"] == room_type:
			return room
	return {}


## Suciedad de una habitación (hito 37).
static func get_room_dirt(room: Dictionary) -> float:
	return float(room.get("dirt", 0.0))


## Índice de la habitación que contiene una casilla, o -1.
func get_room_index_at(cell: Vector2i) -> int:
	return RoomRules.room_index_at(rooms, cell)


## Índice de habitación de cada casilla que está en alguna (para buscar muchas de una
## vez). Se guarda mientras las casillas de las habitaciones no cambien; la suciedad no
## cuenta. No modificar el resultado.
func get_room_index_map() -> Dictionary[Vector2i, int]:
	var parts: Array = []
	for room: Dictionary in rooms:
		parts.append(room["cells"])
	var key: int = parts.hash()
	if key != _room_map_key or (_room_map.is_empty() and not rooms.is_empty()):
		_room_map = {}
		# Al revés, para que con casillas repetidas gane la primera como en room_index_at.
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


## Capacidad para productos: los racks de la Sala de servidores que funciona (cada rack
## es una unidad; un producto usa las de su tamaño).
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


## Mesas de comedor de la Sala de descanso que funciona si también tiene nevera y
## microondas (hito 53: almuerzo dentro); vacío si no se puede almorzar dentro.
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


## Casillas libres de la Sala de descanso junto a las mesas de comedor, adonde caminan los
## que almuerzan dentro (en orden; puede haber menos que asientos).
func get_lunch_spots() -> Array[Vector2i]:
	return _spots_near(get_lunch_tables())


## Muebles dentro de la Sala de descanso que funciona (hito 54).
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


## Suma de un valor de los muebles de la Sala de descanso que funciona, contando uno de
## cada tipo (break_mood, distraction, vending_income).
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


## Inodoros dentro de los Baños que funcionan (hito 52).
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


## Lo que cuestan al mes los muebles con costo mensual (los racks, estén donde estén),
## sin descuentos.
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


## Suma la suciedad de people_hours horas-persona a la habitación de room_index (la
## mitad con zafacón), sin pasar del máximo.
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


## Deja todas las habitaciones limpias (limpieza externa de un evento, hito 44).
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


## Casilla libre de una habitación donde puede pararse alguien (sin muebles y que no sea
## la entrada), o la primera si no hay.
func get_room_spot(room_index: int) -> Vector2i:
	var cells: Array[Vector2i] = rooms[room_index]["cells"]
	var taken: Array[Vector2i] = get_blocking_cells()
	for cell: Vector2i in cells:
		if not taken.has(cell) and cell != entrance:
			return cell
	return cells[0]


## Devuelve el estado de la oficina para guardarlo (hito 9). Las casillas se
## guardan como listas [x, y] para que pasen por JSON sin perderse.
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
		"site": [site_rect.position.x, site_rect.position.y, site_rect.size.x, site_rect.size.y],
		"floors": saved_floors,
		"edges": saved_edges,
		"rooms": saved_rooms,
		"furniture": saved_furniture,
		"entrance": [entrance.x, entrance.y],
	}


## Restaura el estado de la oficina desde una partida guardada (hito 9).
func import_state(state: Dictionary) -> void:
	_query_cache.clear()
	# Antes del hito 25 el local era solo un rectángulo ("lot").
	if state.has("lot_cells"):
		var cells: Array[Vector2i] = []
		for pair: Array in state["lot_cells"]:
			cells.append(_to_cell(pair))
		lot = Lot.from_cells(cells)
	else:
		var saved_lot: Array = state.get("lot", [0, 0, 0, 0])
		lot = Lot.from_rect(Rect2i(int(saved_lot[0]), int(saved_lot[1]), int(saved_lot[2]), int(saved_lot[3])))
	land_paid = int(state.get("land_paid", 0))
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
	_hang_wall_items()


# El escritorio amplio (2×1) ya no existe: en una partida vieja cada uno pasa a ser un
# escritorio sencillo, con su computadora, en la casilla de las dos que tiene un asiento
# delante de su frente (así el puesto sigue funcionando); si ninguna, en la de anclaje.
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
		# Las pantallas extra ahora solo van en un escritorio largo con computadora pro: las que
		# no cumplen se quitan y se devuelve lo pagado.
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


# Antes del hito 45 el aire acondicionado ocupaba una casilla de piso: cada objeto de
# pared que no está en una cara de pared libre se cuelga en la más cercana de su
# habitación (o de su casilla). Si no hay ninguna, se quita y se devuelve lo pagado.
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
		# Los muebles chicos guardan su cuarto; las partidas viejas los ponen en el primero.
		"quarter": int(item.get("quarter", 0 if FurnitureCatalog.is_small(String(item["id"])) else -1)),
	}


# JSON guarda los números como decimales; aquí vuelven a ser casillas enteras.
func _to_cell(pair: Array) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))


func _load_json(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("No se pudo leer %s" % path)
	return {}
