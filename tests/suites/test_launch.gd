# Prueba del hito 42: lanzamiento y ciclo de vida de los productos.
# Criterio: un producto pequeño de buena calidad llega cerca de $150 al día en su mejor
# momento; con errores pierde usuarios; una actualización lo reaviva; Mediana empresa pide
# uno lanzado.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=launch
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261142
## Sala de servidores como en test_servers: x 3 a 5, y 0 a 1, puerta al sur en x 4.
const ROOM_CELL := Vector2i(4, 0)
const AIR_CELL := Vector2i(3, 0)
const RACK_CELLS: Array[Vector2i] = [Vector2i(5, 0), Vector2i(5, 1)]

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()
var _notices: Array[String] = []


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_launch()
	_check_quality()
	_check_lifecycle()
	_check_production_bugs()
	_check_update()
	_check_racks_and_retire()
	_check_stage_and_value()
	_check_save()
	await _check_ui()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva en Pequeña empresa, con dinero, objetivos cumplidos y una Sala de servidores
# que funciona con un rack.
func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	Products.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Company.stage = 2
	Economy.earn(200000, "Prueba")
	var walls: Array[Dictionary] = []
	for x: int in [3, 5]:
		walls.append({"edge": Vector3i(x, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL})
	walls.append({"edge": Vector3i(4, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.DOOR})
	_builder.apply(walls)
	_builder.mark_room(OfficeState.SERVER_ROOM, ROOM_CELL)
	_builder.place("air_conditioner", AIR_CELL, 2)
	_builder.place("server_rack", RACK_CELLS[0], 0)
	_expect(OfficeState.get_server_capacity() == 1, "sala con un rack")


# Un producto terminado: diseño hecho por Junior (o el nivel dado) y esos errores ocultos.
func _finished_product(size: String = "small", bugs: int = 0, level: String = "junior") -> Dictionary:
	var product: Dictionary = Products.get_product(Products.start("mobile_app", size)["id"])
	for phase: String in ContractCatalog.PHASES:
		product["progress"][phase] = float(product["points"][phase])
	product["design_done"] = float(product["points"]["design"])
	product["design_skill"] = float(product["points"]["design"]) * ProductCatalog.get_level_value(level)
	product["bugs_hidden"] = bugs
	return product


# Lo que mira la calidad de un producto pequeño con diseño de ese nivel y esos errores.
func _quality_case(level: String, bugs: int) -> Dictionary:
	return {"design_done": 450.0, "design_skill": 450.0 * ProductCatalog.get_level_value(level), "bugs_hidden": bugs,
		"bugs_found": 0, "total_points": 1500}


func _days(count: int) -> void:
	GameClock.fast_forward_hours(count * GameConstants.HOURS_PER_DAY)


func _check_launch() -> void:
	_new_game()
	var product: Dictionary = Products.get_product(Products.start("mobile_app", "small")["id"])
	_expect(Products.launch_problem(product["id"]).contains("terminado"), "sin terminar no se lanza")
	_expect(not Products.launch(product["id"])["ok"], "launch lo rechaza")
	Products.abandon(product["id"])
	product = _finished_product("medium")
	_expect(Products.launch_problem(product["id"]).contains("3 racks"), "un mediano pide 3 racks: %s" % Products.launch_problem(product["id"]))
	Products.abandon(product["id"])
	product = _finished_product()
	_notices.clear()
	var result: Dictionary = Products.launch(product["id"])
	_expect(result["ok"] and product["state"] == Products.STATE_LAUNCHED, "lanzar: %s" % result["message"])
	_expect(_notices.size() == 1 and _notices[0].begins_with("Lanzaste"), "avisa: %s" % [_notices])
	_expect(Products.get_development_count() == 0 and Projects.get_project_count() == 0, "lanzado ya no cuenta para el tope")
	_expect(Products.get_used_racks() == 1 and Products.get_free_racks() == 0, "usa su rack")
	_expect(Products.launch_problem(_finished_product()["id"]).contains("1 rack"), "sin racks libres no se lanza otro")
	_expect(Products.launched_count == 1, "cuenta los lanzados")


func _check_quality() -> void:
	_new_game()
	var junior: Dictionary = _quality_case("junior", 0)
	var senior: Dictionary = _quality_case("senior", 0)
	var buggy: Dictionary = _quality_case("junior", 15)
	_expect(is_equal_approx(Products.get_quality(junior), 0.625), "Junior sin errores: %.3f" % Products.get_quality(junior))
	_expect(is_equal_approx(Products.get_quality(senior), 1.0), "Senior sin errores: %.3f" % Products.get_quality(senior))
	_expect(is_equal_approx(Products.get_quality(buggy), 0.125), "15 errores en 1,500 puntos quitan toda la parte de errores")
	_expect(is_equal_approx(Products.get_quality_factor(0.0), 0.5) and is_equal_approx(Products.get_quality_factor(1.0), 1.5),
		"el ingreso va de la mitad al 150 %")
	# El diseño se anota por el nivel de quien lo hace: el CEO es SemiSenior.
	var product: Dictionary = Products.get_product(Products.start("game", "small")["id"])
	Products.assign(product["id"], Projects.CEO_TEAM)
	while float(product["progress"]["design"]) < 100.0:
		GameClock.fast_forward_hours(1)
	_expect(is_equal_approx(float(product["design_skill"]) / float(product["design_done"]), ProductCatalog.get_level_value("semi_senior")),
		"el diseño del CEO vale como SemiSenior")


func _check_lifecycle() -> void:
	_new_game()
	var product: Dictionary = _finished_product()
	Products.launch(product["id"])
	var first: int = Products.get_users(product)
	_days(1)
	_expect(Products.get_users(product) > first and product["phase"] == Products.PHASE_GROWTH, "crece")
	_days(29)
	_expect(product["phase"] == Products.PHASE_PLATEAU and is_equal_approx(float(product["curve"]), 1.0), "en 30 días llega al pico")
	var peak: int = Products.get_daily_income(product)
	_expect(peak >= 140 and peak <= 200, "pequeño de buena calidad cerca de $150 al día: %d" % peak)
	_expect(Products.get_users(product) == ProductCatalog.get_peak_users("small"), "usuarios en el pico: %d" % Products.get_users(product))
	_expect(Economy.get_month_totals(Economy.get_current_month()).get(Products.CONCEPT_INCOME, 0) > 0
		or Economy.get_month_totals(Economy.get_current_month() - 1).get(Products.CONCEPT_INCOME, 0) > 0, "cobra «Ingreso de productos»")
	_days(60)
	_expect(product["phase"] == Products.PHASE_DECLINE, "tras 60 días en el pico cae")
	_days(60)
	var half: float = float(product["curve"])
	_expect(half < 0.6 and half > 0.5, "a mitad de la caída: %.2f" % half)
	_days(70)
	_expect(is_equal_approx(float(product["curve"]), ProductCatalog.get_lifecycle("floor")), "y se queda en el piso")
	# Con vendedores crece más rápido.
	_expect(is_equal_approx(Products.get_growth_speed(), 1.0), "sin vendedores, velocidad 1")
	Staff.employees.append({"id": 990, "name": "Vendedor", "role": "salesperson", "level": "junior", "salary": 0,
		"schedule": StaffCatalog.get_role_schedule("salesperson"), "energy": 100, "mood": 70, "stress": 20, "paid_until": 0, "owed": 0})
	_expect(is_equal_approx(Products.get_growth_speed(), 1.15), "un vendedor +15 %%: %.2f" % Products.get_growth_speed())


func _check_production_bugs() -> void:
	_new_game()
	_builder.place("server_rack", RACK_CELLS[1], 0)
	var clean: Dictionary = _finished_product()
	Products.launch(clean["id"])
	var buggy: Dictionary = _finished_product("small", 10)
	Products.launch(buggy["id"])
	_expect(int(buggy["production_bugs"]) == 10, "los errores pasan a producción")
	_days(10)
	_expect(is_equal_approx(float(buggy["bug_loss"]), 0.5), "10 errores quitan 5 %% por día: %.2f" % float(buggy["bug_loss"]))
	_expect(Products.get_users(buggy) <= Products.get_users(clean) / 2 + 1, "con errores pierde usuarios: %d contra %d" % [
		Products.get_users(buggy), Products.get_users(clean)])
	_days(10)
	_expect(is_equal_approx(float(buggy["bug_loss"]), ProductCatalog.get_production_bugs("max_loss")), "hasta un tope")


func _check_update() -> void:
	_new_game()
	var product: Dictionary = _finished_product("small", 10)
	Products.launch(product["id"])
	_days(120)
	_expect(product["phase"] == Products.PHASE_DECLINE and float(product["bug_loss"]) > 0.0, "cayendo y con errores")
	var before: int = Products.get_users(product)
	_expect(Products.update_problem(product["id"]).is_empty(), "se puede actualizar")
	var result: Dictionary = Products.start_update(product["id"])
	_expect(result["ok"] and product.has("update"), "empezar la actualización: %s" % result["message"])
	var update: Dictionary = product["update"]
	_expect(int(update["total_points"]) == 300 and int(update["team_id"]) == Projects.CEO_TEAM, "20 %% de los puntos, la lleva el CEO")
	_expect(Products.get_development_count() == 1 and not Products.update_problem(product["id"]).is_empty(), "cuenta para el tope")
	_expect(Products.get_product_of(Projects.CEO_TEAM) == update and Products.describe_project(update).begins_with("Actualización"),
		"es el proyecto del CEO")
	_expect(Products.get_daily_income(product) > 0, "sigue dando ingreso mientras se actualiza")
	_notices.clear()
	var hours: int = 0
	while product.has("update") and hours < 24 * 60:
		GameClock.fast_forward_hours(1)
		hours += 1
	_expect(not product.has("update"), "la actualización termina (%d horas)" % hours)
	_expect(product["phase"] == Products.PHASE_PLATEAU and is_equal_approx(float(product["curve"]), 1.0)
		and is_equal_approx(float(product["bug_loss"]), 0.0), "vuelve al pico sin la pérdida por errores")
	_expect(Products.get_users(product) > before, "lo reaviva: %d contra %d" % [Products.get_users(product), before])
	_expect(_notices.any(func(text: String) -> bool: return text.begins_with("Actualización terminada")), "avisa: %s" % [_notices])
	# Abandonar una actualización deja el producto como estaba.
	Products.start_update(product["id"])
	_expect(Products.abandon(product["id"])["ok"] and not product.has("update") and Products.get_product(product["id"]) == product,
		"abandonar la actualización no quita el producto")


func _check_racks_and_retire() -> void:
	_new_game()
	_builder.place("server_rack", RACK_CELLS[1], 0)
	var first: Dictionary = _finished_product()
	Products.launch(first["id"])
	var second: Dictionary = _finished_product()
	Products.launch(second["id"])
	_days(30)
	var full: int = Products.get_users(second)
	_expect(Products.get_supported_ids() == ([first["id"], second["id"]] as Array[int]), "los dos tienen rack")
	_builder.sell_furniture_at(RACK_CELLS[1])
	_expect(Products.get_supported_ids() == ([first["id"]] as Array[int]), "sin el segundo rack, el primero lanzado lo conserva")
	_expect(Products.get_users(second) == full / 2, "el otro tiene la mitad de los usuarios: %d" % Products.get_users(second))
	_notices.clear()
	_expect(Products.retire(first["id"])["ok"] and Products.get_launched().size() == 1 and _notices.size() == 1, "retirar")
	_expect(Products.get_supported_ids() == ([second["id"]] as Array[int]) and Products.get_users(second) == full,
		"libera su rack para el otro")
	_expect(not Products.retire(first["id"])["ok"], "dos veces no")


func _check_stage_and_value() -> void:
	_new_game()
	var requirement: Dictionary = {}
	for item: Dictionary in Company.get_requirements(3):
		if item["key"] == "products_launched":
			requirement = item
	_expect(not requirement.is_empty() and int(requirement["needed"]) == 1 and not requirement["met"], "Mediana empresa pide 1 lanzado")
	var product: Dictionary = _finished_product()
	Products.launch(product["id"])
	for item: Dictionary in Company.get_requirements(3):
		if item["key"] == "products_launched":
			_expect(item["met"], "lanzado, se cumple")
	_days(30)
	var parts: Array[Dictionary] = Company.get_value_parts()
	_expect(String(parts[3]["label"]).begins_with("Productos") and int(parts[3]["amount"]) == Products.get_daily_income(product) * ProductCatalog.get_value_days(),
		"el valor suma value_days días de ingreso: %s" % [parts[3]])
	_expect(Products.get_active_count() == 1, "producto activo")


func _check_save() -> void:
	_new_game()
	var product: Dictionary = _finished_product("small", 4)
	Products.launch(product["id"])
	_days(5)
	Products.start_update(product["id"])
	product["update"]["progress"]["design"] = 20.0
	var users: int = Products.get_users(product)
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(Products.get_launched().is_empty() and Products.launched_count == 0, "partida nueva sin lanzados")
	_expect(SaveManager.load_game("slot_5"), "cargar")
	var loaded: Dictionary = Products.get_product(product["id"])
	_expect(not loaded.is_empty() and loaded["state"] == Products.STATE_LAUNCHED and Products.get_users(loaded) == users
		and int(loaded["production_bugs"]) == 4 and Products.launched_count == 1, "el lanzado se guarda: %s" % [loaded])
	_expect(loaded.has("update") and is_equal_approx(float(loaded["update"]["progress"]["design"]), 20.0)
		and int(loaded["update"]["product_id"]) == product["id"], "y su actualización")
	# Una partida del hito 41 (sin launched_count ni campos de lanzamiento) carga.
	Products.import_state({"products": [{"id": 1, "name": "Viejo", "type": "saas", "size": "small", "state": "development"}]})
	_expect(Products.get_in_development().size() == 1 and Products.launched_count == 0, "partida del hito 41")


func _check_ui() -> void:
	_new_game()
	var product: Dictionary = _finished_product()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var panel: ProjectsPanel = game.get_node("ProjectsPanel")
	panel.set_open(true)
	panel.set_tab(ProjectsPanel.TAB_PRODUCTS)
	await get_tree().process_frame
	var launch: Button = panel.get_launch_button(product["id"])
	_expect(launch != null and not launch.disabled and launch.text.contains("calidad 63 %"), "botón Lanzar con la calidad")
	launch.pressed.emit()
	await get_tree().process_frame
	_expect(product["state"] == Products.STATE_LAUNCHED, "Lanzar desde el panel")
	var text: String = panel.get_list_text()
	_expect(text.contains("Lanzados (1) · racks 1 de 1") and text.contains("usuarios") and text.contains("Creciendo"), "sección Lanzados: %s" % text)
	panel.get_update_button(product["id"]).pressed.emit()
	await get_tree().process_frame
	_expect(product.has("update") and panel.get_list_text().contains("Actualización en curso"), "Actualizar desde el panel")
	_expect(panel.get_owner_choice(product["id"]) != null, "elige quién lleva la actualización")
	panel.get_abandon_button(product["id"]).pressed.emit()
	await get_tree().process_frame
	panel.get_confirm_abandon_button().pressed.emit()
	await get_tree().process_frame
	_expect(not product.has("update"), "abandonar la actualización")
	panel.get_retire_button(product["id"]).pressed.emit()
	await get_tree().process_frame
	_expect(panel.get_confirm_retire_button() != null and Products.get_launched().size() == 1, "Retirar pide confirmación")
	panel.get_confirm_retire_button().pressed.emit()
	await get_tree().process_frame
	_expect(Products.get_launched().is_empty() and panel.get_list_text().contains("Ningún producto lanzado"), "retirado")
	panel.set_open(false)
	game.queue_free()
	await get_tree().process_frame
