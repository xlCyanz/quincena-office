# Jornada: cada empleado llega a su puesto por un camino válido y se va al terminar; la ficha
# muestra sus barras; con la oficina vacía el tiempo salta a la próxima entrada.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=workday
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261111
const FRAME: float = 1.0 / 60.0

var _failures: int = 0
var _checks: int = 0
var _game: Node
var _programmer: Dictionary = {}
var _seller: Dictionary = {}
var _left: Dictionary[String, int] = {}


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Carpeta aparte para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_expected()
	await _start_game()
	_check_arrival()
	_check_lunch()
	await _check_card()
	_check_end_of_day()
	_check_energy_overnight()
	await _check_save()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _check_catalog() -> void:
	var programmer: WorkSchedule = WorkSchedule.from_dict(StaffCatalog.get_role_schedule("programmer"))
	var seller: WorkSchedule = WorkSchedule.from_dict(StaffCatalog.get_role_schedule("salesperson"))
	_expect(programmer.describe() == "lun–vie 8:00–17:00", "horario del programador: %s" % programmer.describe())
	_expect(seller.describe() == "lun–vie 9:00–18:00", "horario del vendedor: %s" % seller.describe())
	_expect(WorkSchedule.from_dict({"days": [0, 2], "start_hour": 9, "end_hour": 13}).describe() == "lun, mié 9:00–13:00",
		"días sueltos")
	_expect(WorkSchedule.get_lunch_offset() == 4 and programmer.get_lunch_hour() == 12 and seller.get_lunch_hour() == 13 \
		and Staff.get_ceo_lunch_hour() == 12, "almuerzo a la 4.ª hora de la jornada")
	var weekdays: Array[int] = [0, 1, 2, 3, 4]
	_expect(StaffCatalog.get_ceo_arrival_hour() == 8 and StaffCatalog.get_ceo_arrival_days() == weekdays,
		"el CEO llega a las 8 de lunes a viernes")
	_expect(StaffCatalog.get_shirt_color("programmer") != StaffCatalog.get_shirt_color("designer"), "camisa por cargo")


func _check_expected() -> void:
	SaveManager.new_game()
	Staff.employees.append({"id": 99, "role": "programmer", "schedule": StaffCatalog.get_role_schedule("programmer"),
		"energy": 100})
	var key: String = Staff.employee_key(99)
	_expect(Staff.is_expected(key, 0, 8) and Staff.is_expected(key, 4, 16), "trabaja lun 8 y vie 16")
	_expect(not Staff.is_expected(key, 0, 12), "a las 12 almuerza")
	_expect(not Staff.is_expected(key, 0, 17) and not Staff.is_expected(key, 5, 10), "no trabaja lun 17 ni sáb 10")
	_expect(Staff.is_expected("ceo", 6, 3) and not Staff.is_expected("ceo", 0, 12), "el CEO está mientras no lo manden a casa, salvo al almorzar")
	# Lunes 17:00 con el CEO en casa: el programador llega en 15 h (martes 8).
	Staff.ceo_at_work = false
	Staff.employees.clear()
	GameClock.fast_forward_hours(9)
	Staff.employees.append({"id": 99, "role": "programmer", "schedule": StaffCatalog.get_role_schedule("programmer"),
		"energy": 100})
	_expect(Staff.hours_until_anyone_expected() == 15, "próxima llegada: %d h" % Staff.hours_until_anyone_expected())
	Staff.employees.clear()
	_expect(Staff.hours_until_anyone_expected() == 15, "el CEO también llega solo el martes a las 8")
	# El CEO llegó solo el martes; mandado a casa el viernes a las 17, vuelve el lunes a las 8.
	GameClock.fast_forward_hours(4 * 24)
	_expect(Staff.ceo_at_work, "el CEO volvió solo")
	Staff.ceo_at_work = false
	_expect(GameClock.get_weekday() == 4 and Staff.hours_until_anyone_expected() == 63, "del viernes 17 al lunes 8: %d h" % Staff.hours_until_anyone_expected())


