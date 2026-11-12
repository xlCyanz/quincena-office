# Prueba del hito 37: contador y limpieza.
# Criterio: con contador el mantenimiento baja 10 % y un préstamo nuevo cuesta 1 punto
# menos; una habitación sucia baja el ánimo y la limpieza la deja en 0.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=administration
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261115
const ACCOUNTANT: String = "accountant"
const CLEANER: String = "cleaner"
## Área de trabajo: todo el local menos la Oficina Ejecutiva y el Cuarto de limpieza.
const WORK_CELL := Vector2i(3, 3)
const DESK_CELL := Vector2i(4, 4)
const CHAIR_CELL := Vector2i(4, 5)
## Cuarto de limpieza en la esquina noreste: (5, 0) y (5, 1).
const CLOSET_CELL := Vector2i(5, 0)
const CLEANING_CELL := Vector2i(5, 1)

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_catalog()
	_check_discounts()
	_check_warnings()
	_check_dirt()
	_check_mood()
	_check_cleaner()
	_check_save()
	await _check_ui()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva en Startup, con dinero de sobra y los objetivos cumplidos, un Área de
# trabajo con un puesto y, con cleaning_room, el Cuarto de limpieza con su armario.
func _new_game(cleaning_room: bool = false, stage: int = 1) -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Company.stage = stage
	Economy.earn(100000, "Prueba")
	Projects.offers.clear()
	_build_offices(cleaning_room)


func _build_offices(cleaning_room: bool) -> void:
	var builder := Builder.new()
	var result: Dictionary
	if cleaning_room:
		var x: int = GridEdge.AXIS_X
		var y: int = GridEdge.AXIS_Y
		result = builder.apply([
			{"edge": Vector3i(4, 0, x), "kind": ConstructionCatalog.WALL},
			{"edge": Vector3i(4, 1, x), "kind": ConstructionCatalog.DOOR},
			{"edge": Vector3i(5, 1, y), "kind": ConstructionCatalog.WALL},
		] as Array[Dictionary])
		_expect(result["ok"], "paredes del Cuarto de limpieza: %s" % result.get("message", ""))
		result = builder.mark_room(Workstations.CLEANING_ROOM, CLEANING_CELL)
		_expect(result["ok"], "marcar el Cuarto de limpieza: %s" % result.get("message", ""))
		result = builder.place("cleaning_closet", CLOSET_CELL, 2)
		_expect(result["ok"], "armario de limpieza: %s" % result.get("message", ""))
	result = builder.mark_room(Workstations.WORK_AREA, WORK_CELL)
	_expect(result["ok"], "marcar el Área de trabajo: %s" % result.get("message", ""))
	result = builder.place("simple_desk", DESK_CELL, 2)
	_expect(result["ok"], "escritorio: %s" % result.get("message", ""))
	result = builder.install_computer("basic_computer", DESK_CELL)
	_expect(result["ok"], "computadora: %s" % result.get("message", ""))
	result = builder.place("basic_chair", CHAIR_CELL, 0)
	_expect(result["ok"], "silla: %s" % result.get("message", ""))


func _hire(role: String, level: String = "intern") -> Dictionary:
	var opened: Dictionary = Staff.open_vacancy(role, level, StaffCatalog.get_salary(role, level), true)
	_expect(opened["ok"], "publicar %s: %s" % [role, opened["message"]])
	if not opened["ok"]:
		return {}
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	var candidates: Array = Staff.get_vacancy(opened["id"])["candidates"]
	if candidates.is_empty():
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
		candidates = Staff.get_vacancy(opened["id"])["candidates"]
	var candidate: Dictionary = candidates[0]
	var result: Dictionary = Staff.make_offer(candidate["id"], candidate["asked_salary"])
	var employee: Dictionary = Staff.get_employee(candidate["id"])
	_expect(not employee.is_empty(), "contratado: %s (%s)" % [role, result["message"]])
	return employee


# Avanza hasta las 0:00 de un lunes.
func _to_monday() -> void:
	var hours: int = posmod(-GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	while GameClock.get_weekday() != 0:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)


# Avanza hasta las 0:00 del día del mes day.
func _to_day(day: int) -> void:
	var hours: int = posmod(-GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	if hours > 0:
		GameClock.fast_forward_hours(hours)
	while GameClock.get_day() != day:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)


func _work_room() -> Dictionary:
	return OfficeState.rooms[OfficeState.get_room_index_at(CHAIR_CELL)]


