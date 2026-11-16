# Personal, capa 3: rasgos, mentores, llegadas escalonadas, puntualidad e historial.
extends "res://scripts/staff/staff_workplace.gd"


## Factor de puntos por rasgos a esa hora: perfeccionista y sociable menos, noctámbulo más de
## noche y menos de día, adicto al café menos sin café.
static func get_trait_points_factor(person: Dictionary, hour: int, coffee: bool = true) -> float:
	var factor: float = _trait_product(person, "points")
	if not coffee:
		factor *= _trait_product(person, "no_coffee_points")
	return factor * _trait_product(person, "night_points" if WorkSchedule.is_night_hour(hour) else "day_points")


# Al empezar cada hora, quien entra llega a tiempo, tarde (pierde la hora) o falta (la jornada)
# según sus rasgos. Sorteo fijo por semilla, empleado y hora: no gasta _rng.
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
		var roll: float = _lateness_roll(employee, now)
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


# Sorteo de tardanza al empezar el turno en at (fijo por persona y hora; 1.0 si no es
# impuntual). Se puede pedir antes.
func _lateness_roll(employee: Dictionary, at: int) -> float:
	if _trait_value(employee, "late_chance") <= 0.0 and _trait_value(employee, "absent_chance") <= 0.0:
		return 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_rng.seed, int(employee["id"]), at])
	return rng.randf()


## Minutos respecto de la hora en punto en que entra alguien cuya llegada es en at (negativo =
## antes); fijo por persona y hora. Solo es visual.
func get_arrival_offset(employee: Dictionary, at: int) -> int:
	if not arrival_spread_enabled:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_rng.seed, int(employee["id"]), at, "arrival"])
	var unpunctual: bool = _trait_value(employee, "late_chance") > 0.0
	var late_chance: float = StaffCatalog.get_arrivals("unpunctual_late_chance" if unpunctual else "late_chance")
	var earliest: int = int(StaffCatalog.get_arrivals("unpunctual_earliest" if unpunctual else "earliest"))
	if rng.randf() < late_chance:
		return rng.randi_range(1, int(StaffCatalog.get_arrivals("latest")))
	return rng.randi_range(earliest, 0)


## Minutos de la hora actual que tarda en entrar quien empieza (o vuelve de llegar tarde) ahora; 0 si no.
func get_late_minutes(key: String) -> int:
	var employee: Dictionary = get_employee_by_key(key)
	if employee.is_empty() or not is_expected_now(key):
		return 0
	var weekday: int = GameClock.get_weekday()
	var hour: int = GameClock.get_hour()
	var previous_weekday: int = weekday if hour > 0 else posmod(weekday - 1, GameConstants.DAYS_PER_WEEK)
	var previous_hour: int = posmod(hour - 1, GameConstants.HOURS_PER_DAY)
	if is_expected(key, previous_weekday, previous_hour) or get_schedule(employee).is_lunch(previous_weekday, previous_hour):
		return 0
	return maxi(get_arrival_offset(employee, _absolute_hour()), 0)


## Minutos antes de la hora siguiente en que entra quien empieza en ella a tiempo; 0 si no.
func get_early_minutes(key: String) -> int:
	var employee: Dictionary = get_employee_by_key(key)
	if employee.is_empty() or is_expected_now(key):
		return 0
	var next: int = _absolute_hour() + 1
	var hours_per_day: int = GameConstants.HOURS_PER_DAY
	@warning_ignore("integer_division")
	var weekday: int = (next / hours_per_day) % GameConstants.DAYS_PER_WEEK
	var hour: int = next % hours_per_day
	var schedule: WorkSchedule = get_schedule(employee)
	if schedule.start_hour != hour or not schedule.days.has(weekday):
		return 0
	if _lateness_roll(employee, next) < _trait_value(employee, "late_chance") + _trait_value(employee, "absent_chance"):
		return 0
	return maxi(-get_arrival_offset(employee, next), 0)


