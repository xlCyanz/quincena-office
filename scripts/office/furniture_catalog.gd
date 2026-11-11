# Catálogo de muebles leído de data/furniture.json. Se usa por su nombre de clase,
# por ejemplo FurnitureCatalog.get_item("basic_chair"); el archivo se lee una sola vez.
class_name FurnitureCatalog
extends RefCounted

const CATALOG_PATH: String = "res://data/furniture.json"

static var _items: Dictionary = {}


## Datos de un mueble: name, size (Vector2i), height, color (Color) e is_seat.
## Devuelve un diccionario vacío si el id no existe.
static func get_item(id: String) -> Dictionary:
	if _items.is_empty():
		_load()
	return _items.get(id, {})


## Casillas que ocupa un mueble colocado con su casilla de anclaje y su rotación.
## Con rotación 1 o 3 el mueble gira un cuarto de vuelta y se cambian ancho y fondo.
static func get_footprint(id: String, anchor: Vector2i, rotation: int) -> Array[Vector2i]:
	var size: Vector2i = get_item(id).get("size", Vector2i.ONE)
	if rotation % 2 == 1:
		size = Vector2i(size.y, size.x)
	var cells: Array[Vector2i] = []
	for x: int in range(size.x):
		for y: int in range(size.y):
			cells.append(anchor + Vector2i(x, y))
	return cells


static func _load() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary:
		push_error("No se pudo leer %s" % CATALOG_PATH)
		return
	for id: String in parsed:
		if id.begins_with("_"):
			continue
		var raw: Dictionary = parsed[id]
		var size: Array = raw.get("size", [1, 1])
		_items[id] = {
			"name": String(raw.get("name", id)),
			"size": Vector2i(int(size[0]), int(size[1])),
			"height": float(raw.get("height", 16.0)),
			"color": Color(String(raw.get("color", "888888"))),
			"is_seat": bool(raw.get("is_seat", false)),
		}
