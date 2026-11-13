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
# fuera. El CEO no tiene horario: llega
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
# Ánimo y renuncias (hito 19): cada día el ánimo y el estrés se acercan a una meta que
# depende del sueldo comparado con su nivel, de tener contrato, de la nómina debida, del
# atraso y del cansancio (data/staff.json, morale). Con ánimo bajo o estrés alto varios
# días seguidos el empleado avisa ("quit_day": el día en que se va; -1 si no avisó); un
# aumento suficiente lo retiene. A veces alguien pide aumento ("raise_request": {"amount",
# "until_day"} o vacío). "bad_days" son los días seguidos mal, "min_energy" la energía más
# baja del día, "last_raise_day" el día del último aumento (o de la contratación) y
# "carry" lo ganado con un sueldo anterior que todavía no se pagó.
#
# Equipos (hito 15): un equipo es {"id", "name", "members", "schedule"}; members son ids
# de empleados y cada empleado está como mucho en un equipo. El turno del equipo
# (schedule) reemplaza el horario de su cargo para todos sus miembros; quien no está en
# ningún equipo sigue con el de su cargo. Cada turno dura teams.shift_hours horas desde
# la entrada y deja al menos teams.min_rest_days de descanso por semana. El proyecto de
# cada equipo lo guarda el contrato (Projects).
#
# Ascensos (hito 30): "projects_worked" cuenta los contratos entregados en los que el
# empleado sumó puntos (EventBus.contract_delivered); los vendedores cuentan en cambio
# los contratos aceptados mientras estaban (EventBus.contract_accepted). Con eso y los
# días en la empresa (data/staff.json, promotion) el jugador puede ascenderlo al nivel
# siguiente con un sueldo mayor (promote); el ascenso cuenta como aumento.
#
# Líderes de equipo (hito 31): desde Startup un Senior puede ascender a líder de equipo
# (cargo sin niveles, sueldo fijo) o se contrata con su vacante. Un equipo guarda su
# líder en "leader_id" (0 si no tiene); el líder no es miembro, no suma puntos y sigue el
# turno del equipo. Desde esa etapa un equipo sin su líder presente rinde
# teams.no_leader_factor (get_team_factor). Un líder sin equipo sigue siendo líder.
#
# Gerentes (hito 32): desde Pequeña empresa un líder asciende a gerente o se contrata con
# su vacante; trabaja en una Oficina única (StaffCatalog.get_workplace). Cada líder guarda
# "manager_id": su gerente, o 0 si lo dirige el CEO. El jugador lo elige (set_manager):
# un gerente dirige hasta management.max_leaders_per_manager líderes y el CEO hasta
# max_leaders_for_ceo líderes con equipo. Con el gerente presente sus equipos rinden
# manager_bonus más, y la meta de estrés de sus miembros baja.
#
# Departamentos y ejecutivos (hito 33): cada cargo es de un departamento
# (StaffCatalog.get_role_department). Desde departments.from_stage (Mediana empresa) los
# que no tienen ejecutivo los dirige el CEO y rinden menos cuantos más dirige
# (get_department_factor). Un ejecutivo trabaja en una Oficina única y guarda en
# "department" el que dirige (uno por departamento). El de Administración puede hacer las
# entrevistas en lugar del CEO (interview["by"]).
#
# Horas extra y turno de noche (hito 34): un turno o un horario propio
# ("own_schedule" con "schedule") puede sumar horas extra. Cada hora del horario que
# termina suma a "overtime_pay" y "night_pay" (dinero con decimales); la nómina las pasa a
# "owed" y guarda qué parte es de cada concepto en "owed_overtime" y "owed_night", que se
# cobran como «Horas extra» y «Recargo nocturno» (data/staff.json, overtime).
#
# Plantillas y agenda (hito 35): una plantilla de turno es {"id", "name", "schedule"}
# (shift_templates). Un equipo con "template_id" sigue su plantilla: cambiarla cambia el
# turno de todos sus equipos; con NO_TEMPLATE tiene turno propio. El "schedule" del
# equipo siempre es su turno vigente. get_agenda da quién trabaja cada hora de un día y
# marca los huecos (AGENDA_GAP: un equipo trabajando sin su líder presente o, desde el
# hito 36, nadie en la Recepción mientras puede haber un cliente esperando).
#
# Contador y limpieza (hito 37, data/staff.json accounting y cleaning): con un contador
# en la empresa el mantenimiento y la tasa de los préstamos nuevos bajan (por el factor de
# Administración) y, unos días antes de cada nómina o día 1, avisa si el saldo de hoy no
# alcanza. Cada hora que termina, quien trabajó en su puesto ensucia la habitación de su
# puesto (OfficeState.add_dirt) y cada persona de limpieza en su turno limpia la más sucia.
# Una habitación sucia baja la meta de ánimo de quienes trabajan en ella.
#
# Competencia (hito 38, data/staff.json competition): cada día otra empresa puede hacerle
# una oferta a un empleado SemiSenior o Senior (o de dirección): "outside_offer" =
# {"salary", "until_day"}. Un aumento que la iguale lo retiene; si no, se va a su
# "until_day" o cuando el jugador lo deja ir (let_go).
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
## bathroom_short_day si nunca faltaron inodoros (lejos de cualquier día de juego).
const NO_SHORT_DAY: int = -1000
## Habitación cuya cafetera necesitan los adictos al café (hito 51).
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
## Cargo que atiende a los clientes que visitan la Recepción (hito 36).
const RECEPTIONIST_ROLE: String = "receptionist"
const NO_CLOSET_MESSAGE: String = "No hay ningún armario de limpieza libre: hace falta un Cuarto de limpieza que funcione, con un armario."

var vacancies: Array[Dictionary] = []
var employees: Array[Dictionary] = []
var interview: Dictionary = {}
## El CEO está trabajando (en la oficina o almorzando) hasta que el jugador lo manda a casa.
var ceo_at_work: bool = true
## Día (GameClock.get_day_count) del último despido; -1000 si no hubo.
var last_firing_day: int = NO_FIRING
var teams: Array[Dictionary] = []
## Plantillas de turno: {"id", "name", "schedule"}.
var shift_templates: Array[Dictionary] = []
## Empleados contratados en toda la partida (para la pantalla de fin).
var hired_count: int = 0
## La nómina de hoy no alcanzó y espera la respuesta al préstamo de emergencia (hito 24):
## todavía no baja el ánimo ni cuenta como atraso.
var payroll_held: bool = false
## Día en que se acabó el café por un evento (hito 51): ese día los adictos rinden como
## sin cafetera. NO_COFFEE_OUT si no.
var coffee_out_day: int = NO_COFFEE_OUT
## Inodoros dañados por el evento «Baño dañado» (hito 52): no cuentan hasta repararlos.
var broken_toilets: int = 0
## Último día en que faltaron inodoros alguna hora (hito 52); NO_SHORT_DAY si nunca.
var bathroom_short_day: int = NO_SHORT_DAY
## Solo para pruebas: false hace como si siempre alcanzaran los inodoros (las pruebas de
## los hitos anteriores al 52 miden oficinas sin baño). No se guarda.
var bathrooms_enabled: bool = true
## Solo para pruebas: false deja los candidatos como antes del hito 56 (sin primera tanda,
## sin calidad por sueldo y ambiente ni candidato extra del premio). No se guarda.
var company_hiring_enabled: bool = true
## Hasta qué día (sin incluirlo) el «Premio de la industria» suma un candidato por vacante.
var award_until: int = 0
## Pausas (hito 54): hora absoluta → claves de quienes descansan esa hora (la actual y la
## anterior, que la producción y la energía cobran al terminar).
var breaks: Dictionary[int, Array] = {}
## Quiénes estuvieron hoy en la oficina (para la máquina expendedora, hito 54).
var present_today: Dictionary[String, bool] = {}

var _next_id: int = 1
var _next_team_id: int = 1
var _next_template_id: int = 1
# Hora (como _absolute_hour) en que terminó la última entrevista; no se guarda.
var _last_interview_end: int = NO_FIRING
var _rng := RandomNumberGenerator.new()
# Ambiente por habitación y muebles (ver _ambiance_detail).
var _ambiance_cache: Dictionary[int, Dictionary] = {}
# Mientras _update_morale recorre a todos: puestos, escritorios y hash de los muebles
# buscados una sola vez (ver _seat_lookup). Vacío el resto del tiempo.
var _seat_lookup_cache: Dictionary = {}
# Horarios ya leídos por el hash de su diccionario (ver _cached_schedule).
var _schedule_cache: Dictionary[int, WorkSchedule] = {}
# id → posición en employees (get_employee); se comprueba al usarla y se rehace si no coincide.
var _employee_index: Dictionary[int, int] = {}


func _ready() -> void:
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.balance_changed.connect(func(_balance: int) -> void: _pay_debt_if_possible())
	EventBus.emergency_loan_resolved.connect(_on_emergency_loan_resolved)
	EventBus.contract_delivered.connect(_on_contract_delivered)
	EventBus.contract_accepted.connect(_on_contract_accepted)


## Prepara el personal de una partida nueva: sin vacantes y con una semilla al azar.
func new_game() -> void:
	vacancies.clear()
	employees.clear()
	interview = {}
	ceo_at_work = true
	last_firing_day = NO_FIRING
	teams.clear()
	_reset_templates()
	hired_count = 0
	payroll_held = false
	coffee_out_day = NO_COFFEE_OUT
	broken_toilets = 0
	bathroom_short_day = NO_SHORT_DAY
	award_until = 0
	breaks.clear()
	present_today.clear()
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
	var locked: String = role_problem(role)
	if not locked.is_empty():
		return {"ok": false, "message": locked, "id": 0}
	if not StaffCatalog.has_levels(role):
		level = StaffCatalog.get_level_ids()[-1]
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
		"publicity_until": publicity_until, "candidates": [] as Array[Dictionary], "first_done": false,
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
	var station_problem: String = get_station_problem(candidate["role"])
	if not station_problem.is_empty():
		return {"ok": false, "result": "", "message": station_problem}
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


## Empieza la entrevista de un candidato con el CEO o, con by_executive, con el
## ejecutivo de Administración. Devuelve {"ok", "message"}.
func start_interview(candidate_id: int, by_executive: bool = false) -> Dictionary:
	var problem: String = interview_problem(candidate_id, by_executive)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var hours: int = int(StaffCatalog.get_hiring("interview_hours"))
	var by: String = "ceo" if not by_executive else employee_key(get_interviewer()["id"])
	interview = {"candidate_id": candidate_id, "ends_at": _absolute_hour() + hours, "by": by}
	EventBus.staff_changed.emit()
	return {"ok": true, "message": "%s entrevista a %s hasta las %02d:00." % [_interviewer_name(by),
		get_candidate(candidate_id)["name"], (GameClock.get_hour() + hours) % GameConstants.HOURS_PER_DAY]}


## Ejecutivo que puede hacer entrevistas (el de departments.interviews_department), o vacío.
func get_interviewer() -> Dictionary:
	return get_executive_of(String(StaffCatalog.get_departments("interviews_department")))


func _interviewer_name(by: String) -> String:
	return "El CEO" if by == "ceo" else "%s (ejecutivo)" % get_employee_by_key(by).get("name", "?")


## Por qué no se puede entrevistar ahora a un candidato ("" si se puede).
func interview_problem(candidate_id: int, by_executive: bool = false) -> String:
	var candidate: Dictionary = get_candidate(candidate_id)
	if candidate.is_empty():
		return "Ese candidato ya no está."
	if bool(candidate["interviewed"]):
		return "Ya lo entrevistaste."
	if not interview.is_empty():
		return "%s ya está en una entrevista." % _interviewer_name(String(interview.get("by", "ceo")))
	var by: String = "ceo"
	if by_executive:
		var interviewer: Dictionary = get_interviewer()
		if interviewer.is_empty():
			return "Hace falta un ejecutivo de %s para delegar las entrevistas." % StaffCatalog.get_department_name(
				String(StaffCatalog.get_departments("interviews_department")))
		by = employee_key(interviewer["id"])
	var hours: int = int(StaffCatalog.get_hiring("interview_hours"))
	var weekday: int = GameClock.get_weekday()
	var hour: int = GameClock.get_hour()
	for offset: int in range(hours):
		if hour + offset >= GameConstants.HOURS_PER_DAY or not is_expected(by, weekday, hour + offset):
			if by != "ceo":
				return "%s tiene que estar en la oficina las %d horas de la entrevista." % [_interviewer_name(by), hours]
			return "El CEO tiene que estar en la oficina las %d horas de la entrevista, sin cruzar el almuerzo (%02d:00) ni la medianoche." % [
				hours, get_ceo_lunch_hour()]
	return ""


## Manda al CEO a casa (false) o a la oficina (true). Si se va, su entrevista se corta.
func set_ceo_at_work(value: bool) -> void:
	if value == ceo_at_work:
		return
	ceo_at_work = value
	if not value and String(interview.get("by", "ceo")) == "ceo":
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
	return _is_working_at(employee, weekday, hour)


# Lo mismo que is_expected para un empleado que ya se tiene a mano (y su equipo, si se
# buscaron todos con _get_team_map).
func _is_working_at(employee: Dictionary, weekday: int, hour: int, team_map: Dictionary[int, Dictionary] = {}) -> bool:
	var schedule: WorkSchedule = _cached_schedule(employee) if team_map.is_empty() \
		else _cached_schedule_in(employee, team_map.get(int(employee["id"]), {}))
	return schedule.is_working(weekday, hour) and not schedule.is_lunch(weekday, hour) and not is_missing(employee, weekday, hour)


## Indica si alguien falta a esa hora de la semana por llegar tarde o faltar el día
## (hito 51). La hora se toma como la más cercana a ahora con ese día y esa hora.
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


## Indica si el CEO produce en esa hora (contada como get_absolute_hour): está
## trabajando, no almuerza, no está en una entrevista y no se quedó dormido (desde
## sleep_hour hasta su hora de llegada).
func is_ceo_producing(at: int) -> bool:
	var hour: int = posmod(at, GameConstants.HOURS_PER_DAY)
	if not is_expected("ceo", get_weekday_at(at), hour) or is_ceo_asleep(hour):
		return false
	var hours: int = int(StaffCatalog.get_hiring("interview_hours"))
	var ceo_interview: bool = not interview.is_empty() and String(interview.get("by", "ceo")) == "ceo"
	var ends_at: int = int(interview["ends_at"]) if ceo_interview else _last_interview_end
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
	return int(employee.get("carry", 0)) + maxi(0, roundi(int(employee["salary"]) * days / float(GameConstants.DAYS_PER_MONTH)))


## Lo que cuesta despedir a un empleado hoy: lo ganado (con horas extra y recargo
## nocturno) más lo que se le debe.
func get_firing_cost(employee: Dictionary) -> int:
	return get_earned(employee) + get_extra_earned(employee) + int(employee["owed"])


## Horas extra y recargo nocturno ganados desde la última nómina, sin pagar todavía.
func get_extra_earned(employee: Dictionary) -> int:
	return roundi(float(employee.get("overtime_pay", 0.0))) + roundi(float(employee.get("night_pay", 0.0)))


