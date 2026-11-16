# Cámara de la oficina: arrastre con inercia, WASD/flechas, borde de la ventana y zoom por niveles
# con animación que deja fijo el punto bajo el ratón. Su centro no sale del rombo del solar.
# Estado lógico: position y zoom_index; sin cámara suave todo cambia al instante.
class_name OfficeCamera
extends Camera2D

## Píxeles que debe moverse el ratón con el botón izquierdo para que sea arrastre y no clic.
const DRAG_THRESHOLD_PX: float = 6.0

## Giro de rueda (o deslizamiento en el trackpad) para cambiar un nivel.
const WHEEL_STEP: float = 1.0

## Pellizco en el trackpad para cambiar un nivel.
const PINCH_STEP: float = 0.25

## Teclas que mueven la cámara (por posición física, así WASD sirve en toda distribución) y su dirección.
const PAN_KEYS: Dictionary[Key, Vector2] = {
	KEY_W: Vector2.UP, KEY_A: Vector2.LEFT, KEY_S: Vector2.DOWN, KEY_D: Vector2.RIGHT,
	KEY_UP: Vector2.UP, KEY_LEFT: Vector2.LEFT, KEY_DOWN: Vector2.DOWN, KEY_RIGHT: Vector2.RIGHT,
}

## Solo para pruebas: false hace instantáneos zoom, encuadre e inercia aunque la opción esté encendida.
static var smoothing_enabled: bool = true

var zoom_index: int = GameConstants.CAMERA_START_ZOOM_INDEX

## Si el botón izquierdo arrastra la cámara (en construcción no; central y derecho siempre).
var left_drag_enabled: bool = true

## Si devuelve true (un menú encima), teclado y borde no mueven la cámara.
var pan_blocker: Callable = Callable()

# Ya se avisó EventBus.ui_action de este arrastre o movimiento con teclas.
var _drag_reported: bool = false
var _pan_reported: bool = false
# Rombo del mapa (OfficeGrid.get_site_world_area); sin mapa no hay límites.
var _area := Transform2D()
var _has_area: bool = false
var _drag_button: MouseButton = MOUSE_BUTTON_NONE
var _drag_start := Vector2.ZERO
var _is_dragging: bool = false
var _wheel_accumulator: float = 0.0
var _pinch_accumulator: float = 0.0
# Zoom que se ve ahora (llega a get_zoom_level() con la animación).
var _shown_zoom: float = GameConstants.CAMERA_ZOOM_LEVELS[GameConstants.CAMERA_START_ZOOM_INDEX]
# Zoom con la rueda: punto del mundo que queda bajo el ratón.
var _anchored: bool = false
var _anchor_world := Vector2.ZERO
var _anchor_offset := Vector2.ZERO  # desde el centro de la pantalla
# Encuadre animado: el centro va hacia _glide_target.
var _gliding: bool = false
var _glide_target := Vector2.ZERO
# Inercia: velocidad en px de pantalla por segundo.
var _inertia := Vector2.ZERO
var _drag_velocity := Vector2.ZERO
var _last_motion_usec: int = 0


func _ready() -> void:
	_apply_zoom()
	get_viewport().size_changed.connect(_clamp_position)


## Fija el rombo del mapa (px del mundo) por el que se mueve la cámara.
func set_map_area(area: Transform2D) -> void:
	_area = area
	_has_area = true
	_clamp_position()


## Centra la vista en un punto del mundo (dentro del mapa); con animate y cámara suave, se desliza.
func center_on(world_position: Vector2, animate: bool = false) -> void:
	_stop_motion()
	if animate and is_smooth():
		_gliding = true
		_glide_target = _clamped(world_position)
		return
	position = world_position
	_clamp_position()


## Encuadra un rectángulo del mundo con el zoom más cercano en que cabe (con margen para paneles).
## Con animate y cámara suave, animado.
func fit_rect(target: Rect2, animate: bool = false) -> void:
	var available: Vector2 = get_viewport_rect().size * (1.0 - 2.0 * GameConstants.CAMERA_FIT_MARGIN)
	var best: int = 0
	for index: int in range(GameConstants.CAMERA_ZOOM_LEVELS.size()):
		var level: float = GameConstants.CAMERA_ZOOM_LEVELS[index]
		if target.size.x * level <= available.x and target.size.y * level <= available.y:
			best = index
	zoom_index = best
	if not (animate and is_smooth()):
		_shown_zoom = get_zoom_level()
		_apply_zoom()
	center_on(target.get_center(), animate)


