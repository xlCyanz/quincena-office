# Reglas de construcción: costo, validez y aplicación sobre OfficeState cobrando con Economy.
# Un cambio es {"edge", "kind"} (kind "" vende) o {"cell", "kind"} para pisos; un grupo se cobra
# entero o nada. El contorno no se compra ni vende y los pisos solo se cambian. Los muebles tienen
# sus funciones con su quote_; no pueden tapar la entrada, a un personaje ni el acceso a nada.
# Las habitaciones se marcan gratis; un cambio de paredes que desharía una bloqueada no se permite.
class_name Builder
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


# --- Muebles ---------------------------------------------------------------------


## Compra y coloca un mueble. Uno chico va en el cuarto quarter (0–3); sin cuarto, el primero libre.
func quote_place(id: String, anchor: Vector2i, rotation: int, quarter: int = -1) -> Dictionary:
	var info: Dictionary = FurnitureCatalog.get_item(id)
	if info.is_empty() or bool(info["on_desk"]):
		return _fail(0, "Ese objeto no se coloca en el piso.")
	if FurnitureCatalog.is_small(id) and quarter < 0:
		quarter = _free_quarter(id, anchor)
	var item: Dictionary = {"id": id, "cell": anchor, "rotation": posmod(rotation, 4),
		"assigned_to": "", "computer": "", "monitor": "", "monitors": 0, "quarter": quarter if FurnitureCatalog.is_small(id) else -1}
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	candidate.append(item)
	var cost: int = FurnitureCatalog.get_price(id)
	var problem: String = _wall_problem(item) if bool(info["wall_mounted"]) else _placement_problem(candidate, item)
	if problem.is_empty() and not Economy.can_afford(cost):
		problem = "No alcanza el dinero: cuesta $%d." % cost
	if not problem.is_empty():
		return _fail(cost, problem)
	return {"ok": true, "cost": cost, "message": "%s: −$%d" % [info["name"], cost], "furniture": candidate}


func place(id: String, anchor: Vector2i, rotation: int, quarter: int = -1) -> Dictionary:
	return _commit(quote_place(id, anchor, rotation, quarter))


# Primer cuarto libre de una casilla (0 si no hay).
func _free_quarter(id: String, cell: Vector2i) -> int:
	for quarter: int in range(FurnitureCatalog.QUARTERS):
		var probe: Dictionary = {"id": id, "cell": cell, "rotation": 0, "quarter": quarter}
		if not OfficeState.furniture.any(func(other: Dictionary) -> bool: return FurnitureCatalog.overlaps(probe, other)):
			return quarter
	return 0


## Vende el objeto colgado en una cara de pared (casilla y rotación que deja la pared detrás).
func quote_sell_wall_item(cell: Vector2i, rotation: int) -> Dictionary:
	var index: int = OfficeState.find_wall_item(cell, rotation)
	if index < 0:
		return _fail(0, "Ahí no hay nada colgado.")
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	var item: Dictionary = candidate[index]
	candidate.remove_at(index)
	var resale: int = FurnitureCatalog.get_resale(item["id"])
	var item_name: String = FurnitureCatalog.get_item(item["id"])["name"]
	return {"ok": true, "cost": -resale, "message": "Venta de %s: +$%d" % [item_name, resale], "furniture": candidate}


func sell_wall_item(cell: Vector2i, rotation: int) -> Dictionary:
	return _commit(quote_sell_wall_item(cell, rotation))


# Un objeto de pared va en una cara de pared libre (no puerta) del local, una por cara.
func _wall_problem(item: Dictionary) -> String:
	if not OfficeState.lot.has_point(item["cell"]):
		return "Se cuelga en una pared por dentro del local."
	var edge: Vector3i = FurnitureCatalog.get_wall_edge(item["cell"], item["rotation"])
	if OfficeState.get_edge(edge) != ConstructionCatalog.WALL:
		return "Va colgado en una pared: acércalo a una."
	if OfficeState.find_wall_item(item["cell"], item["rotation"]) >= 0:
		return "En esa pared ya hay algo colgado."
	return ""


