# Reglas de la construcción: cuánto cuesta cada cambio, si se puede hacer y aplicarlo
# sobre OfficeState cobrando o devolviendo dinero con Economy.
#
# Un cambio es un diccionario {"edge": Vector3i, "kind": String} para paredes y puertas
# (kind = "" para vender) o {"cell": Vector2i, "kind": String} para pisos (kind =
# ConstructionCatalog.BARE_FLOOR para vender). Reemplazar una pieza vende la anterior y
# compra la nueva. Varios cambios juntos (por ejemplo, una fila de paredes) se cobran
# todos o ninguno.
class_name Builder
extends RefCounted


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
	if _changes_passage(effective) and not _keeps_ceo_access(effective):
		return {"ok": false, "cost": cost,
			"message": "Así el CEO no podría llegar a su escritorio desde la entrada."}
	return {"ok": true, "cost": cost, "message": _describe(effective, cost)}


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
	if result["cost"] >= 0:
		Economy.spend(result["cost"])
	else:
		Economy.earn(-result["cost"])
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


# Con los cambios aplicados, el CEO tiene que poder salir del local por la puerta de
# entrada y llegar desde ella hasta su silla.
func _keeps_ceo_access(changes: Array[Dictionary]) -> bool:
	var edges: Dictionary[Vector3i, String] = OfficeState.edges.duplicate()
	for change: Dictionary in changes:
		if change.has("edge"):
			if String(change["kind"]).is_empty():
				edges.erase(change["edge"])
			else:
				edges[change["edge"]] = change["kind"]
	var entrance_edge: Vector3i = GridEdge.between(OfficeState.entrance, OfficeState.get_outside_of_entrance())
	if edges.get(entrance_edge, "") == ConstructionCatalog.WALL:
		return false
	var seat: Dictionary = OfficeState.find_furniture_assigned_to("ceo")
	if seat.is_empty():
		return true
	var pathfinder := OfficePathfinder.new()
	pathfinder.build(OfficeState.lot_rect, OfficeState.get_furniture_cells(), edges)
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