## Minutos de la hora actual que alguien se queda al terminar su jornada (no al almorzar),
## fijo por persona y hora; 0 si no termina ahora.
func get_leave_minutes(key: String) -> int:
	var employee: Dictionary = get_employee_by_key(key)
	if employee.is_empty() or not arrival_spread_enabled or is_expected_now(key):
		return 0
	var weekday: int = GameClock.get_weekday()
	var hour: int = GameClock.get_hour()
	var previous_weekday: int = weekday if hour > 0 else posmod(weekday - 1, GameConstants.DAYS_PER_WEEK)
	var previous_hour: int = posmod(hour - 1, GameConstants.HOURS_PER_DAY)
	if not is_expected(key, previous_weekday, previous_hour) or get_schedule(employee).is_lunch(weekday, hour):
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_rng.seed, int(employee["id"]), _absolute_hour(), "leave"])
	return rng.randi_range(int(StaffCatalog.get_arrivals("leave_earliest")), int(StaffCatalog.get_arrivals("leave_latest")))


## Minutos antes de la hora siguiente en que llega el CEO a abrir (open_minutes) si esa es su
## llegada y no está ya; 0 si no. Hasta su hora no rinde.
func get_ceo_early_minutes() -> int:
	if ceo_at_work:
		return 0
	var next: int = _absolute_hour() + 1
	var hours_per_day: int = GameConstants.HOURS_PER_DAY
	@warning_ignore("integer_division")
	var weekday: int = (next / hours_per_day) % GameConstants.DAYS_PER_WEEK
	if next % hours_per_day != StaffCatalog.get_ceo_arrival_hour() or not StaffCatalog.get_ceo_arrival_days().has(weekday):
		return 0
	return StaffCatalog.get_ceo_open_minutes() if arrival_spread_enabled else 0


## Anota los errores ocultos que generó cada uno en la hora (resultado de Production.apply).
func note_bugs_caused(done: Array[Dictionary]) -> void:
	for item: Dictionary in done:
		var bugs: int = int(item.get("bugs", 0))
		if bugs <= 0:
			continue
		var employee: Dictionary = get_employee_by_key(String(item["worker"]["key"]))
		if not employee.is_empty():
			employee["bugs_caused"] = int(employee.get("bugs_caused", 0)) + bugs


## Porcentaje de jornadas en que llegó a tiempo; -1 sin datos.
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


## Factor de los errores que genera alguien al programar (perfeccionista).
static func get_trait_bug_factor(person: Dictionary) -> float:
	return _trait_product(person, "bug_factor")


## Factor de los errores que encuentra alguien al probar (perfeccionista).
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


## Lo que suma a la meta de ánimo un sociable en su equipo (él incluido; una vez aunque haya varios).
func get_team_trait_mood(employee: Dictionary) -> float:
	var best: float = 0.0
	for person: Dictionary in _team_people(employee):
		best = maxf(best, float(_trait_value(person, "team_mood")))
	return best


# Mentores del equipo de un empleado, sin contarlo a él.
func _mentors_of(employee: Dictionary) -> Array[Dictionary]:
	var mentors: Array[Dictionary] = []
	for person: Dictionary in _team_people(employee):
		if person["id"] != employee["id"] and _trait_value(person, "mentor_points") > 0.0:
			mentors.append(person)
	return mentors


# Indica si un empleado es de un nivel que ayuda ese mentor.
static func _is_mentee(employee: Dictionary, mentor: Dictionary) -> bool:
	for trait_id: Variant in mentor.get("traits", []):
		if (StaffCatalog.get_trait_effect(String(trait_id), "mentor_levels", []) as Array).has(employee.get("level", "")):
			return true
	return false


## Factor por un mentor presente en su equipo (1 si no hay; una vez aunque haya varios).
func get_mentor_factor(employee: Dictionary, weekday: int, hour: int) -> float:
	return float(get_team_mentor_factors(get_team_of(employee["id"]), weekday, hour).get(int(employee["id"]), 1.0))


## get_mentor_factor de todo un equipo (id → factor; vacío sin mentores presentes).
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


## Contratos menos que necesita alguien para ascender por un mentor en su equipo.
func get_mentor_projects(employee: Dictionary) -> int:
	var best: int = 0
	for mentor: Dictionary in _mentors_of(employee):
		if _is_mentee(employee, mentor):
			best = maxi(best, int(_trait_value(mentor, "mentor_projects")))
	return best


# Cada discover_days días en la empresa se descubre otro rasgo.
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


## Qué hace un rasgo según sus efectos de data/staff.json; "" si todavía no hace nada.
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
