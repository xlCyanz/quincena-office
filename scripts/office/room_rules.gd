# Reglas de las habitaciones (funciones puras). Un espacio es una zona que se recorre sin
# cruzar paredes ni puertas; cerrado si todo su contorno tiene pared o puerta, y con una puerta
# puede ser habitación. Una habitación ({"type", "cells", "dirt"}) ocupa un espacio entero.
class_name RoomRules
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]


## Espacios del local: {"cells", "doors", "closed", "exterior"} (exterior: toca el contorno del local).
static func find_spaces(lot: Lot, edges: Dictionary[Vector3i, String]) -> Array[Dictionary]:
	var spaces: Array[Dictionary] = []
	var seen: Dictionary[Vector2i, bool] = {}
	var bounds: Rect2i = lot.get_bounds()
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var start := Vector2i(x, y)
			if seen.has(start) or not lot.has_point(start):
				continue
			seen[start] = true
			var cells: Array[Vector2i] = []
			var doors: int = 0
			var closed: bool = true
			var exterior: bool = false
			var queue: Array[Vector2i] = [start]
			while not queue.is_empty():
				var cell: Vector2i = queue.pop_back()
				cells.append(cell)
				for direction: Vector2i in DIRECTIONS:
					var next: Vector2i = cell + direction
					var outside: bool = not lot.has_point(next)
					var kind: String = edges.get(GridEdge.between(cell, next), "")
					if kind.is_empty():
						if outside:
							closed = false
						elif not seen.has(next):
							seen[next] = true
							queue.append(next)
						continue
					if ConstructionCatalog.is_door(kind):
						doors += 1
					if outside:
						exterior = true
			cells.sort()
			spaces.append({"cells": cells, "doors": doors, "closed": closed, "exterior": exterior})
	return spaces


## Índice del espacio que contiene una casilla, o -1.
static func space_index_at(spaces: Array[Dictionary], cell: Vector2i) -> int:
	for index: int in range(spaces.size()):
		var cells: Array[Vector2i] = spaces[index]["cells"]
		if cells.has(cell):
			return index
	return -1


## Índice de la habitación que contiene una casilla, o -1.
static func room_index_at(rooms: Array[Dictionary], cell: Vector2i) -> int:
	for index: int in range(rooms.size()):
		var cells: Array[Vector2i] = rooms[index]["cells"]
		if cells.has(cell):
			return index
	return -1


## Por qué space no se puede marcar como type_id, o "". rooms: las actuales (la de ese espacio se reemplaza).
static func mark_problem(type_id: String, space: Dictionary, rooms: Array[Dictionary], entrance: Vector2i) -> String:
	var type_name: String = RoomCatalog.get_display_name(type_id)
	var cells: Array[Vector2i] = space["cells"]
	if not space["closed"]:
		return "Ese espacio no está cerrado: le faltan paredes."
	if int(space["doors"]) == 0:
		return "Ese espacio no tiene puerta."
	if RoomCatalog.needs_exterior_wall(type_id) and not space["exterior"]:
		return "La %s tiene que estar junto a una pared exterior." % type_name
	if RoomCatalog.needs_entrance(type_id) and not cells.has(entrance):
		return "La %s tiene que contener la entrada de la oficina." % type_name
	for room: Dictionary in rooms:
		if not shares_cells(room["cells"], cells):
			if RoomCatalog.is_unique(type_id) and room["type"] == type_id:
				return "Solo puede haber una %s." % type_name
			continue
		if room["type"] != type_id and RoomCatalog.is_locked(room["type"]):
			return "La %s no se puede quitar." % RoomCatalog.get_display_name(room["type"])
	return ""


