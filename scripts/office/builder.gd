# Reglas de la construcción: cuánto cuesta cada cambio, si se puede hacer y aplicarlo
# sobre OfficeState cobrando o devolviendo dinero con Economy.
#
# Un cambio es un diccionario {"edge": Vector3i, "kind": String} para paredes y puertas
# (kind = "" para vender) o {"cell": Vector2i, "kind": String} para pisos (kind =
# ConstructionCatalog.BARE_FLOOR para vender). Reemplazar una pieza vende la anterior y
# compra la nueva. Varios cambios juntos (por ejemplo, una fila de paredes) se cobran
# todos o ninguno.
#
# Los muebles tienen sus propias funciones (place, rotate, sell_furniture_at,
# install_computer), cada una con su quote_ para la vista previa. Un mueble no puede
# ponerse sobre otro, ni sobre la entrada o un personaje, ni dejar sin acceso una parte
# de la oficina que lo tenía, ni una silla nueva sin acceso.
#
# Las habitaciones (hito 7) se marcan gratis con mark_room y unmark_room. Al cambiar
# las paredes se recalculan con RoomRules; un cambio que desharía una habitación
# bloqueada (la Oficina Ejecutiva) no se permite, y las demás se deshacen con aviso.
class_name Builder
extends RefCounted

## Conceptos de los movimientos de la cuenta empresarial.
const CONCEPT_CONSTRUCTION: String = "Construcción"
const CONCEPT_FURNITURE: String = "Muebles"

## Casillas donde hay personajes (por ejemplo, el CEO): ahí no se pueden poner muebles.
var occupied_cells: Array[Vector2i] = []


## Calcula un grupo de cambios sin aplicarlo. Devuelve {"ok": bool, "cost": int,
## "message": String}; cost es lo que se paga (negativo si se recupera dinero).
func quote(changes: Array[Dictionary]) -> Dictionary:
	var effective: Array[Dictionary] = _effective_changes(changes)
	if effective.is_empty():
		return {"ok": false, "cost": 0, "message": "No hay nada que cambiar ahí."}
	var cost: int = 0
	for change: Dictionary in effective:
		var old_kind: String = _current_kind(change)
		if _is_owned(old_kind):
			cost -= ConstructionCatalog.get_refund(old_kind)
		if _is_owned(change["kind"]):
			cost += ConstructionCatalog.get_price(change["kind"])
	for change: Dictionary in effective:
		if change.has("edge") and not GridEdge.touches_lot(change["edge"], OfficeState.lot_rect):
			return {"ok": false, "cost": cost, "message": "Ese borde está fuera del local."}
		if change.has("cell") and not OfficeState.lot_rect.has_point(change["cell"]):
			return {"ok": false, "cost": cost, "message": "Esa casilla está fuera del local."}
	if not Economy.can_afford(cost):
		return {"ok": false, "cost": cost, "message": "No alcanza el dinero: cuesta $%d." % cost}
	for change: Dictionary in effective:
		if change.has("edge") and not String(change["kind"]).is_empty() and _splits_furniture(change["edge"]):
			return {"ok": false, "cost": cost, "message": "No se puede poner en medio de un mueble."}
	if not _changes_passage(effective):
		return {"ok": true, "cost": cost, "message": _describe(effective, cost)}
	var new_edges: Dictionary[Vector3i, String] = _edges_with(effective)
	if not _keeps_ceo_access(new_edges, OfficeState.furniture):
		return {"ok": false, "cost": cost,
			"message": "Así el CEO no podría llegar a su escritorio desde la entrada."}
	var spaces: Array[Dictionary] = RoomRules.find_spaces(OfficeState.lot_rect, new_edges)
	var rooms: Array[Dictionary] = RoomRules.reconcile(OfficeState.rooms, spaces, OfficeState.entrance,
		OfficeState.furniture)
	var lost: Array[String] = _lost_rooms(rooms)
	for type_id: String in lost:
		if RoomCatalog.is_locked(type_id):
			return {"ok": false, "cost": cost,
				"message": "Así se desharía la %s." % RoomCatalog.get_display_name(type_id)}
	var message: String = _describe(effective, cost)
	if not lost.is_empty():
		var names: Array[String] = []
		for type_id: String in lost:
			names.append(RoomCatalog.get_display_name(type_id))
		message += ". Se deshace: %s" % ", ".join(names)
	return {"ok": true, "cost": cost, "message": message, "rooms": rooms}


