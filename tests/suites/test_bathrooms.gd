# Prueba del hito 52: baños con capacidad.
# Criterio: con 25 personas y 2 inodoros baja el ánimo y la producción; con 3 no; el
# evento de baño dañado quita uno hasta repararlo.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=bathrooms
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261152
const DAY_HOUR: int = 10
## Baño de 3×2 en la esquina noreste del local de 6×8, junto a la Oficina Ejecutiva:
## inodoros arriba, lavamanos abajo a la izquierda y la puerta abajo en el medio.
const BATHROOM_CELL := Vector2i(4, 1)
const TOILET_CELLS: Array[Vector2i] = [Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)]
const SINK_CELL := Vector2i(3, 1)
## Área de trabajo en el espacio abierto del local, con un puesto.
const WORK_CELL := Vector2i(3, 4)
const DESK_CELL := Vector2i(4, 4)
const CHAIR_CELL := Vector2i(4, 5)

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_data()
	_check_without_bathroom()
	_check_capacity()
	_check_mood()
	_check_broken()
	_check_save()
	await _check_ui()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva con un puesto de trabajo y dinero de sobra; los objetivos ya cumplidos.
func _new_game() -> void:
	GameClock.stop()
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(100000, "Prueba")
	Projects.offers.clear()


# Paredes y Baño (sin muebles todavía).
func _build_bathroom() -> void:
	var y: int = GridEdge.AXIS_Y
	var result: Dictionary = _builder.apply([
		{"edge": Vector3i(3, 1, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 1, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 1, y), "kind": ConstructionCatalog.WALL},
	] as Array[Dictionary])
	_expect(result["ok"], "paredes del baño: %s" % result.get("message", ""))
	result = _builder.mark_room(OfficeState.BATHROOM, BATHROOM_CELL)
	_expect(result["ok"], "marcar el Baño: %s" % result.get("message", ""))
	_expect(_builder.place("sink", SINK_CELL, 0)["ok"], "lavamanos")


func _item_at(cell: Vector2i) -> Dictionary:
	for item: Dictionary in OfficeState.furniture:
		if item["cell"] == cell:
			return item
	return {}


func _add_toilets(count: int) -> void:
	for cell: Vector2i in TOILET_CELLS:
		if count <= 0:
			return
		if _item_at(cell).is_empty():
			_expect(_builder.place("toilet", cell, 2)["ok"], "inodoro en %s" % cell)
			count -= 1


# Un empleado de verdad (con puesto) y, si se pide, copias de él sin puesto hasta llegar
# a esa cantidad de empleados: todas trabajan de 8 a 17.
func _hire_staff(total: int) -> Dictionary:
	_expect(_builder.mark_room(Workstations.WORK_AREA, WORK_CELL)["ok"], "marcar el Área de trabajo")
	_expect(_builder.place("simple_desk", DESK_CELL, 2)["ok"] and _builder.place("basic_chair", CHAIR_CELL, 0)["ok"]
		and _builder.install_computer("basic_computer", DESK_CELL)["ok"], "un puesto")
	var employee: Dictionary = Staff.hire_directly("programmer", "junior")
	_expect(not employee.is_empty(), "contratado")
	(employee["traits"] as Array).clear()
	for index: int in range(total - 1):
		var copy: Dictionary = employee.duplicate(true)
		copy["id"] = 1000 + index
		copy["name"] = "Copia %d" % index
		Staff.employees.append(copy)
	return employee


# Una hora (absoluta) del próximo día hábil a esa hora del reloj.
func _hour_at(clock_hour: int) -> int:
	var at: int = Staff.get_absolute_hour() + 1
	while Staff.get_weekday_at(at) >= 5 or posmod(at, 24) != clock_hour:
		at += 1
	return at


func _ceo_contract() -> Dictionary:
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	contract["team_id"] = Projects.CEO_TEAM
	return contract


func _ceo_rate(contract: Dictionary, at: int) -> float:
	var workers: Array[Dictionary] = Projects.get_workers(contract, at)
	return 0.0 if workers.is_empty() else float(workers[0]["rate"])