## Nivel de zoom de destino (1.0 = un píxel del arte por píxel de pantalla).
func get_zoom_level() -> float:
	return GameConstants.CAMERA_ZOOM_LEVELS[zoom_index]


## Zoom que se ve ahora (distinto de get_zoom_level() durante la animación).
func get_shown_zoom() -> float:
	return _shown_zoom


## Si la cámara se mueve con animaciones (opción «Cámara suave»).
func is_smooth() -> bool:
	return smoothing_enabled and bool(Settings.get_value("smooth_camera"))


## Si hay una animación o una inercia en curso.
func is_moving() -> bool:
	return _anchored or _gliding or _inertia != Vector2.ZERO or not is_equal_approx(_shown_zoom, get_zoom_level())


## Termina al instante la animación o la inercia (la vista queda donde iba).
func finish_motion() -> void:
	position = _final_position()
	_stop_motion()
	_shown_zoom = get_zoom_level()
	_apply_zoom()
	_clamp_position()


## Cambia de nivel de zoom dejando fijo el punto de pantalla dado.
func set_zoom_index(new_index: int, anchor_screen: Vector2) -> void:
	new_index = clampi(new_index, 0, GameConstants.CAMERA_ZOOM_LEVELS.size() - 1)
	if new_index == zoom_index:
		return
	var anchor_offset: Vector2 = anchor_screen - get_viewport_rect().size / 2.0
	var anchor_world: Vector2 = position + anchor_offset / _shown_zoom
	zoom_index = new_index
	_gliding = false
	_inertia = Vector2.ZERO
	if is_smooth():
		_anchored = true
		_anchor_world = anchor_world
		_anchor_offset = anchor_offset
		return
	_anchored = false
	_shown_zoom = get_zoom_level()
	_apply_zoom()
	position = anchor_world - anchor_offset / _shown_zoom
	_clamp_position()


## Estado para guardar: nivel de zoom y centro final de la animación en curso.
func export_state() -> Dictionary:
	var final: Vector2 = _final_position()
	return {"zoom": get_zoom_level(), "x": final.x, "y": final.y}


## Restaura el estado; las partidas viejas guardan solo zoom_index en la lista vieja.
func import_state(state: Dictionary) -> void:
	var level: float = get_zoom_level()
	if state.has("zoom"):
		level = float(state["zoom"])
	elif state.has("zoom_index"):
		var legacy: Array[float] = GameConstants.CAMERA_LEGACY_ZOOM_LEVELS
		level = legacy[clampi(int(state["zoom_index"]), 0, legacy.size() - 1)]
	zoom_index = _nearest_zoom_index(level)
	_stop_motion()
	_shown_zoom = get_zoom_level()
	_apply_zoom()
	position = Vector2(float(state.get("x", position.x)), float(state.get("y", position.y)))
	_clamp_position()


func _process(delta: float) -> void:
	if _drag_button == MOUSE_BUTTON_NONE and not (pan_blocker.is_valid() and bool(pan_blocker.call())):
		_pan(delta)
	_step_inertia(delta)
	_step_zoom(delta)
	_step_glide(delta)


# _unhandled_input solo recibe lo que la interfaz no consumió (arrastrar un panel no mueve la oficina).
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
				_drag_reported = false
				_inertia = Vector2.ZERO
				_drag_velocity = Vector2.ZERO
				_gliding = false
				# Con el botón central o derecho se arrastra desde el primer píxel.
				_is_dragging = event.button_index != MOUSE_BUTTON_LEFT
			elif not event.pressed and event.button_index == _drag_button:
				if _is_dragging:
					get_viewport().set_input_as_handled()
					_start_inertia()
				_drag_button = MOUSE_BUTTON_NONE
				_is_dragging = false


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _drag_button == MOUSE_BUTTON_NONE:
		return
	if not _is_dragging:
		if event.position.distance_to(_drag_start) < DRAG_THRESHOLD_PX:
			return
		_is_dragging = true
		# Recupera lo movido antes de superar el umbral.
		_move_by(-(event.position - event.relative - _drag_start) / _shown_zoom)
		_last_motion_usec = Time.get_ticks_usec()
	_move_by(-event.relative / _shown_zoom)
	_note_drag_velocity(event.relative)
	# El tutorial se entera una vez por arrastre.
	if not _drag_reported:
		_drag_reported = true
		EventBus.ui_action.emit("camera_moved")
	get_viewport().set_input_as_handled()


