# Corporación y bolsa: 4 ejecutivos y 3 productos activos llevan a Corporación; con valor
# > $5,000,000 se sale a bolsa y la partida sigue.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=ipo
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261148
## Sala de servidores como en test_launch: x 3 a 5, y 0 a 1, puerta al sur en x 4.
const ROOM_CELL := Vector2i(4, 0)
const AIR_CELL := Vector2i(3, 0)
const RACK_CELLS: Array[Vector2i] = [Vector2i(5, 0), Vector2i(5, 1), Vector2i(3, 0)]
const FAKE_ID: int = 9000

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_data()
	_check_corporation()
	_check_ipo()
	_check_free_mode()
	_check_save()
	await _check_ui()
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
	Products.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(200000, "Prueba")
	Projects.offers.clear()


# Sala de servidores con 3 racks y 3 productos pequeños lanzados.
func _three_products() -> void:
	Company.stage = 2
	var walls: Array[Dictionary] = []
	for x: int in [3, 5]:
		walls.append({"edge": Vector3i(x, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL})
	walls.append({"edge": Vector3i(4, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.DOOR})
	_builder.apply(walls)
	_builder.mark_room(OfficeState.SERVER_ROOM, ROOM_CELL)
	_expect(_builder.place("air_conditioner", AIR_CELL, 2)["ok"], "aire acondicionado")
	for cell: Vector2i in RACK_CELLS:
		_expect(_builder.place("server_rack", cell, 0)["ok"], "rack en %s" % cell)
	_expect(OfficeState.get_server_capacity() == 3, "sala con 3 racks")
	for index: int in range(3):
		var product: Dictionary = Products.get_product(Products.start("mobile_app", "small")["id"])
		for phase: String in ContractCatalog.PHASES:
			product["progress"][phase] = float(product["points"][phase])
		product["design_done"] = float(product["points"]["design"])
		product["design_skill"] = float(product["points"]["design"])
		var result: Dictionary = Products.launch(product["id"])
		_expect(result["ok"], "lanzar el producto %d: %s" % [index + 1, result["message"]])


# Ejecutivos de mentira: solo cuentan para el requisito (no pasa el tiempo con ellos).
func _add_fake_executive(index: int) -> void:
	Staff.employees.append({"id": FAKE_ID + index, "name": "Ejecutivo %d" % index, "role": StaffCatalog.get_executive_role(),
		"level": "", "salary": 0, "department": "", "skills": {"leadership": 50}})


func _remove_fake_executives() -> void:
	Staff.employees.assign(Staff.employees.filter(func(employee: Dictionary) -> bool: return int(employee["id"]) < FAKE_ID))


# Lleva el saldo a que el valor de la empresa quede en target.
func _set_value(target: int) -> void:
	var difference: int = target - Company.get_value()
	if difference > 0:
		Economy.earn(difference, "Prueba")
	elif difference < 0:
		Economy.charge(-difference, "Prueba")


func _check_data() -> void:
	var requirements: Dictionary = Company.get_stage_info(4).get("requirements", {})
	_expect(Company.get_stage_name(4) == "Corporación" and int(requirements.get("executives", 0)) == 4
		and int(requirements.get("active_products", 0)) == 3, "Corporación pide 4 ejecutivos y 3 productos activos: %s" % [requirements])
	_expect(Company.get_ipo_stage() == 4 and Company.get_ipo_value() == 5000000, "bolsa: Corporación y $5,000,000")
	var unlocks: Array = Company.get_stage_info(4).get("unlocks", [])
	_expect(unlocks.any(func(text: Variant) -> bool: return String(text).contains("bolsa"))
		and not unlocks.any(func(text: Variant) -> bool: return String(text).contains("próximamente")), "Corporación desbloquea la bolsa: %s" % [unlocks])


func _check_corporation() -> void:
	_new_game()
	_three_products()
	Company.stage = 3
	_expect(Products.get_active_count() == 3, "3 productos activos")
	for index: int in range(3):
		_add_fake_executive(index)
	Company.check_stage()
	_expect(Company.stage == 3, "con 3 ejecutivos sigue en Mediana empresa")
	_add_fake_executive(3)
	_notices.clear()
	Company.check_stage()
	_expect(Company.stage == 4, "con 4 ejecutivos y 3 productos activos llega a Corporación")
	_expect(_notices.any(func(text: String) -> bool: return text.contains("Corporación")), "y avisa: %s" % [_notices])
	_remove_fake_executives()
	Company.check_stage()
	_expect(Company.stage == 4, "la etapa no baja")


func _check_ipo() -> void:
	_new_game()
	Company.stage = 3
	_set_value(6000000)
	var problem: String = Company.ipo_problem()
	_expect(problem.contains("Corporación"), "antes de Corporación no: %s" % problem)
	_expect(not Company.go_public()["ok"] and not Company.is_public(), "go_public lo rechaza")
	Company.stage = 4
	_set_value(5000000)
	problem = Company.ipo_problem()
	_expect(problem.contains("pasar de $5,000,000"), "con $5,000,000 justos no alcanza: %s" % problem)
	_notices.clear()
	_set_value(5000001)
	_expect(Company.ipo_problem().is_empty(), "con más de $5,000,000 se puede")
	_expect(_notices.any(func(text: String) -> bool: return text.contains("puede salir a bolsa")), "avisa que se puede: %s" % [_notices])
	_notices.clear()
	Economy.earn(10, "Prueba")
	_expect(not _notices.any(func(text: String) -> bool: return text.contains("puede salir a bolsa")), "avisa una sola vez")
	var received: Array[Dictionary] = []
	var listener: Callable = func(stats: Dictionary) -> void: received.append(stats)
	EventBus.went_public.connect(listener)
	var balance: int = Economy.balance
	var day: int = GameClock.get_day_count()
	var result: Dictionary = Company.go_public()
	EventBus.went_public.disconnect(listener)
	_expect(result["ok"] and Company.is_public() and Company.public_day == day, "sale a bolsa: %s" % result["message"])
	_expect(Economy.balance == balance, "no da dinero")
	_expect(received.size() == 1, "avisa con went_public")
	if received.size() == 1:
		var stats: Dictionary = received[0]
		_expect(int(stats["days"]) == day + 1 and int(stats["hired"]) == Staff.hired_count and int(stats["delivered"]) == Projects.delivered_count
			and int(stats["launched"]) == Products.launched_count and int(stats["value"]) == Company.get_value()
			and int(stats["employees"]) == Staff.employees.size() and stats.has("best_reputation"), "estadísticas de cierre: %s" % [stats])
	result = Company.go_public()
	_expect(not result["ok"] and String(result["message"]).contains("ya cotiza"), "no se sale dos veces: %s" % result["message"])


func _check_free_mode() -> void:
	_new_game()
	Company.stage = 4
	_set_value(6000000)
	Company.go_public()
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY * 3)
	_expect(Company.is_public() and not Projects.offers.is_empty(), "modo libre: el juego sigue y llegan ofertas")
	_expect(Company.stage == 4, "sigue en Corporación")


func _check_save() -> void:
	_new_game()
	Company.stage = 4
	_set_value(6000000)
	Company.go_public()
	var day: int = Company.public_day
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(not Company.is_public(), "partida nueva: no cotiza")
	_expect(SaveManager.load_game("slot_5") and Company.is_public() and Company.public_day == day, "se guarda que cotiza")
	# Partida vieja: sin la clave.
	var state: Dictionary = Company.export_state()
	state.erase("public_day")
	state.erase("ipo_announced")
	Company.import_state(state)
	_expect(not Company.is_public(), "una partida vieja no cotiza")


func _check_ui() -> void:
	_new_game()
	Company.stage = 3
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var panel: CompanyPanel = game.get_node("CompanyPanel")
	panel.set_open(true)
	_expect(panel.get_text().contains("Salir a bolsa") and panel.get_text().contains("Valor de más de $5,000,000"), "Empresa muestra la meta")
	var button: Button = panel.get_ipo_button()
	_expect(button != null and button.disabled and button.tooltip_text.contains("Corporación"), "el botón está deshabilitado")
	Company.stage = 4
	_set_value(6000000)
	button = panel.get_ipo_button()
	_expect(button != null and not button.disabled, "cumplida la meta se habilita")
	button.pressed.emit()
	_expect(panel.get_confirm_ipo_button() != null and panel.get_text().contains("no se deshace") and not Company.is_public(),
		"pide confirmar antes")
	GameClock.set_paused(false)
	panel.get_confirm_ipo_button().pressed.emit()
	var screen: IpoScreen = game.get_node("IpoScreen")
	_expect(Company.is_public() and screen.is_open(), "confirmar sale a bolsa y abre el cierre")
	_expect(screen.get_text().contains("Días jugados") and screen.get_text().contains("Productos lanzados")
		and screen.get_text().contains("Valor de la empresa"), "el cierre muestra las estadísticas: %s" % screen.get_text())
	_expect(GameClock.is_paused and not panel.is_open(), "pausa y cierra los menús")
	screen.get_continue_button().pressed.emit()
	_expect(not screen.is_open() and not GameClock.is_paused, "«Seguir jugando» vuelve a la partida como estaba")
	panel.set_open(true)
	_expect(panel.get_text().contains("Cotiza en bolsa desde el día") and panel.get_ipo_button() == null, "Empresa dice que cotiza")
	_expect(screen.get_menu_button().text == "Volver al menú", "y se puede volver al menú")
	game.queue_free()
	await get_tree().process_frame