# Dos puestos, un programador y un vendedor.
func _start_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Economy.earn(10000, "Prueba")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	GameClock.stop()
	_game.ceo.set_process(false)
	_game.ceo.left_office.connect(func() -> void: _left["ceo"] = _left.get("ceo", 0) + 1)
	var builder := Builder.new()
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	for x: int in [3, 5]:
		_expect(builder.place("simple_desk", Vector2i(x, 0), 2)["ok"], "escritorio en %d" % x)
		_expect(builder.place("basic_chair", Vector2i(x, 1), 0)["ok"], "silla en %d" % x)
		_expect(builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "computadora en %d" % x)
	var programmer_vacancy: int = Staff.open_vacancy("programmer", "junior", 1200, true)["id"]
	var seller_vacancy: int = Staff.open_vacancy("salesperson", "junior", 1000, true)["id"]
	GameClock.fast_forward_hours(1)  # lunes 9:00, llegan los candidatos
	_programmer = _hire(programmer_vacancy)
	_seller = _hire(seller_vacancy)
	for employee_id: int in _game.employees:
		var character: Employee = _game.employees[employee_id]
		character.set_process(false)
		character.left_office.connect(func() -> void: _left[character.person_key] = _left.get(character.person_key, 0) + 1)


func _hire(vacancy_id: int) -> Dictionary:
	var candidates: Array = Staff.get_vacancy(vacancy_id)["candidates"]
	_expect(not candidates.is_empty(), "llegó un candidato a la vacante %d" % vacancy_id)
	var candidate: Dictionary = candidates[0]
	_expect(Staff.make_offer(candidate["id"], candidate["asked_salary"])["result"] == "hired", "contratar a %s" % candidate["name"])
	return Staff.get_employee(candidate["id"])


func _character(employee: Dictionary) -> Employee:
	return _game.employees.get(employee["id"])


# Avanza reloj y personajes cuadro a cuadro hasta la condición, comprobando que nadie atraviese muebles ni paredes.
func _walk_until(condition: Callable, max_seconds: float, label: String) -> void:
	# Los topes son para horas de 10 s reales: se escalan.
	max_seconds *= GameConstants.SECONDS_PER_GAME_HOUR / 10.0
	var elapsed: float = 0.0
	var blocked: Array[Vector2i] = OfficeState.get_furniture_cells()
	var previous: Dictionary[OfficeCharacter, Vector2i] = {}
	while not condition.call() and elapsed < max_seconds:
		GameClock.advance(FRAME)
		for character: OfficeCharacter in _game.get_characters():
			character._process(FRAME)
			var cell: Vector2i = character.get_cell()
			var lot: Rect2i = OfficeState.lot_rect
			if character.visible and lot.has_point(cell):
				_expect(not blocked.has(cell) or cell == character.get_seat_cell(),
					"%s: %s atravesó un mueble en %s" % [label, character.display_name, cell])
				var before: Vector2i = previous.get(character, cell)
				if before != cell and lot.has_point(before):
					_expect(not OfficeState.blocks_passage(GridEdge.between(before, cell)),
						"%s: %s atravesó una pared" % [label, character.display_name])
			previous[character] = cell
		elapsed += FRAME
	_expect(condition.call(), "%s: no ocurrió en %.0f s" % [label, max_seconds])


func _all_seated() -> bool:
	for character: OfficeCharacter in _game.get_characters():
		if character.activity != OfficeCharacter.Activity.SEATED:
			return false
	return true


func _check_arrival() -> void:
	_expect(_game.employees.size() == 2, "un personaje por empleado: %d" % _game.employees.size())
	for employee: Dictionary in [_programmer, _seller]:
		var character: Employee = _character(employee)
		_expect(character != null and character.visible and character.activity == OfficeCharacter.Activity.WALKING_TO_DESK,
			"%s entra al contratarlo" % employee["name"])
		var path: Array[Vector2i] = character.get_path_cells()
		var seat: Vector2i = OfficeState.find_furniture_assigned_to(character.person_key)["cell"]
		_expect(character.get_seat_cell() == seat and not path.is_empty() and path[-1] == seat,
			"%s camina hasta su silla %s: %s" % [employee["name"], seat, path])
		_expect(character.shirt_color == StaffCatalog.get_shirt_color(employee["role"]), "camisa de su cargo")
	_walk_until(_all_seated, 60.0, "todos sentados")
	_expect(_character(_programmer).get_cell() == Vector2i(3, 1) and _character(_seller).get_cell() == Vector2i(5, 1),
		"cada uno en su silla")


