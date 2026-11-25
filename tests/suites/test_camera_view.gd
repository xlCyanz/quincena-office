# Mapa y cámara: zoom suave por niveles, inercia al soltar un arrastre, teclado y borde de la
# pantalla, paredes de atrás altas y el mapa de alrededor (pasto, camino, acera, calle, árboles, límite).
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=camera_view
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const SCREEN := Vector2(1280, 720)

var _failures: int = 0
var _checks: int = 0
var _aspect_before: Window.ContentScaleAspect
var _actions: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_packed.call_deferred(GAME_SCENE)
		return
	SaveManager.save_dir = "user://test_saves"
	_aspect_before = get_tree().root.content_scale_aspect
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	EventBus.ui_action.connect(func(action: String) -> void: _actions.append(action))
	_check_options()
	await _check_zoom()
	await _check_inertia()
	await _check_keyboard_and_edges()
	await _check_fixed_view()
	await _check_map()
	await _check_save()
	await _check_menu_bar()
	get_tree().root.content_scale_aspect = _aspect_before
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _wait(frames: int = 2) -> void:
	for i: int in range(frames):
		await get_tree().process_frame


func _open_game() -> Node:
	SaveManager.new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await _wait()
	GameClock.stop()
	return game


func _close_game(game: Node) -> void:
	game.queue_free()
	await _wait(1)


# Espera a que termine la animación de la cámara (con tope).
func _settle(camera: OfficeCamera, max_frames: int = 240) -> void:
	for i: int in range(max_frames):
		if not camera.is_moving():
			return
		await get_tree().process_frame


