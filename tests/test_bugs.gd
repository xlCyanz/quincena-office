# Prueba sin ventana del hito 17: errores y pruebas.
# Criterio: sin QA los errores llegan a la entrega; con QA bajan; con la misma semilla se
# generan siempre los mismos errores.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_bugs.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261111
const DESK_XS: Array[int] = [3, 4, 5]

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_chances()
	_check_fix()
	_check_qa()
	_check_save()
	await _check_panel()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _new_game(seed_value: int) -> void:
	SaveManager.new_game()
	Staff.set_seed(seed_value)
	Projects.set_seed(seed_value)


func _check_chances() -> void:
	_expect(_near(Projects.get_bug_chance("junior", 100.0), 1.0 / 30.0) and _near(Projects.get_bug_chance("senior", 100.0), 1.0 / 70.0)
		and _near(Projects.get_bug_chance("intern", 100.0), 1.0 / 20.0) and _near(Projects.get_bug_chance("semi_senior", 100.0), 1.0 / 45.0),
		"un error cada 20, 30, 45 o 70 puntos según el nivel")
	_expect(_near(Projects.get_bug_chance("junior", 40.0), 2.0 / 30.0) and _near(Projects.get_bug_chance("junior", 50.0), 1.0 / 30.0),
		"cansado, el doble")
	# Hito 19: estresado también el doble, sin sumarse al cansancio.
	_expect(_near(Projects.get_bug_chance("junior", 100.0, 70.0), 2.0 / 30.0) and _near(Projects.get_bug_chance("junior", 100.0, 69.0), 1.0 / 30.0)
		and _near(Projects.get_bug_chance("junior", 40.0, 90.0), 2.0 / 30.0), "estresado, el doble (no se acumula)")


# Corregir cuesta 3 puntos por error y va antes de programar algo nuevo.
func _check_fix() -> void:
	var contract: Dictionary = {"points": {"design": 100, "programming": 100, "testing": 100},
		"progress": {"design": 100.0, "programming": 10.0, "testing": 0.0}, "bugs_found": 2, "bugs_fixed": 0, "fix_progress": 0.0}
	var programmer: Array[Dictionary] = [{"phase": "programming", "rate": 2.0}]
	var done: Array[Dictionary] = Production.apply(contract, programmer)
	_expect(done.size() == 1 and done[0]["kind"] == "fix" and _near(contract["fix_progress"], 2.0)
		and _near(contract["progress"]["programming"], 10.0), "la primera hora corrige sin terminar")
	Production.apply(contract, programmer)
	_expect(contract["bugs_found"] == 1 and contract["bugs_fixed"] == 1 and _near(contract["fix_progress"], 1.0), "uno corregido")
	Production.apply(contract, programmer)
	_expect(contract["bugs_found"] == 0 and contract["bugs_fixed"] == 2 and _near(contract["fix_progress"], 0.0)
		and _near(contract["progress"]["programming"], 10.0), "dos corregidos con 6 puntos")
	Production.apply(contract, programmer)
	_expect(_near(contract["progress"]["programming"], 12.0), "después vuelve a programar")
	# Un diseñador no corrige; el CEO sí.
	contract["bugs_found"] = 1
	var designer: Array[Dictionary] = [{"phase": "design", "rate": 2.0}]
	Production.apply(contract, designer)
	_expect(contract["bugs_found"] == 1, "el diseñador no corrige")
	var ceo: Array[Dictionary] = [{"phase": "", "rate": 3.0}]
	Production.apply(contract, ceo)
	_expect(contract["bugs_found"] == 0, "el CEO corrige")
	# Con las pruebas completas, QA revisa.
	contract["progress"] = {"design": 100.0, "programming": 100.0, "testing": 100.0}
	var qa: Array[Dictionary] = [{"phase": "testing", "rate": 2.0}]
	done = Production.apply(contract, qa)
	_expect(done.size() == 1 and done[0]["kind"] == "review" and _near(done[0]["amount"], 2.0), "QA sigue revisando")


# Empleados de mentira sentados en puestos de verdad.
func _add_staff(roles: Array[String]) -> Array[int]:
	var builder := Builder.new()
	Economy.earn(20000, "Prueba")
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	var ids: Array[int] = []
	for index: int in range(roles.size()):
		var x: int = DESK_XS[index]
		builder.place("simple_desk", Vector2i(x, 0), 2)
		builder.place("basic_chair", Vector2i(x, 1), 0)
		builder.install_computer("basic_computer", Vector2i(x, 0))
		var employee_id: int = 900 + index
		var skills: Dictionary = {}
		for skill: String in StaffCatalog.get_skill_ids():
			skills[skill] = 40
		Staff.employees.append({"id": employee_id, "name": "Persona %d" % employee_id, "sex": "f", "age": 30,
			"role": roles[index], "level": "junior", "asked_salary": 0, "skills": skills, "skill_low": skills.duplicate(),
			"traits": [], "interviewed": false, "known_traits": [], "hired_day": 0, "salary": 0,
			"schedule": StaffCatalog.get_role_schedule(roles[index]), "energy": 100, "mood": 70, "stress": 20,
			"paid_until": 0, "owed": 0})
		var chair: Dictionary = OfficeState.furniture.filter(func(item: Dictionary) -> bool:
			return item["cell"] == Vector2i(x, 1))[0]
		chair["assigned_to"] = Staff.employee_key(employee_id)
		ids.append(employee_id)
	for employee_id: int in ids:
		_expect(Staff.has_working_station(Staff.get_employee(employee_id)), "puesto que funciona para %d" % employee_id)
	return ids


