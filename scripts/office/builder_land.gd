# Construcción, capa 3: compra y venta de terreno (lotes, rectángulos y lados).
extends "res://scripts/office/builder_furniture.gd"


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


## Casillas del lote (OfficeState.get_land_plots) en que cae una casilla; vacío en el local inicial o fuera del solar.
static func get_plot_cells(cell: Vector2i) -> Array[Vector2i]:
	return LandPlots.get_cells(OfficeState.get_land_plot_at(cell))


## Lotes marcados por la herramienta Terreno. Los que tocan el local y tienen algo que comprar son el
## quote_land_cells de sus casillas con "action" "buy"; los comprados enteros, el quote_sell_land_plot con
## "action" "sell". Todos llevan "rect", "origin" (su primera casilla) y "marked" (las casillas que se marcan).
func get_land_plots() -> Array[Dictionary]:
	var plots: Array[Dictionary] = []
	var lot: Lot = OfficeState.lot
	for rect: Rect2i in OfficeState.get_land_plots():
		var cells: Array[Vector2i] = LandPlots.get_cells(rect)
		var owned: int = 0
		var touches: bool = false
		for cell: Vector2i in cells:
			if lot.has_point(cell):
				owned += 1
			else:
				for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
					touches = touches or lot.has_point(cell + direction)
		var quote: Dictionary
		if owned == cells.size():
			quote = quote_sell_land_plot(rect)
			quote["action"] = "sell"
			quote["marked"] = cells
			quote["new_cells"] = [] as Array[Vector2i]
		elif touches:
			quote = quote_land_cells(cells)
			if (quote["new_cells"] as Array).is_empty():
				continue
			quote["action"] = "buy"
			quote["marked"] = quote["new_cells"]
		else:
			continue
		quote["rect"] = rect
		quote["origin"] = cells[0]
		plots.append(quote)
	return plots


## Cotiza vender un lote comprado entero: {"ok", "cost" (negativo: lo que se devuelve), "message", "cells",
## "rooms", "edges"}. El lote tiene que estar vacío (sin muebles, habitaciones, paredes de adentro, puertas
## ni ventanas) y el local tiene que quedar unido; su contorno nuevo lleva pared.
func quote_sell_land_plot(plot: Rect2i) -> Dictionary:
	var cells: Array[Vector2i] = LandPlots.get_cells(plot)
	var refund: int = ConstructionCatalog.get_land_refund(cells.size())
	var result: Dictionary = {"ok": false, "cost": -refund, "message": "", "cells": cells}
	var lot: Lot = OfficeState.lot
	if cells.is_empty() or plot.intersects(OfficeState.get_base_rect()):
		result["message"] = "El local inicial no se vende."
		return result
	var sold: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		sold[cell] = true
		if not lot.has_point(cell):
			result["message"] = "Solo se vende un lote que es tuyo entero."
			return result
	if sold.has(OfficeState.entrance):
		result["message"] = "Ahí está la entrada: ese terreno no se vende."
		return result
	for item: Dictionary in OfficeState.furniture:
		for cell: Vector2i in FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"]):
			if sold.has(cell):
				result["message"] = "Primero quita lo que hay en ese terreno: %s." % String(FurnitureCatalog.get_item(item["id"]).get("name", item["id"]))
				return result
	for room: Dictionary in OfficeState.rooms:
		for cell: Vector2i in room["cells"]:
			if sold.has(cell):
				result["message"] = "Ese terreno es parte de una habitación (%s): desmárcala primero." % \
					RoomCatalog.get_display_name(room["type"])
				return result
	var remaining: Lot = lot.without_cells(cells)
	if not remaining.is_joined():
		result["message"] = "Así el local quedaría partido en dos."
		return result
	var new_edges: Dictionary[Vector3i, String] = OfficeState.edges.duplicate()
	for edge: Vector3i in OfficeState.edges:
		var sides: Array[Vector2i] = GridEdge.get_cells(edge)
		var inside: int = int(sold.has(sides[0])) + int(sold.has(sides[1]))
		if inside == 0:
			continue
		var kind: String = OfficeState.edges[edge]
		if not kind.is_empty():
			var piece: String = ConstructionCatalog.get_display_name(kind).to_lower()
			if inside == 2:
				result["message"] = "Primero quita lo construido adentro de ese terreno (%s)." % piece
				return result
			if kind != ConstructionCatalog.WALL:
				result["message"] = "Primero quita %s del borde de ese terreno." % piece
				return result
		# Su contorno se va con él; la pared hacia el resto del local se vuelve a poner como contorno.
		new_edges.erase(edge)
	for edge: Vector3i in remaining.get_outline():
		if String(new_edges.get(edge, "")).is_empty():
			new_edges[edge] = ConstructionCatalog.WALL
	OfficeState.place_double_door(new_edges, remaining, OfficeState.get_entrance_edge())
	var spaces: Array[Dictionary] = RoomRules.find_spaces(remaining, new_edges)
	var rooms: Array[Dictionary] = RoomRules.reconcile(OfficeState.rooms, spaces, OfficeState.entrance, OfficeState.furniture)
	var lost: Array[String] = _lost_rooms(rooms)
	if not lost.is_empty():
		result["message"] = "Así se perdería la %s." % RoomCatalog.get_display_name(lost[0])
		return result
	result["ok"] = true
	result["message"] = "Vender terreno de %d m²: +%s · mantenimiento −%s al mes." % [cells.size(), MoneyFormat.format(refund),
		MoneyFormat.format(Economy.get_maintenance(cells.size()))]
	result["rooms"] = rooms
	result["edges"] = new_edges
	return result


