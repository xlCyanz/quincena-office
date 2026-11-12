# Prueba del hito 33: departamentos y ejecutivos.
# Criterio: con 3 departamentos a cargo del CEO cada uno rinde 70 %; con un ejecutivo en
# Desarrollo ese vuelve al 100 % más su ventaja y los otros dos suben a 85 %.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=departments
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261115
const EXECUTIVE: String = "executive"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_stage()
	_check_departments()
	_check_executives()
	_check_production()
	_check_promotion()
	_check_interviews()
	_check_save()
	await _check_ui()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva en Mediana empresa con un área de trabajo de tres puestos, dos oficinas
# únicas, dinero de sobra y los objetivos cumplidos.
func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Company.stage = 3
	Economy.earn(100000, "Prueba")
	var builder := Builder.new()
	var x: int = GridEdge.AXIS_X
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	for cell_x: int in [3, 4, 5]:
		_expect(builder.place("simple_desk", Vector2i(cell_x, 0), 2)["ok"], "escritorio en %d" % cell_x)
		_expect(builder.place("basic_chair", Vector2i(cell_x, 1), 0)["ok"], "silla en %d" % cell_x)
		_expect(builder.install_computer("basic_computer", Vector2i(cell_x, 0))["ok"], "computadora en %d" % cell_x)
	_build_office(builder, [
		{"edge": Vector3i(0, 5, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(1, 5, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(1, 6, x), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(1, 7, x), "kind": ConstructionCatalog.WALL},
	], Vector2i(0, 6))
	_build_office(builder, [
		{"edge": Vector3i(4, 5, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 5, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(3, 6, x), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(3, 7, x), "kind": ConstructionCatalog.WALL},
	], Vector2i(5, 6))


func _build_office(builder: Builder, walls: Array[Dictionary], desk: Vector2i) -> void:
	_expect(builder.apply(walls)["ok"], "paredes de la oficina en %s" % desk)
	_expect(builder.mark_room(Workstations.SINGLE_OFFICE, desk)["ok"], "marcar la oficina en %s" % desk)
	_expect(builder.place("simple_desk", desk, 2)["ok"], "escritorio de la oficina en %s" % desk)
	_expect(builder.place("basic_chair", desk + Vector2i(0, 1), 0)["ok"], "silla de la oficina en %s" % desk)


func _hire(role: String, level: String) -> Dictionary:
	var candidate: Dictionary = _candidate(role, level)
	var result: Dictionary = Staff.make_offer(candidate["id"], candidate["asked_salary"])
	var employee: Dictionary = Staff.get_employee(candidate["id"])
	_expect(not employee.is_empty(), "contratado: %s %s (%s)" % [role, level, result["message"]])
	return employee


func _candidate(role: String, level: String) -> Dictionary:
	var opened: Dictionary = Staff.open_vacancy(role, level, StaffCatalog.get_salary(role, level), true)
	_expect(opened["ok"], "publicar %s: %s" % [role, opened["message"]])
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	return Staff.get_vacancy(opened["id"])["candidates"][0]


# Un empleado de mentira de ese cargo (sin puesto), para contar departamentos.
func _fake(role: String) -> Dictionary:
	# El primero se contrata de verdad y sirve de molde para los demás.
	if Staff.employees.is_empty():
		return _hire(role, "junior")
	var fake: Dictionary = Staff.employees[0].duplicate(true)
	fake["id"] = 3000 + Staff.employees.size()
	fake["role"] = role
	fake["level"] = "junior"
	fake.erase("department")
	fake.erase("manager_id")
	Staff.employees.append(fake)
	return fake


func _check_stage() -> void:
	_new_game()
	var requirements: Array[Dictionary] = Company.get_requirements(3)
	_expect(requirements.size() == 1 and requirements[0]["key"] == "employees" and int(requirements[0]["needed"]) == 40,
		"Mediana empresa pide solo 40 empleados: %s" % [requirements])
	Company.stage = 2
	var opened: Dictionary = Staff.open_vacancy(EXECUTIVE, "senior", 9000, false)
	_expect(not opened["ok"] and String(opened["message"]).contains("Mediana empresa"), "en Pequeña empresa no hay ejecutivos: %s" % opened["message"])
	_expect(Company.count_requirement("executives") == 0, "ningún ejecutivo")
	Company.stage = 3
	_hire(EXECUTIVE, "senior")
	_expect(Company.count_requirement("executives") == 1, "el requisito de Corporación cuenta ejecutivos")


func _check_departments() -> void:
	_new_game()
	_expect(Staff.get_departments().is_empty(), "sin empleados no hay departamentos")
	_fake("programmer")
	_expect(Staff.get_departments() == (["development"] as Array[String]), "un programador hace Desarrollo")
	_expect(is_equal_approx(Staff.get_department_factor("development"), 1.0), "1 departamento: 100 %")
	_fake("qa")
	_expect(Staff.get_departments().size() == 1 and Staff.get_department_size("development") == 2, "QA también es Desarrollo")
	_fake("designer")
	_expect(is_equal_approx(Staff.get_department_factor("design"), 0.85), "2 departamentos: 85 %")
	_fake("salesperson")
	_expect(Staff.get_departments() == (["development", "design", "sales"] as Array[String]), "tres departamentos: %s" % [Staff.get_departments()])
	for department: String in Staff.get_departments():
		_expect(is_equal_approx(Staff.get_department_factor(department), 0.7), "3 departamentos: %s rinde 70 %%" % department)
	_expect(is_equal_approx(float(StaffCatalog.get_departments("ceo_factors")[4]), 0.55), "con 4 rendiría 55 %")
	# Líderes y gerentes no son de ningún departamento.
	_fake("team_leader")
	_fake("manager")
	_expect(Staff.get_departments().size() == 3, "líderes y gerentes no hacen departamentos")
	# Antes de Mediana empresa todo rinde 100 %.
	Company.stage = 2
	_expect(is_equal_approx(Staff.get_department_factor("development"), 1.0), "en Pequeña empresa, 100 %")
	Company.stage = 3
	# Ventas: lo que suman los vendedores baja con el rendimiento.
	var base: float = float(ContractCatalog.get_offers("chance"))
	var per_seller: float = float(ContractCatalog.get_offers("chance_per_salesperson"))
	_expect(is_equal_approx(Projects.get_offer_chance(), base + per_seller * 0.7), "ofertas con Ventas al 70 %%: %.3f" % Projects.get_offer_chance())


func _check_executives() -> void:
	_new_game()
	_fake("programmer")
	_fake("designer")
	_fake("salesperson")
	var executive: Dictionary = _hire(EXECUTIVE, "senior")
	_expect(executive["department"] == "development", "dirige el primer departamento sin ejecutivo: %s" % executive["department"])
	var bonus: float = 0.1 * float(executive["skills"]["leadership"]) / 100.0
	_expect(is_equal_approx(Staff.get_department_factor("development"), 1.0 + bonus), "Desarrollo: 100 %% más su ventaja (%.3f)" % Staff.get_department_factor("development"))
	_expect(is_equal_approx(Staff.get_department_factor("design"), 0.85) and is_equal_approx(Staff.get_department_factor("sales"), 0.85), "los otros dos suben a 85 %")
	_expect(Staff.has_working_station(executive), "trabaja en su oficina")
	# Fuera de su horario sigue dirigiendo.
	while Staff.is_expected_now(Staff.employee_key(executive["id"])):
		GameClock.fast_forward_hours(1)
	_expect(is_equal_approx(Staff.get_department_factor("development"), 1.0 + bonus), "dirige aunque no esté")
	# El segundo toma el siguiente libre; no se repiten.
	var second: Dictionary = _hire(EXECUTIVE, "senior")
	_expect(second["department"] == "design", "el segundo dirige Diseño: %s" % second["department"])
	var taken: Dictionary = Staff.set_executive_department(second["id"], "development")
	_expect(not taken["ok"] and String(taken["message"]).contains("ya lo dirige"), "uno por departamento: %s" % taken["message"])
	_expect(Staff.set_executive_department(second["id"], "administration")["ok"], "puede dirigir Administración aunque no exista")
	_expect(is_equal_approx(Staff.get_department_factor("design"), 0.85), "Diseño vuelve al CEO, que dirige 2: 85 %")
	# No entran a equipos.
	var team: Dictionary = Staff.create_team()
	var refused: Dictionary = Staff.add_to_team(team["id"], executive["id"])
	_expect(not refused["ok"] and String(refused["message"]).contains("no entra a un equipo"), "un ejecutivo no entra a un equipo: %s" % refused["message"])
	# Al irse, su departamento vuelve al CEO.
	Staff.fire(executive["id"])
	_expect(is_equal_approx(Staff.get_department_factor("development"), 0.7), "sin ejecutivo, Desarrollo vuelve al CEO")


func _check_production() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	worker["energy"] = 100
	worker["mood"] = 100
	_fake("designer")
	_fake("salesperson")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], worker["id"])
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	Projects.assign(contract["id"], team["id"])
	var at: int = Staff.get_absolute_hour() + 1
	while Staff.get_weekday_at(at) >= 5 or posmod(at, 24) != 10:
		at += 1
	var full: float = Production.get_rate("junior", 100.0, 0.0, 100.0)
	# Mediana empresa: sin líder 75 %, y Desarrollo al 70 % con 3 departamentos del CEO.
	var rate: float = float(Projects.get_workers(contract, at)[0]["rate"])
	_expect(is_equal_approx(rate, full * 0.75 * 0.7), "rinde 75 %% × 70 %%: %.3f" % rate)
	var executive: Dictionary = _hire(EXECUTIVE, "senior")
	var factor: float = Staff.get_department_factor("development")
	rate = float(Projects.get_workers(contract, at)[0]["rate"])
	_expect(is_equal_approx(rate, full * 0.75 * factor), "con ejecutivo en Desarrollo: %.3f" % rate)


func _check_promotion() -> void:
	_new_game()
	var manager: Dictionary = _hire("manager", "senior")
	var leader: Dictionary = _hire("team_leader", "senior")
	Staff.set_manager(leader["id"], manager["id"])
	_fake("designer")
	var progress: Dictionary = Staff.get_promotion_progress(manager)
	_expect(progress["next_role"] == EXECUTIVE and bool(progress["ready"]), "un gerente puede ascender a ejecutivo")
	var result: Dictionary = Staff.promote(manager["id"], 9000)
	_expect(result["ok"] and String(result["message"]).contains("Dirige Diseño"), "asciende y dirige Diseño: %s" % result["message"])
	_expect(manager["role"] == EXECUTIVE and int(leader["manager_id"]) == 0, "sus líderes vuelven al CEO")
	_expect(Staff.has_working_station(manager), "sigue en su oficina")
	_expect(String(Staff.get_promotion_progress(manager)["next_role"]).is_empty(), "un ejecutivo es lo más alto")


func _check_interviews() -> void:
	_new_game()
	var executive: Dictionary = _hire(EXECUTIVE, "senior")
	var waiting: Dictionary = _candidate("qa", "junior")
	var candidate: Dictionary = _candidate("designer", "junior")
	_expect(Staff.interview_problem(candidate["id"], true).contains("Administración"), "sin ejecutivo de Administración no se delega")
	Staff.set_executive_department(executive["id"], "administration")
	_expect(Staff.get_interviewer() == executive, "el de Administración entrevista")
	var started: Dictionary = Staff.start_interview(candidate["id"], true)
	_expect(started["ok"] and String(started["message"]).contains("(ejecutivo)"), "delegada: %s" % started["message"])
	_expect(Staff.interview["by"] == Staff.employee_key(executive["id"]), "la hace el ejecutivo")
	_expect(Staff.is_ceo_producing(Staff.get_absolute_hour()), "el CEO sigue trabajando")
	_expect(Staff.interview_problem(waiting["id"]).contains("ya está en una entrevista"), "una entrevista a la vez: %s" % Staff.interview_problem(waiting["id"]))
	Staff.set_ceo_at_work(false)
	_expect(not Staff.interview.is_empty(), "si el CEO se va, la del ejecutivo sigue")
	Staff.set_ceo_at_work(true)
	GameClock.fast_forward_hours(int(StaffCatalog.get_hiring("interview_hours")))
	_expect(bool(Staff.get_candidate(candidate["id"]).get("interviewed", false)), "termina y queda entrevistado")
	# De noche el ejecutivo no está.
	while GameClock.get_hour() != 20:
		GameClock.fast_forward_hours(1)
	var other: Dictionary = _candidate("qa", "junior")
	while GameClock.get_hour() != 20:
		GameClock.fast_forward_hours(1)
	_expect(Staff.interview_problem(other["id"], true).contains("tiene que estar en la oficina"), "fuera de su horario no entrevista: %s" % Staff.interview_problem(other["id"], true))
	# Despedirlo corta su entrevista.
	while GameClock.get_hour() != 10 or GameClock.get_weekday() >= 5:
		GameClock.fast_forward_hours(1)
	var last: Dictionary = _candidate("qa", "junior")
	while GameClock.get_hour() != 10 or GameClock.get_weekday() >= 5:
		GameClock.fast_forward_hours(1)
	_expect(Staff.start_interview(last["id"], true)["ok"], "otra entrevista delegada")
	Staff.fire(executive["id"])
	_expect(Staff.interview.is_empty(), "al irse el ejecutivo, la entrevista se corta")


func _check_save() -> void:
	_new_game()
	var executive: Dictionary = _hire(EXECUTIVE, "senior")
	var other: Dictionary = _hire(EXECUTIVE, "senior")
	var candidate: Dictionary = _candidate("designer", "junior")
	Staff.set_executive_department(other["id"], "administration")
	Staff.start_interview(candidate["id"], true)
	var before: String = JSON.stringify(Staff.export_state())
	_expect(SaveManager.save_game("slot_4"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_4"), "cargar")
	_expect(JSON.stringify(Staff.export_state()) == before, "ejecutivos y entrevista delegada vuelven igual")
	var old: Dictionary = Staff.export_state()
	for saved: Dictionary in old["employees"]:
		if saved["role"] == EXECUTIVE:
			saved["department"] = "development"
	old["interview"].erase("by")
	Staff.import_state(old)
	_expect(Staff.get_employee(executive["id"])["department"] == "development" and Staff.get_employee(other["id"])["department"] == "",
		"dos en el mismo departamento: el segundo queda sin ninguno")
	_expect(Staff.interview["by"] == "ceo", "una entrevista de antes la hace el CEO")


func _check_ui() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var worker: Dictionary = _hire("programmer", "junior")
	_hire("designer", "junior")
	_hire("salesperson", "junior")
	var staff_panel: StaffPanel = game.get_node("StaffPanel")
	staff_panel.set_open(true)
	await get_tree().process_frame
	var text: String = staff_panel.get_list_text()
	_expect(text.contains("Desarrollo · 1 persona · lo dirige el CEO · rinde 70 %"), "organigrama con departamentos: %s" % text)
	var card: EmployeeCard = game.get_node("EmployeeCard")
	card.open_employee(worker["id"])
	await get_tree().process_frame
	_expect(card.get_text().contains("Departamento: Desarrollo, lo dirige el CEO (rinde 70 %)"), "ficha del programador: %s" % card.get_text())
	var executive: Dictionary = _hire(EXECUTIVE, "senior")
	await get_tree().process_frame
	var percent: int = roundi(Staff.get_department_factor("development") * 100.0)
	text = staff_panel.get_list_text()
	_expect(text.contains("Desarrollo · 1 persona · lo dirige %s · rinde %d %%" % [executive["name"], percent]), "Desarrollo con ejecutivo: %s" % text)
	_expect(text.contains("Diseño · 1 persona · lo dirige el CEO · rinde 85 %"), "Diseño al 85 %%: %s" % text)
	var choice: OptionButton = staff_panel.get_department_choice(executive["id"])
	_expect(choice != null and choice.get_item_text(choice.selected) == "Dirige Desarrollo", "lista del ejecutivo")
	choice.select(3)
	choice.item_selected.emit(3)
	await get_tree().process_frame
	_expect(executive["department"] == "administration", "elegir Administración desde el organigrama")
	var candidate: Dictionary = _candidate("qa", "junior")
	await get_tree().process_frame
	var delegate: Button = staff_panel.get_delegate_button(candidate["id"])
	_expect(delegate != null and not delegate.disabled, "con ejecutivo de Administración aparece Delegar")
	delegate.pressed.emit()
	await get_tree().process_frame
	_expect(Staff.interview.get("by", "") == Staff.employee_key(executive["id"]), "Delegar inicia la entrevista del ejecutivo")
	_expect(staff_panel.get_list_text().contains("En entrevista con %s" % executive["name"]), "la lista dice quién entrevista")
	staff_panel.set_open(false)
	card.open_employee(executive["id"])
	await get_tree().process_frame
	_expect(card.get_text().contains("Dirige Administración"), "ficha del ejecutivo: %s" % card.get_text())
	var company: CompanyPanel = game.get_node("CompanyPanel")
	company.set_open(true)
	await get_tree().process_frame
	text = company.get_text()
	_expect(text.contains("Departamentos") and text.contains("Diseño (el CEO)"), "Empresa muestra los departamentos: %s" % text)
	company.set_open(false)
	game.queue_free()
	await get_tree().process_frame
