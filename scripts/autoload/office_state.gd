# Estado de la oficina: casillas, paredes, muebles y habitaciones, en coordenadas de cuadrícula.
# Pisos y bordes (paredes y puertas) desde el hito 5; muebles en el 6 y detección de
# habitaciones en el 7. Este autoload solo guarda datos: comprar y vender lo hace Builder.
extends Node

## Oficina con la que empieza toda partida nueva.
const STARTING_OFFICE_PATH: String = "res://data/starting_office.json"

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

## Habitaciones: cada una es {"type": String, "cells": Array[Vector2i]}.
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


## Devuelve el estado de la oficina para guardarlo (hito 9). Las casillas se
## guardan como listas [x, y] para que pasen por JSON sin perderse.
func export_state() -> Dictionary:
	var saved_rooms: Array = []
	for room: Dictionary in rooms:
		var cells: Array = []
		for cell: Vector2i in room["cells"]:
			cells.append([cell.x, cell.y])
		saved_rooms.append({"type": room["type"], "cells": cells})
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
		rooms.append({"type": String(room["type"]), "cells": cells})
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