## Lo que vale una hora normal de un empleado: sueldo / 30 / overtime.base_hours.
static func get_hour_pay(employee: Dictionary) -> float:
	return float(employee["salary"]) / GameConstants.DAYS_PER_MONTH / float(StaffCatalog.get_overtime("base_hours"))


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
	var cost: int = _remove_employee(employee, CONCEPT_FIRING)
	var today: int = GameClock.get_day_count()
	var streak: bool = today - last_firing_day <= StaffCatalog.get_payroll("fire_streak_days")
	var mood_change: int = StaffCatalog.get_payroll("fire_streak_mood" if streak else "fire_mood")
	for other: Dictionary in employees:
		_change_mood(other, mood_change)
	last_firing_day = today
	var message: String = "Despediste a %s: %s." % [employee["name"], MoneyFormat.format(cost)]
	EventBus.office_changed.emit()
	EventBus.staff_changed.emit()
	EventBus.send_notice(EventBus.target_menu("staff"), message)
	return {"ok": true, "message": message}


## Sube el sueldo de un empleado. Lo ganado hasta hoy queda con el sueldo anterior.
## Un aumento de al menos retain_raise_ratio retiene a quien avisó que renuncia, y uno
## que cubre lo que pidió acepta su pedido. Devuelve {"ok", "message"}.
func give_raise(employee_id: int, new_salary: int) -> Dictionary:
	var employee: Dictionary = get_employee(employee_id)
	if employee.is_empty():
		return {"ok": false, "message": "Ese empleado ya no está."}
	var salary: int = employee["salary"]
	if new_salary <= salary:
		return {"ok": false, "message": "El sueldo nuevo tiene que ser mayor que %s." % MoneyFormat.format(salary)}
	var messages: Array[String] = ["%s gana ahora %s al mes." % [employee["name"], MoneyFormat.format(new_salary)]]
	messages.append_array(_apply_raise(employee, new_salary))
	var message: String = " ".join(messages)
	EventBus.staff_changed.emit()
	EventBus.send_notice(EventBus.target_employee(employee_id), message)
	return {"ok": true, "message": message}


# Cambia el sueldo (lo ganado hasta hoy queda con el anterior) y resuelve el pedido de
# aumento y el aviso de renuncia. Devuelve lo que pasó con ellos, para el aviso.
func _apply_raise(employee: Dictionary, new_salary: int) -> Array[String]:
	var salary: int = employee["salary"]
	var today: int = GameClock.get_day_count()
	employee["carry"] = get_earned(employee)
	employee["paid_until"] = today
	employee["salary"] = new_salary
	employee["last_raise_day"] = today
	var messages: Array[String] = []
	var request: Dictionary = employee["raise_request"]
	if not request.is_empty() and new_salary >= salary + int(request["amount"]):
		employee["raise_request"] = {}
		_change_mood(employee, int(StaffCatalog.get_morale("raise_accept_mood")))
		messages.append("Le diste el aumento que pidió.")
	var offer: Dictionary = employee.get("outside_offer", {})
	if not offer.is_empty():
		if new_salary >= int(offer["salary"]):
			employee["outside_offer"] = {}
			_change_mood(employee, int(StaffCatalog.get_morale("retain_mood")))
			messages.append("Igualaste la oferta de la otra empresa: se queda.")
		else:
			messages.append("La otra empresa le ofrece %s: con eso no se queda." % MoneyFormat.format(int(offer["salary"])))
	if int(employee["quit_day"]) != NO_QUIT:
		if new_salary >= salary * (1.0 + StaffCatalog.get_morale("retain_raise_ratio")) - 0.5:
			employee["quit_day"] = NO_QUIT
			employee["bad_days"] = 0
			_change_mood(employee, int(StaffCatalog.get_morale("retain_mood")))
			messages.append("Se queda en la empresa.")
		else:
			messages.append("No le alcanza para quedarse: pide al menos %d%% más." % roundi(
				StaffCatalog.get_morale("retain_raise_ratio") * 100.0))
	return messages


## Por qué todavía no existe un cargo en esta etapa, o "" si existe.
func role_problem(role: String) -> String:
	var min_stage: int = StaffCatalog.get_role_min_stage(role)
	if Company.stage < min_stage:
		return "El cargo %s se desbloquea en %s." % [StaffCatalog.get_role_name(role), Company.get_stage_name(min_stage)]
	return ""


## Cómo va un empleado hacia el nivel siguiente: {"next_level", "next_role", "projects",
## "projects_needed", "days", "days_needed", "ready"}. next_level es "" si ya es Senior
## o su cargo no tiene niveles. Un Senior puede ascender a líder de equipo (next_role)
## desde la etapa de ese cargo; ready dice si ya puede.
func get_promotion_progress(employee: Dictionary) -> Dictionary:
	var role: String = employee["role"]
	var next_level: String = StaffCatalog.get_next_level(employee["level"]) if StaffCatalog.has_levels(role) else ""
	var next_role: String = StaffCatalog.get_next_role(role, employee["level"])
	var needs: Dictionary = StaffCatalog.get_promotion(next_level) if not next_level.is_empty() else {}
	var projects: int = int(employee.get("projects_worked", 0))
	var days: int = GameClock.get_day_count() - int(employee["hired_day"])
	var projects_needed: int = maxi(0, int(needs.get("projects", 0)) - get_mentor_projects(employee))
	var progress: Dictionary = {"next_level": next_level, "projects": projects, "days": days,
		"projects_needed": projects_needed, "days_needed": int(needs.get("days", 0))}
	progress["ready"] = not needs.is_empty() and projects >= int(progress["projects_needed"]) \
		and days >= int(progress["days_needed"])
	progress["next_role"] = next_role
	# Para ascender de cargo: blocker "stage" si el cargo aún no existe, "station" si no
	# hay dónde trabaje (una Oficina única libre para un gerente) o "".
	progress["blocker"] = ""
	if not next_role.is_empty():
		if not role_problem(next_role).is_empty():
			progress["blocker"] = "stage"
		elif StaffCatalog.get_workplace(next_role) != StaffCatalog.get_workplace(role) \
				and not get_station_problem(next_role).is_empty():
			progress["blocker"] = "station"
		progress["ready"] = String(progress["blocker"]).is_empty()
	return progress


## Por qué no se puede ascender a un empleado con ese sueldo, o "" si se puede.
func promote_problem(employee_id: int, new_salary: int) -> String:
	var employee: Dictionary = get_employee(employee_id)
	if employee.is_empty():
		return "Ese empleado ya no está."
	var progress: Dictionary = get_promotion_progress(employee)
	if String(progress["next_level"]).is_empty() and String(progress["next_role"]).is_empty():
		return "Ya está en el cargo más alto."
	if not bool(progress["ready"]):
		if progress["blocker"] == "station":
			return get_station_problem(progress["next_role"])
		if not String(progress["next_role"]).is_empty():
			return role_problem(progress["next_role"])
		return "Todavía no cumple lo que pide el ascenso."
	if new_salary <= int(employee["salary"]):
		return "El sueldo nuevo tiene que ser mayor que %s." % MoneyFormat.format(employee["salary"])
	return ""


## Asciende a un empleado al nivel siguiente con un sueldo mayor que el actual: rinde y
## comete errores como su nivel nuevo y su habilidad principal sube al menos al mínimo
## del nivel. Cuenta como aumento (retiene y acepta pedidos). Devuelve {"ok", "message"}.
func promote(employee_id: int, new_salary: int) -> Dictionary:
	var problem: String = promote_problem(employee_id, new_salary)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var employee: Dictionary = get_employee(employee_id)
	# Ascendido: la espera del ambicioso vuelve a contar desde que pueda otra vez.
	employee["promotion_ready_day"] = NOT_MISSING
	var next_role: String = get_promotion_progress(employee)["next_role"]
	if not next_role.is_empty():
		return _promote_to_role(employee, next_role, new_salary)
	var level: String = StaffCatalog.get_next_level(employee["level"])
	employee["level"] = level
	var skill: String = StaffCatalog.get_main_skill(employee["role"])
	var raise_by: int = maxi(0, StaffCatalog.get_main_skill_range(level).x - int(employee["skills"][skill]))
	employee["skills"][skill] = int(employee["skills"][skill]) + raise_by
	employee["skill_low"][skill] = mini(int(employee["skill_low"][skill]) + raise_by,
		100 - StaffCatalog.get_skill_range_width())
	var messages: Array[String] = ["%s asciende a %s %s y gana %s al mes." % [employee["name"],
		StaffCatalog.get_role_name(employee["role"]), StaffCatalog.get_level_name(level), MoneyFormat.format(new_salary)]]
	messages.append_array(_apply_raise(employee, new_salary))
	var message: String = " ".join(messages)
	EventBus.staff_changed.emit()
	EventBus.send_notice(EventBus.target_employee(employee_id), message)
	return {"ok": true, "message": message}


# Asciende a otro cargo (un Senior a líder de equipo). Si era miembro de un equipo sin
# líder, pasa a liderarlo; si el equipo ya tenía líder, queda sin equipo.
func _promote_to_role(employee: Dictionary, role: String, new_salary: int) -> Dictionary:
	var team: Dictionary = get_team_of(employee["id"])
	_leave_team(employee["id"])
	var key: String = employee_key(employee["id"])
	if StaffCatalog.get_workplace(role) != StaffCatalog.get_workplace(employee["role"]):
		# Cambia de puesto: deja su silla y toma una libre de su nuevo lugar de trabajo.
		for item: Dictionary in OfficeState.furniture:
			if item["assigned_to"] == key:
				item["assigned_to"] = ""
		OfficeState.furniture[get_free_workstations(role)[0]["chair"]]["assigned_to"] = key
		EventBus.office_changed.emit()
	if employee["role"] == StaffCatalog.get_leader_role():
		# Un líder que deja de serlo ya no tiene gerente, y un gerente nuevo no dirige a nadie.
		employee.erase("manager_id")
	if is_manager(employee):
		# Un gerente que asciende deja a sus líderes a cargo del CEO.
		for leader: Dictionary in get_leaders_of(employee["id"]):
			leader["manager_id"] = 0
	employee["role"] = role
	if role == StaffCatalog.get_leader_role():
		employee["manager_id"] = 0
	if role == StaffCatalog.get_executive_role():
		employee["department"] = _free_department()
	var messages: Array[String] = ["%s asciende a %s y gana %s al mes." % [employee["name"],
		StaffCatalog.get_role_name(role), MoneyFormat.format(new_salary)]]
	if not team.is_empty() and role == StaffCatalog.get_leader_role():
		if int(team["leader_id"]) == 0:
			team["leader_id"] = employee["id"]
			messages.append("Lidera %s." % team["name"])
		else:
			messages.append("%s ya tiene líder: queda sin equipo." % team["name"])
	if role == StaffCatalog.get_executive_role():
		messages.append(_describe_direction(employee))
	messages.append_array(_apply_raise(employee, new_salary))
	var message: String = " ".join(messages)
	_schedules_changed()
	EventBus.send_notice(EventBus.target_employee(int(employee["id"])), message)
	return {"ok": true, "message": message}


## Indica si un empleado es ejecutivo.
func is_executive(employee: Dictionary) -> bool:
	return employee.get("role", "") == StaffCatalog.get_executive_role()


## Ejecutivos contratados.
func get_executives() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for employee: Dictionary in employees:
		if is_executive(employee):
			result.append(employee)
	return result


## Ejecutivo que dirige un departamento, o vacío.
func get_executive_of(department: String) -> Dictionary:
	for employee: Dictionary in employees:
		if is_executive(employee) and employee.get("department", "") == department:
			return employee
	return {}


## Departamentos que existen (con al menos un empleado), en orden.
func get_departments() -> Array[String]:
	var result: Array[String] = []
	for department: String in StaffCatalog.get_department_ids():
		if get_department_size(department) > 0:
			result.append(department)
	return result


## Empleados de un departamento.
func get_department_size(department: String) -> int:
	var count: int = 0
	for employee: Dictionary in employees:
		if StaffCatalog.get_role_department(employee["role"]) == department:
			count += 1
	return count


## Departamentos que existen y dirige el CEO (sin ejecutivo).
func get_ceo_departments() -> Array[String]:
	# Una sola pasada por los empleados: se pide cada hora por cada equipo.
	var present: Dictionary[String, bool] = {}
	var led: Dictionary[String, bool] = {}
	for employee: Dictionary in employees:
		present[StaffCatalog.get_role_department(employee["role"])] = true
		if is_executive(employee):
			led[String(employee.get("department", ""))] = true
	var result: Array[String] = []
	for department: String in StaffCatalog.get_department_ids():
		if present.has(department) and not led.has(department):
			result.append(department)
	return result


## Indica si en esta etapa el CEO rinde menos por dirigir varios departamentos.
func departments_apply() -> bool:
	return Company.stage >= int(StaffCatalog.get_departments("from_stage"))


## Cuánto rinde un departamento: con ejecutivo, 1 más su ventaja por liderazgo; sin él,
## desde Mediana empresa, según cuántos dirige el CEO; si no, 1.
func get_department_factor(department: String) -> float:
	var executive: Dictionary = get_executive_of(department)
	if not executive.is_empty():
		return 1.0 + float(StaffCatalog.get_departments("executive_max_bonus")) * float(executive["skills"]["leadership"]) / 100.0
	if department.is_empty() or not departments_apply():
		return 1.0
	var factors: Array = StaffCatalog.get_departments("ceo_factors")
	return float(factors[mini(get_ceo_departments().size(), factors.size() - 1)])


## Pone a un ejecutivo a dirigir un departamento (uno por departamento). Devuelve
## {"ok", "message"}.
func set_executive_department(executive_id: int, department: String) -> Dictionary:
	var executive: Dictionary = get_employee(executive_id)
	if executive.is_empty() or not is_executive(executive):
		return {"ok": false, "message": "Ese ejecutivo ya no está."}
	if not StaffCatalog.get_department_ids().has(department):
		return {"ok": false, "message": "Ese departamento no existe."}
	var other: Dictionary = get_executive_of(department)
	if other == executive:
		return {"ok": false, "message": "%s ya dirige %s." % [executive["name"], StaffCatalog.get_department_name(department)]}
	if not other.is_empty():
		return {"ok": false, "message": "%s ya lo dirige %s." % [StaffCatalog.get_department_name(department), other["name"]]}
	executive["department"] = department
	var message: String = _describe_direction(executive).replace("Dirige", "%s dirige" % executive["name"])
	_schedules_changed()
	EventBus.send_notice(EventBus.target_employee(executive_id), message)
	return {"ok": true, "message": message}


# "Dirige Desarrollo." o "No dirige ningún departamento: elígelo en el organigrama."
func _describe_direction(executive: Dictionary) -> String:
	var department: String = executive.get("department", "")
	if department.is_empty():
		return "No dirige ningún departamento: elígelo en el organigrama (Personal)."
	return "Dirige %s." % StaffCatalog.get_department_name(department)


# El primer departamento sin ejecutivo, prefiriendo los que existen; "" si todos tienen.
func _free_department() -> String:
	for department: String in get_departments() + StaffCatalog.get_department_ids():
		if get_executive_of(department).is_empty():
			return department
	return ""


func _on_contract_delivered(worker_keys: Array) -> void:
	var changed: bool = false
	for key: Variant in worker_keys:
		var employee: Dictionary = get_employee_by_key(String(key))
		if not employee.is_empty() and employee["role"] != SALES_ROLE:
			employee["projects_worked"] = int(employee["projects_worked"]) + 1
			changed = true
	if changed:
		EventBus.staff_changed.emit()