func _check_data() -> void:
	_expect(is_equal_approx(StaffCatalog.get_bathrooms("people_per_toilet"), 10.0), "1 inodoro cada 10 personas")
	_expect(FurnitureCatalog.is_toilet("toilet") and not FurnitureCatalog.is_toilet("sink"), "el inodoro cuenta, el lavamanos no")
	_expect(Staff.get_toilets_needed(0) == 0 and Staff.get_toilets_needed(1) == 1 and Staff.get_toilets_needed(10) == 1
		and Staff.get_toilets_needed(11) == 2 and Staff.get_toilets_needed(25) == 3, "hacen falta hacia arriba")
	_expect(is_equal_approx(Staff.get_bathroom_factor(0), 1.0) and is_equal_approx(Staff.get_bathroom_factor(1), 0.95)
		and is_equal_approx(Staff.get_bathroom_factor(3), 0.85) and is_equal_approx(Staff.get_bathroom_factor(4), 0.8)
		and is_equal_approx(Staff.get_bathroom_factor(7), 0.8), "−5 % por inodoro que falta, hasta −20 %")


# El CEO solo sin baño: sale a buscar uno y rinde 5 % menos.
func _check_without_bathroom() -> void:
	_new_game()
	var contract: Dictionary = _ceo_contract()
	var at: int = _hour_at(DAY_HOUR)
	_expect(Staff.count_present(at) == 1, "el CEO cuenta como presente")
	_expect(Staff.get_toilet_capacity() == 0 and Staff.get_bathroom_shortage(at) == 1, "sin baño falta un inodoro")
	var short_rate: float = _ceo_rate(contract, at)
	Staff.bathrooms_enabled = false
	var full_rate: float = _ceo_rate(contract, at)
	Staff.bathrooms_enabled = true
	_expect(full_rate > 0.0 and is_equal_approx(short_rate, full_rate * 0.95), "el CEO rinde 95 %%: %.2f de %.2f" % [short_rate, full_rate])
	Staff.ceo_at_work = false
	_expect(Staff.count_present(at) == 0 and Staff.get_bathroom_shortage(at) == 0, "con el CEO en casa no hay nadie")
	Staff.ceo_at_work = true
	_build_bathroom()
	_expect(Staff.get_toilet_capacity() == 0, "un Baño sin inodoro no funciona")
	_add_toilets(1)
	_expect(Staff.get_toilet_capacity() == 1 and Staff.get_bathroom_shortage(at) == 0, "con un inodoro alcanza")
	_expect(is_equal_approx(_ceo_rate(contract, at), full_rate), "y rinde normal")


# 25 personas: con 2 inodoros falta uno; con 3 no.
func _check_capacity() -> void:
	_new_game()
	_build_bathroom()
	_add_toilets(2)
	_hire_staff(24)
	var contract: Dictionary = _ceo_contract()
	var at: int = _hour_at(DAY_HOUR)
	_expect(Staff.count_present(at) == 25, "25 personas a las 10: %d" % Staff.count_present(at))
	_expect(Staff.count_present(_hour_at(12)) == 0, "almorzando no cuentan (el CEO tampoco)")
	_expect(Staff.get_toilet_capacity() == 2 and Staff.get_bathroom_shortage(at) == 1, "con 2 inodoros falta uno")
	var short_rate: float = _ceo_rate(contract, at)
	_add_toilets(1)
	_expect(Staff.get_toilet_capacity() == 3 and Staff.get_bathroom_shortage(at) == 0, "con 3 alcanzan")
	_expect(is_equal_approx(short_rate, _ceo_rate(contract, at) * 0.95), "con 2 todos rinden 95 %")
	# Un empleado también rinde menos.
	var team: Dictionary = Staff.create_team()
	var worker: Dictionary = Staff.employees[0]
	Staff.add_to_team(team["id"], worker["id"])
	var team_contract: Dictionary = _ceo_contract()
	team_contract["team_id"] = team["id"]
	var full: float = float(Projects.get_workers(team_contract, at)[0]["rate"])
	OfficeState.furniture.erase(_item_at(TOILET_CELLS[2]))
	_expect(is_equal_approx(float(Projects.get_workers(team_contract, at)[0]["rate"]), full * 0.95), "el empleado también")
	# Sin inodoros: faltan 3 (−15 %).
	OfficeState.furniture = OfficeState.furniture.filter(func(item: Dictionary) -> bool: return not FurnitureCatalog.is_toilet(item["id"]))
	_expect(Staff.get_bathroom_shortage(at) == 3 and is_equal_approx(float(Projects.get_workers(team_contract, at)[0]["rate"]), full * 0.85),
		"sin inodoros −15 %")


