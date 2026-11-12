# Prueba sin ventana del hito 15: equipos y turnos.
# Criterio: un empleado solo está en un equipo; cambiar el turno de un equipo cambia la
# hora a la que llegan sus miembros.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_teams.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261111
const WEEKDAYS: Array[int] = [0, 1, 2, 3, 4]

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_schedules()
	_check_teams()
	_check_contracts()
	_check_save()
	await _check_arrivals()
	await _check_panel()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)


# Un empleado de mentira (sin sueldo ni puesto) para probar la lógica de equipos.
func _add_fake(employee_id: int, role: String) -> Dictionary:
	var skills: Dictionary = {}
	for skill: String in StaffCatalog.get_skill_ids():
		skills[skill] = 50
	var employee: Dictionary = {"id": employee_id, "name": "Persona %d" % employee_id, "sex": "f", "age": 30, "role": role,
		"level": "junior", "asked_salary": 0, "skills": skills, "skill_low": skills.duplicate(), "traits": [],
		"interviewed": false, "known_traits": [], "hired_day": 0, "salary": 0, "schedule": StaffCatalog.get_role_schedule(role), "energy": 100, "mood": 70, "stress": 20,
		"paid_until": 0, "owed": 0}
	Staff._add_morale_fields(employee, {})
	Staff.employees.append(employee)
	return employee


func _days(values: Array) -> Array[int]:
	var days: Array[int] = []
	days.assign(values)
	return days


func _check_schedules() -> void:
	var day: WorkSchedule = WorkSchedule.make_shift(8, WEEKDAYS)
	_expect(day.describe() == "lun–vie 8:00–17:00" and day.get_lunch_hour() == 12 and day.get_duration() == 9,
		"turno de día: %s" % day.describe())
	_expect(day.is_working(0, 8) and day.is_lunch(0, 12) and not day.is_working(0, 17) and not day.is_working(5, 10),
		"horas del turno de día")
	var night: WorkSchedule = WorkSchedule.make_shift(22, WEEKDAYS)
	_expect(night.describe() == "lun–vie 22:00–7:00" and night.get_lunch_hour() == 2, "turno de noche: %s" % night.describe())
	_expect(night.is_working(0, 23) and night.is_working(1, 6) and not night.is_working(1, 7) and not night.is_working(0, 21),
		"el turno de noche cruza la medianoche")
	_expect(night.is_lunch(1, 2) and not night.is_working(0, 3) and night.is_working(5, 3), "almuerza a las 2; el sábado termina el del viernes")
	var sunday: WorkSchedule = WorkSchedule.make_shift(20, _days([6]))
	_expect(sunday.is_working(6, 23) and sunday.is_working(0, 4) and not sunday.is_working(0, 5), "del domingo al lunes")
	_expect(night.hours_until_next_work(0, 0) == 22, "lun 0:00 → lun 22:00 son 22 h")
	_expect(Staff.shift_problem(8, WEEKDAYS) == "", "lun–vie vale")
	_expect(Staff.shift_problem(8, _days([0, 1, 2, 3, 4, 5, 6])).contains("descanso"), "sin día de descanso no vale")
	_expect(Staff.shift_problem(8, _days([0, 1, 2, 3, 4, 5])) == "", "seis días con uno de descanso vale")
	_expect(not Staff.shift_problem(8, _days([])).is_empty() and not Staff.shift_problem(24, WEEKDAYS).is_empty(), "sin días u hora inválida")