func _on_contract_accepted() -> void:
	var changed: bool = false
	for employee: Dictionary in employees:
		if employee["role"] == SALES_ROLE:
			employee["projects_worked"] = int(employee["projects_worked"]) + 1
			changed = true
	if changed:
		EventBus.staff_changed.emit()


## Niega el aumento que pidió un empleado (le baja el ánimo).
func deny_raise(employee_id: int) -> bool:
	var employee: Dictionary = get_employee(employee_id)
	if employee.is_empty() or (employee["raise_request"] as Dictionary).is_empty():
		return false
	employee["raise_request"] = {}
	_change_mood(employee, int(StaffCatalog.get_morale("raise_deny_mood")))
	EventBus.staff_changed.emit()
	return true


## Probabilidad diaria de que otra empresa le haga una oferta (0 si no es SemiSenior,
## Senior ni de dirección).
func get_offer_chance(employee: Dictionary) -> float:
	var level: String = employee["level"]
	if not StaffCatalog.has_levels(employee["role"]):
		if not (StaffCatalog.get_management("ladder") as Array).has(employee["role"]):
			return 0.0
		level = StaffCatalog.get_level_ids()[-1]
	var chance: float = float((StaffCatalog.get_competition("chances") as Dictionary).get(level, 0.0))
	var ratio: float = float(employee["salary"]) / maxf(1.0, float(get_market_salary(employee)))
	if ratio < 1.0:
		chance *= float(StaffCatalog.get_competition("underpaid_factor"))
	elif ratio >= float(StaffCatalog.get_competition("well_paid_ratio")):
		chance *= float(StaffCatalog.get_competition("well_paid_factor"))
	var traits: Dictionary = StaffCatalog.get_competition("traits")
	for trait_id: Variant in employee.get("traits", []):
		chance *= float(traits.get(String(trait_id), 1.0))
	return chance


## Iguala la oferta de otra empresa con un aumento. Devuelve {"ok", "message"}.
func match_offer(employee_id: int) -> Dictionary:
	var employee: Dictionary = get_employee(employee_id)
	if employee.is_empty() or (employee.get("outside_offer", {}) as Dictionary).is_empty():
		return {"ok": false, "message": "No tiene ninguna oferta de otra empresa."}
	return give_raise(employee_id, int(employee["outside_offer"]["salary"]))


## Deja que se vaya hoy a la otra empresa (cobra lo ganado y lo debido).
func let_go(employee_id: int) -> Dictionary:
	var employee: Dictionary = get_employee(employee_id)
	if employee.is_empty() or (employee.get("outside_offer", {}) as Dictionary).is_empty():
		return {"ok": false, "message": "No tiene ninguna oferta de otra empresa."}
	return {"ok": true, "message": _leave_for_offer(employee)}


# Se va a la otra empresa: cobra lo ganado y lo debido.
func _leave_for_offer(employee: Dictionary) -> String:
	var cost: int = _remove_employee(employee, CONCEPT_POACHED)
	EventBus.office_changed.emit()
	var message: String = "%s se fue a otra empresa; se le pagó %s." % [employee["name"], MoneyFormat.format(cost)]
	EventBus.send_notice(EventBus.target_menu("staff"), message)
	return message


func _maybe_get_offer(employee: Dictionary, today: int) -> void:
	var chance: float = get_offer_chance(employee)
	if chance <= 0.0 or _rng.randf() >= chance:
		return
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	var raise_range: Array = StaffCatalog.get_competition("raise_range")
	var ratio: float = _rng.randf_range(float(raise_range[0]), float(raise_range[1]))
	var amount: int = maxi(step, roundi(int(employee["salary"]) * ratio / step) * step)
	var days: int = int(StaffCatalog.get_competition("days"))
	employee["outside_offer"] = {"salary": int(employee["salary"]) + amount, "until_day": today + days}
	EventBus.send_notice(EventBus.target_employee(int(employee["id"])), "Otra empresa le ofrece a %s %s al mes: se va en %d días si no igualas la oferta." % [
		employee["name"], MoneyFormat.format(int(employee["salary"]) + amount), days])


## Sueldo de su nivel en la tabla 13.2 (con el que se compara el suyo).
func get_market_salary(employee: Dictionary) -> int:
	return StaffCatalog.get_salary(employee["role"], employee["level"])


## Meta del ánimo de un empleado hoy (ver data/staff.json, morale).
func get_mood_target(employee: Dictionary) -> int:
	var target: float = StaffCatalog.get_morale("mood_base")
	var ratio: float = float(employee["salary"]) / maxf(1.0, float(get_market_salary(employee)))
	if ratio >= StaffCatalog.get_morale("well_paid_ratio"):
		target += StaffCatalog.get_morale("well_paid_mood")
	elif ratio >= 1.0:
		target += StaffCatalog.get_morale("fair_mood")
	elif ratio >= StaffCatalog.get_morale("underpaid_ratio"):
		target += StaffCatalog.get_morale("slightly_underpaid_mood")
	else:
		target += StaffCatalog.get_morale("underpaid_mood")
	if is_idle(employee):
		target += StaffCatalog.get_morale("idle_mood")
	if int(employee["owed"]) > 0:
		target += StaffCatalog.get_morale("owed_mood")
	if int(employee["stress"]) >= int(StaffCatalog.get_morale("stressed_from")):
		target += StaffCatalog.get_morale("stressed_mood")
	if get_schedule(employee).get_night_hours() > 0 and not _trait_flag(employee, "night_mood_free"):
		target += float(StaffCatalog.get_overtime("night_mood"))
	target += get_team_trait_mood(employee)
	if is_waiting_promotion(employee):
		target += _trait_value(employee, "promotion_wait_mood")
	if works_in_dirty_room(employee_key(employee["id"])):
		target += float(StaffCatalog.get_cleaning("dirty_mood"))
	if is_bathroom_short_recently():
		target += StaffCatalog.get_bathrooms("short_mood")
	target += get_break_mood()
	target += get_ambiance(employee_key(employee["id"]))
	target += get_desk_mood(employee_key(employee["id"]))
	return clampi(roundi(target), 0, 100)


## Indica si alguien tiene un rasgo (los tenga descubiertos o no: todos hacen efecto).
static func has_trait(person: Dictionary, trait_id: String) -> bool:
	return (person.get("traits", []) as Array).has(trait_id)


# Efectos sumados de una lista de rasgos, guardados por lista (se piden por persona cada
# hora): "points", "night_points", "day_points" (factores), "bug_factor", "find_factor",
# "team_mood", "mentor_points", "mentor_projects" (el mayor) y "night_mood_free".
static var _trait_summaries: Dictionary[int, Dictionary] = {}
## Efectos que se multiplican como (1 + valor) y los que se multiplican tal cual; los demás
## números cuentan el más fuerte y los true/false, cualquiera.
const PLUS_ONE_EFFECTS: Array[String] = ["points", "night_points", "day_points", "no_coffee_points"]
const TIMES_EFFECTS: Array[String] = ["bug_factor", "find_factor", "quit_days_factor"]


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
				# De varios rasgos con el mismo efecto cuenta el más fuerte.
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


## Cuánto rinden los puntos de alguien a esa hora por sus rasgos (hito 50): el
## perfeccionista y el sociable menos, el noctámbulo más de noche y menos de día y, sin
## café (coffee false, ver has_coffee), el adicto al café menos (hito 51).
static func get_trait_points_factor(person: Dictionary, hour: int, coffee: bool = true) -> float:
	var factor: float = _trait_product(person, "points")
	if not coffee:
		factor *= _trait_product(person, "no_coffee_points")
	return factor * _trait_product(person, "night_points" if WorkSchedule.is_night_hour(hour) else "day_points")


## Indica si hay café hoy: una Sala de descanso que funciona (con su cafetera) y sin el
## evento de que se acabó.
func has_coffee() -> bool:
	return coffee_out_day != GameClock.get_day_count() and Projects.has_working_room(BREAK_ROOM)


## Quiénes toman una pausa a esa hora absoluta (hito 54); vacío si nadie.
func get_breaks(at: int) -> Array[String]:
	var keys: Array[String] = []
	keys.assign(breaks.get(at, []))
	return keys


## Indica si alguien está ahora en una pausa.
func is_on_break(key: String) -> bool:
	return get_breaks(_absolute_hour()).has(key)


# Al empezar la hora: los que trabajan en un cargo que produce con energía baja toman una
# pausa mientras haya lugares en los sofás, primero los más cansados.
func _decide_breaks() -> void:
	var now: int = _absolute_hour()
	for hour: int in breaks.keys():
		if hour < now - 1:
			breaks.erase(hour)
	var places: int = OfficeState.get_rest_places()
	if places <= 0:
		breaks.erase(now)
		return
	var weekday: int = GameClock.get_weekday()
	var hour_of_day: int = GameClock.get_hour()
	var below: float = StaffCatalog.get_breaks("below_energy")
	var team_map: Dictionary[int, Dictionary] = _get_team_map()
	var tired: Array[Dictionary] = []
	for employee: Dictionary in employees:
		if float(employee["energy"]) < below and not Production.get_role_phase(employee["role"]).is_empty() \
				and _is_working_at(employee, weekday, hour_of_day, team_map):
			tired.append(employee)
	tired.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["energy"]) < int(b["energy"]) or (int(a["energy"]) == int(b["energy"]) and int(a["id"]) < int(b["id"])))
	var keys: Array[String] = []
	for employee: Dictionary in tired.slice(0, places):
		keys.append(employee_key(employee["id"]))
	breaks[now] = keys


# Anota quién estuvo hoy en la oficina para la máquina expendedora.
func _note_presence() -> void:
	if OfficeState.get_break_room_effect("vending_income") <= 0.0:
		return
	if is_expected_now("ceo"):
		present_today["ceo"] = true
	var team_map: Dictionary[int, Dictionary] = _get_team_map()
	for employee: Dictionary in employees:
		if _is_working_at(employee, GameClock.get_weekday(), GameClock.get_hour(), team_map):
			present_today[employee_key(employee["id"])] = true


# La máquina expendedora cobra lo de las personas que estuvieron ayer.
func _collect_vending() -> void:
	var income: int = roundi(OfficeState.get_break_room_effect("vending_income") * present_today.size())
	present_today.clear()
	if income > 0:
		Economy.earn(income, CONCEPT_VENDING)


func _export_breaks() -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	for hour: int in breaks:
		saved.append({"hour": hour, "keys": breaks[hour].duplicate()})
	return saved


## Quiénes almuerzan dentro a esa hora absoluta (hito 53): los que están en su hora de
## almuerzo mientras haya asientos en una Sala de descanso armada para almorzar (nevera,
## microondas y mesas), primero el CEO y después por antigüedad. Claves como is_expected.
func get_lunch_inside(at: int) -> Dictionary[String, bool]:
	var inside: Dictionary[String, bool] = {}
	var seats: int = OfficeState.get_lunch_seats()
	if seats <= 0:
		return inside
	var weekday: int = get_weekday_at(at)
	var hour: int = posmod(at, GameConstants.HOURS_PER_DAY)
	if ceo_at_work and hour == get_ceo_lunch_hour():
		inside["ceo"] = true
	var team_map: Dictionary[int, Dictionary] = _get_team_map()
	for employee: Dictionary in employees:
		if inside.size() >= seats:
			break
		var schedule: WorkSchedule = _cached_schedule_in(employee, team_map.get(int(employee["id"]), {}))
		if schedule.is_working(weekday, hour) and schedule.is_lunch(weekday, hour) and not is_missing(employee, weekday, hour):
			inside[employee_key(employee["id"])] = true
	return inside


## Indica si alguien almuerza ahora dentro de la oficina.
func is_lunching_inside(key: String) -> bool:
	return get_lunch_inside(_absolute_hour()).has(key)


## Inodoros que cuentan: los de los Baños que funcionan menos los dañados (hito 52).
func get_toilet_capacity() -> int:
	return maxi(0, OfficeState.count_working_toilets() - broken_toilets)


## Personas en la oficina a esa hora absoluta: quienes trabajan (sin almuerzo, tardanza
## ni ausencia) y el CEO.
func count_present(at: int) -> int:
	var weekday: int = get_weekday_at(at)
	var hour: int = posmod(at, GameConstants.HOURS_PER_DAY)
	var team_map: Dictionary[int, Dictionary] = _get_team_map()
	var count: int = 1 if is_expected("ceo", weekday, hour) else 0
	for employee: Dictionary in employees:
		if _is_working_at(employee, weekday, hour, team_map):
			count += 1
	return count


## Inodoros que hacen falta para esa cantidad de personas: 1 cada 10, hacia arriba.
static func get_toilets_needed(present: int) -> int:
	return ceili(float(present) / StaffCatalog.get_bathrooms("people_per_toilet"))


## Cuántos inodoros faltan a esa hora absoluta (0 si alcanzan).
func get_bathroom_shortage(at: int) -> int:
	if not bathrooms_enabled:
		return 0
	return maxi(0, get_toilets_needed(count_present(at)) - get_toilet_capacity())


## Por cuánto se multiplica la producción con esa falta de inodoros: −5 % por cada uno
## que falta por las colas, hasta −20 %.
static func get_bathroom_factor(shortage: int) -> float:
	return 1.0 - minf(StaffCatalog.get_bathrooms("max_points_loss"), shortage * StaffCatalog.get_bathrooms("points_per_missing"))


## Indica si faltaron inodoros hoy o ayer (baja la meta de ánimo de todos).
func is_bathroom_short_recently() -> bool:
	return GameClock.get_day_count() - bathroom_short_day <= 1


# Anota el día si a esta hora faltan inodoros.
func _check_bathrooms() -> void:
	if get_bathroom_shortage(_absolute_hour()) > 0:
		bathroom_short_day = GameClock.get_day_count()


## Evento «Baño dañado»: un inodoro deja de contar hasta repararlo. Devuelve false si no
## había ninguno que dañar.
func break_toilet() -> bool:
	if broken_toilets >= OfficeState.count_working_toilets():
		return false
	broken_toilets += 1
	EventBus.staff_changed.emit()
	return true


## Repara un inodoro dañado cobrando repair_cost. Devuelve {"ok", "message"}.
func repair_toilet() -> Dictionary:
	var cost: int = int(StaffCatalog.get_bathrooms("repair_cost"))
	if broken_toilets <= 0:
		return {"ok": false, "message": "No hay ningún inodoro dañado."}
	if not Economy.spend(cost, CONCEPT_REPAIR):
		return {"ok": false, "message": "No alcanza el dinero para reparar el baño (%s)." % MoneyFormat.format(cost)}
	broken_toilets -= 1
	var message: String = "Se reparó el baño por %s." % MoneyFormat.format(cost)
	EventBus.staff_changed.emit()
	EventBus.send_notice(EventBus.target_menu("company"), message)
	return {"ok": true, "message": message}


## Se acabó el café por hoy (evento «Se acabó el café»).
func run_out_of_coffee() -> void:
	coffee_out_day = GameClock.get_day_count()


