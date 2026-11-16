# Reglas de construcción: costo, validez y aplicación sobre OfficeState cobrando con Economy.
# Un cambio es {"edge", "kind"} (kind "" vende) o {"cell", "kind"} para pisos; un grupo se cobra
# entero o nada. El contorno no se compra ni vende y los pisos solo se cambian. Los muebles tienen
# sus funciones con su quote_; no pueden tapar la entrada, a un personaje ni el acceso a nada.
# Las habitaciones se marcan gratis; un cambio de paredes que desharía una bloqueada no se permite.
class_name Builder
extends "res://scripts/office/builder_land.gd"


# --- Habitaciones ----------------------------------------------------------------
## Marca con un tipo el espacio de cell (gratis); si era otra, cambia de tipo. Se marca aunque no
## funcione aún: el mensaje lo avisa.
func quote_mark_room(type_id: String, cell: Vector2i) -> Dictionary:
	if RoomCatalog.get_type(type_id).is_empty():
		return _fail(0, "Ese tipo de habitación no existe.")
	if not Company.is_room_unlocked(type_id):
		return _fail(0, Company.room_lock_reason(type_id))
	if not OfficeState.lot.has_point(cell):
		return _fail(0, "Esa casilla está fuera del local.")
	var spaces: Array[Dictionary] = RoomRules.find_spaces(OfficeState.lot, OfficeState.edges)
	var space: Dictionary = spaces[RoomRules.space_index_at(spaces, cell)]
	var type_name: String = RoomCatalog.get_display_name(type_id)
	var current: int = RoomRules.room_index_at(OfficeState.rooms, cell)
	if current >= 0 and OfficeState.rooms[current]["type"] == type_id:
		return _room_status(OfficeState.rooms[current], false)
	if type_id == OfficeState.EXECUTIVE_OFFICE and not OfficeState.find_room(type_id).is_empty():
		# Ya hay Oficina Ejecutiva: marcarla aquí es mudarla (pide confirmar).
		return quote_move_ceo_office(cell)
	var problem: String = RoomRules.mark_problem(type_id, space, OfficeState.rooms, OfficeState.entrance)
	if not problem.is_empty():
		return _fail(0, problem)
	var cells: Array[Vector2i] = space["cells"]
	var room: Dictionary = {"type": type_id, "cells": cells.duplicate()}
	var rooms: Array[Dictionary] = []
	for other: Dictionary in OfficeState.rooms:
		if not RoomRules.shares_cells(other["cells"], cells):
			rooms.append(other)
	rooms.append(room)
	var message: String = "Marcar como %s (%d m²)" % [type_name, cells.size()]
	var problems: Array[String] = RoomRules.function_problems(room, OfficeState.furniture)
	if not problems.is_empty():
		message += ". No funcionará: %s" % ", ".join(problems)
	return {"ok": true, "cost": 0, "message": message + ".", "rooms": rooms}


func mark_room(type_id: String, cell: Vector2i) -> Dictionary:
	return _commit_rooms(quote_mark_room(type_id, cell))


## Cotiza mudar la Oficina Ejecutiva al espacio de cell (cerrado, con puerta y una silla libre frente
## a un escritorio de ahí). El CEO pasa a esa silla y la vieja queda sin marcar. Trae "confirm": true.
func quote_move_ceo_office(cell: Vector2i) -> Dictionary:
	var type_id: String = OfficeState.EXECUTIVE_OFFICE
	var type_name: String = RoomCatalog.get_display_name(type_id)
	if not OfficeState.lot.has_point(cell):
		return _fail(0, "Esa casilla está fuera del local.")
	var old_room: Dictionary = OfficeState.find_room(type_id)
	var spaces: Array[Dictionary] = RoomRules.find_spaces(OfficeState.lot, OfficeState.edges)
	var space: Dictionary = spaces[RoomRules.space_index_at(spaces, cell)]
	var cells: Array[Vector2i] = space["cells"]
	if not old_room.is_empty() and RoomRules.shares_cells(old_room["cells"], cells):
		return _room_status(old_room, false)
	# Igual que al marcarla, sin contar la que se muda.
	var others: Array[Dictionary] = []
	for room: Dictionary in OfficeState.rooms:
		if room["type"] != type_id:
			others.append(room)
	var problem: String = RoomRules.mark_problem(type_id, space, others, OfficeState.entrance)
	if not problem.is_empty():
		return _fail(0, problem)
	var seat: int = _free_seat_with_desk(cells)
	if seat < 0:
		return _fail(0, "Para mudar la %s ahí hace falta un escritorio con una silla libre delante." % type_name)
	var furniture: Array[Dictionary] = []
	for index: int in range(OfficeState.furniture.size()):
		var item: Dictionary = OfficeState.furniture[index].duplicate()
		if item["assigned_to"] == "ceo":
			item["assigned_to"] = ""
		if index == seat:
			item["assigned_to"] = "ceo"
		furniture.append(item)
	var moved: Dictionary = {"type": type_id, "cells": cells.duplicate()}
	var rooms: Array[Dictionary] = []
	for room: Dictionary in others:
		if not RoomRules.shares_cells(room["cells"], cells):
			rooms.append(room)
	rooms.append(moved)
	# Corto: una línea del modo construcción. Lo que falte se dice al mudarla.
	var message: String = "¿Mudar la %s aquí? El CEO pasa a esta silla; la de antes queda sin marcar." % type_name
	var problems: Array[String] = RoomRules.function_problems(moved, furniture)
	return {"ok": true, "cost": 0, "confirm": true, "message": message, "rooms": rooms, "furniture": furniture,
		"seat": OfficeState.furniture[seat]["cell"], "problems": problems}


