# Personal, capa 5: nómina, despidos, aumentos, ascensos, ofertas de otras empresas, ánimo y estrés.
extends "res://scripts/staff/staff_teams.gd"


## Lo ganado desde el último pago hasta hoy incluido (sin la deuda).
func get_earned(employee: Dictionary) -> int:
	var days: int = GameClock.get_day_count() - int(employee["paid_until"])
	return int(employee.get("carry", 0)) + maxi(0, roundi(int(employee["salary"]) * days / float(GameConstants.DAYS_PER_MONTH)))


## Lo que cuesta despedir hoy: lo ganado (con extras) más lo debido.
func get_firing_cost(employee: Dictionary) -> int:
	return get_earned(employee) + get_extra_earned(employee) + int(employee["owed"])


## Horas extra y recargo nocturno ganados desde la última nómina, sin pagar todavía.
func get_extra_earned(employee: Dictionary) -> int:
	return roundi(float(employee.get("overtime_pay", 0.0))) + roundi(float(employee.get("night_pay", 0.0)))


## Valor de una hora normal: sueldo / 30 / overtime.base_hours.
static func get_hour_pay(employee: Dictionary) -> float:
	return float(employee["salary"]) / GameConstants.DAYS_PER_MONTH / float(StaffCatalog.get_overtime("base_hours"))


## Deuda total de nóminas sin pagar.
func get_total_owed() -> int:
	var total: int = 0
	for employee: Dictionary in employees:
		total += int(employee["owed"])
	return total


## Despide: cobra lo ganado y lo debido, libera el puesto y baja el ánimo de los demás (más con
## otro despido reciente). Devuelve {"ok", "message"}.
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


## Sube el sueldo (lo ganado hasta hoy queda con el anterior). Desde retain_raise_ratio retiene
## a quien avisó que renuncia; si cubre lo pedido, acepta el pedido. Devuelve {"ok", "message"}.
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


# Cambia el sueldo y resuelve pedido de aumento y aviso de renuncia; devuelve los textos del aviso.
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


## Por qué un cargo aún no existe en esta etapa, o "".
func role_problem(role: String) -> String:
	var min_stage: int = StaffCatalog.get_role_min_stage(role)
	if Company.stage < min_stage:
		return "El cargo %s se desbloquea en %s." % [StaffCatalog.get_role_name(role), Company.get_stage_name(min_stage)]
	return ""


## Progreso al nivel siguiente: {"next_level", "next_role", "projects", "projects_needed", "days",
## "days_needed", "ready"}. next_level "" sin niveles o Senior; next_role, ascenso a otro cargo.
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
	# blocker: "stage" si el cargo aún no existe, "station" si no hay dónde trabaje, o "".
	progress["blocker"] = ""
	if not next_role.is_empty():
		if not role_problem(next_role).is_empty():
			progress["blocker"] = "stage"
		elif StaffCatalog.get_workplace(next_role) != StaffCatalog.get_workplace(role) \
				and not get_station_problem(next_role).is_empty():
			progress["blocker"] = "station"
		progress["ready"] = String(progress["blocker"]).is_empty()
	return progress


## Por qué no se puede ascender con ese sueldo, o "".
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


## Asciende al nivel o cargo siguiente con un sueldo mayor; la habilidad principal sube al
## mínimo del nivel y cuenta como aumento. Devuelve {"ok", "message"}.
func promote(employee_id: int, new_salary: int) -> Dictionary:
	var problem: String = promote_problem(employee_id, new_salary)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var employee: Dictionary = get_employee(employee_id)
	# La espera del ambicioso vuelve a contar desde que pueda otra vez.
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


# Asciende a otro cargo. Un miembro de un equipo sin líder pasa a liderarlo; si tenía líder,
# queda sin equipo.
func _promote_to_role(employee: Dictionary, role: String, new_salary: int) -> Dictionary:
	var team: Dictionary = get_team_of(employee["id"])
	_leave_team(employee["id"])
	var key: String = employee_key(employee["id"])
	if StaffCatalog.get_workplace(role) != StaffCatalog.get_workplace(employee["role"]):
		# Deja su silla y toma una libre de su nuevo lugar de trabajo.
		for item: Dictionary in OfficeState.furniture:
			if item["assigned_to"] == key:
				item["assigned_to"] = ""
		OfficeState.furniture[get_free_workstations(role)[0]["chair"]]["assigned_to"] = key
		EventBus.office_changed.emit()
	if employee["role"] == StaffCatalog.get_leader_role():
		# Un ex líder no tiene gerente y un gerente nuevo no dirige a nadie.
		employee.erase("manager_id")
	if is_manager(employee):
		# Sus líderes pasan al CEO.
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


## Niega el aumento pedido (baja el ánimo).
func deny_raise(employee_id: int) -> bool:
	var employee: Dictionary = get_employee(employee_id)
	if employee.is_empty() or (employee["raise_request"] as Dictionary).is_empty():
		return false
	employee["raise_request"] = {}
	_change_mood(employee, int(StaffCatalog.get_morale("raise_deny_mood")))
	EventBus.staff_changed.emit()
	return true


## Probabilidad diaria de una oferta de otra empresa (0 si no es SemiSenior, Senior ni dirección).
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


## Meta del ánimo de un empleado hoy (data/staff.json, morale).
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


# Cada día: desde cuándo puede ascender cada ambicioso.
func _update_promotion_waits() -> void:
	for employee: Dictionary in employees:
		if _trait_value(employee, "promotion_wait_days") <= 0.0:
			continue
		var ready: bool = bool(get_promotion_progress(employee)["ready"])
		if not ready:
			employee["promotion_ready_day"] = NOT_MISSING
		elif int(employee.get("promotion_ready_day", NOT_MISSING)) == NOT_MISSING:
			employee["promotion_ready_day"] = GameClock.get_day_count()


