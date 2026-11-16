# Rasgos de conducta e historial: impuntual (tarde, ausencias, puntualidad), adicto al café,
# ambicioso sin ascenso y leal que tarda más en renunciar.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=conduct
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261151
const DAY_HOUR: int = 10
## Sala de descanso: el espacio grande fuera de la Oficina Ejecutiva y el Área de trabajo;
## la cafetera va en medio.
const BREAK_CELL := Vector2i(3, 4)
const COFFEE_CELL := Vector2i(4, 5)
const SIM_DAYS: int = 140

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_data()
	_check_missing()
	_check_unpunctual()
	_check_coffee()
	_check_coffee_energy()
	_check_ambitious()
	_check_loyal()
	_check_bugs_caused()
	_check_save()
	await _check_ui()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva con tres puestos, dinero y los objetivos cumplidos.
func _new_game() -> void:
	GameClock.stop()
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(500000, "Prueba")
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


func _build_break_room() -> void:
	var builder := Builder.new()
	_expect(builder.mark_room(Staff.BREAK_ROOM, BREAK_CELL)["ok"], "marcar la Sala de descanso")
	_expect(builder.place("coffee_maker", COFFEE_CELL, 2)["ok"], "cafetera")
	_expect(Projects.has_working_room(Staff.BREAK_ROOM), "la Sala de descanso funciona")


# Contrata a alguien de ese cargo y nivel con esos rasgos.
func _hire(role: String, level: String, traits: Array = []) -> Dictionary:
	var opened: Dictionary = Staff.open_vacancy(role, level, StaffCatalog.get_salary(role, level), true)
	_expect(opened["ok"], "publicar %s: %s" % [role, opened["message"]])
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	var candidate: Dictionary = Staff.get_vacancy(opened["id"])["candidates"][0]
	Staff.make_offer(candidate["id"], candidate["asked_salary"])
	var employee: Dictionary = Staff.get_employee(candidate["id"])
	_expect(not employee.is_empty(), "contratado: %s %s" % [role, level])
	(employee["traits"] as Array).assign(traits)
	return employee


# Sin contrato renunciarían antes de terminar la prueba.
func _keep_happy(people: Array) -> void:
	for person: Dictionary in people:
		person["mood"] = 100
		person["stress"] = 0
		person["bad_days"] = 0


# Una hora (absoluta) del próximo día hábil a esa hora del reloj.
func _hour_at(clock_hour: int) -> int:
	var at: int = Staff.get_absolute_hour() + 1
	while Staff.get_weekday_at(at) >= 5 or posmod(at, 24) != clock_hour:
		at += 1
	return at


# Adelanta el reloj hasta esa hora absoluta.
func _go_to(at: int) -> void:
	GameClock.fast_forward_hours(at - Staff.get_absolute_hour())


func _worker(contract: Dictionary, employee: Dictionary, at: int) -> Dictionary:
	for worker: Dictionary in Projects.get_workers(contract, at):
		if worker["key"] == Staff.employee_key(employee["id"]):
			return worker
	return {}


func _contract_for(team: Dictionary) -> Dictionary:
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	contract["team_id"] = team["id"]
	return contract


func _check_data() -> void:
	for trait_id: String in ["unpunctual", "coffee_addict", "ambitious", "loyal"]:
		_expect(not StaffCatalog.get_trait_effects(trait_id).is_empty(), "el rasgo %s tiene efecto" % trait_id)
	_expect(Staff.describe_trait("unpunctual").contains("20 % de llegar una hora tarde")
		and Staff.describe_trait("unpunctual").contains("2 % de faltar"), "describe al impuntual: %s" % Staff.describe_trait("unpunctual"))
	_expect(Staff.describe_trait("coffee_addict").contains("−15 %"), "describe al adicto: %s" % Staff.describe_trait("coffee_addict"))
	_expect(Staff.describe_trait("ambitious").contains("15 días") and Staff.describe_trait("ambitious").contains("tientan más"),
		"describe al ambicioso: %s" % Staff.describe_trait("ambitious"))
	_expect(Staff.describe_trait("loyal").contains("el doble"), "describe al leal: %s" % Staff.describe_trait("loyal"))


# En las horas en que falta no cuenta como presente ni produce.
func _check_missing() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], worker["id"])
	var contract: Dictionary = _contract_for(team)
	var at: int = _hour_at(8)
	var key: String = Staff.employee_key(worker["id"])
	var weekday: int = Staff.get_weekday_at(at)
	worker["missing_from"] = at
	worker["missing_until"] = at + 1
	_expect(not Staff.is_expected(key, weekday, 8) and Staff.is_expected(key, weekday, 9), "tarde: falta la primera hora y llega a la segunda")
	_expect(_worker(contract, worker, at).is_empty() and not _worker(contract, worker, at + 1).is_empty(), "no produce mientras falta")
	worker["missing_until"] = at + 9
	_expect(not Staff.is_expected(key, weekday, 10) and not Staff.is_expected(key, weekday, 16), "ausente: falta toda la jornada")
	_expect(Staff.is_expected(key, weekday, 10) == false, "la marca es de ese día")
	_go_to(at + 24 * 7 + 2)
	_expect(Staff.is_expected_now(key) or not Staff.get_schedule(worker).is_working(GameClock.get_weekday(), GameClock.get_hour()),
		"la semana siguiente vuelve a estar")


