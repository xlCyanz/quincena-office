# Personal, capa 6: vacantes, candidatos, entrevistas, citas y contratación.
extends "res://scripts/staff/staff_people.gd"


## Publica una vacante; con publicidad la cobra y falla sin dinero. Devuelve {"ok", "message", "id"}.
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


## Ofrece un sueldo: desde lo pedido lo contrata, desde counter_offer_ratio contraoferta y debajo
## rechaza y se va. Pide un puesto libre. Devuelve {"ok", "result", "message"}, result "hired",
## "counter", "rejected" o "".
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


## Empieza ya la entrevista con el CEO o, con by_executive, el ejecutivo de Administración.
func start_interview(candidate_id: int, by_executive: bool = false) -> Dictionary:
	var problem: String = interview_problem(candidate_id, by_executive)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var by: String = _interviewer_key(by_executive)
	_begin_interview(candidate_id, by)
	return {"ok": true, "message": "%s entrevista a %s hasta las %s." % [_interviewer_name(by),
		get_candidate(candidate_id)["name"], format_clock_minute(int(interview["ends_at"]))]}


## Cita la entrevista para el próximo día en que trabaja quien la hace, a su entrada o en el
## siguiente hueco libre. Devuelve {"ok", "message"}.
func schedule_interview(candidate_id: int, by_executive: bool = false) -> Dictionary:
	var problem: String = appointment_problem(candidate_id, by_executive)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var by: String = _interviewer_key(by_executive)
	var at: int = _next_appointment_slot(by)
	appointments.append({"candidate_id": candidate_id, "by": by, "at": at})
	appointments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) < int(b["at"]))
	EventBus.staff_changed.emit()
	return {"ok": true, "message": "%s entrevistará a %s %s." % [_interviewer_name(by),
		get_candidate(candidate_id)["name"], describe_appointment_time(at)]}


## Por qué no se puede citar ahora a un candidato ("" si se puede).
func appointment_problem(candidate_id: int, by_executive: bool = false) -> String:
	var candidate: Dictionary = get_candidate(candidate_id)
	if candidate.is_empty():
		return "Ese candidato ya no está."
	if bool(candidate["interviewed"]):
		return "Ya lo entrevistaste."
	if int(interview.get("candidate_id", -1)) == candidate_id:
		return "Ya está en la entrevista."
	if not get_appointment(candidate_id).is_empty():
		return "Ya tiene entrevista citada."
	if by_executive and get_interviewer().is_empty():
		return "Hace falta un ejecutivo de %s para delegar las entrevistas." % StaffCatalog.get_department_name(
			String(StaffCatalog.get_departments("interviews_department")))
	var by: String = _interviewer_key(by_executive)
	if RoomRules.counts_enabled and get_guest_chair(by).is_empty():
		return "%s necesita una silla de visita en su oficina para entrevistar." % _interviewer_name(by)
	if _next_appointment_slot(by) < 0:
		return "%s no tiene un hueco para entrevistar en los próximos días." % _interviewer_name(by)
	return ""


## La cita de un candidato, o vacío si no tiene.
func get_appointment(candidate_id: int) -> Dictionary:
	for appointment: Dictionary in appointments:
		if int(appointment["candidate_id"]) == candidate_id:
			return appointment
	return {}


## Minuto absoluto en que llega el citado: entre appointment_early_max y _min antes, fijo por candidato.
func get_appointment_arrival(appointment: Dictionary) -> int:
	var earliest: int = int(StaffCatalog.get_hiring("appointment_early_max"))
	var latest: int = int(StaffCatalog.get_hiring("appointment_early_min"))
	var early: int = latest + posmod(hash([_rng.seed, int(appointment["candidate_id"]), "appointment"]), earliest - latest + 1)
	return int(appointment["at"]) - early


## «mañana a las 08:00», «hoy a las 08:30» o «el jue a las 08:00».
func describe_appointment_time(at: int) -> String:
	@warning_ignore("integer_division")
	var days: int = at / (60 * GameConstants.HOURS_PER_DAY) - _absolute_hour() / GameConstants.HOURS_PER_DAY
	var day: String = "hoy" if days == 0 else ("mañana" if days == 1 else "el " + WorkSchedule.DAY_NAMES[
		posmod(GameClock.get_weekday() + days, GameConstants.DAYS_PER_WEEK)])
	return "%s a las %s" % [day, format_clock_minute(at)]


func _interviewer_key(by_executive: bool) -> String:
	if not by_executive:
		return "ceo"
	var interviewer: Dictionary = get_interviewer()
	return "" if interviewer.is_empty() else employee_key(interviewer["id"])


