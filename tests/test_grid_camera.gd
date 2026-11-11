# Prueba sin ventana del hito 1: conversión píxel↔casilla con la cámara en cada
# nivel de zoom y en varias posiciones, más el arrastre, el zoom y los límites.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_grid_camera.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _failures: int = 0
var _checks: int = 0
var _grid: OfficeGrid
var _camera: OfficeCamera


func _ready() -> void:
	# Con ventana (por ejemplo, F6 en el editor) la prueba movería la cámara a saltos
	# y cerraría el juego; en ese caso se abre el juego normal.
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_packed.call_deferred(MAIN_SCENE)
		return
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	_grid = main.get_node("OfficeGrid")
	_camera = main.get_node("OfficeCamera")
	await _next_frame()

	_check_lot_shape()
	for index: int in range(GameConstants.CAMERA_ZOOM_LEVELS.size()):
		_camera.zoom_index = index
		_camera.import_state({"zoom_index": index, "x": _camera.position.x, "y": _camera.position.y})
		for target: Vector2 in _camera_targets():
			_camera.position = target
			_camera.call("_clamp_position")
			await _next_frame()
			_check_camera_transform()
			_check_all_cells()
			_check_outside_lot()
	await _check_drag_and_zoom()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _next_frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Centro y esquinas del local: la cámara se lleva a cada una (los límites la recortan).
func _camera_targets() -> Array[Vector2]:
	var rect: Rect2 = _grid.get_lot_world_rect()
	return [rect.get_center(), rect.position, rect.end,
		Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]


# Fórmula isométrica escrita a mano, independiente de TileMapLayer.
func _expected_cell(world: Vector2) -> Vector2i:
	var origin: Vector2 = _grid.cell_to_world(Vector2i.ZERO)
	var half: Vector2 = Vector2(GameConstants.TILE_SIZE) / 2.0
	var u: float = (world.x - origin.x) / half.x
	var v: float = (world.y - origin.y) / half.y
	return Vector2i(floori((v + u) / 2.0 + 0.5), floori((v - u) / 2.0 + 0.5))


# Píxel de pantalla donde debería verse un punto del mundo, calculado a mano.
func _world_to_screen(world: Vector2) -> Vector2:
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	return (world - _camera.position) * _camera.get_zoom_level() + view_size / 2.0


func _check_lot_shape() -> void:
	var size: Vector2i = GameConstants.STARTING_LOT_SIZE
	var rect: Rect2 = _grid.get_lot_world_rect()
	var expected := Vector2((size.x + size.y) * GameConstants.TILE_SIZE.x / 2.0,
		(size.x + size.y) * GameConstants.TILE_SIZE.y / 2.0)
	_expect(rect.size == expected, "tamaño del local en píxeles %s, se esperaba %s" % [rect.size, expected])
	var floor_layer: TileMapLayer = _grid.get_node("Floor")
	_expect(floor_layer.get_used_cells().size() == size.x * size.y,
		"casillas pintadas %d, se esperaban %d" % [floor_layer.get_used_cells().size(), size.x * size.y])
	_expect(floor_layer.get_used_rect() == _grid.get_lot_rect(), "rectángulo pintado distinto del local")


func _check_camera_transform() -> void:
	var probe := Vector2(123.0, 45.0)
	var got: Vector2 = _grid.screen_to_world(_world_to_screen(probe))
	_expect(got.distance_to(probe) < 0.01,
		"transformación de cámara (zoom %s): %s → %s" % [_camera.get_zoom_level(), probe, got])