func _check_catalog() -> void:
	_expect(StaffCatalog.get_role_name(ACCOUNTANT) == "Contador" and StaffCatalog.get_salary(ACCOUNTANT, "intern") == 1300
		and not StaffCatalog.has_levels(ACCOUNTANT), "Contador $1,300 sin niveles")
	_expect(StaffCatalog.get_role_min_stage(ACCOUNTANT) == 1 and StaffCatalog.get_workplace(ACCOUNTANT) == Workstations.WORK_AREA,
		"el contador, desde Startup en un Área de trabajo")
	_expect(StaffCatalog.get_role_name(CLEANER) == "Personal de limpieza" and StaffCatalog.get_salary(CLEANER, "senior") == 500
		and StaffCatalog.get_role_min_stage(CLEANER) == 0, "Personal de limpieza $500 desde el inicio")
	_expect(StaffCatalog.get_workplace(CLEANER) == Workstations.CLEANING_ROOM, "trabaja desde el Cuarto de limpieza")
	_expect(StaffCatalog.get_role_department(ACCOUNTANT) == "administration" and StaffCatalog.get_role_department(CLEANER) == "administration",
		"los dos son de Administración")
	_expect(FurnitureCatalog.get_item("trash_can")["name"] == "Zafacón" and bool(FurnitureCatalog.get_item("trash_can")["trash_can"]), "zafacón")
	_expect(bool(FurnitureCatalog.get_item("cleaning_closet")["is_closet"]), "armario de limpieza")
	_expect(RoomCatalog.get_display_name("cleaning_room") == "Cuarto de limpieza", "Cuarto de limpieza")


func _check_discounts() -> void:
	_new_game()
	var base: int = Economy.get_maintenance(OfficeState.lot.get_area())
	_expect(Economy.get_monthly_maintenance() == base, "sin contador el mantenimiento es el normal: %d" % base)
	var rate: float = Bank.get_monthly_rate()
	_expect(is_equal_approx(rate, 0.045), "sin contador la tasa es la de C")
	Company.stage = 0
	_expect(not Staff.role_problem(ACCOUNTANT).is_empty(), "en Emprendimiento no se contrata contador")
	Company.stage = 1
	_hire(ACCOUNTANT)
	_expect(Staff.has_accountant(), "hay contador")
	_expect(Economy.get_monthly_maintenance() == roundi(base * 0.9), "con contador el mantenimiento baja 10 %%: %d" % Economy.get_monthly_maintenance())
	_expect(is_equal_approx(Bank.get_monthly_rate(), 0.035), "y la tasa baja 1 punto: %f" % Bank.get_monthly_rate())
	var result: Dictionary = Bank.request_loan(5000, 6)
	_expect(result["ok"] and is_equal_approx(float(Bank.loans[0]["rate"]), 0.035), "el préstamo nuevo sale al 3.5 %%")
	# El día 1 se cobra el mantenimiento con descuento.
	_to_day(30)
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	var charged: int = -Economy.get_month_totals(GameClock.get_month()).get(Economy.CONCEPT_MAINTENANCE, 0)
	_expect(charged == roundi(base * 0.9), "el día 1 cobra %d de mantenimiento (de %d)" % [charged, base])
	# Desde Mediana empresa el efecto se multiplica por el rendimiento de Administración.
	Company.stage = 3
	var factor: float = Staff.get_department_factor("administration")
	_expect(is_equal_approx(Staff.get_maintenance_discount(), 0.1 * factor), "descuento por el factor de Administración (%.2f)" % factor)


func _check_warnings() -> void:
	_new_game()
	_hire(ACCOUNTANT)
	Economy.charge(Economy.balance - 100, "Prueba")
	_to_day(11)
	_notices.clear()
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(GameClock.get_day() == 12, "día 12")
	var warned: bool = _notices.any(func(text: String) -> bool: return text.begins_with("El contador avisa: el día 15") and text.contains("nómina"))
	_expect(warned, "tres días antes de la nómina avisa que no alcanza: %s" % [_notices])
	_notices.clear()
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(not _notices.any(func(text: String) -> bool: return text.begins_with("El contador")), "solo avisa una vez")
	# El día 28 avisa por la nómina del 30 y lo del día 1.
	Economy.charge(Economy.balance - 100, "Prueba")
	_to_day(27)
	_notices.clear()
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	warned = _notices.any(func(text: String) -> bool: return text.begins_with("El contador avisa: el día 1 ") and text.contains("mantenimiento"))
	_expect(warned, "el 28 avisa por el día 1: %s" % [_notices])
	# Con saldo suficiente no avisa.
	Economy.earn(100000, "Prueba")
	_to_day(11)
	_notices.clear()
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(not _notices.any(func(text: String) -> bool: return text.begins_with("El contador")), "con saldo no avisa")
	# Sin contador nadie avisa.
	_new_game()
	_hire("programmer")
	Economy.charge(Economy.balance - 100, "Prueba")
	_to_day(11)
	_notices.clear()
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(not _notices.any(func(text: String) -> bool: return text.begins_with("El contador")), "sin contador no hay aviso")