func _run_days(people: Array, days: int) -> void:
	for day: int in range(days):
		_keep_happy(people)
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)


func _check_unpunctual() -> void:
	_new_game()
	var late_one: Dictionary = _hire("programmer", "junior", ["unpunctual"])
	var punctual: Dictionary = _hire("designer", "junior")
	_notices.clear()
	_run_days([late_one, punctual], SIM_DAYS)
	var late: int = int(late_one["late_count"])
	var absent: int = int(late_one["absent_count"])
	var total: int = late + absent + int(late_one["on_time_count"])
	_expect(total >= 95 and total <= 101, "cuenta cada jornada: %d" % total)
	_expect(late >= total * 0.1 and late <= total * 0.3, "llega tarde ~20 %% de las veces: %d de %d" % [late, total])
	_expect(absent <= total * 0.08, "falta poco: %d de %d" % [absent, total])
	_expect(int(punctual["late_count"]) == 0 and int(punctual["absent_count"]) == 0 and int(punctual["on_time_count"]) >= total - 1,
		"quien no es impuntual siempre llega a tiempo")
	_expect(Staff.get_punctuality(punctual) == 100 and Staff.get_punctuality(late_one) == roundi(100.0 * (total - late - absent) / total),

		"puntualidad: %d %% y %d %%" % [Staff.get_punctuality(punctual), Staff.get_punctuality(late_one)])
	_expect(absent == 0 or _notices.any(func(text: String) -> bool: return text.contains("faltó")), "una ausencia avisa")
	_new_game()
	var again: Dictionary = _hire("programmer", "junior", ["unpunctual"])
	var other: Dictionary = _hire("designer", "junior")
	_run_days([again, other], SIM_DAYS)
	_expect(int(again["late_count"]) == late and int(again["absent_count"]) == absent, "mismo resultado con la misma semilla")
	_expect(Staff.get_punctuality({}) == -1, "sin jornadas no hay puntualidad")


func _check_coffee() -> void:
	_new_game()
	var addict: Dictionary = _hire("programmer", "junior")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], addict["id"])
	var contract: Dictionary = _contract_for(team)
	contract["progress"]["design"] = float(contract["points"]["design"])
	var at: int = _hour_at(DAY_HOUR)
	var plain: float = float(_worker(contract, addict, at)["rate"])
	(addict["traits"] as Array).assign(["coffee_addict"])
	_expect(not Staff.has_coffee(), "sin Sala de descanso no hay café")
	_expect(is_equal_approx(float(_worker(contract, addict, at)["rate"]), plain * 0.85), "sin café el adicto rinde 85 %")
	_build_break_room()
	_expect(Staff.has_coffee() and is_equal_approx(float(_worker(contract, addict, at)["rate"]), plain), "con cafetera rinde normal")
	Events.trigger("coffee")
	Events.choose(1)
	_expect(not Staff.has_coffee() and is_equal_approx(float(_worker(contract, addict, at)["rate"]), plain * 0.85),
		"«Esperar al pedido»: el adicto rinde menos hoy")
	_keep_happy([addict])
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(Staff.has_coffee(), "al día siguiente vuelve el café")


func _check_coffee_energy() -> void:
	_new_game()
	_build_break_room()
	var addict: Dictionary = _hire("programmer", "junior", ["coffee_addict"])
	var other: Dictionary = _hire("designer", "junior")
	_go_to(_hour_at(DAY_HOUR))
	for person: Dictionary in [addict, other]:
		person["energy"] = 50
	GameClock.fast_forward_hours(1)
	var normal: int = int(StaffCatalog.get_workday("energy_per_work_hour"))
	_expect(int(other["energy"]) == 50 + normal, "sin el rasgo: %d" % other["energy"])
	_expect(int(addict["energy"]) == 50 + normal + 2, "el adicto con café recupera +2: %d" % addict["energy"])


