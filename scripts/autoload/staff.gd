# Personal: vacantes, candidatos, entrevistas y citas, contratación, empleados (jornada, nómina,
# ánimo, ascensos, rasgos), equipos, plantillas de turno, agenda y dirección (líderes, gerentes,
# ejecutivos). Valores en data/staff.json; todo el azar sale de _rng (se guarda con la partida).
extends "res://scripts/staff/staff_hiring.gd"


func _ready() -> void:
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.balance_changed.connect(func(_balance: int) -> void: _pay_debt_if_possible())
	EventBus.emergency_loan_resolved.connect(_on_emergency_loan_resolved)
	EventBus.contract_delivered.connect(_on_contract_delivered)
	EventBus.contract_accepted.connect(_on_contract_accepted)
	EventBus.staff_changed.connect(_clear_hour_caches)
	EventBus.office_changed.connect(_clear_hour_caches)


## Prepara una partida nueva: sin vacantes y con una semilla al azar.
func new_game() -> void:
	vacancies.clear()
	employees.clear()
	interview = {}
	appointments.clear()
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
	_interview_spans.clear()
	_rng.randomize()
	EventBus.staff_changed.emit()


func _process(_delta: float) -> void:
	if not interview.is_empty():
		check_interview()
	if not appointments.is_empty():
		_check_appointments()


## Manda al CEO a casa (false) o a la oficina (true); al irse corta su entrevista.
func set_ceo_at_work(value: bool) -> void:
	if value == ceo_at_work:
		return
	ceo_at_work = value
	if not value and String(interview.get("by", "ceo")) == "ceo":
		interview = {}
	EventBus.presence_changed.emit()
	EventBus.staff_changed.emit()


## Indica si el CEO produce a esa hora absoluta: trabajando, sin almorzar, despierto y no
## toda la hora en entrevistas.
func is_ceo_producing(at: int) -> bool:
	var hour: int = posmod(at, GameConstants.HOURS_PER_DAY)
	if not is_expected("ceo", get_weekday_at(at), hour) or is_ceo_asleep(hour):
		return false
	return get_ceo_interview_factor(at) > 0.0


## Horas hasta la primera en que alguien debe estar en la oficina; -1 si nadie va a venir.
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


# Anota quién estuvo hoy (máquina expendedora).
func _note_presence() -> void:
	if OfficeState.get_break_room_effect("vending_income") <= 0.0:
		return
	present_today.merge(get_present_keys(_absolute_hour()))


func _on_hour_changed(hour: int) -> void:
	_clear_hour_caches()
	_update_energy()
	_update_dirt()
	_check_arrivals()
	_present_cache.clear()
	_check_bathrooms()
	_decide_breaks()
	_note_presence()
	if not ceo_at_work and hour == StaffCatalog.get_ceo_arrival_hour() \
			and StaffCatalog.get_ceo_arrival_days().has(GameClock.get_weekday()):
		set_ceo_at_work(true)
	check_interview()
	_check_appointments()
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


# Préstamo de emergencia: aceptado, la nómina ya se pagó y cuenta a tiempo; rechazado, queda debida.
func _on_emergency_loan_resolved(_accepted: bool) -> void:
	if not payroll_held:
		return
	payroll_held = false
	if get_total_owed() == 0:
		EventBus.payment_recorded.emit(CONCEPT_PAYROLL, true)
	else:
		_payroll_unpaid(get_total_owed())


## Estado para guardar. El azar va como texto: JSON perdería precisión.
func export_state() -> Dictionary:
	return {"vacancies": vacancies.duplicate(true), "employees": employees.duplicate(true),
		"interview": interview.duplicate(), "appointments": appointments.duplicate(true), "ceo_at_work": ceo_at_work, "last_firing_day": last_firing_day,
		"teams": teams.duplicate(true), "next_team_id": _next_team_id, "next_id": _next_id,
		"shift_templates": shift_templates.duplicate(true), "next_template_id": _next_template_id,
		"rng_state": str(_rng.state), "hired_count": hired_count, "payroll_held": payroll_held,
		"coffee_out_day": coffee_out_day, "broken_toilets": broken_toilets, "bathroom_short_day": bathroom_short_day,
		"breaks": _export_breaks(), "present_today": present_today.keys(), "award_until": award_until}


## Restaura el personal de una partida guardada; lo que falte queda vacío.
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
	# Dos ejecutivos no dirigen el mismo departamento.
	var directed: Dictionary[String, bool] = {}
	for executive: Dictionary in get_executives():
		var department: String = executive["department"]
		if directed.has(department) or not StaffCatalog.get_department_ids().has(department):
			executive["department"] = ""
		else:
			directed[department] = true
	# Un líder sin gerente válido pasa al CEO.
	for leader: Dictionary in get_leaders():
		if not is_manager(get_employee(int(leader["manager_id"]))):
			leader["manager_id"] = 0
	var saved_interview: Dictionary = state.get("interview", {})
	interview = {}
	if saved_interview.has("candidate_id"):
		var ends_at: int = int(saved_interview.get("ends_at", 0))
		var starts_at: int = int(saved_interview.get("starts_at", INTERVIEW_NOT_STARTED))
		if not saved_interview.has("starts_at"):
			# Partida vieja: ends_at en horas y 2 h de entrevista.
			starts_at = ends_at * 60 - 120
			ends_at *= 60
		interview = {"candidate_id": int(saved_interview["candidate_id"]), "starts_at": starts_at,
			"ends_at": ends_at, "by": String(saved_interview.get("by", "ceo"))}
		if saved_interview.has("called_at"):
			interview["called_at"] = int(saved_interview["called_at"])
		# Si la hacía un ejecutivo que ya no está, se corta.
		if interview["by"] != "ceo" and get_employee_by_key(interview["by"]).is_empty():
			interview = {}
	appointments.clear()
	for saved: Dictionary in state.get("appointments", []):
		appointments.append({"candidate_id": int(saved["candidate_id"]), "by": String(saved["by"]), "at": int(saved["at"])})
	_drop_missing_interview()
	# Partidas viejas sin plantillas: las de data/staff.json.
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
			# Un empleado está en un solo equipo, sigue contratado y su puesto entra en equipos.
			var member_data: Dictionary = get_employee(member_id)
			if not member_data.is_empty() and can_join_teams(member_data) and get_team_of(member_id).is_empty():
				members.append(member_id)
		var team_id: int = int(saved["id"])
		var schedule: Dictionary = saved.get("schedule", WorkSchedule.make_shift(
			int(StaffCatalog.get_teams("default_start_hour")), StaffCatalog.get_default_team_days()).to_dict())
		# El líder tiene que seguir contratado, ser líder y no estar en otro equipo.
		var leader_id: int = int(saved.get("leader_id", 0))
		var leader: Dictionary = get_employee(leader_id)
		if leader.is_empty() or not is_leader(leader) or not get_team_of(leader_id).is_empty():
			leader_id = 0
		# Con una plantilla que ya no está, se queda con su turno como propio.
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
	_interview_spans.clear()
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