func _team_with(ids: Array[int]) -> Dictionary:
	var team: Dictionary = Staff.create_team()
	for employee_id: int in ids:
		Staff.add_to_team(team["id"], employee_id)
	return team



# Un equipo de 3 hace un contrato de 1000 puntos (600 de programación) hasta terminarlo y
# después extra_days días más. Devuelve los contadores de errores del contrato.
func _run(roles: Array[String], seed_value: int, extra_days: int) -> Dictionary:
	_new_game(seed_value)
	_team_with(_add_staff(roles))
	Projects.accept(Projects.offers[0]["id"])
	var contract: Dictionary = Projects.contracts[0]
	contract["points"] = {"design": 200, "programming": 600, "testing": 200}
	contract["total_points"] = 1000
	# Plazo largo: que el cliente no lo cancele por atraso (hito 18).
	contract["deadline_day"] = GameClock.get_day_count() + 1000
	var finished_at: int = -1
	for hour: int in range(GameConstants.HOURS_PER_DAY * 120):
		GameClock.fast_forward_hours(1)
		if Production.is_finished(contract):
			finished_at = hour
			break
	var at_finish: Dictionary = {"hidden": contract["bugs_hidden"], "found": contract["bugs_found"], "fixed": contract["bugs_fixed"]}
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY * extra_days)
	return {"finished": finished_at >= 0, "at_finish": at_finish, "hidden": contract["bugs_hidden"],
		"found": contract["bugs_found"], "fixed": contract["bugs_fixed"],
		"total": int(contract["bugs_hidden"]) + int(contract["bugs_found"]) + int(contract["bugs_fixed"])}


func _check_qa() -> void:
	var without: Array[String] = ["designer", "programmer", "programmer"]
	var with_qa: Array[String] = ["designer", "programmer", "qa"]
	var plain: Dictionary = _run(without, SEED, 0)
	print("sin QA: ", plain)
	_expect(plain["finished"], "sin QA igual termina")
	# Unos 600 / 30 = 20 errores de los programadores, más los de quienes ayudan.
	_expect(plain["total"] >= 12 and plain["total"] <= 40, "errores generados: %d" % plain["total"])
	_expect(float(plain["hidden"]) >= 0.6 * plain["total"], "sin QA casi todos llegan a la entrega: %d de %d" % [plain["hidden"], plain["total"]])
	var again: Dictionary = _run(without, SEED, 0)
	_expect(again == plain, "con la misma semilla, los mismos errores")
	var other_seed: Dictionary = _run(without, SEED + 1, 0)
	_expect(other_seed != plain, "con otra semilla cambian")
	var tested: Dictionary = _run(with_qa, SEED, 5)
	print("con QA: ", tested)
	_expect(tested["finished"], "con QA termina")
	_expect(int(tested["at_finish"]["hidden"]) <= 0.3 * tested["total"], "con QA quedan pocos ocultos al terminar: %d de %d" % [
		tested["at_finish"]["hidden"], tested["total"]])
	_expect(int(tested["hidden"]) <= int(tested["at_finish"]["hidden"]), "revisando después de terminar no aumentan")
	_expect(tested["found"] == 0 and int(tested["fixed"]) > 0, "los programadores corrigen todo lo encontrado: %s" % [tested])
	_expect(float(tested["hidden"]) / tested["total"] < float(plain["hidden"]) / plain["total"], "con QA llegan menos errores")


func _check_save() -> void:
	_new_game(SEED)
	Projects.accept(Projects.offers[0]["id"])
	var contract: Dictionary = Projects.contracts[0]
	contract["bugs_hidden"] = 4
	contract["bugs_found"] = 2
	contract["bugs_fixed"] = 1
	contract["fix_progress"] = 1.5
	var before: String = JSON.stringify(Projects.export_state())
	_expect(SaveManager.save_game("slot_3"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_3"), "cargar")
	_expect(JSON.stringify(Projects.export_state()) == before, "los errores vuelven igual")
	var old: Dictionary = Projects.export_state()
	for key: String in ["bugs_hidden", "bugs_found", "bugs_fixed", "fix_progress"]:
		(old["contracts"][0] as Dictionary).erase(key)
	Projects.import_state(old)
	_expect(Projects.contracts[0]["bugs_hidden"] == 0 and Projects.contracts[0]["bugs_found"] == 0, "partida vieja sin errores")


func _check_panel() -> void:
	_new_game(SEED)
	Projects.accept(Projects.offers[0]["id"])
	var contract: Dictionary = Projects.contracts[0]
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var panel: ProjectsPanel = game.get_node("ProjectsPanel")
	panel.set_open(true)
	await get_tree().process_frame
	_expect(panel.get_list_text().contains("Errores: ninguno encontrado"), "sin errores: %s" % panel.get_list_text())
	contract["bugs_found"] = 1
	contract["bugs_fixed"] = 2
	contract["bugs_hidden"] = 9137
	EventBus.projects_changed.emit()
	await get_tree().process_frame
	var text: String = panel.get_list_text()
	_expect(text.contains("Errores: 3 encontrados · 1 por corregir · 2 corregidos") and not text.contains("9137"),
		"los ocultos no se muestran: %s" % text)
	game.queue_free()
	await get_tree().process_frame
