# Estado de la oficina: casillas, paredes, muebles y habitaciones, en coordenadas de cuadrícula.
# Hito 3: el local y la oficina inicial. Las paredes llegan en el hito 5, los muebles
# en el 6 y la detección de habitaciones en el 7.
extends Node

## Oficina con la que empieza toda partida nueva.
const STARTING_OFFICE_PATH: String = "res://data/starting_office.json"

## Casillas que ocupa el local.
var lot_rect := Rect2i()

## Habitaciones: cada una es {"type": String, "cells": Array[Vector2i]}.
var rooms: Array[Dictionary] = []

## Muebles: cada uno es {"id": String, "cell": Vector2i, "rotation": int,
## "assigned_to": String}. assigned_to dice quién lo usa ("" si nadie).
## Los de la oficina inicial se dibujan fijos; colocarlos y venderlos llega en el hito 6.
var furniture: Array[Dictionary] = []

## Casilla del borde del local por la que se entra y se sale.
var entrance := Vector2i.ZERO

## Horario del CEO: {"days": Array, "start_hour": int, "end_hour": int} (ver WorkSchedule).
var ceo_schedule: Dictionary = {}


## Indica si hay una partida cargada (nueva o guardada).
func has_game() -> bool:
	return lot_rect.has_area()


## Prepara la oficina de una partida nueva: el local inicial y lo que dice
## STARTING_OFFICE_PATH.
func new_game() -> void:
	lot_rect = Rect2i(Vector2i.ZERO, GameConstants.STARTING_LOT_SIZE)
	rooms.clear()
	furniture.clear()
	var data: Dictionary = _load_json(STARTING_OFFICE_PATH)
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
	ceo_schedule = WorkSchedule.from_dict(data.get("ceo_schedule", {})).to_dict()


## Devuelve el primer mueble asignado a alguien (por ejemplo, "ceo"), o un diccionario vacío.
func find_furniture_assigned_to(who: String) -> Dictionary:
	for item: Dictionary in furniture:
		if item["assigned_to"] == who:
			return item
	return {}


## Todas las casillas ocupadas por muebles.
func get_furniture_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for item: Dictionary in furniture:
		cells.append_array(FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"]))
	return cells


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
			"assigned_to": item["assigned_to"]})
	return {
		"lot": [lot_rect.position.x, lot_rect.position.y, lot_rect.size.x, lot_rect.size.y],
		"rooms": saved_rooms,
		"furniture": saved_furniture,
		"entrance": [entrance.x, entrance.y],
		"ceo_schedule": ceo_schedule.duplicate(true),
	}


## Restaura el estado de la oficina desde una partida guardada (hito 9).
func import_state(state: Dictionary) -> void:
	var lot: Array = state.get("lot", [0, 0, 0, 0])
	lot_rect = Rect2i(int(lot[0]), int(lot[1]), int(lot[2]), int(lot[3]))
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
	ceo_schedule = WorkSchedule.from_dict(state.get("ceo_schedule", {})).to_dict()


func _furniture_from_data(item: Dictionary) -> Dictionary:
	return {
		"id": String(item["id"]),
		"cell": _to_cell(item["cell"]),
		"rotation": int(item.get("rotation", 0)),
		"assigned_to": String(item.get("assigned_to", "")),
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