# Al empezar cada hora: quien entra a trabajar llega a tiempo, tarde (pierde esa hora) o
# falta (pierde la jornada) según sus rasgos. El sorteo depende solo de la semilla, el
# empleado y la hora: no gasta el azar de las vacantes.
func _check_arrivals() -> void:
	var weekday: int = GameClock.get_weekday()
	var hour: int = GameClock.get_hour()
	var now: int = _absolute_hour()
	var team_map: Dictionary[int, Dictionary] = _get_team_map()
	for employee: Dictionary in employees:
		var schedule: WorkSchedule = _cached_schedule_in(employee, team_map.get(int(employee["id"]), {}))
		if schedule.start_hour != hour or not schedule.days.has(weekday):
			continue
		var late: float = _trait_value(employee, "late_chance")
		var absent: float = _trait_value(employee, "absent_chance")
		var roll: float = 1.0
		if late > 0.0 or absent > 0.0:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([_rng.seed, int(employee["id"]), now])
			roll = rng.randf()
		if roll < absent:
			employee["missing_from"] = now
			employee["missing_until"] = now + schedule.get_duration()
			employee["absent_count"] = int(employee.get("absent_count", 0)) + 1
			EventBus.send_notice(EventBus.target_employee(int(employee["id"])), "%s faltó hoy al trabajo." % employee["name"])
		elif roll < absent + late:
			employee["missing_from"] = now
			employee["missing_until"] = now + 1
			employee["late_count"] = int(employee.get("late_count", 0)) + 1
		else:
			employee["on_time_count"] = int(employee.get("on_time_count", 0)) + 1


## Anota los errores ocultos que generó cada empleado en la hora (lo que devuelve
## Production.apply después de Production.handle_bugs).
func note_bugs_caused(done: Array[Dictionary]) -> void:
	for item: Dictionary in done:
		var bugs: int = int(item.get("bugs", 0))
		if bugs <= 0:
			continue
		var employee: Dictionary = get_employee_by_key(String(item["worker"]["key"]))
		if not employee.is_empty():
			employee["bugs_caused"] = int(employee.get("bugs_caused", 0)) + bugs


## Porcentaje de jornadas en que llegó a tiempo, o -1 si todavía no empezó ninguna.
static func get_punctuality(employee: Dictionary) -> int:
	var on_time: int = int(employee.get("on_time_count", 0))
	var total: int = on_time + int(employee.get("late_count", 0)) + int(employee.get("absent_count", 0))
	return -1 if total == 0 else roundi(100.0 * on_time / total)


## «Historial: 3 contratos · 5 errores causados · 2 llegadas tarde · 1 ausencia · puntualidad 90 %».
static func describe_history(employee: Dictionary) -> String:
	var late: int = int(employee.get("late_count", 0))
	var absent: int = int(employee.get("absent_count", 0))
	var parts: Array[String] = [
		"%d %s" % [int(employee.get("projects_worked", 0)), "contrato" if int(employee.get("projects_worked", 0)) == 1 else "contratos"],
		"%d %s" % [int(employee.get("bugs_caused", 0)), "error causado" if int(employee.get("bugs_caused", 0)) == 1 else "errores causados"],
		"%d %s" % [late, "llegada tarde" if late == 1 else "llegadas tarde"],
		"%d %s" % [absent, "ausencia" if absent == 1 else "ausencias"]]
	var punctuality: int = get_punctuality(employee)
	parts.append("puntualidad %s" % ("—" if punctuality < 0 else "%d %%" % punctuality))
	return "Historial: " + " · ".join(parts)


# Cada día: desde cuándo puede ascender cada ambicioso (se borra al ascenderlo o si deja de
# poder).
func _update_promotion_waits() -> void:
	for employee: Dictionary in employees:
		if _trait_value(employee, "promotion_wait_days") <= 0.0:
			continue
		var ready: bool = bool(get_promotion_progress(employee)["ready"])
		if not ready:
			employee["promotion_ready_day"] = NOT_MISSING
		elif int(employee.get("promotion_ready_day", NOT_MISSING)) == NOT_MISSING:
			employee["promotion_ready_day"] = GameClock.get_day_count()


## Indica si un ambicioso lleva tanto tiempo sin que lo asciendan que se molesta.
func is_waiting_promotion(employee: Dictionary) -> bool:
	var since: int = int(employee.get("promotion_ready_day", NOT_MISSING))
	var wait: float = _trait_value(employee, "promotion_wait_days")
	return wait > 0.0 and since != NOT_MISSING and GameClock.get_day_count() - since >= int(wait)


## Por cuánto se multiplican los errores que genera alguien al programar (perfeccionista).
static func get_trait_bug_factor(person: Dictionary) -> float:
	return _trait_product(person, "bug_factor")


## Por cuánto se multiplican los errores que encuentra alguien al probar (perfeccionista).
static func get_trait_find_factor(person: Dictionary) -> float:
	return _trait_product(person, "find_factor")


# Quienes están en el equipo de un empleado (miembros y líder), incluido él.
func _team_people(employee: Dictionary) -> Array[Dictionary]:
	var people: Array[Dictionary] = []
	var team: Dictionary = get_team_of(employee["id"])
	if team.is_empty():
		return people
	var ids: Array = (team["members"] as Array).duplicate()
	if int(team.get("leader_id", 0)) != 0:
		ids.append(int(team["leader_id"]))
	for id: Variant in ids:
		var person: Dictionary = get_employee(int(id))
		if not person.is_empty():
			people.append(person)
	return people


## Lo que suma a la meta de ánimo de alguien tener un compañero sociable en su equipo
## (él mismo incluido; una vez aunque haya varios).
func get_team_trait_mood(employee: Dictionary) -> float:
	var best: float = 0.0
	for person: Dictionary in _team_people(employee):
		best = maxf(best, float(_trait_value(person, "team_mood")))
	return best


# El mayor valor de un efecto numérico entre los rasgos de alguien (0 si ninguno lo tiene).
static func _trait_value(person: Dictionary, key: String) -> float:
	return float(_trait_summary(person).get(key, 0.0))


# Mentores del equipo de un empleado, sin contarlo a él.
func _mentors_of(employee: Dictionary) -> Array[Dictionary]:
	var mentors: Array[Dictionary] = []
	for person: Dictionary in _team_people(employee):
		if person["id"] != employee["id"] and _trait_value(person, "mentor_points") > 0.0:
			mentors.append(person)
	return mentors


# Indica si un nivel es de los que ayuda un mentor.
static func _is_mentee(employee: Dictionary, mentor: Dictionary) -> bool:
	for trait_id: Variant in mentor.get("traits", []):
		if (StaffCatalog.get_trait_effect(String(trait_id), "mentor_levels", []) as Array).has(employee.get("level", "")):
			return true
	return false


## Cuánto más rinde alguien por un mentor de su equipo presente a esa hora (1 si no hay;
## una vez aunque haya varios).
func get_mentor_factor(employee: Dictionary, weekday: int, hour: int) -> float:
	return float(get_team_mentor_factors(get_team_of(employee["id"]), weekday, hour).get(int(employee["id"]), 1.0))


## get_mentor_factor de todos los de un equipo de una vez (id → factor; sin mentores
## presentes, vacío): Projects.get_workers lo pide por cada contrato cada hora.
func get_team_mentor_factors(team: Dictionary, weekday: int, hour: int) -> Dictionary[int, float]:
	var factors: Dictionary[int, float] = {}
	if team.is_empty():
		return factors
	var ids: Array = (team["members"] as Array).duplicate()
	if int(team.get("leader_id", 0)) != 0:
		ids.append(int(team["leader_id"]))
	var people: Array[Dictionary] = []
	var mentors: Array[Dictionary] = []
	for id: Variant in ids:
		var person: Dictionary = get_employee(int(id))
		if person.is_empty():
			continue
		people.append(person)
		if _trait_value(person, "mentor_points") > 0.0 and _is_working_at(person, weekday, hour):
			mentors.append(person)
	if mentors.is_empty():
		return factors
	for person: Dictionary in people:
		var best: float = 0.0
		for mentor: Dictionary in mentors:
			if mentor["id"] != person["id"] and _is_mentee(person, mentor):
				best = maxf(best, _trait_value(mentor, "mentor_points"))
		if best > 0.0:
			factors[int(person["id"])] = 1.0 + best
	return factors


## Cuántos contratos menos necesita alguien para ascender por tener un mentor en su equipo.
func get_mentor_projects(employee: Dictionary) -> int:
	var best: int = 0
	for mentor: Dictionary in _mentors_of(employee):
		if _is_mentee(employee, mentor):
			best = maxi(best, int(_trait_value(mentor, "mentor_projects")))
	return best


# Cada discover_days días en la empresa se descubre el siguiente rasgo de cada empleado.
func _discover_traits() -> void:
	var every: int = StaffCatalog.get_trait_discover_days()
	var today: int = GameClock.get_day_count()
	for employee: Dictionary in employees:
		var days: int = today - int(employee.get("hired_day", today))
		if days <= 0 or days % every != 0:
			continue
		var known: Array = employee.get_or_add("known_traits", [] as Array[String])
		for trait_id: Variant in employee.get("traits", []):
			if not known.has(trait_id):
				known.append(String(trait_id))
				EventBus.send_notice(EventBus.target_employee(int(employee["id"])), "Descubriste que %s es %s." % [employee["name"],
					StaffCatalog.get_trait_name(String(trait_id)).to_lower()])
				break


## Meta del estrés de un empleado hoy.
func get_stress_target(employee: Dictionary) -> int:
	var target: float = StaffCatalog.get_morale("stress_base")
	var contract: Dictionary = _contract_of(employee)
	if contract.has("deadline_day") and Projects.get_days_late(contract) > 0:
		target += StaffCatalog.get_morale("late_stress")
	if int(employee.get("min_energy", 100)) < int(StaffCatalog.get_morale("tired_below")):
		target += StaffCatalog.get_morale("tired_stress")
	# Los equipos de un líder con gerente se estresan menos.
	var team: Dictionary = get_team_of(employee["id"])
	if not team.is_empty() and not get_manager_of(get_team_leader(team)).is_empty():
		target += float(StaffCatalog.get_management("manager_stress"))
	target += float(StaffCatalog.get_overtime("stress_per_hour")) * get_schedule(employee).overtime
	var room: Dictionary = get_workplace_room(employee_key(employee["id"]))
	if not room.is_empty():
		target -= int(_ambiance_detail(room)["stress_relief"])
	return clampi(roundi(target), 0, 100)


## Suma (o resta) a todos los empleados en "mood", "energy" o "stress" (de 0 a 100); lo
## usan los eventos (hito 43). Con ids, solo a esos empleados.
func change_all(key: String, amount: int, ids: Array[int] = []) -> void:
	for employee: Dictionary in employees:
		if not ids.is_empty() and not ids.has(int(employee["id"])):
			continue
		if employee[key] is float:
			employee[key] = clampf(float(employee[key]) + amount, 0.0, 100.0)
		else:
			employee[key] = clampi(int(employee[key]) + amount, 0, 100)
	EventBus.staff_changed.emit()


## Indica si un empleado no tiene trabajo: su equipo no lleva contrato (los vendedores
## no lo necesitan).
func is_idle(employee: Dictionary) -> bool:
	return not Production.get_role_phase(employee["role"]).is_empty() and _contract_of(employee).is_empty()


## Icono de estado de un empleado (hito 57): el primero de status_icons.order que se
## cumple ("no_station", "tired", "upset", "stressed" o "idle"), o "" si ninguno.
func get_status_icon(employee: Dictionary) -> String:
	for icon: Variant in StaffCatalog.get_status_icons("order"):
		if _has_status(employee, String(icon)):
			return String(icon)
	return ""


func _has_status(employee: Dictionary, icon: String) -> bool:
	match icon:
		"no_station":
			return _seat_of(employee_key(int(employee["id"]))).is_empty()
		"tired":
			return float(employee["energy"]) < float(StaffCatalog.get_status_icons("tired_below"))
		"upset":
			return float(employee["mood"]) < float(StaffCatalog.get_status_icons("upset_below")) \
				or int(employee["quit_day"]) != NO_QUIT
		"stressed":
			return float(employee["stress"]) >= float(StaffCatalog.get_status_icons("stressed_from"))
		"idle":
			return is_idle(employee)
	return false


## Días que le quedan a quien avisó que renuncia, o -1.
func quit_days_left(employee: Dictionary) -> int:
	if int(employee["quit_day"]) == NO_QUIT:
		return -1
	return maxi(0, int(employee["quit_day"]) - GameClock.get_day_count())


# Contrato que lleva el equipo de un empleado, o vacío. Un producto en desarrollo (hito 41)
# también es trabajo: devuelve el producto (no tiene plazo ni atraso).
func _contract_of(employee: Dictionary) -> Dictionary:
	var team: Dictionary = get_team_of(employee["id"])
	if team.is_empty():
		return {}
	var contract: Dictionary = Projects.get_contract_of(team["id"])
	return contract if not contract.is_empty() else Products.get_product_of(team["id"])


# Saca a un empleado de la empresa: cobra lo ganado y lo debido con ese concepto y
# libera su puesto y su equipo. Devuelve lo cobrado.
func _remove_employee(employee: Dictionary, concept: String) -> int:
	var cost: int = get_firing_cost(employee)
	# Primero deja de ser empleado: así su deuda no se cuenta en la nómina pendiente.
	employees.erase(employee)
	_leave_team(employee["id"])
	# Los líderes de un gerente que se va vuelven a estar a cargo del CEO.
	for leader: Dictionary in get_leaders_of(employee["id"]):
		leader["manager_id"] = 0
	# Si hacía una entrevista, se corta.
	if String(interview.get("by", "")) == employee_key(employee["id"]):
		interview = {}
	Economy.charge(cost, concept)
	var key: String = employee_key(employee["id"])
	for item: Dictionary in OfficeState.furniture:
		if item["assigned_to"] == key:
			item["assigned_to"] = ""
	return cost


# Cada día: ánimo y estrés se acercan a su meta, vencen los pedidos de aumento, se van
# los que avisaron y avisan los que llevan varios días mal; a veces alguien pide aumento.
func _update_morale() -> void:
	var today: int = GameClock.get_day_count()
	var mood_step: int = int(StaffCatalog.get_morale("mood_step"))
	var stress_step: int = int(StaffCatalog.get_morale("stress_step"))
	_build_seat_lookup()
	for employee: Dictionary in employees.duplicate():
		if not employee.has("quit_day"):
			_add_morale_fields(employee, employee.duplicate())
		employee["stress"] = _approach(int(employee["stress"]), get_stress_target(employee), stress_step)
		employee["mood"] = _approach(int(employee["mood"]), get_mood_target(employee), mood_step)
		employee["min_energy"] = int(employee["energy"])
		var request: Dictionary = employee["raise_request"]
		if not request.is_empty() and today >= int(request["until_day"]):
			employee["raise_request"] = {}
			_change_mood(employee, int(StaffCatalog.get_morale("raise_deny_mood")))
			EventBus.send_notice(EventBus.target_employee(int(employee["id"])), "%s se quedó sin respuesta a su pedido de aumento." % employee["name"])
		var bad: bool = int(employee["mood"]) < int(StaffCatalog.get_morale("quit_mood_below")) \
			or int(employee["stress"]) > int(StaffCatalog.get_morale("quit_stress_above"))
		employee["bad_days"] = int(employee["bad_days"]) + 1 if bad else 0
		var offer: Dictionary = employee.get("outside_offer", {})
		if not offer.is_empty():
			if today >= int(offer["until_day"]):
				_leave_for_offer(employee)
			continue
		if int(employee["quit_day"]) != NO_QUIT:
			if today >= int(employee["quit_day"]):
				_resign(employee)
			continue
		if int(employee["bad_days"]) >= roundi(StaffCatalog.get_morale("quit_bad_days") * _trait_product(employee, "quit_days_factor")):
			employee["quit_day"] = today + int(StaffCatalog.get_morale("notice_days"))
			EventBus.send_notice(EventBus.target_employee(int(employee["id"])), "%s avisa que renuncia: se va en %d días si no le das un aumento." % [
				employee["name"], int(StaffCatalog.get_morale("notice_days"))])
			continue
		_maybe_get_offer(employee, today)
		_maybe_ask_raise(employee, today)
	_seat_lookup_cache = {}
	EventBus.staff_changed.emit()


