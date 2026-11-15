# Herramientas del modo construcción con el ratón: muestra una vista previa de lo que
# se va a construir o vender y, al soltar el botón izquierdo, lo aplica con Builder.
# - Pared: arrastrar a lo largo de una línea de bordes pone una fila de paredes.
# - Puerta: clic en un borde.
# - Piso: arrastrar pinta un rectángulo de casillas.
# - Mueble: clic coloca el mueble; clic derecho (o la tecla R) lo gira antes de ponerlo.
# - Computadora: clic en un escritorio.
# - Girar: clic en un mueble lo gira un cuarto de vuelta.
# - Vender: clic en una pared o puerta interior, o en un mueble (si es un escritorio
#   con computadora, primero la computadora). Los pisos no se venden: se cambian
#   pasando otro piso encima.
# - Tipo de habitación: clic en un espacio cerrado con puerta lo marca con ese tipo.
# - Quitar habitación: clic en una habitación la deja sin tipo.
# - Terreno: se arrastra un rectángulo en el mapa junto al local (se marca lo que se
#   compraría y su precio) y se compra con buy_land (el botón Comprar de BuildPanel).
# En modo construcción se escribe sobre cada habitación su nombre y si funciona.
class_name BuildController
extends Node2D

## Cambió el texto de estado (costo de la vista previa, resultado o error).
signal status_changed(text: String)
## Cambió el terreno elegido con el ratón (o se compró).
signal land_changed

const TOOL_WALL: String = "wall"
const TOOL_DOOR: String = "door"
const TOOL_WINDOW: String = "window"
## Puerta doble de vidrio de la entrada (hito 69).
const TOOL_GLASS_DOOR: String = "glass_door"
const TOOL_ROTATE: String = "rotate"
const TOOL_SELL: String = "sell"
const TOOL_UNMARK_ROOM: String = "unmark_room"
const TOOL_LAND: String = "land"
const LAND_HINT: String = "Arrastra en el mapa junto al local para elegir el terreno."
## Mejorar la computadora de un escritorio o una silla a su calidad siguiente (hito 46).
const TOOL_UPGRADE: String = "upgrade"

## Distancia máxima (en casillas) a un borde para que Vender lo elija en vez de la casilla.
const SELL_EDGE_DISTANCE: float = 0.2
## Píxeles que se puede mover el ratón con el clic derecho para que cuente como clic
## (girar) y no como arrastre de la cámara.
const RIGHT_CLICK_SLOP_PX: float = 6.0

const PREVIEW_OK := Color(0.4, 1.0, 0.5, 0.9)
const PREVIEW_BAD := Color(1.0, 0.35, 0.3, 0.9)
const PREVIEW_LINE_WIDTH: float = 3.0

const LABEL_FONT_SIZE: int = 20
const LABEL_WIDTH: float = 240.0
const LABEL_OUTLINE: int = 5
const LABEL_COLOR := Color(1.0, 1.0, 1.0)
const LABEL_OK_COLOR := Color(0.55, 1.0, 0.6)
const LABEL_BAD_COLOR := Color(1.0, 0.6, 0.5)
const LABEL_OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.8)

## Herramienta elegida: una de las constantes TOOL_, un tipo de piso, el id de un
## mueble o un tipo de habitación.
var tool: String = TOOL_WALL
var builder := Builder.new()

var _grid: OfficeGrid
var _active: bool = false
## Cuarto de la casilla que marca la vista previa (mueble chico), o -1.
var _preview_quarter: int = -1
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
# Terreno elegido en la fila de BuildPanel.
# Esquinas del terreno elegido (vacío si no hay) y si se está arrastrando.
var _land_corners: Array[Vector2i] = []
var _land_dragging: bool = false
# Zoom con el que se dibujaron los nombres de las habitaciones.
var _label_zoom: float = 0.0


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


## Elige el terreno que se va a comprar: el rectángulo entre dos casillas.
func set_land_rect(corner_a: Vector2i, corner_b: Vector2i) -> void:
	_land_corners = [corner_a, corner_b]
	if tool == TOOL_LAND:
		_update_preview()
	land_changed.emit()


## Esquinas del terreno elegido ([] si no hay).
func get_land_rect() -> Array[Vector2i]:
	return _land_corners.duplicate()


## Indica si hay un terreno elegido que se puede comprar.
func can_buy_land() -> bool:
	return _land_corners.size() == 2 and bool(builder.quote_land_rect(_land_corners[0], _land_corners[1])["ok"])


