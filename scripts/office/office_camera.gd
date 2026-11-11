# Cámara de la oficina: se arrastra con el ratón, hace zoom en niveles fijos con la
# rueda y no deja alejarse del local más que un margen (CAMERA_OVERSCROLL_RATIO).
class_name OfficeCamera
extends Camera2D

## Píxeles que hay que mover el ratón con el botón izquierdo pulsado para que cuente
## como arrastre y no como clic (así el clic queda libre para construir o inspeccionar).
const DRAG_THRESHOLD_PX: float = 6.0

## Cuánto hay que girar la rueda (o deslizar en el trackpad) para cambiar un nivel.
const WHEEL_STEP: float = 1.0

## Cuánto hay que pellizcar en el trackpad para cambiar un nivel.
const PINCH_STEP: float = 0.25

var zoom_index: int = GameConstants.CAMERA_START_ZOOM_INDEX

## Si el botón izquierdo arrastra la cámara. En modo construcción se apaga, porque el
## botón izquierdo construye; el central y el derecho siguen moviéndola.
var left_drag_enabled: bool = true

var _bounds := Rect2()
var _drag_button: MouseButton = MOUSE_BUTTON_NONE
var _drag_start := Vector2.ZERO
var _is_dragging: bool = false
var _wheel_accumulator: float = 0.0
var _pinch_accumulator: float = 0.0


func _ready() -> void:
	_apply_zoom()
	get_viewport().size_changed.connect(_clamp_position)


## Fija el rectángulo del local (en píxeles del mundo) y centra la cámara en él.
func set_bounds(bounds: Rect2) -> void:
	_bounds = bounds
	position = bounds.get_center()
	_clamp_position()


## Nivel de zoom actual (1.0 = un píxel del arte por píxel de pantalla).
func get_zoom_level() -> float:
	return GameConstants.CAMERA_ZOOM_LEVELS[zoom_index]


## Cambia al nivel de zoom indicado manteniendo fijo el punto de pantalla dado,
## para que la casilla bajo el ratón no se escape al acercar o alejar.
func set_zoom_index(new_index: int, anchor_screen: Vector2) -> void:
	new_index = clampi(new_index, 0, GameConstants.CAMERA_ZOOM_LEVELS.size() - 1)
	if new_index == zoom_index:
		return
	var anchor_offset: Vector2 = anchor_screen - get_viewport_rect().size / 2.0
	var anchor_world: Vector2 = position + anchor_offset / get_zoom_level()
	zoom_index = new_index
	_apply_zoom()
	position = anchor_world - anchor_offset / get_zoom_level()
	_clamp_position()


## Devuelve el estado de la cámara para guardarlo (hito 9).
func export_state() -> Dictionary:
	return {"zoom_index": zoom_index, "x": position.x, "y": position.y}


## Restaura el estado de la cámara desde una partida guardada (hito 9).
func import_state(state: Dictionary) -> void:
	zoom_index = clampi(int(state.get("zoom_index", zoom_index)), 0, GameConstants.CAMERA_ZOOM_LEVELS.size() - 1)
	_apply_zoom()
	position = Vector2(float(state.get("x", position.x)), float(state.get("y", position.y)))
	_clamp_position()


# _unhandled_input recibe solo lo que la interfaz no consumió: así, en hitos
# posteriores, arrastrar sobre un panel no moverá la oficina.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventMagnifyGesture:
		_handle_pinch(event as InputEventMagnifyGesture)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_handle_wheel(event)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			if event.button_index == MOUSE_BUTTON_LEFT and not left_drag_enabled:
				return
			if event.pressed and _drag_button == MOUSE_BUTTON_NONE:
				_drag_button = event.button_index
				_drag_start = event.position
				# Con el botón central o derecho se arrastra desde el primer píxel.
				_is_dragging = event.button_index != MOUSE_BUTTON_LEFT
			elif not event.pressed and event.button_index == _drag_button:
				if _is_dragging:
					get_viewport().set_input_as_handled()
				_drag_button = MOUSE_BUTTON_NONE
				_is_dragging = false


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _drag_button == MOUSE_BUTTON_NONE:
		return
	if not _is_dragging:
		if event.position.distance_to(_drag_start) < DRAG_THRESHOLD_PX:
			return
		_is_dragging = true
		# Recupera lo que se movió el ratón antes de superar el umbral.
		position -= (event.position - event.relative - _drag_start) / get_zoom_level()
	position -= event.relative / get_zoom_level()
	_clamp_position()
	get_viewport().set_input_as_handled()


func _handle_wheel(event: InputEventMouseButton) -> void:
	# Con ratón cada clic de rueda vale 1; el trackpad manda muchos eventos pequeños,
	# por eso se acumulan hasta completar un paso.
	var amount: float = event.factor if event.factor > 0.0 else 1.0
	var direction: float = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
	if signf(_wheel_accumulator) != direction:
		_wheel_accumulator = 0.0
	_wheel_accumulator += amount * direction
	if absf(_wheel_accumulator) >= WHEEL_STEP:
		_wheel_accumulator = 0.0
		set_zoom_index(zoom_index + int(direction), event.position)
	get_viewport().set_input_as_handled()


func _handle_pinch(event: InputEventMagnifyGesture) -> void:
	_pinch_accumulator += event.factor - 1.0
	if absf(_pinch_accumulator) >= PINCH_STEP:
		var direction: int = 1 if _pinch_accumulator > 0.0 else -1
		_pinch_accumulator = 0.0
		set_zoom_index(zoom_index + direction, event.position)
	get_viewport().set_input_as_handled()


func _apply_zoom() -> void:
	zoom = Vector2.ONE * get_zoom_level()


# Mantiene la vista cerca del local. En cada eje, el borde de la vista puede pasarse
# del local como mucho un margen; si la vista es más grande que el local con su
# margen (zoom lejano), es el local el que no puede salirse de la vista.
func _clamp_position() -> void:
	if not _bounds.has_area():
		return
	var view_half: Vector2 = get_viewport_rect().size / 2.0 / get_zoom_level()
	var margin: Vector2 = get_viewport_rect().size * GameConstants.CAMERA_OVERSCROLL_RATIO / get_zoom_level()
	var low: Vector2 = _bounds.position - margin + view_half
	var high: Vector2 = _bounds.end + margin - view_half
	position = Vector2(
		clampf(position.x, minf(low.x, high.x), maxf(low.x, high.x)),
		clampf(position.y, minf(low.y, high.y), maxf(low.y, high.y)),
	)
