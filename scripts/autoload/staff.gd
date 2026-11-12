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
# La entrevista ocupa interview_hours horas del CEO mientras está en la oficina; solo hay
# una a la vez. interview es {"candidate_id", "ends_at"} (ends_at en horas desde el inicio
# de la partida, ver _absolute_hour) o vacío.
#
# Jornada (hito 12): cada empleado tiene un horario ("schedule", el de su cargo por
# defecto) y las barras "energy", "mood" y "stress" (0–100). Todos salen a almorzar a
# la hora de almuerzo. La energía baja por cada hora de su horario y sube por cada hora
# fuera; ánimo y estrés quedan fijos hasta el hito 19. El CEO no tiene horario: llega
# solo a su hora en días hábiles y se queda hasta que el jugador lo manda a casa
# (ceo_at_work). is_expected dice quién tiene que estar en la oficina a cada hora; los
# personajes de la escena solo lo siguen.
#
# Nómina y despidos (hito 13): cada empleado gana sueldo / 30 por día. "paid_until" es
# el último día (GameClock.get_day_count) que ya tiene pagado o anotado como deuda, y
# "owed" lo que se le debe de nóminas que no alcanzaron. Los días de nómina se paga a
# todos lo ganado más lo debido, todo o nada; si no alcanza, queda como deuda, baja el
# ánimo de todos y se paga solo apenas alcance el saldo. Despedir cobra lo ganado y lo
# debido (aunque el saldo quede negativo) y baja el ánimo de los compañeros.
#
# Equipos (hito 15): un equipo es {"id", "name", "members", "schedule"}; members son ids
# de empleados y cada empleado está como mucho en un equipo. El turno del equipo
# (schedule) reemplaza el horario de su cargo para todos sus miembros; quien no está en
# ningún equipo sigue con el de su cargo. Cada turno dura teams.shift_hours horas desde
# la entrada y deja al menos teams.min_rest_days de descanso por semana. El proyecto de
# cada equipo lo guarda el contrato (Projects).
extends Node

const CONCEPT_PUBLICITY: String = "Publicidad de vacantes"
const CONCEPT_PAYROLL: String = "Nómina"
const CONCEPT_FIRING: String = "Despido"
const EMPLOYEE_PREFIX: String = "employee_"
const NO_FIRING: int = -1000
const NO_STATION_MESSAGE: String = "No hay ningún puesto de trabajo libre: hace falta un escritorio con computadora y una silla delante, dentro de un Área de trabajo que funcione."

var vacancies: Array[Dictionary] = []
var employees: Array[Dictionary] = []
var interview: Dictionary = {}
## El CEO está trabajando (en la oficina o almorzando) hasta que el jugador lo manda a casa.
var ceo_at_work: bool = true
## Día (GameClock.get_day_count) del último despido; -1000 si no hubo.
var last_firing_day: int = NO_FIRING
var teams: Array[Dictionary] = []

var _next_id: int = 1
var _next_team_id: int = 1
# Hora (como _absolute_hour) en que terminó la última entrevista; no se guarda.
var _last_interview_end: int = NO_FIRING
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.balance_changed.connect(func(_balance: int) -> void: _pay_debt_if_possible())


## Prepara el personal de una partida nueva: sin vacantes y con una semilla al azar.
func new_game() -> void:
	vacancies.clear()
	employees.clear()
	interview = {}
	ceo_at_work = true
	last_firing_day = NO_FIRING
	teams.clear()
	_next_id = 1
	_next_team_id = 1
	_last_interview_end = NO_FIRING
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
	var hours: int = int(StaffCatalog.get_hiring("interview_hours"))
	var weekday: int = GameClock.get_weekday()
	var hour: int = GameClock.get_hour()
	for offset: int in range(hours):
		if hour + offset >= GameConstants.HOURS_PER_DAY or not is_expected("ceo", weekday, hour + offset):
			return "El CEO tiene que estar en la oficina las %d horas de la entrevista, sin cruzar el almuerzo (%02d:00) ni la medianoche." % [
				hours, get_ceo_lunch_hour()]
	return ""


## Manda al CEO a casa (false) o a la oficina (true). Si se va, su entrevista se corta.
func set_ceo_at_work(value: bool) -> void:
	if value == ceo_at_work:
		return
	ceo_at_work = value
	if not value:
		interview = {}
	EventBus.presence_changed.emit()
	EventBus.staff_changed.emit()


