# Herramientas del modo construcción con el ratón: vista previa y, al soltar, Builder lo aplica.
# Pared: arrastrar una fila · Puerta/Computadora/Girar: clic · Piso: arrastrar un rectángulo ·
# Mueble: clic (clic derecho o R gira) · Vender: pieza interior o mueble (antes la computadora) ·
# Habitación: clic en un espacio cerrado · Terreno: clic en un lote marcado (los que tocan el local).
# Los pisos no se venden, se cambian. Sobre cada habitación se escribe su nombre y si funciona.
class_name BuildController
extends Node2D

## Cambió el texto de estado (costo, resultado o error).
signal status_changed(text: String)
## Cambió el terreno elegido con el ratón (o se compró).
signal land_changed
## Hay algo que confirmar (mudar la Oficina Ejecutiva): text es la pregunta; vacío = nada pendiente.
signal confirm_changed(text: String)

const TOOL_WALL: String = "wall"
const TOOL_DOOR: String = "door"
const TOOL_WINDOW: String = "window"
## Puerta doble de vidrio de la entrada.
const TOOL_GLASS_DOOR: String = "glass_door"
const TOOL_ROTATE: String = "rotate"
const TOOL_SELL: String = "sell"
const TOOL_UNMARK_ROOM: String = "unmark_room"
const TOOL_LAND: String = "land"
const LAND_HINT: String = "Clic en un lote marcado para comprarlo. Los de más afuera aparecen al comprar el que tienen antes."
## Colores de los lotes de Terreno: comprable, no comprable y bajo el ratón.
const PLOT_OK := Color(0.4, 1.0, 0.5, 0.16)
const PLOT_BAD := Color(1.0, 0.35, 0.3, 0.14)
const PLOT_HOVER := Color(0.4, 1.0, 0.5, 0.38)
## Mejorar computadora o silla a su calidad siguiente.
const TOOL_UPGRADE: String = "upgrade"

## Distancia máxima (casillas) a un borde para que Vender lo elija en vez de la casilla.
const SELL_EDGE_DISTANCE: float = 0.2
## Píxeles de movimiento con clic derecho que aún cuentan como clic (girar), no arrastre.
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

## Herramienta: una constante TOOL_, un tipo de piso, un id de mueble o un tipo de habitación.
var tool: String = TOOL_WALL
var builder := Builder.new()

var _grid: OfficeGrid
var _active: bool = false
## Cuarto que marca la vista previa (mueble chico), o -1.
var _preview_quarter: int = -1
var _pointer := Vector2.ZERO  # posición del ratón en la cuadrícula, con decimales
var _dragging: bool = false
var _drag_start := Vector2.ZERO
var _placement_rotation: int = 0
var _right_press_position := Vector2.ZERO

# Vista previa: lo marcado, si se puede y cómo aplicarlo.
var _preview_cells: Array[Vector2i] = []
var _preview_edges: Array[Vector3i] = []
var _preview_front := Vector2i.ZERO
var _preview_ok: bool = false
var _apply_preview := Callable()
# Terreno elegido en BuildPanel: esquinas (vacío si no hay), si se arrastra y la casilla del
# clic (compra si se suelta en el mismo lote).
var _land_press := Vector2i.ZERO
var _land_pressed: bool = false
# Lo que se hace si el jugador confirma.
var _pending_confirm := Callable()
var _pending_question: String = ""
# Lotes comprables con un clic (Builder.get_land_plots) y el que está bajo el ratón.
var _plots: Array[Dictionary] = []
var _hover_plot: int = -1
# Zoom con el que se dibujaron los nombres.
var _label_zoom: float = 0.0


func setup(grid: OfficeGrid) -> void:
	_grid = grid


## Activa o desactiva el modo construcción.
func set_active(active: bool) -> void:
	if is_confirming():
		answer_confirm(false)
	_active = active
	_dragging = false
	_clear_preview()
	refresh_land_plots()
	queue_redraw()


