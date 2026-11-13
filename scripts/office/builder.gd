# Reglas de la construcción: cuánto cuesta cada cambio, si se puede hacer y aplicarlo
# sobre OfficeState cobrando o devolviendo dinero con Economy.
#
# Un cambio es un diccionario {"edge": Vector3i, "kind": String} para paredes y puertas
# (kind = "" para vender) o {"cell": Vector2i, "kind": String} para pisos. Reemplazar
# una pieza vende la anterior y compra la nueva. Las paredes y la puerta del contorno
# del local no se compran ni se venden, y un piso no se puede quitar (dejar la casilla
# con ConstructionCatalog.BARE_FLOOR): solo cambiar por otro. Varios cambios juntos
# (por ejemplo, una fila de paredes) se cobran todos o ninguno.
#
# Los muebles tienen sus propias funciones (place, rotate, sell_furniture_at,
# install_computer, install_monitor, upgrade), cada una con su quote_ para la vista previa. Un mueble no puede
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
const CONCEPT_LAND: String = "Terreno"

## Lados del local para comprar terreno (diseño 3.1): hacia dónde crece.
const SIDE_NORTH: String = "north"
const SIDE_SOUTH: String = "south"
const SIDE_EAST: String = "east"
const SIDE_WEST: String = "west"
const SIDES: Array[String] = [SIDE_NORTH, SIDE_SOUTH, SIDE_EAST, SIDE_WEST]

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
		if exterior and not _is_window_swap(change):
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