## Gira el mueble de cell un cuarto de vuelta (gratis si cabe, con el mismo anclaje).
func quote_rotate(cell: Vector2i, quarter: int = -1) -> Dictionary:
	var index: int = OfficeState.find_furniture_at(cell, quarter)
	if index < 0:
		return _fail(0, "Ahí no hay ningún mueble.")
	var station_problem: String = _station_problem(index)
	if not station_problem.is_empty():
		return _fail(0, station_problem)
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	var item: Dictionary = candidate[index].duplicate()
	item["rotation"] = posmod(int(item["rotation"]) + 1, 4)
	candidate[index] = item
	var problem: String = _placement_problem(candidate, item)
	if not problem.is_empty():
		return _fail(0, problem)
	var item_name: String = FurnitureCatalog.get_item(item["id"])["name"]
	return {"ok": true, "cost": 0, "message": "%s girado." % item_name, "furniture": candidate}


func rotate(cell: Vector2i, quarter: int = -1) -> Dictionary:
	return _commit(quote_rotate(cell, quarter))


## Vende lo de cell: primero la pantalla extra, luego la computadora, luego el mueble (sin
## mueble, lo colgado). No se vende la silla del CEO ni nada del puesto de un empleado.
func quote_sell_furniture_at(cell: Vector2i, quarter: int = -1) -> Dictionary:
	var index: int = OfficeState.find_furniture_at(cell, quarter)
	if index < 0:
		# Sin mueble en el piso, lo que cuelga en una pared de esa casilla.
		for rotation: int in range(4):
			if OfficeState.find_wall_item(cell, rotation) >= 0:
				return quote_sell_wall_item(cell, rotation)
		return _fail(0, "Ahí no hay ningún mueble.")
	if OfficeState.furniture[index]["assigned_to"] == "ceo":
		return _fail(0, "La silla del CEO no se puede vender.")
	var station_problem: String = _station_problem(index)
	if not station_problem.is_empty():
		return _fail(0, station_problem)
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	var item: Dictionary = candidate[index].duplicate()
	if not String(item.get("monitor", "")).is_empty():
		var monitor_refund: int = FurnitureCatalog.get_resale(item["monitor"])
		var monitor_name: String = FurnitureCatalog.get_item(item["monitor"])["name"]
		# Se vende de a una.
		item["monitors"] = FurnitureCatalog.get_monitor_count(item) - 1
		if int(item["monitors"]) <= 0:
			item["monitor"] = ""
		candidate[index] = item
		return {"ok": true, "cost": -monitor_refund, "message": "Venta de %s: +$%d" % [monitor_name, monitor_refund],
			"furniture": candidate}
	if not String(item["computer"]).is_empty():
		var refund: int = FurnitureCatalog.get_resale(item["computer"])
		var computer_name: String = FurnitureCatalog.get_item(item["computer"])["name"]
		item["computer"] = ""
		candidate[index] = item
		return {"ok": true, "cost": -refund, "message": "Venta de %s: +$%d" % [computer_name, refund],
			"furniture": candidate}
	candidate.remove_at(index)
	var resale: int = FurnitureCatalog.get_resale(item["id"])
	var item_name: String = FurnitureCatalog.get_item(item["id"])["name"]
	return {"ok": true, "cost": -resale, "message": "Venta de %s: +$%d" % [item_name, resale],
		"furniture": candidate}


func sell_furniture_at(cell: Vector2i, quarter: int = -1) -> Dictionary:
	return _commit(quote_sell_furniture_at(cell, quarter))


## Instala una computadora en el escritorio de cell (una por escritorio).
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