func _handle_wheel(event: InputEventMouseButton) -> void:
	# Con ratón cada clic de rueda vale 1; el trackpad manda eventos pequeños que se acumulan.
	var amount: float = event.factor if event.factor > 0.0 else 1.0
	var direction: float = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
	if signf(_wheel_accumulator) != direction:
		_wheel_accumulator = 0.0
	_wheel_accumulator += amount * direction
	if absf(_wheel_accumulator) >= WHEEL_STEP:
		_wheel_accumulator = 0.0
		set_zoom_index(zoom_index + int(direction), event.position)
		EventBus.ui_action.emit("camera_moved")
	get_viewport().set_input_as_handled()


func _handle_pinch(event: InputEventMagnifyGesture) -> void:
	_pinch_accumulator += event.factor - 1.0
	if absf(_pinch_accumulator) >= PINCH_STEP:
		var direction: int = 1 if _pinch_accumulator > 0.0 else -1
		_pinch_accumulator = 0.0
		set_zoom_index(zoom_index + direction, event.position)
		EventBus.ui_action.emit("camera_moved")
	get_viewport().set_input_as_handled()


## Dirección en pantalla que piden las teclas; cero si ninguna o si se escribe en un campo de texto.
func get_key_pan_direction() -> Vector2:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return Vector2.ZERO
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT):
		return Vector2.ZERO
	var direction := Vector2.ZERO
	for key: Key in PAN_KEYS:
		var pressed: bool = Input.is_physical_key_pressed(key) if key in [KEY_W, KEY_A, KEY_S, KEY_D] \
			else Input.is_key_pressed(key)
		if pressed:
			direction += PAN_KEYS[key]
	return direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO


## Dirección por el ratón en el borde de la ventana (opción). window_point en px de la ventana;
## sobre la interfaz no se mueve.
func get_edge_pan_direction(window_point: Vector2, window_size: Vector2) -> Vector2:
	if not bool(Settings.get_value("edge_pan")):
		return Vector2.ZERO
	if not Rect2(Vector2.ZERO, window_size).has_point(window_point):
		return Vector2.ZERO
	if get_viewport().gui_get_hovered_control() != null:
		return Vector2.ZERO
	var edge: float = GameConstants.CAMERA_EDGE_PAN_PX
	var direction := Vector2.ZERO
	if window_point.x < edge:
		direction.x = -1.0
	elif window_point.x >= window_size.x - edge:
		direction.x = 1.0
	if window_point.y < edge:
		direction.y = -1.0
	elif window_point.y >= window_size.y - edge:
		direction.y = 1.0
	return direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO


# Teclado y borde. El borde solo con ventana real y foco (si no, el ratón quedaría pegado al borde).
func _pan(delta: float) -> void:
	var velocity: Vector2 = get_key_pan_direction() * GameConstants.CAMERA_KEY_PAN_SPEED
	if velocity == Vector2.ZERO and DisplayServer.get_name() != "headless" and get_window().has_focus():
		var window: Window = get_window()
		var point: Vector2 = Vector2(DisplayServer.mouse_get_position() - window.position)
		velocity = get_edge_pan_direction(point, Vector2(window.size)) * GameConstants.CAMERA_EDGE_PAN_SPEED
	if velocity == Vector2.ZERO:
		_pan_reported = false
		return
	_gliding = false
	_inertia = Vector2.ZERO
	_move_by(velocity * delta / _shown_zoom)
	if not _pan_reported:
		_pan_reported = true
		EventBus.ui_action.emit("camera_moved")


