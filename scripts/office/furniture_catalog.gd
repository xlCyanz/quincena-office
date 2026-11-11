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
## Las computadoras no ocupan casillas propias.
static func get_footprint(id: String, anchor: Vector2i, rotation: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if bool(get_item(id).get("on_desk", false)):
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
	var items: Dictionary = parsed.get("items", {})
	for id: String in items:
		var raw: Dictionary = items[id]
		var size: Array = raw.get("size", [1, 1])
		_items[id] = {
			"name": String(raw.get("name", id)),
			"price": int(raw.get("price", 0)),
			"size": Vector2i(int(size[0]), int(size[1])),
			"shape": String(raw.get("shape", "desk")),
			"height": float(raw.get("height", 16.0)),
			"color": Color(String(raw.get("color", "888888"))),
			"is_seat": bool(raw.get("is_seat", false)),
			"accepts_computer": bool(raw.get("accepts_computer", false)),
			"on_desk": bool(raw.get("on_desk", false)),
		}