func _push_mouse_button(button: MouseButton, pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	event.factor = 1.0
	get_viewport().push_input(event, true)


func _push_mouse_motion(from: Vector2, to: Vector2, mask: MouseButtonMask) -> void:
	var event := InputEventMouseMotion.new()
	event.position = to
	event.relative = to - from
	event.button_mask = mask
	get_viewport().push_input(event, true)


# Tecla por su lugar en el teclado (así llega a Input y a _unhandled_key_input).
func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _in_map(grid: OfficeGrid, point: Vector2) -> bool:
	var local: Vector2 = grid.get_site_world_area().affine_inverse() * point
	return local.x >= -0.0001 and local.x <= 1.0001 and local.y >= -0.0001 and local.y <= 1.0001


func _check_options() -> void:
	Settings.reset_to_defaults()
	_expect(bool(Settings.get_value("smooth_camera")) and bool(Settings.get_value("edge_pan")),
		"cámara suave y borde de la pantalla encendidos por defecto")
	var options := OptionsList.new()
	add_child(options)
	_expect(options.get_toggle("smooth_camera").text == "Cámara suave", "opción Cámara suave")
	_expect(options.get_toggle("edge_pan").text == "Mover la cámara con el borde de la pantalla",
		"opción del borde de la pantalla")
	options.get_toggle("smooth_camera").button_pressed = false
	_expect(not bool(Settings.get_value("smooth_camera")), "la casilla apaga la cámara suave")
	Settings.reset_to_defaults()
	options.queue_free()
	var levels: Array[float] = GameConstants.CAMERA_ZOOM_LEVELS
	_expect(levels.size() == 11 and levels[0] == 0.25 and levels[levels.size() - 1] == 4.0,
		"11 niveles de zoom de 0.25 a 4: %s" % [levels])
	_expect(levels[GameConstants.CAMERA_START_ZOOM_INDEX] == 2.0, "el nivel de referencia sigue en 2")
	for i: int in range(1, levels.size()):
		_expect(levels[i] > levels[i - 1], "niveles en orden: %s" % levels[i])


func _check_zoom() -> void:
	var game: Node = await _open_game()
	var camera: OfficeCamera = game.get_node("OfficeCamera")
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	_expect(camera.is_smooth(), "la cámara es suave en esta parte")
	camera.finish_motion()
	# Al alejarse del todo se ve el solar completo.
	var site_area: Transform2D = grid.get_site_world_area()
	var site_box := Rect2(site_area.origin, Vector2.ZERO)
	for corner: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		site_box = site_box.expand(site_area * corner)
	_expect(site_box.size.x * GameConstants.CAMERA_ZOOM_LEVELS[0] <= SCREEN.x
		and site_box.size.y * GameConstants.CAMERA_ZOOM_LEVELS[0] <= SCREEN.y,
		"con el zoom mínimo entra todo el solar: %s" % site_box.size)

	# Rueda: el nivel cambia enseguida, lo que se ve llega animado y la casilla bajo el ratón queda fija.
	camera.import_state({"zoom": 2.0, "x": grid.get_lot_world_rect().get_center().x,
		"y": grid.get_lot_world_rect().get_center().y})
	var cell := Vector2i(2, 3)
	var anchor: Vector2 = grid.get_canvas_transform() * grid.cell_to_world(cell)
	var world_before: Vector2 = grid.screen_to_world(anchor)
	_actions.clear()
	_push_mouse_button(MOUSE_BUTTON_WHEEL_UP, true, anchor)
	_expect(camera.get_zoom_level() == 2.5 and camera.get_shown_zoom() == 2.0 and camera.is_moving(),
		"la rueda cambia el nivel y empieza la animación: %s / %s" % [camera.get_zoom_level(), camera.get_shown_zoom()])
	_expect(_actions.has("camera_moved"), "el zoom avisa al tutorial")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(camera.get_shown_zoom() > 2.0 and camera.get_shown_zoom() < 2.5,
		"a mitad de la animación el zoom está entre los niveles: %s" % camera.get_shown_zoom())
	_expect(grid.screen_to_world(anchor).distance_to(world_before) < 0.05,
		"a mitad de la animación el punto bajo el ratón no se mueve")
	await _settle(camera)
	_expect(camera.zoom == Vector2.ONE * 2.5 and not camera.is_moving(), "la animación termina en 2.5: %s" % camera.zoom)
	_expect(grid.screen_to_cell(anchor) == cell and grid.screen_to_world(anchor).distance_to(world_before) < 0.05,
		"al terminar sigue la misma casilla bajo el ratón")
	for i: int in range(3):
		_push_mouse_button(MOUSE_BUTTON_WHEEL_UP, true, anchor)
	_expect(camera.get_zoom_level() == 4.0, "tres pasos más llegan al máximo")
	await _settle(camera)
	_expect(camera.zoom == Vector2.ONE * 4.0, "zoom máximo animado: %s" % camera.zoom)
	# Guardar a mitad de la animación guarda el destino.
	_push_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, SCREEN / 2.0)
	var state: Dictionary = camera.export_state()
	_expect(float(state["zoom"]) == 3.0, "se guarda el nivel de destino: %s" % state)
	await _settle(camera)
	_expect(Vector2(state["x"], state["y"]).distance_to(camera.position) < 0.5, "y el centro donde termina")
	# Partidas viejas: zoom_index en la lista vieja (3 = 2.0).
	camera.import_state({"zoom_index": 3, "x": 0.0, "y": 0.0})
	_expect(camera.get_zoom_level() == 2.0 and camera.zoom == Vector2.ONE * 2.0 and not camera.is_moving(),
		"zoom_index viejo 3 → 2.0: %s" % camera.get_zoom_level())
	camera.import_state({"zoom_index": 0})
	_expect(camera.get_zoom_level() == 0.5, "zoom_index viejo 0 → 0.5")
	camera.import_state({"zoom": 0.25, "x": site_area.origin.x, "y": site_area.origin.y})
	game.frame_office()
	_expect(camera.is_moving(), "Ver oficina se anima")
	await _settle(camera)
	var lot_rect: Rect2 = grid.get_lot_world_rect()
	_expect(camera.position.distance_to(lot_rect.get_center()) < 0.6 and camera.zoom.x == camera.get_zoom_level(),
		"el encuadre animado termina centrado: %s vs %s" % [camera.position, lot_rect.get_center()])
	Settings.set_value("smooth_camera", false)
	_push_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, SCREEN / 2.0)
	_expect(camera.zoom.x == camera.get_zoom_level() and not camera.is_moving(), "sin cámara suave el zoom salta")
	Settings.reset_to_defaults()
	await _close_game(game)


