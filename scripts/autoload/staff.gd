# Personal (diseño, 5.2): vacantes abiertas, los candidatos que llegan a cada una, la
# entrevista y la contratación, y los empleados contratados.
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
# y traits los rasgos (ocultos). Además interviewed (si ya lo entrevistó el CEO),
# known_traits (los rasgos que se conocen) y counter_offer (el sueldo de su contraoferta,
# 0 si no hizo ninguna).
#
# Contratar (hito 11) exige un puesto de trabajo libre (Workstations): el empleado queda
# asignado a su silla con assigned_to = employee_key(id) y la vacante se cierra. Un
# empleado guarda los datos del candidato más "salary" (lo acordado) y "hired_day".
#
# La entrevista ocupa interview_hours horas del CEO dentro de su horario; solo hay una a
# la vez. interview es {"candidate_id", "ends_at"} (ends_at en horas desde el inicio de
# la partida, ver _absolute_hour) o vacío.
extends Node

const CONCEPT_PUBLICITY: String = "Publicidad de vacantes"
const EMPLOYEE_PREFIX: String = "employee_"
const NO_STATION_MESSAGE: String = "No hay ningún puesto de trabajo libre: hace falta un escritorio con computadora y una silla delante, dentro de un Área de trabajo que funcione."

var vacancies: Array[Dictionary] = []
var employees: Array[Dictionary] = []
var interview: Dictionary = {}

var _next_id: int = 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.hour_changed.connect(_on_hour_changed)


## Prepara el personal de una partida nueva: sin vacantes y con una semilla al azar.
func new_game() -> void:
	vacancies.clear()
	employees.clear()
	interview = {}
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
			_drop_missing_interview()
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
				_drop_missing_interview()
				EventBus.staff_changed.emit()
				return true
	return false


## Ofrece un sueldo a un candidato. Si iguala o supera lo que pide, acepta y queda
## contratado; desde counter_offer_ratio de lo que pide, hace una contraoferta (pide lo
## suyo, ver accept_counter_offer); por debajo rechaza y se va. Sin puesto de trabajo
## libre no se puede ofrecer. Devuelve {"ok": bool, "result": String, "message": String}
## con result "hired", "counter", "rejected" o "" si no se pudo ofrecer.
func make_offer(candidate_id: int, offer: int) -> Dictionary:
	var candidate: Dictionary = get_candidate(candidate_id)
	if candidate.is_empty():
		return {"ok": false, "result": "", "message": "Ese candidato ya no está."}
	if get_free_workstations().is_empty():
		return {"ok": false, "result": "", "message": NO_STATION_MESSAGE}
	var asked: int = candidate["asked_salary"]
	if offer >= asked:
		return _hire(candidate, offer)
	if offer >= asked * float(StaffCatalog.get_hiring("counter_offer_ratio")):
		candidate["counter_offer"] = asked
		EventBus.staff_changed.emit()
		return {"ok": true, "result": "counter", "message": "%s no acepta %s, pero aceptaría %s al mes." % [
			candidate["name"], MoneyFormat.format(offer), MoneyFormat.format(asked)]}
	var person: String = candidate["name"]
	discard_candidate(candidate_id)
	return {"ok": true, "result": "rejected", "message": "%s rechaza %s y se va." % [
		person, MoneyFormat.format(offer)]}


## Acepta la contraoferta de un candidato: lo contrata por el sueldo que pidió.
func accept_counter_offer(candidate_id: int) -> Dictionary:
	var candidate: Dictionary = get_candidate(candidate_id)
	if candidate.is_empty() or int(candidate.get("counter_offer", 0)) <= 0:
		return {"ok": false, "result": "", "message": "No hay contraoferta que aceptar."}
	return make_offer(candidate_id, candidate["counter_offer"])


## Empieza la entrevista de un candidato con el CEO. Devuelve {"ok", "message"}.
func start_interview(candidate_id: int) -> Dictionary:
	var problem: String = interview_problem(candidate_id)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var hours: int = int(StaffCatalog.get_hiring("interview_hours"))
	interview = {"candidate_id": candidate_id, "ends_at": _absolute_hour() + hours}
	EventBus.staff_changed.emit()
	return {"ok": true, "message": "El CEO entrevista a %s hasta las %02d:00." % [
		get_candidate(candidate_id)["name"], (GameClock.get_hour() + hours) % GameConstants.HOURS_PER_DAY]}


