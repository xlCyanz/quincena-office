# Producción: el CEO solo hace 24 puntos por día; 2 programadores y 1 diseñador Junior, 48;
# la programación no empieza antes de la mitad del diseño.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=production
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261111
const DESK_XS: Array[int] = [3, 4, 5]

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Carpeta aparte para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_rates()
	_check_phases()
	_check_ceo()
	_check_team()
	_check_overlap()
	_check_save()
	await _check_panel()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	_notices.clear()


func _total(contract: Dictionary) -> float:
	var total: float = 0.0
	for phase: String in ContractCatalog.PHASES:
		total += float(contract["progress"][phase])
	return total


# Muchos puntos para que los topes no molesten.
func _big_contract(points: int) -> Dictionary:
	Projects.accept(Projects.offers[0]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	contract["points"] = {"design": points, "programming": points, "testing": points}
	contract["total_points"] = points * 3
	return contract


func _check_rates() -> void:
	_expect(_near(Production.get_rate("intern", 100.0, 0.0), 1.0) and _near(Production.get_rate("junior", 100.0, 0.0), 2.0)
		and _near(Production.get_rate("semi_senior", 100.0, 0.0), 3.0) and _near(Production.get_rate("senior", 100.0, 0.0), 4.5),
		"puntos por hora de la tabla 13.3")
	_expect(_near(Production.get_energy_factor(100.0), 1.0) and _near(Production.get_energy_factor(50.0), 1.0)
		and _near(Production.get_energy_factor(25.0), 0.75) and _near(Production.get_energy_factor(0.0), 0.5), "efecto de la energía")
	_expect(_near(Production.get_rate("junior", 25.0, 0.0), 1.5), "un junior cansado rinde 1.5")
	_expect(_near(Production.get_rate("junior", 100.0, 0.3), 2.6) and _near(Production.get_computer_bonus("basic_computer"), 0.0),
		"computadora pro +30%, básica sin extra")
	# Ánimo bajo 50 baja el rendimiento hasta 70 % con ánimo 0.
	_expect(_near(Production.get_mood_factor(100.0), 1.0) and _near(Production.get_mood_factor(50.0), 1.0)
		and _near(Production.get_mood_factor(25.0), 0.85) and _near(Production.get_mood_factor(0.0), 0.7), "efecto del ánimo")
	_expect(_near(Production.get_rate("junior", 25.0, 0.0, 0.0), 2.0 * 0.75 * 0.7), "cansado y desanimado se multiplican")
	_expect(Production.get_role_phase("programmer") == "programming" and Production.get_role_phase("designer") == "design"
		and Production.get_role_phase("qa") == "testing" and Production.get_role_phase("salesperson") == "", "fase de cada cargo")


func _check_phases() -> void:
	var contract: Dictionary = {"points": {"design": 100, "programming": 100, "testing": 100},
		"progress": {"design": 0.0, "programming": 0.0, "testing": 0.0}}
	var programmer: Array[Dictionary] = [{"phase": "programming", "rate": 2.0}]
	_expect(Production.is_open(contract, "design") and not Production.is_open(contract, "programming"), "al empezar solo diseño")
	Production.apply(contract, programmer)
	_expect(_near(contract["progress"]["design"], 1.0) and _near(contract["progress"]["programming"], 0.0),
		"el programador ayuda en diseño al 50%")
	contract["progress"]["design"] = 49.0
	_expect(Production.get_room(contract, "programming") == 0.0, "con diseño al 49% programación sigue cerrada")
	contract["progress"]["design"] = 50.0
	_expect(_near(Production.get_room(contract, "programming"), 50.0), "con diseño al 50% se abre hasta el 50%")
	contract["progress"]["programming"] = 49.5
	Production.apply(contract, programmer)
	_expect(_near(contract["progress"]["programming"], 50.0), "programación no pasa el porcentaje de diseño")
	var ceo: Array[Dictionary] = [{"phase": "", "rate": 3.0}]
	Production.apply(contract, ceo)
	_expect(_near(contract["progress"]["design"], 53.0), "el CEO trabaja en diseño")
	var both: Array[Dictionary] = [{"phase": "programming", "rate": 2.0}, {"phase": "design", "rate": 2.0}]
	Production.apply(contract, both)
	_expect(_near(contract["progress"]["design"], 55.0) and _near(contract["progress"]["programming"], 52.0), "orden de las fases")
	contract["progress"] = {"design": 100.0, "programming": 100.0, "testing": 99.0}
	_expect(not Production.is_finished(contract), "falta una prueba")
	Production.apply(contract, programmer)
	_expect(Production.is_finished(contract) and _near(contract["progress"]["testing"], 100.0), "lo que sobra se pierde")


func _check_ceo() -> void:
	# Jornada de 8 a 17 con almuerzo a las 12: 8 horas × 3 = 24.
	_new_game()
	var contract: Dictionary = _big_contract(1000)
	_expect(contract["team_id"] == Projects.CEO_TEAM, "lo lleva el CEO")
	GameClock.fast_forward_hours(9)  # lunes 17:00
	Staff.set_ceo_at_work(false)
	_expect(_near(_total(contract), 24.0), "el CEO produce 24 en su jornada: %.1f" % _total(contract))
	GameClock.fast_forward_hours(15)  # martes 8:00, vuelve solo
	_expect(_near(_total(contract), 24.0) and Staff.ceo_at_work, "en casa no produce")
	# Si se queda, rinde hasta las 22 y se duerme.
	GameClock.fast_forward_hours(24)
	_expect(_near(_total(contract), 24.0 + 13.0 * 3.0), "quedándose rinde 13 horas: %.1f" % (_total(contract) - 24.0))
	_expect(_notices.any(func(text: String) -> bool: return text.contains("dormido")), "aviso de que se durmió")
	_new_game()
	contract = _big_contract(1000)
	var vacancy: int = Staff.open_vacancy("programmer", "junior", 1200, true)["id"]
	GameClock.fast_forward_hours(1)  # 9:00, llegan candidatos
	var before: float = _total(contract)
	_expect(Staff.start_interview(Staff.get_vacancy(vacancy)["candidates"][0]["id"])["ok"], "empezar una entrevista a las 9")
	GameClock.fast_forward_hours(3)  # 12:00
	# Media hora (9:00–9:30): esa hora rinde la mitad, las 10 y las 11 enteras.
	_expect(_near(_total(contract) - before, 1.5 + 3.0 + 3.0), "durante la entrevista (9:00–9:30) no produce: %.1f" % (_total(contract) - before))


# Empleados falsos sentados en puestos de verdad.
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


func _check_team() -> void:
	_new_game()
	var ids: Array[String] = ["programmer", "programmer", "designer"]
	var staff_ids: Array[int] = _add_staff(ids)
	var team: Dictionary = _team_with(staff_ids)
	var contract: Dictionary = _big_contract(1000)
	_expect(contract["team_id"] == team["id"], "lo lleva el equipo")
	_expect(Workstations.computer_of(OfficeState.furniture, Staff.employee_key(staff_ids[0])) == "basic_computer", "computadora del puesto")
	contract["progress"]["design"] = 600.0
	Staff.set_ceo_at_work(false)
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(_near(contract["progress"]["design"], 616.0) and _near(contract["progress"]["programming"], 32.0),
		"diseño +16 y programación +32: %s" % [contract["progress"]])
	_expect(_near(_total(contract) - 600.0, 48.0), "2 programadores y 1 diseñador Junior producen 48 por día")
	_expect(_near(Projects.get_hourly_rate(contract), 6.0), "a las 8:00 del martes rinden 6 por hora")
	var seller_ids: Array[int] = []
	Staff.get_employee(staff_ids[2])["role"] = "salesperson"
	var workers: Array[Dictionary] = Projects.get_workers(contract, Staff.get_absolute_hour() + 2)
	_expect(workers.size() == 2, "el vendedor no trabaja en el contrato")
	Staff.get_employee(staff_ids[0])["energy"] = 25
	workers = Projects.get_workers(contract, Staff.get_absolute_hour() + 2)
	_expect(_near(float(workers[0]["rate"]) + float(workers[1]["rate"]), 3.5), "cansado rinde 1.5")
	_expect(seller_ids.is_empty(), "datos")
	OfficeState.furniture.filter(func(item: Dictionary) -> bool: return item["cell"] == Vector2i(3, 1))[0]["assigned_to"] = ""
	_expect(Projects.get_workers(contract, Staff.get_absolute_hour() + 2).size() == 1, "sin puesto no trabaja")


# Diseñador y programador desde cero: la programación espera la mitad del diseño y nunca la pasa;
# sin QA las pruebas avanzan con ayudantes y termina.
func _check_overlap() -> void:
	_new_game()
	var roles: Array[String] = ["designer", "programmer"]
	var team: Dictionary = _team_with(_add_staff(roles))
	Staff.set_ceo_at_work(false)
	Projects.accept(Projects.offers[0]["id"])
	var contract: Dictionary = Projects.contracts[0]
	_expect(contract["team_id"] == team["id"], "lo lleva el equipo")
	# Sin plazo encima: atrasado subiría el estrés y podrían renunciar.
	contract["deadline_day"] = int(contract["deadline_day"]) + 1000
	var opened_at: float = -1.0
	var testing_at: float = -1.0
	var ok: bool = true
	for hour: int in range(GameConstants.HOURS_PER_DAY * 60):
		GameClock.fast_forward_hours(1)
		var design: float = Production.get_ratio(contract, "design")
		var programming: float = Production.get_ratio(contract, "programming")
		var testing: float = Production.get_ratio(contract, "testing")
		if programming > 0.0 and opened_at < 0.0:
			opened_at = design
		if testing > 0.0 and testing_at < 0.0:
			testing_at = programming
		ok = ok and programming <= design + Production.EPSILON and testing <= programming + Production.EPSILON
		if Production.is_finished(contract):
			break
	_expect(opened_at >= 0.5, "la programación empezó con el diseño al %.0f%%" % (opened_at * 100.0))
	_expect(testing_at >= 0.5, "las pruebas empezaron con programación al %.0f%%" % (testing_at * 100.0))
	_expect(ok, "ninguna fase pasó a la anterior")
	_expect(Production.is_finished(contract), "sin QA igual termina: %s" % [contract["progress"]])
	_expect(_notices.any(func(text: String) -> bool: return text.begins_with("Terminado")), "aviso de terminado")
	var total: float = _total(contract)
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(_near(_total(contract), total), "terminado no suma más")


func _check_save() -> void:
	_new_game()
	var contract: Dictionary = _big_contract(1000)
	GameClock.fast_forward_hours(3)
	var before: String = JSON.stringify(Projects.export_state())
	_expect(SaveManager.save_game("slot_3"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_3"), "cargar")
	_expect(JSON.stringify(Projects.export_state()) == before and _near(_total(Projects.contracts[0]), 9.0), "el avance vuelve igual")
	_expect(contract != null, "datos")


func _check_panel() -> void:
	_new_game()
	Projects.accept(Projects.offers[0]["id"])
	var contract: Dictionary = Projects.contracts[0]
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	GameClock.fast_forward_hours(2)  # 10:00
	var panel: ProjectsPanel = game.get_node("ProjectsPanel")
	panel.set_open(true)
	await get_tree().process_frame
	var bar: ProgressBar = panel.get_phase_bar(contract["id"], "design")
	_expect(bar != null and _near(bar.value, 6.0) and _near(bar.max_value, float(contract["points"]["design"])),
		"barra de diseño: %s" % (bar.value if bar != null else -1.0))
	var text: String = panel.get_list_text()
	for expected: String in ["Lo lleva el CEO", "Diseño", "6 / %d" % contract["points"]["design"], "Programación",
			"0 / %d (espera)" % contract["points"]["programming"], "Ahora rinde 3 puntos por hora."]:
		_expect(text.contains(expected), "el panel muestra «%s»: %s" % [expected, text])
	Projects.assign(contract["id"], Projects.NO_TEAM)
	await get_tree().process_frame
	_expect(panel.get_list_text().contains("Nadie lo lleva"), "sin equipo")
	game.queue_free()
	await get_tree().process_frame