func _check_inertia() -> void:
	var game: Node = await _open_game()
	var camera: OfficeCamera = game.get_node("OfficeCamera")
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var center: Vector2 = grid.get_lot_world_rect().get_center()
	camera.import_state({"zoom": 1.0, "x": center.x, "y": center.y})
	var at: Vector2 = SCREEN / 2.0
	_push_mouse_button(MOUSE_BUTTON_MIDDLE, true, at)
	for i: int in range(4):
		await get_tree().process_frame
		_push_mouse_motion(at, at + Vector2(30, 0), MOUSE_BUTTON_MASK_MIDDLE)
		at += Vector2(30, 0)
	var released: Vector2 = camera.position
	_push_mouse_button(MOUSE_BUTTON_MIDDLE, false, at)
	_expect(camera.is_moving(), "al soltar un arrastre rápido sigue con inercia")
	await _wait(3)
	_expect(camera.position.x < released.x, "la inercia sigue hacia donde se arrastró: %s → %s" % [released, camera.position])
	await _settle(camera)
	_expect(not camera.is_moving() and _in_map(grid, camera.position), "la inercia se frena dentro del mapa")
	camera.import_state({"zoom": 1.0, "x": center.x, "y": center.y})
	at = SCREEN / 2.0
	_push_mouse_button(MOUSE_BUTTON_MIDDLE, true, at)
	await get_tree().process_frame
	_push_mouse_motion(at, at + Vector2(40, 0), MOUSE_BUTTON_MASK_MIDDLE)
	_push_mouse_button(MOUSE_BUTTON_MIDDLE, false, at + Vector2(40, 0))
	_push_mouse_button(MOUSE_BUTTON_RIGHT, true, at)
	_expect(not camera.is_moving(), "un clic corta la inercia")
	_push_mouse_button(MOUSE_BUTTON_RIGHT, false, at)
	_push_mouse_button(MOUSE_BUTTON_MIDDLE, true, at)
	await get_tree().process_frame
	_push_mouse_motion(at, at + Vector2(40, 0), MOUSE_BUTTON_MASK_MIDDLE)
	await get_tree().create_timer(0.2).timeout
	_push_mouse_button(MOUSE_BUTTON_MIDDLE, false, at + Vector2(40, 0))
	_expect(not camera.is_moving(), "soltar tras quedarse quieto no deja inercia")
	var area: Transform2D = grid.get_site_world_area()
	camera.import_state({"zoom": 1.0, "x": (area * Vector2(0.02, 0.5)).x, "y": (area * Vector2(0.02, 0.5)).y})
	at = SCREEN / 2.0
	_push_mouse_button(MOUSE_BUTTON_MIDDLE, true, at)
	for i: int in range(3):
		await get_tree().process_frame
		_push_mouse_motion(at, at + Vector2(60, -30), MOUSE_BUTTON_MASK_MIDDLE)
		at += Vector2(60, -30)
	_push_mouse_button(MOUSE_BUTTON_MIDDLE, false, at)
	await _settle(camera)
	_expect(_in_map(grid, camera.position) and not camera.is_moving(), "la inercia no saca la vista del mapa")
	await _close_game(game)