## Indica si alguien ("ceo" o employee_key(id)) tiene que estar en la oficina en esa
## hora de ese día de la semana. Para el CEO se toma ceo_at_work tal como está ahora.
func is_expected(key: String, weekday: int, hour: int) -> bool:
	if key == "ceo":
		return ceo_at_work and hour != get_ceo_lunch_hour()
	var employee: Dictionary = get_employee_by_key(key)
	if employee.is_empty():
		return false
	var schedule: WorkSchedule = get_schedule(employee)
	return schedule.is_working(weekday, hour) and not schedule.is_lunch(weekday, hour)


## Lo mismo que is_expected, para la hora actual.
func is_expected_now(key: String) -> bool:
	return is_expected(key, GameClock.get_weekday(), GameClock.get_hour())


## Indica si alguien está fuera solo por el almuerzo (su jornada sigue después).
func is_at_lunch(key: String) -> bool:
	var hour: int = GameClock.get_hour()
	if key == "ceo":
		return ceo_at_work and hour == get_ceo_lunch_hour()
	var employee: Dictionary = get_employee_by_key(key)
	return not employee.is_empty() and get_schedule(employee).is_lunch(GameClock.get_weekday(), hour)


## Indica si el CEO produce en esa hora (contada como get_absolute_hour): está
## trabajando, no almuerza, no está en una entrevista y no se quedó dormido (desde
## sleep_hour hasta su hora de llegada).
func is_ceo_producing(at: int) -> bool:
	var hour: int = posmod(at, GameConstants.HOURS_PER_DAY)
	if not is_expected("ceo", get_weekday_at(at), hour) or is_ceo_asleep(hour):
		return false
	var hours: int = int(StaffCatalog.get_hiring("interview_hours"))
	var ends_at: int = int(interview["ends_at"]) if not interview.is_empty() else _last_interview_end
	return not (at >= ends_at - hours and at < ends_at)


## Indica si a esa hora el CEO, si sigue en la oficina, está dormido.
func is_ceo_asleep(hour: int) -> bool:
	return hour >= StaffCatalog.get_ceo_sleep_hour() or hour < StaffCatalog.get_ceo_arrival_hour()


## Hora en que almuerza el CEO: la misma distancia desde su llegada que los demás.
func get_ceo_lunch_hour() -> int:
	return posmod(StaffCatalog.get_ceo_arrival_hour() + WorkSchedule.get_lunch_offset(), GameConstants.HOURS_PER_DAY)


## Horas enteras desde ahora hasta la primera en que alguien tiene que estar en la
## oficina (contando que el CEO llega solo a su hora). -1 si nadie va a venir.
func hours_until_anyone_expected() -> int:
	var hours_per_day: int = GameConstants.HOURS_PER_DAY
	var at_work: bool = ceo_at_work
	var arrival_hour: int = StaffCatalog.get_ceo_arrival_hour()
	var arrival_days: Array[int] = StaffCatalog.get_ceo_arrival_days()
	var lunch: int = get_ceo_lunch_hour()
	var start: int = _absolute_hour()
	for offset: int in range(1, GameConstants.DAYS_PER_WEEK * hours_per_day + 2):
		var total: int = start + offset
		@warning_ignore("integer_division")
		var weekday: int = (total / hours_per_day) % GameConstants.DAYS_PER_WEEK
		var hour: int = total % hours_per_day
		if hour == arrival_hour and arrival_days.has(weekday):
			at_work = true
		if at_work and hour != lunch:
			return offset
		for employee: Dictionary in employees:
			if is_expected(employee_key(employee["id"]), weekday, hour):
				return offset
	return -1


## Lo que un empleado ganó desde su último pago, hasta hoy incluido (sin la deuda).
func get_earned(employee: Dictionary) -> int:
	var days: int = GameClock.get_day_count() - int(employee["paid_until"])
	return maxi(0, roundi(int(employee["salary"]) * days / float(GameConstants.DAYS_PER_MONTH)))


## Lo que cuesta despedir a un empleado hoy: lo ganado más lo que se le debe.
func get_firing_cost(employee: Dictionary) -> int:
	return get_earned(employee) + int(employee["owed"])


## Lo que se debe de nóminas sin pagar, sumando a todos.
func get_total_owed() -> int:
	var total: int = 0
	for employee: Dictionary in employees:
		total += int(employee["owed"])
	return total