## Instala una pantalla extra en el escritorio de cell: si lo admite (hasta max_monitors) y con computadora pro.
func quote_install_monitor(monitor_id: String, cell: Vector2i) -> Dictionary:
	var index: int = OfficeState.find_furniture_at(cell)
	if index < 0 or not bool(FurnitureCatalog.get_item(OfficeState.furniture[index]["id"])["accepts_computer"]):
		return _fail(0, "La pantalla extra va sobre un escritorio largo.")
	var item: Dictionary = OfficeState.furniture[index].duplicate()
	var limit: int = FurnitureCatalog.get_max_monitors(item["id"])
	if limit <= 0:
		return _fail(0, "La pantalla extra solo cabe en un escritorio largo.")
	if String(item["computer"]).is_empty():
		return _fail(0, "Ese escritorio no tiene computadora: instala una primero.")
	if not FurnitureCatalog.allows_monitors(item["computer"]):
		return _fail(0, "Las pantallas extra necesitan una computadora pro.")
	var count: int = FurnitureCatalog.get_monitor_count(item)
	if count >= limit:
		return _fail(0, "Ese escritorio ya tiene todas sus pantallas.")
	var cost: int = FurnitureCatalog.get_price(monitor_id)
	if not Economy.can_afford(cost):
		return _fail(cost, "No alcanza el dinero: cuesta $%d." % cost)
	item["monitor"] = monitor_id
	item["monitors"] = count + 1
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	candidate[index] = item
	var monitor_name: String = FurnitureCatalog.get_item(monitor_id)["name"]
	return {"ok": true, "cost": cost, "message": "%s: −$%d" % [monitor_name, cost], "furniture": candidate}


func install_monitor(monitor_id: String, cell: Vector2i) -> Dictionary:
	return _commit(quote_install_monitor(monitor_id, cell))


## Mejora lo de cell a su calidad siguiente cobrando la diferencia (computadora o silla), también
## en un puesto ocupado.
func quote_upgrade(cell: Vector2i) -> Dictionary:
	var index: int = OfficeState.find_furniture_at(cell)
	if index < 0:
		return _fail(0, "Ahí no hay nada que mejorar.")
	var item: Dictionary = OfficeState.furniture[index].duplicate()
	var old_id: String = item["id"]
	var field: String = "id"
	if bool(FurnitureCatalog.get_item(old_id)["accepts_computer"]):
		if String(item["computer"]).is_empty():
			return _fail(0, "Ese escritorio no tiene computadora: instala una primero.")
		old_id = item["computer"]
		field = "computer"
	var new_id: String = FurnitureCatalog.get_upgrade(old_id)
	var old_name: String = FurnitureCatalog.get_item(old_id)["name"]
	if new_id.is_empty():
		if field == "computer":
			return _fail(0, "%s es la mejor que hay." % old_name)
		return _fail(0, "%s no se puede mejorar." % old_name)
	var cost: int = maxi(0, FurnitureCatalog.get_price(new_id) - FurnitureCatalog.get_price(old_id))
	if not Economy.can_afford(cost):
		return _fail(cost, "No alcanza el dinero: la mejora cuesta $%d." % cost)
	item[field] = new_id
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	candidate[index] = item
	var new_name: String = FurnitureCatalog.get_item(new_id)["name"]
	return {"ok": true, "cost": cost, "message": "%s → %s: −$%d" % [old_name, new_name, cost], "furniture": candidate}


func upgrade(cell: Vector2i) -> Dictionary:
	return _commit(quote_upgrade(cell))


# Los muebles del puesto de un empleado no se venden ni giran mientras lo ocupa.
func _station_problem(index: int) -> String:
	var owner: String = String(OfficeState.furniture[index]["assigned_to"])
	if owner.is_empty():
		owner = Workstations.owner_of(OfficeState.furniture, OfficeState.rooms, index)
	if owner.is_empty() or owner == "ceo":
		return ""
	return "Es parte del puesto de %s: no se puede vender ni girar." % Staff.get_person_name(owner)


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