## Vende el lote si quote_sell_land_plot lo permite: el local se achica, el contorno se cierra y se
## devuelve sale_refund_ratio de lo que cuesta.
func sell_land_plot(plot: Rect2i) -> Dictionary:
	var result: Dictionary = quote_sell_land_plot(plot)
	if not result["ok"]:
		return result
	var cells: Array[Vector2i] = result["cells"]
	var refund: int = -int(result["cost"])
	OfficeState.edges = result["edges"]
	OfficeState.lot = OfficeState.lot.without_cells(cells)
	for cell: Vector2i in cells:
		OfficeState.floors.erase(cell)
	var rooms: Array[Dictionary] = result["rooms"]
	OfficeState.rooms = rooms
	result.erase("rooms")
	result.erase("edges")
	var paid: int = cells.size() * ConstructionCatalog.get_land_price() + ConstructionCatalog.get_land_floor_cost(cells.size())
	OfficeState.land_paid = maxi(OfficeState.land_paid - paid, 0)
	Economy.earn(refund, CONCEPT_LAND)
	EventBus.office_changed.emit()
	result["message"] = "Vendiste %d m² de terreno por %s." % [cells.size(), MoneyFormat.format(refund)]
	return result


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
	var partner: Vector3i = OfficeState.get_double_door_partner()
	if moves_entrance:
		var old_door: Vector3i = GridEdge.between(OfficeState.entrance, street)
		var door_kind: String = String(OfficeState.edges.get(old_door, ConstructionCatalog.DOOR))
		new_edges.erase(old_door)
		var new_door: Vector3i = GridEdge.between(entrance, entrance + outward)
		new_edges[new_door] = door_kind
		# La puerta de vidrio doble se lleva su otro tramo al mismo lado del borde nuevo.
		if partner != OfficeState.NO_EDGE:
			var moved: Vector3i = partner + (new_door - old_door)
			if new_edges.get(moved, "") == ConstructionCatalog.WALL and GridEdge.is_exterior(moved, new_lot):
				new_edges[moved] = ConstructionCatalog.GLASS_DOOR_DOUBLE
		result["entrance"] = entrance
	OfficeState.place_double_door(new_edges, new_lot, GridEdge.between(entrance, entrance + outward) if moves_entrance
		else OfficeState.get_entrance_edge())
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