func _check_dirt() -> void:
	_new_game()
	_hire(ACCOUNTANT)
	_to_monday()
	var index: int = OfficeState.get_room_index_at(CHAIR_CELL)
	OfficeState.rooms[index]["dirt"] = 0.0
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	var hours: int = 0
	var key: String = Staff.employee_key(Staff.employees[0]["id"])
	for hour: int in range(GameConstants.HOURS_PER_DAY):
		if Staff.is_expected(key, 0, hour):
			hours += 1
	_expect(hours == 8 and is_equal_approx(OfficeState.get_room_dirt(_work_room()), 8.0),
		"un día de 8 h ensucia 8: %.1f" % OfficeState.get_room_dirt(_work_room()))
	var office: Dictionary = OfficeState.rooms[OfficeState.get_room_index_at(Vector2i(1, 1))]
	_expect(OfficeState.get_room_dirt(office) > 0.0, "el CEO ensucia su oficina")
	# Con zafacón, la mitad.
	var result: Dictionary = Builder.new().place("trash_can", Vector2i(5, 5), 0)
	_expect(result["ok"], "zafacón: %s" % result.get("message", ""))
	_expect(OfficeState.has_trash_can(_work_room()), "el Área tiene zafacón")
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(is_equal_approx(OfficeState.get_room_dirt(_work_room()), 12.0), "con zafacón el martes suma 4: %.1f" % OfficeState.get_room_dirt(_work_room()))
	# Nunca pasa del máximo.
	OfficeState.add_dirt(index, 500.0)
	_expect(is_equal_approx(OfficeState.get_room_dirt(_work_room()), 100.0), "tope de 100")
	# Cambiar paredes no la limpia.
	result = Builder.new().apply([{"edge": Vector3i(4, 6, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL}] as Array[Dictionary])
	_expect(result["ok"] and is_equal_approx(OfficeState.get_room_dirt(_work_room()), 100.0), "la suciedad sigue a la habitación al cambiar paredes")


func _check_mood() -> void:
	_new_game()
	var worker: Dictionary = _hire(ACCOUNTANT)
	var clean_target: int = Staff.get_mood_target(worker)
	var index: int = OfficeState.get_room_index_at(CHAIR_CELL)
	OfficeState.rooms[index]["dirt"] = 49.0
	_expect(Staff.get_mood_target(worker) == clean_target and not Staff.works_in_dirty_room(Staff.employee_key(worker["id"])), "con 49 no baja")
	OfficeState.rooms[index]["dirt"] = 50.0
	_expect(Staff.get_mood_target(worker) == clean_target - 10, "con 50 la meta baja 10: %d → %d" % [clean_target, Staff.get_mood_target(worker)])
	# Unos días en una habitación sucia (sin limpieza) le bajan el ánimo.
	worker["mood"] = clean_target
	_to_day(GameClock.get_day() % GameConstants.DAYS_PER_MONTH + 1)
	for day: int in range(3):
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	_expect(int(worker["mood"]) < clean_target, "el ánimo baja: %d" % int(worker["mood"]))
	# Aviso al ensuciarse.
	OfficeState.rooms[index]["dirt"] = 49.5
	_notices.clear()
	_to_monday()
	GameClock.fast_forward_hours(10)
	_expect(_notices.any(func(text: String) -> bool: return text == "Área de trabajo está sucia: baja el ánimo de quienes trabajan ahí."),
		"avisa cuando se ensucia: %s" % [_notices])


func _check_cleaner() -> void:
	_new_game(false, 0)
	_expect(Staff.get_station_problem(CLEANER) == Staff.NO_CLOSET_MESSAGE, "sin Cuarto de limpieza no hay puesto")
	_new_game(true, 0)
	_expect(Staff.get_station_problem(CLEANER).is_empty(), "con armario hay puesto")
	var cleaner: Dictionary = _hire(CLEANER)
	_expect(Staff.has_working_station(cleaner), "su puesto es el armario")
	_expect(OfficeState.find_furniture_assigned_to(Staff.employee_key(cleaner["id"]))["cell"] == CLOSET_CELL, "asignado al armario")
	_expect(Staff.get_station_problem(CLEANER) == Staff.NO_CLOSET_MESSAGE, "un armario por persona")
	# No se vende el armario ocupado.
	_expect(not Builder.new().sell_furniture_at(CLOSET_CELL)["ok"], "el armario ocupado no se vende")
	var worker: Dictionary = _hire("programmer", "junior")
	_to_monday()
	var index: int = OfficeState.get_room_index_at(CHAIR_CELL)
	# Sin el CEO, que ensucia su oficina: solo el Área de trabajo está sucia.
	Staff.set_ceo_at_work(false)
	for room: Dictionary in OfficeState.rooms:
		room["dirt"] = 0.0
	OfficeState.rooms[index]["dirt"] = 60.0
	GameClock.fast_forward_hours(8)
	_expect(is_equal_approx(OfficeState.get_room_dirt(_work_room()), 60.0), "antes de su turno sigue sucia")
	GameClock.fast_forward_hours(3)
	_expect(OfficeState.get_room_dirt(_work_room()) == 0.0, "en su turno la limpieza la deja en 0: %.1f" % OfficeState.get_room_dirt(_work_room()))
	_expect(not Staff.works_in_dirty_room(Staff.employee_key(worker["id"])), "ya no está sucia")
	# Limpia siempre la más sucia.
	var office: int = OfficeState.get_room_index_at(Vector2i(1, 1))
	OfficeState.rooms[office]["dirt"] = 40.0
	OfficeState.rooms[index]["dirt"] = 10.0
	_expect(OfficeState.get_dirtiest_room() == office, "la Oficina Ejecutiva es la más sucia")
	_expect(Staff.get_cleaning_room(cleaner) == office, "y ahí va a limpiar")
	GameClock.fast_forward_hours(1)
	_expect(OfficeState.get_room_dirt(OfficeState.rooms[office]) < 40.0 and OfficeState.get_room_dirt(_work_room()) >= 10.0,
		"limpió la Oficina primero")


func _check_save() -> void:
	_new_game()
	var index: int = OfficeState.get_room_index_at(CHAIR_CELL)
	OfficeState.rooms[index]["dirt"] = 37.5
	var state: Dictionary = JSON.parse_string(JSON.stringify(OfficeState.export_state()))
	OfficeState.new_game()
	OfficeState.import_state(state)
	_expect(is_equal_approx(OfficeState.get_room_dirt(_work_room()), 37.5), "la suciedad se guarda")
	for room: Dictionary in state["rooms"]:
		room.erase("dirt")
	OfficeState.import_state(state)
	_expect(OfficeState.get_room_dirt(_work_room()) == 0.0, "una partida vieja carga con la oficina limpia")


func _check_ui() -> void:
	_new_game(true, 1)
	var cleaner: Dictionary = _hire(CLEANER)
	var worker: Dictionary = _hire(ACCOUNTANT)
	_to_monday()
	GameClock.fast_forward_hours(9)
	var index: int = OfficeState.get_room_index_at(CHAIR_CELL)
	OfficeState.rooms[index]["dirt"] = 80.0
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	EventBus.dirt_changed.emit()
	await get_tree().process_frame
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	_expect(grid.get_dirt_overlay().get_stain_count(_work_room()) > 0, "se ven manchas en el Área sucia")
	var employees: Dictionary = game.get("employees")
	var character: Employee = employees.get(int(cleaner["id"]))
	_expect(character != null and _work_room()["cells"].has(character.get_seat_cell()),
		"la persona de limpieza va al Área sucia: %s" % [character.get_seat_cell() if character != null else null])
	var card: EmployeeCard = game.get_node("EmployeeCard")
	card.open_employee(worker["id"])
	await get_tree().process_frame
	_expect(card.get_text().contains("Su lugar de trabajo está sucio"), "la ficha avisa: %s" % card.get_text())
	card.close()
	var staff_panel: StaffPanel = game.get_node("StaffPanel")
	staff_panel.set_open(true)
	await get_tree().process_frame
	var roles: OptionButton = staff_panel.get_role_option()
	var names: Array[String] = []
	for item: int in range(roles.item_count):
		names.append(roles.get_item_text(item))
	_expect(names.any(func(text: String) -> bool: return text.begins_with("Contador")) and names.any(func(text: String) -> bool: return text.begins_with("Personal de limpieza")),
		"Personal ofrece contador y limpieza: %s" % [names])
	staff_panel.set_open(false)
	var bank: BankPanel = game.get_node("BankPanel")
	bank.set_open(true)
	await get_tree().process_frame
	_expect(bank.get_credit_text().contains("con contador"), "el Banco lo dice: %s" % bank.get_credit_text())
	bank.set_open(false)
	game.queue_free()
	await get_tree().process_frame
