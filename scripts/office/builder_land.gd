# Construcción, capa 3: compra de terreno (lotes, rectángulos y lados).
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
