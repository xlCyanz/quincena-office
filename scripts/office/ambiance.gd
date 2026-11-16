# Ambiente de una habitación (funciones puras): puntos de adornos repartidos por el área, menos
# amontonar (crowding_max con crowding_full_over más escritorios de los que caben, uno cada
# desk_area m²). Redondeado entre min y max, suma a la meta de ánimo de quien trabaja ahí.
class_name Ambiance
extends RefCounted


## Detalle: {"points", "decor" (por el área), "desks", "allowed_desks", "crowding" (≤ 0), "value"
## (int) y "stress_relief" (la pecera más fuerte)}. windows y extra_points (puerta de vidrio)
## suman como adornos.
static func get_detail(room: Dictionary, furniture: Array[Dictionary], windows: int = 0, extra_points: int = 0) -> Dictionary:
	var cells: Array[Vector2i] = room["cells"]
	var area: int = maxi(1, cells.size())
	var points: float = windows * ConstructionCatalog.get_window_ambiance() + extra_points
	var desks: int = 0
	var relief: int = 0
	var cell_set: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		cell_set[cell] = true
	for item: Dictionary in furniture:
		if not cell_set.has(item["cell"]):
			continue
		points += FurnitureCatalog.get_ambiance_points(item["id"])
		relief = maxi(relief, FurnitureCatalog.get_stress_relief(item["id"]))
		if bool(FurnitureCatalog.get_item(item["id"]).get("accepts_computer", false)):
			desks += 1
	var decor: float = points * FurnitureCatalog.get_ambiance_config("area_unit") / area
	var allowed: int = floori(area / maxf(1.0, FurnitureCatalog.get_ambiance_config("desk_area")))
	var over: float = float(maxi(0, desks - allowed)) / maxi(1, allowed)
	var crowding: float = -FurnitureCatalog.get_ambiance_config("crowding_max") \
		* minf(1.0, over / maxf(0.01, FurnitureCatalog.get_ambiance_config("crowding_full_over")))
	var value: int = clampi(roundi(decor + crowding), int(FurnitureCatalog.get_ambiance_config("min")),
		int(FurnitureCatalog.get_ambiance_config("max")))
	return {"points": points, "decor": decor, "desks": desks, "allowed_desks": allowed, "crowding": crowding,
		"value": value, "stress_relief": relief}


## Ambiente de una habitación (suma a la meta de ánimo).
static func get_value(room: Dictionary, furniture: Array[Dictionary], windows: int = 0, extra_points: int = 0) -> int:
	return int(get_detail(room, furniture, windows, extra_points)["value"])


## "Ambiente +6" (o "−5 por amontonar") para construcción y la ficha.
static func describe(room: Dictionary, furniture: Array[Dictionary], windows: int = 0, extra_points: int = 0) -> String:
	var detail: Dictionary = get_detail(room, furniture, windows, extra_points)
	var value: int = detail["value"]
	var text: String = "Ambiente %s%d" % ["+" if value > 0 else ("−" if value < 0 else ""), absi(value)]
	if int(detail["desks"]) > int(detail["allowed_desks"]):
		text += " (amontonado: %d escritorios, caben %d)" % [detail["desks"], detail["allowed_desks"]]
	return text
