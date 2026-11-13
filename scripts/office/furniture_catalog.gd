# Catálogo de muebles leído de data/furniture.json. Se usa por su nombre de clase,
# por ejemplo FurnitureCatalog.get_item("basic_chair"); el archivo se lee una sola vez.
#
# La rotación va de 0 a 3 y dice hacia dónde mira el frente del mueble en la
# cuadrícula: 0 = -y, 1 = +x, 2 = +y, 3 = -x (cada paso es un cuarto de vuelta).
class_name FurnitureCatalog
extends RefCounted

const CATALOG_PATH: String = "res://data/furniture.json"
const FRONT_DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static var _items: Dictionary = {}
static var _resale_ratio: float = 0.0
static var _ambiance: Dictionary = {}


## Datos de un mueble: name, price, size (Vector2i), shape, height, color (Color),
## is_seat, accepts_computer y on_desk. Devuelve un diccionario vacío si el id no existe.
static func get_item(id: String) -> Dictionary:
	if _items.is_empty():
		_load()
	return _items.get(id, {})


## Ids de los muebles que se compran desde el modo construcción, en el orden del archivo.
static func get_ids() -> Array[String]:
	if _items.is_empty():
		_load()
	var ids: Array[String] = []
	ids.assign(_items.keys())
	return ids


static func get_price(id: String) -> int:
	return int(get_item(id).get("price", 0))


## Lo que cuesta al mes tenerlo (los racks de servidores; 0 los demás).
static func get_monthly_cost(id: String) -> int:
	return int(get_item(id).get("monthly_cost", 0))


## Indica si es un rack de servidores (capacidad para productos).
## Para qué sirve en el almuerzo dentro (hito 53): "fridge", "microwave", "table" o "".
static func get_lunch_part(id: String) -> String:
	return String(get_item(id).get("lunch_part", ""))


## Valor numérico de un mueble (0 si no lo tiene): rest_places, break_mood, distraction,
## vending_income (hito 54).
static func get_number(id: String, field: String) -> float:
	return float(get_item(id).get(field, 0.0))


## Asientos de una mesa de comedor (0 si no es mesa).
static func get_dining_seats(id: String) -> int:
	return int(get_item(id).get("dining_seats", 0))


## Indica si es un inodoro (hito 52: capacidad de los baños).
static func is_toilet(id: String) -> bool:
	return bool(get_item(id).get("is_toilet", false))


static func is_server_rack(id: String) -> bool:
	return bool(get_item(id).get("server_rack", false))


## Lo que devuelve la reventa (redondeado hacia abajo).
static func get_resale(id: String) -> int:
	if _items.is_empty():
		_load()
	return floori(get_price(id) * _resale_ratio)


## Dirección del frente para una rotación.
static func get_front(rotation: int) -> Vector2i:
	return FRONT_DIRECTIONS[posmod(rotation, 4)]


## Casillas que ocupa un mueble colocado con su casilla de anclaje y su rotación.
## Con rotación 1 o 3 el mueble gira un cuarto de vuelta y se cambian ancho y fondo.
## Las computadoras y los objetos de pared no ocupan casillas propias.
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
	var items: Dictionary = parsed.get("items", {})
	for id: String in items:
		var raw: Dictionary = items[id]
		var size: Array = raw.get("size", [1, 1])
		_items[id] = {
			"name": String(raw.get("name", id)),
			"short_name": String(raw.get("short_name", raw.get("name", id))),
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
			"ambiance": float(raw.get("ambiance", 0.0)),
			"stress_relief": int(raw.get("stress_relief", 0)),
			"production_bonus": float(raw.get("production_bonus", 0.0)),
			"upgrade_to": String(raw.get("upgrade_to", "")),
			"is_monitor": bool(raw.get("is_monitor", false)),
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


## Indica si se cuelga en una pared (hito 45): no ocupa casilla. Su casilla es la que
## mira (la de la habitación donde cuenta) y la pared queda detrás de su frente.
static func is_wall_mounted(id: String) -> bool:
	return bool(get_item(id).get("wall_mounted", false))


## Borde con pared donde cuelga un objeto de pared: el de su casilla detrás del frente.
static func get_wall_edge(cell: Vector2i, rotation: int) -> Vector3i:
	return GridEdge.between(cell, cell - get_front(rotation))


## Calidad siguiente de un mueble o computadora (hito 46), o "" si no se mejora.
static func get_upgrade(id: String) -> String:
	return String(get_item(id).get("upgrade_to", ""))


## Indica si es un segundo monitor: va sobre un escritorio con computadora.
static func is_monitor(id: String) -> bool:
	return bool(get_item(id).get("is_monitor", false))


## Lo que suma a la producción de quien lo usa (computadora o segundo monitor).
static func get_production_bonus(id: String) -> float:
	return float(get_item(id).get("production_bonus", 0.0))


## Energía por hora trabajada sentado ahí (una silla), o 0 si usa la de data/staff.json.
static func get_work_energy(id: String) -> int:
	return int(get_item(id).get("energy_per_work_hour", 0))


## Lo que suma a la meta de ánimo de quien trabaja en ese escritorio.
static func get_mood_bonus(id: String) -> int:
	return int(get_item(id).get("mood_bonus", 0))


## Indica si es una pantalla de presentaciones (hito 47).
static func is_presentation_screen(id: String) -> bool:
	return bool(get_item(id).get("presentation_screen", false))


## Indica si estorba el paso (la alfombra se pisa: ocupa su casilla pero no tapa el paso).
static func blocks_passage(id: String) -> bool:
	return not bool(get_item(id).get("walkable", false))


## Puntos de ambiente que da un adorno (0 si no es adorno).
static func get_ambiance_points(id: String) -> float:
	return float(get_item(id).get("ambiance", 0.0))


## Cuánto baja la meta de estrés de quienes trabajan en su habitación (la pecera).
static func get_stress_relief(id: String) -> int:
	return int(get_item(id).get("stress_relief", 0))


## Valor de la sección ambiance de data/furniture.json (área por punto, amontonar, topes).
static func get_ambiance_config(key: String) -> float:
	if _items.is_empty():
		_load()
	return float(_ambiance.get(key, 0.0))
