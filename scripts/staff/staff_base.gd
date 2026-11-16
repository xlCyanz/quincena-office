# Personal, capa 1 de 7: estado, claves, horarios, presencia y consultas básicas.
# Staff (scripts/autoload/staff.gd) hereda de las capas en orden; cada una solo llama a las de abajo.
extends Node

const CONCEPT_PUBLICITY: String = "Publicidad de vacantes"
const CONCEPT_PAYROLL: String = "Nómina"
## template_id de un equipo con turno propio.
const NO_TEMPLATE: int = 0
# Clave de _get_team_map que ningún empleado usa (los ids empiezan en 1).
const NO_TEAM_KEY: int = -1
const NO_COFFEE_OUT: int = -1
const CONCEPT_REPAIR: String = "Reparación del baño"
const CONCEPT_VENDING: String = "Máquina expendedora"
## bathroom_short_day si nunca faltaron inodoros.
const NO_SHORT_DAY: int = -1000
## Habitación cuya cafetera necesitan los adictos al café.
const BREAK_ROOM: String = "break_room"
## Sin llegadas tarde ni ausencias (ver missing_from).
const NOT_MISSING: int = -1
## Estados de una hora en la agenda.
const AGENDA_OFF: String = "off"
const AGENDA_WORK: String = "work"
const AGENDA_LUNCH: String = "lunch"
const AGENDA_GAP: String = "gap"
const CONCEPT_OVERTIME: String = "Horas extra"
const CONCEPT_NIGHT: String = "Recargo nocturno"
## Cargo que cuenta contratos aceptados en lugar de trabajados para ascender.
const SALES_ROLE: String = "salesperson"
const CONCEPT_FIRING: String = "Despido"
const CONCEPT_RESIGNATION: String = "Liquidación por renuncia"
const CONCEPT_POACHED: String = "Liquidación por irse a otra empresa"
## quit_day de quien no avisó que renuncia.
const NO_QUIT: int = -1
const EMPLOYEE_PREFIX: String = "employee_"
## Cuántos ambientes de habitación se guardan antes de vaciar la caché.
const AMBIANCE_CACHE_SIZE: int = 64
## Cuántos horarios se guardan antes de vaciar la caché (ver _cached_schedule).
const SCHEDULE_CACHE_SIZE: int = 256
const NO_FIRING: int = -1000
const NO_STATION_MESSAGE: String = "No hay ningún puesto de trabajo libre: hace falta un escritorio con computadora y una silla delante, dentro de un Área de trabajo que funcione."
const NO_OFFICE_MESSAGE: String = "No hay ninguna Oficina única libre: hace falta una que funcione, con un escritorio y una silla delante."
const NO_RECEPTION_MESSAGE: String = "No hay ningún mostrador libre: hace falta una Recepción que funcione, con un mostrador y una silla delante."
## Cargo que atiende a los clientes que visitan la Recepción.
const RECEPTIONIST_ROLE: String = "receptionist"
const NO_CLOSET_MESSAGE: String = "No hay ningún armario de limpieza libre: hace falta un Cuarto de limpieza que funcione, con un armario."

var vacancies: Array[Dictionary] = []
var employees: Array[Dictionary] = []
var interview: Dictionary = {}
## Entrevistas citadas: {"candidate_id", "by", "at"} con at en minutos absolutos, ordenadas.
## A esa hora empieza si quien entrevista está en la oficina.
var appointments: Array[Dictionary] = []
## starts_at y ends_at de una entrevista llamada cuyo candidato todavía camina a la silla.
const INTERVIEW_NOT_STARTED: int = -1
## El CEO está trabajando (en la oficina o almorzando) hasta que el jugador lo manda a casa.
var ceo_at_work: bool = true
## Día (GameClock.get_day_count) del último despido; -1000 si no hubo.
var last_firing_day: int = NO_FIRING
var teams: Array[Dictionary] = []
## Plantillas de turno: {"id", "name", "schedule"}.
var shift_templates: Array[Dictionary] = []
## Empleados contratados en toda la partida (para la pantalla de fin).
var hired_count: int = 0
## La nómina de hoy espera la respuesta al préstamo de emergencia: aún no baja el ánimo
## ni cuenta como atraso.
var payroll_held: bool = false
## Día en que se acabó el café (evento): los adictos rinden como sin cafetera.
var coffee_out_day: int = NO_COFFEE_OUT
## Inodoros dañados por el evento «Baño dañado»: no cuentan hasta repararlos.
var broken_toilets: int = 0
## Último día en que faltaron inodoros alguna hora.
var bathroom_short_day: int = NO_SHORT_DAY
## Solo para pruebas: false hace como si siempre alcanzaran los inodoros. No se guarda.
var bathrooms_enabled: bool = true
## Solo para pruebas: false quita la primera tanda, la calidad por sueldo y ambiente y el
## candidato extra del premio. No se guarda.
var company_hiring_enabled: bool = true
## Solo para pruebas: false hace que todos entren a la hora en punto. No se guarda.
var arrival_spread_enabled: bool = true
## Hasta qué día (sin incluirlo) el «Premio de la industria» suma un candidato por vacante.
var award_until: int = 0
## Pausas: hora absoluta → claves de quienes descansan (la actual y la anterior, que se
## cobra al terminar).
var breaks: Dictionary[int, Array] = {}
## Quiénes estuvieron hoy en la oficina (máquina expendedora).
var present_today: Dictionary[String, bool] = {}