## Lotes marcados de la herramienta Terreno.
func get_land_plots() -> Array[Dictionary]:
	return _plots


## Recalcula los lotes marcados (al elegir la herramienta y tras comprar).
func refresh_land_plots() -> void:
	_plots = builder.get_land_plots() if _active and tool == TOOL_LAND else ([] as Array[Dictionary])
	_hover_plot = -1
	queue_redraw()


## Compra el lote marcado que contiene esa casilla.
func buy_land_plot_at(cell: Vector2i) -> Dictionary:
	var index: int = _plot_at(cell)
	if index < 0:
		var none: Dictionary = {"ok": false, "message": LAND_HINT}
		status_changed.emit(none["message"])
		return none
	var result: Dictionary = builder.buy_land_cells(_plots[index]["cells"])
	if not result["ok"]:
		# Lo que impide comprar (dinero, una habitación que se perdería).
		result = builder.quote_land_cells(_plots[index]["cells"])
	status_changed.emit(result["message"])
	refresh_land_plots()
	_update_preview(false)
	land_changed.emit()
	return result


# Índice del lote marcado que compraría esa casilla, o -1.
func _plot_at(cell: Vector2i) -> int:
	for index: int in range(_plots.size()):
		if (_plots[index]["new_cells"] as Array).has(cell):
			return index
	return -1


func is_active() -> bool:
	return _active


## Deja una pregunta pendiente; action se hace si se acepta (answer_confirm).
func ask_confirm(question: String, action: Callable) -> Dictionary:
	_pending_confirm = action
	_pending_question = question
	confirm_changed.emit(question)
	return {"ok": false, "message": question}


## Indica si hay una pregunta esperando respuesta.
func is_confirming() -> bool:
	return _pending_confirm.is_valid()


## Responde la pregunta: con accept se hace; si no, se olvida.
func answer_confirm(accept: bool) -> Dictionary:
	var action: Callable = _pending_confirm
	_pending_confirm = Callable()
	_pending_question = ""
	confirm_changed.emit("")
	if not action.is_valid():
		return {"ok": false, "message": ""}
	var result: Dictionary = action.call() if accept else {"ok": false, "message": "No se mudó nada."}
	status_changed.emit(result["message"])
	_update_preview(false)
	return result


func set_tool(new_tool: String) -> void:
	if is_confirming():
		answer_confirm(false)
	tool = new_tool
	_dragging = false
	_land_pressed = false
	refresh_land_plots()
	_update_preview()
	if tool == TOOL_LAND:
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


# Los nombres van a tamaño fijo en pantalla: se redibujan al cambiar el zoom.
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
		# El clic derecho arrastrado mueve la cámara; aquí solo cuenta el clic.
		if button.pressed:
			_right_press_position = button.position
		elif button.position.distance_to(_right_press_position) <= RIGHT_CLICK_SLOP_PX and _is_furniture_tool():
			rotate_placement()
	elif event is InputEventMouseMotion:
		_update_preview()
		if _dragging:
			get_viewport().set_input_as_handled()


# Terreno: un clic compra un lote marcado (solo los que tocan el local).
func _land_input(event: InputEvent) -> void:
	var cell: Vector2i = Vector2i(_pointer.round())
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_land_pressed = true
			_land_press = cell
		elif _land_pressed:
			_land_pressed = false
			var index: int = _plot_at(cell)
			if index >= 0 and index == _plot_at(_land_press):
				buy_land_plot_at(cell)
			else:
				status_changed.emit(LAND_HINT)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var hover: int = _plot_at(cell)
		if hover != _hover_plot:
			_hover_plot = hover
			if hover >= 0:
				var plot: Dictionary = _plots[hover]
				status_changed.emit(("Clic para comprar: " + String(plot["message"])) if plot["ok"] else String(plot["message"]))
			queue_redraw()


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


