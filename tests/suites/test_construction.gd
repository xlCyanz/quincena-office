# Prueba del hito 5: modo construcción. Las paredes bloquean el paso, las
# puertas lo permiten y cada acción cobra o devuelve dinero; el modo pausa el tiempo.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=construction
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const WALL: String = ConstructionCatalog.WALL
const DOOR: String = ConstructionCatalog.DOOR

var _failures: int = 0
var _checks: int = 0
var _office_changes: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	EventBus.office_changed.connect(func() -> void: _office_changes += 1)
	_check_prices()
	_check_builder()
	_check_pathfinder_walls_and_doors()
	await _check_build_mode_in_game()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _edge_change(edge: Vector3i, kind: String) -> Array[Dictionary]:
	return [{"edge": edge, "kind": kind}]


func _floor_change(cell: Vector2i, kind: String) -> Array[Dictionary]:
	return [{"cell": cell, "kind": kind}]


func _check_prices() -> void:
	_expect(ConstructionCatalog.get_price(WALL) == 50 and ConstructionCatalog.get_price(DOOR) == 200,
		"precios de pared y puerta")
	_expect(ConstructionCatalog.get_price("carpet") == 15 and ConstructionCatalog.get_price("wood") == 25
		and ConstructionCatalog.get_price("ceramic") == 35, "precios de los pisos")
	_expect(ConstructionCatalog.get_refund(WALL) == 25 and ConstructionCatalog.get_refund("ceramic") == 17,
		"la venta devuelve el 50% (redondeado hacia abajo)")


# Cada acción cobra o devuelve exactamente lo que dice el catálogo.
func _check_builder() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	var edge := Vector3i(4, 2, GridEdge.AXIS_X)  # borde interior libre
	var money: int = Economy.balance
	_office_changes = 0

	var result: Dictionary = builder.apply(_edge_change(edge, WALL))
	_expect(result["ok"] and Economy.balance == money - 50 and OfficeState.get_edge(edge) == WALL,
		"pared nueva: %s, saldo %d" % [result, Economy.balance])
	_expect(_office_changes == 1, "office_changed no se emitió al construir")
	money = Economy.balance

	result = builder.apply(_edge_change(edge, WALL))
	_expect(not result["ok"] and Economy.balance == money, "poner una pared donde ya hay una no debe cobrar")

	result = builder.apply(_edge_change(edge, DOOR))
	_expect(result["ok"] and Economy.balance == money - 200 + 25 and OfficeState.get_edge(edge) == DOOR,
		"puerta sobre una pared (vende la pared): %s, saldo %d" % [result, Economy.balance])
	money = Economy.balance

	result = builder.apply(_edge_change(edge, ""))
	_expect(result["ok"] and Economy.balance == money + 100 and OfficeState.get_edge(edge).is_empty(),
		"vender la puerta: %s" % [result])
	money = Economy.balance

	var cell := Vector2i(4, 5)
	result = builder.apply(_floor_change(cell, "carpet"))
	_expect(result["ok"] and Economy.balance == money - 15 + 17 and OfficeState.get_floor(cell) == "carpet",
		"cambiar cerámica por alfombra: %s" % [result])
	money = Economy.balance
	# El contorno del local (paredes y entrada) no se compra ni se vende.
	var entrance_edge := Vector3i(OfficeState.entrance.x, OfficeState.entrance.y, GridEdge.AXIS_Y)
	for pair: Array in [[Vector3i(5, 3, GridEdge.AXIS_X), ""], [Vector3i(5, 3, GridEdge.AXIS_X), DOOR],
			[entrance_edge, ""], [entrance_edge, WALL]]:
		var outline_edge: Vector3i = pair[0]
		var before: String = OfficeState.get_edge(outline_edge)
		result = builder.apply(_edge_change(outline_edge, pair[1]))
		_expect(not result["ok"] and Economy.balance == money and OfficeState.get_edge(outline_edge) == before,
			"cambiar el contorno en %s: %s" % [outline_edge, result])

	# Un piso no se quita: solo se cambia por otro.
	result = builder.apply(_floor_change(cell, ConstructionCatalog.BARE_FLOOR))
	_expect(not result["ok"] and Economy.balance == money and OfficeState.get_floor(cell) == "carpet",
		"quitar la alfombra no debería poderse: %s" % [result])
	result = builder.apply(_floor_change(cell, "wood"))
	_expect(result["ok"] and Economy.balance == money - 25 + 7 and OfficeState.get_floor(cell) == "wood",
		"madera sobre la alfombra: %s" % [result])
	money = Economy.balance

	# Una fila de paredes se cobra entera o no se hace.
	var row: Array[Dictionary] = []
	for y: int in range(3, 6):
		row.append({"edge": Vector3i(4, y, GridEdge.AXIS_X), "kind": WALL})
	Economy.import_state({"balance": 120})
	result = builder.apply(row)
	_expect(not result["ok"] and Economy.balance == 120, "sin dinero suficiente no debe cobrar nada")
	for change: Dictionary in row:
		_expect(OfficeState.get_edge(change["edge"]).is_empty(), "sin dinero se construyó %s" % change["edge"])
	Economy.import_state({"balance": 150})
	result = builder.apply(row)
	_expect(result["ok"] and Economy.balance == 0, "con el dinero justo se construye la fila: %s" % [result])
	Economy.import_state({"balance": money})

	# Fuera del local no se construye.
	result = builder.apply(_edge_change(Vector3i(10, 10, GridEdge.AXIS_X), WALL))
	_expect(not result["ok"], "se construyó fuera del local")
	result = builder.apply(_floor_change(Vector2i(-3, 0), "wood"))
	_expect(not result["ok"], "se puso piso fuera del local")

	# No se puede dejar al CEO sin acceso a su escritorio ni cerrar la entrada.
	var office_door := Vector3i(1, 2, GridEdge.AXIS_Y)
	money = Economy.balance
	result = builder.apply(_edge_change(office_door, WALL))
	_expect(not result["ok"] and OfficeState.get_edge(office_door) == DOOR and Economy.balance == money,
		"se cerró la puerta de la Oficina Ejecutiva: %s" % [result])
	var entrance_door: Vector3i = GridEdge.between(OfficeState.entrance, OfficeState.get_outside_of_entrance())
	result = builder.apply(_edge_change(entrance_door, WALL))
	_expect(not result["ok"] and OfficeState.get_edge(entrance_door) == DOOR, "se tapió la puerta de entrada")


