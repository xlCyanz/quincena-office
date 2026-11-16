# Embargo: qué muebles se lleva el banco para cubrir una deuda (funciones puras; Bank aplica).
# Cuenta la reventa con computadora; nunca la silla ni el escritorio del CEO. Orden: decoración,
# puestos libres y puestos ocupados, y en cada grupo lo que más vale primero.
class_name Embargo
extends RefCounted


## Plan: {"covers", "value" (reventa de todo lo embargable), "take" (índices en furniture, en orden),
## "recovered"}. Si no cubre, take queda vacío.
static func plan(furniture: Array[Dictionary], rooms: Array[Dictionary], debt: int) -> Dictionary:
	var protected: Dictionary[int, bool] = get_protected(furniture)
	var tier: Dictionary[int, int] = {}
	for station: Dictionary in Workstations.find_all(furniture, rooms):
		var occupied: bool = not String(furniture[station["chair"]]["assigned_to"]).is_empty()
		for index: int in [station["chair"], station["desk"]]:
			tier[index] = 2 if occupied else 1
	var candidates: Array[int] = []
	var value: int = 0
	for index: int in range(furniture.size()):
		if protected.has(index):
			continue
		if not tier.has(index):
			# Una silla asignada fuera de un puesto que funciona es de alguien: al final.
			tier[index] = 2 if not String(furniture[index]["assigned_to"]).is_empty() else 0
		candidates.append(index)
		value += get_value(furniture[index])
	candidates.sort_custom(func(a: int, b: int) -> bool:
		if tier[a] != tier[b]:
			return tier[a] < tier[b]
		return get_value(furniture[a]) > get_value(furniture[b]))
	if value < debt:
		return {"covers": false, "value": value, "take": [] as Array[int], "recovered": 0}
	var take: Array[int] = []
	var recovered: int = 0
	for index: int in candidates:
		if recovered >= debt:
			break
		take.append(index)
		recovered += get_value(furniture[index])
	return {"covers": true, "value": value, "take": take, "recovered": recovered}


## Reventa de un mueble con su computadora.
static func get_value(item: Dictionary) -> int:
	var total: int = FurnitureCatalog.get_resale(item["id"])
	if not String(item.get("computer", "")).is_empty():
		total += FurnitureCatalog.get_resale(item["computer"])
	if not String(item.get("monitor", "")).is_empty():
		total += FurnitureCatalog.get_resale(item["monitor"]) * FurnitureCatalog.get_monitor_count(item)
	return total


## Índices de los muebles que no se embargan: la silla del CEO y el escritorio que la mira.
static func get_protected(furniture: Array[Dictionary]) -> Dictionary[int, bool]:
	var protected: Dictionary[int, bool] = {}
	for index: int in range(furniture.size()):
		if furniture[index]["assigned_to"] != "ceo":
			continue
		protected[index] = true
		var chair_cell: Vector2i = furniture[index]["cell"]
		for desk_index: int in range(furniture.size()):
			var desk: Dictionary = furniture[desk_index]
			if not bool(FurnitureCatalog.get_item(desk["id"]).get("accepts_computer", false)):
				continue
			var front: Vector2i = FurnitureCatalog.get_front(desk["rotation"])
			for cell: Vector2i in FurnitureCatalog.get_footprint(desk["id"], desk["cell"], desk["rotation"]):
				if cell + front == chair_cell:
					protected[desk_index] = true
	return protected