## Indica si un ambicioso lleva tanto sin ascenso que se molesta.
func is_waiting_promotion(employee: Dictionary) -> bool:
	var since: int = int(employee.get("promotion_ready_day", NOT_MISSING))
	var wait: float = _trait_value(employee, "promotion_wait_days")
	return wait > 0.0 and since != NOT_MISSING and GameClock.get_day_count() - since >= int(wait)


## Meta del estrés de un empleado hoy.
func get_stress_target(employee: Dictionary) -> int:
	var target: float = StaffCatalog.get_morale("stress_base")
	var contract: Dictionary = _contract_of(employee)
	if contract.has("deadline_day") and Projects.get_days_late(contract) > 0:
		target += StaffCatalog.get_morale("late_stress")
	if int(employee.get("min_energy", 100)) < int(StaffCatalog.get_morale("tired_below")):
		target += StaffCatalog.get_morale("tired_stress")
	# Con gerente, los equipos se estresan menos.
	var team: Dictionary = get_team_of(employee["id"])
	if not team.is_empty() and not get_manager_of(get_team_leader(team)).is_empty():
		target += float(StaffCatalog.get_management("manager_stress"))
	target += float(StaffCatalog.get_overtime("stress_per_hour")) * get_schedule(employee).overtime
	var room: Dictionary = get_workplace_room(employee_key(employee["id"]))
	if not room.is_empty():
		target -= int(_ambiance_detail(room)["stress_relief"])
	return clampi(roundi(target), 0, 100)


## Suma a "mood", "energy" o "stress" (0–100) de todos o de los ids dados (eventos).
func change_all(key: String, amount: int, ids: Array[int] = []) -> void:
	for employee: Dictionary in employees:
		if not ids.is_empty() and not ids.has(int(employee["id"])):
			continue
		if employee[key] is float:
			employee[key] = clampf(float(employee[key]) + amount, 0.0, 100.0)
		else:
			employee[key] = clampi(int(employee[key]) + amount, 0, 100)
	EventBus.staff_changed.emit()


## Indica si un empleado no tiene trabajo: su equipo no lleva proyecto (salvo vendedores).
func is_idle(employee: Dictionary) -> bool:
	return not Production.get_role_phase(employee["role"]).is_empty() and _contract_of(employee).is_empty()


## Icono de estado: el primero de status_icons.order que se cumple, o "".
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


# Proyecto que lleva el equipo de un empleado (contrato o producto en desarrollo), o vacío.
func _contract_of(employee: Dictionary) -> Dictionary:
	var team: Dictionary = get_team_of(employee["id"])
	if team.is_empty():
		return {}
	var contract: Dictionary = Projects.get_contract_of(team["id"])
	return contract if not contract.is_empty() else Products.get_product_of(team["id"])


# Saca a un empleado: cobra lo ganado y lo debido con ese concepto y libera puesto y equipo.
# Devuelve lo cobrado.
func _remove_employee(employee: Dictionary, concept: String) -> int:
	var cost: int = get_firing_cost(employee)
	# Primero deja de ser empleado, así su deuda no cuenta en la nómina pendiente.
	employees.erase(employee)
	_leave_team(employee["id"])
	# Sus líderes pasan al CEO.
	for leader: Dictionary in get_leaders_of(employee["id"]):
		leader["manager_id"] = 0
	# Si hacía una entrevista, se corta.
	if String(interview.get("by", "")) == employee_key(employee["id"]):
		interview = {}
	for appointment: Dictionary in appointments.duplicate():
		if String(appointment["by"]) == employee_key(employee["id"]):
			appointments.erase(appointment)
	Economy.charge(cost, concept)
	var key: String = employee_key(employee["id"])
	for item: Dictionary in OfficeState.furniture:
		if item["assigned_to"] == key:
			item["assigned_to"] = ""
	return cost


# Cada día: ánimo y estrés hacia su meta, vencen pedidos, se van los que avisaron, avisan los
# que llevan días mal y a veces alguien pide aumento.
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


## Costo de la nómina que llega en days_ahead días: lo ganado, esos días, extras y lo debido.
func estimate_payroll(days_ahead: int) -> int:
	var total: int = 0
	for employee: Dictionary in employees:
		total += get_firing_cost(employee) + roundi(int(employee["salary"]) * days_ahead / float(GameConstants.DAYS_PER_MONTH))
	return total


# El contador avisa warning_days días antes de cada nómina y día 1 si el saldo de hoy no alcanza.
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


# Anota lo ganado como deuda y trata de pagarla; si no alcanza, queda y baja el ánimo de todos.
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
	# Antes de castigar se ofrece el préstamo de emergencia; se marca antes porque la
	# respuesta puede llegar dentro de la misma señal.
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


# Cambia la energía según la hora que terminó (trabajo o descanso) y suma horas extra y recargo.
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
		# El horario a mano: las horas extra se pagan aunque llegue tarde o falte.
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
			# Almorzó dentro: descansa el doble, y con café algo más.
			change = lunch_rest
		elif on_break.has(employee_key(employee["id"])):
			# Pausa en la Sala de descanso.
			change = break_rest
		elif present:
			change = _work_energy_of(seats.get(employee_key(employee["id"]), {}))
			if coffee:
				change += int(_trait_value(employee, "coffee_energy"))
		employee["energy"] = clampi(int(employee["energy"]) + change, 0, 100)
		employee["min_energy"] = mini(int(employee.get("min_energy", 100)), int(employee["energy"]))
	EventBus.staff_changed.emit()
