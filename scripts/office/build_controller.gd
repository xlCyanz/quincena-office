# Herramientas del modo construcción con el ratón: muestra una vista previa de lo que
# se va a construir o vender y, al soltar el botón izquierdo, lo aplica con Builder.
# - Pared: arrastrar a lo largo de una línea de bordes pone una fila de paredes.
# - Puerta: clic en un borde.
# - Piso: arrastrar pinta un rectángulo de casillas.
# - Mueble: clic coloca el mueble; clic derecho (o la tecla R) lo gira antes de ponerlo.
# - Computadora: clic en un escritorio.
# - Girar: clic en un mueble lo gira un cuarto de vuelta.
# - Vender: clic en una pared o puerta, en un mueble (si es un escritorio con
#   computadora, primero la computadora) o en una casilla, para vender su piso.
class_name BuildController
extends Node2D

## Cambió el texto de estado (costo de la vista previa, resultado o error).
signal status_changed(text: String)

const TOOL_WALL: String = "wall"
const TOOL_DOOR: String = "door"
const TOOL_ROTATE: String = "rotate"
const TOOL_SELL: String = "sell"

## Distancia máxima (en casillas) a un borde para que Vender lo elija en vez de la casilla.
const SELL_EDGE_DISTANCE: float = 0.2
## Píxeles que se puede mover el ratón con el clic derecho para que cuente como clic
## (girar) y no como arrastre de la cámara.
const RIGHT_CLICK_SLOP_PX: float = 6.0

const PREVIEW_OK := Color(0.4, 1.0, 0.5, 0.9)
const PREVIEW_BAD := Color(1.0, 0.35, 0.3, 0.9)
const PREVIEW_LINE_WIDTH: float = 3.0

## Herramienta elegida: una de las constantes TOOL_, un tipo de piso o el id de un mueble.
var tool: String = TOOL_WALL
var builder := Builder.new()

var _grid: OfficeGrid
var _active: bool = false
var _pointer := Vector2.ZERO  # posición del ratón en la cuadrícula, con decimales
var _dragging: bool = false
var _drag_start := Vector2.ZERO
var _placement_rotation: int = 0
var _right_press_position := Vector2.ZERO

# Vista previa: lo que se marca en pantalla, si se puede hacer y cómo aplicarlo.
var _preview_cells: Array[Vector2i] = []
var _preview_edges: Array[Vector3i] = []
var _preview_front := Vector2i.ZERO
var _preview_ok: bool = false
var _apply_preview := Callable()


func setup(grid: OfficeGrid) -> void:
	_grid = grid


## Activa o desactiva el modo construcción.
func set_active(active: bool) -> void:
	_active = active
	_dragging = false
	_clear_preview()
	queue_redraw()


func is_active() -> bool:
	return _active


func set_tool(new_tool: String) -> void:
	tool = new_tool
	_dragging = false
	_update_preview()


## Gira un cuarto de vuelta el mueble que se va a colocar.
func rotate_placement() -> void:
	_placement_rotation = (_placement_rotation + 1) % 4
	_update_preview()


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _grid == null:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R:
		rotate_placement()
		get_viewport().set_input_as_handled()
		return
	var mouse := event as InputEventMouse
	if mouse == null:
		return
	_pointer = _grid.world_to_grid(_grid.screen_to_world(mouse.position))
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_dragging = true
			_drag_start = _pointer
			_update_preview()
		elif _dragging:
			_update_preview(false)
			_dragging = false
			var result: Dictionary = _apply_preview.call() if _apply_preview.is_valid() else {
				"message": "No hay nada que hacer ahí."}
			status_changed.emit(result["message"])
			_update_preview(false)
		get_viewport().set_input_as_handled()
	elif button != null and button.button_index == MOUSE_BUTTON_RIGHT:
		# El clic derecho también mueve la cámara si se arrastra; aquí solo cuenta el clic.
		if button.pressed:
			_right_press_position = button.position
		elif button.position.distance_to(_right_press_position) <= RIGHT_CLICK_SLOP_PX and _is_furniture_tool():
			rotate_placement()
	elif event is InputEventMouseMotion:
		_update_preview()
		if _dragging:
			get_viewport().set_input_as_handled()


func _is_furniture_tool() -> bool:
	var info: Dictionary = FurnitureCatalog.get_item(tool)
	return not info.is_empty() and not bool(info["on_desk"])


func _clear_preview() -> void:
	_preview_cells.clear()
	_preview_edges.clear()
	_preview_front = Vector2i.ZERO
	_preview_ok = false
	_apply_preview = Callable()