func _maybe_ask_raise(employee: Dictionary, today: int) -> void:
	if not (employee["raise_request"] as Dictionary).is_empty():
		return
	var ratio: float = float(employee["salary"]) / maxf(1.0, float(get_market_salary(employee)))
	if ratio >= StaffCatalog.get_morale("raise_request_below_ratio"):
		return
	if today - int(employee["last_raise_day"]) < int(StaffCatalog.get_morale("raise_request_min_days")):
		return
	if _rng.randf() >= StaffCatalog.get_morale("raise_request_chance"):
		return
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	var amount: int = maxi(step, roundi(int(employee["salary"]) * StaffCatalog.get_morale("raise_request_ratio") / step) * step)
	employee["raise_request"] = {"amount": amount, "until_day": today + int(StaffCatalog.get_morale("raise_request_days"))}
	EventBus.send_notice(EventBus.target_employee(int(employee["id"])), "%s pide un aumento de %s." % [employee["name"], MoneyFormat.format(amount)])


# Un empleado se va por su cuenta: cobra lo ganado y lo debido.
func _resign(employee: Dictionary) -> void:
	var cost: int = _remove_employee(employee, CONCEPT_RESIGNATION)
	EventBus.office_changed.emit()
	EventBus.send_notice(EventBus.target_menu("staff"), "%s renunció y se fue; se le pagó %s." % [employee["name"], MoneyFormat.format(cost)])


static func _approach(value: int, target: int, step: int) -> int:
	if value < target:
		return mini(value + step, target)
	return maxi(value - step, target)


## Horario de un empleado: el propio si tiene, si no el turno de su equipo y, sin
## equipo, el de su cargo.
func get_schedule(employee: Dictionary) -> WorkSchedule:
	if bool(employee.get("own_schedule", false)):
		return WorkSchedule.from_dict(employee["schedule"])
	var team: Dictionary = get_team_of(employee["id"])
	return WorkSchedule.from_dict(team["schedule"] if not team.is_empty() else employee["schedule"])


# Lo mismo que get_schedule, solo para leer: se guarda un WorkSchedule por cada horario
# distinto (el hash de su diccionario) porque se pide por cada empleado cada hora.
func _cached_schedule(employee: Dictionary) -> WorkSchedule:
	return _cached_schedule_in(employee, {} if bool(employee.get("own_schedule", false)) else get_team_of(employee["id"]))


# Lo mismo que _cached_schedule con su equipo ya buscado (ver _get_team_map).
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


## Le da a un empleado un horario propio (reemplaza el de su equipo o su cargo):
## hora de entrada, días y horas extra. Devuelve {"ok", "message"}.
func set_own_schedule(employee_id: int, start_hour: int, days: Array[int], overtime: int = 0) -> Dictionary:
	var employee: Dictionary = get_employee(employee_id)
	if employee.is_empty():
		return {"ok": false, "message": "Ese empleado ya no está."}
	var problem: String = shift_problem(start_hour, days, overtime)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var schedule: WorkSchedule = WorkSchedule.make_shift(start_hour, days, overtime)
	employee["schedule"] = schedule.to_dict()
	employee["own_schedule"] = true
	_schedules_changed()
	return {"ok": true, "message": "Horario de %s: %s." % [employee["name"], schedule.describe()]}


## Quita el horario propio: vuelve al turno de su equipo o al horario de su cargo.
func clear_own_schedule(employee_id: int) -> Dictionary:
	var employee: Dictionary = get_employee(employee_id)
	if employee.is_empty():
		return {"ok": false, "message": "Ese empleado ya no está."}
	employee["own_schedule"] = false
	employee["schedule"] = StaffCatalog.get_role_schedule(employee["role"])
	_schedules_changed()
	var team: Dictionary = get_team_of(employee_id)
	return {"ok": true, "message": "%s vuelve %s: %s." % [employee["name"],
		"al turno de " + String(team["name"]) if not team.is_empty() else "al horario de su cargo",
		get_schedule(employee).describe()]}


## Indica si un empleado tiene horario propio.
func has_own_schedule(employee: Dictionary) -> bool:
	return bool(employee.get("own_schedule", false))


## Crea un equipo vacío con el turno por defecto y lo devuelve.
func create_team() -> Dictionary:
	var schedule: Dictionary = WorkSchedule.make_shift(int(StaffCatalog.get_teams("default_start_hour")),
		StaffCatalog.get_default_team_days()).to_dict()
	# Un equipo nuevo usa la primera plantilla, si hay.
	var template_id: int = NO_TEMPLATE
	if not shift_templates.is_empty():
		template_id = shift_templates[0]["id"]
		schedule = (shift_templates[0]["schedule"] as Dictionary).duplicate(true)
	var members: Array[int] = []
	var team: Dictionary = {"id": _next_team_id, "name": "%s %d" % [StaffCatalog.get_teams("name_prefix"), _next_team_id],
		"members": members, "leader_id": 0, "schedule": schedule, "template_id": template_id}
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


## Pone a un empleado en un equipo (si estaba en otro, sale de aquel). Un líder de
## equipo entra como su líder, si el equipo no tiene; los demás, como miembros, hasta
## teams.max_members. Devuelve {"ok", "message"}.
func add_to_team(team_id: int, employee_id: int) -> Dictionary:
	var team: Dictionary = get_team(team_id)
	var employee: Dictionary = get_employee(employee_id)
	if team.is_empty() or employee.is_empty():
		return {"ok": false, "message": "Ese equipo o ese empleado ya no está."}
	if int(get_team_of(employee_id).get("id", 0)) == team_id:
		return {"ok": false, "message": "%s ya está en %s." % [employee["name"], team["name"]]}
	if is_manager(employee) or is_executive(employee):
		return {"ok": false, "message": "%s es %s: dirige desde su oficina y no entra a un equipo." % [
			employee["name"], StaffCatalog.get_role_name(employee["role"]).to_lower()]}
	if is_leader(employee):
		if int(team["leader_id"]) != 0:
			return {"ok": false, "message": "%s ya tiene líder: %s. Quítalo primero." % [team["name"],
				get_employee(int(team["leader_id"]))["name"]]}
		if int(employee.get("manager_id", 0)) == 0 and get_team_of(employee_id).is_empty() and get_ceo_leaders().size() >= get_leader_cap(0):
			return {"ok": false, "message": "El CEO ya dirige %d líderes de equipo: asígnale un gerente a %s en el organigrama (Personal)." % [
				get_leader_cap(0), employee["name"]]}
		_leave_team(employee_id)
		team["leader_id"] = employee_id
		_schedules_changed()
		return {"ok": true, "message": "%s lidera %s." % [employee["name"], team["name"]]}
	var members: Array[int] = team["members"]
	var max_members: int = int(StaffCatalog.get_teams("max_members"))
	if members.size() >= max_members:
		return {"ok": false, "message": "%s ya tiene %d miembros, el máximo para un líder." % [team["name"], max_members]}
	_leave_team(employee_id)
	members.append(employee_id)
	_schedules_changed()
	return {"ok": true, "message": "%s entra a %s." % [employee["name"], team["name"]]}


## Indica si un empleado es gerente.
func is_manager(employee: Dictionary) -> bool:
	return employee.get("role", "") == StaffCatalog.get_manager_role()


## Gerentes contratados.
func get_managers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for employee: Dictionary in employees:
		if is_manager(employee):
			result.append(employee)
	return result


## Líderes de equipo contratados.
func get_leaders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for employee: Dictionary in employees:
		if is_leader(employee):
			result.append(employee)
	return result