## Habitaciones tras cambiar paredes: cada una pasa al espacio en común con más de sus muebles
## obligatorios (a igualdad, más casillas en común). Las locked eligen primero; sin espacio se pierden.
static func reconcile(rooms: Array[Dictionary], spaces: Array[Dictionary], entrance: Vector2i,
		furniture: Array[Dictionary]) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for room: Dictionary in rooms:
		if RoomCatalog.is_locked(room["type"]):
			ordered.append(room)
	for room: Dictionary in rooms:
		if not RoomCatalog.is_locked(room["type"]):
			ordered.append(room)
	var result: Array[Dictionary] = []
	var claimed: Dictionary[int, bool] = {}
	for room: Dictionary in ordered:
		var best: int = -1
		var best_score := Vector2i.ZERO
		for index: int in range(spaces.size()):
			if claimed.has(index):
				continue
			var overlap: int = _count_shared(room["cells"], spaces[index]["cells"])
			if overlap == 0:
				continue
			var score := Vector2i(_count_required_furniture(room["type"], spaces[index]["cells"], furniture), overlap)
			if best < 0 or score > best_score:
				best = index
				best_score = score
		if best < 0 or not mark_problem(room["type"], spaces[best], result, entrance).is_empty():
			continue
		claimed[best] = true
		var cells: Array[Vector2i] = spaces[best]["cells"]
		# La suciedad sigue a la habitación aunque cambie de casillas.
		result.append({"type": room["type"], "cells": cells.duplicate(), "dirt": float(room.get("dirt", 0.0))})
	return result


# Cuántos de los muebles que pide un tipo hay en cells.
static func _count_required_furniture(type_id: String, cells: Array[Vector2i], furniture: Array[Dictionary]) -> int:
	var count: int = 0
	for requirement: Dictionary in RoomCatalog.get_requirements(type_id):
		for item: Dictionary in furniture:
			if requirement["items"].has(item["id"]) and cells.has(item["cell"]):
				count += 1
	return count


## Solo para pruebas: false pide uno de cada mueble aunque diga count. No se guarda.
static var counts_enabled: bool = true


## Lo que le falta a una habitación para funcionar, en frases para el jugador; vacío si funciona.
static func function_problems(room: Dictionary, furniture: Array[Dictionary]) -> Array[String]:
	var problems: Array[String] = []
	var cells: Array[Vector2i] = room["cells"]
	var min_area: int = RoomCatalog.get_min_area(room["type"])
	if cells.size() < min_area:
		problems.append("es muy pequeña (%d de %d m²)" % [cells.size(), min_area])
	for requirement: Dictionary in RoomCatalog.get_requirements(room["type"]):
		# count: cuántos hacen falta (por defecto uno).
		var needed: int = int(requirement.get("count", 1)) if counts_enabled else 1
		var found: int = 0
		for item: Dictionary in furniture:
			if requirement["items"].has(item["id"]) and cells.has(item["cell"]):
				found += 1
				if found >= needed:
					break
		if found < needed:
			var label: String = String(requirement["name"]).to_lower()
			problems.append("falta %s" % label if needed == 1 else "faltan %s (%d de %d)" % [label, found, needed])
	return problems


## Habitaciones obligatorias que faltan, como "Recepción" o "Baño (0 de 2)".
static func missing_mandatory(rooms: Array[Dictionary]) -> Array[String]:
	var missing: Array[String] = []
	for type_id: String in RoomCatalog.get_type_ids():
		var needed: int = RoomCatalog.get_mandatory_count(type_id)
		var count: int = 0
		for room: Dictionary in rooms:
			if room["type"] == type_id:
				count += 1
		if count >= needed:
			continue
		var type_name: String = RoomCatalog.get_display_name(type_id)
		missing.append(type_name if needed == 1 else "%s (%d de %d)" % [type_name, count, needed])
	return missing


## Indica si dos listas de casillas tienen alguna en común.
static func shares_cells(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	return _count_shared(a, b) > 0


static func _count_shared(a: Array[Vector2i], b: Array[Vector2i]) -> int:
	var count: int = 0
	for cell: Vector2i in a:
		if b.has(cell):
			count += 1
	return count
