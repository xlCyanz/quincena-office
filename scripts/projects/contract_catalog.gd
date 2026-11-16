# Catálogo de contratos (data/contracts.json): tamaños, tipos, reglas de ofertas y clientes.
# Se lee una vez; se usa por su nombre de clase.
class_name ContractCatalog
extends RefCounted

const CONTRACTS_PATH: String = "res://data/contracts.json"
## Fases del trabajo, en orden.
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


## Plazo [mínimo, máximo] en días para points puntos: lo que tarda al ritmo de su tamaño × offers.days_slack.
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


## Valor de contracts.json, visits.
static func get_visits(key: String) -> Variant:
	return _contracts()["visits"][key]


## Valor de contracts.json, bugs.
static func get_bugs(key: String) -> Variant:
	return _contracts()["bugs"][key]


## Valor de contracts.json, delivery.
static func get_delivery(key: String) -> Variant:
	return _contracts()["delivery"][key]


## Puntos de programación por error, en promedio, de un nivel.
static func get_points_per_bug(level: String) -> float:
	return float(_contracts()["bugs"]["points_per_bug"].get(level, 30))


## Valor de contracts.json, meetings.
static func get_meetings(key: String) -> Variant:
	return _contracts().get("meetings", {}).get(key, 1.0)


## Habitación que exige un tamaño para aceptarlo ("" si ninguna).
static func get_required_room(size: String) -> String:
	return String(get_size(size).get("requires_room", ""))


## Indica si un tamaño es de clientes de élite.
static func is_elite(size: String) -> bool:
	return bool(get_size(size).get("elite", false))


static func get_elite_clients() -> Array[String]:
	var clients: Array[String] = []
	clients.assign(_contracts().get("elite_clients", []))
	return clients


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