## Líderes que dirige un gerente (todos los que lo tienen como gerente).
func get_leaders_of(manager_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for leader: Dictionary in get_leaders():
		if int(leader.get("manager_id", 0)) == manager_id:
			result.append(leader)
	return result


## Líderes con equipo que dirige el CEO (los que no tienen gerente).
func get_ceo_leaders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for leader: Dictionary in get_leaders_of(0):
		if not get_team_of(leader["id"]).is_empty():
			result.append(leader)
	return result


## Cuántos líderes puede dirigir un gerente (o el CEO con manager_id 0).
func get_leader_cap(manager_id: int) -> int:
	return int(StaffCatalog.get_management("max_leaders_for_ceo" if manager_id == 0 else "max_leaders_per_manager"))


## Gerente de un líder, o vacío si lo dirige el CEO.
func get_manager_of(leader: Dictionary) -> Dictionary:
	return get_employee(int(leader.get("manager_id", 0)))


## Pone a un líder a cargo de un gerente (o del CEO con manager_id 0), si le queda
## lugar. Devuelve {"ok", "message"}.
func set_manager(leader_id: int, manager_id: int) -> Dictionary:
	var leader: Dictionary = get_employee(leader_id)
	if leader.is_empty() or not is_leader(leader):
		return {"ok": false, "message": "Ese líder de equipo ya no está."}
	if int(leader.get("manager_id", 0)) == manager_id:
		return {"ok": false, "message": "%s ya está a cargo de %s." % [leader["name"], _boss_name(manager_id)]}
	var manager: Dictionary = get_employee(manager_id)
	if manager_id != 0 and (manager.is_empty() or not is_manager(manager)):
		return {"ok": false, "message": "Ese gerente ya no está."}
	var cap: int = get_leader_cap(manager_id)
	var count: int = get_ceo_leaders().size() if manager_id == 0 else get_leaders_of(manager_id).size()
	if count >= cap and (manager_id != 0 or not get_team_of(leader_id).is_empty()):
		return {"ok": false, "message": "%s ya dirige %d líderes, el máximo." % [_boss_name(manager_id), cap]}
	leader["manager_id"] = manager_id
	var message: String = "%s queda a cargo de %s." % [leader["name"], _boss_name(manager_id)]
	_schedules_changed()
	EventBus.send_notice(EventBus.target_employee(leader_id), message)
	return {"ok": true, "message": message}


func _boss_name(manager_id: int) -> String:
	return "el CEO" if manager_id == 0 else String(get_employee(manager_id).get("name", "?"))


## Indica si el gerente que dirige al líder de un equipo está trabajando a esa hora.
func is_manager_present(team: Dictionary, at: int) -> bool:
	var manager: Dictionary = get_manager_of(get_team_leader(team))
	return not manager.is_empty() and is_expected(employee_key(manager["id"]), get_weekday_at(at),
		posmod(at, GameConstants.HOURS_PER_DAY))


## Indica si un empleado es líder de equipo.
func is_leader(employee: Dictionary) -> bool:
	return employee.get("role", "") == StaffCatalog.get_leader_role()


## Líder de un equipo, o vacío si no tiene.
func get_team_leader(team: Dictionary) -> Dictionary:
	return get_employee(int(team.get("leader_id", 0)))


## Indica si el líder de un equipo está trabajando a esa hora (contada como
## get_absolute_hour).
func is_leader_present(team: Dictionary, at: int) -> bool:
	var leader: Dictionary = get_team_leader(team)
	return not leader.is_empty() and is_expected(employee_key(leader["id"]), get_weekday_at(at),
		posmod(at, GameConstants.HOURS_PER_DAY))


## Indica si en esta etapa un equipo necesita a su líder presente para rendir al 100 %.
func leaders_required() -> bool:
	return Company.stage >= StaffCatalog.get_role_min_stage(StaffCatalog.get_leader_role())


## Cuánto rinde un equipo a esa hora: 1, o teams.no_leader_factor si desde la etapa de
## los líderes no tiene a su líder presente.
func get_team_factor(team: Dictionary, at: int) -> float:
	var factor: float = 1.0
	if leaders_required() and not is_leader_present(team, at):
		factor = float(StaffCatalog.get_teams("no_leader_factor"))
	if is_manager_present(team, at):
		factor *= 1.0 + float(StaffCatalog.get_management("manager_bonus"))
	return factor


## Saca a un empleado de su equipo: vuelve al horario de su cargo.
func remove_from_team(employee_id: int) -> bool:
	if not _leave_team(employee_id):
		return false
	_schedules_changed()
	return true


## Cambia el turno de un equipo: hora de entrada, días (con al menos un día de
## descanso) y horas extra. Devuelve {"ok", "message"}.
func set_team_shift(team_id: int, start_hour: int, days: Array[int], overtime: int = 0) -> Dictionary:
	var team: Dictionary = get_team(team_id)
	if team.is_empty():
		return {"ok": false, "message": "Ese equipo ya no está."}
	var problem: String = shift_problem(start_hour, days, overtime)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var schedule: WorkSchedule = WorkSchedule.make_shift(start_hour, days, overtime)
	team["schedule"] = schedule.to_dict()
	# Un turno elegido a mano ya no sigue la plantilla.
	team["template_id"] = NO_TEMPLATE
	_schedules_changed()
	return {"ok": true, "message": "Turno de %s: %s." % [team["name"], schedule.describe()]}


## Plantilla con ese id, o vacío.
func get_template(template_id: int) -> Dictionary:
	for template: Dictionary in shift_templates:
		if template["id"] == template_id:
			return template
	return {}


## Plantilla que sigue un equipo, o vacío si tiene turno propio.
func get_template_of(team: Dictionary) -> Dictionary:
	return get_template(int(team.get("template_id", NO_TEMPLATE)))


## Equipos que siguen una plantilla.
func get_teams_with_template(template_id: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for team: Dictionary in teams:
		if int(team.get("template_id", NO_TEMPLATE)) == template_id:
			found.append(team)
	return found


## Crea una plantilla nueva con el turno por defecto y la devuelve.
func create_template() -> Dictionary:
	var template: Dictionary = {"id": _next_template_id,
		"name": "%s %d" % [StaffCatalog.get_teams("template_prefix"), _next_template_id],
		"schedule": WorkSchedule.make_shift(int(StaffCatalog.get_teams("default_start_hour")),
			StaffCatalog.get_default_team_days()).to_dict()}
	_next_template_id += 1
	shift_templates.append(template)
	EventBus.staff_changed.emit()
	return template


## Cambia el nombre de una plantilla. Devuelve {"ok", "message"}.
func rename_template(template_id: int, new_name: String) -> Dictionary:
	var template: Dictionary = get_template(template_id)
	if template.is_empty():
		return {"ok": false, "message": "Esa plantilla ya no está."}
	var clean: String = new_name.strip_edges()
	var max_length: int = int(StaffCatalog.get_teams("max_template_name"))
	if clean.is_empty():
		return {"ok": false, "message": "La plantilla necesita un nombre."}
	if clean.length() > max_length:
		return {"ok": false, "message": "El nombre puede tener hasta %d letras." % max_length}
	template["name"] = clean
	EventBus.staff_changed.emit()
	return {"ok": true, "message": "La plantilla se llama ahora %s." % clean}


## Borra una plantilla: sus equipos se quedan con el turno que tenían, como turno propio.
func delete_template(template_id: int) -> Dictionary:
	var template: Dictionary = get_template(template_id)
	if template.is_empty():
		return {"ok": false, "message": "Esa plantilla ya no está."}
	var users: Array[Dictionary] = get_teams_with_template(template_id)
	for team: Dictionary in users:
		team["template_id"] = NO_TEMPLATE
	shift_templates.erase(template)
	EventBus.staff_changed.emit()
	return {"ok": true, "message": "Borraste %s%s." % [template["name"],
		"" if users.is_empty() else "; sus equipos se quedan con ese turno como propio"]}


## Cambia el turno de una plantilla y el de todos los equipos que la siguen.
func set_template_shift(template_id: int, start_hour: int, days: Array[int], overtime: int = 0) -> Dictionary:
	var template: Dictionary = get_template(template_id)
	if template.is_empty():
		return {"ok": false, "message": "Esa plantilla ya no está."}
	var problem: String = shift_problem(start_hour, days, overtime)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var schedule: WorkSchedule = WorkSchedule.make_shift(start_hour, days, overtime)
	template["schedule"] = schedule.to_dict()
	var users: Array[Dictionary] = get_teams_with_template(template_id)
	for team: Dictionary in users:
		team["schedule"] = schedule.to_dict()
	_schedules_changed()
	var count: String = "" if users.is_empty() else " Cambia el turno de %d %s." % [users.size(),
		"equipo" if users.size() == 1 else "equipos"]
	return {"ok": true, "message": "%s: %s.%s" % [template["name"], schedule.describe(), count]}


## Hace que un equipo siga una plantilla, o NO_TEMPLATE para que se quede con su turno
## como propio. Devuelve {"ok", "message"}.
func set_team_template(team_id: int, template_id: int) -> Dictionary:
	var team: Dictionary = get_team(team_id)
	if team.is_empty():
		return {"ok": false, "message": "Ese equipo ya no está."}
	if template_id == NO_TEMPLATE:
		team["template_id"] = NO_TEMPLATE
		EventBus.staff_changed.emit()
		return {"ok": true, "message": "%s tiene turno propio: %s." % [team["name"], WorkSchedule.from_dict(team["schedule"]).describe()]}
	var template: Dictionary = get_template(template_id)
	if template.is_empty():
		return {"ok": false, "message": "Esa plantilla ya no está."}
	team["template_id"] = template_id
	team["schedule"] = (template["schedule"] as Dictionary).duplicate(true)
	_schedules_changed()
	return {"ok": true, "message": "%s sigue la plantilla %s: %s." % [team["name"], template["name"],
		WorkSchedule.from_dict(team["schedule"]).describe()]}


## Agenda de un día de la semana: una fila por equipo y por persona con horario propio,
## {"kind" ("team" o "employee"), "id", "label", "cells"}, con cells = 24 estados
## (AGENDA_OFF, AGENDA_WORK, AGENDA_LUNCH o AGENDA_GAP) de las horas que empiezan ese día.
func get_agenda(weekday: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for team: Dictionary in teams:
		var schedule: WorkSchedule = WorkSchedule.from_dict(team["schedule"])
		var cells: Array[String] = []
		for hour: int in range(GameConstants.HOURS_PER_DAY):
			var state: String = _agenda_state(schedule, weekday, hour)
			if state == AGENDA_WORK and _is_leader_gap(team, weekday, hour):
				state = AGENDA_GAP
			cells.append(state)
		rows.append({"kind": "team", "id": team["id"], "label": team["name"], "cells": cells})
	# Recepción (hito 36): las horas en que un cliente puede estar esperando.
	if Projects.visits_enabled():
		var cells: Array[String] = []
		var arrival: int = int(ContractCatalog.get_offers("arrival_hour"))
		var wait: int = Projects.get_visit_wait_hours()
		for hour: int in range(GameConstants.HOURS_PER_DAY):
			var state: String = AGENDA_OFF
			if hour >= arrival and hour < arrival + wait:
				state = AGENDA_WORK if is_reception_attended(weekday, hour) else AGENDA_GAP
			cells.append(state)
		rows.append({"kind": "reception", "id": 0, "label": "Recepción", "cells": cells})
	for employee: Dictionary in employees:
		if not has_own_schedule(employee):
			continue
		var schedule: WorkSchedule = get_schedule(employee)
		var cells: Array[String] = []
		for hour: int in range(GameConstants.HOURS_PER_DAY):
			cells.append(_agenda_state(schedule, weekday, hour))
		rows.append({"kind": "employee", "id": employee["id"], "label": employee["name"], "cells": cells})
	return rows


## Huecos de un día para el jugador: "Equipo 1 sin líder de 22:00 a 24:00".
func get_agenda_gaps(weekday: int) -> Array[String]:
	var gaps: Array[String] = []
	for row: Dictionary in get_agenda(weekday):
		var cells: Array = row["cells"]
		var hour: int = 0
		while hour < cells.size():
			if cells[hour] != AGENDA_GAP:
				hour += 1
				continue
			var start: int = hour
			while hour < cells.size() and cells[hour] == AGENDA_GAP:
				hour += 1
			if row["kind"] == "reception":
				gaps.append("nadie en la Recepción de %d:00 a %d:00" % [start, hour])
			else:
				gaps.append("%s sin líder de %d:00 a %d:00" % [row["label"], start, hour])
	return gaps


func _agenda_state(schedule: WorkSchedule, weekday: int, hour: int) -> String:
	if schedule.is_lunch(weekday, hour):
		return AGENDA_LUNCH
	return AGENDA_WORK if schedule.is_working(weekday, hour) else AGENDA_OFF


# Hueco: desde la etapa de los líderes, un equipo con miembros trabaja sin su líder.
func _is_leader_gap(team: Dictionary, weekday: int, hour: int) -> bool:
	if not leaders_required() or (team["members"] as Array).is_empty():
		return false
	return not is_leader_present(team, weekday * GameConstants.HOURS_PER_DAY + hour)


# Vuelve a las plantillas de data/staff.json.
func _reset_templates() -> void:
	shift_templates.clear()
	_next_template_id = 1
	for data: Dictionary in StaffCatalog.get_default_templates():
		shift_templates.append({"id": _next_template_id, "name": data["name"], "schedule": data["schedule"]})
		_next_template_id += 1


## Por qué no vale un turno, o "" si vale.
func shift_problem(start_hour: int, days: Array[int], overtime: int = 0) -> String:
	if start_hour < 0 or start_hour >= GameConstants.HOURS_PER_DAY:
		return "La hora de entrada tiene que estar entre 0 y 23."
	var max_overtime: int = int(StaffCatalog.get_overtime("max_hours"))
	if overtime < 0 or overtime > max_overtime:
		return "Las horas extra van de 0 a %d por día." % max_overtime
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


## Equipo de un empleado (como miembro o como líder), o vacío si no está en ninguno.
func get_team_of(employee_id: int) -> Dictionary:
	for team: Dictionary in teams:
		if (team["members"] as Array).has(employee_id) or int(team.get("leader_id", 0)) == employee_id:
			return team
	return {}


# Equipo de cada empleado que está en uno (como get_team_of), para revisar a todos de una
# vez sin recorrer los equipos por cada uno. Lleva la clave NO_TEAM_KEY para no quedar vacío.
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
	if int(team.get("leader_id", 0)) == employee_id:
		team["leader_id"] = 0
	(team["members"] as Array).erase(employee_id)
	return true


# Cambió quién trabaja a qué hora: los personajes revisan si tienen que llegar o irse.
func _schedules_changed() -> void:
	EventBus.staff_changed.emit()
	EventBus.presence_changed.emit()


## Empleado con ese id, o vacío.
func get_employee(employee_id: int) -> Dictionary:
	# Se pide muchas veces por hora: se busca en el índice y, si no coincide (alguien
	# entró o salió), se rehace.
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


## Candidato que está en entrevista ahora, o vacío.
func get_interviewed_now() -> Dictionary:
	return {} if interview.is_empty() else get_candidate(interview["candidate_id"])


## Puestos de trabajo que nadie ocupa (ver Workstations.find_all), donde trabaja ese
## cargo (un Área de trabajo si no se dice).
func get_free_workstations(role: String = "") -> Array[Dictionary]:
	var room_type: String = Workstations.WORK_AREA if role.is_empty() else StaffCatalog.get_workplace(role)
	return Workstations.find_free(OfficeState.furniture, OfficeState.rooms, room_type)


## Por qué no hay dónde contratar a alguien de ese cargo, o "" si hay lugar.
func get_station_problem(role: String) -> String:
	if not get_free_workstations(role).is_empty():
		return ""
	match StaffCatalog.get_workplace(role):
		Workstations.SINGLE_OFFICE:
			return NO_OFFICE_MESSAGE
		Workstations.RECEPTION:
			return NO_RECEPTION_MESSAGE
		Workstations.CLEANING_ROOM:
			return NO_CLOSET_MESSAGE
	return NO_STATION_MESSAGE


## Indica si a esa hora de ese día de la semana hay un recepcionista trabajando en su
## mostrador.
func is_reception_attended(weekday: int, hour: int) -> bool:
	for employee: Dictionary in employees:
		if employee["role"] == RECEPTIONIST_ROLE and has_working_station(employee) \
				and is_expected(employee_key(employee["id"]), weekday, hour):
			return true
	return false


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


## Claves (assigned_to) de quienes tienen un puesto que funciona. Para revisar a muchos de
## una vez sin buscar los puestos por cada uno.
func get_working_station_keys() -> Dictionary[String, bool]:
	var keys: Dictionary[String, bool] = {}
	for station: Dictionary in Workstations.find_all(OfficeState.furniture, OfficeState.rooms):
		var owner: String = String(OfficeState.furniture[station["chair"]]["assigned_to"])
		if not owner.is_empty():
			keys[owner] = true
	return keys


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
	return "%s · %s al mes" % [StaffCatalog.describe_title(vacancy["role"], vacancy["level"]),
		MoneyFormat.format(vacancy["salary"])]


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
## Qué hace un rasgo, armado con sus efectos de data/staff.json (y la competencia);
## "" si todavía no hace nada.
static func describe_trait(trait_id: String) -> String:
	var parts: Array[String] = []
	var percent: Callable = func(value: float) -> String:
		return "%s%d %%" % ["+" if value > 0.0 else "−", absi(roundi(value * 100.0))]
	var points: Variant = StaffCatalog.get_trait_effect(trait_id, "points")
	if points != null:
		parts.append("%s de puntos" % percent.call(float(points)))
	var night: Variant = StaffCatalog.get_trait_effect(trait_id, "night_points")
	if night != null:
		parts.append("%s de puntos de noche" % percent.call(float(night)))
	var day: Variant = StaffCatalog.get_trait_effect(trait_id, "day_points")
	if day != null:
		parts.append("%s de día" % percent.call(float(day)))
	if bool(StaffCatalog.get_trait_effect(trait_id, "night_mood_free", false)):
		parts.append("el turno de noche no le baja el ánimo")
	var bugs: Variant = StaffCatalog.get_trait_effect(trait_id, "bug_factor")
	if bugs != null:
		parts.append("%s de errores al programar" % percent.call(float(bugs) - 1.0))
	var find: Variant = StaffCatalog.get_trait_effect(trait_id, "find_factor")
	if find != null:
		parts.append("encuentra %s de errores al probar" % percent.call(float(find) - 1.0))
	var team_mood: Variant = StaffCatalog.get_trait_effect(trait_id, "team_mood")
	if team_mood != null:
		parts.append("+%d al ánimo de su equipo" % int(team_mood))
	var mentor: Variant = StaffCatalog.get_trait_effect(trait_id, "mentor_points")
	if mentor != null:
		var levels: Array[String] = []
		for level: Variant in StaffCatalog.get_trait_effect(trait_id, "mentor_levels", []):
			levels.append(StaffCatalog.get_level_name(String(level)))
		parts.append("%s de su equipo rinden %s si está presente y ascienden con %d contrato menos" % [
			" y ".join(levels), percent.call(float(mentor)), int(StaffCatalog.get_trait_effect(trait_id, "mentor_projects", 0))])
	var late: Variant = StaffCatalog.get_trait_effect(trait_id, "late_chance")
	if late != null:
		parts.append("%d %% de llegar una hora tarde" % roundi(float(late) * 100.0))
	var absent: Variant = StaffCatalog.get_trait_effect(trait_id, "absent_chance")
	if absent != null:
		parts.append("%d %% de faltar el día" % roundi(float(absent) * 100.0))
	var no_coffee: Variant = StaffCatalog.get_trait_effect(trait_id, "no_coffee_points")
	if no_coffee != null:
		parts.append("sin cafetera en la Sala de descanso %s de puntos" % percent.call(float(no_coffee)))
	var coffee_energy: Variant = StaffCatalog.get_trait_effect(trait_id, "coffee_energy")
	if coffee_energy != null:
		parts.append("con ella +%d de energía por hora" % int(coffee_energy))
	var wait: Variant = StaffCatalog.get_trait_effect(trait_id, "promotion_wait_days")
	if wait != null:
		parts.append("si puede ascender y pasan %d días sin ascenderlo, %d de ánimo" % [int(wait),
			int(StaffCatalog.get_trait_effect(trait_id, "promotion_wait_mood", 0))])
	var quit_factor: Variant = StaffCatalog.get_trait_effect(trait_id, "quit_days_factor")
	if quit_factor != null:
		parts.append("aguanta %s más días mal antes de renunciar" % ("el doble de" if is_equal_approx(float(quit_factor), 2.0) else "%.1f veces" % float(quit_factor)))
	var offers: float = float((StaffCatalog.get_competition("traits") as Dictionary).get(trait_id, 1.0))
	if offers < 1.0:
		parts.append("otras empresas lo tientan menos")
	elif offers > 1.0:
		parts.append("otras empresas lo tientan más")
	return "; ".join(parts)


static func describe_known_traits(person: Dictionary) -> String:
	var names: Array[String] = []
	for trait_id: String in person.get("known_traits", []):
		names.append(StaffCatalog.get_trait_name(trait_id))
	return "" if names.is_empty() else "Rasgos: %s" % ", ".join(names)


## "Programador Junior · $1,200 al mes" para un empleado.
static func describe_employee(employee: Dictionary) -> String:
	return "%s · %s al mes" % [StaffCatalog.describe_title(employee["role"], employee["level"]),
		MoneyFormat.format(employee["salary"])]


func _on_hour_changed(hour: int) -> void:
	_update_energy()
	_update_dirt()
	_check_arrivals()
	_check_bathrooms()
	_decide_breaks()
	_note_presence()
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
	_collect_vending()
	if GameConstants.PAYROLL_DAYS.has(day):
		_run_payroll()
	_update_promotion_waits()
	_update_morale()
	_discover_traits()
	_accountant_warning(day)


## Indica si la empresa tiene al menos un contador (hito 37).
func has_accountant() -> bool:
	var role: String = String(StaffCatalog.get_accounting("role"))
	for employee: Dictionary in employees:
		if employee["role"] == role:
			return true
	return false


## Cuánto baja el mantenimiento (0.1 = 10 %): el descuento del contador por el factor
## de Administración, o 0 sin contador.
func get_maintenance_discount() -> float:
	if not has_accountant():
		return 0.0
	return float(StaffCatalog.get_accounting("maintenance_discount")) * get_department_factor("administration") * get_printer_factor()


## Cuánto baja la tasa mensual de un préstamo nuevo (0.01 = 1 punto), o 0 sin contador.
func get_loan_rate_discount() -> float:
	if not has_accountant():
		return 0.0
	return float(StaffCatalog.get_accounting("loan_rate_discount")) * get_department_factor("administration") * get_printer_factor()


## Cuánto valen los efectos del contador (hito 55): accountant_boost de la impresora si
## hay una en el Área de trabajo donde está la silla de algún contador; si no, 1.
func get_printer_factor() -> float:
	var role: String = String(StaffCatalog.get_accounting("role"))
	var best: float = 1.0
	for employee: Dictionary in employees:
		if employee["role"] != role:
			continue
		var room: Dictionary = get_workplace_room(employee_key(int(employee["id"])))
		if room.is_empty() or room["type"] != Workstations.WORK_AREA:
			continue
		for item: Dictionary in OfficeState.furniture:
			var boost: float = FurnitureCatalog.get_number(item["id"], "accountant_boost")
			if boost > best and (room["cells"] as Array).has(item["cell"]):
				best = boost
	return best


## Lo que costaría la nómina del día de pago que está a days_ahead días: lo ganado hasta
## hoy, lo de esos días, horas extra y lo que ya se debe.
func estimate_payroll(days_ahead: int) -> int:
	var total: int = 0
	for employee: Dictionary in employees:
		total += get_firing_cost(employee) + roundi(int(employee["salary"]) * days_ahead / float(GameConstants.DAYS_PER_MONTH))
	return total


# El contador avisa warning_days días antes de cada nómina y de cada día 1 si con el
# saldo de hoy no alcanza para todo lo que se paga hasta ese día.
func _accountant_warning(day: int) -> void:
	if not has_accountant():
		return
	var ahead: int = int(StaffCatalog.get_accounting("warning_days"))
	var target: int = (day - 1 + ahead) % GameConstants.DAYS_PER_MONTH + 1
	if not GameConstants.PAYROLL_DAYS.has(target) and target != 1:
		return
	var payroll_day: int = -1
	for payday: int in GameConstants.PAYROLL_DAYS:
		var until: int = posmod(payday - day, GameConstants.DAYS_PER_MONTH)
		if until > 0 and until <= ahead:
			payroll_day = until
	var due: int = 0
	var what: Array[String] = []
	if payroll_day > 0 and not employees.is_empty():
		due += estimate_payroll(payroll_day)
		what.append("la nómina")
	if target == 1:
		due += Bank.get_due_on_first() + Economy.get_monthly_maintenance() + Economy.get_monthly_server_cost()
		what.append("las cuotas y el mantenimiento")
	if due <= 0 or Economy.balance >= due:
		return
	EventBus.send_notice(EventBus.target_menu("bank"), "El contador avisa: el día %d no alcanza para %s (faltan %s)." % [
		target, " ni ".join(what), MoneyFormat.format(due - Economy.balance)])


# Cada hora que termina: quien trabajó en su puesto ensucia su habitación y el personal
# de limpieza en su turno limpia la más sucia.
func _update_dirt() -> void:
	var ended: int = _absolute_hour() - 1
	var weekday: int = get_weekday_at(ended)
	var hour: int = posmod(ended, GameConstants.HOURS_PER_DAY)
	var cleaner_role: String = String(StaffCatalog.get_cleaning("role"))
	var cleaners: Array[Dictionary] = []
	var stations: Dictionary[String, bool] = get_working_station_keys()
	var team_map: Dictionary[int, Dictionary] = _get_team_map()
	var seats: Dictionary[String, Dictionary] = {}
	for item: Dictionary in OfficeState.furniture:
		var owner: String = String(item["assigned_to"])
		if not owner.is_empty() and not seats.has(owner):
			seats[owner] = item
	for employee: Dictionary in employees:
		if employee["role"] == cleaner_role:
			if stations.has(employee_key(employee["id"])) and _is_working_at(employee, weekday, hour, team_map):
				cleaners.append(employee)
	var changed: bool = false
	var was_dirty: Array[bool] = []
	for room: Dictionary in OfficeState.rooms:
		was_dirty.append(OfficeState.is_room_dirty(room))
	# Personas-hora por habitación: se suman y se ensucia cada habitación una vez.
	var room_map: Dictionary[Vector2i, int] = OfficeState.get_room_index_map()
	var people: Dictionary[int, int] = {}
	var seat: Dictionary = seats.get("ceo", {})
	if is_expected("ceo", weekday, hour) and not seat.is_empty():
		var ceo_room: int = room_map.get(seat["cell"], -1)
		if ceo_room >= 0:
			people[ceo_room] = people.get(ceo_room, 0) + 1
	for employee: Dictionary in employees:
		if employee["role"] == cleaner_role or not _is_working_at(employee, weekday, hour, team_map):
			continue
		seat = seats.get(employee_key(employee["id"]), {})
		if seat.is_empty():
			continue
		var room_index: int = room_map.get(seat["cell"], -1)
		if room_index >= 0:
			people[room_index] = people.get(room_index, 0) + 1
	for room_index: int in people:
		OfficeState.add_dirt(room_index, float(people[room_index]))
		changed = true
	var amount: float = float(StaffCatalog.get_cleaning("clean_per_hour")) * get_department_factor("administration")
	for _cleaner: Dictionary in cleaners:
		var dirtiest: int = OfficeState.get_dirtiest_room()
		if dirtiest >= 0:
			OfficeState.clean_room(dirtiest, amount)
			changed = true
	if not changed:
		return
	for index: int in range(OfficeState.rooms.size()):
		if not was_dirty[index] and OfficeState.is_room_dirty(OfficeState.rooms[index]):
			EventBus.send_notice(EventBus.target_room(OfficeState.rooms[index]["cells"][0]), "%s está sucia: baja el ánimo de quienes trabajan ahí." % RoomCatalog.get_display_name(OfficeState.rooms[index]["type"]))
	EventBus.dirt_changed.emit()


## Habitación donde está limpiando ahora alguien de limpieza (la más sucia), o -1 si no
## está en su turno o todo está limpio.
func get_cleaning_room(employee: Dictionary) -> int:
	if employee["role"] != String(StaffCatalog.get_cleaning("role")) or not is_expected_now(employee_key(employee["id"])):
		return -1
	return OfficeState.get_dirtiest_room()


## Indica si la habitación del puesto de alguien está sucia.
## Habitación donde está la silla de alguien, o vacío.
func get_workplace_room(key: String) -> Dictionary:
	var seat: Dictionary = _seat_of(key)
	if seat.is_empty():
		return {}
	var room_index: int = _room_map().get(seat["cell"], -1)
	return OfficeState.rooms[room_index] if room_index >= 0 else {}


## Ambiente de la habitación donde trabaja alguien (0 sin puesto; hito 45).
func get_ambiance(key: String) -> int:
	var room: Dictionary = get_workplace_room(key)
	return 0 if room.is_empty() else int(_ambiance_detail(room)["value"])


# Ambiance.get_detail de una habitación con los muebles de ahora, guardado mientras la
# habitación y los muebles no cambien (las metas de ánimo y estrés lo piden por persona).
func _ambiance_detail(room: Dictionary) -> Dictionary:
	var furniture_hash: int = int(_seat_lookup_cache["furniture_hash"]) if not _seat_lookup_cache.is_empty() \
		else OfficeState.furniture.hash()
	var windows: int = OfficeState.count_room_windows(room)
	var key: int = [room.hash(), furniture_hash, windows].hash()
	if not _ambiance_cache.has(key):
		if _ambiance_cache.size() >= AMBIANCE_CACHE_SIZE:
			_ambiance_cache.clear()
		_ambiance_cache[key] = Ambiance.get_detail(room, OfficeState.furniture, windows)
	return _ambiance_cache[key]


# El mueble asignado a alguien (OfficeState.find_furniture_assigned_to), del recorrido de
# _update_morale si está en curso.
func _seat_of(key: String) -> Dictionary:
	if _seat_lookup_cache.is_empty():
		return OfficeState.find_furniture_assigned_to(key)
	return _seat_lookup_cache["seats"].get(key, {})


# Arma _seat_lookup_cache: el primer mueble asignado a cada uno, el escritorio de cada
# puesto ocupado y el hash de los muebles. Lo que cambia mientras se recorre (alguien que
# se va libera su silla) no lo usa nadie más: el ambiente no mira quién ocupa qué.
func _build_seat_lookup() -> void:
	var furniture: Array[Dictionary] = OfficeState.furniture
	var seats: Dictionary[String, Dictionary] = {}
	for item: Dictionary in furniture:
		var owner: String = String(item["assigned_to"])
		if not owner.is_empty() and not seats.has(owner):
			seats[owner] = item
	var desks: Dictionary[String, Dictionary] = {}
	for station: Dictionary in Workstations.find_all(furniture, OfficeState.rooms):
		var owner: String = String(furniture[station["chair"]]["assigned_to"])
		if not desks.has(owner):
			desks[owner] = furniture[station["desk"]]
	_seat_lookup_cache = {"seats": seats, "desks": desks, "furniture_hash": furniture.hash(),
		"room_map": OfficeState.get_room_index_map(), "break_mood": OfficeState.get_break_room_effect("break_mood")}


# OfficeState.get_room_index_map, del recorrido de _update_morale si está en curso.
func _room_map() -> Dictionary:
	return _seat_lookup_cache["room_map"] if not _seat_lookup_cache.is_empty() else OfficeState.get_room_index_map()


## Lo que suman a la meta de ánimo de todos el dispensador, el ping pong y la máquina
## expendedora de la Sala de descanso (hito 54; uno de cada uno).
func get_break_mood() -> float:
	if not _seat_lookup_cache.is_empty():
		return float(_seat_lookup_cache["break_mood"])
	return OfficeState.get_break_room_effect("break_mood")


## Lo que suma a la meta de ánimo el escritorio del puesto de alguien (el amplio, hito 46).
func get_desk_mood(key: String) -> int:
	var desk: Dictionary = _seat_lookup_cache["desks"].get(key, {}) if not _seat_lookup_cache.is_empty() \
		else Workstations.station_desk_of(OfficeState.furniture, OfficeState.rooms, key)
	return 0 if desk.is_empty() else FurnitureCatalog.get_mood_bonus(desk["id"])


## Energía que pierde alguien por hora trabajada: la de su silla si tiene una propia (la
## ergonómica, hito 46) o la de data/staff.json.
func get_work_energy(key: String) -> int:
	var seat: Dictionary = OfficeState.find_furniture_assigned_to(key)
	return _work_energy_of(seat)


func _work_energy_of(seat: Dictionary) -> int:
	var own: int = 0 if seat.is_empty() else FurnitureCatalog.get_work_energy(seat["id"])
	return own if own != 0 else int(StaffCatalog.get_workday("energy_per_work_hour"))


func works_in_dirty_room(key: String) -> bool:
	var seat: Dictionary = _seat_of(key)
	if seat.is_empty():
		return false
	var room_index: int = _room_map().get(seat["cell"], -1)
	return room_index >= 0 and OfficeState.is_room_dirty(OfficeState.rooms[room_index])


# Anota lo ganado por cada uno hasta hoy como deuda y trata de pagarla toda. Si no
# alcanza, la deuda queda y baja el ánimo de todos.
func _run_payroll() -> void:
	if employees.is_empty():
		return
	var today: int = GameClock.get_day_count()
	for employee: Dictionary in employees:
		var overtime: int = roundi(float(employee.get("overtime_pay", 0.0)))
		var night: int = roundi(float(employee.get("night_pay", 0.0)))
		employee["owed"] = int(employee["owed"]) + get_earned(employee) + overtime + night
		employee["owed_overtime"] = int(employee.get("owed_overtime", 0)) + overtime
		employee["owed_night"] = int(employee.get("owed_night", 0)) + night
		employee["overtime_pay"] = 0.0
		employee["night_pay"] = 0.0
		employee["paid_until"] = today
		employee["carry"] = 0
	var total: int = get_total_owed()
	if _pay_debt_if_possible():
		EventBus.payment_recorded.emit(CONCEPT_PAYROLL, true)
		return
	# Antes de castigar se pregunta si alguien la cubre (el préstamo de emergencia).
	# Se marca antes de preguntar: la respuesta puede llegar dentro de la misma señal.
	var response: Dictionary = {"held": false}
	payroll_held = true
	EventBus.payroll_short.emit(total - Economy.balance, response)
	if bool(response["held"]):
		return
	payroll_held = false
	_payroll_unpaid(total)


# La nómina quedó sin pagar: es un atraso y baja el ánimo de todos.
func _payroll_unpaid(total: int) -> void:
	EventBus.payment_recorded.emit(CONCEPT_PAYROLL, false)
	for employee: Dictionary in employees:
		_change_mood(employee, StaffCatalog.get_payroll("unpaid_mood"))
	EventBus.staff_changed.emit()
	EventBus.send_notice(EventBus.target_menu("bank"), "No alcanza el dinero para la nómina: se deben %s. Se pagará apenas alcance." % MoneyFormat.format(total))


# Respuesta al préstamo de emergencia: aceptado, la nómina ya se pagó con él y cuenta a
# tiempo; rechazado, queda debida como cualquier nómina que no alcanza.
func _on_emergency_loan_resolved(_accepted: bool) -> void:
	if not payroll_held:
		return
	payroll_held = false
	if get_total_owed() == 0:
		EventBus.payment_recorded.emit(CONCEPT_PAYROLL, true)
	else:
		_payroll_unpaid(get_total_owed())


# Paga toda la deuda de nómina si alcanza el saldo. Devuelve true si pagó.
func _pay_debt_if_possible() -> bool:
	var total: int = get_total_owed()
	if total <= 0 or not Economy.can_afford(total):
		return false
	var overtime: int = 0
	var night: int = 0
	for employee: Dictionary in employees:
		overtime += int(employee.get("owed_overtime", 0))
		night += int(employee.get("owed_night", 0))
		employee["owed"] = 0
		employee["owed_overtime"] = 0
		employee["owed_night"] = 0
	# Cada parte con su concepto: sueldos, horas extra y recargo nocturno.
	if total - overtime - night > 0:
		Economy.spend(total - overtime - night, CONCEPT_PAYROLL)
	if overtime > 0:
		Economy.spend(overtime, CONCEPT_OVERTIME)
	if night > 0:
		Economy.spend(night, CONCEPT_NIGHT)
	EventBus.staff_changed.emit()
	EventBus.send_notice(EventBus.target_menu("bank"), "Nómina pagada: %s." % MoneyFormat.format(total))
	return true


func _change_mood(employee: Dictionary, change: int) -> void:
	employee["mood"] = clampi(int(employee["mood"]) + change, 0, 100)


# La energía de cada empleado cambia según si la hora que acaba de terminar era de
# trabajo o de descanso; si era de trabajo, suma sus horas extra y recargo nocturno.
func _update_energy() -> void:
	if employees.is_empty():
		return
	var ended: int = _absolute_hour() - 1
	@warning_ignore("integer_division")
	var weekday: int = (ended / GameConstants.HOURS_PER_DAY) % GameConstants.DAYS_PER_WEEK
	var hour: int = posmod(ended, GameConstants.HOURS_PER_DAY)
	var seats: Dictionary[String, Dictionary] = {}
	for item: Dictionary in OfficeState.furniture:
		var owner: String = String(item["assigned_to"])
		if not owner.is_empty() and not seats.has(owner):
			seats[owner] = item
	var rest: int = int(StaffCatalog.get_workday("energy_per_rest_hour"))
	var pay_factor: float = float(StaffCatalog.get_overtime("pay_factor"))
	var night_bonus: float = float(StaffCatalog.get_overtime("night_bonus"))
	var team_map: Dictionary[int, Dictionary] = _get_team_map()
	var coffee: bool = has_coffee()
	var lunch_inside: Dictionary[String, bool] = get_lunch_inside(ended)
	var coffee_rest: int = int(StaffCatalog.get_breaks("coffee_energy")) if coffee else 0
	var lunch_rest: int = roundi(rest * StaffCatalog.get_lunch("energy_factor")) + coffee_rest
	var on_break: Array[String] = get_breaks(ended)
	var break_rest: int = int(StaffCatalog.get_breaks("energy")) + coffee_rest
	for employee: Dictionary in employees:
		# Lo mismo que is_expected, con el horario a mano para las horas extra (que se
		# pagan aunque llegue tarde o falte).
		var schedule: WorkSchedule = _cached_schedule_in(employee, team_map.get(int(employee["id"]), {}))
		var working: bool = schedule.is_working(weekday, hour) and not schedule.is_lunch(weekday, hour)
		if working:
			var hour_pay: float = get_hour_pay(employee)
			if schedule.is_overtime_hour(schedule.get_shift_hour(weekday, hour)):
				employee["overtime_pay"] = float(employee.get("overtime_pay", 0.0)) + hour_pay * pay_factor
			if WorkSchedule.is_night_hour(hour):
				employee["night_pay"] = float(employee.get("night_pay", 0.0)) + hour_pay * night_bonus
		var present: bool = working and not is_missing(employee, weekday, hour)
		var change: int = rest
		if lunch_inside.has(employee_key(employee["id"])):
			# Almorzó dentro (hito 53): descansa el doble, y con café un poco más (hito 54).
			change = lunch_rest
		elif on_break.has(employee_key(employee["id"])):
			# Pausa en la Sala de descanso (hito 54).
			change = break_rest
		elif present:
			change = _work_energy_of(seats.get(employee_key(employee["id"]), {}))
			if coffee:
				change += int(_trait_value(employee, "coffee_energy"))
		employee["energy"] = clampi(int(employee["energy"]) + change, 0, 100)
		employee["min_energy"] = mini(int(employee.get("min_energy", 100)), int(employee["energy"]))
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
	if String(interview.get("by", "ceo")) == "ceo":
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
	var station: Dictionary = get_free_workstations(candidate["role"])[0]
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
	_add_morale_fields(employee, {})
	employees.append(employee)
	hired_count += 1
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


## Contrata a alguien de ese cargo y nivel sin vacante ni entrevista, con el sueldo de
## la tabla (lo usa la empresa con la que empieza la partida). Devuelve el empleado, o
## vacío si el cargo no se puede contratar o no tiene puesto libre.
func hire_directly(role: String, level: String) -> Dictionary:
	if not role_problem(role).is_empty() or not get_station_problem(role).is_empty():
		return {}
	if not StaffCatalog.has_levels(role):
		level = StaffCatalog.get_level_ids()[-1]
	var candidate: Dictionary = _make_candidate({"role": role, "level": level}, GameClock.get_day_count())
	_hire(candidate, StaffCatalog.get_salary(role, level))
	return get_employee(candidate["id"])


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


# Cuántos candidatos llegan hoy a una vacante. El primer día (hito 56) llega la primera
# tanda según las estrellas, más uno con publicidad; con el premio, uno más cada día.
func _roll_arrivals(vacancy: Dictionary, today: int) -> int:
	var first: bool = not bool(vacancy.get("first_done", true))
	vacancy["first_done"] = true
	if company_hiring_enabled:
		var extra: int = 1 if today < award_until else 0
		if first:
			return get_first_batch() + (1 if today < int(vacancy["publicity_until"]) else 0) + extra
		return _roll_daily(vacancy, today) + extra
	return _roll_daily(vacancy, today)


func _roll_daily(vacancy: Dictionary, today: int) -> int:
	var key: String = "arrivals_with_publicity" if today < int(vacancy["publicity_until"]) else "arrivals"
	var arrivals: Vector2i = StaffCatalog.get_hiring_range(key)
	var count: int = _rng.randi_range(arrivals.x, arrivals.y)
	# Un sueldo bastante mejor que el de la tabla atrae a veces a uno más.
	var table: int = StaffCatalog.get_salary(vacancy["role"], vacancy["level"])
	if vacancy["salary"] >= table * float(StaffCatalog.get_hiring("high_offer_ratio")) \
			and _rng.randf() < float(StaffCatalog.get_hiring("high_offer_extra_chance")):
		count += 1
	return count


## Cuántos llegan el primer día de una vacante: first_batch + first_batch_per_star por
## estrella entera sobre neutral_stars (1★ = 1, 3★ = 3, 5★ = 5), al menos first_batch_min.
func get_first_batch() -> int:
	var stars: int = floori(Projects.reputation)
	return maxi(int(StaffCatalog.get_hiring("first_batch_min")), int(StaffCatalog.get_hiring("first_batch"))
		+ int(StaffCatalog.get_hiring("first_batch_per_star")) * (stars - int(StaffCatalog.get_hiring("neutral_stars"))))


## Calidad de los candidatos de una vacante, entre −max_quality y +max_quality: el sueldo
## ofrecido frente al de la tabla (quality_per_salary por cada 100 % de más o de menos) y el
## ambiente medio de las Áreas de trabajo (quality_per_ambiance por punto).
func get_candidate_quality(role: String, level: String, salary: int) -> float:
	var table: int = maxi(1, StaffCatalog.get_salary(role, level))
	var quality: float = (float(salary) / table - 1.0) * float(StaffCatalog.get_hiring("quality_per_salary")) \
		+ get_work_area_ambiance() * float(StaffCatalog.get_hiring("quality_per_ambiance"))
	var limit: float = float(StaffCatalog.get_hiring("max_quality"))
	return clampf(quality, -limit, limit)


## Dónde cae una habilidad dentro de su rango (0 a 1) con un azar roll de 0 a 1: con calidad
## positiva el rango se corre hacia arriba (0.5 = solo la mitad de arriba), con negativa hacia abajo.
static func quality_position(roll: float, quality: float) -> float:
	return clampf(roll * (1.0 - absf(quality)) + maxf(quality, 0.0), 0.0, 1.0)


## Ambiente medio de las Áreas de trabajo (0 sin ninguna).
func get_work_area_ambiance() -> float:
	var total: int = 0
	var count: int = 0
	for room: Dictionary in OfficeState.rooms:
		if room["type"] == Workstations.WORK_AREA:
			total += int(_ambiance_detail(room)["value"])
			count += 1
	return float(total) / count if count > 0 else 0.0


## Lo que se espera de una vacante con ese sueldo, para el formulario de Personal:
## «Llegan 3 el primer día (3 ★) · habilidades +20 % (sueldo +10 %, ambiente +4)».
func describe_hiring_outlook(role: String, level: String, salary: int) -> String:
	var quality: int = roundi(get_candidate_quality(role, level, salary) * 100.0)
	var text: String = "Llegan %d el primer día (%d ★) · habilidades %s" % [get_first_batch(), floori(Projects.reputation),
		"normales" if quality == 0 else ("%+d %%" % quality).replace("-", "−")]
	var parts: Array[String] = []
	var table: int = maxi(1, StaffCatalog.get_salary(role, level))
	var salary_diff: int = roundi((float(salary) / table - 1.0) * 100.0)
	if salary_diff != 0:
		parts.append(("sueldo %+d %%" % salary_diff).replace("-", "−"))
	var ambiance: int = roundi(get_work_area_ambiance())
	if ambiance != 0:
		parts.append(("ambiente %+d" % ambiance).replace("-", "−"))
	if not parts.is_empty():
		text += " (%s)" % ", ".join(parts)
	if GameClock.get_day_count() < award_until:
		text += " · premio: +1 por día"
	return text


## Suma un candidato a cada vacante cada día durante days días (el «Premio de la industria»).
func boost_candidates(days: int) -> void:
	award_until = maxi(award_until, next_arrival_day() + days)


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
	var quality: float = 0.0
	if company_hiring_enabled and vacancy.has("salary"):
		quality = get_candidate_quality(role, level, int(vacancy["salary"]))
	for skill: String in StaffCatalog.get_skill_ids():
		var skill_range: Vector2i = main_range if skill == main_skill else other_range
		var value: int = _rng.randi_range(skill_range.x, skill_range.y) if not company_hiring_enabled \
			else skill_range.x + roundi((skill_range.y - skill_range.x) * quality_position(_rng.randf(), quality))
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
		"shift_templates": shift_templates.duplicate(true), "next_template_id": _next_template_id,
		"rng_state": str(_rng.state), "hired_count": hired_count, "payroll_held": payroll_held,
		"coffee_out_day": coffee_out_day, "broken_toilets": broken_toilets, "bathroom_short_day": bathroom_short_day,
		"breaks": _export_breaks(), "present_today": present_today.keys(), "award_until": award_until}


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
			"candidates": candidates, "first_done": bool(saved.get("first_done", true)),
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
		_add_morale_fields(employee, saved)
		employees.append(employee)
	# Dos ejecutivos no dirigen el mismo departamento: el segundo queda sin ninguno.
	var directed: Dictionary[String, bool] = {}
	for executive: Dictionary in get_executives():
		var department: String = executive["department"]
		if directed.has(department) or not StaffCatalog.get_department_ids().has(department):
			executive["department"] = ""
		else:
			directed[department] = true
	# Un líder cuyo gerente ya no está (o no es gerente) queda a cargo del CEO.
	for leader: Dictionary in get_leaders():
		if not is_manager(get_employee(int(leader["manager_id"]))):
			leader["manager_id"] = 0
	var saved_interview: Dictionary = state.get("interview", {})
	interview = {}
	if saved_interview.has("candidate_id"):
		interview = {"candidate_id": int(saved_interview["candidate_id"]),
			"ends_at": int(saved_interview.get("ends_at", 0)), "by": String(saved_interview.get("by", "ceo"))}
		# Si la hacía un ejecutivo que ya no está, se corta.
		if interview["by"] != "ceo" and get_employee_by_key(interview["by"]).is_empty():
			interview = {}
	_drop_missing_interview()
	# Antes del hito 35 no había plantillas: empieza con las de data/staff.json.
	if state.has("shift_templates"):
		shift_templates.clear()
		var top: int = 0
		for saved: Dictionary in state["shift_templates"]:
			var template_id: int = int(saved["id"])
			top = maxi(top, template_id)
			shift_templates.append({"id": template_id, "name": String(saved.get("name", "%s %d" % [
				StaffCatalog.get_teams("template_prefix"), template_id])),
				"schedule": WorkSchedule.from_dict(saved.get("schedule", {})).to_dict()})
		_next_template_id = maxi(int(state.get("next_template_id", top + 1)), top + 1)
	else:
		_reset_templates()
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
		# Antes del hito 31 no había líderes; tiene que seguir contratado, ser líder y no
		# estar en otro equipo.
		var leader_id: int = int(saved.get("leader_id", 0))
		var leader: Dictionary = get_employee(leader_id)
		if leader.is_empty() or not is_leader(leader) or not get_team_of(leader_id).is_empty():
			leader_id = 0
		# Un equipo de una plantilla que ya no está se queda con su turno como propio.
		var template: Dictionary = get_template(int(saved.get("template_id", NO_TEMPLATE)))
		if not template.is_empty():
			schedule = template["schedule"]
		teams.append({"id": team_id, "name": String(saved.get("name", "%s %d" % [StaffCatalog.get_teams("name_prefix"), team_id])),
			"members": members, "leader_id": leader_id, "schedule": WorkSchedule.from_dict(schedule).to_dict(),
			"template_id": NO_TEMPLATE if template.is_empty() else int(template["id"])})
	_next_team_id = int(state.get("next_team_id", 1))
	payroll_held = bool(state.get("payroll_held", false))
	coffee_out_day = int(state.get("coffee_out_day", NO_COFFEE_OUT))
	award_until = int(state.get("award_until", 0))
	broken_toilets = int(state.get("broken_toilets", 0))
	bathroom_short_day = int(state.get("bathroom_short_day", NO_SHORT_DAY))
	breaks.clear()
	for saved: Variant in state.get("breaks", []):
		var keys: Array[String] = []
		for key: Variant in (saved as Dictionary).get("keys", []):
			keys.append(String(key))
		breaks[int((saved as Dictionary).get("hour", 0))] = keys
	present_today.clear()
	for key: Variant in state.get("present_today", []):
		present_today[String(key)] = true
	_last_interview_end = NO_FIRING
	ceo_at_work = bool(state.get("ceo_at_work", true))
	last_firing_day = int(state.get("last_firing_day", NO_FIRING))
	hired_count = int(state.get("hired_count", employees.size()))
	_next_id = int(state.get("next_id", 1))
	var rng_state: String = String(state.get("rng_state", ""))
	if rng_state.is_valid_int():
		_rng.state = rng_state.to_int()
	else:
		_rng.randomize()
	EventBus.staff_changed.emit()


# Los datos del hito 19 de un empleado (desde una partida guardada o nuevos).
func _add_morale_fields(employee: Dictionary, saved: Dictionary) -> void:
	employee["carry"] = int(saved.get("carry", 0))
	employee["own_schedule"] = bool(saved.get("own_schedule", false))
	employee["overtime_pay"] = float(saved.get("overtime_pay", 0.0))
	employee["night_pay"] = float(saved.get("night_pay", 0.0))
	# Lo debido de horas extra y noche nunca pasa de lo debido en total.
	employee["owed_overtime"] = clampi(int(saved.get("owed_overtime", 0)), 0, int(employee["owed"]))
	employee["owed_night"] = clampi(int(saved.get("owed_night", 0)), 0, int(employee["owed"]) - int(employee.get("owed_overtime", 0)))
	employee["bad_days"] = int(saved.get("bad_days", 0))
	employee["quit_day"] = int(saved.get("quit_day", NO_QUIT))
	employee["min_energy"] = int(saved.get("min_energy", employee["energy"]))
	employee["projects_worked"] = int(saved.get("projects_worked", 0))
	# Historial (hito 51): errores que generó al programar, llegadas tarde, ausencias y
	# jornadas a tiempo; missing_from/missing_until son las horas (absolutas) en que falta;
	# promotion_ready_day, desde cuándo puede ascender (para el ambicioso).
	for counter: String in ["bugs_caused", "late_count", "absent_count", "on_time_count"]:
		employee[counter] = int(saved.get(counter, 0))
	employee["missing_from"] = int(saved.get("missing_from", NOT_MISSING))
	employee["missing_until"] = int(saved.get("missing_until", NOT_MISSING))
	employee["promotion_ready_day"] = int(saved.get("promotion_ready_day", NOT_MISSING))
	if is_leader(employee):
		employee["manager_id"] = int(saved.get("manager_id", 0))
	if is_executive(employee):
		# Al contratarlo dirige el primer departamento libre.
		employee["department"] = String(saved["department"]) if saved.has("department") else _free_department()
	employee["last_raise_day"] = int(saved.get("last_raise_day", employee.get("hired_day", 0)))
	var offer: Dictionary = saved.get("outside_offer", {})
	employee["outside_offer"] = {} if not offer.has("salary") else {"salary": int(offer["salary"]),
		"until_day": int(offer.get("until_day", 0))}
	var request: Dictionary = saved.get("raise_request", {})
	employee["raise_request"] = {} if not request.has("amount") else {"amount": int(request["amount"]),
		"until_day": int(request.get("until_day", 0))}


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
