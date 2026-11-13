# Prueba del hito 53: almuerzo en la oficina.
# Criterio: con la sala armada, quien cabe almuerza dentro, recupera más energía y rinde
# media hora; los demás salen.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=lunch
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261153
const LUNCH_HOUR: int = 12
## Sala de descanso: el espacio abierto del local fuera del Área de trabajo (norte) y de
## la Oficina Ejecutiva; sus muebles van contra la pared oeste.
const BREAK_CELL := Vector2i(3, 4)
const COFFEE_CELL := Vector2i(0, 4)
const FRIDGE_CELL := Vector2i(0, 5)
const MICROWAVE_CELL := Vector2i(0, 6)
const TABLE_CELL := Vector2i(1, 4)
const SECOND_TABLE_CELL := Vector2i(1, 6)

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	# Sin baños para medir la producción exacta (los baños tienen su parte).
	Staff.bathrooms_enabled = false
	_check_data()
	_check_seats()
	_check_who_eats()
	_check_energy()
	_check_production()
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


func _set_up_lunch() -> void:
	_expect(_builder.place("fridge", FRIDGE_CELL, 1)["ok"], "nevera")
	_expect(_builder.place("microwave", MICROWAVE_CELL, 1)["ok"], "microondas")
	_expect(_builder.place("dining_table", TABLE_CELL, 0)["ok"], "mesa de comedor")


# Tres empleados con puesto y copias sin puesto hasta llegar a total: todos almuerzan a
# las 12 (de 8 a 17).
func _hire_staff(total: int) -> Array[Dictionary]:
	var hired: Array[Dictionary] = []
	for index: int in range(mini(total, 3)):
		var employee: Dictionary = Staff.hire_directly("programmer", "junior")
		_expect(not employee.is_empty(), "contratado %d" % index)
		(employee["traits"] as Array).clear()
		hired.append(employee)
	for index: int in range(total - hired.size()):
		var copy: Dictionary = hired[0].duplicate(true)
		copy["id"] = 1000 + index
		copy["name"] = "Copia %d" % index
		Staff.employees.append(copy)
		hired.append(copy)
	return hired


# Una hora (absoluta) del próximo día hábil a esa hora del reloj.
func _hour_at(clock_hour: int) -> int:
	var at: int = Staff.get_absolute_hour() + 1
	while Staff.get_weekday_at(at) >= 5 or posmod(at, 24) != clock_hour:
		at += 1
	return at


func _go_to(at: int) -> void:
	GameClock.fast_forward_hours(at - Staff.get_absolute_hour())


func _rate_of(contract: Dictionary, key: String, at: int) -> float:
	for worker: Dictionary in Projects.get_workers(contract, at):
		if worker["key"] == key:
			return float(worker["rate"])
	return 0.0


func _contract(team_id: int) -> Dictionary:
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	contract["team_id"] = team_id
	return contract


func _check_data() -> void:
	_expect(FurnitureCatalog.get_price("fridge") == 400 and FurnitureCatalog.get_price("microwave") == 150
		and FurnitureCatalog.get_price("dining_table") == 300, "nevera $400, microondas $150, mesa $300")
	_expect(FurnitureCatalog.get_dining_seats("dining_table") == 4 and FurnitureCatalog.get_lunch_part("fridge") == "fridge",
		"4 asientos por mesa")
	_expect(is_equal_approx(StaffCatalog.get_lunch("energy_factor"), 2.0) and is_equal_approx(StaffCatalog.get_lunch("work_factor"), 0.5),
		"el doble de energía y media hora de trabajo")


