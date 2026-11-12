# Personal (diseño, 5.2): vacantes abiertas y los candidatos que llegan a cada una.
# Contratar llega en el hito 11; aquí solo se publican vacantes, llegan candidatos y
# se descartan o caducan.
#
# Cada día, a la hora de llegada (data/staff.json, hiring.arrival_hour), primero se van
# los candidatos que ya esperaron sus días y después llegan los nuevos de cada vacante.
# Todo el azar sale de _rng, cuyo estado se guarda con la partida: con la misma semilla
# llegan siempre los mismos candidatos.
#
# Una vacante es {"id", "role", "level", "salary", "publicity_until", "candidates"}.
# publicity_until es el primer día (contado con GameClock.get_day_count) en que la
# publicidad ya no cuenta; 0 si no tiene. Un candidato es {"id", "name", "sex", "age",
# "role", "level", "asked_salary", "skills", "skill_low", "traits", "arrived_day"}:
# skills son los valores reales (ocultos), skill_low el inicio del rango que se muestra
# y traits los rasgos (ocultos hasta la entrevista).
extends Node

const CONCEPT_PUBLICITY: String = "Publicidad de vacantes"

var vacancies: Array[Dictionary] = []

var _next_id: int = 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.hour_changed.connect(_on_hour_changed)


## Prepara el personal de una partida nueva: sin vacantes y con una semilla al azar.
func new_game() -> void:
	vacancies.clear()
	_next_id = 1
	_rng.randomize()
	EventBus.staff_changed.emit()


## Fija la semilla del azar (las pruebas la usan para tener resultados repetibles).
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Publica una vacante. Con publicidad cobra su precio y falla si no alcanza el dinero.
## Devuelve {"ok": bool, "message": String, "id": int}.
func open_vacancy(role: String, level: String, salary: int, publicity: bool) -> Dictionary:
	if not StaffCatalog.get_role_ids().has(role) or not StaffCatalog.get_level_ids().has(level):
		return {"ok": false, "message": "Ese cargo no existe.", "id": 0}
	if salary <= 0:
		return {"ok": false, "message": "El sueldo tiene que ser mayor que cero.", "id": 0}
	var publicity_until: int = 0
	if publicity:
		var cost: int = int(StaffCatalog.get_hiring("publicity_cost"))
		if not Economy.spend(cost, CONCEPT_PUBLICITY):
			return {"ok": false, "message": "No alcanza el dinero para la publicidad (%s)." % MoneyFormat.format(cost), "id": 0}
		publicity_until = next_arrival_day() + int(StaffCatalog.get_hiring("publicity_days"))
	var vacancy: Dictionary = {
		"id": _take_id(), "role": role, "level": level, "salary": salary,
		"publicity_until": publicity_until, "candidates": [] as Array[Dictionary],
	}
	vacancies.append(vacancy)
	EventBus.staff_changed.emit()
	var title: String = describe_vacancy(vacancy)
	return {"ok": true, "message": "Vacante publicada: %s. Los candidatos llegan a las %02d:00." % [
		title, int(StaffCatalog.get_hiring("arrival_hour"))], "id": vacancy["id"]}


## Cierra una vacante; sus candidatos se van. Devuelve false si no existe.
func close_vacancy(vacancy_id: int) -> bool:
	for index: int in range(vacancies.size()):
		if vacancies[index]["id"] == vacancy_id:
			vacancies.remove_at(index)
			EventBus.staff_changed.emit()
			return true
	return false


## Descarta a un candidato. Devuelve false si no existe.
func discard_candidate(candidate_id: int) -> bool:
	for vacancy: Dictionary in vacancies:
		var candidates: Array[Dictionary] = vacancy["candidates"]
		for index: int in range(candidates.size()):
			if candidates[index]["id"] == candidate_id:
				candidates.remove_at(index)
				EventBus.staff_changed.emit()
				return true
	return false


## Vacante con ese id, o vacío.
func get_vacancy(vacancy_id: int) -> Dictionary:
	for vacancy: Dictionary in vacancies:
		if vacancy["id"] == vacancy_id:
			return vacancy
	return {}