# Para cada casilla del local prueba el centro y puntos junto a las 4 puntas y a los
# 4 lados del rombo (a 1 píxel de pantalla del borde).
func _check_all_cells() -> void:
	var half: Vector2 = Vector2(GameConstants.TILE_SIZE) / 2.0
	var inset: float = 1.0 / _camera.get_zoom_level()
	var lot: Rect2i = _grid.get_lot_rect()
	for x: int in range(lot.position.x, lot.end.x):
		for y: int in range(lot.position.y, lot.end.y):
			var cell := Vector2i(x, y)
			var center: Vector2 = _grid.cell_to_world(cell)
			var offsets: Array[Vector2] = [
				Vector2.ZERO,
				Vector2(half.x - 2.0 * inset - 1.0, 0.0), Vector2(-half.x + 2.0 * inset + 1.0, 0.0),
				Vector2(0.0, half.y - inset - 0.5), Vector2(0.0, -half.y + inset + 0.5),
				Vector2(half.x, half.y) / 2.0 * 0.9, Vector2(-half.x, half.y) / 2.0 * 0.9,
				Vector2(half.x, -half.y) / 2.0 * 0.9, Vector2(-half.x, -half.y) / 2.0 * 0.9,
			]
			for offset: Vector2 in offsets:
				var world: Vector2 = center + offset
				var screen: Vector2 = _world_to_screen(world)
				var got: Vector2i = _grid.screen_to_cell(screen)
				var context := "zoom %s, cámara %s, casilla %s, punto %s" % [
					_camera.get_zoom_level(), _camera.position, cell, offset]
				_expect(got == cell, "%s → %s" % [context, got])
				_expect(_expected_cell(world) == cell, "fórmula manual: " + context)
				_grid.update_hover(_grid.screen_to_world(screen))
				var highlight: Node2D = _grid.get_node("CellHighlight")
				_expect(_grid.hovered_cell == cell and highlight.visible
					and highlight.global_position.distance_to(center) < 0.01, "resaltado: " + context)


# Justo fuera de cada borde del local no debe resaltarse nada.
func _check_outside_lot() -> void:
	var lot: Rect2i = _grid.get_lot_rect()
	var outside: Array[Vector2i] = []
	for x: int in range(lot.position.x - 1, lot.end.x + 1):
		outside.append(Vector2i(x, lot.position.y - 1))
		outside.append(Vector2i(x, lot.end.y))
	for y: int in range(lot.position.y, lot.end.y):
		outside.append(Vector2i(lot.position.x - 1, y))
		outside.append(Vector2i(lot.end.x, y))
	for cell: Vector2i in outside:
		var screen: Vector2 = _world_to_screen(_grid.cell_to_world(cell))
		_expect(_grid.screen_to_cell(screen) == cell, "fuera del local: casilla %s" % cell)
		_grid.update_hover(_grid.screen_to_world(screen))
		_expect(_grid.hovered_cell == OfficeGrid.NO_CELL and not _grid.get_node("CellHighlight").visible,
			"no debe resaltarse la casilla %s fuera del local" % cell)