## Compra el terreno elegido.
func buy_land() -> Dictionary:
	if _land_corners.size() != 2:
		var hint: Dictionary = {"ok": false, "message": LAND_HINT}
		status_changed.emit(hint["message"])
		return hint
	var result: Dictionary = builder.buy_land_rect(_land_corners[0], _land_corners[1])
	if result["ok"]:
		_land_corners.clear()
	status_changed.emit(result["message"])
	_update_preview(false)
	land_changed.emit()
	return result


func set_tool(new_tool: String) -> void:
	tool = new_tool
	_dragging = false
	_land_dragging = false
	_update_preview()
	if tool == TOOL_LAND and _land_corners.is_empty():
		status_changed.emit(LAND_HINT)
	if _is_room_tool():
		var missing: Array[String] = RoomRules.missing_mandatory(OfficeState.rooms)
		var hint: String = "Clic en un espacio cerrado con puerta."
		if not missing.is_empty():
			hint += " Faltan: %s." % ", ".join(missing)
		status_changed.emit(hint)


## Gira un cuarto de vuelta el mueble que se va a colocar.
func rotate_placement() -> void:
	_placement_rotation = (_placement_rotation + 1) % 4
	_update_preview()


# Los nombres de las habitaciones se dibujan a tamaño fijo en pantalla: si cambia el
# zoom, se vuelven a dibujar.
func _process(_delta: float) -> void:
	if _active and get_canvas_transform().get_scale().x != _label_zoom:
		queue_redraw()


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
	if tool == TOOL_LAND:
		_land_input(event)
		return
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


# Terreno: con el botón izquierdo se arrastra el rectángulo; al soltar queda elegido.
func _land_input(event: InputEvent) -> void:
	var cell: Vector2i = Vector2i(_pointer.round())
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_land_dragging = true
			_land_corners = [cell, cell]
			_update_preview()
		elif _land_dragging:
			_land_dragging = false
			_land_corners[1] = cell
			_update_preview()
			land_changed.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _land_dragging:
		if _land_corners[1] != cell:
			_land_corners[1] = cell
			_update_preview()
		get_viewport().set_input_as_handled()


func _is_room_tool() -> bool:
	return not RoomCatalog.get_type(tool).is_empty()


func _is_furniture_tool() -> bool:
	var info: Dictionary = FurnitureCatalog.get_item(tool)
	return not info.is_empty() and not bool(info["on_desk"])