func _check_ambitious() -> void:
	_new_game()
	var ambitious: Dictionary = _hire("programmer", "junior", ["ambitious"])
	var calm: Dictionary = _hire("designer", "junior")
	for person: Dictionary in [ambitious, calm]:
		person["projects_worked"] = 20
		person["hired_day"] = GameClock.get_day_count() - 200
	_expect(bool(Staff.get_promotion_progress(ambitious)["ready"]), "puede ascender")
	_keep_happy([ambitious, calm])
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(int(ambitious["promotion_ready_day"]) == GameClock.get_day_count(), "anota desde cuándo puede")
	_expect(int(calm["promotion_ready_day"]) == Staff.NOT_MISSING, "a quien no es ambicioso no se le anota")
	_run_days([ambitious, calm], 14)
	_expect(not Staff.is_waiting_promotion(ambitious), "a los 14 días todavía espera tranquilo")
	_run_days([ambitious, calm], 1)
	_expect(Staff.is_waiting_promotion(ambitious), "a los 15 se molesta")
	var waiting: int = Staff.get_mood_target(ambitious)
	var since: int = int(ambitious["promotion_ready_day"])
	ambitious["promotion_ready_day"] = Staff.NOT_MISSING
	var calm_target: int = Staff.get_mood_target(ambitious)
	ambitious["promotion_ready_day"] = since
	_expect(waiting == calm_target - 15, "−15 a su meta de ánimo: %d → %d" % [calm_target, waiting])
	var result: Dictionary = Staff.promote(ambitious["id"], int(ambitious["salary"]) + 1000)
	_expect(result["ok"], "ascenderlo: %s" % result["message"])
	_run_days([ambitious, calm], 1)
	_expect(not Staff.is_waiting_promotion(ambitious), "ascendido, deja de esperar")
	_expect(int(ambitious["promotion_ready_day"]) == GameClock.get_day_count(), "y la espera vuelve a contar desde hoy")


# Con ánimo bajo cada día: el leal avisa con el doble de días.
func _check_loyal() -> void:
	_new_game()
	var loyal: Dictionary = _hire("programmer", "junior", ["loyal"])
	var other: Dictionary = _hire("designer", "junior")
	var needed: int = int(StaffCatalog.get_morale("quit_bad_days"))
	for day: int in range(needed * 2):
		for person: Dictionary in [loyal, other]:
			person["mood"] = 0
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
		if day == needed - 1:
			_expect(int(other["quit_day"]) != Staff.NO_QUIT, "a los %d días mal avisa" % needed)
			_expect(int(loyal["quit_day"]) == Staff.NO_QUIT, "el leal todavía no")
	_expect(int(loyal["quit_day"]) != Staff.NO_QUIT, "el leal avisa a los %d días" % (needed * 2))


func _check_bugs_caused() -> void:
	_new_game()
	var programmer: Dictionary = _hire("programmer", "intern")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], programmer["id"])
	var contract: Dictionary = _contract_for(team)
	contract["progress"]["design"] = float(contract["points"]["design"])
	_run_days([programmer], 10)
	var total: int = int(contract["bugs_hidden"]) + int(contract["bugs_found"]) + int(contract["bugs_fixed"])
	_expect(total > 0 and int(programmer["bugs_caused"]) == total, "anota los errores que generó: %d de %d" % [programmer["bugs_caused"], total])
	_expect(Staff.describe_history(programmer).contains("%d errores causados" % total), "historial: %s" % Staff.describe_history(programmer))


func _check_save() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior", ["unpunctual"])
	worker["late_count"] = 3
	worker["absent_count"] = 1
	worker["on_time_count"] = 16
	worker["bugs_caused"] = 7
	worker["missing_from"] = 100
	worker["missing_until"] = 109
	worker["promotion_ready_day"] = 4
	Staff.coffee_out_day = GameClock.get_day_count()
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(Staff.coffee_out_day == Staff.NO_COFFEE_OUT, "partida nueva con café")
	_expect(SaveManager.load_game("slot_5"), "cargar")
	var loaded: Dictionary = Staff.get_employee(worker["id"])
	_expect(int(loaded["late_count"]) == 3 and int(loaded["absent_count"]) == 1 and int(loaded["on_time_count"]) == 16
		and int(loaded["bugs_caused"]) == 7 and int(loaded["missing_from"]) == 100 and int(loaded["missing_until"]) == 109
		and int(loaded["promotion_ready_day"]) == 4, "se guarda el historial")
	_expect(Staff.coffee_out_day == GameClock.get_day_count(), "y el día sin café")
	# Una partida vieja no tenía historial.
	var state: Dictionary = Staff.export_state()
	for saved: Dictionary in state["employees"]:
		for field: String in ["late_count", "absent_count", "on_time_count", "bugs_caused", "missing_from", "missing_until", "promotion_ready_day"]:
			saved.erase(field)
	state.erase("coffee_out_day")
	Staff.import_state(state)
	loaded = Staff.get_employee(worker["id"])
	_expect(int(loaded["late_count"]) == 0 and int(loaded["missing_from"]) == Staff.NOT_MISSING and Staff.get_punctuality(loaded) == -1,
		"una partida vieja empieza sin historial")


func _check_ui() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "junior", ["unpunctual"])
	(worker["known_traits"] as Array).assign(["unpunctual"])
	worker["late_count"] = 2
	worker["on_time_count"] = 8
	worker["projects_worked"] = 1
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var card: EmployeeCard = game.get_node("EmployeeCard")
	card.open_employee(worker["id"])
	var text: String = card.get_text()
	_expect(text.contains("Historial: 1 contrato · 0 errores causados · 2 llegadas tarde · 0 ausencias · puntualidad 80 %"),
		"la ficha muestra el historial: %s" % text)
	_expect(text.contains("· Impuntual: 20 % de llegar una hora tarde"), "y explica el rasgo")
	game.queue_free()
	await get_tree().process_frame
