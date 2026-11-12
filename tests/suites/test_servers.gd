# Prueba del hito 40: Sala de servidores.
# Criterio: sin aire acondicionado la sala no funciona; cada rack cobra su mantenimiento
# el día 1; la capacidad cuenta los racks de la sala.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=servers
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261140
## La sala ocupa x 3 a 5, y 0 a 1, junto a la Oficina Ejecutiva, con puerta al sur en x 4.
const ROOM_CELL := Vector2i(4, 0)
const AIR_CELL := Vector2i(3, 0)
const RACK_CELLS: Array[Vector2i] = [Vector2i(5, 0), Vector2i(5, 1)]
## Un rack fuera de la sala: cobra mantenimiento pero no da capacidad.
const OUTSIDE_RACK := Vector2i(5, 5)

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_room()
	_check_maintenance()
	_check_accountant()
	_check_save()
	await _check_ui()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva en Pequeña empresa con dinero de sobra, objetivos cumplidos y las paredes
# de la sala (sin marcarla).
func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Company.stage = 2
	Economy.earn(100000, "Prueba")
	var walls: Array[Dictionary] = []
	for x: int in [3, 5]:
		walls.append({"edge": Vector3i(x, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL})
	walls.append({"edge": Vector3i(4, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.DOOR})
	_expect(_builder.apply(walls)["ok"], "paredes de la sala")


func _server_room() -> Dictionary:
	var index: int = OfficeState.get_room_index_at(ROOM_CELL)
	return {} if index < 0 else OfficeState.rooms[index]


func _check_catalog() -> void:
	_expect(FurnitureCatalog.get_price("server_rack") == 3000 and FurnitureCatalog.is_server_rack("server_rack"), "rack de $3,000")
	_expect(FurnitureCatalog.get_monthly_cost("server_rack") == 100, "cada rack cuesta $100 al mes")
	_expect(FurnitureCatalog.get_price("air_conditioner") == 800 and FurnitureCatalog.get_monthly_cost("air_conditioner") == 0,
		"aire acondicionado de $800 sin costo mensual")
	_expect(FurnitureCatalog.get_ids().has("server_rack") and FurnitureCatalog.get_ids().has("air_conditioner"), "se compran en el modo construcción")


func _check_room() -> void:
	_new_game()
	_expect(_builder.mark_room(OfficeState.SERVER_ROOM, ROOM_CELL)["ok"], "marcar la Sala de servidores")
	_expect(OfficeState.get_server_room().is_empty() and OfficeState.get_server_capacity() == 0, "vacía no funciona")
	_expect(_builder.place("server_rack", RACK_CELLS[0], 2)["ok"], "colocar un rack")
	var status: Dictionary = _builder.room_status(_server_room())
	_expect(not status["ok"] and status["message"].contains("aire acondicionado"), "sin aire acondicionado no funciona: %s" % status["message"])
	_expect(OfficeState.get_server_capacity() == 0, "y no da capacidad")
	_expect(_builder.place("air_conditioner", AIR_CELL, 2)["ok"], "colocar el aire acondicionado")
	status = _builder.room_status(_server_room())
	_expect(status["ok"] and status["message"].contains("funciona. 1 rack."), "con rack y aire funciona: %s" % status["message"])
	_expect(OfficeState.get_server_capacity() == 1, "capacidad 1")
	_expect(_builder.place("server_rack", RACK_CELLS[1], 0)["ok"], "segundo rack")
	_expect(OfficeState.get_server_capacity() == 2 and _builder.room_status(_server_room())["message"].contains("2 racks"), "capacidad 2")
	_expect(_builder.place("server_rack", OUTSIDE_RACK, 0)["ok"], "un rack fuera de la sala")
	_expect(OfficeState.get_server_capacity() == 2, "el rack de afuera no da capacidad")
	_expect(OfficeState.get_furniture_monthly_cost() == 300, "pero cobra: %d" % OfficeState.get_furniture_monthly_cost())
	_expect(_builder.sell_furniture_at(AIR_CELL)["ok"], "vender el aire acondicionado")
	_expect(OfficeState.get_server_room().is_empty() and OfficeState.get_server_capacity() == 0, "sin aire la sala deja de funcionar")


# Racks y su mantenimiento el día 1 del mes siguiente, aparte del local.
func _build_working_room() -> void:
	_builder.mark_room(OfficeState.SERVER_ROOM, ROOM_CELL)
	_builder.place("air_conditioner", AIR_CELL, 2)
	for cell: Vector2i in RACK_CELLS:
		_builder.place("server_rack", cell, 0)
	_builder.place("server_rack", OUTSIDE_RACK, 0)


func _next_first() -> void:
	while GameClock.get_day() != 1 or GameClock.get_month() == 1:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)


func _check_maintenance() -> void:
	_new_game()
	_build_working_room()
	_expect(Economy.get_monthly_server_cost() == 300, "3 racks: $300 al mes")
	_next_first()
	var totals: Dictionary[String, int] = Economy.get_month_totals(GameClock.get_month())
	_expect(totals.get(Economy.CONCEPT_SERVERS, 0) == -300, "el día 1 cobra los racks: %s" % [totals])
	_expect(totals.get(Economy.CONCEPT_MAINTENANCE, 0) == -Economy.get_monthly_maintenance(), "el local se cobra aparte")
	# Sin racks no se cobra nada ni aparece el concepto.
	_new_game()
	_next_first()
	_expect(not Economy.get_month_totals(GameClock.get_month()).has(Economy.CONCEPT_SERVERS), "sin racks no hay cobro")


func _check_accountant() -> void:
	_new_game()
	_build_working_room()
	# El contador necesita su puesto en un Área de trabajo.
	_expect(_builder.mark_room(Workstations.WORK_AREA, Vector2i(3, 4))["ok"], "Área de trabajo")
	_builder.place("simple_desk", Vector2i(1, 5), 2)
	_builder.install_computer("basic_computer", Vector2i(1, 5))
	_builder.place("basic_chair", Vector2i(1, 6), 0)
	var accountant: Dictionary = Staff.hire_directly("accountant", "senior")
	_expect(not accountant.is_empty() and Staff.has_accountant(), "con contador")
	_expect(Economy.get_monthly_server_cost() == 270, "el contador descuenta 10 %%: %d" % Economy.get_monthly_server_cost())


func _check_save() -> void:
	_new_game()
	_build_working_room()
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(OfficeState.get_server_capacity() == 0 and Economy.get_monthly_server_cost() == 0, "partida nueva sin racks")
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(OfficeState.get_server_capacity() == 2 and Economy.get_monthly_server_cost() == 300, "los racks se guardan")


func _check_ui() -> void:
	_new_game()
	_build_working_room()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var panel: CompanyPanel = game.get_node("CompanyPanel")
	panel.set_open(true)
	await get_tree().process_frame
	var text: String = panel.get_text()
	_expect(text.contains("Servidores") and text.contains("2 racks") and text.contains(MoneyFormat.format(300)), "Empresa muestra los servidores: %s" % text)
	_builder.sell_furniture_at(AIR_CELL)
	await get_tree().process_frame
	_expect(panel.get_text().contains("no funciona"), "y avisa si la sala no funciona")
	var build_panel: Node = game.get_node("BuildPanel")
	var names: Array[String] = []
	for button: Node in build_panel.find_children("*", "Button", true, false):
		names.append((button as Button).text)
	_expect(names.has("Rack $3000") and names.has("Aire $800"),
		"botones Rack y Aire en construcción: %s" % [names])
	panel.set_open(false)
	game.queue_free()
	await get_tree().process_frame