# Recalcula la vista previa bajo el ratón; si announce, también avisa de su costo.
func _update_preview(announce: bool = true) -> void:
	_clear_preview()
	var start: Vector2 = _drag_start if _dragging else _pointer
	var cell: Vector2i = Vector2i(_pointer.round())
	var quote: Dictionary = {}
	var info: Dictionary = FurnitureCatalog.get_item(tool)
	if _is_furniture_tool():
		var rotation: int = _placement_rotation
		_preview_cells = FurnitureCatalog.get_footprint(tool, cell, rotation)
		_preview_front = FurnitureCatalog.get_front(rotation)
		quote = builder.quote_place(tool, cell, rotation)
		_apply_preview = func() -> Dictionary: return builder.place(tool, cell, rotation)
	elif not info.is_empty():  # computadora
		_preview_cells = _footprint_at(cell)
		quote = builder.quote_install_computer(tool, cell)
		_apply_preview = func() -> Dictionary: return builder.install_computer(tool, cell)
	elif tool == TOOL_ROTATE:
		quote = builder.quote_rotate(cell)
		var index: int = OfficeState.find_furniture_at(cell)
		if index >= 0:
			var item: Dictionary = OfficeState.furniture[index]
			_preview_cells = FurnitureCatalog.get_footprint(item["id"], item["cell"], int(item["rotation"]) + 1)
			_preview_front = FurnitureCatalog.get_front(int(item["rotation"]) + 1)
		_apply_preview = func() -> Dictionary: return builder.rotate(cell)
	elif tool == TOOL_SELL and _sell_targets_furniture(cell):
		_preview_cells = _footprint_at(cell)
		quote = builder.quote_sell_furniture_at(cell)
		_apply_preview = func() -> Dictionary: return builder.sell_furniture_at(cell)
	else:
		var changes: Array[Dictionary] = _structure_changes(start, _pointer)
		for change: Dictionary in changes:
			if change.has("edge"):
				_preview_edges.append(change["edge"])
			else:
				_preview_cells.append(change["cell"])
		if not changes.is_empty():
			quote = builder.quote(changes)
			_apply_preview = func() -> Dictionary: return builder.apply(changes)
	if not quote.is_empty():
		_preview_ok = quote["ok"]
		if announce:
			status_changed.emit(quote["message"])
	queue_redraw()


# Vender elige el mueble de la casilla salvo que el ratón esté junto a una pared o puerta.
func _sell_targets_furniture(cell: Vector2i) -> bool:
	if OfficeState.find_furniture_at(cell) < 0:
		return false
	var edge: Vector3i = GridEdge.nearest(_pointer)
	return OfficeState.get_edge(edge).is_empty() or GridEdge.distance_to(edge, _pointer) > SELL_EDGE_DISTANCE


func _footprint_at(cell: Vector2i) -> Array[Vector2i]:
	var index: int = OfficeState.find_furniture_at(cell)
	if index < 0:
		return [cell]
	var item: Dictionary = OfficeState.furniture[index]
	return FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"])


# Cambios de pisos, paredes y puertas (los de Builder.quote) para la herramienta actual.
func _structure_changes(start: Vector2, end: Vector2) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	match tool:
		TOOL_WALL:
			for edge: Vector3i in _edge_line(GridEdge.nearest(start), end):
				changes.append({"edge": edge, "kind": ConstructionCatalog.WALL})
		TOOL_DOOR:
			changes.append({"edge": GridEdge.nearest(end), "kind": ConstructionCatalog.DOOR})
		TOOL_SELL:
			var edge: Vector3i = GridEdge.nearest(end)
			if not OfficeState.get_edge(edge).is_empty() and GridEdge.distance_to(edge, end) <= SELL_EDGE_DISTANCE:
				changes.append({"edge": edge, "kind": ""})
			else:
				changes.append({"cell": Vector2i(end.round()), "kind": ConstructionCatalog.BARE_FLOOR})
		TOOL_ROTATE:
			pass
		_:
			var first: Vector2i = Vector2i(start.round())
			var last: Vector2i = Vector2i(end.round())
			var area := Rect2i(first.min(last), (first - last).abs() + Vector2i.ONE)
			area = area.intersection(OfficeState.lot_rect)
			for x: int in range(area.position.x, area.end.x):
				for y: int in range(area.position.y, area.end.y):
					changes.append({"cell": Vector2i(x, y), "kind": tool})
	return changes


# Bordes de la misma línea que start, desde start hasta la altura de end.
func _edge_line(start: Vector3i, end: Vector2) -> Array[Vector3i]:
	var edges: Array[Vector3i] = []
	if start.z == GridEdge.AXIS_X:
		var last: int = roundi(end.y)
		for y: int in range(mini(start.y, last), maxi(start.y, last) + 1):
			edges.append(Vector3i(start.x, y, GridEdge.AXIS_X))
	else:
		var last: int = roundi(end.x)
		for x: int in range(mini(start.x, last), maxi(start.x, last) + 1):
			edges.append(Vector3i(x, start.y, GridEdge.AXIS_Y))
	return edges


func _draw() -> void:
	if not _active:
		return
	var color: Color = PREVIEW_OK if _preview_ok else PREVIEW_BAD
	for edge: Vector3i in _preview_edges:
		var ends: Array[Vector2] = GridEdge.get_endpoints(edge)
		draw_line(_grid.grid_to_world(ends[0]), _grid.grid_to_world(ends[1]), color, PREVIEW_LINE_WIDTH)
	for cell: Vector2i in _preview_cells:
		var center := Vector2(cell)
		var corners: PackedVector2Array = IsoBox.grid_rect_corners(_grid, center - Vector2(0.5, 0.5),
			center + Vector2(0.5, 0.5))
		corners.append(corners[0])
		draw_polyline(corners, color, PREVIEW_LINE_WIDTH / 2.0)
	# Flecha hacia el frente del mueble.
	if _preview_front != Vector2i.ZERO and not _preview_cells.is_empty():
		var center := Vector2.ZERO
		for cell: Vector2i in _preview_cells:
			center += Vector2(cell)
		center /= _preview_cells.size()
		var tip: Vector2 = center + Vector2(_preview_front) * 0.45
		draw_line(_grid.grid_to_world(center), _grid.grid_to_world(tip), color, PREVIEW_LINE_WIDTH)
		draw_circle(_grid.grid_to_world(tip), PREVIEW_LINE_WIDTH * 1.5, color)