func _clear_preview() -> void:
	_preview_quarter = -1
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
	var quarter: int = FurnitureCatalog.quarter_at(_pointer)
	var quote: Dictionary = {}
	var info: Dictionary = FurnitureCatalog.get_item(tool)
	if tool == TOOL_LAND:
		if _land_corners.size() != 2:
			queue_redraw()
			return
		quote = builder.quote_land_rect(_land_corners[0], _land_corners[1])
		_preview_cells = quote["new_cells"] if quote["ok"] else quote["cells"]
	elif _is_furniture_tool() and bool(info["wall_mounted"]):
		# Objeto de pared: va en la pared más cercana al ratón, del lado donde está el ratón.
		var slot: Array = _wall_slot()
		var wall_cell: Vector2i = slot[0]
		var wall_rotation: int = slot[1]
		_preview_cells = [wall_cell]
		_preview_edges = [FurnitureCatalog.get_wall_edge(wall_cell, wall_rotation)]
		quote = builder.quote_place(tool, wall_cell, wall_rotation)
		_apply_preview = func() -> Dictionary: return builder.place(tool, wall_cell, wall_rotation)
	elif tool == TOOL_SELL and _wall_item_under_pointer() >= 0:
		var hung: Dictionary = OfficeState.furniture[_wall_item_under_pointer()]
		var hung_cell: Vector2i = hung["cell"]
		var hung_rotation: int = hung["rotation"]
		_preview_cells = [hung_cell]
		_preview_edges = [FurnitureCatalog.get_wall_edge(hung_cell, hung_rotation)]
		quote = builder.quote_sell_wall_item(hung_cell, hung_rotation)
		_apply_preview = func() -> Dictionary: return builder.sell_wall_item(hung_cell, hung_rotation)
	elif _is_furniture_tool():
		var placement_rotation: int = _placement_rotation
		var placement_quarter: int = quarter if FurnitureCatalog.is_small(tool) else -1
		_preview_cells = FurnitureCatalog.get_footprint(tool, cell, placement_rotation)
		_preview_quarter = placement_quarter
		_preview_front = FurnitureCatalog.get_front(placement_rotation)
		quote = builder.quote_place(tool, cell, placement_rotation, placement_quarter)
		_apply_preview = func() -> Dictionary: return builder.place(tool, cell, placement_rotation, placement_quarter)
	elif not info.is_empty() and FurnitureCatalog.is_monitor(tool):  # segundo monitor
		_preview_cells = _footprint_at(cell)
		quote = builder.quote_install_monitor(tool, cell)
		_apply_preview = func() -> Dictionary: return builder.install_monitor(tool, cell)
	elif not info.is_empty():  # computadora
		_preview_cells = _footprint_at(cell)
		quote = builder.quote_install_computer(tool, cell)
		_apply_preview = func() -> Dictionary: return builder.install_computer(tool, cell)
	elif tool == TOOL_UPGRADE:
		_preview_cells = _footprint_at(cell)
		quote = builder.quote_upgrade(cell)
		_apply_preview = func() -> Dictionary: return builder.upgrade(cell)
	elif tool == TOOL_ROTATE:
		quote = builder.quote_rotate(cell, quarter)
		var index: int = OfficeState.find_furniture_at(cell, quarter)
		if index >= 0:
			var item: Dictionary = OfficeState.furniture[index]
			_preview_cells = FurnitureCatalog.get_footprint(item["id"], item["cell"], int(item["rotation"]) + 1)
			_preview_quarter = FurnitureCatalog.get_quarter(item)
			_preview_front = FurnitureCatalog.get_front(int(item["rotation"]) + 1)
		_apply_preview = func() -> Dictionary: return builder.rotate(cell, quarter)
	elif _is_room_tool() or tool == TOOL_UNMARK_ROOM:
		if OfficeState.lot.has_point(cell):
			_preview_cells = _space_at(cell)
			if tool == TOOL_UNMARK_ROOM:
				quote = builder.quote_unmark_room(cell)
				_apply_preview = func() -> Dictionary: return builder.unmark_room(cell)
			else:
				var room_type: String = tool
				quote = builder.quote_mark_room(room_type, cell)
				_apply_preview = func() -> Dictionary: return builder.mark_room(room_type, cell)
	elif tool == TOOL_SELL and _sell_targets_furniture(cell):
		_preview_cells = _footprint_at(cell, quarter)
		quote = builder.quote_sell_furniture_at(cell, quarter)
		_apply_preview = func() -> Dictionary: return builder.sell_furniture_at(cell, quarter)
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


# [casilla, rotación] de la cara de pared más cercana al ratón: el borde más cercano y,
# de sus dos casillas, la del lado del ratón (la pared queda detrás del frente).
func _wall_slot() -> Array:
	var edge: Vector3i = GridEdge.nearest(_pointer)
	var cells: Array[Vector2i] = GridEdge.get_cells(edge)
	var cell: Vector2i = cells[0]
	if (Vector2(cells[1]) - _pointer).length_squared() < (Vector2(cells[0]) - _pointer).length_squared():
		cell = cells[1]
	var other: Vector2i = cells[1] if cell == cells[0] else cells[0]
	return [cell, FurnitureCatalog.FRONT_DIRECTIONS.find(cell - other)]


# Objeto colgado en la cara de pared junto al ratón (índice en furniture), o -1.
func _wall_item_under_pointer() -> int:
	var edge: Vector3i = GridEdge.nearest(_pointer)
	if GridEdge.distance_to(edge, _pointer) > SELL_EDGE_DISTANCE * 2.0:
		return -1
	var slot: Array = _wall_slot()
	return OfficeState.find_wall_item(slot[0], slot[1])


# Vender elige el mueble de la casilla salvo que el ratón esté junto a una pared o puerta.
func _sell_targets_furniture(cell: Vector2i) -> bool:
	if OfficeState.find_furniture_at(cell) < 0:
		return false
	var edge: Vector3i = GridEdge.nearest(_pointer)
	return OfficeState.get_edge(edge).is_empty() or GridEdge.distance_to(edge, _pointer) > SELL_EDGE_DISTANCE


# Casillas del espacio (zona entre paredes y puertas) que contiene cell.
func _space_at(cell: Vector2i) -> Array[Vector2i]:
	var spaces: Array[Dictionary] = RoomRules.find_spaces(OfficeState.lot, OfficeState.edges)
	var index: int = RoomRules.space_index_at(spaces, cell)
	if index < 0:
		return [cell]
	return spaces[index]["cells"]