# Por qué item (ya en candidate) no puede quedar así, o "".
func _placement_problem(candidate: Array[Dictionary], item: Dictionary) -> String:
	var cells: Array[Vector2i] = FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"])
	for cell: Vector2i in cells:
		if not OfficeState.lot.has_point(cell):
			return "No cabe: se sale del local."
		if cell == OfficeState.entrance:
			return "No se puede tapar la entrada."
		if occupied_cells.has(cell):
			return "Hay alguien en esa casilla."
	for other: Dictionary in candidate:
		if not is_same(other, item) and FurnitureCatalog.overlaps(item, other):
			return "Ahí ya hay otro objeto."
	for a: Vector2i in cells:
		for b: Vector2i in cells:
			var step: Vector2i = (b - a).abs()
			if step.x + step.y == 1 and not OfficeState.get_edge(GridEdge.between(a, b)).is_empty():
				return "Hay una pared en medio."
	return _access_problem(candidate, item)


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


# --- Terreno ----------------------------------------------------------------------


## Casillas de un terreno width × depth pegado a un lado (width a lo largo, depth hacia afuera,
## offset desde la esquina del rectángulo del local). Cada fila se apoya en el local, así rellena
## huecos de un local en L. Devuelve {"cells": todo el rectángulo, "new_cells": lo que se compra}.
static func plan_land(lot: Lot, side: String, width: int, depth: int, offset: int) -> Dictionary:
	var out: Vector2i = _side_direction(side)
	var along := Vector2i(absi(out.y), absi(out.x))
	var bounds: Rect2i = lot.get_bounds()
	var first: int = along.x * bounds.position.x + along.y * bounds.position.y + offset
	var start: int = 0
	var touches: bool = false
	# Por fila, la casilla del local más afuera; el terreno arranca tras la más cercana.
	var farthest: Dictionary[int, int] = {}
	for cell: Vector2i in lot.get_cells():
		var t: int = along.x * cell.x + along.y * cell.y
		if t < first or t >= first + width:
			continue
		var reach: int = out.x * cell.x + out.y * cell.y + 1
		farthest[t] = maxi(farthest.get(t, reach), reach)
	for t: int in farthest:
		start = farthest[t] if not touches else mini(start, farthest[t])
		touches = true
	var cells: Array[Vector2i] = []
	var new_cells: Array[Vector2i] = []
	if not touches:
		return {"cells": cells, "new_cells": new_cells}
	for t: int in range(first, first + width):
		for k: int in range(depth):
			var cell: Vector2i = along * t + out * (start + k)
			cells.append(cell)
			if not lot.has_point(cell):
				new_cells.append(cell)
	return {"cells": cells, "new_cells": new_cells}


static func _side_direction(side: String) -> Vector2i:
	match side:
		SIDE_NORTH:
			return Vector2i(0, -1)
		SIDE_SOUTH:
			return Vector2i(0, 1)
		SIDE_WEST:
			return Vector2i(-1, 0)
	return Vector2i(1, 0)


## Cotiza un terreno width × depth pegado a un lado (ver plan_land), como quote_land_cells.
func quote_land(side: String, width: int, depth: int, offset: int) -> Dictionary:
	if width < 1 or depth < 1:
		return {"ok": false, "cost": 0, "message": "El terreno tiene que medir al menos 1 × 1.",
			"cells": [] as Array[Vector2i], "new_cells": [] as Array[Vector2i]}
	var plan: Dictionary = plan_land(OfficeState.lot, side, width, depth, offset)
	return quote_land_cells(plan["cells"])


## Compra ese terreno si quote_land lo permite.
func buy_land(side: String, width: int, depth: int, offset: int) -> Dictionary:
	return _commit_land(quote_land(side, width, depth, offset))


## Cotiza el rectángulo entre dos esquinas (arrastre de la herramienta Terreno).
func quote_land_rect(corner_a: Vector2i, corner_b: Vector2i) -> Dictionary:
	var low := Vector2i(mini(corner_a.x, corner_b.x), mini(corner_a.y, corner_b.y))
	var high := Vector2i(maxi(corner_a.x, corner_b.x), maxi(corner_a.y, corner_b.y))
	var cells: Array[Vector2i] = []
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			cells.append(Vector2i(x, y))
	return quote_land_cells(cells)


