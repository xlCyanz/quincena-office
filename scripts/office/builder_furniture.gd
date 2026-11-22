# Construcción, capa 2: muebles (poner, girar, vender, computadoras, pantallas y mejoras).
extends "res://scripts/office/builder_structure.gd"


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
	if not FurnitureCatalog.fits_desk(computer_id, item["id"]):
		var desk_names: Array[String] = []
		for desk_id: String in FurnitureCatalog.get_desks(computer_id):
			desk_names.append(String(FurnitureCatalog.get_item(desk_id)["name"]).to_lower())
		return _fail(0, "%s solo va sobre un %s." % [FurnitureCatalog.get_item(computer_id)["name"], " o ".join(desk_names)])
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
		if field == "computer" and FurnitureCatalog.get_desks(old_id).is_empty():
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
