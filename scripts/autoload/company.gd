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
# medianos piden la etapa 2 (Projects).
#
# Hito 28: los objetivos guiados de data/objectives.json. Se ven los primeros
# visible_count sin cumplir, en orden; cuando uno se cumple avisa, paga su recompensa
# (dinero con el concepto «Objetivo cumplido» y reputación) una sola vez y entra el
# siguiente. Las condiciones miran el estado de la partida (cuántos hay de algo), así
# una partida vieja marca al cargar los que ya cumple, sin recompensa.
extends Node

const STAGES_PATH: String = "res://data/stages.json"
const OBJECTIVES_PATH: String = "res://data/objectives.json"

## Etapa actual: 0 = Emprendimiento … 4 = Corporación (índice en data/stages.json).
var stage: int = 0

## Ids de los objetivos cumplidos, en el orden en que se cumplieron.
var objectives_done: Array[String] = []

# Mientras SaveManager prepara o carga una partida, los demás sistemas cambian de a uno
# y avisan: no se revisan objetivos con un estado a medias.
var _loading: bool = false
# Partida de antes del hito 28: al terminar de cargar se marcan los que ya cumple.
var _mark_silently: bool = false
# Pagar una recompensa cambia el saldo y vuelve a avisar: se evita revisar dentro de una revisión.
var _checking: bool = false


func _ready() -> void:
	EventBus.balance_changed.connect(func(_balance: int) -> void: _notify())
	EventBus.bank_changed.connect(_notify)
	EventBus.office_changed.connect(_notify)
	EventBus.day_changed.connect(func(_day: int, _month: int) -> void: check_stage())
	EventBus.staff_changed.connect(check_objectives)
	EventBus.projects_changed.connect(check_objectives)
	EventBus.office_changed.connect(check_objectives)
	EventBus.stage_changed.connect(func(_stage: int) -> void: check_objectives())
	EventBus.company_value_changed.connect(func(_value: int) -> void: check_objectives())


func new_game() -> void:
	stage = 0
	objectives_done.clear()
	_mark_silently = false


## SaveManager avisa que empieza a preparar o cargar una partida…
func begin_load() -> void:
	_loading = true


## … y que terminó: se marcan sin recompensa los objetivos que una partida vieja ya
## cumple y se revisan los demás.
func finish_load() -> void:
	_loading = false
	if _mark_silently:
		_mark_met_silently()
	EventBus.objectives_changed.emit()
	check_objectives()


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
		"executives":
			return Staff.get_executives().size()
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
		var text: String = "¡La empresa pasó a %s!" % get_stage_name()
		var unlocks: Array[String] = get_new_unlocks(stage)
		if not unlocks.is_empty():
			text += " Desbloquea: %s." % ", ".join(PackedStringArray(unlocks)).to_lower()
		EventBus.notice.emit(text)


## Lo que trae una etapa al llegar: su lista unlocks más el tope por préstamo si cambia.
func get_new_unlocks(index: int) -> Array[String]:
	var result: Array[String] = []
	var cap: int = int(get_stage_info(index).get("max_loan", 0))
	if index > 0 and cap != int(get_stage_info(index - 1).get("max_loan", 0)):
		result.append(describe_loan_cap(cap))
	for item: Variant in get_stage_info(index).get("unlocks", []):
		result.append(String(item))
	return result


## «Préstamos de hasta $10,000» o «Préstamos sin tope de etapa» (solo el límite del banco).
static func describe_loan_cap(cap: int) -> String:
	return "Préstamos de hasta %s" % MoneyFormat.format(cap) if cap > 0 else "Préstamos sin tope de etapa (solo el límite del banco)"


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


# --- Objetivos (hito 28) ---

## Todos los objetivos, en orden: {"id", "text", "condition", "money", "reputation"}.
func get_objectives() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in _objectives_data().get("objectives", []):
		result.append(item)
	return result


## Los objetivos que se ven ahora: los primeros sin cumplir, hasta visible_count.
func get_visible_objectives() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data: Dictionary = _objectives_data()
	var limit: int = int(data.get("visible_count", 3))
	for item: Dictionary in data.get("objectives", []):
		if result.size() >= limit:
			break
		if not objectives_done.has(String(item["id"])):
			result.append(item)
	return result


func is_objective_done(objective_id: String) -> bool:
	return objectives_done.has(objective_id)


