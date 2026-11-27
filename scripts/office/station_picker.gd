# Elegir en el mapa el puesto nuevo de un empleado: marca con su contorno los puestos a los que puede pasar
# (verde libre, azul ocupado: intercambian) y el suyo; un clic sobre la silla o el escritorio lo cambia
# (Staff.move_to_station), clic derecho o Esc (cancel) lo deja como estaba.
class_name StationPicker
extends Node2D

## Terminó la elección: message es el resultado, o "" si se canceló.
signal finished(message: String)

const FREE_COLOR := UiTheme.POSITIVE
const TAKEN_COLOR := UiTheme.INFO
const OWN_COLOR := UiTheme.ACCENT
## Grosor de las líneas en px de pantalla (no cambia con el zoom).
const HOVER_WIDTH: float = 3.5
const LINE_WIDTH: float = 2.0
## Alfa del rombo bajo la silla de cada puesto (más con el ratón encima).
const FILL_ALPHA: float = 0.28
const HOVER_FILL_ALPHA: float = 0.5
const DASH: int = 6
const GAP: float = 1.0
## Movimiento máximo (px) entre apretar y soltar para que cuente como clic y no como arrastre de la cámara.
const CLICK_TOLERANCE_PX: float = 8.0

var _grid: OfficeGrid
var _employee_id: int = 0
var _choices: Array[Dictionary] = []
var _hover: int = -1
var _press_position := Vector2.ZERO
var _zoom: float = 0.0


func setup(grid: OfficeGrid) -> void:
	_grid = grid
	EventBus.office_changed.connect(_refresh)
	EventBus.staff_changed.connect(_refresh)


## Empieza a elegir el puesto de un empleado; devuelve {"ok", "message"} (no empieza si no hay a dónde ir).
func start(employee_id: int) -> Dictionary:
	var choices: Array[Dictionary] = Staff.get_station_choices(employee_id)
	if choices.is_empty():
		return {"ok": false, "message": "No hay otro puesto para %s." % Staff.get_employee(employee_id).get("name", "?")}
	_employee_id = employee_id
	_refresh()
	return {"ok": true, "message": "Elige en el mapa el puesto nuevo de %s (verde libre, azul intercambian; clic derecho o Esc cancela)." % Staff.get_employee(employee_id)["name"]}


func is_active() -> bool:
	return _employee_id != 0


func get_employee_id() -> int:
	return _employee_id


func cancel() -> void:
	if is_active():
		_stop()
		finished.emit("")


## Puestos que se ofrecen (ver Staff.get_station_choices).
func get_choices() -> Array[Dictionary]:
	return _choices


## Índice en get_choices del puesto cuya silla o escritorio está en cell, o -1.
func get_choice_at(cell: Vector2i) -> int:
	for index: int in range(_choices.size()):
		for part: String in ["chair", "desk"]:
			var item: Dictionary = OfficeState.furniture[_choices[index][part]]
			if FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"]).has(cell):
				return index
	return -1


## Pasa al empleado al puesto de cell (como el clic); devuelve {"ok", "message"}.
func pick_at(cell: Vector2i) -> Dictionary:
	var index: int = get_choice_at(cell)
	if index < 0:
		return {"ok": false, "message": "Elige una silla o un escritorio marcado."}
	var result: Dictionary = Staff.move_to_station(_employee_id, int(_choices[index]["chair"]))
	if result["ok"]:
		_stop()
		finished.emit(result["message"])
	return result


func _stop() -> void:
	_employee_id = 0
	_choices.clear()
	_hover = -1
	queue_redraw()


# Al cambiar la oficina o el personal se recalculan los puestos; si el empleado ya no está, se cancela.
func _refresh() -> void:
	if not is_active():
		return
	if Staff.get_employee(_employee_id).is_empty():
		cancel()
		return
	_choices = Staff.get_station_choices(_employee_id)
	queue_redraw()


func _process(_delta: float) -> void:
	if is_active() and get_canvas_transform().get_scale().x != _zoom:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or _grid == null:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var hover: int = get_choice_at(_cell_at(motion.position))
		if hover != _hover:
			_hover = hover
			queue_redraw()
		return
	var button := event as InputEventMouseButton
	if button == null:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT and not button.pressed:
		cancel()
		get_viewport().set_input_as_handled()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press_position = button.position
		elif _press_position.distance_to(button.position) <= CLICK_TOLERANCE_PX:
			var result: Dictionary = pick_at(_cell_at(button.position))
			if not result["ok"]:
				EventBus.notice.emit(result["message"])
			get_viewport().set_input_as_handled()


func _cell_at(screen_position: Vector2) -> Vector2i:
	return Vector2i(_grid.world_to_grid(_grid.screen_to_world(screen_position)).round())


func _draw() -> void:
	if not is_active() or _grid == null:
		return
	_zoom = get_canvas_transform().get_scale().x
	var scale: float = 1.0 / maxf(_zoom, 0.01)
	var own: Dictionary = OfficeState.find_furniture_assigned_to(Staff.employee_key(_employee_id))
	if not own.is_empty():
		_draw_cell(own["cell"], OWN_COLOR, FILL_ALPHA)
		draw_multiline(_grid.get_furniture_outline(own, DASH, GAP), OWN_COLOR, LINE_WIDTH * scale)
	for index: int in range(_choices.size()):
		var choice: Dictionary = _choices[index]
		var color: Color = FREE_COLOR if String(choice["owner"]).is_empty() else TAKEN_COLOR
		var hovered: bool = index == _hover
		_draw_cell(OfficeState.furniture[choice["chair"]]["cell"], color, HOVER_FILL_ALPHA if hovered else FILL_ALPHA)
		for part: String in ["chair", "desk"]:
			var outline: PackedVector2Array = _grid.get_furniture_outline(OfficeState.furniture[choice[part]], DASH, GAP)
			if not outline.is_empty():
				draw_multiline(outline, color, (HOVER_WIDTH if hovered else LINE_WIDTH) * scale)


# Rombo de color en el piso de una casilla.
func _draw_cell(cell: Vector2i, color: Color, alpha: float) -> void:
	var center := Vector2(cell)
	var points := PackedVector2Array()
	for corner: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		points.append(_grid.grid_to_world(center + corner))
	draw_colored_polygon(points, Color(color, alpha))