# Primer hueco para una entrevista desde mañana: la entrada de quien la hace o los huecos
# siguientes antes del almuerzo sin pisar otra cita. -1 si no hay en appointment_max_days.
func _next_appointment_slot(by: String) -> int:
	var minutes: int = int(StaffCatalog.get_hiring("interview_minutes"))
	var hours_per_day: int = GameConstants.HOURS_PER_DAY
	var today_start: int = (_absolute_hour() - GameClock.get_hour()) * 60
	var schedule: WorkSchedule = null
	if by != "ceo":
		var employee: Dictionary = get_employee_by_key(by)
		if employee.is_empty():
			return -1
		schedule = get_schedule(employee)
	for offset: int in range(1, int(StaffCatalog.get_hiring("appointment_max_days")) + 1):
		var weekday: int = posmod(GameClock.get_weekday() + offset, GameConstants.DAYS_PER_WEEK)
		var start_hour: int
		if by == "ceo":
			if not StaffCatalog.get_ceo_arrival_days().has(weekday):
				continue
			start_hour = StaffCatalog.get_ceo_arrival_hour()
		else:
			if not schedule.days.has(weekday):
				continue
			start_hour = schedule.start_hour
		var day_start: int = today_start + offset * hours_per_day * 60
		var slot: int = day_start + start_hour * 60
		# Hasta el almuerzo de esa jornada.
		var lunch: int = day_start + (start_hour + WorkSchedule.get_lunch_offset()) * 60
		while slot + minutes <= lunch:
			if not _slot_taken(slot, minutes):
				return slot
			slot += minutes
	return -1


func _slot_taken(slot: int, minutes: int) -> bool:
	for appointment: Dictionary in appointments:
		var at: int = int(appointment["at"])
		if slot < at + minutes and at < slot + minutes:
			return true
	return false


# A la hora de cada cita llama al candidato si quien entrevista está y no hay otra; tras
# appointment_grace_minutes sin él se cancela con aviso.
func _check_appointments() -> void:
	if appointments.is_empty():
		return
	var now: int = get_absolute_minute()
	var changed: bool = false
	for appointment: Dictionary in appointments.duplicate():
		if now < int(appointment["at"]):
			break
		var by: String = String(appointment["by"])
		var candidate: Dictionary = get_candidate(int(appointment["candidate_id"]))
		var present: bool = (by == "ceo" and ceo_at_work and is_expected(by, GameClock.get_weekday(), GameClock.get_hour())) \
			or (by != "ceo" and is_expected(by, GameClock.get_weekday(), GameClock.get_hour()))
		if candidate.is_empty() or (by != "ceo" and get_employee_by_key(by).is_empty()):
			appointments.erase(appointment)
			changed = true
		elif present and interview.is_empty() and (not RoomRules.counts_enabled or not get_guest_chair(by).is_empty()):
			appointments.erase(appointment)
			_call_interview(int(appointment["candidate_id"]), by)
			changed = true
		elif now >= int(appointment["at"]) + int(StaffCatalog.get_hiring("appointment_grace_minutes")):
			appointments.erase(appointment)
			changed = true
			EventBus.send_notice(EventBus.target_menu("staff"),
				"%s no pudo entrevistar a %s a la hora citada: vuelve a citarlo." % [_interviewer_name(by), candidate["name"]])
	if changed:
		EventBus.staff_changed.emit()


# Llama al candidato: la entrevista empieza al sentarse (start_called_interview) o, sin
# escena que lo dibuje, a los interview_walk_max_minutes.
func _call_interview(candidate_id: int, by: String) -> void:
	interview = {"candidate_id": candidate_id, "called_at": get_absolute_minute(),
		"starts_at": INTERVIEW_NOT_STARTED, "ends_at": INTERVIEW_NOT_STARTED, "by": by}
	EventBus.staff_changed.emit()


## Indica si la entrevista en curso ya empezó (false mientras el candidato llamado camina).
func is_interview_started() -> bool:
	return not interview.is_empty() and int(interview["starts_at"]) != INTERVIEW_NOT_STARTED


## El candidato llamado se sentó: empieza la media hora de entrevista.
func start_called_interview() -> void:
	if interview.is_empty() or is_interview_started():
		return
	var now: int = get_absolute_minute()
	interview["starts_at"] = now
	interview["ends_at"] = now + int(StaffCatalog.get_hiring("interview_minutes"))
	EventBus.staff_changed.emit()


func _begin_interview(candidate_id: int, by: String) -> void:
	var now: int = get_absolute_minute()
	interview = {"candidate_id": candidate_id, "starts_at": now,
		"ends_at": now + int(StaffCatalog.get_hiring("interview_minutes")), "by": by}
	EventBus.staff_changed.emit()


## Termina la entrevista si ya pasó su fin. Se llama cada cuadro y cada hora (los saltos no
## pasan por los cuadros).
func check_interview() -> void:
	if interview.is_empty():
		return
	if not is_interview_started():
		if get_absolute_minute() >= int(interview.get("called_at", 0)) + int(StaffCatalog.get_hiring("interview_walk_max_minutes")):
			start_called_interview()
		return
	if get_absolute_minute() >= int(interview["ends_at"]):
		_finish_interview()


## Silla de visita de la oficina de alguien ("ceo" o clave): una silla sin dueño de su habitación.
func get_guest_chair(by: String) -> Dictionary:
	var room: Dictionary = get_workplace_room(by)
	if room.is_empty():
		return {}
	var cells: Array = room["cells"]
	for item: Dictionary in OfficeState.furniture:
		if String(item["assigned_to"]).is_empty() and cells.has(item["cell"]) \
				and bool(FurnitureCatalog.get_item(String(item["id"])).get("is_seat", false)):
			return item
	return {}


## Ejecutivo que puede entrevistar (el de departments.interviews_department), o vacío.
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
	if RoomRules.counts_enabled and get_guest_chair(by).is_empty():
		return "%s necesita una silla de visita en su oficina para entrevistar." % _interviewer_name(by)
	var minutes: int = int(StaffCatalog.get_hiring("interview_minutes"))
	var weekday: int = GameClock.get_weekday()
	var hour: int = GameClock.get_hour()
	# Quien entrevista tiene que estar en todas las horas que toca.
	@warning_ignore("integer_division")
	var hours: int = (GameClock.get_minute() + minutes - 1) / 60 + 1
	for offset: int in range(hours):
		if hour + offset >= GameConstants.HOURS_PER_DAY or not is_expected(by, weekday, hour + offset):
			if by != "ceo":
				return "%s tiene que estar en la oficina los %d minutos de la entrevista." % [_interviewer_name(by), minutes]
			return "El CEO tiene que estar en la oficina los %d minutos de la entrevista, sin cruzar el almuerzo (%02d:00) ni la medianoche." % [
				minutes, get_ceo_lunch_hour()]
	return ""


## Parte de la hora absoluta at que el CEO no pasó entrevistando (0.5 con media hora).
func get_ceo_interview_factor(at: int) -> float:
	var spans: Array[Vector2i] = _interview_spans.duplicate()
	if is_interview_started() and String(interview.get("by", "ceo")) == "ceo":
		spans.append(Vector2i(int(interview["starts_at"]), int(interview["ends_at"])))
	var busy: int = 0
	for span: Vector2i in spans:
		busy += maxi(0, mini(span.y, at * 60 + 60) - maxi(span.x, at * 60))
	return clampf(1.0 - busy / 60.0, 0.0, 1.0)


## Candidato que está en entrevista ahora, o vacío.
func get_interviewed_now() -> Dictionary:
	return {} if interview.is_empty() else get_candidate(interview["candidate_id"])


## Candidatos esperando en todas las vacantes.
func get_waiting_count() -> int:
	var count: int = 0
	for vacancy: Dictionary in vacancies:
		count += vacancy["candidates"].size()
	return count


## Primer día en que pueden llegar candidatos: hoy si aún no es la hora de llegada, si no mañana.
func next_arrival_day() -> int:
	var today: int = GameClock.get_day_count()
	return today if GameClock.get_hour() < int(StaffCatalog.get_hiring("arrival_hour")) else today + 1


## Días de publicidad que le quedan a una vacante (0 si no tiene).
func publicity_days_left(vacancy: Dictionary) -> int:
	return maxi(int(vacancy["publicity_until"]) - next_arrival_day(), 0)


## Días que le quedan a un candidato (se va a la hora de llegada de ese día): 0 = hoy.
func candidate_days_left(candidate: Dictionary) -> int:
	var leaves_on: int = int(candidate["arrived_day"]) + int(StaffCatalog.get_hiring("candidate_days"))
	return maxi(leaves_on - GameClock.get_day_count(), 0)


## "Programador Junior · $1,200 al mes".
static func describe_vacancy(vacancy: Dictionary) -> String:
	return "%s · %s al mes" % [StaffCatalog.describe_title(vacancy["role"], vacancy["level"]),
		MoneyFormat.format(vacancy["salary"])]


## Habilidades: en rangos («Programación 40–60») o, ya entrevistado, los valores reales.
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