# La meta de ánimo baja 10 el día que faltaron y el siguiente.
func _check_mood() -> void:
	_new_game()
	_build_bathroom()
	_add_toilets(2)
	var worker: Dictionary = _hire_staff(25)
	GameClock.fast_forward_hours(_hour_at(DAY_HOUR) - Staff.get_absolute_hour())
	_expect(Staff.bathroom_short_day == GameClock.get_day_count(), "anota el día en que faltaron")
	var short_target: int = Staff.get_mood_target(worker)
	Staff.bathroom_short_day = Staff.NO_SHORT_DAY
	var target: int = Staff.get_mood_target(worker)
	_expect(short_target == target - 10, "−10 a la meta de ánimo: %d → %d" % [target, short_target])
	_add_toilets(1)
	GameClock.fast_forward_hours(1)
	_expect(Staff.bathroom_short_day == Staff.NO_SHORT_DAY, "con 3 inodoros no falta")
	target = Staff.get_mood_target(worker)
	Staff.bathroom_short_day = GameClock.get_day_count() - 1
	_expect(Staff.get_mood_target(worker) == target - 10, "al día siguiente todavía molesta")
	Staff.bathroom_short_day = GameClock.get_day_count() - 2
	_expect(Staff.get_mood_target(worker) == target, "después ya no")


# «Baño dañado»: el cartel quita un inodoro hasta repararlo; el plomero no.
func _check_broken() -> void:
	_new_game()
	_build_bathroom()
	_add_toilets(3)
	_hire_staff(25)
	var at: int = _hour_at(DAY_HOUR)
	Events.trigger("broken_bathroom")
	Events.choose(0)
	_expect(Staff.broken_toilets == 0 and Staff.get_toilet_capacity() == 3, "con el plomero no se pierde ninguno")
	Events.trigger("broken_bathroom")
	var balance: int = Economy.balance
	Events.choose(1)
	_expect(Staff.broken_toilets == 1 and Staff.get_toilet_capacity() == 2, "con el cartel queda uno dañado")
	_expect(Economy.balance == balance, "el cartel no cobra")
	_expect(Staff.get_bathroom_shortage(at) == 1, "y ahora falta uno")
	_expect(Staff.repair_toilet()["ok"] and Economy.balance == balance - 400 and Staff.broken_toilets == 0
		and Staff.get_toilet_capacity() == 3, "reparar cuesta $400 y vuelve a contar")
	_expect(Economy.get_month_totals(Economy.get_current_month()).get(Staff.CONCEPT_REPAIR, 0) == -400, "con su concepto")
	_expect(not Staff.repair_toilet()["ok"], "sin dañados no se repara nada")
	for count: int in range(3):
		_expect(Staff.break_toilet(), "se daña el %d.º" % (count + 1))
	_expect(not Staff.break_toilet() and Staff.get_toilet_capacity() == 0, "no se dañan más de los que hay")
	Economy.charge(Economy.balance, "Prueba")
	_expect(not Staff.repair_toilet()["ok"] and Staff.broken_toilets == 3, "sin dinero no se repara")


func _check_save() -> void:
	_new_game()
	Staff.broken_toilets = 2
	Staff.bathroom_short_day = 7
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(Staff.broken_toilets == 0 and Staff.bathroom_short_day == Staff.NO_SHORT_DAY, "partida nueva sin daños")
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(Staff.broken_toilets == 2 and Staff.bathroom_short_day == 7, "se guardan los dañados y el día")
	var state: Dictionary = Staff.export_state()
	state.erase("broken_toilets")
	state.erase("bathroom_short_day")
	Staff.import_state(state)
	_expect(Staff.broken_toilets == 0 and Staff.bathroom_short_day == Staff.NO_SHORT_DAY, "una partida vieja empieza sin daños")


