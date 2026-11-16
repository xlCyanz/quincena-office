# Construcción, capa 1 de 4: paredes, puertas y pisos (quote/apply), cobro y reglas de acceso.
# Builder (builder.gd) hereda de las capas en orden; cada una solo llama a las de abajo.
extends RefCounted

## Conceptos de los movimientos de la cuenta.
const CONCEPT_CONSTRUCTION: String = "Construcción"
const CONCEPT_FURNITURE: String = "Muebles"
const CONCEPT_LAND: String = "Terreno"

## Lados del local hacia donde crece el terreno.
const SIDE_NORTH: String = "north"
const SIDE_SOUTH: String = "south"
const SIDE_EAST: String = "east"
const SIDE_WEST: String = "west"
const SIDES: Array[String] = [SIDE_NORTH, SIDE_SOUTH, SIDE_EAST, SIDE_WEST]

## Casillas con personajes (no se ponen muebles ahí).
## Ninguna casilla (para _edges_with_land).
const NO_CELL := Vector2i(-1000000, -1000000)

var occupied_cells: Array[Vector2i] = []


## Calcula un grupo de cambios sin aplicarlo: {"ok", "cost" (negativo si recupera), "message"}.
func quote(changes: Array[Dictionary]) -> Dictionary:
	var effective: Array[Dictionary] = _effective_changes(changes)
	if effective.is_empty():
		return {"ok": false, "cost": 0, "message": "No hay nada que cambiar ahí."}
	var cost: int = 0
	for change: Dictionary in effective:
		var old_kind: String = _paid_kind(change, _current_kind(change))
		if _is_owned(old_kind):
			cost -= ConstructionCatalog.get_refund(old_kind)
		if _is_owned(_paid_kind(change, change["kind"])):
			cost += ConstructionCatalog.get_price(change["kind"])
	for change: Dictionary in effective:
		if change.has("edge") and not GridEdge.touches_lot(change["edge"], OfficeState.lot):
			return {"ok": false, "cost": cost, "message": "Ese borde está fuera del local."}
		var exterior: bool = change.has("edge") and GridEdge.is_exterior(change["edge"], OfficeState.lot)
		if change.has("edge") and change["kind"] == ConstructionCatalog.WINDOW and not exterior:
			return {"ok": false, "cost": cost, "message": "Las ventanas solo van en las paredes exteriores del local."}
		if change.has("edge") and change["kind"] == ConstructionCatalog.GLASS_DOOR and not _is_entrance_swap(change):
			return {"ok": false, "cost": cost,
				"message": "La puerta de vidrio solo va en lugar de la puerta de entrada de la oficina."}
		if exterior and not _is_window_swap(change) and not _is_entrance_swap(change):
			return {"ok": false, "cost": cost, "message": "Las paredes exteriores no se pueden comprar ni vender."}
		if change.has("cell") and not OfficeState.lot.has_point(change["cell"]):
			return {"ok": false, "cost": cost, "message": "Esa casilla está fuera del local."}
		if change.has("cell") and change["kind"] == ConstructionCatalog.BARE_FLOOR:
			return {"ok": false, "cost": cost,
				"message": "El piso no se puede quitar, solo cambiar por otro: elige un piso y pásalo encima."}
	if not Economy.can_afford(cost):
		return {"ok": false, "cost": cost, "message": "No alcanza el dinero: cuesta $%d." % cost}
	for change: Dictionary in effective:
		if change.has("edge") and not String(change["kind"]).is_empty() and _splits_furniture(change["edge"]):
			return {"ok": false, "cost": cost, "message": "No se puede poner en medio de un mueble."}
		if change.has("edge") and change["kind"] != ConstructionCatalog.WALL and not OfficeState.wall_items_on(change["edge"]).is_empty():
			return {"ok": false, "cost": cost, "message": "Hay algo colgado en esa pared: véndelo primero."}
	if not _changes_passage(effective):
		return {"ok": true, "cost": cost, "message": _describe(effective, cost)}
	var new_edges: Dictionary[Vector3i, String] = _edges_with(effective)
	if not _keeps_ceo_access(new_edges, OfficeState.furniture):
		return {"ok": false, "cost": cost,
			"message": "Así el CEO no podría llegar a su escritorio desde la entrada."}
	var spaces: Array[Dictionary] = RoomRules.find_spaces(OfficeState.lot, new_edges)
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


## Aplica un grupo de cambios si quote() lo permite; devuelve lo mismo.
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