## Cómo va un objetivo: {"met": bool, "progress": String} (progress = «2 / 5» en los que
## cuentan algo, o "").
func get_objective_progress(objective: Dictionary) -> Dictionary:
	var condition: Dictionary = objective.get("condition", {})
	var count: int = int(condition.get("count", 1))
	var current: int = -1
	match String(condition.get("type", "")):
		"room":
			return {"met": not OfficeState.find_room(String(condition.get("room", ""))).is_empty(), "progress": ""}
		"role":
			current = 0
			for employee: Dictionary in Staff.employees:
				if employee["role"] == String(condition.get("role", "")):
					current += 1
		"employees":
			current = Staff.employees.size()
		"accepted":
			current = Projects.accepted_count
		"delivered":
			current = Projects.delivered_count
		"teams":
			current = Staff.get_active_team_count()
		"complete_teams":
			current = get_complete_team_count()
		"stage":
			return {"met": stage >= int(condition.get("stage", 0)), "progress": ""}
		"land":
			return {"met": OfficeState.land_paid > 0, "progress": ""}
		"reputation":
			return {"met": Projects.reputation >= float(condition.get("value", 0)) - 0.0001, "progress": ""}
		"value":
			var value: int = get_value()
			var goal: int = int(condition.get("value", 0))
			return {"met": value >= goal, "progress": "%s / %s" % [MoneyFormat.format(value), MoneyFormat.format(goal)]}
	if current < 0:
		return {"met": false, "progress": ""}
	return {"met": current >= count, "progress": "%d / %d" % [mini(current, count), count] if count > 1 else ""}


## Revisa los objetivos visibles y cumple los que ya se alcanzaron (con recompensa).
func check_objectives() -> void:
	if _loading or _checking:
		return
	_checking = true
	var found: bool = true
	while found:
		found = false
		for objective: Dictionary in get_visible_objectives():
			if get_objective_progress(objective)["met"]:
				_complete(objective, true)
				found = true
				break
	_checking = false


# Marca un objetivo cumplido; con reward avisa y paga su recompensa.
func _complete(objective: Dictionary, reward: bool) -> void:
	objectives_done.append(String(objective["id"]))
	if reward:
		var parts: Array[String] = []
		var money: int = int(objective.get("money", 0))
		if money > 0:
			Economy.earn(money, String(_objectives_data().get("concept", "Objetivo cumplido")))
			parts.append(MoneyFormat.format(money))
		var stars: float = float(objective.get("reputation", 0.0))
		if stars > 0.0:
			Projects.add_reputation(stars)
			parts.append("+%s ★" % String.num(stars, 2))
		var text: String = "Objetivo cumplido: %s." % String(objective["text"])
		if not parts.is_empty():
			text += " Recompensa: %s." % " y ".join(PackedStringArray(parts))
		EventBus.notice.emit(text)
		EventBus.objective_completed.emit(String(objective["id"]))
	EventBus.objectives_changed.emit()


# Marca sin recompensa todos los objetivos que la partida ya cumple.
func _mark_met_silently() -> void:
	_mark_silently = false
	for objective: Dictionary in get_objectives():
		if not objectives_done.has(String(objective["id"])) and get_objective_progress(objective)["met"]:
			objectives_done.append(String(objective["id"]))


## Estado para guardar.
func export_state() -> Dictionary:
	return {"stage": stage, "objectives_done": objectives_done.duplicate()}


## Restaura el estado. Las partidas de antes del hito 27 calculan su etapa al cargar; las
## de antes del hito 28 marcan sin recompensa los objetivos que ya cumplen.
func import_state(state: Dictionary) -> void:
	stage = clampi(int(state.get("stage", 0)), 0, maxi(0, get_stage_count() - 1))
	objectives_done.clear()
	if state.has("objectives_done"):
		for objective_id: Variant in state["objectives_done"]:
			objectives_done.append(String(objective_id))
	else:
		_mark_silently = true
	check_stage(false)
	if not _loading and _mark_silently:
		_mark_met_silently()


func _stages() -> Array:
	return _data().get("stages", [])


func _objectives_data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OBJECTIVES_PATH))
	if parsed is Dictionary:
		return parsed
	push_error("No se pudo leer %s" % OBJECTIVES_PATH)
	return {}


# Se lee al usarlo, como data/bank.json, para que los ajustes del hito 29 se vean sin reiniciar.
func _data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAGES_PATH))
	if parsed is Dictionary:
		return parsed
	push_error("No se pudo leer %s" % STAGES_PATH)
	return {}