# Recalcula la vista previa; si announce, avisa su costo.
func _update_preview(announce: bool = true) -> void:
	_clear_preview()
	var start: Vector2 = _drag_start if _dragging else _pointer
	var cell: Vector2i = Vector2i(_pointer.round())
	var quarter: int = FurnitureCatalog.quarter_at(_pointer)
	var quote: Dictionary = {}
	var info: Dictionary = FurnitureCatalog.get_item(tool)
	if tool == TOOL_LAND:
		# Los lotes marcados se dibujan aparte (_draw_land_plots).
		queue_redraw()
		return
	elif _is_furniture_tool() and bool(info["wall_mounted"]):
		# Objeto de pared: en la pared más cercana, del lado del ratón.
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
				if bool(quote.get("confirm", false)):
					# Mudar la Oficina Ejecutiva: el clic pregunta y la respuesta lo hace.
					var question: String = String(quote["message"])
					_apply_preview = func() -> Dictionary: return ask_confirm(question,
						func() -> Dictionary: return builder.move_ceo_office(cell))
				else:
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


# [casilla, rotación] de la cara de pared más cercana: el borde más cercano y la casilla del lado del ratón.
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


# Vender toma el mueble de la casilla salvo que el ratón esté junto a una pared o puerta.
func _sell_targets_furniture(cell: Vector2i) -> bool:
	if OfficeState.find_furniture_at(cell) < 0:
		return false
	var edge: Vector3i = GridEdge.nearest(_pointer)
	return OfficeState.get_edge(edge).is_empty() or GridEdge.distance_to(edge, _pointer) > SELL_EDGE_DISTANCE


# Casillas del espacio que contiene cell.
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


# Cambios de pisos y bordes (de Builder.quote) para la herramienta actual.
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


# Bordes de la línea de start, de start hasta la altura de end.
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
	_draw_land_plots()
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


# Lotes marcados: casillas rellenas y precio encima.
func _draw_land_plots() -> void:
	if tool != TOOL_LAND or _plots.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var zoom: float = get_canvas_transform().get_scale().x
	for index: int in range(_plots.size()):
		var plot: Dictionary = _plots[index]
		var fill: Color = PLOT_HOVER if index == _hover_plot and plot["ok"] else (PLOT_OK if plot["ok"] else PLOT_BAD)
		var center := Vector2.ZERO
		var cells: Array = plot["new_cells"]
		for cell: Vector2i in cells:
			center += Vector2(cell)
			draw_colored_polygon(IsoBox.grid_rect_corners(_grid, Vector2(cell) - Vector2(0.47, 0.47), Vector2(cell) + Vector2(0.47, 0.47)), fill)
		draw_set_transform(_grid.grid_to_world(center / cells.size()), 0.0, Vector2.ONE / zoom)
		var text: String = MoneyFormat.format(int(plot["cost"]))
		var at := Vector2(-LABEL_WIDTH / 2.0, LABEL_FONT_SIZE * 0.35)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, LABEL_FONT_SIZE, LABEL_OUTLINE, LABEL_OUTLINE_COLOR)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, LABEL_FONT_SIZE, LABEL_OK_COLOR if plot["ok"] else LABEL_BAD_COLOR)
		draw_set_transform(Vector2.ZERO)


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
		# Escala inversa al zoom, para que el texto no crezca ni se pixele.
		draw_set_transform(center, 0.0, Vector2.ONE / _label_zoom)
		var text_position := Vector2(-LABEL_WIDTH / 2.0, 0.0)
		for line: Array in lines:
			draw_string_outline(font, text_position, line[0], HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH,
				LABEL_FONT_SIZE, LABEL_OUTLINE, LABEL_OUTLINE_COLOR)
			draw_string(font, text_position, line[0], HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH,
				LABEL_FONT_SIZE, line[1])
			text_position.y += LABEL_FONT_SIZE + 2
	draw_set_transform(Vector2.ZERO)
