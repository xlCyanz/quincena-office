# Estado de la oficina: casillas, paredes, muebles y habitaciones, en coordenadas de cuadrícula.
# Pisos y bordes (paredes y puertas) desde el hito 5; muebles en el 6 y detección de
# habitaciones en el 7. Este autoload solo guarda datos: comprar y vender lo hace Builder.
extends Node

## Oficina con la que empieza toda partida nueva.
const STARTING_OFFICE_PATH: String = "res://data/starting_office.json"
## Tipo de la Sala de servidores (data/rooms.json).
const SERVER_ROOM: String = "server_room"

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

## Tipo de piso de cada casilla del local (ver ConstructionCatalog).
var floors: Dictionary[Vector2i, String] = {}

## Piezas en los bordes: GridEdge → ConstructionCatalog.WALL o DOOR. Un borde que no
## está en el diccionario está libre.
var edges: Dictionary[Vector3i, String] = {}

## Habitaciones: cada una es {"type": String, "cells": Array[Vector2i], "dirt": float}
## (dirt = suciedad de 0 a cleaning.max_dirt, hito 37; puede faltar y vale 0).
var rooms: Array[Dictionary] = []

## Muebles: cada uno es {"id": String, "cell": Vector2i, "rotation": int,
## "assigned_to": String, "computer": String}. cell es la casilla de anclaje,
## assigned_to dice quién lo usa ("" si nadie) y computer, la computadora instalada
## en un escritorio ("" si no tiene). Comprar, girar y vender lo hace Builder.
var furniture: Array[Dictionary] = []

## Lo que se pagó por el terreno comprado (cuenta en el valor de la empresa).
var land_paid: int = 0

## Casilla del borde del local por la que se entra y se sale.
var entrance := Vector2i.ZERO



## Indica si hay una partida cargada (nueva o guardada).
func has_game() -> bool:
	return lot.has_area()


## Prepara la oficina de una partida nueva: el local inicial y lo que dice
## STARTING_OFFICE_PATH.
func new_game() -> void:
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


## Índice en furniture del mueble que ocupa una casilla, o -1 si está libre.
func find_furniture_at(cell: Vector2i) -> int:
	for index: int in range(furniture.size()):
		var item: Dictionary = furniture[index]
		if FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"]).has(cell):
			return index
	return -1


## Pieza en un borde: ConstructionCatalog.WALL, DOOR o "" si está libre.
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
	return get_edge(edge) == ConstructionCatalog.WALL


## Casilla de fuera del local a la que se sale por la entrada: la vecina fuera del
## local cuyo borde tiene la puerta (o, si no hay puerta, la primera vecina de fuera).
func get_outside_of_entrance() -> Vector2i:
	var fallback := Vector2i(-1, -1)
	for direction: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		var outside: Vector2i = entrance + direction
		if lot.has_point(outside):
			continue
		if get_edge(GridEdge.between(entrance, outside)) == ConstructionCatalog.DOOR:
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
	var taken: Array[Vector2i] = get_furniture_cells()
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
			"assigned_to": item["assigned_to"], "computer": item["computer"]})
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
	entrance = _to_cell(state.get("entrance", [0, 0]))


func _furniture_from_data(item: Dictionary) -> Dictionary:
	return {
		"id": String(item["id"]),
		"cell": _to_cell(item["cell"]),
		"rotation": int(item.get("rotation", 0)),
		"assigned_to": String(item.get("assigned_to", "")),
		"computer": String(item.get("computer", "")),
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
