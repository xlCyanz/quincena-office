# Personal, capa 2: puestos, habitaciones, ambiente, suciedad, baños, almuerzo, pausas y contador.
extends "res://scripts/staff/staff_base.gd"


## Indica si hay café hoy: Sala de descanso que funciona y sin el evento de que se acabó.
func has_coffee() -> bool:
	return coffee_out_day != GameClock.get_day_count() and Projects.has_working_room(BREAK_ROOM)


# Al empezar la hora, quienes producen con energía baja toman una pausa mientras haya lugar
# en los sofás, los más cansados primero.
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


# La máquina expendedora cobra por las personas que estuvieron ayer.
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


## Quiénes almuerzan dentro a esa hora absoluta: el CEO y después por antigüedad, mientras haya
## asientos en una Sala de descanso con nevera, microondas y mesas.
func get_lunch_inside(at: int) -> Dictionary[String, bool]:
	if not GameClock.in_hour_tick:
		return _find_lunch_inside(at)
	if not _lunch_cache.has(at):
		_lunch_cache[at] = _find_lunch_inside(at)
	return _lunch_cache[at]


func _find_lunch_inside(at: int) -> Dictionary[String, bool]:
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


## Inodoros que cuentan: los de Baños que funcionan menos los dañados.
func get_toilet_capacity() -> int:
	return maxi(0, OfficeState.count_working_toilets() - broken_toilets)


## Personas en la oficina a esa hora absoluta: quienes trabajan (sin almuerzo, tardanza ni
## ausencia) y el CEO.
func count_present(at: int) -> int:
	return get_present_keys(at).size()


## Claves de quienes están en la oficina a esa hora absoluta.
func get_present_keys(at: int) -> Dictionary[String, bool]:
	if GameClock.in_hour_tick and _present_cache.has(at):
		return _present_cache[at]
	var weekday: int = get_weekday_at(at)
	var hour: int = posmod(at, GameConstants.HOURS_PER_DAY)
	var team_map: Dictionary[int, Dictionary] = _get_team_map()
	var keys: Dictionary[String, bool] = {}
	if is_expected("ceo", weekday, hour):
		keys["ceo"] = true
	for employee: Dictionary in employees:
		if _is_working_at(employee, weekday, hour, team_map):
			keys[employee_key(employee["id"])] = true
	if GameClock.in_hour_tick:
		_present_cache[at] = keys
	return keys


## Inodoros que hacen falta para esa cantidad de personas: 1 cada 10, hacia arriba.
static func get_toilets_needed(present: int) -> int:
	return ceili(float(present) / StaffCatalog.get_bathrooms("people_per_toilet"))


## Cuántos inodoros faltan a esa hora absoluta (0 si alcanzan).
func get_bathroom_shortage(at: int) -> int:
	if not bathrooms_enabled:
		return 0
	return maxi(0, get_toilets_needed(count_present(at)) - get_toilet_capacity())


## Factor de producción por falta de inodoros: −5 % por cada uno, hasta −20 %.
static func get_bathroom_factor(shortage: int) -> float:
	return 1.0 - minf(StaffCatalog.get_bathrooms("max_points_loss"), shortage * StaffCatalog.get_bathrooms("points_per_missing"))


## Indica si faltaron inodoros hoy o ayer (baja la meta de ánimo).
func is_bathroom_short_recently() -> bool:
	return GameClock.get_day_count() - bathroom_short_day <= 1


# Anota el día si a esta hora faltan inodoros.
func _check_bathrooms() -> void:
	if get_bathroom_shortage(_absolute_hour()) > 0:
		bathroom_short_day = GameClock.get_day_count()


## Evento «Baño dañado»: un inodoro deja de contar. false si no había ninguno.
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


## Indica si el líder de un equipo trabaja a esa hora absoluta.
func is_leader_present(team: Dictionary, at: int) -> bool:
	var leader: Dictionary = get_team_leader(team)
	return not leader.is_empty() and is_expected(employee_key(leader["id"]), get_weekday_at(at),
		posmod(at, GameConstants.HOURS_PER_DAY))


## Puestos libres donde trabaja ese cargo (un Área de trabajo si no se dice).
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


## Indica si a esa hora hay un recepcionista trabajando en su mostrador.
func is_reception_attended(weekday: int, hour: int) -> bool:
	for employee: Dictionary in employees:
		if employee["role"] == RECEPTIONIST_ROLE and has_working_station(employee) \
				and is_expected(employee_key(employee["id"]), weekday, hour):
			return true
	return false


## Indica si el puesto de un empleado sigue funcionando.
func has_working_station(employee: Dictionary) -> bool:
	return Workstations.is_working_station(OfficeState.furniture, OfficeState.rooms, employee_key(employee["id"]))