# A las 12 salen todos y con la oficina vacía el tiempo salta a las 13. Cada uno almuerza a la 4.ª hora:
# el CEO y el programador (desde las 8) a las 12, el vendedor (desde las 9) a las 13.
func _check_lunch() -> void:
	GameClock.advance((11 - GameClock.get_hour()) * GameConstants.SECONDS_PER_GAME_HOUR)
	_walk_until(func() -> bool: return GameClock.get_hour() == 12, 10.0, "llegar a las 12")
	_expect(_game.ceo.activity == OfficeCharacter.Activity.WALKING_OUT
		and _character(_programmer).activity == OfficeCharacter.Activity.WALKING_OUT, "a las 12 salen el CEO y el programador")
	_expect(_character(_seller).activity == OfficeCharacter.Activity.SEATED, "el vendedor sigue: almuerza a las 13")
	_expect(_game.describe_employee_activity(_programmer["id"]) == "saliendo a almorzar", "estado al salir")
	_walk_until(func() -> bool: return GameClock.get_hour() == 13, 90.0, "llegar a las 13")
	_expect(_left.get("ceo", 0) == 1 and _left.get(Staff.employee_key(_programmer["id"]), 0) == 1, "salieron una vez")
	_expect(_game.ceo.activity == OfficeCharacter.Activity.WALKING_TO_DESK
		and _character(_programmer).activity == OfficeCharacter.Activity.WALKING_TO_DESK, "a las 13 vuelven del almuerzo")
	_expect(_character(_seller).activity == OfficeCharacter.Activity.WALKING_OUT, "a las 13 sale el vendedor")
	# Energía −6 por hora trabajada y +4 en el almuerzo: 9, 10, 11 y 12 → −18 + 4.
	_expect(int(_programmer["energy"]) == 86, "energía a las 13: %d" % _programmer["energy"])
	_walk_until(func() -> bool: return GameClock.get_hour() == 14, 90.0, "llegar a las 14")
	_walk_until(_all_seated, 60.0, "sentados tras almorzar")
	_expect(_left.get(Staff.employee_key(_seller["id"]), 0) == 1, "el vendedor salió a almorzar")
	_expect(int(_programmer["energy"]) == 80, "energía a las 14: %d" % _programmer["energy"])


func _check_card() -> void:
	var card: EmployeeCard = _game.get_node("EmployeeCard")
	_expect(not card.is_open(), "la ficha empieza cerrada")
	var character: Employee = _character(_programmer)
	var screen: Vector2 = _game.get_canvas_transform() * (character.position + Vector2(0.0, -30.0))
	await _click_at(screen)
	_expect(card.is_open() and card.get_employee_id() == _programmer["id"], "un clic en el empleado abre su ficha")
	var text: String = card.get_text()
	for expected: String in [_programmer["name"], "Programador Junior", "Horario: lun–vie 8:00–17:00", "almuerzo 12:00–13:00",
			"Ahora: trabajando", "Energía 80", "Ánimo 70", "Estrés 20", "Habilidades: Programación"]:
		_expect(text.contains(expected), "la ficha muestra «%s»: %s" % [expected, text])
	_expect(card.get_bar_value("energy") == 80.0 and card.get_bar_value("mood") == 70.0 and card.get_bar_value("stress") == 20.0,
		"barras de la ficha")
	_expect(not GameClock.is_paused, "la ficha no pausa el tiempo")
	# Se actualiza sola con la hora.
	GameClock.advance(GameConstants.SECONDS_PER_GAME_HOUR)
	_expect(card.get_bar_value("energy") == 74.0, "la barra baja con la hora: %.0f" % card.get_bar_value("energy"))
	var panel: StaffPanel = _game.get_node("StaffPanel")
	panel.set_open(true)
	await get_tree().process_frame
	await _click_at(panel.get_card_button(_seller["id"]).get_global_rect().get_center())
	_expect(card.get_employee_id() == _seller["id"] and card.get_text().contains("9:00–18:00"),
		"Ficha desde Personal: %s" % card.get_text())
	panel.set_open(false)
	card.close()
	await _click_at(_game.get_canvas_transform() * _game.get_node("OfficeGrid").grid_to_world(Vector2(4.0, 6.0)))
	_expect(not card.is_open(), "un clic en el piso no abre la ficha")


