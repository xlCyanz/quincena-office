# Prueba del hito 54: Sala de descanso y pausas.
# Criterio: un cansado toma una pausa si hay sofá libre y recupera energía; el ping pong
# sube el ánimo y baja un poco la producción; la máquina da su ingreso diario.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=breaks
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261154
## Sala de descanso: el espacio abierto del local fuera del Área de trabajo (norte) y de
## la Oficina Ejecutiva.
const BREAK_CELL := Vector2i(3, 4)
const COFFEE_CELL := Vector2i(0, 4)
const WATER_CELL := Vector2i(0, 5)
const VENDING_CELL := Vector2i(0, 6)
const SOFA_CELL := Vector2i(1, 6)
const PING_PONG_CELL := Vector2i(4, 5)

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	# Sin baños para medir la producción exacta (los baños tienen su parte).
	Staff.bathrooms_enabled = false
	_check_data()
	_check_places()
	_check_breaks()
	_check_mood()
	_check_ping_pong()
	_check_vending()
	_check_save()
	await _check_ui()
	Staff.bathrooms_enabled = true
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva con un Área de trabajo de tres puestos al norte y la Sala de descanso con
# su cafetera en el resto del local.
func _new_game() -> void:
	GameClock.stop()
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(100000, "Prueba")
	Projects.offers.clear()
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(_builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(_builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	for x: int in [3, 4, 5]:
		_expect(_builder.place("simple_desk", Vector2i(x, 0), 2)["ok"], "escritorio en %d" % x)
		_expect(_builder.place("basic_chair", Vector2i(x, 1), 0)["ok"], "silla en %d" % x)
		_expect(_builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "computadora en %d" % x)
	_expect(_builder.mark_room(OfficeState.BREAK_ROOM, BREAK_CELL)["ok"], "marcar la Sala de descanso")
	_expect(_builder.place("coffee_maker", COFFEE_CELL, 1)["ok"], "cafetera")


func _hire_three() -> Array[Dictionary]:
	var hired: Array[Dictionary] = []
	for index: int in range(3):
		var employee: Dictionary = Staff.hire_directly("programmer", "junior")
		_expect(not employee.is_empty(), "contratado %d" % index)
		(employee["traits"] as Array).clear()
		hired.append(employee)
	return hired


# Una hora (absoluta) del próximo día hábil a esa hora del reloj.
func _hour_at(clock_hour: int) -> int:
	var at: int = Staff.get_absolute_hour() + 1
	while Staff.get_weekday_at(at) >= 5 or posmod(at, 24) != clock_hour:
		at += 1
	return at


func _go_to(at: int) -> void:
	GameClock.fast_forward_hours(at - Staff.get_absolute_hour())


func _keep_happy(people: Array[Dictionary]) -> void:
	for person: Dictionary in people:
		person["mood"] = 100
		person["stress"] = 0
		person["bad_days"] = 0


func _team_contract(people: Array[Dictionary]) -> Dictionary:
	var team: Dictionary = Staff.create_team()
	for person: Dictionary in people:
		Staff.add_to_team(team["id"], person["id"])
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	contract["team_id"] = team["id"]
	return contract


func _rate_of(contract: Dictionary, person: Dictionary, at: int) -> float:
	for worker: Dictionary in Projects.get_workers(contract, at):
		if worker["key"] == Staff.employee_key(person["id"]):
			return float(worker["rate"])
	return 0.0


func _check_data() -> void:
	_expect(FurnitureCatalog.get_price("sofa") == 500 and FurnitureCatalog.get_price("water_dispenser") == 120
		and FurnitureCatalog.get_price("ping_pong") == 700 and FurnitureCatalog.get_price("vending_machine") == 900,
		"sofá $500, agua $120, ping pong $700, expendedora $900")
	_expect(int(FurnitureCatalog.get_number("sofa", "rest_places")) == 2, "el sofá tiene 2 lugares")
	_expect(FurnitureCatalog.get_footprint("ping_pong", Vector2i.ZERO, 0).size() == 4, "el ping pong ocupa 4 casillas")
	_expect(is_equal_approx(StaffCatalog.get_breaks("below_energy"), 40.0) and is_equal_approx(StaffCatalog.get_breaks("energy"), 15.0)
		and is_equal_approx(StaffCatalog.get_breaks("coffee_energy"), 3.0), "pausa bajo 40, +15 y +3 con café")


func _check_places() -> void:
	_new_game()
	_expect(OfficeState.get_rest_places() == 0, "sin sofá no hay lugares")
	_expect(_builder.place("sofa", SOFA_CELL, 0)["ok"] and OfficeState.get_rest_places() == 2, "un sofá, 2 lugares")
	_expect(OfficeState.get_rest_spots().size() >= 2, "lugares junto al sofá: %s" % [OfficeState.get_rest_spots()])
	OfficeState.furniture = OfficeState.furniture.filter(func(item: Dictionary) -> bool: return item["id"] != "coffee_maker")
	_expect(OfficeState.get_rest_places() == 0, "sin Sala de descanso que funcione no cuenta")


# Los dos más cansados descansan; el tercero sigue; quien no produce no toma pausas.
func _check_breaks() -> void:
	_new_game()
	var people: Array[Dictionary] = _hire_three()
	var cleaner: Dictionary = people[0].duplicate(true)
	cleaner["id"] = 900
	cleaner["role"] = "cleaner"
	Staff.employees.append(cleaner)
	var contract: Dictionary = _team_contract(people)
	_go_to(_hour_at(10))
	for pair: Array in [[people[0], 30], [people[1], 20], [people[2], 35], [cleaner, 5]]:
		(pair[0] as Dictionary)["energy"] = pair[1]
	GameClock.fast_forward_hours(1)
	_expect(Staff.get_breaks(Staff.get_absolute_hour()).is_empty(), "sin sofá nadie descansa")
	_expect(_builder.place("sofa", SOFA_CELL, 0)["ok"], "sofá")
	_go_to(_hour_at(10))
	for pair: Array in [[people[0], 30], [people[1], 20], [people[2], 35], [cleaner, 5]]:
		(pair[0] as Dictionary)["energy"] = pair[1]
	_keep_happy(people)
	GameClock.fast_forward_hours(1)
	var now: int = Staff.get_absolute_hour()
	var keys: Array[String] = Staff.get_breaks(now)
	var expected: Array[String] = [Staff.employee_key(people[1]["id"]), Staff.employee_key(people[0]["id"])]
	_expect(keys == expected,
		"los 2 más cansados, primero el que menos tiene: %s" % [keys])
	_expect(not keys.has(Staff.employee_key(cleaner["id"])), "la limpieza no toma pausas")
	_expect(Staff.is_on_break(Staff.employee_key(people[1]["id"])), "is_on_break")
	_expect(is_zero_approx(_rate_of(contract, people[1], now)) and _rate_of(contract, people[2], now) > 0.0,
		"en la pausa no produce; el otro sí")
	var before: Array[int] = [int(people[0]["energy"]), int(people[1]["energy"]), int(people[2]["energy"])]
	GameClock.fast_forward_hours(1)
	var rest: int = int(StaffCatalog.get_breaks("energy")) + int(StaffCatalog.get_breaks("coffee_energy"))
	_expect(int(people[1]["energy"]) == before[1] + rest and int(people[0]["energy"]) == before[0] + rest,
		"la pausa recupera +%d con café: %d → %d" % [rest, before[1], people[1]["energy"]])
	_expect(int(people[2]["energy"]) == before[2] + int(StaffCatalog.get_workday("energy_per_work_hour")), "el que trabajó pierde lo normal")
	_expect(Staff.get_breaks(Staff.get_absolute_hour()).is_empty(), "a las 12 almuerzan: nadie en pausa")
	_expect(Staff.get_breaks(now - 5).is_empty(), "las pausas viejas se olvidan")
	# Sin café la pausa recupera solo 15.
	_go_to(_hour_at(10))
	people[1]["energy"] = 20
	GameClock.fast_forward_hours(1)
	Staff.run_out_of_coffee()
	var resting: int = int(people[1]["energy"])
	GameClock.fast_forward_hours(1)
	_expect(int(people[1]["energy"]) == resting + 15, "sin café +15: %d → %d" % [resting, people[1]["energy"]])


# El agua, el ping pong y la máquina suben la meta de ánimo de todos; uno de cada uno.
func _check_mood() -> void:
	_new_game()
	var people: Array[Dictionary] = _hire_three()
	var base: int = Staff.get_mood_target(people[0])
	_expect(_builder.place("water_dispenser", WATER_CELL, 1)["ok"] and Staff.get_mood_target(people[0]) == base + 2, "agua +2")
	_expect(_builder.place("water_dispenser", Vector2i(5, 3), 2)["ok"] and Staff.get_mood_target(people[0]) == base + 2,
		"un segundo dispensador no suma")
	_expect(_builder.place("ping_pong", PING_PONG_CELL, 0)["ok"] and Staff.get_mood_target(people[0]) == base + 10, "ping pong +8")
	_expect(_builder.place("vending_machine", VENDING_CELL, 1)["ok"] and Staff.get_mood_target(people[1]) == base + 13, "máquina +3")
	OfficeState.furniture = OfficeState.furniture.filter(func(item: Dictionary) -> bool: return item["id"] != "coffee_maker")
	_expect(Staff.get_mood_target(people[0]) == base, "sin Sala de descanso que funcione no suman")


func _check_ping_pong() -> void:
	_new_game()
	var people: Array[Dictionary] = _hire_three()
	var contract: Dictionary = _team_contract(people)
	var at: int = _hour_at(10)
	var plain: float = _rate_of(contract, people[0], at)
	_expect(_builder.place("ping_pong", PING_PONG_CELL, 0)["ok"], "ping pong")
	_expect(plain > 0.0 and is_equal_approx(_rate_of(contract, people[0], at), plain * 0.97), "con ping pong se distraen: −3 %")
	_expect(_builder.place("ping_pong", Vector2i(1, 4), 0)["ok"] and is_equal_approx(_rate_of(contract, people[0], at), plain * 0.97),
		"dos mesas no distraen más")


# $2 por persona que estuvo en la oficina, al terminar el día.
func _check_vending() -> void:
	_new_game()
	var people: Array[Dictionary] = _hire_three()
	_expect(_builder.place("vending_machine", VENDING_CELL, 1)["ok"], "máquina expendedora")
	_go_to(_hour_at(10))
	var month: int = Economy.get_current_month()
	_keep_happy(people)
	_go_to(Staff.get_absolute_hour() + 24 - GameClock.get_hour())
	_expect(Economy.get_month_totals(month).get(Staff.CONCEPT_VENDING, 0) == 8, "4 personas (con el CEO): $8 = %d" % Economy.get_month_totals(month).get(Staff.CONCEPT_VENDING, 0))
	_expect(Staff.present_today.size() <= 1, "empieza un día nuevo: %d" % Staff.present_today.size())
	OfficeState.furniture = OfficeState.furniture.filter(func(item: Dictionary) -> bool: return item["id"] != "vending_machine")
	var before: int = Economy.get_month_totals(month).get(Staff.CONCEPT_VENDING, 0)
	_keep_happy(people)
	GameClock.fast_forward_hours(24)
	_expect(Economy.get_month_totals(Economy.get_current_month()).get(Staff.CONCEPT_VENDING, 0) <= before + 2, "sin máquina no cobra (salvo lo de la medianoche)")


func _check_save() -> void:
	_new_game()
	Staff.breaks = {50: ["employee_1"]}
	Staff.present_today = {"ceo": true, "employee_2": true}
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(Staff.breaks.is_empty() and Staff.present_today.is_empty(), "partida nueva sin pausas")
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(Staff.get_breaks(50) == (["employee_1"] as Array[String]) and Staff.present_today.size() == 2, "se guardan las pausas y la presencia")
	var state: Dictionary = Staff.export_state()
	state.erase("breaks")
	state.erase("present_today")
	Staff.import_state(state)
	_expect(Staff.breaks.is_empty() and Staff.present_today.is_empty(), "una partida vieja empieza sin pausas")


func _check_ui() -> void:
	_new_game()
	var people: Array[Dictionary] = _hire_three()
	_expect(_builder.place("sofa", SOFA_CELL, 0)["ok"], "sofá")
	_go_to(_hour_at(10))
	people[0]["energy"] = 10
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.fast_forward_hours(1)
	GameClock.stop()
	var spots: Array[Vector2i] = OfficeState.get_rest_spots()
	var tired: OfficeCharacter = game.employees[int(people[0]["id"])]
	_expect(spots.has(tired.get_seat_cell()), "el cansado camina al sofá: %s" % tired.get_seat_cell())
	tired.import_state({"activity": OfficeCharacter.Activity.SEATED, "cell": [tired.get_seat_cell().x, tired.get_seat_cell().y]})
	_expect(game.describe_employee_activity(int(people[0]["id"])) == "descansando en la Sala de descanso",
		"su ficha: %s" % game.describe_employee_activity(int(people[0]["id"])))
	var other: OfficeCharacter = game.employees[int(people[1]["id"])]
	_expect(not spots.has(other.get_seat_cell()), "los demás siguen en su silla")
	game.queue_free()
	await get_tree().process_frame
