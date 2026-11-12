# Ambiente de una habitación (diseño 2 y 19.2; hito 45). Funciones puras sobre los datos
# de OfficeState. Los adornos (plantas, cuadros, reloj, lámpara, alfombra, pecera) suman
# sus puntos de ambiente; los puntos se reparten por el área (una sala grande pide más
# adornos). Amontonar resta según cuánto se pasa de los escritorios que caben (uno cada
# desk_area m²): crowding_max al tener crowding_full_over más, en proporción antes. El valor,
# redondeado y entre min y max de data/furniture.json, se suma a la meta de ánimo de
# quienes trabajan en la habitación.
class_name Ambiance
extends RefCounted


## Detalle del ambiente de una habitación: {"points" (puntos de adornos), "decor" (lo que
## suman por el área), "desks", "allowed_desks", "crowding" (lo que resta amontonar, ≤ 0),
## "value" (int, el ambiente) y "stress_relief" (lo que baja la meta de estrés, la pecera
## más fuerte que haya)}.
static func get_detail(room: Dictionary, furniture: Array[Dictionary]) -> Dictionary:
	var cells: Array[Vector2i] = room["cells"]
	var area: int = maxi(1, cells.size())
	var points: float = 0.0
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


## Ambiente de una habitación (lo que suma a la meta de ánimo).
static func get_value(room: Dictionary, furniture: Array[Dictionary]) -> int:
	return int(get_detail(room, furniture)["value"])


## "Ambiente +6" (o "−5 por amontonar"): para el modo construcción y la ficha.
static func describe(room: Dictionary, furniture: Array[Dictionary]) -> String:
	var detail: Dictionary = get_detail(room, furniture)
	var value: int = detail["value"]
	var text: String = "Ambiente %s%d" % ["+" if value > 0 else ("−" if value < 0 else ""), absi(value)]
	if int(detail["desks"]) > int(detail["allowed_desks"]):
		text += " (amontonado: %d escritorios, caben %d)" % [detail["desks"], detail["allowed_desks"]]
	return text