## Compra el rectángulo entre dos esquinas si quote_land_rect lo permite.
func buy_land_rect(corner_a: Vector2i, corner_b: Vector2i) -> Dictionary:
	return _commit_land(quote_land_rect(corner_a, corner_b))


## Compra esas casillas si quote_land_cells lo permite.
func buy_land_cells(cells: Array[Vector2i]) -> Dictionary:
	return _commit_land(quote_land_cells(cells))


## Casillas del lote en que cae una casilla (lotes alineados con (0, 0)).
static func get_plot_cells(cell: Vector2i) -> Array[Vector2i]:
	var size: Vector2i = ConstructionCatalog.get_land_plot_size()
	var origin := Vector2i(floori(float(cell.x) / size.x) * size.x, floori(float(cell.y) / size.y) * size.y)
	var cells: Array[Vector2i] = []
	for y: int in range(size.y):
		for x: int in range(size.x):
			cells.append(origin + Vector2i(x, y))
	return cells


## Lotes comprables: tocan el local y tienen algo que comprar. Cada uno es el quote_land_cells
## de sus casillas más "origin" (su primera casilla).
func get_land_plots() -> Array[Dictionary]:
	var size: Vector2i = ConstructionCatalog.get_land_plot_size()
	var area: Rect2i = OfficeState.lot_rect.grow_individual(size.x, size.y, size.x, size.y)
	var plots: Array[Dictionary] = []
	var seen: Dictionary[Vector2i, bool] = {}
	for y: int in range(area.position.y, area.end.y, size.y):
		for x: int in range(area.position.x, area.end.x, size.x):
			var cells: Array[Vector2i] = get_plot_cells(Vector2i(x, y))
			if seen.has(cells[0]):
				continue
			seen[cells[0]] = true
			var quote: Dictionary = quote_land_cells(cells)
			if (quote["new_cells"] as Array).is_empty():
				continue
			quote["origin"] = cells[0]
			plots.append(quote)
	return plots