var _next_id: int = 1
var _next_team_id: int = 1
var _next_template_id: int = 1
# Entrevistas del CEO ya terminadas: (inicio, fin) en minutos absolutos, las últimas.
var _interview_spans: Array[Vector2i] = []
var _rng := RandomNumberGenerator.new()
# Ambiente por habitación y muebles (ver _ambiance_detail).
var _ambiance_cache: Dictionary[int, Dictionary] = {}
# Puestos, escritorios y hash de muebles buscados una vez mientras _update_morale recorre
# a todos; vacío el resto del tiempo.
var _seat_lookup_cache: Dictionary = {}
# Horarios ya leídos por el hash de su diccionario (ver _cached_schedule).
var _schedule_cache: Dictionary[int, WorkSchedule] = {}
# id → posición en employees; se rehace si no coincide.
var _employee_index: Dictionary[int, int] = {}
# Presentes y quienes almuerzan dentro por hora absoluta. Solo se usan con
# GameClock.in_hour_tick; se borran al cambiar la hora, el personal o la oficina.
var _present_cache: Dictionary[int, Dictionary] = {}
var _lunch_cache: Dictionary[int, Dictionary] = {}

# Efectos sumados de una lista de rasgos, por lista (se piden por persona cada hora).
static var _trait_summaries: Dictionary[int, Dictionary] = {}

## Efectos que se multiplican como (1 + valor) y los que van tal cual; de los demás cuenta el
## más fuerte y de los booleanos, cualquiera.
const PLUS_ONE_EFFECTS: Array[String] = ["points", "night_points", "day_points", "no_coffee_points"]

const TIMES_EFFECTS: Array[String] = ["bug_factor", "find_factor", "quit_days_factor"]


func _clear_hour_caches() -> void:
	_present_cache.clear()
	_lunch_cache.clear()


## Fija la semilla del azar (pruebas).
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Minutos desde el inicio de la partida.
func get_absolute_minute() -> int:
	return _absolute_hour() * 60 + GameClock.get_minute()


## «09:30» para un minuto absoluto.
static func format_clock_minute(minute: int) -> String:
	@warning_ignore("integer_division")
	return "%02d:%02d" % [posmod(minute / 60, GameConstants.HOURS_PER_DAY), posmod(minute, 60)]


## Indica si alguien ("ceo" o clave) debe estar en la oficina a esa hora. Para el CEO usa
## ceo_at_work tal como está.
func is_expected(key: String, weekday: int, hour: int) -> bool:
	if key == "ceo":
		return ceo_at_work and hour != get_ceo_lunch_hour()
	var employee: Dictionary = get_employee_by_key(key)
	if employee.is_empty():
		return false
	return _is_working_at(employee, weekday, hour)


# is_expected para un empleado ya a mano (y su equipo, de _get_team_map).
func _is_working_at(employee: Dictionary, weekday: int, hour: int, team_map: Dictionary[int, Dictionary] = {}) -> bool:
	var schedule: WorkSchedule = _cached_schedule(employee) if team_map.is_empty() \
		else _cached_schedule_in(employee, team_map.get(int(employee["id"]), {}))
	return schedule.is_working(weekday, hour) and not schedule.is_lunch(weekday, hour) and not is_missing(employee, weekday, hour)


## Indica si alguien falta a esa hora por tardanza o ausencia (la hora absoluta más cercana).
func is_missing(employee: Dictionary, weekday: int, hour: int) -> bool:
	var from: int = int(employee.get("missing_from", NOT_MISSING))
	if from == NOT_MISSING:
		return false
	var at: int = _nearest_absolute(weekday, hour)
	return at >= from and at < int(employee.get("missing_until", NOT_MISSING))