## Candidatos esperando en todas las vacantes.
func get_waiting_count() -> int:
	var count: int = 0
	for vacancy: Dictionary in vacancies:
		count += vacancy["candidates"].size()
	return count


## Primer día (GameClock.get_day_count) en que pueden llegar candidatos: hoy si aún no
## es la hora de llegada, si no mañana.
func next_arrival_day() -> int:
	var today: int = GameClock.get_day_count()
	return today if GameClock.get_hour() < int(StaffCatalog.get_hiring("arrival_hour")) else today + 1


## Días de publicidad que le quedan a una vacante (0 si no tiene).
func publicity_days_left(vacancy: Dictionary) -> int:
	return maxi(int(vacancy["publicity_until"]) - next_arrival_day(), 0)


## Días que le quedan a un candidato antes de irse con otra empresa (se va a la hora
## de llegada de ese día): 0 = hoy, 1 = mañana.
func candidate_days_left(candidate: Dictionary) -> int:
	var leaves_on: int = int(candidate["arrived_day"]) + int(StaffCatalog.get_hiring("candidate_days"))
	return maxi(leaves_on - GameClock.get_day_count(), 0)


## "Programador Junior · $1,200 al mes".
static func describe_vacancy(vacancy: Dictionary) -> String:
	return "%s %s · %s al mes" % [StaffCatalog.get_role_name(vacancy["role"]),
		StaffCatalog.get_level_name(vacancy["level"]), MoneyFormat.format(vacancy["salary"])]


## Habilidades de un candidato como se ven al contratar: "Programación 40–60 · …".
static func describe_skills(candidate: Dictionary) -> String:
	var parts: Array[String] = []
	var width: int = StaffCatalog.get_skill_range_width()
	for skill: String in StaffCatalog.get_skill_ids():
		var low: int = int(candidate["skill_low"][skill])
		parts.append("%s %d–%d" % [StaffCatalog.get_skill_name(skill), low, low + width])
	return " · ".join(parts)


func _on_hour_changed(hour: int) -> void:
	if hour == int(StaffCatalog.get_hiring("arrival_hour")):
		_process_arrivals(GameClock.get_day_count())


# Primero se van los que ya esperaron sus días; después llegan los nuevos.
func _process_arrivals(today: int) -> void:
	var waiting_days: int = int(StaffCatalog.get_hiring("candidate_days"))
	var max_waiting: int = int(StaffCatalog.get_hiring("max_waiting"))
	for vacancy: Dictionary in vacancies:
		var staying: Array[Dictionary] = []
		for candidate: Dictionary in vacancy["candidates"]:
			if today < int(candidate["arrived_day"]) + waiting_days:
				staying.append(candidate)
		vacancy["candidates"] = staying
		var arriving: int = _roll_arrivals(vacancy, today)
		for i: int in range(arriving):
			if staying.size() >= max_waiting:
				break
			staying.append(_make_candidate(vacancy, today))
	EventBus.staff_changed.emit()


# Cuántos candidatos llegan hoy a una vacante.
func _roll_arrivals(vacancy: Dictionary, today: int) -> int:
	var key: String = "arrivals_with_publicity" if today < int(vacancy["publicity_until"]) else "arrivals"
	var arrivals: Vector2i = StaffCatalog.get_hiring_range(key)
	var count: int = _rng.randi_range(arrivals.x, arrivals.y)
	# Un sueldo bastante mejor que el de la tabla atrae a veces a uno más.
	var table: int = StaffCatalog.get_salary(vacancy["role"], vacancy["level"])
	if vacancy["salary"] >= table * float(StaffCatalog.get_hiring("high_offer_ratio")) \
			and _rng.randf() < float(StaffCatalog.get_hiring("high_offer_extra_chance")):
		count += 1
	return count


