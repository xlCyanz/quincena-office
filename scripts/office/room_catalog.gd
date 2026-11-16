# Tipos de habitación (data/rooms.json), leídos una vez.
class_name RoomCatalog
extends RefCounted

const CATALOG_PATH: String = "res://data/rooms.json"

static var _types: Dictionary = {}


## Ids de los tipos de habitación, en el orden del archivo.
static func get_type_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_catalog().keys())
	return ids


## Datos de un tipo (ver data/rooms.json), o vacío.
static func get_type(type_id: String) -> Dictionary:
	return _catalog().get(type_id, {})


static func get_display_name(type_id: String) -> String:
	return String(get_type(type_id).get("name", type_id))


static func get_min_area(type_id: String) -> int:
	return int(get_type(type_id).get("min_area", 0))


static func is_unique(type_id: String) -> bool:
	return bool(get_type(type_id).get("unique", false))


## Cuántas habitaciones de este tipo son obligatorias (0 si es opcional).
static func get_mandatory_count(type_id: String) -> int:
	return int(get_type(type_id).get("mandatory_count", 0))


## Indica si solo se marca desde la primera oferta que la exige (Sala de reuniones).
static func is_unlocked_by_offer(type_id: String) -> bool:
	return bool(get_type(type_id).get("unlocked_by_offer", false))


## Indica si una habitación de este tipo no se puede quitar ni deshacer.
static func is_locked(type_id: String) -> bool:
	return bool(get_type(type_id).get("locked", false))


static func needs_exterior_wall(type_id: String) -> bool:
	return bool(get_type(type_id).get("needs_exterior_wall", false))


static func needs_entrance(type_id: String) -> bool:
	return bool(get_type(type_id).get("needs_entrance", false))


## Muebles que necesita: [{"name", "items", "count"?}] (vale cualquiera de items; count por defecto 1).
static func get_requirements(type_id: String) -> Array[Dictionary]:
	var requirements: Array[Dictionary] = []
	requirements.assign(get_type(type_id).get("required", []))
	return requirements


static func get_color(type_id: String) -> Color:
	return Color(String(get_type(type_id).get("color", "888888")))


static func _catalog() -> Dictionary:
	if _types.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary:
			_types = (parsed as Dictionary).get("types", {})
		else:
			push_error("No se pudo leer %s" % CATALOG_PATH)
	return _types