# La hora absoluta más cercana a ahora que cae en ese día de la semana y esa hora.
func _nearest_absolute(weekday: int, hour: int) -> int:
	var week: int = GameConstants.DAYS_PER_WEEK * GameConstants.HOURS_PER_DAY
	var now: int = _absolute_hour()
	var target: int = weekday * GameConstants.HOURS_PER_DAY + hour
	@warning_ignore("integer_division")
	var difference: int = posmod(target - posmod(now, week) + week / 2, week) - week / 2
	return now + difference


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


## Indica si a esa hora el CEO estaría dormido.
func is_ceo_asleep(hour: int) -> bool:
	return hour >= StaffCatalog.get_ceo_sleep_hour() or hour < StaffCatalog.get_ceo_arrival_hour()


## Hora de almuerzo del CEO: a la misma distancia de su llegada que los demás.
func get_ceo_lunch_hour() -> int:
	return posmod(StaffCatalog.get_ceo_arrival_hour() + WorkSchedule.get_lunch_offset(), GameConstants.HOURS_PER_DAY)


## Indica si un empleado es ejecutivo.
func is_executive(employee: Dictionary) -> bool:
	return employee.get("role", "") == StaffCatalog.get_executive_role()


## Sueldo de su nivel en la tabla, con el que se compara el suyo.
func get_market_salary(employee: Dictionary) -> int:
	return StaffCatalog.get_salary(employee["role"], employee["level"])


## Indica si alguien tiene un rasgo (conocido o no: todos hacen efecto).
static func has_trait(person: Dictionary, trait_id: String) -> bool:
	return (person.get("traits", []) as Array).has(trait_id)


static func _trait_summary(person: Dictionary) -> Dictionary:
	var traits: Array = person.get("traits", [])
	var key: int = traits.hash()
	if _trait_summaries.has(key):
		return _trait_summaries[key]
	var summary: Dictionary = {}
	for factor_key: String in PLUS_ONE_EFFECTS + TIMES_EFFECTS:
		summary[factor_key] = 1.0
	for trait_id: Variant in traits:
		var effects: Dictionary = StaffCatalog.get_trait_effects(String(trait_id))
		for effect_key: String in effects:
			var value: Variant = effects[effect_key]
			if PLUS_ONE_EFFECTS.has(effect_key):
				summary[effect_key] = float(summary[effect_key]) * (1.0 + float(value))
			elif TIMES_EFFECTS.has(effect_key):
				summary[effect_key] = float(summary[effect_key]) * float(value)
			elif value is bool:
				summary[effect_key] = bool(summary.get(effect_key, false)) or bool(value)
			elif value is float or value is int:
				# Con el mismo efecto cuenta el más fuerte.
				if absf(float(value)) > absf(float(summary.get(effect_key, 0.0))):
					summary[effect_key] = float(value)
	_trait_summaries[key] = summary
	return summary


# Indica si algún rasgo de alguien tiene ese efecto en true.
static func _trait_flag(person: Dictionary, key: String) -> bool:
	return bool(_trait_summary(person).get(key, false))


# Producto de los factores de un efecto numérico de los rasgos de alguien.
static func _trait_product(person: Dictionary, key: String) -> float:
	return float(_trait_summary(person).get(key, 1.0))


## Quiénes toman una pausa a esa hora absoluta.
func get_breaks(at: int) -> Array[String]:
	var keys: Array[String] = []
	keys.assign(breaks.get(at, []))
	return keys


## Indica si alguien está ahora en una pausa.
func is_on_break(key: String) -> bool:
	return get_breaks(_absolute_hour()).has(key)


# Mayor valor de un efecto numérico entre los rasgos de alguien (0 si ninguno).
static func _trait_value(person: Dictionary, key: String) -> float:
	return float(_trait_summary(person).get(key, 0.0))


static func _approach(value: int, target: int, step: int) -> int:
	if value < target:
		return mini(value + step, target)
	return maxi(value - step, target)


## Horario de un empleado: el propio, si no el de su equipo y, sin equipo, el de su cargo.
func get_schedule(employee: Dictionary) -> WorkSchedule:
	if bool(employee.get("own_schedule", false)):
		return WorkSchedule.from_dict(employee["schedule"])
	var team: Dictionary = get_team_of(employee["id"])
	return WorkSchedule.from_dict(team["schedule"] if not team.is_empty() else employee["schedule"])