## Despide a un empleado: cobra lo ganado y lo debido, libera su puesto y baja el
## ánimo de los demás (más si hubo otro despido hace poco). Devuelve {"ok", "message"}.
func fire(employee_id: int) -> Dictionary:
	var employee: Dictionary = get_employee(employee_id)
	if employee.is_empty():
		return {"ok": false, "message": "Ese empleado ya no está."}
	var cost: int = get_firing_cost(employee)
	# Primero deja de ser empleado: así su deuda no se cuenta en la nómina pendiente.
	employees.erase(employee)
	_leave_team(employee_id)
	Economy.charge(cost, CONCEPT_FIRING)
	var key: String = employee_key(employee_id)
	for item: Dictionary in OfficeState.furniture:
		if item["assigned_to"] == key:
			item["assigned_to"] = ""
	var today: int = GameClock.get_day_count()
	var streak: bool = today - last_firing_day <= StaffCatalog.get_payroll("fire_streak_days")
	var mood_change: int = StaffCatalog.get_payroll("fire_streak_mood" if streak else "fire_mood")
	for other: Dictionary in employees:
		_change_mood(other, mood_change)
	last_firing_day = today
	var message: String = "Despediste a %s: %s." % [employee["name"], MoneyFormat.format(cost)]
	EventBus.office_changed.emit()
	EventBus.staff_changed.emit()
	EventBus.notice.emit(message)
	return {"ok": true, "message": message}


## Horario de un empleado: el turno de su equipo o, sin equipo, el de su cargo.
func get_schedule(employee: Dictionary) -> WorkSchedule:
	var team: Dictionary = get_team_of(employee["id"])
	return WorkSchedule.from_dict(team["schedule"] if not team.is_empty() else employee["schedule"])


## Crea un equipo vacío con el turno por defecto y lo devuelve.
func create_team() -> Dictionary:
	var schedule: WorkSchedule = WorkSchedule.make_shift(int(StaffCatalog.get_teams("default_start_hour")),
		StaffCatalog.get_default_team_days())
	var members: Array[int] = []
	var team: Dictionary = {"id": _next_team_id, "name": "%s %d" % [StaffCatalog.get_teams("name_prefix"), _next_team_id],
		"members": members, "schedule": schedule.to_dict()}
	_next_team_id += 1
	teams.append(team)
	EventBus.staff_changed.emit()
	return team


## Borra un equipo; sus miembros vuelven al horario de su cargo.
func delete_team(team_id: int) -> bool:
	var team: Dictionary = get_team(team_id)
	if team.is_empty():
		return false
	teams.erase(team)
	_schedules_changed()
	return true


## Pone a un empleado en un equipo (si estaba en otro, sale de aquel).
## Devuelve {"ok", "message"}.
func add_to_team(team_id: int, employee_id: int) -> Dictionary:
	var team: Dictionary = get_team(team_id)
	var employee: Dictionary = get_employee(employee_id)
	if team.is_empty() or employee.is_empty():
		return {"ok": false, "message": "Ese equipo o ese empleado ya no está."}
	if int(get_team_of(employee_id).get("id", 0)) == team_id:
		return {"ok": false, "message": "%s ya está en %s." % [employee["name"], team["name"]]}
	_leave_team(employee_id)
	var members: Array[int] = team["members"]
	members.append(employee_id)
	_schedules_changed()
	return {"ok": true, "message": "%s entra a %s." % [employee["name"], team["name"]]}


## Saca a un empleado de su equipo: vuelve al horario de su cargo.
func remove_from_team(employee_id: int) -> bool:
	if not _leave_team(employee_id):
		return false
	_schedules_changed()
	return true


## Cambia el turno de un equipo: hora de entrada y días (con al menos un día de
## descanso). Devuelve {"ok", "message"}.
func set_team_shift(team_id: int, start_hour: int, days: Array[int]) -> Dictionary:
	var team: Dictionary = get_team(team_id)
	if team.is_empty():
		return {"ok": false, "message": "Ese equipo ya no está."}
	var problem: String = shift_problem(start_hour, days)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var schedule: WorkSchedule = WorkSchedule.make_shift(start_hour, days)
	team["schedule"] = schedule.to_dict()
	_schedules_changed()
	return {"ok": true, "message": "Turno de %s: %s." % [team["name"], schedule.describe()]}


