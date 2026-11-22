# Catálogo de muebles (data/furniture.json), leído una vez. Rotación 0–3: hacia dónde mira el
# frente (0 = -y, 1 = +x, 2 = +y, 3 = -x).
class_name FurnitureCatalog
extends RefCounted

## Cuartos de una casilla para los muebles chicos.
const QUARTERS: int = 4
const CATALOG_PATH: String = "res://data/furniture.json"
const FRONT_DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static var _items: Dictionary = {}
static var _resale_ratio: float = 0.0
static var _ambiance: Dictionary = {}
static var _categories: Dictionary = {}


## Datos de un mueble (name, price, size, shape, height, color, …); vacío si el id no existe.
static func get_item(id: String) -> Dictionary:
	if _items.is_empty():
		_load()
	return _items.get(id, {})


## Categorías de la sección Muebles de Construir: id → nombre, en orden.
static func get_categories() -> Dictionary:
	if _items.is_empty():
		_load()
	return _categories


## Categoría de un mueble ("" si no tiene).
static func get_category(id: String) -> String:
	return String(get_item(id).get("category", ""))


## Muebles que se compran en construcción, en el orden del archivo.
static func get_ids() -> Array[String]:
	if _items.is_empty():
		_load()
	var ids: Array[String] = []
	ids.assign(_items.keys())
	return ids


static func get_price(id: String) -> int:
	return int(get_item(id).get("price", 0))


## Costo mensual (los racks; 0 los demás).
static func get_monthly_cost(id: String) -> int:
	return int(get_item(id).get("monthly_cost", 0))


## Para qué sirve en el almuerzo dentro (hito 53): "fridge", "microwave", "table" o "".
static func get_lunch_part(id: String) -> String:
	return String(get_item(id).get("lunch_part", ""))


## Valor numérico de un mueble (0 si no lo tiene): rest_places, break_mood, distraction, vending_income.
static func get_number(id: String, field: String) -> float:
	return float(get_item(id).get(field, 0.0))


## Asientos de una mesa de comedor (0 si no es mesa).
static func get_dining_seats(id: String) -> int:
	return int(get_item(id).get("dining_seats", 0))


## Indica si es un inodoro (hito 52: capacidad de los baños).
static func is_toilet(id: String) -> bool:
	return bool(get_item(id).get("is_toilet", false))


## Indica si es un inodoro.
static func is_server_rack(id: String) -> bool:
	return bool(get_item(id).get("server_rack", false))


## Reventa (hacia abajo).
static func get_resale(id: String) -> int:
	if _items.is_empty():
		_load()
	return floori(get_price(id) * _resale_ratio)


## Dirección del frente para una rotación.
static func get_front(rotation: int) -> Vector2i:
	return FRONT_DIRECTIONS[posmod(rotation, 4)]


