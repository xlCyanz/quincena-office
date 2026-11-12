# Catálogo de contratos leído de data/contracts.json: tamaños, tipos de proyecto,
# reglas de las ofertas y nombres de clientes. Se usa por su nombre de clase; el
# archivo se lee una sola vez.
class_name ContractCatalog
extends RefCounted

const CONTRACTS_PATH: String = "res://data/contracts.json"
## Fases del trabajo, en el orden en que avanzan.
const PHASES: Array[String] = ["design", "programming", "testing"]
const PHASE_NAMES: Dictionary[String, String] = {"design": "diseño", "programming": "programación", "testing": "pruebas"}

static var _data: Dictionary = {}


static func get_size_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_contracts()["sizes"].keys())
	return ids


static func get_size(size: String) -> Dictionary:
	return _contracts()["sizes"].get(size, {})


static func get_size_name(size: String) -> String:
	return String(get_size(size).get("name", size))


## Rango [mínimo, máximo] de un valor de un tamaño: "points" o "pay".
static func get_size_range(size: String, key: String) -> Vector2i:
	var values: Array = get_size(size)[key]
	return Vector2i(int(values[0]), int(values[1]))


## Plazo [mínimo, máximo] en días para un contrato de points puntos (hito 29): lo que
## tarda al ritmo esperado de su tamaño por la holgura de offers.days_slack.
static func get_days_range(size: String, points: int) -> Vector2i:
	var rate: float = maxf(1.0, float(get_size(size).get("points_per_day", 1)))
	var slack: Array = get_offers("days_slack")
	return Vector2i(ceili(points / rate * float(slack[0])), ceili(points / rate * float(slack[1])))


static func get_type_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_contracts()["types"].keys())
	return ids


static func get_type_name(type_id: String) -> String:
	return String(_contracts()["types"].get(type_id, {}).get("name", type_id))


## Porcentajes de diseño, programación y pruebas de un tipo de proyecto.
static func get_split(type_id: String) -> Array[int]:
	var split: Array[int] = []
	for value: Variant in _contracts()["types"][type_id]["split"]:
		split.append(int(value))
	return split


## Un valor de la sección "offers".
static func get_offers(key: String) -> Variant:
	return _contracts()["offers"][key]


## Valor de las visitas de clientes (data/contracts.json, visits).
static func get_visits(key: String) -> Variant:
	return _contracts()["visits"][key]


## Valor de los errores (data/contracts.json, bugs).
static func get_bugs(key: String) -> Variant:
	return _contracts()["bugs"][key]


## Valor de la entrega (data/contracts.json, delivery).
static func get_delivery(key: String) -> Variant:
	return _contracts()["delivery"][key]


## Puntos de programación por error, en promedio, de un nivel.
static func get_points_per_bug(level: String) -> float:
	return float(_contracts()["bugs"]["points_per_bug"].get(level, 30))


static func get_clients() -> Array[String]:
	var clients: Array[String] = []
	clients.assign(_contracts()["clients"])
	return clients


static func _contracts() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACTS_PATH))
		if not parsed is Dictionary:
			push_error("No se pudo leer %s" % CONTRACTS_PATH)
			return {}
		_data = parsed
	return _data