## Por qué no vale un turno, o "" si vale.
func shift_problem(start_hour: int, days: Array[int]) -> String:
	if start_hour < 0 or start_hour >= GameConstants.HOURS_PER_DAY:
		return "La hora de entrada tiene que estar entre 0 y 23."
	var unique: Array[int] = []
	for day: int in days:
		if day < 0 or day >= GameConstants.DAYS_PER_WEEK:
			return "Ese día no existe."
		if not unique.has(day):
			unique.append(day)
	if unique.is_empty():
		return "El turno necesita al menos un día de trabajo."
	var rest_days: int = int(StaffCatalog.get_teams("min_rest_days"))
	if unique.size() > GameConstants.DAYS_PER_WEEK - rest_days:
		return "Cada empleado necesita al menos %d día de descanso por semana." % rest_days
	return ""


## Equipo con ese id, o vacío.
func get_team(team_id: int) -> Dictionary:
	for team: Dictionary in teams:
		if team["id"] == team_id:
			return team
	return {}


## Equipo de un empleado, o vacío si no está en ninguno.
func get_team_of(employee_id: int) -> Dictionary:
	for team: Dictionary in teams:
		if (team["members"] as Array).has(employee_id):
			return team
	return {}


## Equipos que tienen al menos un miembro (cada uno puede llevar un contrato).
func get_active_team_count() -> int:
	var count: int = 0
	for team: Dictionary in teams:
		if not (team["members"] as Array).is_empty():
			count += 1
	return count


## Empleados que no están en ningún equipo.
func get_employees_without_team() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for employee: Dictionary in employees:
		if get_team_of(employee["id"]).is_empty():
			result.append(employee)
	return result


# Saca a un empleado del equipo en que esté. Devuelve true si estaba en alguno.
func _leave_team(employee_id: int) -> bool:
	var team: Dictionary = get_team_of(employee_id)
	if team.is_empty():
		return false
	(team["members"] as Array).erase(employee_id)
	return true


# Cambió quién trabaja a qué hora: los personajes revisan si tienen que llegar o irse.
func _schedules_changed() -> void:
	EventBus.staff_changed.emit()
	EventBus.presence_changed.emit()


## Empleado con ese id, o vacío.
func get_employee(employee_id: int) -> Dictionary:
	for employee: Dictionary in employees:
		if employee["id"] == employee_id:
			return employee
	return {}


## Empleado con esa clave de assigned_to, o vacío.
func get_employee_by_key(key: String) -> Dictionary:
	if not key.begins_with(EMPLOYEE_PREFIX):
		return {}
	return get_employee(key.trim_prefix(EMPLOYEE_PREFIX).to_int())


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
	_update_energy()
	if not ceo_at_work and hour == StaffCatalog.get_ceo_arrival_hour() \
			and StaffCatalog.get_ceo_arrival_days().has(GameClock.get_weekday()):
		set_ceo_at_work(true)
	if not interview.is_empty() and _absolute_hour() >= int(interview["ends_at"]):
		_finish_interview()
	if ceo_at_work and hour == StaffCatalog.get_ceo_sleep_hour():
		EventBus.notice.emit("El CEO se quedó dormido en la oficina: no rinde hasta las %d:00. Mándalo a casa." % StaffCatalog.get_ceo_arrival_hour())
	if hour == int(StaffCatalog.get_hiring("arrival_hour")):
		_process_arrivals(GameClock.get_day_count())


func _on_day_changed(day: int, _month: int) -> void:
	if GameConstants.PAYROLL_DAYS.has(day):
		_run_payroll()


# Anota lo ganado por cada uno hasta hoy como deuda y trata de pagarla toda. Si no
# alcanza, la deuda queda y baja el ánimo de todos.
func _run_payroll() -> void:
	if employees.is_empty():
		return
	var today: int = GameClock.get_day_count()
	for employee: Dictionary in employees:
		employee["owed"] = int(employee["owed"]) + get_earned(employee)
		employee["paid_until"] = today
	var total: int = get_total_owed()
	if _pay_debt_if_possible():
		return
	for employee: Dictionary in employees:
		_change_mood(employee, StaffCatalog.get_payroll("unpaid_mood"))
	EventBus.staff_changed.emit()
	EventBus.notice.emit("No alcanza el dinero para la nómina: se deben %s. Se pagará apenas alcance." % MoneyFormat.format(total))


# Paga toda la deuda de nómina si alcanza el saldo. Devuelve true si pagó.
func _pay_debt_if_possible() -> bool:
	var total: int = get_total_owed()
	if total <= 0 or not Economy.can_afford(total):
		return false
	for employee: Dictionary in employees:
		employee["owed"] = 0
	Economy.spend(total, CONCEPT_PAYROLL)
	EventBus.staff_changed.emit()
	EventBus.notice.emit("Nómina pagada: %s." % MoneyFormat.format(total))
	return true


