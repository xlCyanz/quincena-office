# Turno de limpieza: entra a las 7:20, empieza a limpiar a las 7:30 y sale a las 15:00; rasgos propios
# (Meticuloso, Despistado, Madrugador, Alegre…) y no entra en equipos ni proyectos.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=cleaning_shift
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const CLEANING_POOL: Array[String] = ["meticulous", "careless", "early_bird", "cheerful", "unpunctual", "loyal", "coffee_addict"]

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_packed.call_deferred(GAME_SCENE)
		return
	SaveManager.save_dir = "user://test_saves"
	_check_data()
	var demo_before: bool = SaveManager.start_with_demo
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	_check_candidates()
	SaveManager.new_game()
	_check_teams()
	SaveManager.new_game()
	_check_traits()
	SaveManager.new_game()
	_check_dirt()
	SaveManager.new_game()
	await _check_in_game()
	SaveManager.start_with_demo = demo_before
	SaveManager.new_game()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _cleaners() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for employee: Dictionary in Staff.employees:
		if Staff.is_cleaner(employee):
			result.append(employee)
	return result


func _check_data() -> void:
	var schedule: WorkSchedule = WorkSchedule.from_dict(StaffCatalog.get_role_schedule("cleaner"))
	_expect(schedule.start_hour == 7 and schedule.end_hour == 15 and schedule.days == [0, 1, 2, 3, 4],
		"limpieza trabaja de lunes a viernes de 7 a 15")
	_expect(schedule.is_lunch(0, 11) and not schedule.is_lunch(0, 10), "almuerza a la 4.ª hora (11:00)")
	_expect(int(StaffCatalog.get_cleaning("arrive_minute")) == 20 and int(StaffCatalog.get_cleaning("start_minute")) == 30,
		"entra a las 7:20 y limpia desde las 7:30")
	_expect(StaffCatalog.is_role_without_teams("cleaner") and not StaffCatalog.is_role_without_teams("programmer"),
		"solo limpieza es no_teams")
	_expect(StaffCatalog.get_trait_ids("cleaner") == CLEANING_POOL, "rasgos de limpieza: %s" % [StaffCatalog.get_trait_ids("cleaner")])
	var default_pool: Array[String] = StaffCatalog.get_trait_ids("programmer")
	_expect(default_pool == StaffCatalog.get_trait_ids() and not default_pool.has("meticulous") and default_pool.has("night_owl"),
		"los demás cargos no tienen rasgos de limpieza")
	for trait_id: String in CLEANING_POOL:
		_expect(not Staff.describe_trait(trait_id).is_empty() and StaffCatalog.get_trait_name(trait_id) != trait_id,
			"el rasgo %s tiene nombre y efecto" % trait_id)
	_expect(Staff.describe_trait("meticulous").contains("limpia +25 %"), "describe al meticuloso: %s" % Staff.describe_trait("meticulous"))
	_expect(Staff.describe_trait("careless").contains("limpia −20 %"), "describe al despistado: %s" % Staff.describe_trait("careless"))
	_expect(Staff.describe_trait("early_bird").contains("20 min antes"), "describe al madrugador: %s" % Staff.describe_trait("early_bird"))
	_expect(Staff.describe_trait("cheerful").contains("+2 a la meta de ánimo de todos"), "describe al alegre: %s" % Staff.describe_trait("cheerful"))


func _check_candidates() -> void:
	var cleaner_ok: bool = true
	var other_ok: bool = true
	var seen: Dictionary[String, bool] = {}
	for role: String in ["cleaner", "programmer"]:
		var vacancy: Dictionary = {"role": role, "level": StaffCatalog.get_level_ids()[0], "salary": StaffCatalog.get_salary(role, StaffCatalog.get_level_ids()[0])}
		for i: int in range(60):
			var candidate: Dictionary = Staff._make_candidate(vacancy, GameClock.get_day_count())
			for trait_id: String in candidate["traits"]:
				if role == "cleaner":
					cleaner_ok = cleaner_ok and CLEANING_POOL.has(trait_id)
					seen[trait_id] = true
				else:
					other_ok = other_ok and StaffCatalog.get_trait_ids().has(trait_id) and not ["meticulous", "careless", "early_bird", "cheerful"].has(trait_id)
	_expect(cleaner_ok, "los candidatos de limpieza solo traen rasgos de limpieza")
	_expect(seen.size() == CLEANING_POOL.size(), "salen todos los rasgos de limpieza: %s" % [seen.keys()])
	_expect(other_ok, "los demás candidatos no traen rasgos de limpieza")