func _check_teams() -> void:
	_new_game()
	var ana: Dictionary = _add_fake(901, "programmer")
	var beto: Dictionary = _add_fake(902, "designer")
	var first: Dictionary = Staff.create_team()
	var second: Dictionary = Staff.create_team()
	_expect(first["name"] == "Equipo 1" and second["name"] == "Equipo 2", "nombres de equipo")
	_expect(WorkSchedule.from_dict(first["schedule"]).describe() == "lun–vie 8:00–17:00", "turno por defecto")
	_expect(Staff.add_to_team(first["id"], 901)["ok"] and Staff.add_to_team(first["id"], 902)["ok"], "añadir dos al Equipo 1")
	_expect(not Staff.add_to_team(first["id"], 901)["ok"], "no se añade dos veces")
	_expect(Staff.add_to_team(second["id"], 901)["ok"], "pasar a Ana al Equipo 2")
	var only_beto: Array[int] = [902]
	var only_ana: Array[int] = [901]
	_expect(first["members"] == only_beto and second["members"] == only_ana, "un empleado solo está en un equipo")
	_expect(Staff.get_team_of(901)["id"] == second["id"], "equipo de Ana")
	# El turno del equipo manda sobre el del cargo.
	var key: String = Staff.employee_key(901)
	_expect(Staff.is_expected(key, 0, 8), "a las 8 con el turno por defecto")
	_expect(Staff.set_team_shift(second["id"], 10, _days([1, 2, 3, 4, 5]))["ok"], "cambiar el turno")
	_expect(not Staff.is_expected(key, 1, 9) and Staff.is_expected(key, 1, 10) and not Staff.is_expected(key, 1, 14)
		and Staff.is_expected(key, 1, 18) and not Staff.is_expected(key, 1, 19) and Staff.is_expected(key, 5, 10)
		and not Staff.is_expected(key, 0, 10), "con el turno nuevo llega a las 10, almuerza a las 14 y trabaja mar–sáb")
	_expect(Staff.is_at_lunch(key) == false, "no almuerza ahora")
	_expect(not Staff.set_team_shift(second["id"], 8, _days([0, 1, 2, 3, 4, 5, 6]))["ok"]
		and WorkSchedule.from_dict(second["schedule"]).start_hour == 10, "un turno sin descanso no se guarda")
	# Fuera del equipo vuelve al horario de su cargo.
	_expect(Staff.remove_from_team(901) and Staff.get_team_of(901).is_empty() and Staff.is_expected(key, 0, 8)
		and not Staff.remove_from_team(901), "sacar del equipo")
	var loose: Array[Dictionary] = Staff.get_employees_without_team()
	_expect(loose.size() == 1 and loose[0]["id"] == 901, "Ana queda sin equipo")
	_expect(Staff.get_active_team_count() == 1, "solo cuenta el equipo con miembros")
	_expect(Staff.delete_team(first["id"]) and Staff.get_team_of(902).is_empty() and Staff.teams.size() == 1, "borrar un equipo")
	# Despedir saca del equipo.
	Staff.add_to_team(second["id"], 902)
	_expect(Staff.fire(902)["ok"] and (second["members"] as Array).is_empty(), "despedir saca del equipo")
	_expect(ana["id"] == 901 and beto["id"] == 902, "datos")


func _check_contracts() -> void:
	_new_game()
	Projects.reputation = 5.0
	_add_fake(901, "programmer")
	_add_fake(902, "designer")
	_expect(Projects.get_contract_limit() == 1, "sin equipos: solo el contrato del CEO")
	var first_offer: int = Projects.offers[0]["id"]
	_expect(Projects.accept(first_offer)["ok"], "aceptar el primero")
	var first: Dictionary = Projects.get_contract(first_offer)
	_expect(first["team_id"] == Projects.CEO_TEAM and Projects.describe_owner(first) == "lo lleva el CEO", "sin equipos lo lleva el CEO")
	var empty_team: Dictionary = Staff.create_team()
	_expect(Projects.get_contract_limit() == 1, "un equipo vacío no suma")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], 901)
	_expect(Projects.get_contract_limit() == 2, "un equipo con miembros suma uno")
	while Projects.offers.size() < 2:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	var second_offer: int = Projects.offers[0]["id"]
	_expect(Projects.accept(second_offer)["ok"], "aceptar el segundo")
	var second: Dictionary = Projects.get_contract(second_offer)
	_expect(second["team_id"] == team["id"] and Projects.describe_owner(second) == "lo lleva %s" % team["name"],
		"el nuevo va al equipo libre")
	_expect(not Projects.accept(Projects.offers[0]["id"])["ok"], "tope de 2")
	# Un equipo lleva un contrato a la vez.
	_expect(Projects.assign(first_offer, team["id"])["ok"], "darle el primero al equipo")
	_expect(first["team_id"] == team["id"] and second["team_id"] == Projects.NO_TEAM and Projects.get_contract_of(Projects.CEO_TEAM).is_empty(),
		"el contrato anterior del equipo queda sin equipo")
	_expect(Projects.describe_owner(second) == "sin equipo", "sin equipo")
	_expect(Projects.assign(second_offer, Projects.CEO_TEAM)["ok"] and Projects.get_contract_of(Projects.CEO_TEAM)["id"] == second_offer,
		"el CEO toma el segundo")
	_expect(not Projects.assign(second_offer, 999)["ok"], "no se asigna a un equipo que no existe")
	# Borrar el equipo deja su contrato sin equipo.
	Staff.delete_team(team["id"])
	_expect(first["team_id"] == Projects.NO_TEAM, "borrar el equipo libera su contrato")
	_expect(Projects.get_contract_limit() == 1, "vuelve el tope de 1")
	Staff.delete_team(empty_team["id"])


