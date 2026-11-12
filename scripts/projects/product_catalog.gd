# Catálogo de productos propios leído de data/products.json: tamaños, tipos y nombres.
# Se usa por su nombre de clase; el archivo se lee una sola vez.
class_name ProductCatalog
extends RefCounted

const PRODUCTS_PATH: String = "res://data/products.json"

static var _data: Dictionary = {}


## Etapa (índice de data/stages.json) desde la que se pueden desarrollar productos.
static func get_min_stage() -> int:
	return int(_products().get("min_stage", 0))


static func get_size_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_products()["sizes"].keys())
	return ids


static func get_size_name(size: String) -> String:
	return String(_products()["sizes"].get(size, {}).get("name", size))


static func get_points(size: String) -> int:
	return int(_products()["sizes"].get(size, {}).get("points", 0))


static func get_racks(size: String) -> int:
	return int(_products()["sizes"].get(size, {}).get("racks", 0))


static func get_daily_income(size: String) -> int:
	return int(_products()["sizes"].get(size, {}).get("daily_income", 0))


static func get_type_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_products()["types"].keys())
	return ids


static func get_type_name(type_id: String) -> String:
	return String(_products()["types"].get(type_id, {}).get("name", type_id))


## Porcentajes de diseño, programación y pruebas de un tipo de producto.
static func get_split(type_id: String) -> Array[int]:
	var split: Array[int] = []
	for value: Variant in _products()["types"][type_id]["split"]:
		split.append(int(value))
	return split


## Nombre del producto número index (0 el primero): los de la lista y después numerados.
static func get_product_name(index: int) -> String:
	var names: Array = _products().get("names", [])
	if index < names.size():
		return String(names[index])
	return "Producto %d" % (index + 1)


static func _products() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRODUCTS_PATH))
		if not parsed is Dictionary:
			push_error("No se pudo leer %s" % PRODUCTS_PATH)
			return {}
		_data = parsed
	return _data