## Claves de quienes tienen un puesto que funciona (para revisar a muchos de una vez).
func get_working_station_keys() -> Dictionary[String, bool]:
	var keys: Dictionary[String, bool] = {}
	for station: Dictionary in Workstations.find_all(OfficeState.furniture, OfficeState.rooms):
		var owner: String = String(OfficeState.furniture[station["chair"]]["assigned_to"])
		if not owner.is_empty():
			keys[owner] = true
	return keys


## Indica si la empresa tiene al menos un contador.
func has_accountant() -> bool:
	var role: String = String(StaffCatalog.get_accounting("role"))
	for employee: Dictionary in employees:
		if employee["role"] == role:
			return true
	return false


## Factor de los efectos del contador: accountant_boost con impresora en el Área de trabajo de
## algún contador; si no, 1.
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


## Habitación que limpia ahora alguien de limpieza (la más sucia), o -1.
func get_cleaning_room(employee: Dictionary) -> int:
	if employee["role"] != String(StaffCatalog.get_cleaning("role")) or not is_expected_now(employee_key(employee["id"])):
		return -1
	return OfficeState.get_dirtiest_room()


## Habitación donde está la silla de alguien, o vacío.
func get_workplace_room(key: String) -> Dictionary:
	var seat: Dictionary = _seat_of(key)
	if seat.is_empty():
		return {}
	var room_index: int = _room_map().get(seat["cell"], -1)
	return OfficeState.rooms[room_index] if room_index >= 0 else {}


## Ambiente de la habitación donde trabaja alguien (0 sin puesto).
func get_ambiance(key: String) -> int:
	var room: Dictionary = get_workplace_room(key)
	return 0 if room.is_empty() else int(_ambiance_detail(room)["value"])


# Ambiance.get_detail de una habitación, guardado mientras ni ella ni los muebles cambien.
func _ambiance_detail(room: Dictionary) -> Dictionary:
	var furniture_hash: int = int(_seat_lookup_cache["furniture_hash"]) if not _seat_lookup_cache.is_empty() \
		else OfficeState.furniture.hash()
	var windows: int = OfficeState.count_room_windows(room)
	var door_points: int = OfficeState.get_room_door_ambiance(room)
	var key: int = [room.hash(), furniture_hash, windows, door_points].hash()
	if not _ambiance_cache.has(key):
		if _ambiance_cache.size() >= AMBIANCE_CACHE_SIZE:
			_ambiance_cache.clear()
		_ambiance_cache[key] = Ambiance.get_detail(room, OfficeState.furniture, windows, door_points)
	return _ambiance_cache[key]


# Mueble asignado a alguien, de _seat_lookup_cache si _update_morale está en curso.
func _seat_of(key: String) -> Dictionary:
	if _seat_lookup_cache.is_empty():
		return OfficeState.find_furniture_assigned_to(key)
	return _seat_lookup_cache["seats"].get(key, {})


# Arma _seat_lookup_cache: primer mueble asignado a cada uno, escritorio de cada puesto y hash
# de los muebles. Los cambios durante el recorrido no afectan al ambiente.
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


# OfficeState.get_room_index_map, de la caché si _update_morale está en curso.
func _room_map() -> Dictionary:
	return _seat_lookup_cache["room_map"] if not _seat_lookup_cache.is_empty() else OfficeState.get_room_index_map()


## Lo que suman a la meta de ánimo de todos los muebles de la Sala de descanso (uno de cada uno).
func get_break_mood() -> float:
	if not _seat_lookup_cache.is_empty():
		return float(_seat_lookup_cache["break_mood"])
	return OfficeState.get_break_room_effect("break_mood")


## Lo que suma a la meta de ánimo el escritorio del puesto de alguien.
func get_desk_mood(key: String) -> int:
	var desk: Dictionary = _seat_lookup_cache["desks"].get(key, {}) if not _seat_lookup_cache.is_empty() \
		else Workstations.station_desk_of(OfficeState.furniture, OfficeState.rooms, key)
	return 0 if desk.is_empty() else FurnitureCatalog.get_mood_bonus(desk["id"])


## Energía que pierde alguien por hora trabajada: la de su silla si tiene, si no la de data/staff.json.
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


## Ambiente medio de las Áreas de trabajo (0 sin ninguna).
func get_work_area_ambiance() -> float:
	var total: int = 0
	var count: int = 0
	for room: Dictionary in OfficeState.rooms:
		if room["type"] == Workstations.WORK_AREA:
			total += int(_ambiance_detail(room)["value"])
			count += 1
	return float(total) / count if count > 0 else 0.0