## "Programador Junior · $1,200 al mes" para un empleado.
static func describe_employee(employee: Dictionary) -> String:
	return "%s · %s al mes" % [StaffCatalog.describe_title(employee["role"], employee["level"]),
		MoneyFormat.format(employee["salary"])]


# La entrevista revela los valores reales y un rasgo (el primero que aún no se conoce).
func _finish_interview() -> void:
	if String(interview.get("by", "ceo")) == "ceo":
		_interview_spans.append(Vector2i(int(interview["starts_at"]), int(interview["ends_at"])))
		if _interview_spans.size() > 4:
			_interview_spans.pop_front()
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


# Si el candidato ya no está, la entrevista termina sin más.
func _drop_missing_interview() -> void:
	if not interview.is_empty() and get_interviewed_now().is_empty():
		interview = {}
	for appointment: Dictionary in appointments.duplicate():
		if get_candidate(int(appointment["candidate_id"])).is_empty():
			appointments.erase(appointment)


# Contrata: ocupa el primer puesto libre y cierra la vacante (los demás candidatos se van).
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
	EventBus.sound_requested.emit("hire")
	return {"ok": true, "result": "hired", "message": "%s aceptó: entra como %s." % [
		employee["name"], describe_employee(employee)]}


## Contrata sin vacante ni entrevista con el sueldo de la tabla (empresa de prueba). Devuelve el
## empleado, o vacío si no se puede o no hay puesto.
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
			# Quien tiene entrevista citada la espera.
			if today < int(candidate["arrived_day"]) + waiting_days or not get_appointment(int(candidate["id"])).is_empty():
				staying.append(candidate)
		vacancy["candidates"] = staying
		var arriving: int = _roll_arrivals(vacancy, today)
		for i: int in range(arriving):
			if staying.size() >= max_waiting:
				break
			staying.append(_make_candidate(vacancy, today))
	_drop_missing_interview()
	EventBus.staff_changed.emit()


# Candidatos que llegan hoy: el primer día la tanda según las estrellas (+1 con publicidad);
# con el premio, uno más cada día.
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


## Cuántos llegan el primer día: first_batch + first_batch_per_star por estrella sobre
## neutral_stars, al menos first_batch_min.
func get_first_batch() -> int:
	var stars: int = floori(Projects.reputation)
	return maxi(int(StaffCatalog.get_hiring("first_batch_min")), int(StaffCatalog.get_hiring("first_batch"))
		+ int(StaffCatalog.get_hiring("first_batch_per_star")) * (stars - int(StaffCatalog.get_hiring("neutral_stars"))))


## Calidad de los candidatos (±max_quality): sueldo ofrecido frente a la tabla y ambiente medio
## de las Áreas de trabajo.
func get_candidate_quality(role: String, level: String, salary: int) -> float:
	var table: int = maxi(1, StaffCatalog.get_salary(role, level))
	var quality: float = (float(salary) / table - 1.0) * float(StaffCatalog.get_hiring("quality_per_salary")) \
		+ get_work_area_ambiance() * float(StaffCatalog.get_hiring("quality_per_ambiance"))
	var limit: float = float(StaffCatalog.get_hiring("max_quality"))
	return clampf(quality, -limit, limit)


## Posición de una habilidad en su rango (0–1) para un azar roll: la calidad la corre arriba o abajo.
static func quality_position(roll: float, quality: float) -> float:
	return clampf(roll * (1.0 - absf(quality)) + maxf(quality, 0.0), 0.0, 1.0)


## Pronóstico de una vacante para Personal: «Llegan 3 el primer día (3 ★) · habilidades +20 % …».
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


## Suma un candidato por vacante cada día durante days días («Premio de la industria»).
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
	var trait_pool: Array[String] = StaffCatalog.get_trait_ids(role if cleaning_shift_enabled else "")
	var trait_count: Vector2i = StaffCatalog.get_traits_per_person()
	for i: int in range(_rng.randi_range(trait_count.x, trait_count.y)):
		traits.append(trait_pool.pop_at(_rng.randi_range(0, trait_pool.size() - 1)))
	return {
		"id": _take_id(), "name": full_name, "sex": sex, "age": _rng.randi_range(ages.x, ages.y),
		"role": role, "level": level, "asked_salary": maxi(step, roundi(asked / step) * step),
		"skills": skills, "skill_low": skill_low, "traits": traits, "arrived_day": today,
		"interviewed": false, "known_traits": [] as Array[String], "counter_offer": 0,
	}


func _import_candidate(saved: Dictionary) -> Dictionary:
	var candidate: Dictionary = _import_person(saved)
	candidate["arrived_day"] = int(saved.get("arrived_day", 0))
	candidate["counter_offer"] = int(saved.get("counter_offer", 0))
	return candidate
