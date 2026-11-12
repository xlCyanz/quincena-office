# Prueba sin ventana del hito 32: gerentes y organigrama.
# Criterio: sin Oficina única libre no se contrata un gerente; los equipos de sus líderes
# rinden 110 % y bajan el estrés; un sexto líder sin gerente no se puede nombrar.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_managers.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261114
const LEADER: String = "team_leader"
const MANAGER: String = "manager"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_offices()
	_check_unlock()
	_check_promotion()
	_check_hiring()
	_check_caps()
	_check_effects()
	_check_save()
	await _check_ui()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva en Pequeña empresa con un área de trabajo de tres puestos, dinero de
# sobra, los objetivos cumplidos y, si se pide, oficinas únicas amuebladas (hasta 2).
func _new_game(offices: int = 0) -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Company.stage = 2
	Economy.earn(80000, "Prueba")
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
	if offices >= 1:
		_build_office(builder, [
			{"edge": Vector3i(0, 5, y), "kind": ConstructionCatalog.WALL},
			{"edge": Vector3i(1, 5, y), "kind": ConstructionCatalog.DOOR},
			{"edge": Vector3i(1, 6, x), "kind": ConstructionCatalog.WALL},
			{"edge": Vector3i(1, 7, x), "kind": ConstructionCatalog.WALL},
		], Vector2i(0, 6))
	if offices >= 2:
		_build_office(builder, [
			{"edge": Vector3i(4, 5, y), "kind": ConstructionCatalog.DOOR},
			{"edge": Vector3i(5, 5, y), "kind": ConstructionCatalog.WALL},
			{"edge": Vector3i(3, 6, x), "kind": ConstructionCatalog.WALL},
			{"edge": Vector3i(3, 7, x), "kind": ConstructionCatalog.WALL},
		], Vector2i(5, 6))


# Una Oficina única de 2 × 2 con un escritorio en desk y la silla delante (al sur).
func _build_office(builder: Builder, walls: Array[Dictionary], desk: Vector2i) -> void:
	_expect(builder.apply(walls)["ok"], "paredes de la oficina en %s" % desk)
	_expect(builder.mark_room(Workstations.SINGLE_OFFICE, desk)["ok"], "marcar la oficina en %s" % desk)
	_expect(builder.place("simple_desk", desk, 2)["ok"], "escritorio de la oficina en %s" % desk)
	_expect(builder.place("basic_chair", desk + Vector2i(0, 1), 0)["ok"], "silla de la oficina en %s" % desk)


# Contrata a alguien de ese cargo y nivel en la próxima llegada de candidatos.
func _hire(role: String, level: String) -> Dictionary:
	var candidate: Dictionary = _candidate(role, level)
	var result: Dictionary = Staff.make_offer(candidate["id"], candidate["asked_salary"])
	var employee: Dictionary = Staff.get_employee(candidate["id"])
	_expect(not employee.is_empty(), "contratado: %s %s (%s)" % [role, level, result["message"]])
	return employee


# Publica una vacante y espera al primer candidato.
func _candidate(role: String, level: String) -> Dictionary:
	var opened: Dictionary = Staff.open_vacancy(role, level, StaffCatalog.get_salary(role, level), true)
	_expect(opened["ok"], "publicar %s: %s" % [role, opened["message"]])
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	return Staff.get_vacancy(opened["id"])["candidates"][0]


# Un líder de equipo (contratado) sin equipo.
func _leader() -> Dictionary:
	return _hire(LEADER, "senior")


# Una hora absoluta del próximo día hábil a esa hora del día.
func _hour_at(hour: int) -> int:
	var at: int = Staff.get_absolute_hour() + 1
	while Staff.get_weekday_at(at) >= 5 or posmod(at, 24) != hour:
		at += 1
	return at


func _check_offices() -> void:
	_new_game(2)
	var all: Array[Dictionary] = Workstations.find_all(OfficeState.furniture, OfficeState.rooms)
	var offices: Array[Dictionary] = Workstations.find_all(OfficeState.furniture, OfficeState.rooms, Workstations.SINGLE_OFFICE)
	_expect(offices.size() == 2 and all.size() == 5, "2 oficinas y 3 puestos: %d / %d" % [offices.size(), all.size()])
	_expect(Staff.get_free_workstations().size() == 3, "los puestos libres de un Área de trabajo no cuentan las oficinas")
	_expect(Staff.get_free_workstations(MANAGER).size() == 2, "un gerente usa las oficinas")
	# Un segundo escritorio con su silla en la misma oficina no hace otro puesto (se
	# agregan a mano: en 2 × 2 tapan la puerta).
	var desk: Dictionary = {}
	var chair: Dictionary = {}
	for item: Dictionary in OfficeState.furniture:
		if item["cell"] == Vector2i(0, 6):
			desk = item.duplicate(true)
		elif item["cell"] == Vector2i(0, 7):
			chair = item.duplicate(true)
	desk["cell"] = Vector2i(1, 6)
	chair["cell"] = Vector2i(1, 7)
	var furniture: Array[Dictionary] = OfficeState.furniture.duplicate(true)
	furniture.append(desk)
	furniture.append(chair)
	_expect(Workstations.find_all(furniture, OfficeState.rooms, Workstations.SINGLE_OFFICE).size() == 2, "una persona por oficina")
	_expect(Workstations.find_all(furniture, OfficeState.rooms, Workstations.WORK_AREA).size() == 3, "las áreas de trabajo no cambian")