# Quita cambios nulos y repetidos. Vender una ventana del contorno la vuelve pared.
func _effective_changes(changes: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for original: Dictionary in changes:
		var change: Dictionary = original
		if change.has("edge") and String(change["kind"]).is_empty() \
				and OfficeState.get_edge(change["edge"]) == ConstructionCatalog.WINDOW \
				and GridEdge.is_exterior(change["edge"], OfficeState.lot):
			change = {"edge": change["edge"], "kind": ConstructionCatalog.WALL}
		# Vender la puerta de vidrio (o reemplazarla) deja la puerta normal.
		if change.has("edge") and change["edge"] == OfficeState.get_entrance_edge() \
				and OfficeState.get_edge(change["edge"]) == ConstructionCatalog.GLASS_DOOR \
				and change["kind"] != ConstructionCatalog.GLASS_DOOR:
			change = {"edge": change["edge"], "kind": ConstructionCatalog.DOOR}
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


# Lo comprado que se puede vender (no un borde libre ni una casilla sin piso).
func _is_owned(kind: String) -> bool:
	return not kind.is_empty() and kind != ConstructionCatalog.BARE_FLOOR


# La pieza que cuenta para el precio: la del contorno no se compró ("").
func _paid_kind(change: Dictionary, kind: String) -> String:
	if change.has("edge") and (kind == ConstructionCatalog.WALL or kind == ConstructionCatalog.DOOR) \
			and GridEdge.is_exterior(change["edge"], OfficeState.lot):
		return ""
	return kind


# En el contorno solo se cambia pared por ventana o al revés.
func _is_window_swap(change: Dictionary) -> bool:
	var pieces: Array[String] = [ConstructionCatalog.WALL, ConstructionCatalog.WINDOW]
	return pieces.has(_current_kind(change)) and pieces.has(String(change["kind"]))


# En la entrada solo se cambia puerta por puerta de vidrio o al revés.
func _is_entrance_swap(change: Dictionary) -> bool:
	if not change.has("edge") or change["edge"] != OfficeState.get_entrance_edge():
		return false
	return ConstructionCatalog.is_door(_current_kind(change)) and ConstructionCatalog.is_door(String(change["kind"]))


func _changes_passage(changes: Array[Dictionary]) -> bool:
	for change: Dictionary in changes:
		if change.has("edge"):
			return true
	return false


# Bordes de la oficina con los cambios aplicados.
func _edges_with(changes: Array[Dictionary]) -> Dictionary[Vector3i, String]:
	var edges: Dictionary[Vector3i, String] = OfficeState.edges.duplicate()
	for change: Dictionary in changes:
		if change.has("edge"):
			if String(change["kind"]).is_empty():
				edges.erase(change["edge"])
			else:
				edges[change["edge"]] = change["kind"]
	return edges


# Tipos de las habitaciones actuales que no siguen en rooms.
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


# El CEO tiene que poder ir de la entrada a su silla.
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
	pathfinder.build(OfficeState.lot, OfficeState.blocking_cells_of(furniture), edges)
	return not pathfinder.find_path(OfficeState.entrance, seat["cell"]).is_empty()


func _describe(changes: Array[Dictionary], cost: int) -> String:
	var bought: Dictionary[String, int] = {}
	var sold: int = 0
	for change: Dictionary in changes:
		if _is_owned(_paid_kind(change, change["kind"])):
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


# Con candidate, lo que se alcanzaba desde la entrada sigue alcanzable (salvo el mueble), toda
# silla tiene acceso y el CEO llega a la suya.
func _access_problem(candidate: Array[Dictionary], item: Dictionary) -> String:
	var lot: Lot = OfficeState.lot
	var before := OfficePathfinder.new()
	before.build(lot, OfficeState.get_blocking_cells(), OfficeState.edges)
	var after := OfficePathfinder.new()
	var blocked_after: Array[Vector2i] = OfficeState.blocking_cells_of(candidate)
	after.build(lot, blocked_after, OfficeState.edges)
	var reachable_after: Dictionary[Vector2i, bool] = after.get_reachable(OfficeState.entrance)
	for cell: Vector2i in before.get_reachable(OfficeState.entrance):
		if not reachable_after.has(cell) and not blocked_after.has(cell):
			return "Así una parte de la oficina quedaría sin acceso."
	if bool(FurnitureCatalog.get_item(item["id"])["is_seat"]) and not _seat_reachable(after, reachable_after, item["cell"]):
		return "No se podría llegar a esa silla."
	# Una silla que ya está y se podía alcanzar tiene que seguir alcanzable.
	var reachable_before: Dictionary[Vector2i, bool] = before.get_reachable(OfficeState.entrance)
	for other: Dictionary in OfficeState.furniture:
		if other == item or not bool(FurnitureCatalog.get_item(other["id"]).get("is_seat", false)):
			continue
		if _seat_reachable(before, reachable_before, other["cell"]) and not _seat_reachable(after, reachable_after, other["cell"]):
			return "Así no se podría llegar a una silla."
	if not _keeps_ceo_access(OfficeState.edges, candidate):
		return "Así el CEO no podría llegar a su escritorio desde la entrada."
	return ""


# Indica si se llega a una silla: alguna vecina alcanzable sin pared entre ellas.
func _seat_reachable(pathfinder: OfficePathfinder, reachable: Dictionary[Vector2i, bool], seat: Vector2i) -> bool:
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var next: Vector2i = seat + direction
		if reachable.has(next) and pathfinder.can_cross(seat, next):
			return true
	return false
