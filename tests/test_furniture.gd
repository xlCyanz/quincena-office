# Prueba sin ventana del hito 6: colocar, girar y vender escritorio, silla, computadora
# y planta. No se puede colocar sobre otro objeto ni bloquear el único acceso; la
# reventa devuelve el 50%.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_furniture.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	_check_catalog()
	_check_place_and_overlap()
	_check_access()
	_check_rotate()
	_check_computer_and_sell()
	await _check_in_game_with_mouse()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _index_at(cell: Vector2i) -> int:
	return OfficeState.find_furniture_at(cell)


func _check_catalog() -> void:
	var prices: Dictionary = {"simple_desk": 150, "basic_chair": 60, "basic_computer": 500,
		"small_plant": 40, "executive_desk": 900}
	for id: String in prices:
		_expect(FurnitureCatalog.get_price(id) == prices[id], "precio de %s" % id)
		_expect(FurnitureCatalog.get_resale(id) == prices[id] / 2, "la reventa de %s no es el 50%%" % id)
	_expect(FurnitureCatalog.get_footprint("basic_computer", Vector2i(2, 2), 0).is_empty(),
		"la computadora no debería ocupar casilla")
	_expect(FurnitureCatalog.get_footprint("executive_desk", Vector2i(2, 2), 1) == [Vector2i(2, 2), Vector2i(2, 3)],
		"el escritorio ejecutivo girado debería ocupar (2, 2) y (2, 3)")


func _check_place_and_overlap() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	var money: int = Economy.balance
	var count: int = OfficeState.furniture.size()

	var result: Dictionary = builder.place("simple_desk", Vector2i(4, 4), 0)
	_expect(result["ok"] and Economy.balance == money - 150 and OfficeState.furniture.size() == count + 1,
		"colocar un escritorio sencillo: %s" % [result])
	money = Economy.balance

	for id: String in ["basic_chair", "small_plant", "simple_desk"]:
		result = builder.place(id, Vector2i(4, 4), 0)
		_expect(not result["ok"] and Economy.balance == money, "%s encima del escritorio: %s" % [id, result])
	result = builder.place("executive_desk", Vector2i(3, 4), 0)  # ocuparía (3, 4) y (4, 4)
	_expect(not result["ok"] and Economy.balance == money, "un escritorio de 2 casillas pisando otro: %s" % [result])
	result = builder.place("small_plant", Vector2i(1, 0), 0)
	_expect(not result["ok"], "una planta sobre el escritorio del CEO: %s" % [result])
	result = builder.place("small_plant", OfficeState.entrance, 0)
	_expect(not result["ok"], "una planta tapando la entrada: %s" % [result])
	result = builder.place("executive_desk", Vector2i(5, 3), 0)  # (6, 3) está fuera
	_expect(not result["ok"], "un escritorio que se sale del local: %s" % [result])

	# Un mueble no puede quedar partido por una pared, ni una pared partir un mueble.
	builder.apply([{"edge": Vector3i(4, 6, GridEdge.AXIS_X), "kind": ConstructionCatalog.WALL}])
	money = Economy.balance
	result = builder.place("executive_desk", Vector2i(4, 6), 0)
	_expect(not result["ok"] and Economy.balance == money, "un escritorio atravesado por una pared: %s" % [result])
	builder.place("executive_desk", Vector2i(2, 5), 0)  # (2, 5) y (3, 5)
	result = builder.apply([{"edge": Vector3i(2, 5, GridEdge.AXIS_X), "kind": ConstructionCatalog.WALL}])
	_expect(not result["ok"], "una pared en medio de un escritorio: %s" % [result])

	# Donde hay un personaje no se coloca nada.
	builder.occupied_cells = [Vector2i(0, 5)]
	result = builder.place("small_plant", Vector2i(0, 5), 0)
	_expect(not result["ok"], "una planta encima de un personaje: %s" % [result])