# Asientos solo con nevera, microondas y mesa en una Sala de descanso que funciona.
func _check_seats() -> void:
	_new_game()
	_expect(OfficeState.get_lunch_seats() == 0, "solo con cafetera no hay almuerzo dentro")
	_expect(_builder.place("fridge", FRIDGE_CELL, 1)["ok"] and OfficeState.get_lunch_seats() == 0, "falta el microondas y la mesa")
	_expect(_builder.place("microwave", MICROWAVE_CELL, 1)["ok"] and OfficeState.get_lunch_seats() == 0, "falta la mesa")
	_expect(_builder.place("dining_table", TABLE_CELL, 0)["ok"] and OfficeState.get_lunch_seats() == 4, "con una mesa, 4 asientos")
	_expect(OfficeState.get_lunch_spots().size() >= 4, "lugares junto a la mesa: %s" % [OfficeState.get_lunch_spots()])
	var blocked: Array[Vector2i] = OfficeState.get_blocking_cells()
	_expect(OfficeState.get_lunch_spots().all(func(spot: Vector2i) -> bool: return not blocked.has(spot) and spot != OfficeState.entrance),
		"los lugares están libres")
	_expect(_builder.place("dining_table", SECOND_TABLE_CELL, 0)["ok"] and OfficeState.get_lunch_seats() == 8, "con dos mesas, 8")
	# Sin la cafetera la Sala de descanso no funciona.
	OfficeState.furniture = OfficeState.furniture.filter(func(item: Dictionary) -> bool: return item["id"] != "coffee_maker")
	_expect(OfficeState.get_lunch_seats() == 0, "sin Sala de descanso que funcione no hay almuerzo dentro")


# 4 asientos: el CEO y los 3 más antiguos almuerzan dentro; los demás salen.
func _check_who_eats() -> void:
	_new_game()
	_set_up_lunch()
	var people: Array[Dictionary] = _hire_staff(6)
	var at: int = _hour_at(LUNCH_HOUR)
	var inside: Dictionary[String, bool] = Staff.get_lunch_inside(at)
	_expect(inside.size() == 4 and inside.has("ceo"), "el CEO y 3 más: %s" % [inside.keys()])
	for index: int in range(people.size()):
		var key: String = Staff.employee_key(people[index]["id"])
		_expect(inside.has(key) == (index < 3), "%s %s" % [people[index]["name"], "dentro" if index < 3 else "fuera"])
	_expect(Staff.get_lunch_inside(at - 1).is_empty(), "a las 11 nadie almuerza")
	Staff.ceo_at_work = false
	_expect(Staff.get_lunch_inside(at).size() == 4 and not Staff.get_lunch_inside(at).has("ceo"), "el CEO en casa deja su asiento")
	Staff.ceo_at_work = true
	people[0]["missing_from"] = at - 4
	people[0]["missing_until"] = at + 5
	_expect(not Staff.get_lunch_inside(at).has(Staff.employee_key(people[0]["id"])), "quien faltó no almuerza dentro")


# Dentro descansa el doble que fuera.
func _check_energy() -> void:
	_new_game()
	_set_up_lunch()
	var people: Array[Dictionary] = _hire_staff(5)
	_go_to(_hour_at(LUNCH_HOUR))
	for person: Dictionary in people:
		person["energy"] = 50
	GameClock.fast_forward_hours(1)
	var rest: int = int(StaffCatalog.get_workday("energy_per_rest_hour"))
	# Con café (hito 54) quien almuerza dentro recupera un poco más.
	var inside: int = rest * 2 + int(StaffCatalog.get_breaks("coffee_energy"))
	_expect(int(people[0]["energy"]) == 50 + inside, "dentro +%d: %d" % [inside, people[0]["energy"]])
	_expect(int(people[4]["energy"]) == 50 + rest, "fuera +%d: %d" % [rest, people[4]["energy"]])
	# Sin microondas todos salen.
	OfficeState.furniture = OfficeState.furniture.filter(func(item: Dictionary) -> bool: return item["id"] != "microwave")
	_go_to(_hour_at(LUNCH_HOUR))
	people[0]["energy"] = 50
	GameClock.fast_forward_hours(1)
	_expect(int(people[0]["energy"]) == 50 + rest, "sin microondas sale y descansa normal")


