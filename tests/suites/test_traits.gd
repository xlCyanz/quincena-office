# Prueba del hito 50: rasgos de producción.
# Criterio: un noctámbulo rinde más de noche; un perfeccionista hace menos errores y menos
# puntos; un mentor acelera a los juniors de su equipo; los rasgos se descubren a los 15 días.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=traits
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261150
const DAY_HOUR: int = 10
const NIGHT_HOUR: int = 23

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_data()
	_check_points()
	_check_bugs()
	_check_mentor()
	_check_sociable()
	_check_night_mood()
	_check_discovery()
	_check_save()
	await _check_ui()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva con un área de trabajo de tres puestos, dinero de sobra y los objetivos
# ya cumplidos.
func _new_game() -> void:
	GameClock.stop()
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(50000, "Prueba")
	var builder := Builder.new()
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	for x: int in [3, 4, 5]:
		_expect(builder.place("simple_desk", Vector2i(x, 0), 2)["ok"], "escritorio en %d" % x)
		_expect(builder.place("basic_chair", Vector2i(x, 1), 0)["ok"], "silla en %d" % x)
		_expect(builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "computadora en %d" % x)


# Contrata a alguien de ese cargo y nivel, sin rasgos (cada prueba pone los suyos).
func _hire(role: String, level: String) -> Dictionary:
	var opened: Dictionary = Staff.open_vacancy(role, level, StaffCatalog.get_salary(role, level), true)
	_expect(opened["ok"], "publicar %s: %s" % [role, opened["message"]])
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	var candidate: Dictionary = Staff.get_vacancy(opened["id"])["candidates"][0]
	Staff.make_offer(candidate["id"], candidate["asked_salary"])
	var employee: Dictionary = Staff.get_employee(candidate["id"])
	_expect(not employee.is_empty(), "contratado: %s %s" % [role, level])
	_set_traits(employee, [])
	return employee


func _set_traits(person: Dictionary, traits: Array) -> void:
	(person["traits"] as Array).assign(traits)


# Una hora (absoluta) del próximo día hábil a esa hora del reloj.
func _hour_at(clock_hour: int) -> int:
	var at: int = Staff.get_absolute_hour() + 1
	while Staff.get_weekday_at(at) >= 5 or posmod(at, 24) != clock_hour:
		at += 1
	return at


# El trabajador de un empleado en el contrato a esa hora, o vacío.
func _worker(contract: Dictionary, employee: Dictionary, at: int) -> Dictionary:
	for worker: Dictionary in Projects.get_workers(contract, at):
		if worker["key"] == Staff.employee_key(employee["id"]):
			return worker
	return {}


# Un contrato pequeño aceptado y asignado al equipo.
func _contract_for(team: Dictionary) -> Dictionary:
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	contract["team_id"] = team["id"]
	return contract


func _check_data() -> void:
	for trait_id: String in ["night_owl", "perfectionist", "sociable", "mentor"]:
		_expect(StaffCatalog.get_trait_ids().has(trait_id) and not Staff.describe_trait(trait_id).is_empty(), "el rasgo %s tiene efecto" % trait_id)
	_expect(StaffCatalog.get_trait_discover_days() == 15, "se descubren cada 15 días")
	_expect(Staff.describe_trait("night_owl").contains("+20 % de puntos de noche"), "describe al noctámbulo: %s" % Staff.describe_trait("night_owl"))
	_expect(Staff.describe_trait("loyal").contains("menos"), "el leal ya decía algo por la competencia: %s" % Staff.describe_trait("loyal"))


