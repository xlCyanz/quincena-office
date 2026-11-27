# Cambiar de puesto: un empleado pasa a un puesto libre de su lugar de trabajo o intercambia el suyo con otro;
# desde la ficha se elige en el mapa (StationPicker) y Esc lo cancela.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=station_change
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261127
const OPEN_CELL := Vector2i(3, 3)
## Escritorios que se prueban (mirando a +y); la silla va en la casilla de delante.
const DESKS: Array[Vector2i] = [Vector2i(4, 4), Vector2i(6, 4), Vector2i(2, 4), Vector2i(4, 2), Vector2i(6, 2), Vector2i(2, 2)]

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_new_game()
	var chairs: Array[int] = _build_stations(3)
	_expect(chairs.size() == 3, "tres puestos armados: %d" % chairs.size())
	if chairs.size() == 3:
		_check_logic(chairs)
		await _check_ui()
	SaveManager.new_game()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	GameClock.stop()
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	Economy.earn(200000, "Prueba")


# Arma count puestos en un Área de trabajo; devuelve el índice de cada silla.
func _build_stations(count: int) -> Array[int]:
	var chairs: Array[int] = []
	if not _builder.mark_room(Workstations.WORK_AREA, OPEN_CELL)["ok"]:
		return chairs
	for desk: Vector2i in DESKS:
		if chairs.size() == count:
			break
		var chair: Vector2i = desk + Vector2i(0, 1)
		if not _builder.quote_place("simple_desk", desk, 2)["ok"] or OfficeState.find_furniture_at(chair) >= 0:
			continue
		_builder.place("simple_desk", desk, 2)
		_builder.install_computer("basic_computer", desk)
		if not _builder.place("basic_chair", chair, 0)["ok"]:
			_builder.sell_furniture_at(desk)
			_builder.sell_furniture_at(desk)
			continue
		chairs.append(OfficeState.find_furniture_at(chair))
	return chairs


func _owner(chair: int) -> String:
	return String(OfficeState.furniture[chair]["assigned_to"])


func _check_logic(chairs: Array[int]) -> void:
	var first: Dictionary = Staff.hire_directly("programmer", "junior")
	var second: Dictionary = Staff.hire_directly("designer", "junior")
	var first_key: String = Staff.employee_key(first["id"])
	var second_key: String = Staff.employee_key(second["id"])
	var start: int = chairs.find_custom(func(chair: int) -> bool: return _owner(chair) == first_key)
	var free: int = chairs.find_custom(func(chair: int) -> bool: return _owner(chair).is_empty())
	_expect(start >= 0 and free >= 0, "uno queda libre")
	var choices: Array[Dictionary] = Staff.get_station_choices(first["id"])
	_expect(choices.size() == 2 and choices.all(func(choice: Dictionary) -> bool: return int(choice["chair"]) != chairs[start]),
		"se ofrecen los otros dos puestos, no el suyo: %d" % choices.size())
	_expect(not Staff.station_change_problem(first["id"], chairs[start]).is_empty(), "no se pasa a su propio puesto")
	var desk: int = OfficeState.find_furniture_at(OfficeState.furniture[chairs[free]]["cell"] - Vector2i(0, 1))
	_expect(not Staff.move_to_station(first["id"], desk)["ok"], "hay que elegir por la silla")

	var result: Dictionary = Staff.move_to_station(first["id"], chairs[free])
	_expect(result["ok"] and _owner(chairs[free]) == first_key and _owner(chairs[start]).is_empty(),
		"pasa al puesto libre y deja el suyo: %s" % result["message"])
	_expect(Staff.has_working_station(first), "el puesto nuevo funciona")
	var second_chair: int = OfficeState.furniture.find_custom(func(item: Dictionary) -> bool: return item["assigned_to"] == second_key)
	result = Staff.move_to_station(first["id"], second_chair)
	_expect(result["ok"] and _owner(second_chair) == first_key and _owner(chairs[free]) == second_key
		and String(result["message"]).contains("intercambian"), "con un puesto ocupado intercambian: %s" % result["message"])
	var counts: Dictionary[String, int] = {}
	for item: Dictionary in OfficeState.furniture:
		var owner: String = String(item["assigned_to"])
		if not owner.is_empty():
			counts[owner] = counts.get(owner, 0) + 1
	_expect(counts.get(first_key, 0) == 1 and counts.get(second_key, 0) == 1, "nadie queda con dos sillas: %s" % counts)

	var ceo_chair: int = OfficeState.furniture.find_custom(func(item: Dictionary) -> bool: return item["assigned_to"] == "ceo")
	_expect(ceo_chair < 0 or not Staff.move_to_station(first["id"], ceo_chair)["ok"], "la silla del CEO no se toma")
	var accountant: Dictionary = Staff.hire_directly("accountant", "junior")
	if not accountant.is_empty() and StaffCatalog.get_workplace("accountant") != Workstations.WORK_AREA:
		_expect(Staff.get_station_choices(accountant["id"]).all(func(choice: Dictionary) -> bool:
			return choice["room_type"] == StaffCatalog.get_workplace("accountant")), "solo puestos de su lugar de trabajo")


func _check_ui() -> void:
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var card: EmployeeCard = game.get_node("EmployeeCard")
	var picker: StationPicker = game.get_node("StationPicker")
	var staff: StaffPanel = game.get_node("StaffPanel")
	var employee: Dictionary = Staff.employees[0]
	var key: String = Staff.employee_key(employee["id"])
	staff.set_open(true)
	card.open_employee(employee["id"])
	await get_tree().process_frame
	var button: Button = card.get_station_button()
	_expect(button != null and not button.disabled and button.text == "Cambiar de puesto", "la ficha tiene Cambiar de puesto")
	button.pressed.emit()
	await get_tree().process_frame
	_expect(picker.is_active() and picker.get_employee_id() == employee["id"] and not staff.is_open(),
		"elige en el mapa con Personal cerrado")
	_expect(button.text == "Cancelar", "la ficha ofrece cancelar: %s" % button.text)
	_expect(game.call("handle_escape") == "station" and not picker.is_active() and button.text == "Cambiar de puesto",
		"Esc cancela la elección")

	button.pressed.emit()
	await get_tree().process_frame
	var target: Dictionary = {}
	for choice: Dictionary in picker.get_choices():
		if String(choice["owner"]).is_empty():
			target = choice
	_expect(not target.is_empty(), "hay un puesto libre marcado")
	if not target.is_empty():
		var desk: Dictionary = OfficeState.furniture[target["desk"]]
		_expect(picker.get_choice_at(desk["cell"]) >= 0, "el escritorio también sirve para elegir")
		var result: Dictionary = picker.pick_at(desk["cell"])
		_expect(result["ok"] and _owner(target["chair"]) == key and not picker.is_active(), "elegir lo pasa al puesto: %s" % result["message"])
		await get_tree().process_frame
		_expect(button.text == "Cambiar de puesto", "la ficha vuelve a la normalidad")
	_expect(not picker.pick_at(Vector2i(-50, -50))["ok"], "sin elección activa no pasa nada")
	game.queue_free()
	await get_tree().process_frame