## Aplica un grupo de cambios si quote() lo permite. Devuelve lo mismo que quote().
func apply(changes: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = quote(changes)
	if not result["ok"]:
		return result
	for change: Dictionary in _effective_changes(changes):
		if change.has("edge"):
			OfficeState.set_edge(change["edge"], change["kind"])
		else:
			OfficeState.set_floor(change["cell"], change["kind"])
	if result.has("rooms"):
		var rooms: Array[Dictionary] = result["rooms"]
		OfficeState.rooms = rooms
		result.erase("rooms")
	if result["cost"] >= 0:
		Economy.spend(result["cost"], CONCEPT_CONSTRUCTION)
	else:
		Economy.earn(-result["cost"], CONCEPT_CONSTRUCTION)
	EventBus.office_changed.emit()
	return result


# Quita los cambios que no cambian nada (poner lo que ya hay) y los repetidos.
func _effective_changes(changes: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for change: Dictionary in changes:
		var key: Variant = change.get("edge", change.get("cell"))
		if seen.has(key) or _current_kind(change) == change["kind"]:
			continue
		seen[key] = true
		result.append(change)
	return result


func _current_kind(change: Dictionary) -> String:
	if change.has("edge"):
		return OfficeState.get_edge(change["edge"])
	return OfficeState.get_floor(change["cell"])


# Lo que se compró y se puede vender (no un borde libre ni una casilla sin piso).
func _is_owned(kind: String) -> bool:
	return not kind.is_empty() and kind != ConstructionCatalog.BARE_FLOOR


func _changes_passage(changes: Array[Dictionary]) -> bool:
	for change: Dictionary in changes:
		if change.has("edge"):
			return true
	return false


# Los bordes de la oficina con los cambios de bordes aplicados.
func _edges_with(changes: Array[Dictionary]) -> Dictionary[Vector3i, String]:
	var edges: Dictionary[Vector3i, String] = OfficeState.edges.duplicate()
	for change: Dictionary in changes:
		if change.has("edge"):
			if String(change["kind"]).is_empty():
				edges.erase(change["edge"])
			else:
				edges[change["edge"]] = change["kind"]
	return edges


# Tipos de las habitaciones actuales que no siguen en rooms (una vez por habitación).
func _lost_rooms(rooms: Array[Dictionary]) -> Array[String]:
	var remaining: Array[String] = []
	for room: Dictionary in rooms:
		remaining.append(room["type"])
	var lost: Array[String] = []
	for room: Dictionary in OfficeState.rooms:
		if remaining.has(room["type"]):
			remaining.erase(room["type"])
		else:
			lost.append(room["type"])
	return lost


# Indica si el borde queda entre dos casillas del mismo mueble.
func _splits_furniture(edge: Vector3i) -> bool:
	var cells: Array[Vector2i] = GridEdge.get_cells(edge)
	var index: int = OfficeState.find_furniture_at(cells[0])
	return index >= 0 and index == OfficeState.find_furniture_at(cells[1])


# El CEO tiene que poder salir del local por la puerta de entrada y llegar desde ella
# hasta su silla.
func _keeps_ceo_access(edges: Dictionary[Vector3i, String], furniture: Array[Dictionary]) -> bool:
	var entrance_edge: Vector3i = GridEdge.between(OfficeState.entrance, OfficeState.get_outside_of_entrance())
	if edges.get(entrance_edge, "") == ConstructionCatalog.WALL:
		return false
	var seat: Dictionary = {}
	for item: Dictionary in furniture:
		if item["assigned_to"] == "ceo":
			seat = item
	if seat.is_empty():
		return true
	var pathfinder := OfficePathfinder.new()
	pathfinder.build(OfficeState.lot_rect, OfficeState.cells_of_furniture(furniture), edges)
	return not pathfinder.find_path(OfficeState.entrance, seat["cell"]).is_empty()


func _describe(changes: Array[Dictionary], cost: int) -> String:
	var bought: Dictionary[String, int] = {}
	var sold: int = 0
	for change: Dictionary in changes:
		if _is_owned(change["kind"]):
			bought[change["kind"]] = bought.get(change["kind"], 0) + 1
		else:
			sold += 1
	var parts: Array[String] = []
	for kind: String in bought:
		var piece_name: String = ConstructionCatalog.get_display_name(kind)
		parts.append("%s ×%d" % [piece_name, bought[kind]] if bought[kind] > 1 else piece_name)
	if sold > 0:
		parts.append("Venta ×%d" % sold if sold > 1 else "Venta")
	var amount: String = "−$%d" % cost if cost >= 0 else "+$%d" % -cost
	return "%s: %s" % [", ".join(parts), amount]


# --- Muebles ---------------------------------------------------------------------


## Comprar un mueble y colocarlo con su casilla de anclaje y su rotación.
func quote_place(id: String, anchor: Vector2i, rotation: int) -> Dictionary:
	var info: Dictionary = FurnitureCatalog.get_item(id)
	if info.is_empty() or bool(info["on_desk"]):
		return _fail(0, "Ese objeto no se coloca en el piso.")
	var item: Dictionary = {"id": id, "cell": anchor, "rotation": posmod(rotation, 4),
		"assigned_to": "", "computer": ""}
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	candidate.append(item)
	var cost: int = FurnitureCatalog.get_price(id)
	var problem: String = _placement_problem(candidate, item)
	if problem.is_empty() and not Economy.can_afford(cost):
		problem = "No alcanza el dinero: cuesta $%d." % cost
	if not problem.is_empty():
		return _fail(cost, problem)
	return {"ok": true, "cost": cost, "message": "%s: −$%d" % [info["name"], cost], "furniture": candidate}


func place(id: String, anchor: Vector2i, rotation: int) -> Dictionary:
	return _commit(quote_place(id, anchor, rotation))


## Girar un cuarto de vuelta el mueble que ocupa cell. Es gratis, pero el mueble girado
## tiene que caber (las casillas nuevas se cuentan desde la misma casilla de anclaje).
func quote_rotate(cell: Vector2i) -> Dictionary:
	var index: int = OfficeState.find_furniture_at(cell)
	if index < 0:
		return _fail(0, "Ahí no hay ningún mueble.")
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	var item: Dictionary = candidate[index].duplicate()
	item["rotation"] = posmod(int(item["rotation"]) + 1, 4)
	candidate[index] = item
	var problem: String = _placement_problem(candidate, item)
	if not problem.is_empty():
		return _fail(0, problem)
	var item_name: String = FurnitureCatalog.get_item(item["id"])["name"]
	return {"ok": true, "cost": 0, "message": "%s girado." % item_name, "furniture": candidate}


func rotate(cell: Vector2i) -> Dictionary:
	return _commit(quote_rotate(cell))


## Vender lo que hay en cell: si es un escritorio con computadora, primero la
## computadora; si no, el mueble. La silla del CEO no se vende.
func quote_sell_furniture_at(cell: Vector2i) -> Dictionary:
	var index: int = OfficeState.find_furniture_at(cell)
	if index < 0:
		return _fail(0, "Ahí no hay ningún mueble.")
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	var item: Dictionary = candidate[index].duplicate()
	if not String(item["computer"]).is_empty():
		var refund: int = FurnitureCatalog.get_resale(item["computer"])
		var computer_name: String = FurnitureCatalog.get_item(item["computer"])["name"]
		item["computer"] = ""
		candidate[index] = item
		return {"ok": true, "cost": -refund, "message": "Venta de %s: +$%d" % [computer_name, refund],
			"furniture": candidate}
	if not String(item["assigned_to"]).is_empty():
		return _fail(0, "La silla del CEO no se puede vender.")
	candidate.remove_at(index)
	var resale: int = FurnitureCatalog.get_resale(item["id"])
	var item_name: String = FurnitureCatalog.get_item(item["id"])["name"]
	return {"ok": true, "cost": -resale, "message": "Venta de %s: +$%d" % [item_name, resale],
		"furniture": candidate}


func sell_furniture_at(cell: Vector2i) -> Dictionary:
	return _commit(quote_sell_furniture_at(cell))


## Instalar una computadora en el escritorio que ocupa cell (uno por escritorio).
func quote_install_computer(computer_id: String, cell: Vector2i) -> Dictionary:
	var index: int = OfficeState.find_furniture_at(cell)
	if index < 0 or not bool(FurnitureCatalog.get_item(OfficeState.furniture[index]["id"])["accepts_computer"]):
		return _fail(0, "La computadora va sobre un escritorio.")
	var item: Dictionary = OfficeState.furniture[index].duplicate()
	if not String(item["computer"]).is_empty():
		return _fail(0, "Ese escritorio ya tiene computadora.")
	var cost: int = FurnitureCatalog.get_price(computer_id)
	if not Economy.can_afford(cost):
		return _fail(cost, "No alcanza el dinero: cuesta $%d." % cost)
	item["computer"] = computer_id
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	candidate[index] = item
	var computer_name: String = FurnitureCatalog.get_item(computer_id)["name"]
	return {"ok": true, "cost": cost, "message": "%s: −$%d" % [computer_name, cost], "furniture": candidate}


func install_computer(computer_id: String, cell: Vector2i) -> Dictionary:
	return _commit(quote_install_computer(computer_id, cell))


func _fail(cost: int, message: String) -> Dictionary:
	return {"ok": false, "cost": cost, "message": message}


# Aplica una cotización correcta: cambia los muebles, cobra o devuelve y avisa.
func _commit(result: Dictionary) -> Dictionary:
	if not result["ok"]:
		return result
	var furniture: Array[Dictionary] = result["furniture"]
	OfficeState.furniture = furniture
	if result["cost"] >= 0:
		Economy.spend(result["cost"], CONCEPT_FURNITURE)
	else:
		Economy.earn(-result["cost"], CONCEPT_FURNITURE)
	EventBus.office_changed.emit()
	result.erase("furniture")
	return result


# Motivo por el que item (ya dentro de candidate) no puede quedar así, o "" si puede.
func _placement_problem(candidate: Array[Dictionary], item: Dictionary) -> String:
	var cells: Array[Vector2i] = FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"])
	for cell: Vector2i in cells:
		if not OfficeState.lot_rect.has_point(cell):
			return "No cabe: se sale del local."
		if cell == OfficeState.entrance:
			return "No se puede tapar la entrada."
		if occupied_cells.has(cell):
			return "Hay alguien en esa casilla."
	var others: Array[Dictionary] = candidate.duplicate()
	others.erase(item)
	var taken: Array[Vector2i] = OfficeState.cells_of_furniture(others)
	for cell: Vector2i in cells:
		if taken.has(cell):
			return "Ahí ya hay otro objeto."
	for a: Vector2i in cells:
		for b: Vector2i in cells:
			var step: Vector2i = (b - a).abs()
			if step.x + step.y == 1 and not OfficeState.get_edge(GridEdge.between(a, b)).is_empty():
				return "Hay una pared en medio."
	return _access_problem(candidate, item)


# Con candidate, toda casilla a la que se llegaba desde la entrada tiene que seguir
# alcanzable (salvo las que ocupa el mueble), una silla tiene que tener acceso y el
# CEO tiene que poder llegar a la suya.
func _access_problem(candidate: Array[Dictionary], item: Dictionary) -> String:
	var lot: Rect2i = OfficeState.lot_rect
	var before := OfficePathfinder.new()
	before.build(lot, OfficeState.get_furniture_cells(), OfficeState.edges)
	var after := OfficePathfinder.new()
	var blocked_after: Array[Vector2i] = OfficeState.cells_of_furniture(candidate)
	after.build(lot, blocked_after, OfficeState.edges)
	var reachable_after: Dictionary[Vector2i, bool] = after.get_reachable(OfficeState.entrance)
	for cell: Vector2i in before.get_reachable(OfficeState.entrance):
		if not reachable_after.has(cell) and not blocked_after.has(cell):
			return "Así una parte de la oficina quedaría sin acceso."
	if bool(FurnitureCatalog.get_item(item["id"])["is_seat"]):
		var seat: Vector2i = item["cell"]
		var reachable_seat: bool = false
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = seat + direction
			if reachable_after.has(next) and after.can_cross(seat, next):
				reachable_seat = true
		if not reachable_seat:
			return "No se podría llegar a esa silla."
	if not _keeps_ceo_access(OfficeState.edges, candidate):
		return "Así el CEO no podría llegar a su escritorio desde la entrada."
	return ""


# --- Habitaciones ----------------------------------------------------------------


## Marcar como habitación de un tipo el espacio que contiene cell (no cuesta dinero).
## Si ya era otra habitación, cambia de tipo. Se puede marcar aunque todavía le
## falten tamaño o muebles para funcionar: el mensaje lo avisa.
func quote_mark_room(type_id: String, cell: Vector2i) -> Dictionary:
	if RoomCatalog.get_type(type_id).is_empty():
		return _fail(0, "Ese tipo de habitación no existe.")
	if not OfficeState.lot_rect.has_point(cell):
		return _fail(0, "Esa casilla está fuera del local.")
	var spaces: Array[Dictionary] = RoomRules.find_spaces(OfficeState.lot_rect, OfficeState.edges)
	var space: Dictionary = spaces[RoomRules.space_index_at(spaces, cell)]
	var type_name: String = RoomCatalog.get_display_name(type_id)
	var current: int = RoomRules.room_index_at(OfficeState.rooms, cell)
	if current >= 0 and OfficeState.rooms[current]["type"] == type_id:
		return _room_status(OfficeState.rooms[current], false)
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


## Quitar la habitación que contiene cell; el espacio queda sin tipo.
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


## Estado de una habitación para el jugador: si funciona o qué le falta. ok dice si
## funciona.
func room_status(room: Dictionary) -> Dictionary:
	return _room_status(room, true)


func _room_status(room: Dictionary, ok_if_working: bool) -> Dictionary:
	var type_name: String = RoomCatalog.get_display_name(room["type"])
	var cells: Array[Vector2i] = room["cells"]
	var problems: Array[String] = RoomRules.function_problems(room, OfficeState.furniture)
	if problems.is_empty():
		return {"ok": ok_if_working, "cost": 0, "message": "%s (%d m²): funciona." % [type_name, cells.size()]}
	return {"ok": false, "cost": 0,
		"message": "%s (%d m²): no funciona, %s." % [type_name, cells.size(), ", ".join(problems)]}


func _commit_rooms(result: Dictionary) -> Dictionary:
	if not result["ok"] or not result.has("rooms"):
		return result
	var rooms: Array[Dictionary] = result["rooms"]
	OfficeState.rooms = rooms
	EventBus.office_changed.emit()
	result.erase("rooms")
	return result
