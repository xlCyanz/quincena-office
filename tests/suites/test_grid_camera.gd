# Prueba del hito 1: conversión píxel↔casilla con la cámara en cada
# nivel de zoom y en varias posiciones, más el arrastre, el zoom y los límites.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=grid_camera
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

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
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	_grid = main.get_node("OfficeGrid")
	_camera = main.get_node("OfficeCamera")
	await _next_frame()

	_check_lot_shape()
	for index: int in range(GameConstants.CAMERA_ZOOM_LEVELS.size()):
		_camera.zoom_index = index
		_camera.import_state({"zoom": GameConstants.CAMERA_ZOOM_LEVELS[index], "x": _camera.position.x, "y": _camera.position.y})
		for target: Vector2 in _camera_targets():
			_camera.position = target
			_camera.call("_clamp_position")
			await _next_frame()
			_check_camera_transform()
			_check_all_cells()
			_check_outside_lot()
	await _check_drag_and_zoom()

	finished.emit(_failures, _checks)


func _next_frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Centro y esquinas del local, más un punto lejano: la cámara se lleva a cada uno
# (los límites del mapa la recortan).
func _camera_targets() -> Array[Vector2]:
	var rect: Rect2 = _grid.get_lot_world_rect()
	return [rect.get_center(), rect.position, rect.end,
		Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), Vector2(-9000.0, 9000.0)]


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
	# El mapa pinta todo el solar (local + terreno) con el local en el centro.
	var site: Rect2i = OfficeState.site_rect
	_expect(site.size == GameConstants.MAX_SITE_SIZE, "tamaño del solar %s" % site.size)
	_expect(site.encloses(_grid.get_lot_rect()), "el solar no contiene al local")
	var floor_layer: TileMapLayer = _grid.get_node("Floor")
	_expect(floor_layer.get_used_cells().size() == site.get_area(),
		"casillas pintadas %d, se esperaban %d" % [floor_layer.get_used_cells().size(), site.get_area()])
	_expect(floor_layer.get_used_rect() == site, "rectángulo pintado distinto del solar")
	var area: Transform2D = _grid.get_site_world_area()
	for corner: Vector2i in [site.position, site.end - Vector2i.ONE]:
		var local: Vector2 = area.affine_inverse() * _grid.cell_to_world(corner)
		_expect(local.x > 0.0 and local.x < 1.0 and local.y > 0.0 and local.y < 1.0,
			"la casilla %s queda fuera del rombo del mapa (%s)" % [corner, local])


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
	_camera.set_map_area(_grid.get_site_world_area())
	_camera.import_state({"zoom": GameConstants.CAMERA_ZOOM_LEVELS[GameConstants.CAMERA_START_ZOOM_INDEX]})
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
	_camera.import_state({"zoom": levels[levels.size() - 1], "x": lot_center.x, "y": lot_center.y})
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

	# Movimiento libre: se puede llevar la vista lejos del local, dentro del mapa.
	_camera.import_state({"zoom": levels[GameConstants.CAMERA_START_ZOOM_INDEX], "x": lot_center.x, "y": lot_center.y})
	var far_cell: Vector2i = OfficeState.site_rect.position + Vector2i(2, 2)
	_camera.center_on(_grid.cell_to_world(far_cell))
	_expect(_camera.position == _grid.cell_to_world(far_cell), "la cámara no llega a una esquina del mapa")

	# Encuadre: la oficina completa queda a la vista y centrada.
	_camera.fit_rect(_grid.get_lot_world_rect())
	var fit_size: Vector2 = view_size / _camera.get_zoom_level()
	var fit_view := Rect2(_camera.position - fit_size / 2.0, fit_size)
	_expect(fit_view.encloses(_grid.get_lot_world_rect()), "el encuadre no muestra toda la oficina")
	_expect(_camera.position.distance_to(lot_center) < 0.01, "el encuadre no centra la oficina")

	# Límites: arrastrar muy lejos deja el centro de la vista en el borde del mapa.
	for index: int in range(levels.size()):
		_camera.import_state({"zoom": levels[index], "x": lot_center.x, "y": lot_center.y})
		for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_camera.position = lot_center
			var from: Vector2 = view_size / 2.0
			_push_mouse_button(MOUSE_BUTTON_MIDDLE, true, from)
			_push_mouse_motion(from, from + direction * 20000.0, MOUSE_BUTTON_MASK_MIDDLE)
			_push_mouse_button(MOUSE_BUTTON_MIDDLE, false, from + direction * 20000.0)
			await _next_frame()
			_check_center_in_map("zoom %s, arrastre %s" % [_camera.get_zoom_level(), direction])


func _check_center_in_map(context: String) -> void:
	var local: Vector2 = _grid.get_site_world_area().affine_inverse() * _camera.position
	var tolerance := 0.0001
	var inside: bool = local.x >= -tolerance and local.x <= 1.0 + tolerance \
		and local.y >= -tolerance and local.y <= 1.0 + tolerance
	var on_edge: bool = absf(local.x) < tolerance or absf(local.x - 1.0) < tolerance \
		or absf(local.y) < tolerance or absf(local.y - 1.0) < tolerance
	_expect(inside and on_edge, "%s: el centro de la vista no quedó en el borde del mapa (%s)" % [context, local])