# Quita los cambios que no cambian nada (poner lo que ya hay) y los repetidos. Vender
# una ventana del contorno la vuelve pared (el contorno siempre está cerrado).
func _effective_changes(changes: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for original: Dictionary in changes:
		var change: Dictionary = original
		if change.has("edge") and String(change["kind"]).is_empty() \
				and OfficeState.get_edge(change["edge"]) == ConstructionCatalog.WINDOW \
				and GridEdge.is_exterior(change["edge"], OfficeState.lot):
			change = {"edge": change["edge"], "kind": ConstructionCatalog.WALL}
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


# La pieza que cuenta para el precio: la pared del contorno no se compró ("").
func _paid_kind(change: Dictionary, kind: String) -> String:
	if change.has("edge") and kind == ConstructionCatalog.WALL and GridEdge.is_exterior(change["edge"], OfficeState.lot):
		return ""
	return kind


# En el contorno solo se cambia pared por ventana o ventana por pared (hito 55).
func _is_window_swap(change: Dictionary) -> bool:
	var pieces: Array[String] = [ConstructionCatalog.WALL, ConstructionCatalog.WINDOW]
	return pieces.has(_current_kind(change)) and pieces.has(String(change["kind"]))


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


## Comprar un mueble y colocarlo con su casilla de anclaje y su rotación.
func quote_place(id: String, anchor: Vector2i, rotation: int) -> Dictionary:
	var info: Dictionary = FurnitureCatalog.get_item(id)
	if info.is_empty() or bool(info["on_desk"]):
		return _fail(0, "Ese objeto no se coloca en el piso.")
	var item: Dictionary = {"id": id, "cell": anchor, "rotation": posmod(rotation, 4),
		"assigned_to": "", "computer": "", "monitor": ""}
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	candidate.append(item)
	var cost: int = FurnitureCatalog.get_price(id)
	var problem: String = _wall_problem(item) if bool(info["wall_mounted"]) else _placement_problem(candidate, item)
	if problem.is_empty() and not Economy.can_afford(cost):
		problem = "No alcanza el dinero: cuesta $%d." % cost
	if not problem.is_empty():
		return _fail(cost, problem)
	return {"ok": true, "cost": cost, "message": "%s: −$%d" % [info["name"], cost], "furniture": candidate}


func place(id: String, anchor: Vector2i, rotation: int) -> Dictionary:
	return _commit(quote_place(id, anchor, rotation))


## Vender el objeto colgado en una cara de pared (su casilla y la rotación que deja la
## pared detrás).
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


# Un objeto de pared va en una cara de pared libre dentro del local: la pared queda
# detrás de su frente (no en una puerta) y cada cara lleva un solo objeto.
func _wall_problem(item: Dictionary) -> String:
	if not OfficeState.lot.has_point(item["cell"]):
		return "Se cuelga en una pared por dentro del local."
	var edge: Vector3i = FurnitureCatalog.get_wall_edge(item["cell"], item["rotation"])
	if OfficeState.get_edge(edge) != ConstructionCatalog.WALL:
		return "Va colgado en una pared: acércalo a una."
	if OfficeState.find_wall_item(item["cell"], item["rotation"]) >= 0:
		return "En esa pared ya hay algo colgado."
	return ""


## Girar un cuarto de vuelta el mueble que ocupa cell. Es gratis, pero el mueble girado
## tiene que caber (las casillas nuevas se cuentan desde la misma casilla de anclaje).
func quote_rotate(cell: Vector2i) -> Dictionary:
	var index: int = OfficeState.find_furniture_at(cell)
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


func rotate(cell: Vector2i) -> Dictionary:
	return _commit(quote_rotate(cell))


## Vender lo que hay en cell: si es un escritorio con segundo monitor, primero el
## monitor; si tiene computadora, después la computadora; si no, el mueble (sin mueble, lo colgado en una pared de la casilla).
## La silla del CEO no se vende, ni nada del puesto de un empleado.
func quote_sell_furniture_at(cell: Vector2i) -> Dictionary:
	var index: int = OfficeState.find_furniture_at(cell)
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


## Instalar un segundo monitor en el escritorio que ocupa cell: necesita computadora y
## va uno por escritorio (hito 46).
func quote_install_monitor(monitor_id: String, cell: Vector2i) -> Dictionary:
	var index: int = OfficeState.find_furniture_at(cell)
	if index < 0 or not bool(FurnitureCatalog.get_item(OfficeState.furniture[index]["id"])["accepts_computer"]):
		return _fail(0, "El monitor va sobre un escritorio.")
	var item: Dictionary = OfficeState.furniture[index].duplicate()
	if String(item["computer"]).is_empty():
		return _fail(0, "Ese escritorio no tiene computadora: instala una primero.")
	if not String(item.get("monitor", "")).is_empty():
		return _fail(0, "Ese escritorio ya tiene segundo monitor.")
	var cost: int = FurnitureCatalog.get_price(monitor_id)
	if not Economy.can_afford(cost):
		return _fail(cost, "No alcanza el dinero: cuesta $%d." % cost)
	item["monitor"] = monitor_id
	var candidate: Array[Dictionary] = OfficeState.furniture.duplicate()
	candidate[index] = item
	var monitor_name: String = FurnitureCatalog.get_item(monitor_id)["name"]
	return {"ok": true, "cost": cost, "message": "%s: −$%d" % [monitor_name, cost], "furniture": candidate}


func install_monitor(monitor_id: String, cell: Vector2i) -> Dictionary:
	return _commit(quote_install_monitor(monitor_id, cell))


## Mejorar lo que hay en cell a su calidad siguiente (hito 46), cobrando la diferencia de
## precio: la computadora de un escritorio (básica → media → pro) o una silla básica
## (→ ergonómica). Se puede aunque sea parte de un puesto ocupado: no cambia el lugar.
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


# Los muebles del puesto de un empleado (silla, escritorio y computadora) no se venden
# ni se giran mientras lo ocupa: primero hay que despedirlo (hito 13).
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


# Motivo por el que item (ya dentro de candidate) no puede quedar así, o "" si puede.
func _placement_problem(candidate: Array[Dictionary], item: Dictionary) -> String:
	var cells: Array[Vector2i] = FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"])
	for cell: Vector2i in cells:
		if not OfficeState.lot.has_point(cell):
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



# Indica si se llega a una silla: alguna casilla vecina alcanzable sin pared entre ellas.
func _seat_reachable(pathfinder: OfficePathfinder, reachable: Dictionary[Vector2i, bool], seat: Vector2i) -> bool:
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var next: Vector2i = seat + direction
		if reachable.has(next) and pathfinder.can_cross(seat, next):
			return true
	return false


# --- Terreno ----------------------------------------------------------------------


## Casillas de un terreno de width × depth pegado a un lado del local. width va a lo
## largo del lado y depth hacia afuera; offset corre el terreno a lo largo del lado
## desde la esquina del rectángulo que encierra el local (0 = alineado con ella). En
## cada fila (o columna) el terreno se apoya en la casilla del local más lejana, así
## rellena los huecos de un local en L; las casillas que ya son del local no cuentan.
## Devuelve {"cells": Array[Vector2i] (todo el rectángulo), "new_cells": las que se compran}.
static func plan_land(lot: Lot, side: String, width: int, depth: int, offset: int) -> Dictionary:
	var out: Vector2i = _side_direction(side)
	var along := Vector2i(absi(out.y), absi(out.x))
	var bounds: Rect2i = lot.get_bounds()
	var first: int = along.x * bounds.position.x + along.y * bounds.position.y + offset
	var start: int = 0
	var touches: bool = false
	# Por cada fila: la casilla del local más hacia afuera. El terreno arranca después de
	# la más cercana de todas, así toca el local y rellena los huecos.
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


## Calcula la compra de un terreno sin hacerla: {"ok", "cost", "message", "cells"
## (el rectángulo, para la vista previa), "new_cells", "rooms"}.
func quote_land(side: String, width: int, depth: int, offset: int) -> Dictionary:
	var plan: Dictionary = plan_land(OfficeState.lot, side, width, depth, offset)
	var cells: Array[Vector2i] = plan["cells"]
	var new_cells: Array[Vector2i] = plan["new_cells"]
	var land_cost: int = new_cells.size() * ConstructionCatalog.get_land_price()
	var floor_cost: int = ConstructionCatalog.get_land_floor_cost(new_cells.size())
	var cost: int = land_cost + floor_cost
	var result: Dictionary = {"ok": false, "cost": cost, "message": "", "cells": cells, "new_cells": new_cells}
	if width < 1 or depth < 1:
		result["message"] = "El terreno tiene que medir al menos 1 × 1."
		return result
	if cells.is_empty():
		result["message"] = "Así el terreno no toca el local."
		return result
	for cell: Vector2i in cells:
		if not OfficeState.site_rect.has_point(cell):
			result["message"] = "Se sale del solar: no se puede crecer más por ahí."
			return result
	if new_cells.is_empty():
		result["message"] = "Ese terreno ya es del local."
		return result
	if new_cells.has(OfficeState.get_outside_of_entrance()):
		result["message"] = "No se puede tapar la puerta de entrada."
		return result
	if not Economy.can_afford(cost):
		result["message"] = "No alcanza el dinero: %d m² cuestan %s." % [new_cells.size(), MoneyFormat.format(cost)]
		return result
	var new_lot: Lot = OfficeState.lot.with_cells(new_cells)
	var new_edges: Dictionary[Vector3i, String] = _edges_with_land(new_lot)
	for edge: Vector3i in OfficeState.edges:
		if not new_edges.has(edge) and not OfficeState.wall_items_on(edge).is_empty():
			result["message"] = "Hay algo colgado en la pared que se abriría: véndelo primero."
			return result
	var spaces: Array[Dictionary] = RoomRules.find_spaces(new_lot, new_edges)
	var rooms: Array[Dictionary] = RoomRules.reconcile(OfficeState.rooms, spaces, OfficeState.entrance, OfficeState.furniture)
	var lost: Array[String] = _lost_rooms(rooms)
	for type_id: String in lost:
		if RoomCatalog.is_locked(type_id):
			result["message"] = "Así se abriría la %s al terreno nuevo: elige otro lugar." % RoomCatalog.get_display_name(type_id)
			return result
	# Una habitación puede crecer hacia el terreno nuevo, pero no juntarse con otro espacio.
	for room: Dictionary in rooms:
		var before: Array[Vector2i] = []
		for old_room: Dictionary in OfficeState.rooms:
			if old_room["type"] == room["type"] and RoomRules.shares_cells(old_room["cells"], room["cells"]):
				before = old_room["cells"]
		for cell: Vector2i in room["cells"]:
			if not before.has(cell) and not new_cells.has(cell):
				result["message"] = "Así la %s se juntaría con el resto de la oficina: compra el terreno solo junto a ella o junto al resto." % (
					RoomCatalog.get_display_name(room["type"]))
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
	if not lost.is_empty():
		var names: Array[String] = []
		for type_id: String in lost:
			names.append(RoomCatalog.get_display_name(type_id))
		message += " Se deshace: %s." % ", ".join(names)
	result["ok"] = true
	result["message"] = message
	result["rooms"] = rooms
	return result


## Compra el terreno si quote_land lo permite: el local crece, el contorno se corre al
## nuevo borde (el borde compartido queda abierto) y las casillas nuevas traen piso.
func buy_land(side: String, width: int, depth: int, offset: int) -> Dictionary:
	var result: Dictionary = quote_land(side, width, depth, offset)
	if not result["ok"]:
		return result
	var new_cells: Array[Vector2i] = result["new_cells"]
	var new_lot: Lot = OfficeState.lot.with_cells(new_cells)
	var window_refund: int = int(result.get("window_refund", 0))
	OfficeState.edges = _edges_with_land(new_lot)
	OfficeState.lot = new_lot
	var floor_type: String = String(ConstructionCatalog.get_land().get("floor", ConstructionCatalog.BARE_FLOOR))
	for cell: Vector2i in new_cells:
		OfficeState.set_floor(cell, floor_type)
	var rooms: Array[Dictionary] = result["rooms"]
	OfficeState.rooms = rooms
	result.erase("rooms")
	OfficeState.land_paid += int(result["cost"])
	Economy.spend(result["cost"], CONCEPT_LAND)
	if window_refund > 0:
		Economy.earn(window_refund, CONCEPT_CONSTRUCTION)
	EventBus.office_changed.emit()
	result["message"] = "Compraste %d m² de terreno por %s." % [new_cells.size(), MoneyFormat.format(int(result["cost"]))]
	if window_refund > 0:
		result["message"] += " Las ventanas del borde que se abrió devolvieron %s." % MoneyFormat.format(window_refund)
	return result


# Ventanas del contorno de ahora que el terreno nuevo quita (el borde que se abre).
func _opened_windows(new_edges: Dictionary[Vector3i, String]) -> int:
	var count: int = 0
	for edge: Vector3i in OfficeState.edges:
		if OfficeState.edges[edge] == ConstructionCatalog.WINDOW and not new_edges.has(edge):
			count += 1
	return count


# Los bordes de la oficina con el contorno corrido al local nuevo: se abre el borde que
# ahora queda entre dos casillas del local y se pone pared en el contorno nuevo.
func _edges_with_land(new_lot: Lot) -> Dictionary[Vector3i, String]:
	var edges: Dictionary[Vector3i, String] = OfficeState.edges.duplicate()
	var new_outline: Array[Vector3i] = new_lot.get_outline()
	for edge: Vector3i in OfficeState.lot.get_outline():
		if not new_outline.has(edge):
			edges.erase(edge)
	for edge: Vector3i in new_outline:
		if not edges.has(edge):
			edges[edge] = ConstructionCatalog.WALL
	return edges


# --- Habitaciones ----------------------------------------------------------------


## Marcar como habitación de un tipo el espacio que contiene cell (no cuesta dinero).
## Si ya era otra habitación, cambia de tipo. Se puede marcar aunque todavía le
## falten tamaño o muebles para funcionar: el mensaje lo avisa.
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
	var racks: String = ""
	if room["type"] == OfficeState.SERVER_ROOM:
		var count: int = OfficeState.count_racks(room)
		racks = " %d %s." % [count, "rack" if count == 1 else "racks"]
	var ambiance: String = " %s." % Ambiance.describe(room, OfficeState.furniture, OfficeState.count_room_windows(room))
	if problems.is_empty():
		return {"ok": ok_if_working, "cost": 0, "message": "%s (%d m²): funciona.%s%s" % [type_name, cells.size(), racks, ambiance]}
	return {"ok": false, "cost": 0,
		"message": "%s (%d m²): no funciona, %s.%s" % [type_name, cells.size(), ", ".join(problems), ambiance]}


func _commit_rooms(result: Dictionary) -> Dictionary:
	if not result["ok"] or not result.has("rooms"):
		return result
	var rooms: Array[Dictionary] = result["rooms"]
	OfficeState.rooms = rooms
	EventBus.office_changed.emit()
	result.erase("rooms")
	return result