func _check_keyboard_and_edges() -> void:
	var game: Node = await _open_game()
	var camera: OfficeCamera = game.get_node("OfficeCamera")
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var center: Vector2 = grid.get_lot_world_rect().get_center()
	camera.import_state({"zoom": 1.0, "x": center.x, "y": center.y})
	_actions.clear()
	for key: Key in [KEY_W, KEY_UP]:
		camera.import_state({"zoom": 1.0, "x": center.x, "y": center.y})
		_key(key, true)
		_expect(camera.get_key_pan_direction() == Vector2.UP, "%s mueve hacia arriba" % OS.get_keycode_string(key))
		await _wait(5)
		_key(key, false)
		_expect(camera.position.y < center.y - 1.0 and is_equal_approx(camera.position.x, center.x),
			"con %s la cámara sube: %s" % [OS.get_keycode_string(key), camera.position])
	_expect(_actions.has("camera_moved"), "las teclas avisan al tutorial")
	_key(KEY_D, true)
	_key(KEY_S, true)
	_expect(camera.get_key_pan_direction().is_equal_approx(Vector2(1, 1).normalized()), "D y S juntas en diagonal")
	_key(KEY_D, false)
	_key(KEY_S, false)
	_expect(camera.get_key_pan_direction() == Vector2.ZERO, "sin teclas no se mueve")
	var field := LineEdit.new()
	game.get_node("Hud").add_child(field)
	field.grab_focus()
	_key(KEY_A, true)
	_expect(camera.get_key_pan_direction() == Vector2.ZERO, "con un campo de texto activo A no mueve")
	_key(KEY_A, false)
	field.queue_free()
	game.set_pause_menu_open(true)
	camera.import_state({"zoom": 1.0, "x": center.x, "y": center.y})
	_key(KEY_W, true)
	await _wait(4)
	_key(KEY_W, false)
	_expect(camera.position == center, "con la pausa abierta las teclas no mueven la cámara")
	game.set_pause_menu_open(false)
	# Borde de la pantalla: sin ventana se prueba la regla.
	var size: Vector2 = SCREEN
	_expect(camera.get_edge_pan_direction(Vector2(3, 360), size) == Vector2.LEFT, "borde izquierdo")
	_expect(camera.get_edge_pan_direction(Vector2(1278, 360), size) == Vector2.RIGHT, "borde derecho")
	_expect(camera.get_edge_pan_direction(Vector2(640, 2), size) == Vector2.UP, "borde de arriba")
	_expect(camera.get_edge_pan_direction(Vector2(2, 2), size).is_equal_approx(Vector2(-1, -1).normalized()), "esquina")
	_expect(camera.get_edge_pan_direction(Vector2(640, 360), size) == Vector2.ZERO, "en el medio no")
	_expect(camera.get_edge_pan_direction(Vector2(-5, 360), size) == Vector2.ZERO, "fuera de la ventana no")
	Settings.set_value("edge_pan", false)
	_expect(camera.get_edge_pan_direction(Vector2(3, 360), size) == Vector2.ZERO, "con la opción apagada no")
	Settings.reset_to_defaults()
	camera.import_state({"zoom": 1.0, "x": center.x, "y": center.y})
	await _wait(4)
	_expect(camera.position == center, "sin ventana el borde no mueve la cámara")
	await _close_game(game)


# La vista no gira: las paredes de atrás (contorno con el exterior detrás) van altas y las demás bajas.
func _check_fixed_view() -> void:
	var game: Node = await _open_game()
	var camera: OfficeCamera = game.get_node("OfficeCamera")
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var builder: Builder = game.get_node("BuildController").builder
	_expect(not "view_rotation" in grid and not game.has_method("rotate_view"), "no hay giro de la vista")
	camera.finish_motion()
	var before: Vector2 = camera.position
	var key := InputEventKey.new()
	for code: Key in [KEY_Q, KEY_E]:
		key.physical_keycode = code
		key.keycode = code
		key.pressed = true
		get_viewport().push_input(key)
	await _wait()
	camera.finish_motion()
	_expect(camera.position == before, "Q y E no hacen nada")
	var lot: Rect2i = grid.get_lot_rect()
	var round_trip: bool = true
	for x: int in range(lot.position.x, lot.end.x):
		for y: int in range(lot.position.y, lot.end.y):
			if grid.world_to_cell(grid.cell_to_world(Vector2i(x, y))) != Vector2i(x, y):
				round_trip = false
	_expect(round_trip, "casilla → píxel → casilla")
	Economy.earn(5000, "Prueba")
	var inner := Vector3i(lot.position.x + 2, lot.position.y + 4, GridEdge.AXIS_X)
	builder.apply([{"edge": inner, "kind": ConstructionCatalog.WALL}])
	await _wait()
	var back := Vector3i(lot.position.x + 2, lot.position.y - 1, GridEdge.AXIS_Y)  # norte: el exterior queda detrás
	var front := Vector3i(lot.position.x + 2, lot.end.y - 1, GridEdge.AXIS_Y)  # sur: el exterior queda delante
	_expect(grid.is_back_edge(back) and not grid.is_back_edge(front) and not grid.is_back_edge(inner),
		"atrás el norte; el sur y lo interior no")
	var views: Dictionary = {}
	for child: Node in grid.get_node("Objects").get_children():
		if child is EdgePieceView:
			views[child.edge] = child
	var low: float = ConstructionCatalog.get_low_wall_height()
	var tall: float = float(ConstructionCatalog.get_edge_piece(ConstructionCatalog.WALL)["height"])
	_expect(views.has(back) and views[back].tall and is_equal_approx(views[back].get("_height"), tall), "la pared de atrás va alta")
	_expect(views.has(front) and not views[front].tall and is_equal_approx(views[front].get("_height"), low), "la de adelante, baja")
	_expect(views.has(inner) and not views[inner].tall, "la interior, baja")
	_expect(tall > 40.0 and low < 16.0, "alta más que una persona y baja casi al piso: %d / %d" % [tall, low])
	await _close_game(game)