# El CEO se va cuando lo mandan (15), el programador a las 17 y el vendedor a las 18;
# al salir el último, el tiempo salta al martes a las 8.
func _check_end_of_day() -> void:
	# El CEO se va a las 15: los empleados siguen, así que no hay salto.
	GameClock.advance(maxi(0, 15 - GameClock.get_hour()) * GameConstants.SECONDS_PER_GAME_HOUR)
	Staff.set_ceo_at_work(false)
	_walk_until(func() -> bool: return _left.get("ceo", 0) == 2, 30.0, "el CEO sale")
	_expect(GameClock.get_weekday() == 0 and GameClock.get_hour() < 17 and _game.ceo.activity == OfficeCharacter.Activity.AWAY,
		"con empleados no hay salto: %d:%02d" % [GameClock.get_hour(), GameClock.get_minute()])
	GameClock.advance((16 - GameClock.get_hour()) * GameConstants.SECONDS_PER_GAME_HOUR)
	_walk_until(func() -> bool: return GameClock.get_hour() == 17, 10.0, "llegar a las 17")
	var programmer: Employee = _character(_programmer)
	_expect(programmer.activity == OfficeCharacter.Activity.WALKING_OUT, "a las 17 el programador se va")
	var path: Array[Vector2i] = programmer.get_path_cells()
	_expect(path.size() >= 2 and not OfficeState.lot_rect.has_point(path[-1]) and path[-2] == OfficeState.entrance,
		"sale por la entrada: %s" % [path])
	_expect(_character(_seller).activity == OfficeCharacter.Activity.SEATED, "el vendedor sigue hasta las 18")
	_expect(int(_programmer["energy"]) == 62, "energía al terminar: %d" % _programmer["energy"])
	var programmer_key: String = programmer.person_key
	_walk_until(func() -> bool: return _left.get(programmer_key, 0) == 2, 30.0, "el programador sale")
	_expect(GameClock.get_hour() == 17, "con el vendedor en la oficina no hay salto")
	_walk_until(func() -> bool: return GameClock.get_weekday() == 1, 60.0, "el vendedor sale y salta la noche")
	_expect(GameClock.get_hour() == 8 and GameClock.get_minute() == 0, "salto hasta el martes a las 8: %d:%02d" % [
		GameClock.get_hour(), GameClock.get_minute()])
	_expect(_game.ceo.activity == OfficeCharacter.Activity.WALKING_TO_DESK and programmer.activity == OfficeCharacter.Activity.WALKING_TO_DESK,
		"a las 8 llegan el CEO y el programador")
	_expect(_character(_seller).activity == OfficeCharacter.Activity.AWAY, "el vendedor llega a las 9")
	_expect(_game.describe_employee_activity(_seller["id"]) == "fuera de su horario", "estado del vendedor")


func _check_energy_overnight() -> void:
	_expect(int(_programmer["energy"]) == 100 and int(_seller["energy"]) == 100, "la energía se recupera de noche: %d, %d" % [
		_programmer["energy"], _seller["energy"]])
	# El ánimo se mueve 3 por día hacia su meta; el estrés queda en 20.
	_expect(absi(int(_programmer["mood"]) - 70) == 3 and int(_programmer["stress"]) == 20, "ánimo y estrés del día: %d, %d" % [
		_programmer["mood"], _programmer["stress"]])
	_walk_until(_all_seated, 120.0, "todos sentados el martes")


func _check_save() -> void:
	var before_staff: String = JSON.stringify(Staff.export_state())
	var cells: Dictionary[int, Vector2i] = {}
	for employee_id: int in _game.employees:
		cells[employee_id] = _game.employees[employee_id].get_cell()
	_expect(SaveManager.save_game("slot_2"), "guardar")
	_game.queue_free()
	await get_tree().process_frame
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_2"), "cargar")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	GameClock.stop()
	_expect(JSON.stringify(Staff.export_state()) == before_staff, "el personal vuelve igual")
	_expect(_game.employees.size() == 2, "vuelven los dos empleados")
	for employee_id: int in cells:
		var character: Employee = _game.employees.get(employee_id)
		_expect(character != null and character.activity == OfficeCharacter.Activity.SEATED and character.get_cell() == cells[employee_id],
			"el empleado %d vuelve sentado en su silla" % employee_id)
	# Partida vieja sin datos de jornada: toma los de su cargo.
	var old: Dictionary = Staff.export_state()
	for saved: Dictionary in old["employees"]:
		for key: String in ["schedule", "energy", "mood", "stress"]:
			saved.erase(key)
	Staff.import_state(old)
	_expect(Staff.employees[0]["schedule"] == StaffCatalog.get_role_schedule(Staff.employees[0]["role"]) and int(Staff.employees[0]["energy"]) == 100,
		"empleado viejo con horario de su cargo y energía llena")
	_game.queue_free()
	await get_tree().process_frame


func _click_at(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	await _push(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _push(event)


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame
