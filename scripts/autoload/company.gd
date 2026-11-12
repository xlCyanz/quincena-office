# La empresa en conjunto (diseño, 9 y 17.2).
#
# Hito 26: el valor de la empresa, un número siempre visible que funciona como
# puntuación: dinero + reventa de los muebles y las computadoras + terreno comprado (a
# lo que se pagó) − deuda con el banco (capital pendiente, cuotas atrasadas y recargos).
# Los productos se suman en la fase 5. No se guarda: se calcula con Economy,
# OfficeState y Bank, y cuando algo de eso cambia avisa con
# EventBus.company_value_changed.
#
# Hito 27: las cinco etapas de data/stages.json. Se revisan cada día y nunca bajan; al
# subir avisan (EventBus.stage_changed y un aviso al jugador). Cada etapa pone un tope
# por préstamo (Bank) y puede desbloquear tipos de habitación (Builder). Los contratos
# medianos piden la etapa 2 (Projects). Los objetivos guiados llegan en el hito 28.
extends Node

const STAGES_PATH: String = "res://data/stages.json"

## Etapa actual: 0 = Emprendimiento … 4 = Corporación (índice en data/stages.json).
var stage: int = 0


func _ready() -> void:
	EventBus.balance_changed.connect(func(_balance: int) -> void: _notify())
	EventBus.bank_changed.connect(_notify)
	EventBus.office_changed.connect(_notify)
	EventBus.day_changed.connect(func(_day: int, _month: int) -> void: check_stage())


func new_game() -> void:
	stage = 0


# --- Valor (hito 26) ---

## Valor de la empresa.
func get_value() -> int:
	var total: int = 0
	for part: Dictionary in get_value_parts():
		total += int(part["amount"])
	return total


## Partes del valor, en orden: [{"label", "amount"}] (la deuda va en negativo).
func get_value_parts() -> Array[Dictionary]:
	return [
		{"label": "Dinero", "amount": Economy.balance},
		{"label": "Muebles y computadoras (reventa)", "amount": Bank.get_assets_value()},
		{"label": "Terreno comprado", "amount": OfficeState.land_paid},
		{"label": "Deuda con el banco", "amount": -Bank.get_seizable_debt()},
	]


func _notify() -> void:
	EventBus.company_value_changed.emit(get_value())


# --- Etapas (hito 27) ---

## Cuántas etapas hay.
func get_stage_count() -> int:
	return _stages().size()


## Datos de una etapa: {"id", "name", "requirements", "max_loan", "rooms", "unlocks"}.
func get_stage_info(index: int) -> Dictionary:
	var stages: Array = _stages()
	if index < 0 or index >= stages.size():
		return {}
	return stages[index]


func get_stage_name(index: int = -1) -> String:
	return String(get_stage_info(stage if index < 0 else index).get("name", ""))


## Requisitos de una etapa con lo que hay hoy: [{"key", "label", "current", "needed", "met"}].
func get_requirements(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var names: Dictionary = _data().get("requirement_names", {})
	var requirements: Dictionary = get_stage_info(index).get("requirements", {})
	for key: String in requirements:
		var needed: int = int(requirements[key])
		var current: int = count_requirement(key)
		result.append({"key": key, "label": String(names.get(key, key)), "current": current, "needed": needed,
			"met": current >= needed})
	return result


## Cuánto hay hoy de un requisito («employees», «delivered», «complete_teams»…). Los
## productos y los ejecutivos llegan en las fases 4 y 5: por ahora son 0.
func count_requirement(key: String) -> int:
	match key:
		"employees":
			return Staff.employees.size()
		"delivered":
			return Projects.delivered_count
		"complete_teams":
			return get_complete_team_count()
	return 0


## Equipos con al menos un diseñador, un programador y un QA.
func get_complete_team_count() -> int:
	var count: int = 0
	for team: Dictionary in Staff.teams:
		var roles: Dictionary[String, bool] = {}
		for employee_id: int in team["members"]:
			roles[String(Staff.get_employee(employee_id).get("role", ""))] = true
		if roles.has("designer") and roles.has("programmer") and roles.has("qa"):
			count += 1
	return count


## Indica si se cumplen los requisitos de una etapa.
func meets(index: int) -> bool:
	for requirement: Dictionary in get_requirements(index):
		if not requirement["met"]:
			return false
	return true


## Sube de etapa todo lo que se pueda (nunca baja). Con notify avisa al jugador de cada
## etapa nueva; al cargar una partida se hace en silencio.
func check_stage(notify: bool = true) -> void:
	var reached: int = stage
	while reached + 1 < get_stage_count() and meets(reached + 1):
		reached += 1
	if reached == stage:
		return
	stage = reached
	EventBus.stage_changed.emit(stage)
	if notify:
		var unlocks: Array = get_stage_info(stage).get("unlocks", [])
		var text: String = "¡La empresa pasó a %s!" % get_stage_name()
		if not unlocks.is_empty():
			text += " Desbloquea: %s." % ", ".join(PackedStringArray(unlocks)).to_lower()
		EventBus.notice.emit(text)


## Tope por préstamo de la etapa actual (0 = sin tope, solo manda el límite del banco).
func get_max_loan() -> int:
	return int(get_stage_info(stage).get("max_loan", 0))


## Etapa (índice) en la que se desbloquea un tipo de habitación, o 0 si está desde el inicio.
func get_room_stage(type_id: String) -> int:
	for index: int in range(get_stage_count()):
		if (get_stage_info(index).get("rooms", []) as Array).has(type_id):
			return index
	return 0


## Indica si ya se puede marcar un tipo de habitación.
func is_room_unlocked(type_id: String) -> bool:
	return stage >= get_room_stage(type_id)


## Estado para guardar.
func export_state() -> Dictionary:
	return {"stage": stage}


## Restaura el estado. Las partidas de antes del hito 27 calculan su etapa al cargar.
func import_state(state: Dictionary) -> void:
	stage = clampi(int(state.get("stage", 0)), 0, maxi(0, get_stage_count() - 1))
	check_stage(false)


func _stages() -> Array:
	return _data().get("stages", [])


# Se lee al usarlo, como data/bank.json, para que los ajustes del hito 29 se vean sin reiniciar.
func _data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAGES_PATH))
	if parsed is Dictionary:
		return parsed
	push_error("No se pudo leer %s" % STAGES_PATH)
	return {}