# get_schedule de solo lectura: un WorkSchedule por horario distinto (por hash), porque se pide
# por empleado cada hora.
func _cached_schedule(employee: Dictionary) -> WorkSchedule:
	return _cached_schedule_in(employee, {} if bool(employee.get("own_schedule", false)) else get_team_of(employee["id"]))


# _cached_schedule con su equipo ya buscado.
func _cached_schedule_in(employee: Dictionary, team: Dictionary) -> WorkSchedule:
	var data: Dictionary = employee["schedule"]
	if not bool(employee.get("own_schedule", false)) and not team.is_empty():
		data = team["schedule"]
	var key: int = data.hash()
	if not _schedule_cache.has(key):
		if _schedule_cache.size() >= SCHEDULE_CACHE_SIZE:
			_schedule_cache.clear()
		_schedule_cache[key] = WorkSchedule.from_dict(data)
	return _schedule_cache[key]


## Indica si un empleado tiene horario propio.
func has_own_schedule(employee: Dictionary) -> bool:
	return bool(employee.get("own_schedule", false))


## Indica si un empleado es gerente.
func is_manager(employee: Dictionary) -> bool:
	return employee.get("role", "") == StaffCatalog.get_manager_role()


## Indica si un empleado es líder de equipo.
func is_leader(employee: Dictionary) -> bool:
	return employee.get("role", "") == StaffCatalog.get_leader_role()


## Líder de un equipo, o vacío si no tiene.
func get_team_leader(team: Dictionary) -> Dictionary:
	return get_employee(int(team.get("leader_id", 0)))


## Equipo con ese id, o vacío.
func get_team(team_id: int) -> Dictionary:
	for team: Dictionary in teams:
		if team["id"] == team_id:
			return team
	return {}


## Equipo de un empleado (como miembro o como líder), o vacío si no está en ninguno.
func get_team_of(employee_id: int) -> Dictionary:
	for team: Dictionary in teams:
		if (team["members"] as Array).has(employee_id) or int(team.get("leader_id", 0)) == employee_id:
			return team
	return {}


# Equipo de cada empleado que está en uno, para revisar a todos de una vez. Lleva la clave
# NO_TEAM_KEY para no quedar vacío.
func _get_team_map() -> Dictionary[int, Dictionary]:
	var result: Dictionary[int, Dictionary] = {NO_TEAM_KEY: {}}
	for team: Dictionary in teams:
		for member: Variant in team["members"]:
			if not result.has(int(member)):
				result[int(member)] = team
		var leader: int = int(team.get("leader_id", 0))
		if leader != 0 and not result.has(leader):
			result[leader] = team
	return result


## Empleados que no están en ningún equipo.
func get_employees_without_team() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for employee: Dictionary in employees:
		if get_team_of(employee["id"]).is_empty():
			result.append(employee)
	return result


## Empleado con ese id, o vacío.
func get_employee(employee_id: int) -> Dictionary:
	# Se pide mucho: se busca en el índice y se rehace si no coincide.
	var index: int = _employee_index.get(employee_id, -1)
	if index >= 0 and index < employees.size() and employees[index]["id"] == employee_id:
		return employees[index]
	_employee_index.clear()
	for position: int in range(employees.size()):
		_employee_index[int(employees[position]["id"])] = position
	index = _employee_index.get(employee_id, -1)
	return employees[index] if index >= 0 else {}


## Empleado con esa clave de assigned_to, o vacío.
func get_employee_by_key(key: String) -> Dictionary:
	if not key.begins_with(EMPLOYEE_PREFIX):
		return {}
	return get_employee(key.trim_prefix(EMPLOYEE_PREFIX).to_int())


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


func _change_mood(employee: Dictionary, change: int) -> void:
	employee["mood"] = clampi(int(employee["mood"]) + change, 0, 100)


## Día de la semana (0 = lunes) de una hora contada como get_absolute_hour.
static func get_weekday_at(at: int) -> int:
	@warning_ignore("integer_division")
	return (at / GameConstants.HOURS_PER_DAY) % GameConstants.DAYS_PER_WEEK


## Hora absoluta actual (horas desde el inicio de la partida).
func get_absolute_hour() -> int:
	return _absolute_hour()


# Horas enteras desde el inicio de la partida.
func _absolute_hour() -> int:
	return GameClock.get_day_count() * GameConstants.HOURS_PER_DAY + GameClock.get_hour()


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


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
