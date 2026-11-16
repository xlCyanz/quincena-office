# Personal, capa 4: equipos, plantillas, agenda, horario propio y dirección (líderes, gerentes, ejecutivos).
extends "res://scripts/staff/staff_traits.gd"


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
	# Una sola pasada: se pide cada hora por equipo.
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


## Factor de un departamento: con ejecutivo 1 + su liderazgo; sin él, desde Mediana empresa,
## según cuántos dirige el CEO; si no, 1.
func get_department_factor(department: String) -> float:
	var executive: Dictionary = get_executive_of(department)
	if not executive.is_empty():
		return 1.0 + float(StaffCatalog.get_departments("executive_max_bonus")) * float(executive["skills"]["leadership"]) / 100.0
	if department.is_empty() or not departments_apply():
		return 1.0
	var factors: Array = StaffCatalog.get_departments("ceo_factors")
	return float(factors[mini(get_ceo_departments().size(), factors.size() - 1)])


## Pone a un ejecutivo a dirigir un departamento (uno por departamento). Devuelve {"ok", "message"}.
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


# Primer departamento sin ejecutivo, prefiriendo los que existen; "" si todos tienen.
func _free_department() -> String:
	for department: String in get_departments() + StaffCatalog.get_department_ids():
		if get_executive_of(department).is_empty():
			return department
	return ""


## Le da a un empleado un horario propio (entrada, días y horas extra). Devuelve {"ok", "message"}.
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


## Quita el horario propio: vuelve al de su equipo o su cargo.
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


## Pone a un empleado en un equipo (sale del anterior): un líder entra como líder si falta;
## los demás como miembros, hasta teams.max_members. Devuelve {"ok", "message"}.
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
	if StaffCatalog.is_role_without_teams(String(employee["role"])):
		return {"ok": false, "message": "%s es %s: no entra a equipos ni a proyectos." % [
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


## Líderes que dirige un gerente.
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


## Pone a un líder a cargo de un gerente (o del CEO con 0), si le queda lugar. Devuelve {"ok", "message"}.
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


## Indica si el gerente del líder de un equipo trabaja a esa hora.
func is_manager_present(team: Dictionary, at: int) -> bool:
	var manager: Dictionary = get_manager_of(get_team_leader(team))
	return not manager.is_empty() and is_expected(employee_key(manager["id"]), get_weekday_at(at),
		posmod(at, GameConstants.HOURS_PER_DAY))


## Indica si en esta etapa un equipo necesita a su líder presente para rendir al 100 %.
func leaders_required() -> bool:
	return Company.stage >= StaffCatalog.get_role_min_stage(StaffCatalog.get_leader_role())


## Factor de un equipo a esa hora: no_leader_factor sin su líder (desde la etapa de líderes), si no 1.
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


## Cambia el turno de un equipo (entrada, días con al menos uno libre, horas extra). Devuelve
## {"ok", "message"}.
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


## Borra una plantilla; sus equipos se quedan con su turno como propio.
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


## Hace que un equipo siga una plantilla, o NO_TEMPLATE para quedarse con su turno. Devuelve
## {"ok", "message"}.
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


## Agenda de un día: una fila por equipo y por persona con horario propio, {"kind", "id",
## "label", "cells"}; cells son 24 estados AGENDA_* de las horas que empiezan ese día.
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
	# Recepción: las horas en que un cliente puede estar esperando.
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


# Hueco: desde la etapa de líderes, un equipo con miembros trabaja sin su líder.
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


## Equipos que tienen al menos un miembro (cada uno puede llevar un contrato).
func get_active_team_count() -> int:
	var count: int = 0
	for team: Dictionary in teams:
		if not (team["members"] as Array).is_empty():
			count += 1
	return count


# Saca a un empleado del equipo en que esté. Devuelve true si estaba en alguno.
func _leave_team(employee_id: int) -> bool:
	var team: Dictionary = get_team_of(employee_id)
	if team.is_empty():
		return false
	if int(team.get("leader_id", 0)) == employee_id:
		team["leader_id"] = 0
	(team["members"] as Array).erase(employee_id)
	return true


# Cambió quién trabaja a qué hora: los personajes revisan si llegan o se van.
func _schedules_changed() -> void:
	EventBus.staff_changed.emit()
	EventBus.presence_changed.emit()


## Descuento del mantenimiento (0.1 = 10 %): el del contador por el factor de Administración, o 0.
func get_maintenance_discount() -> float:
	if not has_accountant():
		return 0.0
	return float(StaffCatalog.get_accounting("maintenance_discount")) * get_department_factor("administration") * get_printer_factor()


## Descuento de la tasa mensual de un préstamo nuevo (0.01 = 1 punto), o 0 sin contador.
func get_loan_rate_discount() -> float:
	if not has_accountant():
		return 0.0
	return float(StaffCatalog.get_accounting("loan_rate_discount")) * get_department_factor("administration") * get_printer_factor()


# Cada hora: quien trabajó ensucia su habitación y limpieza en su turno limpia la más sucia.
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
	# Se suman las personas-hora por habitación y se ensucia cada una una vez.
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
	for cleaner: Dictionary in cleaners:
		var dirtiest: int = OfficeState.get_dirtiest_room()
		if dirtiest < 0:
			continue
		var share: float = _trait_product(cleaner, "clean")
		# La hora de entrada solo limpia desde start_minute.
		if _cached_schedule_in(cleaner, team_map.get(int(cleaner["id"]), {})).start_hour == hour:
			share *= float(60 - get_cleaning_minutes(cleaner).y) / 60.0
		if share > 0.0:
			OfficeState.clean_room(dirtiest, amount * share)
			changed = true
	if not changed:
		return
	for index: int in range(OfficeState.rooms.size()):
		if not was_dirty[index] and OfficeState.is_room_dirty(OfficeState.rooms[index]):
			EventBus.send_notice(EventBus.target_room(OfficeState.rooms[index]["cells"][0]), "%s está sucia: baja el ánimo de quienes trabajan ahí." % RoomCatalog.get_display_name(OfficeState.rooms[index]["type"]))
	EventBus.dirt_changed.emit()


# Campos de ánimo de un empleado (de una partida guardada o nuevos).
func _add_morale_fields(employee: Dictionary, saved: Dictionary) -> void:
	employee["carry"] = int(saved.get("carry", 0))
	employee["own_schedule"] = bool(saved.get("own_schedule", false))
	employee["overtime_pay"] = float(saved.get("overtime_pay", 0.0))
	employee["night_pay"] = float(saved.get("night_pay", 0.0))
	# Lo debido de extras y noche nunca pasa de lo debido en total.
	employee["owed_overtime"] = clampi(int(saved.get("owed_overtime", 0)), 0, int(employee["owed"]))
	employee["owed_night"] = clampi(int(saved.get("owed_night", 0)), 0, int(employee["owed"]) - int(employee.get("owed_overtime", 0)))
	employee["bad_days"] = int(saved.get("bad_days", 0))
	employee["quit_day"] = int(saved.get("quit_day", NO_QUIT))
	employee["min_energy"] = int(saved.get("min_energy", employee["energy"]))
	employee["projects_worked"] = int(saved.get("projects_worked", 0))
	# Historial; missing_from/missing_until son las horas absolutas en que falta y
	# promotion_ready_day, desde cuándo puede ascender.
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