func _footprint_at(cell: Vector2i, quarter: int = -1) -> Array[Vector2i]:
	var index: int = OfficeState.find_furniture_at(cell, quarter)
	if index < 0:
		return [cell]
	var item: Dictionary = OfficeState.furniture[index]
	_preview_quarter = FurnitureCatalog.get_quarter(item)
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
		TOOL_WINDOW:
			changes.append({"edge": GridEdge.nearest(end), "kind": ConstructionCatalog.WINDOW})
		TOOL_GLASS_DOOR:
			changes.append({"edge": GridEdge.nearest(end), "kind": ConstructionCatalog.GLASS_DOOR})
		TOOL_SELL:
			var edge: Vector3i = GridEdge.nearest(end)
			if not OfficeState.get_edge(edge).is_empty() and GridEdge.distance_to(edge, end) <= SELL_EDGE_DISTANCE:
				changes.append({"edge": edge, "kind": ""})
			else:
				changes.append({"cell": Vector2i(end.round()), "kind": ConstructionCatalog.BARE_FLOOR})
		TOOL_ROTATE, TOOL_UNMARK_ROOM:
			pass
		_:
			var first: Vector2i = Vector2i(start.round())
			var last: Vector2i = Vector2i(end.round())
			var area := Rect2i(first.min(last), (first - last).abs() + Vector2i.ONE)
			for x: int in range(area.position.x, area.end.x):
				for y: int in range(area.position.y, area.end.y):
					if OfficeState.lot.has_point(Vector2i(x, y)):
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
	_draw_room_labels()
	var color: Color = PREVIEW_OK if _preview_ok else PREVIEW_BAD
	for edge: Vector3i in _preview_edges:
		var ends: Array[Vector2] = GridEdge.get_endpoints(edge)
		draw_line(_grid.grid_to_world(ends[0]), _grid.grid_to_world(ends[1]), color, PREVIEW_LINE_WIDTH)
	for cell: Vector2i in _preview_cells:
		var center := Vector2(cell)
		var half := Vector2(0.5, 0.5)
		if _preview_quarter >= 0:  # mueble chico: solo su cuarto
			center += FurnitureCatalog.get_quarter_offset(_preview_quarter)
			half = Vector2(0.25, 0.25)
		var corners: PackedVector2Array = IsoBox.grid_rect_corners(_grid, center - half, center + half)
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


# Nombre de cada habitación y, debajo, si funciona.
func _draw_room_labels() -> void:
	var font: Font = ThemeDB.fallback_font
	_label_zoom = get_canvas_transform().get_scale().x
	for room: Dictionary in OfficeState.rooms:
		var cells: Array[Vector2i] = room["cells"]
		var center := Vector2.ZERO
		for cell: Vector2i in cells:
			center += Vector2(cell)
		center = _grid.grid_to_world(center / cells.size())
		var working: bool = builder.room_status(room)["ok"]
		var lines: Array[Array] = [
			[RoomCatalog.get_display_name(room["type"]), LABEL_COLOR],
			["Funciona" if working else "No funciona", LABEL_OK_COLOR if working else LABEL_BAD_COLOR],
		]
		var windows: int = OfficeState.count_room_windows(room)
		var door_points: int = OfficeState.get_room_door_ambiance(room)
		var ambiance: int = Ambiance.get_value(room, OfficeState.furniture, windows, door_points)
		if ambiance != 0:
			lines.append([Ambiance.describe(room, OfficeState.furniture, windows, door_points).split(" (")[0],
				LABEL_OK_COLOR if ambiance > 0 else LABEL_BAD_COLOR])
		# Escala inversa al zoom de la cámara, para que el texto no crezca ni se pixele.
		draw_set_transform(center, 0.0, Vector2.ONE / _label_zoom)
		var text_position := Vector2(-LABEL_WIDTH / 2.0, 0.0)
		for line: Array in lines:
			draw_string_outline(font, text_position, line[0], HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH,
				LABEL_FONT_SIZE, LABEL_OUTLINE, LABEL_OUTLINE_COLOR)
			draw_string(font, text_position, line[0], HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH,
				LABEL_FONT_SIZE, line[1])
			text_position.y += LABEL_FONT_SIZE + 2
	draw_set_transform(Vector2.ZERO)