func _check_map() -> void:
	var game: Node = await _open_game()
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var site: Rect2i = OfficeState.site_rect
	var plan: Dictionary = grid.get_map_plan()
	var tiles: Dictionary = plan["tiles"]
	var data: Dictionary = MapDecor.get_data()
	var surround: int = int(data["surround_width"])
	var outer: Rect2i = site.grow(surround)
	_expect(tiles.size() == outer.get_area() - OfficeState.lot.get_area(), "el plano cubre todo menos el local")
	var exit: Vector2i = OfficeState.get_outside_of_entrance() - OfficeState.entrance
	var step: Vector2i = OfficeState.get_outside_of_entrance()
	var path_ok: bool = true
	var path_length: int = 0
	while site.has_point(step):
		path_ok = path_ok and tiles.get(step, "") == MapDecor.PATH
		step += exit
		path_length += 1
	_expect(path_ok and path_length > 0, "camino de la entrada al borde del solar (%d casillas)" % path_length)
	var sidewalk: int = int(data["sidewalk_width"])
	var road: int = int(data["road_width"])
	_expect(tiles.get(step, "") == MapDecor.SIDEWALK, "acera al salir del solar: %s" % tiles.get(step, ""))
	var road_styles: Dictionary = {}
	for i: int in range(road):
		var row_cell: Vector2i = step + exit * (sidewalk + i)
		for along: int in range(-3, 4):
			var cell: Vector2i = row_cell + Vector2i(exit.y, exit.x) * along
			road_styles[tiles.get(cell, "")] = true
	_expect(road_styles.has(MapDecor.ROAD) and road_styles.has(MapDecor.ROAD_LINE) and road_styles.size() == 2,
		"la calle tiene asfalto y línea: %s" % [road_styles.keys()])
	var opposite: Vector2i = site.position - Vector2i(2, 2) if exit.x + exit.y > 0 else site.end + Vector2i(1, 1)
	_expect(tiles.get(opposite, "") == MapDecor.OUTSIDE, "esquina contraria: pasto de afuera (%s)" % tiles.get(opposite, ""))
	var grass_ok: bool = true
	for cell: Vector2i in tiles:
		if site.has_point(cell) and tiles[cell] != MapDecor.GRASS and tiles[cell] != MapDecor.PATH:
			grass_ok = false
		if not site.has_point(cell) and (tiles[cell] == MapDecor.GRASS or tiles[cell] == MapDecor.PATH):
			grass_ok = false
	_expect(grass_ok, "dentro del solar pasto o camino; fuera, lo de afuera")
	var around: TileMapLayer = grid.get_node("Surroundings")
	_expect(around.get_used_cells().size() == outer.get_area() - site.get_area(), "capa de alrededor: %d" % around.get_used_cells().size())
	_expect(around.get_index() < grid.get_node("Floor").get_index(), "alrededor debajo del piso")
	var trees: Array[TreeView] = grid.get_trees()
	var margin: int = int(data["trees"]["lot_margin"])
	var trees_ok: bool = trees.size() > 20
	var inside_site: int = 0
	for tree: TreeView in trees:
		var style: String = tiles.get(tree.cell, "")
		if style != MapDecor.GRASS and style != MapDecor.OUTSIDE:
			trees_ok = false
		if site.has_point(tree.cell):
			inside_site += 1
			for cell: Vector2i in OfficeState.lot.get_cells():
				if maxi(absi(cell.x - tree.cell.x), absi(cell.y - tree.cell.y)) < margin:
					trees_ok = false
	_expect(trees_ok and inside_site > 0, "%d árboles (%d en el solar) bien puestos" % [trees.size(), inside_site])
	_expect(MapDecor.plan(site, OfficeState.lot, OfficeState.get_outside_of_entrance(), OfficeState.edges) == plan,
		"el plano no cambia solo")
	var border: PackedVector2Array = grid.get_site_border().get_corners()
	var area: Transform2D = grid.get_site_world_area()
	var border_ok: bool = border.size() == 4
	for corner: Vector2 in border:
		var local: Vector2 = area.affine_inverse() * corner
		border_ok = border_ok and absf(local.x - roundf(local.x)) < 0.001 and absf(local.y - roundf(local.y)) < 0.001
	_expect(border_ok, "el borde marca las esquinas del solar")
	Economy.earn(200000, "Prueba")
	var builder: Builder = game.get_node("BuildController").builder
	var quote: Dictionary = builder.quote_land("east", 6, OfficeState.lot.get_bounds().size.y, 0)
	_expect(quote.get("ok", false), "se puede comprar terreno al este: %s" % quote.get("message", ""))
	_expect(builder.buy_land("east", 6, OfficeState.lot.get_bounds().size.y, 0)["ok"], "comprar terreno")
	await _wait()
	var after: Array[TreeView] = grid.get_trees()
	var cleared: bool = true
	for tree: TreeView in after:
		if OfficeState.lot.has_point(tree.cell):
			cleared = false
	_expect(cleared and grid.get_map_plan() != plan, "el mapa se rehace al comprar terreno")
	await _close_game(game)