## Muda la Oficina Ejecutiva si quote_move_ceo_office lo permite (ya confirmado).
func move_ceo_office(cell: Vector2i) -> Dictionary:
	var result: Dictionary = quote_move_ceo_office(cell)
	if not result["ok"] or not result.has("rooms"):
		return result
	var furniture: Array[Dictionary] = result["furniture"]
	var rooms: Array[Dictionary] = result["rooms"]
	OfficeState.furniture = furniture
	OfficeState.rooms = rooms
	result.erase("furniture")
	result.erase("rooms")
	result.erase("confirm")
	result["message"] = "La %s se mudó." % RoomCatalog.get_display_name(OfficeState.EXECUTIVE_OFFICE)
	var problems: Array = result.get("problems", [])
	if not problems.is_empty():
		result["message"] += " Aún no funciona: %s." % ", ".join(problems)
	EventBus.office_changed.emit()
	return result


# Índice de una silla sin dueño en cells con el frente de un escritorio o mostrador de cells delante; -1 si no.
func _free_seat_with_desk(cells: Array[Vector2i]) -> int:
	for index: int in range(OfficeState.furniture.size()):
		var item: Dictionary = OfficeState.furniture[index]
		if not bool(FurnitureCatalog.get_item(item["id"]).get("is_seat", false)) or not String(item["assigned_to"]).is_empty():
			continue
		if not cells.has(item["cell"]):
			continue
		var desk: Dictionary = OfficeState.get_desk_facing(item["cell"])
		if desk.is_empty():
			continue
		var front: Vector2i = FurnitureCatalog.FRONT_DIRECTIONS[int(desk["direction"])]
		if cells.has(item["cell"] + front):
			return index
	return -1


## Quita la habitación de cell; el espacio queda sin tipo.
func quote_unmark_room(cell: Vector2i) -> Dictionary:
	var index: int = RoomRules.room_index_at(OfficeState.rooms, cell)
	if index < 0:
		return _fail(0, "Ahí no hay ninguna habitación.")
	var type_id: String = OfficeState.rooms[index]["type"]
	if RoomCatalog.is_locked(type_id):
		return _fail(0, "La %s no se puede quitar." % RoomCatalog.get_display_name(type_id))
	var rooms: Array[Dictionary] = OfficeState.rooms.duplicate()
	rooms.remove_at(index)
	return {"ok": true, "cost": 0, "rooms": rooms,
		"message": "Quitar la habitación %s." % RoomCatalog.get_display_name(type_id)}


func unmark_room(cell: Vector2i) -> Dictionary:
	return _commit_rooms(quote_unmark_room(cell))


## Estado de una habitación para el jugador: si funciona (ok) o qué le falta.
func room_status(room: Dictionary) -> Dictionary:
	return _room_status(room, true)


func _room_status(room: Dictionary, ok_if_working: bool) -> Dictionary:
	var type_name: String = RoomCatalog.get_display_name(room["type"])
	var cells: Array[Vector2i] = room["cells"]
	var problems: Array[String] = RoomRules.function_problems(room, OfficeState.furniture)
	var racks: String = ""
	if room["type"] == OfficeState.SERVER_ROOM:
		var count: int = OfficeState.count_racks(room)
		racks = " %d %s." % [count, "rack" if count == 1 else "racks"]
	var ambiance: String = " %s." % Ambiance.describe(room, OfficeState.furniture, OfficeState.count_room_windows(room),
		OfficeState.get_room_door_ambiance(room))
	if problems.is_empty():
		return {"ok": ok_if_working, "cost": 0, "message": "%s (%d m²): funciona.%s%s" % [type_name, cells.size(), racks, ambiance]}
	return {"ok": false, "cost": 0,
		"message": "%s (%d m²): no funciona, %s.%s" % [type_name, cells.size(), ", ".join(problems), ambiance]}


func _commit_rooms(result: Dictionary) -> Dictionary:
	if not result["ok"] or not result.has("rooms"):
		return result
	if bool(result.get("confirm", false)):
		# Mudar no se hace sin preguntar: lo hace move_ceo_office.
		return {"ok": false, "cost": 0, "confirm": true, "message": result["message"]}
	var rooms: Array[Dictionary] = result["rooms"]
	OfficeState.rooms = rooms
	EventBus.office_changed.emit()
	result.erase("rooms")
	return result
