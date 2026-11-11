# Herramientas del modo construcción con el ratón: muestra una vista previa de lo que
# se va a construir o vender y, al soltar el botón izquierdo, lo aplica con Builder.
# - Pared: arrastrar a lo largo de una línea de bordes pone una fila de paredes.
# - Puerta: clic en un borde.
# - Piso: arrastrar pinta un rectángulo de casillas.
# - Vender: clic en una pared o puerta (o en una casilla, para vender su piso).
class_name BuildController
extends Node2D

## Cambió el texto de estado (costo de la vista previa, resultado o error).
signal status_changed(text: String)

const TOOL_WALL: String = "wall"
const TOOL_DOOR: String = "door"
const TOOL_SELL: String = "sell"

## Distancia máxima (en casillas) a un borde para que Vender lo elija en vez del piso.
const SELL_EDGE_DISTANCE: float = 0.2

const PREVIEW_OK := Color(0.4, 1.0, 0.5, 0.9)
const PREVIEW_BAD := Color(1.0, 0.35, 0.3, 0.9)
const PREVIEW_LINE_WIDTH: float = 3.0

## Herramienta elegida: TOOL_WALL, TOOL_DOOR, TOOL_SELL o un tipo de piso.
var tool: String = TOOL_WALL
var builder := Builder.new()

var _grid: OfficeGrid
var _active: bool = false
var _pointer := Vector2.ZERO  # posición del ratón en la cuadrícula, con decimales
var _dragging: bool = false
var _drag_start := Vector2.ZERO
var _preview: Array[Dictionary] = []
var _preview_ok: bool = false


func setup(grid: OfficeGrid) -> void:
	_grid = grid


## Activa o desactiva el modo construcción.
func set_active(active: bool) -> void:
	_active = active
	_dragging = false
	_preview.clear()
	queue_redraw()


func is_active() -> bool:
	return _active


func set_tool(new_tool: String) -> void:
	tool = new_tool
	_dragging = false
	_update_preview()


## Cambios que se aplicarían ahora mismo (para la vista previa y para las pruebas).
func get_preview() -> Array[Dictionary]:
	return _preview.duplicate()


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _grid == null:
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
			var result: Dictionary = builder.apply(_preview)
			status_changed.emit(result["message"])
			_update_preview(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_update_preview()
		if _dragging:
			get_viewport().set_input_as_handled()


# Recalcula los cambios bajo el ratón; si announce, también avisa de su costo.
func _update_preview(announce: bool = true) -> void:
	_preview = _changes_for(_drag_start if _dragging else _pointer, _pointer)
	_preview_ok = false
	if not _preview.is_empty():
		var quote: Dictionary = builder.quote(_preview)
		_preview_ok = quote["ok"]
		if announce:
			status_changed.emit(quote["message"])
	queue_redraw()


func _changes_for(start: Vector2, end: Vector2) -> Array[Dictionary]:
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
				changes.append({"cell": _cell_at(end), "kind": ConstructionCatalog.BARE_FLOOR})
		_:
			var first: Vector2i = _cell_at(start)
			var last: Vector2i = _cell_at(end)
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


func _cell_at(grid_position: Vector2) -> Vector2i:
	return Vector2i(grid_position.round())


func _draw() -> void:
	if not _active:
		return
	var color: Color = PREVIEW_OK if _preview_ok else PREVIEW_BAD
	for change: Dictionary in _preview:
		if change.has("edge"):
			var ends: Array[Vector2] = GridEdge.get_endpoints(change["edge"])
			draw_line(_grid.grid_to_world(ends[0]), _grid.grid_to_world(ends[1]), color, PREVIEW_LINE_WIDTH)
		else:
			var center := Vector2(change["cell"])
			var corners: PackedVector2Array = IsoBox.grid_rect_corners(_grid, center - Vector2(0.5, 0.5),
				center + Vector2(0.5, 0.5))
			corners.append(corners[0])
			draw_polyline(corners, color, PREVIEW_LINE_WIDTH / 2.0)
