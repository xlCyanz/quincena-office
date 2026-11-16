# Cuartos de casilla: los muebles chicos ocupan un cuarto y caben 4 por casilla, nunca con uno grande;
# vender y girar eligen el del cuarto bajo el ratón; se guarda el cuarto (las partidas viejas, el 0).
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=quarters
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const CELL := Vector2i(4, 4)

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_packed.call_deferred(GAME_SCENE)
		return
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_builder()
	_check_save()
	await _check_controller()
	SaveManager.new_game()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _items_at(cell: Vector2i) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in OfficeState.furniture:
		if item["cell"] == cell:
			found.append(item)
	return found


func _check_catalog() -> void:
	for id: String in ["small_plant", "trash_can", "water_dispenser", "floor_lamp"]:
		_expect(FurnitureCatalog.is_small(id), "%s es chico" % id)
	_expect(not FurnitureCatalog.is_small("simple_desk") and not FurnitureCatalog.is_small("large_plant"), "escritorio y planta grande no")
	_expect(FurnitureCatalog.quarter_at(Vector2(4.2, 3.8)) == 1 and FurnitureCatalog.quarter_at(Vector2(3.8, 4.2)) == 2
		and FurnitureCatalog.quarter_at(Vector2(3.9, 3.9)) == 0 and FurnitureCatalog.quarter_at(Vector2(4.1, 4.1)) == 3,
		"el cuarto sale del lado del punto dentro de la casilla")
	_expect(FurnitureCatalog.get_quarter_offset(0) == Vector2(-0.25, -0.25) and FurnitureCatalog.get_quarter_offset(3) == Vector2(0.25, 0.25),
		"centro de cada cuarto")


func _check_builder() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	for quarter: int in [2, 0, 3, 1]:
		var result: Dictionary = builder.place("small_plant", CELL, 0, quarter)
		_expect(result["ok"], "planta en el cuarto %d: %s" % [quarter, result["message"]])
	_expect(_items_at(CELL).size() == 4, "caben 4 chicos en una casilla")
	var full: Dictionary = builder.place("trash_can", CELL, 0)
	_expect(not full["ok"] and String(full["message"]).contains("otro objeto"), "un quinto no cabe: %s" % full["message"])
	_expect(not builder.place("simple_desk", CELL, 0)["ok"], "un escritorio no va con chicos")
	# Vender el del cuarto 2 deja los otros; sin cuarto, se pone en el libre.
	var money: int = Economy.balance
	_expect(builder.sell_furniture_at(CELL, 2)["ok"] and Economy.balance > money, "vender el del cuarto 2")
	var quarters: Array[int] = []
	for item: Dictionary in _items_at(CELL):
		quarters.append(FurnitureCatalog.get_quarter(item))
	quarters.sort()
	_expect(quarters == ([0, 1, 3] as Array[int]), "quedan los cuartos 0, 1 y 3: %s" % [quarters])
	_expect(builder.place("trash_can", CELL, 0)["ok"], "un zafacón sin cuarto entra en el libre")
	_expect(FurnitureCatalog.get_quarter(OfficeState.furniture[OfficeState.find_furniture_at(CELL, 2)]) == 2
		and OfficeState.furniture[OfficeState.find_furniture_at(CELL, 2)]["id"] == "trash_can", "y quedó en el cuarto 2")
	_expect(builder.rotate(CELL, 1)["ok"] and int(OfficeState.furniture[OfficeState.find_furniture_at(CELL, 1)]["rotation"]) == 1,
		"girar el del cuarto 1")
	# Junto a un escritorio: no sobre él, sí al lado.
	builder.place("simple_desk", CELL + Vector2i(1, 0), 0)
	_expect(not builder.place("small_plant", CELL + Vector2i(1, 0), 0, 0)["ok"], "un chico no va encima de un escritorio")
	_expect(OfficeState.get_blocking_cells().has(CELL), "la casilla con chicos tapa el paso")


func _check_save() -> void:
	var saved: Dictionary = OfficeState.export_state()
	OfficeState.import_state(JSON.parse_string(JSON.stringify(saved)))
	var quarters: Array[int] = []
	for item: Dictionary in _items_at(CELL):
		quarters.append(FurnitureCatalog.get_quarter(item))
	quarters.sort()
	_expect(quarters == ([0, 1, 2, 3] as Array[int]), "guardar y cargar conserva los cuartos: %s" % [quarters])
	for item: Dictionary in saved["furniture"]:
		item.erase("quarter")
	OfficeState.import_state(JSON.parse_string(JSON.stringify(saved)))
	var plant: Dictionary = OfficeState.furniture[OfficeState.find_furniture_at(CELL)]
	_expect(FurnitureCatalog.get_quarter(plant) == 0, "partida vieja: cuarto 0")
	_expect(FurnitureCatalog.get_quarter(OfficeState.find_furniture_assigned_to("ceo")) == -1, "la silla del CEO ocupa la casilla entera")


func _check_controller() -> void:
	SaveManager.new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var panel: BuildPanel = game.get_node("BuildPanel")
	var controller: BuildController = game.get_node("BuildController")
	panel.set_build_mode(true)
	panel.select_tool("small_plant")
	# Ratón en el cuarto de abajo a la derecha.
	controller.set("_pointer", Vector2(CELL) + Vector2(0.3, 0.2))
	controller.call("_update_preview")
	_expect(int(controller.get("_preview_quarter")) == 3 and bool(controller.get("_preview_ok")), "la vista previa marca el cuarto 3")
	var apply: Callable = controller.get("_apply_preview")
	_expect(apply.call()["ok"] and FurnitureCatalog.get_quarter(OfficeState.furniture[OfficeState.find_furniture_at(CELL)]) == 3,
		"el clic la pone en el cuarto 3")
	await get_tree().process_frame
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var view: FurnitureView = null
	for child: Node in grid.find_children("*", "FurnitureView", true, false):
		if (child as FurnitureView).item_id == "small_plant":
			view = child
	var expected: Vector2 = grid.grid_to_world(Vector2(CELL) + FurnitureCatalog.get_quarter_offset(3))
	_expect(view != null and view.quarter == 3 and view.position.distance_to(expected) < 2.0,
		"se dibuja en su cuarto: %s / %s" % [view.position if view else Vector2.ZERO, expected])
	# Vender con el ratón en otro cuarto vacío de la misma casilla vende igual la planta.
	panel.select_tool(BuildController.TOOL_SELL)
	controller.set("_pointer", Vector2(CELL) + Vector2(-0.2, -0.2))
	controller.call("_update_preview")
	apply = controller.get("_apply_preview")
	_expect(apply.is_valid() and apply.call()["ok"] and OfficeState.find_furniture_at(CELL) < 0, "vender la planta desde su casilla")
	panel.set_build_mode(false)
	game.queue_free()
	await get_tree().process_frame