func _check_access() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	var money: int = Economy.balance
	# Frente a la puerta de la Oficina Ejecutiva, por dentro o por fuera: el CEO no llegaría.
	for cell: Vector2i in [Vector2i(1, 2), Vector2i(1, 3)]:
		var result: Dictionary = builder.place("small_plant", cell, 0)
		_expect(not result["ok"] and Economy.balance == money and _index_at(cell) < 0,
			"una planta en %s bloquea la puerta de la Oficina Ejecutiva: %s" % [cell, result])
	# Un rincón al que solo se llega por (5, 1)–(5, 2): taparlo lo dejaría sin acceso.
	builder.apply([
		{"edge": Vector3i(3, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL},
	])
	money = Economy.balance
	var result: Dictionary = builder.place("small_plant", Vector2i(5, 2), 0)
	_expect(not result["ok"] and Economy.balance == money, "una planta que encierra el rincón: %s" % [result])
	result = builder.place("small_plant", Vector2i(4, 4), 0)
	_expect(result["ok"], "una planta en medio del local no bloquea nada: %s" % [result])


func _check_rotate() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	var money: int = Economy.balance
	# El escritorio del CEO girado pisaría su silla.
	var result: Dictionary = builder.rotate(Vector2i(1, 0))
	_expect(not result["ok"] and OfficeState.furniture[_index_at(Vector2i(1, 0))]["rotation"] == 2,
		"el escritorio del CEO giró sobre su silla: %s" % [result])
	builder.place("executive_desk", Vector2i(4, 4), 0)  # (4, 4) y (5, 4)
	money = Economy.balance
	result = builder.rotate(Vector2i(5, 4))
	var index: int = _index_at(Vector2i(4, 5))
	_expect(result["ok"] and Economy.balance == money and index >= 0 and OfficeState.furniture[index]["rotation"] == 1,
		"girar es gratis y el escritorio pasa a ocupar (4, 4) y (4, 5): %s" % [result])
	_expect(_index_at(Vector2i(5, 4)) < 0, "tras girar, (5, 4) debería quedar libre")
	for i: int in range(3):
		builder.rotate(Vector2i(4, 4))
	_expect(OfficeState.furniture[_index_at(Vector2i(4, 4))]["rotation"] == 0, "cuatro giros vuelven al inicio")
	result = builder.rotate(Vector2i(3, 3))
	_expect(not result["ok"], "girar donde no hay mueble: %s" % [result])


func _check_computer_and_sell() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	builder.place("simple_desk", Vector2i(4, 4), 0)
	builder.place("small_plant", Vector2i(4, 6), 0)
	var money: int = Economy.balance

	var result: Dictionary = builder.install_computer("basic_computer", Vector2i(4, 4))
	_expect(result["ok"] and Economy.balance == money - 500
		and OfficeState.furniture[_index_at(Vector2i(4, 4))]["computer"] == "basic_computer",
		"instalar una computadora: %s" % [result])
	money = Economy.balance
	result = builder.install_computer("basic_computer", Vector2i(4, 4))
	_expect(not result["ok"] and Economy.balance == money, "dos computadoras en un escritorio: %s" % [result])
	result = builder.install_computer("basic_computer", Vector2i(4, 6))
	_expect(not result["ok"], "una computadora sobre una planta: %s" % [result])
	result = builder.install_computer("basic_computer", Vector2i(3, 3))
	_expect(not result["ok"], "una computadora en el piso: %s" % [result])
	result = builder.place("basic_computer", Vector2i(3, 3), 0)
	_expect(not result["ok"], "colocar una computadora como mueble: %s" % [result])

	# Vender: primero la computadora, luego el escritorio, cada uno al 50%.
	result = builder.sell_furniture_at(Vector2i(4, 4))
	_expect(result["ok"] and Economy.balance == money + 250 and _index_at(Vector2i(4, 4)) >= 0
		and OfficeState.furniture[_index_at(Vector2i(4, 4))]["computer"].is_empty(), "vender la computadora: %s" % [result])
	money = Economy.balance
	result = builder.sell_furniture_at(Vector2i(4, 4))
	_expect(result["ok"] and Economy.balance == money + 75 and _index_at(Vector2i(4, 4)) < 0,
		"vender el escritorio: %s" % [result])
	money = Economy.balance
	result = builder.sell_furniture_at(Vector2i(4, 6))
	_expect(result["ok"] and Economy.balance == money + 20, "vender la planta: %s" % [result])
	money = Economy.balance
	result = builder.sell_furniture_at(Vector2i(1, 1))
	_expect(not result["ok"] and Economy.balance == money and _index_at(Vector2i(1, 1)) >= 0,
		"la silla del CEO no se vende: %s" % [result])
	# El escritorio del CEO trae computadora: se vende primero ella (+250) y luego él (+450).
	result = builder.sell_furniture_at(Vector2i(2, 0))
	_expect(result["ok"] and Economy.balance == money + 250, "vender la computadora del CEO: %s" % [result])
	result = builder.sell_furniture_at(Vector2i(2, 0))
	_expect(result["ok"] and Economy.balance == money + 250 + 450 and _index_at(Vector2i(1, 0)) < 0,
		"vender el escritorio ejecutivo: %s" % [result])
	result = builder.sell_furniture_at(Vector2i(3, 3))
	_expect(not result["ok"], "vender donde no hay mueble: %s" % [result])


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame


func _click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	await _push(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _push(event)


func _check_in_game_with_mouse() -> void:
	SaveManager.new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameClock.stop()
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var panel: BuildPanel = game.get_node("BuildPanel")
	var at_cell: Callable = func(cell: Vector2i) -> Vector2:
		return grid.get_canvas_transform() * grid.cell_to_world(cell)
	var press: Callable = func(tool: String) -> void:
		await _click(panel.get_tool_button(tool).get_global_rect().get_center())

	await _click(panel.get_open_button().get_global_rect().get_center())
	_expect(panel.is_build_mode() and GameClock.is_paused, "no se abrió el modo construcción en pausa")

	# Escritorio sencillo, girado con un clic derecho antes de ponerlo.
	await press.call("simple_desk")
	var money: int = Economy.balance
	await _click(at_cell.call(Vector2i(4, 5)), MOUSE_BUTTON_RIGHT)
	await _click(at_cell.call(Vector2i(4, 5)))
	var index: int = _index_at(Vector2i(4, 5))
	_expect(index >= 0 and OfficeState.furniture[index]["id"] == "simple_desk" and OfficeState.furniture[index]["rotation"] == 1
		and Economy.balance == money - 150, "colocar el escritorio girado con el ratón")
	var views: int = _count_views(grid)
	money = Economy.balance
	await _click(at_cell.call(Vector2i(4, 5)))
	_expect(Economy.balance == money and _count_views(grid) == views, "se colocó otro escritorio encima")

	# Computadora sobre el escritorio.
	await press.call("basic_computer")
	await _click(at_cell.call(Vector2i(4, 5)))
	_expect(OfficeState.furniture[_index_at(Vector2i(4, 5))]["computer"] == "basic_computer"
		and Economy.balance == money - 500, "instalar la computadora con el ratón")

	# Girar con la herramienta.
	await press.call(BuildController.TOOL_ROTATE)
	await _click(at_cell.call(Vector2i(4, 5)))
	_expect(OfficeState.furniture[_index_at(Vector2i(4, 5))]["rotation"] == 2, "girar con el ratón")

	# Silla y planta; la planta frente a la puerta de la oficina se rechaza.
	await press.call("basic_chair")
	money = Economy.balance
	await _click(at_cell.call(Vector2i(4, 6)))
	_expect(_index_at(Vector2i(4, 6)) >= 0 and Economy.balance == money - 60, "colocar la silla con el ratón")
	await press.call("small_plant")
	money = Economy.balance
	await _click(at_cell.call(Vector2i(1, 3)))
	_expect(_index_at(Vector2i(1, 3)) < 0 and Economy.balance == money, "la planta bloqueó la puerta de la oficina")
	await _click(at_cell.call(Vector2i(0, 7)))
	_expect(_index_at(Vector2i(0, 7)) >= 0 and Economy.balance == money - 40, "colocar la planta con el ratón")

	# Vender con el ratón: computadora y luego escritorio, al 50%.
	await press.call(BuildController.TOOL_SELL)
	money = Economy.balance
	await _click(at_cell.call(Vector2i(4, 5)))
	await _click(at_cell.call(Vector2i(4, 5)))
	_expect(_index_at(Vector2i(4, 5)) < 0 and Economy.balance == money + 250 + 75, "vender computadora y escritorio")

	# El CEO no atraviesa los muebles nuevos.
	var path: Array[Vector2i] = game.ceo.get_path_cells()
	for cell: Vector2i in path:
		_expect(cell == OfficeState.find_furniture_assigned_to("ceo")["cell"] or _index_at(cell) < 0,
			"el camino del CEO pasa por el mueble de %s" % cell)
	_expect(_count_views(grid) == OfficeState.furniture.size(), "los muebles dibujados no coinciden con los guardados")

	# Guardar y restaurar los muebles (con su rotación y computadora).
	var saved: Dictionary = JSON.parse_string(JSON.stringify(OfficeState.export_state()))
	var before: String = JSON.stringify(OfficeState.export_state())
	OfficeState.import_state(saved)
	_expect(JSON.stringify(OfficeState.export_state()) == before, "los muebles no se restauraron igual")
	game.queue_free()
	await get_tree().process_frame


func _count_views(grid: OfficeGrid) -> int:
	var count: int = 0
	for child: Node in grid.get_node("Objects").get_children():
		if child is FurnitureView and child.part == FurnitureView.PART_MAIN and not child.is_queued_for_deletion():
			count += 1
	return count