## Cotiza esas casillas: {"ok", "cost", "message", "cells", "new_cells", "rooms", "edges", "entrance"?}.
## Se compran las del solar fuera del local conectadas a él; con la casilla frente a la puerta, la
## entrada se corre al borde nuevo. Cada pedazo abre su borde hacia un solo espacio (el común o la
## habitación con más borde), así no se juntan habitaciones; lo colgado deja la pared cerrada.
func quote_land_cells(cells: Array[Vector2i]) -> Dictionary:
	var lot: Lot = OfficeState.lot
	var street: Vector2i = OfficeState.get_outside_of_entrance()
	var wanted: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		if OfficeState.site_rect.has_point(cell) and not lot.has_point(cell):
			wanted[cell] = true
	var new_cells: Array[Vector2i] = _connected_to_lot(lot, wanted)
	var land_cost: int = new_cells.size() * ConstructionCatalog.get_land_price()
	var floor_cost: int = ConstructionCatalog.get_land_floor_cost(new_cells.size())
	var cost: int = land_cost + floor_cost
	var result: Dictionary = {"ok": false, "cost": cost, "message": "", "cells": cells, "new_cells": new_cells}
	if new_cells.is_empty():
		if cells.is_empty():
			result["message"] = "El terreno tiene que tocar el local."
		elif cells.all(func(cell: Vector2i) -> bool: return lot.has_point(cell)) and not cells.is_empty():
			result["message"] = "Ese terreno ya es del local."
		elif cells.all(func(cell: Vector2i) -> bool: return not OfficeState.site_rect.has_point(cell)):
			result["message"] = "Eso está fuera del solar: no se puede crecer más por ahí."
		else:
			result["message"] = "El terreno tiene que tocar el local."
		return result
	if not Economy.can_afford(cost):
		result["message"] = "No alcanza el dinero: %d m² cuestan %s." % [new_cells.size(), MoneyFormat.format(cost)]
		return result
	var new_lot: Lot = lot.with_cells(new_cells)
	# Con la casilla frente a la puerta, la entrada se corre al borde nuevo (sin hueco de calle encerrado).
	var entrance: Vector2i = OfficeState.entrance
	var moves_entrance: bool = new_cells.has(street)
	var outward: Vector2i = street - entrance
	if moves_entrance:
		entrance = street
		while new_lot.has_point(entrance + outward):
			entrance += outward
		if not OfficeState.site_rect.has_point(entrance + outward):
			result["message"] = "Hay que dejar una casilla libre frente a la entrada para salir a la calle."
			return result
	var new_edges: Dictionary[Vector3i, String] = _edges_with_land(new_lot, new_cells, street if moves_entrance else NO_CELL)
	if moves_entrance:
		var old_door: Vector3i = GridEdge.between(OfficeState.entrance, street)
		var door_kind: String = String(OfficeState.edges.get(old_door, ConstructionCatalog.DOOR))
		new_edges.erase(old_door)
		new_edges[GridEdge.between(entrance, entrance + outward)] = door_kind
		result["entrance"] = entrance
	var spaces: Array[Dictionary] = RoomRules.find_spaces(new_lot, new_edges)
	var rooms: Array[Dictionary] = RoomRules.reconcile(OfficeState.rooms, spaces, entrance, OfficeState.furniture)
	var lost: Array[String] = _lost_rooms(rooms)
	for type_id: String in lost:
		if RoomCatalog.is_locked(type_id):
			result["message"] = "Así se perdería la %s: elige otro lugar." % RoomCatalog.get_display_name(type_id)
			return result
	var floor_type: String = String(ConstructionCatalog.get_land().get("floor", ConstructionCatalog.BARE_FLOOR))
	var message: String = "Terreno de %d m² por %s (%s + %s %s) · mantenimiento +%s al mes." % [new_cells.size(),
		MoneyFormat.format(cost), MoneyFormat.format(land_cost), ConstructionCatalog.get_display_name(floor_type).to_lower(),
		MoneyFormat.format(floor_cost), MoneyFormat.format(Economy.get_maintenance(new_cells.size()))]
	var windows: int = _opened_windows(new_edges)
	result["window_refund"] = windows * ConstructionCatalog.get_refund(ConstructionCatalog.WINDOW)
	if windows > 0:
		message += " Se quitan %d %s del borde que se abre (+%s)." % [windows, "ventana" if windows == 1 else "ventanas",
			MoneyFormat.format(int(result["window_refund"]))]
	if moves_entrance:
		message += " La puerta de entrada pasa al borde nuevo."
	if not lost.is_empty():
		var names: Array[String] = []
		for type_id: String in lost:
			names.append(RoomCatalog.get_display_name(type_id))
		message += " Se deshace: %s." % ", ".join(names)
	result["ok"] = true
	result["message"] = message
	result["rooms"] = rooms
	result["edges"] = new_edges
	return result


# Compra un terreno ya cotizado: crece el local, se corre el contorno y lo nuevo trae piso.
func _commit_land(result: Dictionary) -> Dictionary:
	if not result["ok"]:
		return result
	var new_cells: Array[Vector2i] = result["new_cells"]
	var window_refund: int = int(result.get("window_refund", 0))
	OfficeState.edges = result["edges"]
	OfficeState.lot = OfficeState.lot.with_cells(new_cells)
	if result.has("entrance"):
		OfficeState.entrance = result["entrance"]
	var floor_type: String = String(ConstructionCatalog.get_land().get("floor", ConstructionCatalog.BARE_FLOOR))
	for cell: Vector2i in new_cells:
		OfficeState.set_floor(cell, floor_type)
	var rooms: Array[Dictionary] = result["rooms"]
	OfficeState.rooms = rooms
	result.erase("rooms")
	result.erase("edges")
	OfficeState.land_paid += int(result["cost"])
	Economy.spend(result["cost"], CONCEPT_LAND)
	if window_refund > 0:
		Economy.earn(window_refund, CONCEPT_CONSTRUCTION)
	EventBus.office_changed.emit()
	result["message"] = "Compraste %d m² de terreno por %s." % [new_cells.size(), MoneyFormat.format(int(result["cost"]))]
	if window_refund > 0:
		result["message"] += " Las ventanas del borde que se abrió devolvieron %s." % MoneyFormat.format(window_refund)
	return result