## Por qué no se puede entrevistar ahora a un candidato ("" si se puede).
func interview_problem(candidate_id: int) -> String:
	var candidate: Dictionary = get_candidate(candidate_id)
	if candidate.is_empty():
		return "Ese candidato ya no está."
	if bool(candidate["interviewed"]):
		return "Ya lo entrevistaste."
	if not interview.is_empty():
		return "El CEO ya está en una entrevista."
	var schedule: WorkSchedule = WorkSchedule.from_dict(OfficeState.ceo_schedule)
	var hours: int = int(StaffCatalog.get_hiring("interview_hours"))
	var weekday: int = GameClock.get_weekday()
	var hour: int = GameClock.get_hour()
	if not schedule.is_working(weekday, hour) or not schedule.is_working(weekday, hour + hours - 1):
		return "El CEO entrevista dentro de su horario (%02d:00–%02d:00) y la entrevista dura %d horas." % [
			schedule.start_hour, schedule.end_hour, hours]
	return ""


## Candidato que está en entrevista ahora, o vacío.
func get_interviewed_now() -> Dictionary:
	return {} if interview.is_empty() else get_candidate(interview["candidate_id"])


## Puestos de trabajo que nadie ocupa (ver Workstations.find_all).
func get_free_workstations() -> Array[Dictionary]:
	return Workstations.find_free(OfficeState.furniture, OfficeState.rooms)


## Clave con la que un empleado ocupa su silla (assigned_to).
static func employee_key(employee_id: int) -> String:
	return "%s%d" % [EMPLOYEE_PREFIX, employee_id]


## Nombre de quien tiene esa clave de assigned_to ("ceo" o un empleado).
func get_person_name(key: String) -> String:
	if key == "ceo":
		return "el CEO"
	for employee: Dictionary in employees:
		if employee_key(employee["id"]) == key:
			return employee["name"]
	return "otra persona"


## Indica si el puesto de un empleado sigue funcionando (por ejemplo, si nadie deshizo
## su Área de trabajo).
func has_working_station(employee: Dictionary) -> bool:
	return Workstations.is_working_station(OfficeState.furniture, OfficeState.rooms, employee_key(employee["id"]))


## Candidato con ese id en cualquier vacante, o vacío.
func get_candidate(candidate_id: int) -> Dictionary:
	for vacancy: Dictionary in vacancies:
		for candidate: Dictionary in vacancy["candidates"]:
			if candidate["id"] == candidate_id:
				return candidate
	return {}


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


## Habilidades de un candidato o empleado: en rangos ("Programación 40–60 · …") o, si
## ya se entrevistó, los valores reales ("Programación 47 · …").
static func describe_skills(candidate: Dictionary) -> String:
	var parts: Array[String] = []
	var width: int = StaffCatalog.get_skill_range_width()
	for skill: String in StaffCatalog.get_skill_ids():
		if bool(candidate.get("interviewed", false)):
			parts.append("%s %d" % [StaffCatalog.get_skill_name(skill), int(candidate["skills"][skill])])
		else:
			var low: int = int(candidate["skill_low"][skill])
			parts.append("%s %d–%d" % [StaffCatalog.get_skill_name(skill), low, low + width])
	return " · ".join(parts)


## Rasgos que se conocen: "Rasgos: Perfeccionista" o "" si no se conoce ninguno.
static func describe_known_traits(person: Dictionary) -> String:
	var names: Array[String] = []
	for trait_id: String in person.get("known_traits", []):
		names.append(StaffCatalog.get_trait_name(trait_id))
	return "" if names.is_empty() else "Rasgos: %s" % ", ".join(names)


## "Programador Junior · $1,200 al mes" para un empleado.
static func describe_employee(employee: Dictionary) -> String:
	return "%s %s · %s al mes" % [StaffCatalog.get_role_name(employee["role"]),
		StaffCatalog.get_level_name(employee["level"]), MoneyFormat.format(employee["salary"])]


func _on_hour_changed(hour: int) -> void:
	if not interview.is_empty() and _absolute_hour() >= int(interview["ends_at"]):
		_finish_interview()
	if hour == int(StaffCatalog.get_hiring("arrival_hour")):
		_process_arrivals(GameClock.get_day_count())


# Horas enteras desde el inicio de la partida.
func _absolute_hour() -> int:
	return GameClock.get_day_count() * GameConstants.HOURS_PER_DAY + GameClock.get_hour()