func _check_unlock() -> void:
	_new_game(1)
	Company.stage = 1
	var opened: Dictionary = Staff.open_vacancy(MANAGER, "senior", 6000, false)
	_expect(not opened["ok"] and String(opened["message"]).contains("Pequeña empresa"), "en Startup no hay vacante de gerente: %s" % opened["message"])
	var leader: Dictionary = _leader()
	var progress: Dictionary = Staff.get_promotion_progress(leader)
	_expect(progress["next_role"] == MANAGER and progress["blocker"] == "stage", "un líder ascenderá a gerente desde Pequeña empresa")
	Company.stage = 2
	_expect(bool(Staff.get_promotion_progress(leader)["ready"]), "en Pequeña empresa con oficina libre ya puede")
	# Un gerente sigue a ejecutivo, que se desbloquea en Mediana empresa (hito 33).
	var manager: Dictionary = leader.duplicate(true)
	manager["role"] = MANAGER
	var next: Dictionary = Staff.get_promotion_progress(manager)
	_expect(next["next_role"] == "executive" and next["blocker"] == "stage", "un gerente ascenderá a ejecutivo desde Mediana empresa")


func _check_promotion() -> void:
	_new_game(0)
	var leader: Dictionary = _leader()
	var worker: Dictionary = _hire("programmer", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], leader["id"])
	Staff.add_to_team(team["id"], worker["id"])
	# Sin oficina libre no asciende.
	var progress: Dictionary = Staff.get_promotion_progress(leader)
	_expect(progress["blocker"] == "station" and not bool(progress["ready"]), "sin Oficina única libre no puede")
	var failed: Dictionary = Staff.promote(leader["id"], 6000)
	_expect(not failed["ok"] and failed["message"] == Staff.NO_OFFICE_MESSAGE, "lo dice: %s" % failed["message"])
	_build_office(Builder.new(), [
		{"edge": Vector3i(0, 5, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(1, 5, GridEdge.AXIS_Y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(1, 6, GridEdge.AXIS_X), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(1, 7, GridEdge.AXIS_X), "kind": ConstructionCatalog.WALL},
	], Vector2i(0, 6))
	var free_before: int = Staff.get_free_workstations().size()
	var result: Dictionary = Staff.promote(leader["id"], 6000)
	_expect(result["ok"], "asciende a gerente: %s" % result["message"])
	_expect(leader["role"] == MANAGER and int(leader["salary"]) == 6000, "es gerente con $6,000")
	_expect(int(team["leader_id"]) == 0, "su equipo queda sin líder")
	_expect(not leader.has("manager_id"), "un gerente no tiene gerente")
	var key: String = Staff.employee_key(leader["id"])
	var office: Dictionary = Workstations.find_all(OfficeState.furniture, OfficeState.rooms, Workstations.SINGLE_OFFICE)[0]
	_expect(OfficeState.furniture[office["chair"]]["assigned_to"] == key, "se sienta en la oficina")
	_expect(Staff.has_working_station(leader), "su puesto funciona")
	_expect(Staff.get_free_workstations().size() == free_before + 1, "deja libre su silla del Área de trabajo")
	_expect(Staff.describe_employee(leader) == "Gerente · %s al mes" % MoneyFormat.format(6000), "sin nivel: %s" % Staff.describe_employee(leader))
	var assigned: int = 0
	for item: Dictionary in OfficeState.furniture:
		if item["assigned_to"] == key:
			assigned += 1
	_expect(assigned == 1, "una sola silla")


func _check_hiring() -> void:
	_new_game(1)
	var candidate: Dictionary = _candidate(MANAGER, "intern")
	_expect(candidate["role"] == MANAGER and candidate["level"] == "senior", "la vacante de gerente no elige nivel")
	var manager: Dictionary = _hire(MANAGER, "intern")
	_expect(Staff.has_working_station(manager), "el gerente contratado se sienta en su oficina")
	_expect(Staff.get_free_workstations().size() == 3, "no ocupa un puesto del Área de trabajo")
	# Sin otra oficina no se contrata otro.
	var result: Dictionary = Staff.make_offer(candidate["id"], candidate["asked_salary"] + 1000)
	_expect(not result["ok"] and result["message"] == Staff.NO_OFFICE_MESSAGE, "sin Oficina única libre no se contrata: %s" % result["message"])
	# Despedir al gerente devuelve sus líderes al CEO.
	var leader: Dictionary = _leader()
	_expect(Staff.set_manager(leader["id"], manager["id"])["ok"], "asignar líder")
	Staff.fire(manager["id"])
	_expect(int(leader["manager_id"]) == 0, "al irse el gerente, su líder vuelve al CEO")
	_expect(Staff.get_free_workstations(MANAGER).size() == 1, "la oficina queda libre")


func _check_caps() -> void:
	_new_game(1)
	var manager: Dictionary = _hire(MANAGER, "senior")
	# Líderes y equipos de mentira para no necesitar 11 puestos.
	var template: Dictionary = Staff.employees[0]
	var leaders: Array[Dictionary] = []
	for i: int in range(7):
		var leader: Dictionary = template.duplicate(true)
		leader["id"] = 500 + i
		leader["name"] = "Líder %d" % i
		leader["role"] = LEADER
		leader["manager_id"] = 0
		Staff.employees.append(leader)
		leaders.append(leader)
	var teams: Array[Dictionary] = []
	for i: int in range(7):
		teams.append(Staff.create_team())
	for i: int in range(5):
		_expect(Staff.add_to_team(teams[i]["id"], leaders[i]["id"])["ok"], "el CEO dirige al líder %d" % (i + 1))
	_expect(Staff.get_ceo_leaders().size() == 5, "el CEO dirige 5")
	var sixth: Dictionary = Staff.add_to_team(teams[5]["id"], leaders[5]["id"])
	_expect(not sixth["ok"] and String(sixth["message"]).contains("gerente"), "un sexto líder sin gerente no se nombra: %s" % sixth["message"])
	# Un líder sin equipo puede quedar a cargo del CEO aunque esté lleno.
	_expect(Staff.set_manager(leaders[5]["id"], manager["id"])["ok"], "con gerente sí")
	_expect(Staff.add_to_team(teams[5]["id"], leaders[5]["id"])["ok"], "y ahora se nombra")
	_expect(Staff.set_manager(leaders[5]["id"], 0)["ok"] == false, "no vuelve al CEO lleno mientras lidera un equipo")
	# Un gerente dirige hasta 5.
	for i: int in range(4):
		_expect(Staff.set_manager(leaders[i]["id"], manager["id"])["ok"], "al gerente: %d" % i)
	_expect(Staff.get_leaders_of(manager["id"]).size() == 5, "el gerente dirige 5")
	var over: Dictionary = Staff.set_manager(leaders[4]["id"], manager["id"])
	_expect(not over["ok"] and String(over["message"]).contains("máximo"), "el sexto no entra: %s" % over["message"])
	_expect(Staff.set_manager(leaders[0]["id"], manager["id"])["ok"] == false, "ya está a cargo de él")
	_expect(Staff.set_manager(manager["id"], 0)["ok"] == false, "un gerente no es líder")
	_expect(Staff.set_manager(leaders[6]["id"], 999)["ok"] == false, "un gerente que no existe")


func _check_effects() -> void:
	_new_game(1)
	var manager: Dictionary = _hire(MANAGER, "senior")
	var leader: Dictionary = _leader()
	var worker: Dictionary = _hire("programmer", "junior")
	worker["energy"] = 100
	worker["mood"] = 100
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], leader["id"])
	Staff.add_to_team(team["id"], worker["id"])
	# Turno de 14 a 23: el gerente (8 a 17) está solo hasta las 17.
	Staff.set_team_shift(team["id"], 14, [0, 1, 2, 3, 4])
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	Projects.assign(contract["id"], team["id"])
	var full: float = Production.get_rate("junior", 100.0, 0.0, 100.0)
	var both: int = _hour_at(15)
	var late: int = _hour_at(20)
	var stress_alone: int = Staff.get_stress_target(worker)
	_expect(is_equal_approx(Staff.get_team_factor(team, both), 1.0), "sin gerente asignado, 100 %")
	Staff.set_manager(leader["id"], manager["id"])
	_expect(Staff.is_manager_present(team, both) and is_equal_approx(Staff.get_team_factor(team, both), 1.1), "con su gerente presente, 110 %%: %.3f" % Staff.get_team_factor(team, both))
	_expect(is_equal_approx(float(Projects.get_workers(contract, both)[0]["rate"]), full * 1.1), "el programador rinde 110 %")
	_expect(not Staff.is_manager_present(team, late) and is_equal_approx(Staff.get_team_factor(team, late), 1.0), "a las 20 el gerente ya se fue: 100 %")
	_expect(Staff.get_stress_target(worker) == stress_alone + int(StaffCatalog.get_management("manager_stress")), "la meta de estrés baja 10: %d" % Staff.get_stress_target(worker))
	# Sin líder presente: 75 % × 110 %.
	Staff.remove_from_team(leader["id"])
	_expect(is_equal_approx(Staff.get_team_factor(team, both), 0.75), "sin líder no hay gerente que cuente: 75 %")


