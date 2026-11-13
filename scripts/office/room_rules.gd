# Reglas de las habitaciones, como funciones puras sobre los datos de OfficeState.
#
# Un espacio es una zona de casillas que se recorre sin cruzar paredes ni puertas
# (los muebles no cuentan). Está cerrado si todo su contorno tiene pared o puerta, y
# puede ser habitación si además tiene al menos una puerta. Se calcula con un relleno
# desde cada casilla (diseño, 15.7); con los tamaños de la fase 1 es instantáneo, así
# que se recalcula con cada cambio de paredes y no solo al salir del modo construcción.
#
# Una habitación es {"type": String, "cells": Array[Vector2i]} (y "dirt", su suciedad
# desde el hito 37): siempre ocupa un
# espacio entero. Al cambiar las paredes, cada habitación pasa al espacio nuevo que
# tiene más de sus muebles obligatorios y, a igualdad, más casillas en común con ella;
# si ninguno le sirve, se deshace.
class_name RoomRules
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]


## Espacios del local. Cada uno es {"cells": Array[Vector2i], "doors": int,
## "closed": bool, "exterior": bool}; exterior dice si toca el borde del local con
## una pared o una puerta.
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


## Motivo por el que space no se puede marcar como type_id, o "" si se puede. rooms son
## las habitaciones actuales (la que ya ocupe ese espacio se reemplazaría).
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


## Las habitaciones después de un cambio de paredes: cada una pasa al espacio que
## comparte casillas con ella y tiene más de sus muebles obligatorios (a igualdad, el
## que más casillas comparte), si se puede marcar ahí. Las bloqueadas (locked) eligen
## primero. Las que no encuentran espacio se pierden.
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
		# La suciedad (hito 37) sigue a la habitación aunque cambie de casillas.
		result.append({"type": room["type"], "cells": cells.duplicate(), "dirt": float(room.get("dirt", 0.0))})
	return result


# Cuántos muebles de los que pide un tipo de habitación hay dentro de cells.
static func _count_required_furniture(type_id: String, cells: Array[Vector2i], furniture: Array[Dictionary]) -> int:
	var count: int = 0
	for requirement: Dictionary in RoomCatalog.get_requirements(type_id):
		for item: Dictionary in furniture:
			if requirement["items"].has(item["id"]) and cells.has(item["cell"]):
				count += 1
	return count


## Lo que le falta a una habitación para funcionar (tamaño y muebles), en frases para
## el jugador. Vacío si funciona.
static func function_problems(room: Dictionary, furniture: Array[Dictionary]) -> Array[String]:
	var problems: Array[String] = []
	var cells: Array[Vector2i] = room["cells"]
	var min_area: int = RoomCatalog.get_min_area(room["type"])
	if cells.size() < min_area:
		problems.append("es muy pequeña (%d de %d m²)" % [cells.size(), min_area])
	for requirement: Dictionary in RoomCatalog.get_requirements(room["type"]):
		var found: bool = false
		for item: Dictionary in furniture:
			if requirement["items"].has(item["id"]) and cells.has(item["cell"]):
				found = true
				break
		if not found:
			problems.append("falta %s" % String(requirement["name"]).to_lower())
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