# La entrevista revela los valores reales y un rasgo (el primero que aún no se conoce).
func _finish_interview() -> void:
	var candidate: Dictionary = get_interviewed_now()
	interview = {}
	if candidate.is_empty():
		return
	candidate["interviewed"] = true
	var known: Array[String] = candidate["known_traits"]
	for trait_id: String in candidate["traits"]:
		if not known.has(trait_id):
			known.append(trait_id)
			break
	EventBus.staff_changed.emit()


# Si el candidato de la entrevista ya no está (se fue, lo descartaron o se cerró su
# vacante), la entrevista termina sin más.
func _drop_missing_interview() -> void:
	if not interview.is_empty() and get_interviewed_now().is_empty():
		interview = {}


# Contrata a un candidato por un sueldo: ocupa el primer puesto libre, deja de ser
# candidato y su vacante se cierra (los demás candidatos se van).
func _hire(candidate: Dictionary, salary: int) -> Dictionary:
	var station: Dictionary = get_free_workstations()[0]
	var employee: Dictionary = candidate.duplicate(true)
	employee.erase("arrived_day")
	employee.erase("counter_offer")
	employee["salary"] = salary
	employee["hired_day"] = GameClock.get_day_count()
	employees.append(employee)
	OfficeState.furniture[station["chair"]]["assigned_to"] = employee_key(employee["id"])
	for index: int in range(vacancies.size()):
		if vacancies[index]["candidates"].has(candidate):
			vacancies.remove_at(index)
			break
	_drop_missing_interview()
	EventBus.office_changed.emit()
	EventBus.staff_changed.emit()
	return {"ok": true, "result": "hired", "message": "%s aceptó: entra como %s." % [
		employee["name"], describe_employee(employee)]}


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
	_drop_missing_interview()
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
		"interviewed": false, "known_traits": [] as Array[String], "counter_offer": 0,
	}


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


## Devuelve el estado del personal para guardarlo. El estado del azar va como texto,
## porque JSON guarda los números como decimales y perdería precisión.
func export_state() -> Dictionary:
	return {"vacancies": vacancies.duplicate(true), "employees": employees.duplicate(true),
		"interview": interview.duplicate(), "next_id": _next_id, "rng_state": str(_rng.state)}


## Restaura el estado del personal desde una partida guardada. Sin datos (partidas de
## la fase 1 o del hito 10) queda sin vacantes, sin empleados o sin entrevista.
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
	employees.clear()
	for saved: Dictionary in state.get("employees", []):
		var employee: Dictionary = _import_person(saved)
		employee["salary"] = int(saved.get("salary", employee["asked_salary"]))
		employee["hired_day"] = int(saved.get("hired_day", 0))
		employees.append(employee)
	var saved_interview: Dictionary = state.get("interview", {})
	interview = {}
	if saved_interview.has("candidate_id"):
		interview = {"candidate_id": int(saved_interview["candidate_id"]),
			"ends_at": int(saved_interview.get("ends_at", 0))}
	_drop_missing_interview()
	_next_id = int(state.get("next_id", 1))
	var rng_state: String = String(state.get("rng_state", ""))
	if rng_state.is_valid_int():
		_rng.state = rng_state.to_int()
	else:
		_rng.randomize()
	EventBus.staff_changed.emit()


func _import_candidate(saved: Dictionary) -> Dictionary:
	var candidate: Dictionary = _import_person(saved)
	candidate["arrived_day"] = int(saved.get("arrived_day", 0))
	candidate["counter_offer"] = int(saved.get("counter_offer", 0))
	return candidate


# Lo que comparten candidatos y empleados.
func _import_person(saved: Dictionary) -> Dictionary:
	var skills: Dictionary = {}
	var skill_low: Dictionary = {}
	for skill: String in StaffCatalog.get_skill_ids():
		skills[skill] = int(saved["skills"].get(skill, 1))
		skill_low[skill] = int(saved["skill_low"].get(skill, 1))
	var traits: Array[String] = []
	traits.assign(saved.get("traits", []))
	var known_traits: Array[String] = []
	known_traits.assign(saved.get("known_traits", []))
	return {
		"id": int(saved["id"]), "name": String(saved["name"]), "sex": String(saved["sex"]),
		"age": int(saved["age"]), "role": String(saved["role"]), "level": String(saved["level"]),
		"asked_salary": int(saved["asked_salary"]), "skills": skills, "skill_low": skill_low,
		"traits": traits, "interviewed": bool(saved.get("interviewed", false)), "known_traits": known_traits,
	}