func _check_points() -> void:
	var owl: Dictionary = {"traits": ["night_owl"]}
	_expect(is_equal_approx(Staff.get_trait_points_factor(owl, NIGHT_HOUR), 1.2), "noctámbulo +20 % de noche")
	_expect(is_equal_approx(Staff.get_trait_points_factor(owl, 3), 1.2), "también de madrugada")
	_expect(is_equal_approx(Staff.get_trait_points_factor(owl, DAY_HOUR), 0.9), "noctámbulo −10 % de día")
	_expect(is_equal_approx(Staff.get_trait_points_factor({"traits": ["perfectionist"]}, DAY_HOUR), 0.85), "perfeccionista −15 %")
	_expect(is_equal_approx(Staff.get_trait_points_factor({"traits": ["sociable"]}, DAY_HOUR), 0.95), "sociable −5 %")
	_expect(is_equal_approx(Staff.get_trait_points_factor({"traits": ["night_owl", "perfectionist"]}, NIGHT_HOUR), 1.2 * 0.85), "se multiplican")
	_expect(is_equal_approx(Staff.get_trait_points_factor({"traits": ["loyal", "ambitious"]}, DAY_HOUR), 1.0), "los demás no cambian los puntos")
	# En un contrato real.
	_new_game()
	var programmer: Dictionary = _hire("programmer", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], programmer["id"])
	var contract: Dictionary = _contract_for(team)
	contract["progress"]["design"] = float(contract["points"]["design"])
	var at: int = _hour_at(DAY_HOUR)
	var plain: float = float(_worker(contract, programmer, at)["rate"])
	_expect(plain > 0.0, "sin rasgos rinde: %s" % plain)
	_set_traits(programmer, ["night_owl"])
	_expect(is_equal_approx(float(_worker(contract, programmer, at)["rate"]), plain * 0.9), "un noctámbulo de día rinde 90 %")
	_set_traits(programmer, ["perfectionist"])
	var perfect: Dictionary = _worker(contract, programmer, at)
	_expect(is_equal_approx(float(perfect["rate"]), plain * 0.85), "un perfeccionista rinde 85 %")
	# Rasgos sin descubrir también cuentan.
	_expect((programmer["known_traits"] as Array).is_empty(), "sin descubrir")


func _check_bugs() -> void:
	_new_game()
	var programmer: Dictionary = _hire("programmer", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], programmer["id"])
	var contract: Dictionary = _contract_for(team)
	var at: int = _hour_at(DAY_HOUR)
	var plain: Dictionary = _worker(contract, programmer, at)
	_set_traits(programmer, ["perfectionist"])
	var perfect: Dictionary = _worker(contract, programmer, at)
	_expect(is_equal_approx(float(perfect["bug_chance"]), float(plain["bug_chance"]) * 0.6), "perfeccionista: 60 % de los errores")
	_expect(is_equal_approx(float(plain["find_factor"]), 1.0) and is_equal_approx(float(perfect["find_factor"]), 1.25), "y encuentra 25 % más")
	# Encontrar: con muchos errores ocultos, la proporción se nota.
	var found: Array[int] = []
	for factor: float in [1.0, 1.25]:
		var project: Dictionary = {"points": {"testing": 1000.0}, "bugs_hidden": 10000, "bugs_found": 0}
		var worker: Dictionary = {"phase": "testing", "find_factor": factor}
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED
		Production.handle_bugs(project, [{"worker": worker, "phase": "testing", "amount": 10.0, "kind": "work"}] as Array[Dictionary], rng)
		found.append(int(project["bugs_found"]))
	var ratio: float = float(found[1]) / maxf(1.0, float(found[0]))
	_expect(ratio > 1.15 and ratio < 1.35, "un QA perfeccionista encuentra ~25 %% más: %s" % [found])


func _check_mentor() -> void:
	_new_game()
	var junior: Dictionary = _hire("programmer", "junior")
	var senior: Dictionary = _hire("programmer", "senior")
	var mentor: Dictionary = _hire("designer", "senior")
	var team: Dictionary = Staff.create_team()
	for person: Dictionary in [junior, senior, mentor]:
		Staff.add_to_team(team["id"], person["id"])
	var contract: Dictionary = _contract_for(team)
	contract["progress"]["design"] = float(contract["points"]["design"])
	var at: int = _hour_at(DAY_HOUR)
	var junior_rate: float = float(_worker(contract, junior, at)["rate"])
	var senior_rate: float = float(_worker(contract, senior, at)["rate"])
	var needed: int = int(Staff.get_promotion_progress(junior)["projects_needed"])
	_set_traits(mentor, ["mentor"])
	_expect(is_equal_approx(float(_worker(contract, junior, at)["rate"]), junior_rate * 1.15), "con un mentor presente el junior rinde +15 %")
	_expect(is_equal_approx(float(_worker(contract, senior, at)["rate"]), senior_rate), "a un senior no lo cambia")
	_expect(int(Staff.get_promotion_progress(junior)["projects_needed"]) == needed - 1, "el junior asciende con un contrato menos: %d → %d" % [
		needed, int(Staff.get_promotion_progress(junior)["projects_needed"])])
	# Fuera del turno del mentor no ayuda: el mentor con horario propio de tarde.
	Staff.set_own_schedule(mentor["id"], 16, [0, 1, 2, 3, 4] as Array[int])
	_expect(is_equal_approx(float(_worker(contract, junior, at)["rate"]), junior_rate), "sin el mentor presente rinde lo normal")
	Staff.clear_own_schedule(mentor["id"])
	# Dos mentores no suman.
	_set_traits(senior, ["mentor"])
	_expect(is_equal_approx(float(_worker(contract, junior, at)["rate"]), junior_rate * 1.15), "dos mentores ayudan una vez")
	# Un mentor no se ayuda a sí mismo ni a otros equipos.
	_set_traits(junior, ["mentor"])
	_set_traits(senior, [])
	_set_traits(mentor, [])
	_expect(is_equal_approx(float(_worker(contract, junior, at)["rate"]), junior_rate), "un mentor junior no se ayuda solo")
	_set_traits(mentor, ["mentor"])
	Staff.remove_from_team(mentor["id"])
	_set_traits(junior, [])
	_expect(is_equal_approx(float(_worker(contract, junior, at)["rate"]), junior_rate), "un mentor de otro equipo no ayuda")
	_expect(int(Staff.get_promotion_progress(junior)["projects_needed"]) == needed, "ni para ascender")


