# La empresa en conjunto: valor (dinero + bienes + terreno − deuda; no se guarda, avisa con
# EventBus.company_value_changed), etapas de data/stages.json (nunca bajan), objetivos guiados de
# data/objectives.json (recompensa una sola vez) y la salida a bolsa.
extends Node

const STAGES_PATH: String = "res://data/stages.json"
const OBJECTIVES_PATH: String = "res://data/objectives.json"
## public_day de una empresa que no cotiza en bolsa.
const NOT_PUBLIC: int = -1

## Etapa actual: 0 = Emprendimiento … 4 = Corporación (índice en data/stages.json).
var stage: int = 0

## Ids de los objetivos cumplidos, en el orden en que se cumplieron.
var objectives_done: Array[String] = []

# Mientras SaveManager prepara o carga, no se revisan objetivos con el estado a medias.
var _loading: bool = false
# Partida sin objectives_done: al terminar de cargar se marcan los que ya cumple.
var _mark_silently: bool = false
# Pagar una recompensa cambia el saldo y vuelve a avisar: se evita revisar dentro de una revisión.
var _checking: bool = false
var _objectives: Dictionary = {}
## Día (GameClock.get_day_count) en que salió a bolsa, o NOT_PUBLIC; después sigue en modo libre.
var public_day: int = NOT_PUBLIC
# Ya se avisó que se puede salir a bolsa (una sola vez por partida).
var _ipo_announced: bool = false


func _ready() -> void:
	EventBus.balance_changed.connect(func(_balance: int) -> void: _notify())
	EventBus.bank_changed.connect(_notify)
	EventBus.office_changed.connect(_notify)
	EventBus.products_changed.connect(_notify)
	EventBus.day_changed.connect(func(_day: int, _month: int) -> void: check_stage())
	EventBus.stage_changed.connect(func(_stage: int) -> void: _announce_ipo())
	EventBus.staff_changed.connect(check_objectives)
	EventBus.projects_changed.connect(check_objectives)
	EventBus.office_changed.connect(check_objectives)
	EventBus.stage_changed.connect(func(_stage: int) -> void: check_objectives())
	EventBus.company_value_changed.connect(func(_value: int) -> void: check_objectives())


func new_game() -> void:
	stage = 0
	public_day = NOT_PUBLIC
	_ipo_announced = false
	objectives_done.clear()
	_mark_silently = false


## SaveManager avisa que empieza a preparar o cargar una partida…
func begin_load() -> void:
	_loading = true


## … y que terminó: marca sin recompensa los objetivos que ya cumple y revisa los demás.
func finish_load() -> void:
	_loading = false
	if _mark_silently:
		_mark_met_silently()
	EventBus.objectives_changed.emit()
	check_objectives()


# --- Valor ---

## Valor de la empresa.
func get_value() -> int:
	var total: int = 0
	for part: Dictionary in get_value_parts():
		total += int(part["amount"])
	return total


## Partes del valor, en orden: [{"label", "amount"}] (deuda y lo que falta pagar al inversionista en negativo).
func get_value_parts() -> Array[Dictionary]:
	var parts: Array[Dictionary] = [
		{"label": "Dinero", "amount": Economy.balance},
		{"label": "Muebles y computadoras (reventa)", "amount": Bank.get_assets_value()},
		{"label": "Terreno comprado", "amount": OfficeState.land_paid},
		{"label": "Productos (%d días de ingreso)" % ProductCatalog.get_value_days(), "amount": Products.get_value()},
		{"label": "Deuda con el banco", "amount": -Bank.get_seizable_debt()},
	]
	if not Bank.investor.is_empty():
		parts.append({"label": "Pendiente con el inversionista (%d meses)" % Bank.get_investor_months_left(),
			"amount": -Bank.get_investor_remaining()})
	return parts


func _notify() -> void:
	EventBus.company_value_changed.emit(get_value())
	_announce_ipo()


# --- Salir a bolsa ---

## Indica si la empresa ya cotiza en bolsa (modo libre).
func is_public() -> bool:
	return public_day != NOT_PUBLIC


## Etapa que pide salir a bolsa (índice; 4 = Corporación).
func get_ipo_stage() -> int:
	return int(_data().get("ipo", {}).get("min_stage", 4))


## Valor que hay que superar para salir a bolsa.
func get_ipo_value() -> int:
	return int(_data().get("ipo", {}).get("min_value", 5000000))