# Las pedidas conectadas al local, directamente o por otras pedidas.
static func _connected_to_lot(lot: Lot, wanted: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var found: Dictionary[Vector2i, bool] = {}
	var queue: Array[Vector2i] = []
	for cell: Vector2i in wanted:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			if lot.has_point(cell + direction):
				found[cell] = true
				queue.append(cell)
				break
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = cell + direction
			if wanted.has(next) and not found.has(next):
				found[next] = true
				queue.append(next)
	var cells: Array[Vector2i] = []
	for cell: Vector2i in wanted:
		if found.has(cell):
			cells.append(cell)
	return cells


# Ventanas del contorno que quita el terreno nuevo (borde que se abre).
func _opened_windows(new_edges: Dictionary[Vector3i, String]) -> int:
	var count: int = 0
	for edge: Vector3i in OfficeState.edges:
		if OfficeState.edges[edge] == ConstructionCatalog.WINDOW and not new_edges.has(edge):
			count += 1
	return count


# Bordes con el contorno corrido: el nuevo lleva pared y cada pedazo abre su borde hacia un solo
# espacio viejo (el que no es habitación; si no, el de más borde). Lo colgado queda como estaba.
func _edges_with_land(new_lot: Lot, new_cells: Array[Vector2i], street: Vector2i = NO_CELL) -> Dictionary[Vector3i, String]:
	var edges: Dictionary[Vector3i, String] = OfficeState.edges.duplicate()
	for edge: Vector3i in new_lot.get_outline():
		if not edges.has(edge):
			edges[edge] = ConstructionCatalog.WALL
	var spaces: Array[Dictionary] = RoomRules.find_spaces(OfficeState.lot, OfficeState.edges)
	var pending: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in new_cells:
		pending[cell] = true
	for start: Vector2i in new_cells:
		if not pending.has(start):
			continue
		# Un pedazo de terreno nuevo (casillas nuevas unidas).
		var piece: Array[Vector2i] = [start]
		pending.erase(start)
		var index: int = 0
		while index < piece.size():
			for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				var next: Vector2i = piece[index] + direction
				if pending.has(next):
					pending.erase(next)
					piece.append(next)
			index += 1
		# Bordes que comparte con cada espacio de antes.
		var shared: Dictionary[int, Array] = {}
		for cell: Vector2i in piece:
			for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				var old: Vector2i = cell + direction
				if not OfficeState.lot.has_point(old):
					continue
				var space: int = RoomRules.space_index_at(spaces, old)
				if not shared.has(space):
					shared[space] = []
				shared[space].append(GridEdge.between(cell, old))
		var chosen: int = -1
		var best: int = -1
		for space: int in shared:
			var cells: Array = spaces[space]["cells"] if space >= 0 else []
			var is_room: bool = not cells.is_empty() and RoomRules.room_index_at(OfficeState.rooms, cells[0]) >= 0
			# El espacio común gana a cualquier habitación; después, el de más borde.
			var score: int = shared[space].size() + (0 if is_room else 100000)
			# El pedazo con la casilla frente a la puerta se abre hacia el espacio de la entrada (la Recepción).
			if piece.has(street) and cells.has(OfficeState.entrance):
				score += 100000000
			if score > best:
				best = score
				chosen = space
		if chosen in shared:
			for edge: Vector3i in shared[chosen]:
				if OfficeState.wall_items_on(edge).is_empty():
					edges.erase(edge)
	return edges


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