func _check_sociable() -> void:
	_new_game()
	var first: Dictionary = _hire("programmer", "junior")
	var second: Dictionary = _hire("designer", "junior")
	var outsider: Dictionary = _hire("qa", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], first["id"])
	Staff.add_to_team(team["id"], second["id"])
	var base: int = Staff.get_mood_target(second)
	var outside_base: int = Staff.get_mood_target(outsider)
	_set_traits(first, ["sociable"])
	_expect(Staff.get_mood_target(second) == base + 5, "un compañero sociable sube 5 la meta de ánimo: %d → %d" % [base, Staff.get_mood_target(second)])
	_expect(Staff.get_mood_target(outsider) == outside_base, "a otro equipo no")
	_set_traits(second, ["sociable"])
	_expect(Staff.get_mood_target(second) == base + 5, "dos sociables suman una vez")


func _check_night_mood() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	Staff.set_own_schedule(worker["id"], 22, [0, 1, 2, 3, 4] as Array[int])
	var night: int = Staff.get_mood_target(worker)
	_set_traits(worker, ["night_owl"])
	var owl: int = Staff.get_mood_target(worker)
	_expect(owl == night - int(StaffCatalog.get_overtime("night_mood")), "al noctámbulo la noche no le baja el ánimo: %d → %d" % [night, owl])


func _check_discovery() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	_set_traits(worker, ["night_owl", "mentor", "loyal"])
	(worker["known_traits"] as Array).clear()
	var hired_day: int = int(worker["hired_day"])
	_notices.clear()
	_keep_happy(worker)
	GameClock.fast_forward_hours((hired_day + 14 - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY + 24 - GameClock.get_hour() - 1)
	_expect((worker["known_traits"] as Array).is_empty(), "a los 14 días no se conoce ninguno")
	GameClock.fast_forward_hours(2)
	_expect(worker["known_traits"] == ["night_owl"], "a los 15 días se descubre el primero: %s" % [worker["known_traits"]])
	_expect(_notices.any(func(text: String) -> bool: return text.contains("noctámbulo")), "y avisa: %s" % [_notices])
	_keep_happy(worker)
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY * 15)
	_expect(worker["known_traits"] == ["night_owl", "mentor"], "a los 30 el segundo: %s" % [worker["known_traits"]])
	for i: int in range(2):
		_keep_happy(worker)
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY * 15)
	_expect(not Staff.get_employee(worker["id"]).is_empty(), "sigue en la empresa")
	_expect((worker["known_traits"] as Array).size() == 3, "después, todos: %s" % [worker["known_traits"]])


# Sin contrato y con la oficina sucia renunciaría antes de descubrir todo.
func _keep_happy(worker: Dictionary) -> void:
	worker["mood"] = 100
	worker["stress"] = 0
	worker["bad_days"] = 0


func _check_save() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	_set_traits(worker, ["perfectionist", "sociable"])
	(worker["known_traits"] as Array).assign(["perfectionist"])
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	var loaded: Dictionary = Staff.get_employee(worker["id"])
	_expect(loaded["traits"] == ["perfectionist", "sociable"] and loaded["known_traits"] == ["perfectionist"], "se guardan los rasgos y los conocidos")


func _check_ui() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	_set_traits(worker, ["night_owl", "mentor"])
	(worker["known_traits"] as Array).assign(["night_owl"])
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var card: EmployeeCard = game.get_node("EmployeeCard")
	card.open_employee(worker["id"])
	var text: String = card.get_text()
	_expect(text.contains("Rasgos: Noctámbulo") and text.contains("· Noctámbulo: −10 % de puntos") == false
		and text.contains("· Noctámbulo: +20 % de puntos de noche"), "la ficha explica el rasgo conocido: %s" % text)
	_expect(not text.contains("Mentor"), "y no muestra los que no se conocen")
	game.queue_free()
	await get_tree().process_frame