## Por qué todavía no se puede salir a bolsa ("" si se puede).
func ipo_problem() -> String:
	if is_public():
		return "La empresa ya cotiza en bolsa."
	if stage < get_ipo_stage():
		return "Para salir a bolsa la empresa tiene que ser %s." % get_stage_name(get_ipo_stage())
	var value: int = get_value()
	if value <= get_ipo_value():
		return "Para salir a bolsa el valor de la empresa tiene que pasar de %s (ahora %s)." % [
			MoneyFormat.format(get_ipo_value()), MoneyFormat.format(value)]
	return ""


## Sale a bolsa (meta final, sin dinero; sigue en modo libre) y emite EventBus.went_public. Devuelve {"ok", "message"}.
func go_public() -> Dictionary:
	var problem: String = ipo_problem()
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	public_day = GameClock.get_day_count()
	var message: String = "¡La empresa salió a bolsa! La partida sigue en modo libre."
	EventBus.send_notice(EventBus.target_menu("company"), message)
	EventBus.went_public.emit(get_ipo_stats())
	return {"ok": true, "message": message}


## Estadísticas de la pantalla de cierre.
func get_ipo_stats() -> Dictionary:
	return {"days": GameClock.get_day_count() + 1, "hired": Staff.hired_count, "employees": Staff.employees.size(),
		"delivered": Projects.delivered_count, "launched": Products.launched_count, "value": get_value(),
		"best_reputation": Projects.best_reputation}


# La primera vez que se cumple, avisa que se puede salir a bolsa.
func _announce_ipo() -> void:
	if _ipo_announced or _loading or not ipo_problem().is_empty():
		return
	_ipo_announced = true
	EventBus.send_notice(EventBus.target_menu("company"), "La empresa ya puede salir a bolsa: es la meta final. Hazlo desde Empresa.")


# --- Etapas ---

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


## Cuánto hay hoy de un requisito («employees», «delivered», «complete_teams»…).
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
		"products_launched":
			return Products.launched_count
		"active_products":
			return Products.get_active_count()
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


## Sube de etapa todo lo que se pueda (nunca baja); con notify avisa de cada etapa nueva.
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
		EventBus.send_notice(EventBus.target_menu("company"), text)


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
	if RoomCatalog.is_unlocked_by_offer(type_id) and not Projects.meeting_room_unlocked:
		return false
	return stage >= get_room_stage(type_id)


## Por qué todavía no se puede marcar un tipo de habitación (o "" si se puede).
func room_lock_reason(type_id: String) -> String:
	if is_room_unlocked(type_id):
		return ""
	if RoomCatalog.is_unlocked_by_offer(type_id) and not Projects.meeting_room_unlocked:
		return "La %s se habilita cuando llegue la primera oferta grande." % RoomCatalog.get_display_name(type_id)
	return "La %s se desbloquea en %s." % [RoomCatalog.get_display_name(type_id), get_stage_name(get_room_stage(type_id))]


# --- Objetivos ---

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


## Cómo va un objetivo: {"met", "progress"} (progress = «2 / 5» si cuenta algo, si no "").
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
		EventBus.send_notice(EventBus.target_menu("company"), text)
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
	return {"stage": stage, "objectives_done": objectives_done.duplicate(), "public_day": public_day,
		"ipo_announced": _ipo_announced}


## Restaura el estado; sin etapa la calcula al cargar y sin objetivos marca los que ya cumple.
func import_state(state: Dictionary) -> void:
	stage = clampi(int(state.get("stage", 0)), 0, maxi(0, get_stage_count() - 1))
	public_day = int(state.get("public_day", NOT_PUBLIC))
	_ipo_announced = bool(state.get("ipo_announced", false))
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


# Se lee una vez: los objetivos se revisan con cada cambio.
func _objectives_data() -> Dictionary:
	if _objectives.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OBJECTIVES_PATH))
		if not parsed is Dictionary:
			push_error("No se pudo leer %s" % OBJECTIVES_PATH)
			return {}
		_objectives = parsed
	return _objectives


# Se lee al usarlo para ver los ajustes sin reiniciar.
func _data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAGES_PATH))
	if parsed is Dictionary:
		return parsed
	push_error("No se pudo leer %s" % STAGES_PATH)
	return {}