func _check_ui() -> void:
	_new_game()
	_build_bathroom()
	_add_toilets(1)
	Staff.broken_toilets = 1
	var worker: Dictionary = _hire_staff(5)
	GameClock.fast_forward_hours(_hour_at(DAY_HOUR) - Staff.get_absolute_hour())
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var panel: CompanyPanel = game.get_node("CompanyPanel")
	panel.set_open(true)
	var text: String = panel.get_text()
	_expect(text.contains("Baños") and text.contains("Hacen falta ahora (6 personas)") and text.contains("Faltan inodoros")
		and text.contains("rinden 5 % menos"), "Empresa muestra los baños: %s" % text)
	_expect(panel.get_repair_button() != null and panel.get_repair_button().text.contains("$400"), "y el botón de reparar")
	panel.get_repair_button().pressed.emit()
	await get_tree().process_frame
	_expect(Staff.broken_toilets == 0 and panel.get_repair_button() == null and not panel.get_text().contains("Faltan inodoros"),
		"reparado, alcanza y el botón se va")
	Staff.broken_toilets = 1
	# Los que están sentados salen a buscar un baño y vuelven.
	var characters: Array[OfficeCharacter] = game.get_characters()
	for character: OfficeCharacter in characters:
		character.import_state({"activity": OfficeCharacter.Activity.SEATED,
			"cell": [character.get_seat_cell().x, character.get_seat_cell().y]})
	# Cada uno sale una vez cada trip_every_hours (6) horas, repartidos: por hora como mucho
	# los que no caben (6 personas) ÷ 6 = 1, y en 12 horas nadie sale más de dos veces.
	var every: int = int(StaffCatalog.get_bathrooms("trip_every_hours"))
	_expect(every == 6, "una salida cada 6 horas")
	var hour: int = Staff.get_absolute_hour()
	var trips: Dictionary[String, int] = {}
	var per_hour: Array[int] = []
	var out: Array[OfficeCharacter] = []
	for step: int in range(every * 2):
		for character: OfficeCharacter in characters:
			character.import_state({"activity": OfficeCharacter.Activity.SEATED,
				"cell": [character.get_seat_cell().x, character.get_seat_cell().y]})
		per_hour.append(game._send_bathroom_trips(hour + step))
		out = characters.filter(func(character: OfficeCharacter) -> bool:
			return character.activity == OfficeCharacter.Activity.STEPPING_OUT)
		for character: OfficeCharacter in out:
			trips[character.person_key] = trips.get(character.person_key, 0) + 1
	var most: int = 0
	for count: int in per_hour:
		most = maxi(most, count)
	var total: int = 0
	for key: String in trips:
		total += trips[key]
	_expect(most <= 1 and total >= 4 and total <= 12 and trips.size() >= 3,
		"falta 1 inodoro: en %d horas %d salidas %s" % [every * 2, total, per_hour])
	for key: String in trips:
		_expect(trips[key] <= 2, "%s salió %d veces en %d horas" % [key, trips[key], every * 2])
	if out.is_empty():
		for character: OfficeCharacter in characters:
			character.step_out()
			out.append(character)
			break
	_expect(game.describe_employee_activity(worker["id"]) == "buscando un baño fuera del edificio"
		or game.describe_employee_activity(worker["id"]) == "trabajando", "la ficha lo dice")
	var walker: OfficeCharacter = out[0]
	walker.grid_position = Vector2(OfficeState.get_outside_of_entrance())
	walker._path.clear()
	walker._on_destination_reached()
	_expect(walker.activity == OfficeCharacter.Activity.WALKING_TO_DESK, "afuera, vuelve a su silla")
	_expect(not game.is_office_empty(), "salir al baño no vacía la oficina")
	Staff.broken_toilets = 0
	_expect(game._send_bathroom_trips() == 0, "con inodoros nadie sale")
	game.queue_free()
	await get_tree().process_frame