# Mueve el centro (px del mundo) sin salir del mapa y devuelve lo movido de verdad. El ancla del zoom se mueve igual.
func _move_by(world_delta: Vector2) -> Vector2:
	var before: Vector2 = position
	position += world_delta
	_clamp_position()
	var moved: Vector2 = position - before
	if _anchored:
		_anchor_world += moved
	return moved


func _note_drag_velocity(relative: Vector2) -> void:
	var now: int = Time.get_ticks_usec()
	var seconds: float = (now - _last_motion_usec) / 1000000.0
	_last_motion_usec = now
	if seconds <= 0.0:
		return
	var sample: Vector2 = relative / seconds
	_drag_velocity = sample if seconds > 0.1 else _drag_velocity.lerp(sample, 0.6)


func _start_inertia() -> void:
	_inertia = Vector2.ZERO
	if not is_smooth():
		return
	if Time.get_ticks_usec() - _last_motion_usec > GameConstants.CAMERA_INERTIA_RELEASE_MS * 1000:
		return
	if _drag_velocity.length() < GameConstants.CAMERA_INERTIA_MIN_SPEED:
		return
	_inertia = _drag_velocity.limit_length(GameConstants.CAMERA_INERTIA_MAX_SPEED)


func _step_inertia(delta: float) -> void:
	if _inertia == Vector2.ZERO:
		return
	var wanted: Vector2 = -_inertia * delta / _shown_zoom
	var moved: Vector2 = _move_by(wanted)
	# Contra el borde del mapa se frena del todo.
	if moved.distance_to(wanted) > 0.01:
		_inertia = Vector2.ZERO
		return
	_inertia *= exp(-GameConstants.CAMERA_INERTIA_FRICTION * delta)
	if _inertia.length() < GameConstants.CAMERA_INERTIA_MIN_SPEED:
		_inertia = Vector2.ZERO


func _step_zoom(delta: float) -> void:
	var target: float = get_zoom_level()
	if _shown_zoom != target:
		if not is_smooth():
			_shown_zoom = target
		else:
			# En escala logarítmica, así acercar y alejar se sienten igual.
			var weight: float = 1.0 - exp(-GameConstants.CAMERA_SMOOTH_SPEED * delta)
			_shown_zoom = exp(lerpf(log(_shown_zoom), log(target), weight))
			if absf(_shown_zoom - target) < target * 0.002:
				_shown_zoom = target
		_apply_zoom()
	if _anchored:
		position = _anchor_world - _anchor_offset / _shown_zoom
		_clamp_position()
		if _shown_zoom == target:
			_anchored = false


func _step_glide(delta: float) -> void:
	if not _gliding:
		return
	if not is_smooth():
		position = _glide_target
		_gliding = false
		return
	var weight: float = 1.0 - exp(-GameConstants.CAMERA_SMOOTH_SPEED * delta)
	position = position.lerp(_glide_target, weight)
	if position.distance_to(_glide_target) < 0.5:
		position = _glide_target
		_gliding = false
	_clamp_position()


# Centro de la vista al terminar la animación.
func _final_position() -> Vector2:
	if _gliding:
		return _glide_target
	if _anchored:
		return _clamped(_anchor_world - _anchor_offset / get_zoom_level())
	return position


func _stop_motion() -> void:
	_anchored = false
	_gliding = false
	_inertia = Vector2.ZERO


func _nearest_zoom_index(level: float) -> int:
	var best: int = 0
	for index: int in range(GameConstants.CAMERA_ZOOM_LEVELS.size()):
		if absf(GameConstants.CAMERA_ZOOM_LEVELS[index] - level) < absf(GameConstants.CAMERA_ZOOM_LEVELS[best] - level):
			best = index
	return best


func _apply_zoom() -> void:
	zoom = Vector2.ONE * _shown_zoom


# Mantiene el centro dentro del rombo del mapa.
func _clamp_position() -> void:
	position = _clamped(position)


# Pasa el punto al rombo (0 a 1 por lado), lo recorta y vuelve al mundo. Dentro no se toca (redondeo).
func _clamped(point: Vector2) -> Vector2:
	if not _has_area:
		return point
	var local: Vector2 = _area.affine_inverse() * point
	var clamped: Vector2 = local.clamp(Vector2.ZERO, Vector2.ONE)
	return point if clamped == local else _area * clamped