# Con AStarGrid2D a doble resolución: las paredes cortan el paso y las puertas no.
func _check_pathfinder_walls_and_doors() -> void:
	var lot := Lot.from_rect(Rect2i(0, 0, 6, 8))
	var edges: Dictionary[Vector3i, String] = {}
	for y: int in range(lot.get_bounds().size.y):
		edges[Vector3i(2, y, GridEdge.AXIS_X)] = WALL  # muro entre las columnas 2 y 3
	edges[Vector3i(2, 6, GridEdge.AXIS_X)] = DOOR
	var finder := OfficePathfinder.new()
	finder.build(lot, [], edges)
	_expect(not finder.can_cross(Vector2i(2, 0), Vector2i(3, 0)), "se puede cruzar una pared")
	_expect(finder.can_cross(Vector2i(2, 6), Vector2i(3, 6)), "no se puede cruzar una puerta")
	_expect(finder.can_cross(Vector2i(0, 0), Vector2i(0, 1)), "no se puede cruzar un borde libre")
	var path: Array[Vector2i] = finder.find_path(Vector2i(2, 0), Vector2i(3, 0))
	_expect(path.size() == 1 + 6 + 1 + 6, "el rodeo por la puerta debería tener 14 casillas, tiene %d" % path.size())
	var crossed_door: bool = false
	for i: int in range(1, path.size()):
		var step: Vector2i = (path[i] - path[i - 1]).abs()
		_expect(step.x + step.y == 1, "salto en el camino de %s a %s" % [path[i - 1], path[i]])
		var edge: Vector3i = GridEdge.between(path[i - 1], path[i])
		_expect(edges.get(edge, "") != WALL, "el camino cruza la pared %s" % edge)
		crossed_door = crossed_door or edges.get(edge, "") == DOOR
	_expect(crossed_door, "el camino no pasa por la puerta")
	edges[Vector3i(2, 6, GridEdge.AXIS_X)] = WALL
	finder.build(lot, [], edges)
	_expect(finder.find_path(Vector2i(2, 0), Vector2i(3, 0)).is_empty(), "sin puerta no debería haber camino")
	# El contorno del local está cerrado aunque no tenga paredes.
	finder.build(lot, [], {})
	_expect(not finder.can_cross(Vector2i(0, 0), Vector2i(-1, 0)), "se puede salir del local por un borde")


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame


func _mouse_button(at: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event


func _mouse_motion(at: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event


func _click(at: Vector2) -> void:
	await _push(_mouse_button(at, true))
	await _push(_mouse_button(at, false))


func _drag(from: Vector2, to: Vector2) -> void:
	await _push(_mouse_motion(from, Vector2.ZERO))
	await _push(_mouse_button(from, true))
	var steps: int = 6
	for i: int in range(1, steps + 1):
		var point: Vector2 = from.lerp(to, float(i) / steps)
		await _push(_mouse_motion(point, (to - from) / steps))
	await _push(_mouse_button(to, false))


# Todo con el ratón dentro del juego: Construir, elegir herramienta, arrastrar, vender, Salir.
func _check_build_mode_in_game() -> void:
	SaveManager.new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameClock.stop()  # el tiempo se mueve a mano
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var camera: OfficeCamera = game.get_node("OfficeCamera")
	var panel: BuildPanel = game.get_node("BuildPanel")
	var ceo: Ceo = game.ceo
	var to_screen: Callable = func(grid_position: Vector2) -> Vector2:
		return grid.get_canvas_transform() * grid.grid_to_world(grid_position)

	# Entrar: clic en "Construir".
	_expect(not GameClock.is_paused, "el juego empieza en pausa")
	await _click(panel.get_open_button().get_global_rect().get_center())
	_expect(panel.is_build_mode(), "el clic en Construir no abrió el modo construcción")
	_expect(GameClock.is_paused and GameClock.get_time_scale() == 0.0, "el modo construcción no pausó el tiempo")
	var key := InputEventKey.new()
	key.keycode = KEY_3
	key.pressed = true
	await _push(key)
	_expect(GameClock.is_paused, "en modo construcción el atajo 3 quitó la pausa")

	# Paredes: arrastrar a lo largo del borde x = 4.5, de la fila 1 a la 4 (4 piezas).
	var money: int = Economy.balance
	var walls_before: int = _count_pieces(grid)
	var camera_before: Vector2 = camera.position
	await _drag(to_screen.call(Vector2(4.5, 1.0)), to_screen.call(Vector2(4.5, 4.0)))
	for y: int in range(1, 5):
		_expect(OfficeState.get_edge(Vector3i(4, y, GridEdge.AXIS_X)) == WALL, "falta la pared en la fila %d" % y)
	_expect(Economy.balance == money - 4 * 50, "4 paredes deberían costar $200; saldo %d → %d" % [money, Economy.balance])
	_expect(_count_pieces(grid) == walls_before + 4, "no se dibujaron las 4 paredes nuevas")
	_expect(camera.position == camera_before, "arrastrar para construir movió la cámara")

	# Puerta: clic en el borde del medio.
	await _click(panel.get_tool_button(BuildController.TOOL_DOOR).get_global_rect().get_center())
	money = Economy.balance
	await _click(to_screen.call(Vector2(4.5, 2.0)))
	_expect(OfficeState.get_edge(Vector3i(4, 2, GridEdge.AXIS_X)) == DOOR and Economy.balance == money - 175,
		"la puerta sobre la pared debería costar $175; saldo %d → %d" % [money, Economy.balance])

	# Piso: arrastrar alfombra de (3, 4) a (4, 5).
	await _click(panel.get_tool_button("carpet").get_global_rect().get_center())
	money = Economy.balance
	await _drag(to_screen.call(Vector2(3.0, 4.0)), to_screen.call(Vector2(4.0, 5.0)))
	for cell: Vector2i in [Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 5), Vector2i(4, 5)]:
		_expect(OfficeState.get_floor(cell) == "carpet", "la casilla %s no quedó con alfombra" % cell)
	_expect(Economy.balance == money + 4 * (17 - 15), "4 casillas de alfombra sobre cerámica: saldo %d → %d" % [
		money, Economy.balance])

	# Vender: clic sobre una pared.
	await _click(panel.get_tool_button(BuildController.TOOL_SELL).get_global_rect().get_center())
	money = Economy.balance
	await _click(to_screen.call(Vector2(4.5, 4.0)))
	_expect(OfficeState.get_edge(Vector3i(4, 4, GridEdge.AXIS_X)).is_empty() and Economy.balance == money + 25,
		"vender una pared debería devolver $25; saldo %d → %d" % [money, Economy.balance])

	# Una pared que encierra al CEO se rechaza y no cobra.
	await _click(panel.get_tool_button(BuildController.TOOL_WALL).get_global_rect().get_center())
	money = Economy.balance
	await _click(to_screen.call(Vector2(1.0, 2.5)))
	_expect(OfficeState.get_edge(Vector3i(1, 2, GridEdge.AXIS_Y)) == DOOR and Economy.balance == money,
		"se tapió la puerta de la Oficina Ejecutiva con el ratón")

	# El CEO, que va de camino, rodea las paredes nuevas.
	var path: Array[Vector2i] = ceo.get_path_cells()
	var previous: Vector2i = ceo.get_cell()
	for cell: Vector2i in path:
		_expect(not OfficeState.blocks_passage(GridEdge.between(previous, cell)),
			"el camino del CEO cruza una pared entre %s y %s" % [previous, cell])
		previous = cell

	# Salir: el tiempo vuelve a correr.
	await _click(panel.get_exit_button().get_global_rect().get_center())
	_expect(not panel.is_build_mode() and not GameClock.is_paused, "al salir el tiempo no volvió a correr")

	# Con la cámara, el botón izquierdo vuelve a arrastrar.
	camera_before = camera.position
	var center: Vector2 = get_viewport().get_visible_rect().size / 2.0
	await _drag(center, center + Vector2(40.0, 0.0))
	_expect(camera.position != camera_before, "fuera del modo construcción el botón izquierdo no mueve la cámara")
	game.queue_free()
	await get_tree().process_frame


func _count_pieces(grid: OfficeGrid) -> int:
	var count: int = 0
	for child: Node in grid.get_node("Objects").get_children():
		if child is EdgePieceView and not child.is_queued_for_deletion():
			count += 1
	return count