func _check_teams() -> void:
	var cleaners: Array[Dictionary] = _cleaners()
	_expect(cleaners.size() >= 1 and not Staff.teams.is_empty(), "la empresa de prueba tiene limpieza y equipos")
	if cleaners.is_empty() or Staff.teams.is_empty():
		return
	var cleaner: Dictionary = cleaners[0]
	var team: Dictionary = Staff.teams[0]
	_expect(not Staff.can_join_teams(cleaner), "limpieza no puede entrar a equipos")
	var result: Dictionary = Staff.add_to_team(team["id"], cleaner["id"])
	_expect(not result["ok"] and String(result["message"]).contains("no entra a equipos ni a proyectos"),
		"sumarla a un equipo falla: %s" % result["message"])
	_expect(Staff.get_team_of(cleaner["id"]).is_empty(), "sigue sin equipo")
	_expect(not Staff.get_employees_without_team().has(cleaner), "no sale entre los «Sin equipo»")
	# Una partida guardada con limpieza en un equipo la saca al cargar.
	var state: Dictionary = JSON.parse_string(JSON.stringify(Staff.export_state()))
	(state["teams"][0]["members"] as Array).append(cleaner["id"])
	Staff.import_state(state)
	_expect(Staff.get_team_of(cleaner["id"]).is_empty(), "al cargar sale del equipo")


func _check_traits() -> void:
	var cleaners: Array[Dictionary] = _cleaners()
	var someone: Dictionary = {}
	for employee: Dictionary in Staff.employees:
		if not Staff.is_cleaner(employee):
			someone = employee
			break
	if cleaners.is_empty() or someone.is_empty():
		_expect(false, "hay limpieza y otros empleados")
		return
	for employee: Dictionary in Staff.employees:
		employee["traits"] = [] as Array[String]
	Staff._clear_hour_caches()
	var before: int = Staff.get_mood_target(someone)
	cleaners[0]["traits"] = ["cheerful"] as Array[String]
	Staff._clear_hour_caches()
	_expect(Staff.get_mood_target(someone) == before + 2, "un alegre sube 2 la meta de ánimo de todos")
	_expect(Staff.get_mood_target(cleaners[0]) >= 0, "también la suya")
	if cleaners.size() > 1:
		cleaners[1]["traits"] = ["cheerful"] as Array[String]
		Staff._clear_hour_caches()
		_expect(Staff.get_mood_target(someone) == before + 2, "dos alegres no suman doble")
	cleaners[0]["traits"] = ["early_bird"] as Array[String]
	_expect(Staff.get_cleaning_minutes(cleaners[0]) == Vector2i(0, 10), "madrugador: entra a las 7:00 y limpia desde las 7:10")
	cleaners[0]["traits"] = [] as Array[String]
	_expect(Staff.get_cleaning_minutes(cleaners[0]) == Vector2i(20, 30), "sin rasgos: 7:20 y 7:30")
	_expect(Staff.get_cleaning_minutes(someone) == Vector2i.ZERO, "los demás no tienen minutos de limpieza")


# La hora de entrada limpia la mitad (desde las 7:30); cada uno según sus rasgos.
func _check_dirt() -> void:
	var cleaners: Array[Dictionary] = _cleaners()
	if cleaners.size() < 2:
		_expect(false, "la empresa de prueba tiene dos de limpieza: %d" % cleaners.size())
		return
	# Al lunes 7:00.
	GameClock.fast_forward_hours(posmod(7 - GameClock.get_hour(), GameConstants.HOURS_PER_DAY))
	while GameClock.get_weekday() != 0 or GameClock.get_hour() != 7:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	Staff.set_ceo_at_work(false)
	for employee: Dictionary in Staff.employees:
		employee["traits"] = [] as Array[String]
		employee["missing_until"] = 0
	cleaners[0]["traits"] = ["meticulous"] as Array[String]
	cleaners[1]["traits"] = ["careless"] as Array[String]
	for room: Dictionary in OfficeState.rooms:
		room["dirt"] = 0.0
	OfficeState.rooms[0]["dirt"] = 100.0
	var amount: float = float(StaffCatalog.get_cleaning("clean_per_hour")) * Staff.get_department_factor("administration")
	var working: int = 0
	for cleaner: Dictionary in cleaners:
		if Staff.is_expected_now(Staff.employee_key(cleaner["id"])):
			working += 1
	_expect(working == cleaners.size(), "a las 7:00 le toca a toda la limpieza: %d de %d" % [working, cleaners.size()])
	GameClock.fast_forward_hours(1)
	var expected: float = 100.0 - amount * 0.5 * (1.25 + 0.8)
	_expect(absf(OfficeState.get_room_dirt(OfficeState.rooms[0]) - expected) < 0.01,
		"la primera hora limpian media hora (meticuloso +25 %%, despistado −20 %%): %.2f, se esperaba %.2f" % [
		OfficeState.get_room_dirt(OfficeState.rooms[0]), expected])
	for room: Dictionary in OfficeState.rooms:
		room["dirt"] = 0.0
	OfficeState.rooms[0]["dirt"] = 100.0
	GameClock.fast_forward_hours(1)
	expected = 100.0 - amount * (1.25 + 0.8)
	_expect(OfficeState.get_room_dirt(OfficeState.rooms[0]) <= expected + 0.01,
		"las demás horas limpian la hora entera: %.2f" % OfficeState.get_room_dirt(OfficeState.rooms[0]))