# Almorzando dentro rinde media hora; fuera nada.
func _check_production() -> void:
	_new_game()
	_set_up_lunch()
	var people: Array[Dictionary] = _hire_staff(3)
	var team: Dictionary = Staff.create_team()
	for person: Dictionary in people:
		Staff.add_to_team(team["id"], person["id"])
	var contract: Dictionary = _contract(team["id"])
	var ceo_contract: Dictionary = _contract(Projects.CEO_TEAM)
	var at: int = _hour_at(LUNCH_HOUR)
	var key: String = Staff.employee_key(people[0]["id"])
	var working: float = _rate_of(contract, key, at - 1)
	_expect(working > 0.0 and is_equal_approx(_rate_of(contract, key, at), working * 0.5), "el empleado rinde la mitad: %.2f de %.2f" % [_rate_of(contract, key, at), working])
	var ceo_working: float = _rate_of(ceo_contract, "ceo", at - 1)
	_expect(ceo_working > 0.0 and is_equal_approx(_rate_of(ceo_contract, "ceo", at), ceo_working * 0.5), "el CEO también")
	# Con otro empleado más antiguo ocupando el último asiento, el tercero sale y no rinde.
	var copy: Dictionary = people[0].duplicate(true)
	copy["id"] = 999
	Staff.employees.push_front(copy)
	var last: String = Staff.employee_key(people[2]["id"])
	_expect(not Staff.get_lunch_inside(at).has(last) and is_zero_approx(_rate_of(contract, last, at)), "quien no cabe sale y no rinde")
	Staff.employees.pop_front()
	OfficeState.furniture = OfficeState.furniture.filter(func(item: Dictionary) -> bool: return item["id"] != "dining_table")
	_expect(is_zero_approx(_rate_of(contract, key, at)) and is_zero_approx(_rate_of(ceo_contract, "ceo", at)), "sin mesa nadie trabaja en el almuerzo")


func _check_ui() -> void:
	_new_game()
	_set_up_lunch()
	var people: Array[Dictionary] = _hire_staff(3)
	var extra: Dictionary = people[0].duplicate(true)
	extra["id"] = 999
	Staff.employees.append(extra)
	_go_to(_hour_at(LUNCH_HOUR))
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var spots: Array[Vector2i] = OfficeState.get_lunch_spots()
	var eaters: Array[OfficeCharacter] = []
	for character: OfficeCharacter in game.get_characters():
		if spots.has(character.get_seat_cell()):
			eaters.append(character)
	_expect(eaters.size() == 4, "4 caminan a la mesa: %d" % eaters.size())
	var outside: OfficeCharacter = game.employees[999]
	_expect(not spots.has(outside.get_seat_cell()) and outside.activity == OfficeCharacter.Activity.AWAY, "el quinto almuerza fuera")
	_expect(game.describe_employee_activity(999) == "almorzando fuera", "su ficha: %s" % game.describe_employee_activity(999))
	var eater: OfficeCharacter = game.employees[int(people[0]["id"])]
	eater.import_state({"activity": OfficeCharacter.Activity.SEATED, "cell": [eater.get_seat_cell().x, eater.get_seat_cell().y]})
	_expect(game.describe_employee_activity(int(people[0]["id"])) == "almorzando en la Sala de descanso",
		"la ficha dice que almuerza dentro: %s" % game.describe_employee_activity(int(people[0]["id"])))
	var spots_used: Dictionary[Vector2i, bool] = {}
	for character: OfficeCharacter in eaters:
		spots_used[character.get_seat_cell()] = true
	_expect(spots_used.size() == 4, "cada uno en su lugar")
	# Termina el almuerzo: vuelven a sus sillas.
	GameClock.fast_forward_hours(1)
	_expect(eater.get_seat_cell() == OfficeState.find_furniture_assigned_to(Staff.employee_key(people[0]["id"]))["cell"], "vuelve a su silla")
	_expect(game.ceo.get_seat_cell() == OfficeState.find_furniture_assigned_to("ceo")["cell"], "y el CEO a la suya")
	game.queue_free()
	await get_tree().process_frame