func _push_mouse_button(button: MouseButton, pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	event.factor = 1.0
	get_viewport().push_input(event, true)


func _push_mouse_motion(from: Vector2, to: Vector2, button_mask: MouseButtonMask) -> void:
	var event := InputEventMouseMotion.new()
	event.position = to
	event.relative = to - from
	event.button_mask = button_mask
	get_viewport().push_input(event, true)


func _check_drag_and_zoom() -> void:
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var lot_center: Vector2 = _grid.get_lot_world_rect().get_center()

	# Zoom con la rueda: niveles fijos, sin pasarse de los extremos.
	_camera.set_bounds(_grid.get_lot_world_rect())
	_camera.import_state({"zoom_index": GameConstants.CAMERA_START_ZOOM_INDEX})
	_camera.position = lot_center
	var levels: Array[float] = GameConstants.CAMERA_ZOOM_LEVELS
	for i: int in range(levels.size() + 1):
		_push_mouse_button(MOUSE_BUTTON_WHEEL_UP, true, view_size / 2.0)
	await _next_frame()
	_expect(_camera.zoom == Vector2.ONE * levels[levels.size() - 1], "zoom máximo con la rueda: %s" % _camera.zoom)
	for i: int in range(levels.size() + 1):
		_push_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, view_size / 2.0)
	await _next_frame()
	_expect(_camera.zoom == Vector2.ONE * levels[0], "zoom mínimo con la rueda: %s" % _camera.zoom)

	# El zoom mantiene fija la casilla bajo el ratón.
	var corner_cell := Vector2i(1, 1)
	var anchor: Vector2 = _world_to_screen(_grid.cell_to_world(corner_cell))
	_push_mouse_button(MOUSE_BUTTON_WHEEL_UP, true, anchor)
	await _next_frame()
	_expect(_grid.screen_to_cell(anchor) == corner_cell, "la casilla bajo el ratón cambió al hacer zoom")

	# Arrastre con el botón izquierdo: el mundo sigue al ratón.
	_camera.import_state({"zoom_index": levels.size() - 1, "x": lot_center.x, "y": lot_center.y})
	await _next_frame()
	var start: Vector2 = view_size / 2.0
	var grabbed: Vector2 = _grid.screen_to_world(start)
	# Arrastre casi horizontal para no tocar los límites con ninguna ventana.
	var finish: Vector2 = start + Vector2(40.0, 1.0)
	_push_mouse_button(MOUSE_BUTTON_LEFT, true, start)
	_push_mouse_motion(start, start + Vector2(2.0, 1.0), MOUSE_BUTTON_MASK_LEFT)
	_expect(_camera.position == lot_center, "un movimiento menor al umbral no debe arrastrar %s vs %s" % [_camera.position, lot_center])
	_push_mouse_motion(start + Vector2(2.0, 1.0), finish, MOUSE_BUTTON_MASK_LEFT)
	_push_mouse_button(MOUSE_BUTTON_LEFT, false, finish)
	await _next_frame()
	_expect(_grid.screen_to_world(finish).distance_to(grabbed) < 0.01,
		"tras arrastrar, el punto agarrado no quedó bajo el ratón %s vs %s" % [_grid.screen_to_world(finish), grabbed])

	# Límites: arrastrar muy lejos deja la vista como mucho a un margen del local.
	for index: int in range(levels.size()):
		_camera.import_state({"zoom_index": index, "x": lot_center.x, "y": lot_center.y})
		for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_camera.position = lot_center
			var from: Vector2 = view_size / 2.0
			_push_mouse_button(MOUSE_BUTTON_MIDDLE, true, from)
			_push_mouse_motion(from, from + direction * 5000.0, MOUSE_BUTTON_MASK_MIDDLE)
			_push_mouse_button(MOUSE_BUTTON_MIDDLE, false, from + direction * 5000.0)
			await _next_frame()
			_check_view_near_lot("zoom %s, arrastre %s" % [_camera.get_zoom_level(), direction])


func _check_view_near_lot(context: String) -> void:
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom_level: float = _camera.get_zoom_level()
	var view := Rect2(_camera.position - view_size / 2.0 / zoom_level, view_size / zoom_level)
	var lot: Rect2 = _grid.get_lot_world_rect()
	var margin: Vector2 = view_size * GameConstants.CAMERA_OVERSCROLL_RATIO / zoom_level
	var allowed: Rect2 = lot.grow_individual(margin.x, margin.y, margin.x, margin.y)
	var tolerance := 0.01
	# O la vista cabe dentro del local con su margen, o el local con su margen cabe en la vista.
	var view_inside: bool = allowed.grow(tolerance).encloses(view)
	var lot_inside: bool = view.grow(tolerance).encloses(allowed)
	var x_ok: bool = (view.position.x >= allowed.position.x - tolerance and view.end.x <= allowed.end.x + tolerance) \
		or (allowed.position.x >= view.position.x - tolerance and allowed.end.x <= view.end.x + tolerance)
	var y_ok: bool = (view.position.y >= allowed.position.y - tolerance and view.end.y <= allowed.end.y + tolerance) \
		or (allowed.position.y >= view.position.y - tolerance and allowed.end.y <= view.end.y + tolerance)
	_expect(x_ok and y_ok, "%s: vista %s fuera del margen permitido %s (%s, %s)" % [
		context, view, allowed, view_inside, lot_inside])
	# Siempre debe verse alguna casilla del local.
	_expect(view.intersects(lot), "%s: el local quedó fuera de la vista" % context)