func _change_mood(employee: Dictionary, change: int) -> void:
	employee["mood"] = clampi(int(employee["mood"]) + change, 0, 100)


# La energía de cada empleado cambia según si la hora que acaba de terminar era de
# trabajo o de descanso.
func _update_energy() -> void:
	if employees.is_empty():
		return
	var ended: int = _absolute_hour() - 1
	@warning_ignore("integer_division")
	var weekday: int = (ended / GameConstants.HOURS_PER_DAY) % GameConstants.DAYS_PER_WEEK
	var hour: int = posmod(ended, GameConstants.HOURS_PER_DAY)
	var work: int = int(StaffCatalog.get_workday("energy_per_work_hour"))
	var rest: int = int(StaffCatalog.get_workday("energy_per_rest_hour"))
	for employee: Dictionary in employees:
		var change: int = work if is_expected(employee_key(employee["id"]), weekday, hour) else rest
		employee["energy"] = clampi(int(employee["energy"]) + change, 0, 100)
	EventBus.staff_changed.emit()


## Día de la semana (0 = lunes) de una hora contada como get_absolute_hour.
static func get_weekday_at(at: int) -> int:
	@warning_ignore("integer_division")
	return (at / GameConstants.HOURS_PER_DAY) % GameConstants.DAYS_PER_WEEK


## Horas enteras desde el inicio de la partida (la hora actual).
func get_absolute_hour() -> int:
	return _absolute_hour()


# Horas enteras desde el inicio de la partida.
func _absolute_hour() -> int:
	return GameClock.get_day_count() * GameConstants.HOURS_PER_DAY + GameClock.get_hour()


# La entrevista revela los valores reales y un rasgo (el primero que aún no se conoce).
func _finish_interview() -> void:
	_last_interview_end = int(interview["ends_at"])
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
	employee["schedule"] = StaffCatalog.get_role_schedule(employee["role"])
	employee["energy"] = int(StaffCatalog.get_workday("start_energy"))
	employee["mood"] = int(StaffCatalog.get_workday("start_mood"))
	employee["stress"] = int(StaffCatalog.get_workday("start_stress"))
	# Gana desde el día de su contratación (incluido).
	employee["paid_until"] = GameClock.get_day_count() - 1
	employee["owed"] = 0
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
		"interview": interview.duplicate(), "ceo_at_work": ceo_at_work, "last_firing_day": last_firing_day,
		"teams": teams.duplicate(true), "next_team_id": _next_team_id, "next_id": _next_id,
		"rng_state": str(_rng.state)}


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
		var schedule: Dictionary = saved.get("schedule", StaffCatalog.get_role_schedule(employee["role"]))
		employee["schedule"] = WorkSchedule.from_dict(schedule).to_dict()
		for bar: String in ["energy", "mood", "stress"]:
			employee[bar] = int(saved.get(bar, StaffCatalog.get_workday("start_" + bar)))
		employee["paid_until"] = int(saved.get("paid_until", employee["hired_day"] - 1))
		employee["owed"] = int(saved.get("owed", 0))
		employees.append(employee)
	var saved_interview: Dictionary = state.get("interview", {})
	interview = {}
	if saved_interview.has("candidate_id"):
		interview = {"candidate_id": int(saved_interview["candidate_id"]),
			"ends_at": int(saved_interview.get("ends_at", 0))}
	_drop_missing_interview()
	teams.clear()
	for saved: Dictionary in state.get("teams", []):
		var members: Array[int] = []
		for member: Variant in saved.get("members", []):
			var member_id: int = int(member)
			# Un empleado solo puede estar en un equipo y tiene que seguir contratado.
			if not get_employee(member_id).is_empty() and get_team_of(member_id).is_empty():
				members.append(member_id)
		var team_id: int = int(saved["id"])
		var schedule: Dictionary = saved.get("schedule", WorkSchedule.make_shift(
			int(StaffCatalog.get_teams("default_start_hour")), StaffCatalog.get_default_team_days()).to_dict())
		teams.append({"id": team_id, "name": String(saved.get("name", "%s %d" % [StaffCatalog.get_teams("name_prefix"), team_id])),
			"members": members, "schedule": WorkSchedule.from_dict(schedule).to_dict()})
	_next_team_id = int(state.get("next_team_id", 1))
	_last_interview_end = NO_FIRING
	ceo_at_work = bool(state.get("ceo_at_work", true))
	last_firing_day = int(state.get("last_firing_day", NO_FIRING))
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