func _check_save() -> void:
	_new_game(1)
	var manager: Dictionary = _hire(MANAGER, "senior")
	var leader: Dictionary = _leader()
	Staff.set_manager(leader["id"], manager["id"])
	var before: String = JSON.stringify(Staff.export_state())
	_expect(SaveManager.save_game("slot_4"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_4"), "cargar")
	_expect(JSON.stringify(Staff.export_state()) == before, "gerente y líderes vuelven igual")
	var old: Dictionary = Staff.export_state()
	for saved: Dictionary in old["employees"]:
		saved.erase("manager_id")
	Staff.import_state(old)
	_expect(int(Staff.get_employee(leader["id"])["manager_id"]) == 0, "partida vieja: lo dirige el CEO")
	old = Staff.export_state()
	for saved: Dictionary in old["employees"]:
		if saved["role"] == LEADER:
			saved["manager_id"] = leader["id"]
	Staff.import_state(old)
	_expect(int(Staff.get_employee(leader["id"])["manager_id"]) == 0, "un gerente inválido se descarta")


func _check_ui() -> void:
	_new_game(1)
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var manager: Dictionary = _hire(MANAGER, "senior")
	var leader: Dictionary = _leader()
	var worker: Dictionary = _hire("designer", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], leader["id"])
	Staff.add_to_team(team["id"], worker["id"])
	var staff_panel: StaffPanel = game.get_node("StaffPanel")
	staff_panel.set_open(true)
	await get_tree().process_frame
	var text: String = staff_panel.get_list_text()
	_expect(text.contains("Organigrama") and text.contains("CEO · dirige 1 de 5 líderes con equipo"), "organigrama: %s" % text)
	_expect(text.contains("Gerente %s · dirige 0 de 5 líderes" % manager["name"]), "el gerente: %s" % text)
	var choice: OptionButton = staff_panel.get_boss_choice(leader["id"])
	_expect(choice != null and not choice.disabled and choice.item_count == 2, "lista A cargo de")
	choice.select(1)
	choice.item_selected.emit(1)
	await get_tree().process_frame
	_expect(int(leader["manager_id"]) == manager["id"], "elegir el gerente desde el organigrama")
	text = staff_panel.get_list_text()
	_expect(text.contains("Gerente %s · dirige 1 de 5 líderes" % manager["name"]), "ahora dirige 1: %s" % text)
	staff_panel.set_open(false)
	var card: EmployeeCard = game.get_node("EmployeeCard")
	card.open_employee(leader["id"])
	await get_tree().process_frame
	_expect(card.get_text().contains("Lo dirige: %s (gerente)" % manager["name"]), "ficha del líder: %s" % card.get_text())
	card.open_employee(manager["id"])
	await get_tree().process_frame
	_expect(card.get_text().contains("Dirige 1 de 5 líderes: %s" % leader["name"]), "ficha del gerente: %s" % card.get_text())
	var teams_panel: TeamsPanel = game.get_node("TeamsPanel")
	teams_panel.set_open(true)
	await get_tree().process_frame
	text = teams_panel.get_list_text()
	_expect(text.contains("gerente %s presente: +10 %%" % manager["name"]), "Equipos muestra al gerente: %s" % text)
	teams_panel.set_open(false)
	# El personaje del gerente va a la silla de su oficina.
	var character: Employee = game.get("employees")[manager["id"]]
	var office: Dictionary = Workstations.find_all(OfficeState.furniture, OfficeState.rooms, Workstations.SINGLE_OFFICE)[0]
	_expect(character.get_seat_cell() == office["cell"], "el gerente se sienta en su oficina")
	_expect(character.shirt_color == StaffCatalog.get_shirt_color(MANAGER), "camisa de gerente")
	game.queue_free()
	await get_tree().process_frame