func _check_save() -> void:
	var game: Node = await _open_game()
	var camera: OfficeCamera = game.get_node("OfficeCamera")
	camera.set_zoom_index(4, SCREEN / 3.0)
	_expect(SaveManager.save_game("slot_5"), "guardar")
	var camera_state: Dictionary = camera.export_state()
	await _close_game(game)
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	var loaded: Node = GAME_SCENE.instantiate()
	add_child(loaded)
	await _wait()
	GameClock.stop()
	var restored: Dictionary = loaded.get_node("OfficeCamera").export_state()
	_expect(is_equal_approx(float(restored["zoom"]), float(camera_state["zoom"]))
		and Vector2(restored["x"], restored["y"]).distance_to(Vector2(camera_state["x"], camera_state["y"])) < 0.01,
		"la cámara vuelve igual: %s vs %s" % [restored, camera_state])
	# Una partida con la vista girada vuelve a la esquina de siempre y encuadra la oficina.
	loaded.call("_restore_scene_state", {"view_rotation": 3, "camera": {"zoom": 0.25, "x": -9999.0, "y": -9999.0}})
	loaded.get_node("OfficeCamera").finish_motion()
	_expect(loaded.get_node("OfficeCamera").export_state()["x"] != -9999.0, "partida vieja girada: encuadra la oficina")
	await _close_game(loaded)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_dir.path_join("slot_5.json")))


func _check_menu_bar() -> void:
	var game: Node = await _open_game()
	await _wait()
	var bar: Container = game.get_node("BuildPanel").get_menu_bar()
	_expect(game.menu_bar_button("RotateViewButton") == null, "ya no hay botón de girar la vista")
	var tops: Dictionary = {}
	for child: Node in bar.get_children():
		if child is Control and child.visible:
			tops[roundi(child.position.y)] = true
	_expect(tops.size() == 1, "a 100 %% en 1280×720 la barra entra en una fila: %d filas" % tops.size())
	await _close_game(game)
