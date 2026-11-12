# Prueba del hito 41: desarrollo de productos.
# Criterio: desde Pequeña empresa y con una Sala de servidores que funcione se empieza un
# producto; comparte el tope de proyectos con los contratos; un equipo lleva uno a la
# vez; avanza con fases y errores como un contrato; se abandona; se guarda.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=products
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261141
## Sala de servidores como en test_servers: x 3 a 5, y 0 a 1, puerta al sur en x 4.
const ROOM_CELL := Vector2i(4, 0)
const AIR_CELL := Vector2i(3, 0)
const RACK_CELL := Vector2i(5, 0)

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()
var _notices: Array[String] = []


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_catalog()
	_check_gating()
	_check_start_and_limit()
	_check_team_exclusivity()
	_check_production()
	_check_abandon()
	_check_save()
	await _check_ui()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva en Pequeña empresa, con dinero, objetivos cumplidos y las paredes de la sala.
func _new_game(server_room: bool = true) -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	Products.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Company.stage = 2
	Economy.earn(100000, "Prueba")
	var walls: Array[Dictionary] = []
	for x: int in [3, 5]:
		walls.append({"edge": Vector3i(x, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL})
	walls.append({"edge": Vector3i(4, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.DOOR})
	_expect(_builder.apply(walls)["ok"], "paredes de la sala")
	if server_room:
		_build_server_room()


func _build_server_room() -> void:
	_builder.mark_room(OfficeState.SERVER_ROOM, ROOM_CELL)
	_builder.place("air_conditioner", AIR_CELL, 2)
	_builder.place("server_rack", RACK_CELL, 0)


# Un equipo de un diseñador con su puesto en un Área de trabajo. Devuelve el equipo.
func _make_team() -> Dictionary:
	_builder.mark_room(Workstations.WORK_AREA, Vector2i(3, 4))
	_builder.place("simple_desk", Vector2i(1, 5), 2)
	_builder.install_computer("basic_computer", Vector2i(1, 5))
	_builder.place("basic_chair", Vector2i(1, 6), 0)
	var designer: Dictionary = Staff.hire_directly("designer", "junior")
	_expect(not designer.is_empty(), "contratar un diseñador")
	var team: Dictionary = Staff.create_team()
	_expect(Staff.add_to_team(team["id"], designer["id"])["ok"], "armar un equipo")
	return team


func _check_catalog() -> void:
	_expect(ProductCatalog.get_type_ids() == (["mobile_app", "saas", "game"] as Array[String]), "tres tipos: %s" % [ProductCatalog.get_type_ids()])
	_expect(ProductCatalog.get_type_name("saas") == "Software en la nube", "nombre del tipo")
	_expect(ProductCatalog.get_size_ids() == (["small", "medium", "large"] as Array[String]), "tres tamaños")
	_expect(ProductCatalog.get_racks("small") == 1 and ProductCatalog.get_racks("medium") == 3 and ProductCatalog.get_racks("large") == 8,
		"racks 1/3/8")
	for type_id: String in ProductCatalog.get_type_ids():
		var split: Array[int] = ProductCatalog.get_split(type_id)
		_expect(split.size() == 3 and split[0] + split[1] + split[2] == 100, "el reparto de %s suma 100" % type_id)
	_expect(ProductCatalog.get_min_stage() == 2, "desde Pequeña empresa")


func _check_gating() -> void:
	_new_game(false)
	Company.stage = 1
	_expect(Products.start_problem().contains("Pequeña empresa"), "antes de Pequeña empresa no: %s" % Products.start_problem())
	_expect(not Products.start("mobile_app", "small")["ok"] and Products.products.is_empty(), "no se empieza")
	Company.stage = 2
	_expect(Products.start_problem().contains("Sala de servidores"), "sin sala no: %s" % Products.start_problem())
	_builder.mark_room(OfficeState.SERVER_ROOM, ROOM_CELL)
	_builder.place("server_rack", RACK_CELL, 0)
	_expect(not Products.start_problem().is_empty(), "con la sala sin aire tampoco")
	_builder.place("air_conditioner", AIR_CELL, 2)
	_expect(Products.start_problem().is_empty(), "con la sala funcionando sí")
	_expect(not Products.start("bogus", "small")["ok"], "un tipo que no existe no")


func _check_start_and_limit() -> void:
	_new_game()
	var result: Dictionary = Products.start("saas", "medium")
	_expect(result["ok"], "empezar: %s" % result["message"])
	var product: Dictionary = Products.get_product(result["id"])
	_expect(product["name"] == ProductCatalog.get_product_name(0) and product["state"] == Products.STATE_DEVELOPMENT, "nombre y estado")
	_expect(product["points"]["design"] == 750 and product["points"]["programming"] == 3000 and product["points"]["testing"] == 1250,
		"5000 puntos repartidos 15/60/25: %s" % [product["points"]])
	_expect(int(product["team_id"]) == Projects.CEO_TEAM, "sin equipos lo lleva el CEO")
	_expect(Projects.get_project_count() == 1 and Projects.get_contract_limit() == 1, "cuenta para el tope")
	_expect(Products.start_problem().contains("tope"), "con el tope lleno no se empieza otro: %s" % Products.start_problem())
	var offer: Dictionary = Projects.create_offer("small")
	_expect(not Projects.accept(offer["id"])["ok"], "ni se acepta un contrato")
	_expect(Products.abandon(product["id"])["ok"], "abandonar")
	_expect(Projects.accept(offer["id"])["ok"], "ahora sí el contrato")
	_expect(not Products.start("game", "small")["ok"], "y el contrato también ocupa el tope")


func _check_team_exclusivity() -> void:
	_new_game()
	var team: Dictionary = _make_team()
	_expect(Projects.get_contract_limit() == 2, "un equipo: tope 2")
	var product: Dictionary = Products.get_product(Products.start("mobile_app", "small")["id"])
	_expect(int(product["team_id"]) == team["id"], "se lo da al primer equipo libre")
	var designer: Dictionary = Staff.employees[0]
	_expect(not Staff.is_idle(designer), "un producto también es trabajo (no baja el ánimo por estar sin contrato)")
	var offer: Dictionary = Projects.create_offer("small")
	_expect(Projects.accept(offer["id"])["ok"], "aceptar un contrato")
	var contract: Dictionary = Projects.contracts[0]
	_expect(int(contract["team_id"]) == Projects.CEO_TEAM, "el contrato va al CEO, el equipo está ocupado")
	_expect(Projects.assign(contract["id"], team["id"])["ok"], "darle el contrato al equipo")
	_expect(int(product["team_id"]) == Projects.NO_TEAM, "el producto queda sin equipo")
	_expect(Products.assign(product["id"], team["id"])["ok"], "devolverle el producto")
	_expect(int(contract["team_id"]) == Projects.NO_TEAM and int(product["team_id"]) == team["id"], "y el contrato queda sin equipo")
	_expect(Products.assign(product["id"], Projects.CEO_TEAM)["ok"] and Products.get_product_of(team["id"]).is_empty(),
		"pasárselo al CEO libera el equipo")
	Staff.delete_team(team["id"])
	_expect(int(product["team_id"]) == Projects.CEO_TEAM, "borrar un equipo no toca al CEO")


func _check_production() -> void:
	_new_game()
	var product: Dictionary = Products.get_product(Products.start("mobile_app", "small")["id"])
	_notices.clear()
	# El CEO trabaja en días hábiles; avanzar hasta que termine.
	var hours: int = 0
	while not Production.is_finished(product) and hours < 24 * 200:
		GameClock.fast_forward_hours(1)
		hours += 1
	_expect(Production.is_finished(product), "el CEO lo termina (%d horas)" % hours)
	_expect(float(product["progress"]["design"]) >= 450.0 - Production.EPSILON, "diseño completo: %s" % [product["progress"]])
	_expect(int(product["bugs_hidden"]) + int(product["bugs_found"]) + int(product["bugs_fixed"]) > 0, "programar deja errores")
	_expect((product["worked_by"] as Array).is_empty(), "el CEO no se anota (como en los contratos): %s" % [product["worked_by"]])
	_expect(_notices.any(func(text: String) -> bool: return text.begins_with("Terminado:") and text.contains(product["name"])),
		"avisa al terminar: %s" % [_notices])
	_expect(Products.get_development_count() == 1, "terminado sigue en desarrollo hasta lanzarlo (hito 42)")


func _check_abandon() -> void:
	_new_game()
	var id: int = Products.start("game", "large")["id"]
	_notices.clear()
	var result: Dictionary = Products.abandon(id)
	_expect(result["ok"] and Products.products.is_empty() and _notices.size() == 1, "abandonar avisa y lo quita")
	_expect(not Products.abandon(id)["ok"], "dos veces no")
	_expect(Products.start("game", "small")["ok"] and Products.products[0]["name"] == ProductCatalog.get_product_name(1),
		"el siguiente usa otro nombre")


func _check_save() -> void:
	_new_game()
	var product: Dictionary = Products.get_product(Products.start("saas", "small")["id"])
	product["progress"]["design"] = 100.5
	product["bugs_hidden"] = 3
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(Products.products.is_empty(), "partida nueva sin productos")
	_expect(SaveManager.load_game("slot_5"), "cargar")
	var loaded: Dictionary = Products.get_product(product["id"])
	_expect(not loaded.is_empty() and is_equal_approx(float(loaded["progress"]["design"]), 100.5) and loaded["bugs_hidden"] == 3
		and loaded["name"] == product["name"] and int(loaded["team_id"]) == Projects.CEO_TEAM, "el producto se guarda: %s" % [loaded])
	_expect(Products.start("saas", "small")["ok"] == false, "el tope sigue contando lo cargado")
	# Una partida de antes del hito 41 no tiene "products".
	Products.import_state({})
	_expect(Products.products.is_empty() and Products.start_problem().is_empty(), "partida vieja: sin productos")


func _check_ui() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var panel: ProjectsPanel = game.get_node("ProjectsPanel")
	panel.set_open(true)
	await get_tree().process_frame
	_expect(panel.get_tab() == ProjectsPanel.TAB_CONTRACTS and panel.get_start_button() == null, "abre en Contratos")
	panel.get_tab_button(ProjectsPanel.TAB_PRODUCTS).pressed.emit()
	await get_tree().process_frame
	_expect(panel.get_tab() == ProjectsPanel.TAB_PRODUCTS, "pestaña Productos")
	panel.choose_new_product("game", "medium")
	var text: String = panel.get_list_text()
	_expect(text.contains("Nuevo producto") and text.contains("5,000 puntos") and text.contains("3 racks") and not text.contains("$5,000"),
		"muestra el producto elegido: %s" % text)
	_expect(not panel.get_start_button().disabled, "Empezar habilitado")
	panel.get_start_button().pressed.emit()
	await get_tree().process_frame
	_expect(Products.get_development_count() == 1 and Products.products[0]["type"] == "game" and Products.products[0]["size"] == "medium",
		"Empezar crea el elegido")
	var product_id: int = Products.products[0]["id"]
	text = panel.get_list_text()
	_expect(text.contains("En desarrollo (1)") and text.contains(Products.describe_title(Products.products[0])), "lo lista: %s" % text)
	_expect(panel.get_product_bar(product_id, "design") != null and panel.get_owner_choice(product_id) != null, "barras y quién lo lleva")
	_expect(panel.get_start_button().disabled and panel.get_list_text().contains("tope"), "con el tope lleno no se empieza otro")
	var choice: OptionButton = panel.get_owner_choice(product_id)
	choice.select(0)
	choice.item_selected.emit(0)
	await get_tree().process_frame
	_expect(int(Products.products[0]["team_id"]) == Projects.NO_TEAM and panel.get_list_text().contains("Nadie lo lleva"), "dejarlo sin nadie: %s · %s" % [Products.products[0]["team_id"], panel.get_list_text()])
	panel.get_abandon_button(product_id).pressed.emit()
	await get_tree().process_frame
	_expect(panel.get_confirm_abandon_button() != null and Products.get_development_count() == 1, "pide confirmación")
	panel.get_confirm_abandon_button().pressed.emit()
	await get_tree().process_frame
	_expect(Products.products.is_empty() and panel.get_list_text().contains("Ningún producto"), "abandonado")
	panel.set_tab(ProjectsPanel.TAB_CONTRACTS)
	await get_tree().process_frame
	_expect(panel.get_list_text().contains("En curso (0 de 1)"), "Contratos como antes")
	# Horarios ofrece el producto en la lista del CEO.
	Products.start("saas", "small")
	await get_tree().process_frame
	var teams_panel: TeamsPanel = game.get_node("TeamsPanel")
	teams_panel.set_open(true)
	await get_tree().process_frame
	var ceo_choice: OptionButton = teams_panel.get_ceo_project_choice()
	_expect(ceo_choice.get_item_text(ceo_choice.selected).begins_with("Producto:"), "Horarios muestra el producto del CEO: %s" %
		ceo_choice.get_item_text(ceo_choice.selected))
	ceo_choice.select(0)
	ceo_choice.item_selected.emit(0)
	_expect(int(Products.products[0]["team_id"]) == Projects.NO_TEAM, "Ninguno lo suelta")
	teams_panel.set_open(false)
	panel.set_open(false)
	game.queue_free()
	await get_tree().process_frame