## Casillas que ocupa un mueble con su anclaje y rotación (1 y 3 cambian ancho y fondo).
## Computadoras y objetos de pared no ocupan casillas.
static func get_footprint(id: String, anchor: Vector2i, rotation: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if bool(get_item(id).get("on_desk", false)) or is_wall_mounted(id):
		return cells
	var size: Vector2i = get_item(id).get("size", Vector2i.ONE)
	if rotation % 2 == 1:
		size = Vector2i(size.y, size.x)
	for x: int in range(size.x):
		for y: int in range(size.y):
			cells.append(anchor + Vector2i(x, y))
	return cells


static func _load() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary:
		push_error("No se pudo leer %s" % CATALOG_PATH)
		return
	_resale_ratio = float(parsed.get("resale_ratio", 0.0))
	_ambiance = parsed.get("ambiance", {})
	_categories = parsed.get("categories", {})
	var items: Dictionary = parsed.get("items", {})
	for id: String in items:
		var raw: Dictionary = items[id]
		var size: Array = raw.get("size", [1, 1])
		_items[id] = {
			"name": String(raw.get("name", id)),
			"short_name": String(raw.get("short_name", raw.get("name", id))),
			"category": String(raw.get("category", "")),
			"price": int(raw.get("price", 0)),
			"size": Vector2i(int(size[0]), int(size[1])),
			"shape": String(raw.get("shape", "desk")),
			"height": float(raw.get("height", 16.0)),
			"color": Color(String(raw.get("color", "888888"))),
			"is_seat": bool(raw.get("is_seat", false)),
			"accepts_computer": bool(raw.get("accepts_computer", false)),
			"on_desk": bool(raw.get("on_desk", false)),
			"is_counter": bool(raw.get("is_counter", false)),
			"waiting_seat": bool(raw.get("waiting_seat", false)),
			"trash_can": bool(raw.get("trash_can", false)),
			"is_closet": bool(raw.get("is_closet", false)),
			"server_rack": bool(raw.get("server_rack", false)),
			"air_conditioner": bool(raw.get("air_conditioner", false)),
			"monthly_cost": int(raw.get("monthly_cost", 0)),
			"wall_mounted": bool(raw.get("wall_mounted", false)),
			"walkable": bool(raw.get("walkable", false)),
			"small": bool(raw.get("small", false)),
			"ambiance": float(raw.get("ambiance", 0.0)),
			"stress_relief": int(raw.get("stress_relief", 0)),
			"production_bonus": float(raw.get("production_bonus", 0.0)),
			"upgrade_to": String(raw.get("upgrade_to", "")),
			"is_monitor": bool(raw.get("is_monitor", false)),
			"max_monitors": int(raw.get("max_monitors", 0)),
			"extra_monitors": bool(raw.get("extra_monitors", false)),
			"desks": Array(raw.get("desks", []), TYPE_STRING, "", null),
			"energy_per_work_hour": int(raw.get("energy_per_work_hour", 0)),
			"mood_bonus": int(raw.get("mood_bonus", 0)),
			"presentation_screen": bool(raw.get("presentation_screen", false)),
			"is_toilet": bool(raw.get("is_toilet", false)),
			"lunch_part": String(raw.get("lunch_part", "")),
			"dining_seats": int(raw.get("dining_seats", 0)),
			"rest_places": int(raw.get("rest_places", 0)),
			"accountant_boost": float(raw.get("accountant_boost", 0.0)),
			"meeting_board": bool(raw.get("meeting_board", false)),
			"break_mood": float(raw.get("break_mood", 0.0)),
			"distraction": float(raw.get("distraction", 0.0)),
			"vending_income": float(raw.get("vending_income", 0.0)),
		}


## Mueble chico: ocupa un cuarto de su casilla y caben hasta 4 chicos por casilla.
static func is_small(id: String) -> bool:
	return bool(get_item(id).get("small", false))


## Cuarto de la casilla que ocupa un mueble (0–3), o -1 si ocupa la casilla entera.
static func get_quarter(item: Dictionary) -> int:
	return clampi(int(item.get("quarter", 0)), 0, QUARTERS - 1) if is_small(String(item["id"])) else -1


## Centro de un cuarto respecto al de su casilla, en casillas: 0 arriba a la izquierda, 1 a su
## derecha (x mayor), 2 y 3 debajo (y mayor).
static func get_quarter_offset(quarter: int) -> Vector2:
	return Vector2(float(quarter % 2) - 0.5, float(quarter / 2) - 0.5) * 0.5


## Cuarto de su casilla en el que cae un punto de la cuadrícula (con decimales).
static func quarter_at(point: Vector2) -> int:
	var local: Vector2 = point - point.round()
	return (1 if local.x >= 0.0 else 0) + (2 if local.y >= 0.0 else 0)


## Indica si dos muebles chocan (comparten casilla y no son dos chicos en cuartos distintos).
static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	var cells_a: Array[Vector2i] = get_footprint(a["id"], a["cell"], a["rotation"])
	var shared: bool = false
	for cell: Vector2i in get_footprint(b["id"], b["cell"], b["rotation"]):
		if cells_a.has(cell):
			shared = true
			break
	if not shared:
		return false
	var quarter_a: int = get_quarter(a)
	var quarter_b: int = get_quarter(b)
	return quarter_a < 0 or quarter_b < 0 or quarter_a == quarter_b


## Indica si se cuelga en una pared: no ocupa casilla; su casilla es la que mira y la pared queda detrás.
static func is_wall_mounted(id: String) -> bool:
	return bool(get_item(id).get("wall_mounted", false))


## Calidad siguiente de un mueble, o "" si no se mejora.
static func get_wall_edge(cell: Vector2i, rotation: int) -> Vector3i:
	return GridEdge.between(cell, cell - get_front(rotation))


## Indica si es una pantalla extra (va sobre un escritorio con computadora).
static func get_upgrade(id: String) -> String:
	return String(get_item(id).get("upgrade_to", ""))


## Pantallas extra que admite un escritorio.
static func is_monitor(id: String) -> bool:
	return bool(get_item(id).get("is_monitor", false))


## Indica si una computadora admite pantallas extra.
static func get_max_monitors(id: String) -> int:
	return int(get_item(id).get("max_monitors", 0))


## Pantallas extra de un escritorio (partidas viejas guardaban una en "monitor").
static func allows_monitors(computer_id: String) -> bool:
	return bool(get_item(computer_id).get("extra_monitors", false))


## Cuántas pantallas extra tiene un escritorio (las partidas de antes guardaban solo una, en "monitor").
static func get_monitor_count(item: Dictionary) -> int:
	if String(item.get("monitor", "")).is_empty():
		return 0
	return maxi(int(item.get("monitors", 1)), 1)


## Escritorios en los que cabe una computadora: vacío = en cualquiera.
static func get_desks(computer_id: String) -> Array[String]:
	return get_item(computer_id).get("desks", [] as Array[String])


## Indica si una computadora se puede poner sobre ese escritorio (la laptop, solo en el ejecutivo).
static func fits_desk(computer_id: String, desk_id: String) -> bool:
	var desks: Array[String] = get_desks(computer_id)
	return desks.is_empty() or desks.has(desk_id)


## Bono de producción (computadora o pantalla extra).
static func get_production_bonus(id: String) -> float:
	return float(get_item(id).get("production_bonus", 0.0))


## Energía por hora trabajada sentado ahí, o 0 para usar la de staff.json.
static func get_work_energy(id: String) -> int:
	return int(get_item(id).get("energy_per_work_hour", 0))


## Suma a la meta de ánimo de quien trabaja en ese escritorio.
static func get_mood_bonus(id: String) -> int:
	return int(get_item(id).get("mood_bonus", 0))


## Indica si es una pantalla de presentaciones.
static func is_presentation_screen(id: String) -> bool:
	return bool(get_item(id).get("presentation_screen", false))


## Indica si tapa el paso (la alfombra se pisa).
static func blocks_passage(id: String) -> bool:
	return not bool(get_item(id).get("walkable", false))


## Puntos de ambiente que da un adorno (0 si no es adorno).
static func get_ambiance_points(id: String) -> float:
	return float(get_item(id).get("ambiance", 0.0))


## Cuánto baja la meta de estrés de su habitación (la pecera).
static func get_stress_relief(id: String) -> int:
	return int(get_item(id).get("stress_relief", 0))


## Valor de furniture.json, ambiance.
static func get_ambiance_config(key: String) -> float:
	if _items.is_empty():
		_load()
	return float(_ambiance.get(key, 0.0))