func _make_candidate(vacancy: Dictionary, today: int) -> Dictionary:
	var role: String = vacancy["role"]
	var level: String = vacancy["level"]
	var sex: String = "female" if _rng.randf() < 0.5 else "male"
	var first_names: Array[String] = StaffCatalog.get_first_names(sex)
	var last_names: Array[String] = StaffCatalog.get_last_names()
	var full_name: String = "%s %s" % [first_names[_rng.randi_range(0, first_names.size() - 1)],
		last_names[_rng.randi_range(0, last_names.size() - 1)]]
	var ages: Vector2i = StaffCatalog.get_age_range(level)
	var main_skill: String = StaffCatalog.get_main_skill(role)
	var main_range: Vector2i = StaffCatalog.get_main_skill_range(level)
	var other_range: Vector2i = StaffCatalog.get_other_skill_range()
	var width: int = StaffCatalog.get_skill_range_width()
	var skills: Dictionary = {}
	var skill_low: Dictionary = {}
	for skill: String in StaffCatalog.get_skill_ids():
		var skill_range: Vector2i = main_range if skill == main_skill else other_range
		var value: int = _rng.randi_range(skill_range.x, skill_range.y)
		skills[skill] = value
		# El rango que se ve contiene el valor real en un lugar al azar.
		skill_low[skill] = clampi(value - _rng.randi_range(0, width), maxi(1, value - width), mini(value, 100 - width))
	var ratio_values: Array = StaffCatalog.get_hiring("asked_salary_ratio")
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	var asked: float = StaffCatalog.get_salary(role, level) * _rng.randf_range(float(ratio_values[0]), float(ratio_values[1]))
	var traits: Array[String] = []
	var trait_pool: Array[String] = StaffCatalog.get_trait_ids()
	var trait_count: Vector2i = StaffCatalog.get_traits_per_person()
	for i: int in range(_rng.randi_range(trait_count.x, trait_count.y)):
		traits.append(trait_pool.pop_at(_rng.randi_range(0, trait_pool.size() - 1)))
	return {
		"id": _take_id(), "name": full_name, "sex": sex, "age": _rng.randi_range(ages.x, ages.y),
		"role": role, "level": level, "asked_salary": maxi(step, roundi(asked / step) * step),
		"skills": skills, "skill_low": skill_low, "traits": traits, "arrived_day": today,
	}


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


## Devuelve el estado del personal para guardarlo. El estado del azar va como texto,
## porque JSON guarda los números como decimales y perdería precisión.
func export_state() -> Dictionary:
	return {"vacancies": vacancies.duplicate(true), "next_id": _next_id, "rng_state": str(_rng.state)}


## Restaura el estado del personal desde una partida guardada. Sin datos (partidas de
## la fase 1) queda sin vacantes.
func import_state(state: Dictionary) -> void:
	vacancies.clear()
	for saved: Dictionary in state.get("vacancies", []):
		var candidates: Array[Dictionary] = []
		for candidate: Dictionary in saved.get("candidates", []):
			candidates.append(_import_candidate(candidate))
		vacancies.append({
			"id": int(saved["id"]), "role": String(saved["role"]), "level": String(saved["level"]),
			"salary": int(saved["salary"]), "publicity_until": int(saved.get("publicity_until", 0)),
			"candidates": candidates,
		})
	_next_id = int(state.get("next_id", 1))
	var rng_state: String = String(state.get("rng_state", ""))
	if rng_state.is_valid_int():
		_rng.state = rng_state.to_int()
	else:
		_rng.randomize()
	EventBus.staff_changed.emit()


func _import_candidate(saved: Dictionary) -> Dictionary:
	var skills: Dictionary = {}
	var skill_low: Dictionary = {}
	for skill: String in StaffCatalog.get_skill_ids():
		skills[skill] = int(saved["skills"].get(skill, 1))
		skill_low[skill] = int(saved["skill_low"].get(skill, 1))
	var traits: Array[String] = []
	traits.assign(saved.get("traits", []))
	return {
		"id": int(saved["id"]), "name": String(saved["name"]), "sex": String(saved["sex"]),
		"age": int(saved["age"]), "role": String(saved["role"]), "level": String(saved["level"]),
		"asked_salary": int(saved["asked_salary"]), "skills": skills, "skill_low": skill_low,
		"traits": traits, "arrived_day": int(saved["arrived_day"]),
	}