func _check_in_game() -> void:
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	# Al martes 6:00.
	GameClock.fast_forward_hours(posmod(6 - GameClock.get_hour(), GameConstants.HOURS_PER_DAY))
	while GameClock.get_weekday() != 1:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	var cleaners: Array[Dictionary] = _cleaners()
	if cleaners.size() < 2:
		_expect(false, "hay dos de limpieza")
		game.queue_free()
		return
	for employee: Dictionary in Staff.employees:
		employee["traits"] = [] as Array[String]
	cleaners[1]["traits"] = ["early_bird"] as Array[String]
	var keys: Array[String] = [Staff.employee_key(cleaners[0]["id"]), Staff.employee_key(cleaners[1]["id"])]
	Staff.set_ceo_at_work(false)
	_send_all_home(game)
	game.call("_update_routines")
	var entered: Dictionary[String, int] = {}
	var started: Dictionary[String, int] = {}
	var hurried: bool = false
	var day_start: int = (Staff.get_absolute_hour() + 1) * 60
	for minute: int in range(1, 100):
		_advance_minute(game)
		for index: int in range(2):
			var character: Employee = game.employees[int(cleaners[index]["id"])]
			if character.activity != OfficeCharacter.Activity.AWAY and not entered.has(keys[index]):
				entered[keys[index]] = game.get_arrival_minute() - day_start
				hurried = hurried or character.hurry
			if character.cleaning and not started.has(keys[index]):
				started[keys[index]] = game.get_arrival_minute() - day_start
	_expect(entered.get(keys[0], -1) == 20, "entra a las 7:20: %s" % entered.get(keys[0], -1))
	_expect(started.get(keys[0], -1) == 30, "empieza a limpiar a las 7:30: %s" % started.get(keys[0], -1))
	_expect(entered.get(keys[1], -1) == 0, "el madrugador entra a las 7:00: %s" % entered.get(keys[1], -1))
	_expect(started.get(keys[1], -1) == 10, "y limpia desde las 7:10: %s" % started.get(keys[1], -1))
	_expect(not hurried, "entra sin apuro")
	# Salida: a las 15:00 en punto, sin quedarse.
	GameClock.fast_forward_hours(15 - GameClock.get_hour())
	_expect(GameClock.get_hour() == 15 and Staff.get_leave_minutes(keys[0]) == 0 and not Staff.is_expected_now(keys[0]),
		"a las 15:00 se va sin quedarse")
	# El panel de equipos no la ofrece para añadir.
	var panel: TeamsPanel = game.get_node("TeamsPanel")
	panel.set_open(true)
	await get_tree().process_frame
	var choice: OptionButton = panel.get_team_control(Staff.teams[0]["id"], "add_choice")
	var offered: bool = choice == null
	if choice != null:
		for index: int in range(choice.item_count):
			offered = offered or choice.get_item_id(index) == int(cleaners[0]["id"])
	_expect(not offered, "el panel de equipos no la ofrece para añadir")
	panel.set_open(false)
	game.queue_free()
	await get_tree().process_frame


func _advance_minute(game: Node) -> void:
	GameClock.advance(GameConstants.SECONDS_PER_GAME_HOUR / 60.0 / GameClock.get_time_scale())
	game._process(0.0)


func _send_all_home(game: Node) -> void:
	for character: OfficeCharacter in game.get_characters():
		character.call("_release_cells")
		character.call("_set_activity", OfficeCharacter.Activity.AWAY)
		character.get_path_cells()
		character.set("_path", [] as Array[Vector2i])
		character.visible = false