func _check_save() -> void:
	_new_game()
	_add_fake(901, "programmer")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], 901)
	Staff.set_team_shift(team["id"], 22, WEEKDAYS)
	Projects.accept(Projects.offers[0]["id"])
	var staff_before: String = JSON.stringify(Staff.export_state())
	var projects_before: String = JSON.stringify(Projects.export_state())
	_expect(SaveManager.save_game("slot_5"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(JSON.stringify(Staff.export_state()) == staff_before and JSON.stringify(Projects.export_state()) == projects_before,
		"equipos y contratos vuelven igual")
	_expect(Staff.is_expected(Staff.employee_key(901), 1, 3), "el turno de noche vuelve")
	_expect(Staff.create_team()["name"] == "Equipo 2", "la numeración sigue")
	# Partida vieja sin equipos ni team_id: sin equipos y el contrato es del CEO.
	var old_staff: Dictionary = Staff.export_state()
	old_staff.erase("teams")
	old_staff.erase("next_team_id")
	Staff.import_state(old_staff)
	var old_projects: Dictionary = Projects.export_state()
	(old_projects["contracts"][0] as Dictionary).erase("team_id")
	Projects.import_state(old_projects)
	_expect(Staff.teams.is_empty() and Projects.contracts[0]["team_id"] == Projects.CEO_TEAM, "partida vieja")
	# Una partida con un empleado en dos equipos lo deja solo en el primero.
	var broken: Dictionary = Staff.export_state()
	broken["teams"] = [{"id": 1, "name": "A", "members": [901, 777], "schedule": team["schedule"]},
		{"id": 2, "name": "B", "members": [901]}]
	Staff.import_state(broken)
	var only: Array[int] = [901]
	_expect(Staff.teams[0]["members"] == only and (Staff.teams[1]["members"] as Array).is_empty()
		and WorkSchedule.from_dict(Staff.teams[1]["schedule"]).start_hour == 8, "datos rotos se corrigen")


# Con la escena: el miembro de un equipo con entrada a las 10 llega a las 10 y el
# programador sin equipo, a las 8 (el horario de su cargo).
func _check_arrivals() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameClock.stop()
	_build_stations()
	var vacancies: Array[int] = [Staff.open_vacancy("programmer", "junior", 1200, true)["id"],
		Staff.open_vacancy("designer", "junior", 1000, true)["id"]]
	GameClock.fast_forward_hours(1)  # lunes 9:00, llegan los candidatos
	for vacancy: int in vacancies:
		var candidate: Dictionary = Staff.get_vacancy(vacancy)["candidates"][0]
		_expect(Staff.make_offer(candidate["id"], candidate["asked_salary"])["result"] == "hired", "contratar a %s" % candidate["name"])
	_expect(Staff.employees.size() == 2, "dos empleados")
	var in_team: Dictionary = Staff.employees[0]
	var loose: Dictionary = Staff.employees[1]
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], in_team["id"])
	_expect(Staff.set_team_shift(team["id"], 10, WEEKDAYS)["ok"], "turno de 10 a 19")
	# Al cambiar el turno a media mañana (antes de las 10) el miembro se va.
	var member: Employee = game.employees[in_team["id"]]
	var other_one: Employee = game.employees[loose["id"]]
	if GameClock.get_hour() < 10:
		_expect(member.activity == OfficeCharacter.Activity.WALKING_OUT or member.activity == OfficeCharacter.Activity.AWAY,
			"antes de su entrada se va")
	# Hasta el próximo día hábil a las 7.
	var hours: int = posmod(7 - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	while GameClock.get_weekday() > 4:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(GameClock.get_hour() == 7, "a las 7")
	GameClock.fast_forward_hours(1)
	_expect(other_one.activity == OfficeCharacter.Activity.WALKING_TO_DESK, "a las 8 llega el que no tiene equipo")
	_expect(member.activity != OfficeCharacter.Activity.WALKING_TO_DESK, "a las 8 el del equipo no llega")
	GameClock.fast_forward_hours(1)
	_expect(member.activity != OfficeCharacter.Activity.WALKING_TO_DESK, "a las 9 tampoco")
	GameClock.fast_forward_hours(1)
	_expect(member.activity == OfficeCharacter.Activity.WALKING_TO_DESK, "a las 10 llega el del equipo")
	_expect(game.describe_employee_activity(in_team["id"]) != "fuera de su horario", "estado al llegar")
	# La ficha muestra el equipo y el turno.
	var card: EmployeeCard = game.get_node("EmployeeCard")
	card.open_employee(in_team["id"])
	_expect(card.get_text().contains("Equipo: %s" % team["name"]) and card.get_text().contains("lun–vie 10:00–19:00")
		and card.get_text().contains("almuerzo 14:00–15:00"), "ficha: %s" % card.get_text())
	card.close()
	game.queue_free()
	await get_tree().process_frame


func _build_stations() -> void:
	var builder := Builder.new()
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	Economy.earn(20000, "Prueba")
	_expect(builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	for x: int in [3, 5]:
		_expect(builder.place("simple_desk", Vector2i(x, 0), 2)["ok"], "escritorio en %d" % x)
		_expect(builder.place("basic_chair", Vector2i(x, 1), 0)["ok"], "silla en %d" % x)
		_expect(builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "computadora en %d" % x)


func _check_panel() -> void:
	_new_game()
	_add_fake(901, "programmer")
	_add_fake(902, "qa")
	Projects.accept(Projects.offers[0]["id"])
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameClock.stop()
	var panel: TeamsPanel = game.get_node("TeamsPanel")
	var projects_panel: ProjectsPanel = game.get_node("ProjectsPanel")
	var build_panel: BuildPanel = game.get_node("BuildPanel")
	_expect(panel.get_open_button().get_parent() == build_panel.get_menu_bar() and panel.get_open_button().text == "Equipos",
		"botón Equipos en la barra")
	await _click(projects_panel.get_open_button())
	await _click(panel.get_open_button())
	_expect(panel.is_open() and not projects_panel.is_open() and not GameClock.is_paused, "Equipos se abre, cierra Proyectos y no pausa")
	_expect(panel.get_list_text().contains("Equipos (0)") and panel.get_list_text().contains("Persona 901"), "sin equipos: %s" % panel.get_list_text())
	_expect(panel.get_ceo_project_choice().get_item_text(panel.get_ceo_project_choice().selected).contains(Projects.contracts[0]["client"]),
		"el CEO lleva el contrato")
	await _click(panel.get_create_button())
	await get_tree().process_frame
	_expect(Staff.teams.size() == 1, "crear equipo con el botón")
	var team_id: int = Staff.teams[0]["id"]
	var choice: OptionButton = panel.get_team_control(team_id, "add_choice")
	_expect(choice != null and choice.item_count == 2, "dos empleados para añadir")
	choice.select(1)
	await get_tree().process_frame
	await _click(panel.get_team_control(team_id, "add"))
	await get_tree().process_frame
	var only_qa: Array[int] = [902]
	_expect(Staff.teams[0]["members"] == only_qa, "añadir desde el panel")
	await _click(panel.get_team_control(team_id, "later"))
	await get_tree().process_frame
	_expect(WorkSchedule.from_dict(Staff.teams[0]["schedule"]).start_hour == 9, "+ atrasa la entrada")
	_expect(panel.get_list_text().contains("Turno: lun–vie 9:00–18:00 · almuerzo 13:00"), "turno en el panel")
	await _click(panel.get_team_control(team_id, "day_5"))
	await get_tree().process_frame
	var to_saturday: Array[int] = [0, 1, 2, 3, 4, 5]
	_expect(WorkSchedule.from_dict(Staff.teams[0]["schedule"]).days == to_saturday, "sumar el sábado")
	await _click(panel.get_team_control(team_id, "day_6"))
	await get_tree().process_frame
	_expect(panel.get_status_text().contains("descanso") and WorkSchedule.from_dict(Staff.teams[0]["schedule"]).days == to_saturday,
		"sin descanso no se puede: %s" % panel.get_status_text())
	var project: OptionButton = panel.get_team_control(team_id, "project")
	project.select(1)
	project.item_selected.emit(1)
	await get_tree().process_frame
	_expect(Projects.contracts[0]["team_id"] == team_id, "dar el contrato al equipo")
	_expect(panel.get_ceo_project_choice().selected == 0, "el CEO queda sin contrato")
	await _click(panel.get_team_control(team_id, "remove_902"))
	await get_tree().process_frame
	_expect((Staff.teams[0]["members"] as Array).is_empty(), "quitar del equipo")
	await _click(panel.get_team_control(team_id, "delete"))
	await get_tree().process_frame
	_expect(Staff.teams.is_empty() and Projects.contracts[0]["team_id"] == Projects.NO_TEAM, "borrar equipo desde el panel")
	game.queue_free()
	await get_tree().process_frame


func _click(control: Control) -> void:
	# Si está dentro de una lista con desplazamiento, la mueve hasta verlo.
	var parent: Node = control.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent != null:
		(parent as ScrollContainer).ensure_control_visible(control)
		await get_tree().process_frame
		await get_tree().process_frame
	var at: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	await _push(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _push(event)


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame
