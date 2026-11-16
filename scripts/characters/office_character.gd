# Personaje de la oficina (CEO o empleado): entra, camina a su silla, se sienta y sale.
# La escena decide cuándo con update_routine; la lógica va en casillas (grid_position).
class_name OfficeCharacter
extends Node2D

## Llegó a su silla y se sentó.
signal sat_down
## Salió del local por la entrada.
signal left_office

## STEPPING_OUT: sale del edificio a buscar un baño (faltan inodoros) y vuelve.
enum Activity { AWAY, WALKING_TO_DESK, SEATED, WALKING_OUT, STEPPING_OUT }

# Muñeco provisional: ~32×64 px de pie, achicado por BODY_SCALE.
const PANTS_COLOR := Color("2f3b52")
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.25)
const SEAT_HEIGHT_PX: float = 14.0
## Escala del muñeco: con 0.8 mide ~50 px de pie (1.7 m frente a un escritorio de 75 cm).
## El icono de estado no se achica.
const BODY_SCALE: float = 0.8
## Iconos de estado (Staff.get_status_icon): color del globo y signo.
const STATUS_ICONS: Dictionary[String, Array] = {
	"no_station": [Color("8a8f99"), "?"],
	"tired": [Color("5b8bd9"), "z"],
	"upset": [Color("d9534f"), "!"],
	"stressed": [Color("e08a2c"), "#"],
	"idle": [Color("a6a6a6"), "…"],
}
const ICON_RADIUS: float = 7.0
const ICON_FONT_SIZE: int = 11
## Zona de clic relativa al punto de apoyo (ya con BODY_SCALE).
const CLICK_AREA := Rect2(-10.0, -52.0, 20.0, 56.0)
## Ciclos de caminar por casilla y segundos reales por cuadro de las poses quietas.
const WALK_CYCLES_PER_CELL: float = 1.5
const FRAME_SECONDS: Dictionary[String, float] = {"idle": 0.45, "type": 0.14, "mop": 0.3}
## Dónde queda el cubo de quien trapea: casillas a su izquierda y hacia atrás.
const BUCKET_SIDE: float = 0.42
const BUCKET_BACK: float = 0.12
## Posición del icono de estado sobre la cabeza, de pie y sentado.
const SPRITE_ICON_STANDING := Vector2(11.0, -52.0)
const SPRITE_ICON_SEATED := Vector2(11.0, -46.0)
## Sentado de espaldas: franja del sprite que se dibuja, desde el asiento hacia arriba.
const SEATED_BACK_BAND := Vector2(21.0, 128.0)
## Franja de antebrazos y manos del sprite sentado, en px sobre los pies.
const HANDS_BAND := Vector2(41.0, 52.0)
## Paletas de cada conjunto (base, piel oscura, piel clara).
const LOOK_VARIANTS: Array[String] = ["", "_v1", "_v2"]
## Ninguna casilla (para _release_cells).
const NO_CELL := Vector2i(-1000000, -1000000)

## "ceo" o Staff.employee_key(id) (igual que assigned_to en su silla).
var person_key: String = ""
## Nombre para los avisos ("El CEO", "Ana Pérez").
var display_name: String = ""
var shirt_color := Color("e8e4dc")
## Corbata; transparente si no lleva.
var tie_color := Color(0.0, 0.0, 0.0, 0.0)
var skin_color := Color("d9a47a")
var hair_color := Color("3b2a20")

## Hoja de sprites (ver make_look); sin ella se dibuja el muñeco provisional.
var look: String = "":
	set(value):
		look = value
		queue_redraw()
## Teclea al sentarse frente a una computadora (las visitas no).
var can_type: bool = true

var activity: Activity = Activity.AWAY
## Icono de estado ("" ninguno; claves de STATUS_ICONS).
var status_icon: String = ""
## Se queda de pie al llegar en vez de sentarse (quien llega antes y espera).
var standing: bool = false:
	set(value):
		standing = value
		_animate(0.0, Vector2.ZERO)
		_update_position()
		queue_redraw()
## Con prisa camina CHARACTER_HURRY_FACTOR veces más rápido hasta llegar.
var hurry: bool = false
## Posición en la cuadrícula; con decimales mientras camina.
var grid_position := Vector2.ZERO

var _grid: OfficeGrid
var _pathfinder: OfficePathfinder
var _seat_cell := Vector2i.ZERO
var _entrance := Vector2i.ZERO
var _outside := Vector2i.ZERO
# Casillas por recorrer; la primera es la siguiente.
var _path: Array[Vector2i] = []
# Una persona por casilla del local: casilla → personaje (la suya y, caminando, la siguiente).
static var _occupants: Dictionary = {}
# Fila en la puerta: quienes esperan en la calle, por orden de llegada.
static var _door_queue: Array = []
# Sillas dibujadas junto con quien se sienta (casilla → personaje); FurnitureView usa draws_chair_at.
static var _chairs_drawn: Dictionary = {}
# Casillas del local que ocupa este personaje.
var _held: Array[Vector2i] = []
# Segundos (a 1x) esperando a que se libere la siguiente casilla.
var _blocked_time: float = 0.0
var _next_repath: float = GameConstants.CHARACTER_REPATH_WAIT
# Estado del sprite: dirección (0–3, como las rotaciones), pose y cuadro.
var _facing: int = 2
var _pose: String = "stand"
var _frame: int = 0
var _walk_phase: float = 0.0
var _anim_time: float = 0.0
# Asiento de su lugar: dirección sentado (-1 si no hay) y si queda frente a una computadora.
var _seat_facing: int = -1
var _at_computer: bool = false
# Mueble de su asiento ("" si no hay), para el cuadro «sentado en esa silla».
var _seat_item: String = ""
var _claimed_chair := Vector2i(-1000000, -1000000)
# Cuánto se arrima sentado al escritorio de delante, en casillas.
var _tuck := Vector2.ZERO
# Pieza que dibuja las manos sobre el escritorio (_draw_hands).
var _hands: Node2D
# Cubo de trapear: pieza aparte para ordenarse con los muebles (_draw_bucket).
var _bucket: Node2D
## Personal de limpieza en su turno: camina con el suape y, parado en su lugar, trapea con el
## cubo al lado (si su aspecto tiene esas poses).
var cleaning: bool = false:
	set(value):
		if value == cleaning:
			return
		cleaning = value
		_animate(0.0, Vector2.ZERO)
		_update_position()


## Prepara al personaje (lo llama la escena). outside es la casilla de la calle frente a la
## entrada; empieza fuera y update_routine lo hace entrar.
func setup(grid: OfficeGrid, pathfinder: OfficePathfinder, seat_cell: Vector2i,
		entrance: Vector2i, outside: Vector2i) -> void:
	_grid = grid
	_pathfinder = pathfinder
	_seat_cell = seat_cell
	_entrance = entrance
	_outside = outside
	grid_position = Vector2(entrance)
	# Desfasa la animación para que no se muevan todos a la vez.
	_anim_time = float(absi(person_key.hash()) % 997) / 100.0
	if _hands == null:
		# Con y_sort_enabled la pieza de las manos se ordena con los muebles.
		y_sort_enabled = true
		_hands = Node2D.new()
		_hands.name = "Hands"
		_hands.draw.connect(_draw_hands)
		add_child(_hands)
		_bucket = Node2D.new()
		_bucket.name = "Bucket"
		_bucket.draw.connect(_draw_bucket)
		add_child(_bucket)
	if not EventBus.office_changed.is_connected(_refresh_seat):
		EventBus.office_changed.connect(_refresh_seat)
	_set_activity(Activity.AWAY)
	visible = false
	_update_position()


## Aspecto: conjunto de ropa ("casual", "office", "executive" o "cleaning"; de mujer si woman) y paleta según number.
static func make_look(woman: bool, outfit: String, number: int) -> String:
	var base: String = outfit
	if woman:
		base = "woman" if outfit == "casual" else "woman_" + outfit
	return base + LOOK_VARIANTS[posmod(number, LOOK_VARIANTS.size())]


## Indica si un nombre es de mujer (por su primer nombre en data/names.json).
static func is_woman_name(full_name: String) -> bool:
	return StaffCatalog.get_first_names("female").has(full_name.get_slice(" ", 0))


## Indica si la silla de esa casilla se dibuja junto con quien está sentado.
static func draws_chair_at(cell: Vector2i) -> bool:
	var who: Variant = _chairs_drawn.get(cell)
	return who != null and is_instance_valid(who)


# Pose con la silla dibujada si las hojas la traen; si no, la pose suelta.
func _drawn_pose() -> String:
	if (_pose == "sit" or _pose == "type") and not _seat_item.is_empty():
		var joined: String = "%s_%s" % [_pose, _seat_item]
		if SpriteLibrary.has_character_pose(joined):
			return joined
	return _pose


# Avisa a las sillas si esta se dibuja ahora con su ocupante.
func _update_chair_claim() -> void:
	var cell: Vector2i = _seat_cell if visible and SpriteLibrary.has_character_look(look) and _drawn_pose() != _pose else NO_CELL
	if cell == _claimed_chair:
		return
	if _chairs_drawn.get(_claimed_chair) == self:
		_chairs_drawn.erase(_claimed_chair)
	_claimed_chair = cell
	if cell != NO_CELL:
		_chairs_drawn[cell] = self
	if is_inside_tree():
		get_tree().call_group(FurnitureView.CHAIR_GROUP, "queue_redraw")


## Estado del sprite: {pose, facing, frame}.
func get_sprite_state() -> Dictionary:
	return {"pose": _pose, "facing": _facing, "frame": _frame}


## Casilla en la que está (la más cercana si va entre dos).
func get_cell() -> Vector2i:
	return Vector2i(grid_position.round())


## Casilla de su silla.
func get_seat_cell() -> Vector2i:
	return _seat_cell


## Casillas que le faltan por recorrer.
func get_path_cells() -> Array[Vector2i]:
	return _path.duplicate()


## Indica si un punto del mundo cae sobre el personaje (para el clic).
func contains_point(world_point: Vector2) -> bool:
	return visible and CLICK_AREA.has_point(world_point - position)


## Entra si expected y está fuera o saliendo; sale si no y está dentro o llegando.
func update_routine(expected: bool) -> void:
	if expected and (activity == Activity.AWAY or activity == Activity.WALKING_OUT):
		if activity == Activity.AWAY:
			# Aparece en la entrada; si está ocupada, espera en la calle.
			_release_cells()
			grid_position = Vector2(_entrance) if _door_queue_front() == null and _claim(_entrance, false) \
				else Vector2(_outside)
			visible = true
		_walk_to(_seat_cell, Activity.WALKING_TO_DESK)
	elif not expected and (activity == Activity.SEATED or activity == Activity.WALKING_TO_DESK
			or activity == Activity.STEPPING_OUT):
		if not _grid.is_in_lot(get_cell()) and (_door_queue.has(self) or not visible):
			# Aún en la calle: se va sin cruzar la puerta, así no tapa la entrada.
			_path.clear()
			_door_queue.erase(self)
			_set_activity(Activity.WALKING_OUT)
			_on_destination_reached()
			return
		hurry = false
		_walk_to(_entrance, Activity.WALKING_OUT, [_outside])


## Sentado, sale a buscar un baño y vuelve a su silla. False si no estaba sentado.
func step_out() -> bool:
	if activity != Activity.SEATED:
		return false
	_walk_to(_entrance, Activity.STEPPING_OUT, [_outside])
	return true


## Cambia su silla; si estaba en la oficina, camina hasta la nueva.
func set_seat(seat_cell: Vector2i) -> void:
	if seat_cell == _seat_cell:
		return
	_seat_cell = seat_cell
	if activity == Activity.SEATED or activity == Activity.WALKING_TO_DESK:
		_walk_to(_seat_cell, Activity.WALKING_TO_DESK)


## Recalcula el camino hacia donde iba (por ejemplo, tras construir).
func replan() -> void:
	_replan_avoiding([])


# Como replan, esquivando avoid si se puede.
func _replan_avoiding(avoid: Array[Vector2i]) -> void:
	_refresh_entrance()
	match activity:
		Activity.WALKING_TO_DESK:
			_walk_to(_seat_cell, Activity.WALKING_TO_DESK, [], avoid)
		Activity.SEATED:
			# Sentado fuera de su lugar (partida vieja): va a su lugar.
			if get_cell() != _seat_cell:
				_walk_to(_seat_cell, Activity.WALKING_TO_DESK, [], avoid)
		Activity.WALKING_OUT:
			_walk_to(_entrance, Activity.WALKING_OUT, [_outside], avoid)
		Activity.STEPPING_OUT:
			_walk_to(_entrance, Activity.STEPPING_OUT, [_outside], avoid)


func _process(delta: float) -> void:
	if activity == Activity.AWAY:
		_release_cells()
		_door_queue.erase(self)
		return
	# Parado en una casilla que no tiene (al cargar o aparecer): la toma.
	if _held.is_empty() and grid_position == Vector2(get_cell()):
		_claim(get_cell(), true)
	var before: Vector2 = grid_position
	if not _path.is_empty():
		_advance(GameClock.get_time_scale() * delta)
	# Al llegar toma la pose de su lugar en este mismo cuadro.
	_animate(delta, grid_position - before if not _path.is_empty() else Vector2.ZERO)


# Avanza lo que da el tiempo de juego transcurrido.
func _advance(scaled_delta: float) -> void:
	var step: float = GameConstants.CHARACTER_WALK_SPEED * scaled_delta \
		* (GameConstants.CHARACTER_HURRY_FACTOR if hurry else 1.0)
	while step > 0.0 and not _path.is_empty():
		var next: Vector2i = _path[0]
		# Dentro del local, tras esperar mucho, pasa igual; afuera espera siempre.
		var inside: bool = _grid.is_in_lot(get_cell())
		var force: bool = _blocked_time >= GameConstants.CHARACTER_PASS_WAIT and inside
		# Desde la calle se entra por turno: primero el que espera hace más.
		var my_turn: bool = inside or _held.has(next) or not _grid.is_in_lot(next) or _door_queue_front() in [null, self]
		if not my_turn or not _claim(next, force):
			if not inside and not _door_queue.has(self):
				_door_queue.append(self)
			_on_blocked(scaled_delta)
			break
		if not inside:
			_door_queue.erase(self)
		visible = true
		var target := Vector2(next)
		var distance: float = grid_position.distance_to(target)
		if distance <= step:
			grid_position = target
			step -= distance
			_path.pop_front()
			_release_cells(next)
			_blocked_time = 0.0
			_next_repath = GameConstants.CHARACTER_REPATH_WAIT
		else:
			grid_position = grid_position.move_toward(target, step)
			step = 0.0
	_update_position()
	if _path.is_empty():
		_on_destination_reached()


# Elige pose, dirección y cuadro; moved es lo avanzado en este cuadro (casillas). Redibuja solo si cambia.
func _animate(delta: float, moved: Vector2) -> void:
	if look.is_empty():
		return
	var pose: String = "idle"
	var facing: int = _facing
	var frame: int = 0
	if moved != Vector2.ZERO:
		pose = "mopwalk" if _has_mop() else "walk"
		facing = _facing_of(moved)
		_walk_phase = fposmod(_walk_phase + moved.length() * WALK_CYCLES_PER_CELL, 1.0)
		frame = int(_walk_phase * SpriteLibrary.get_character_frames(pose))
	else:
		if GameClock.get_time_scale() > 0.0:
			_anim_time += delta
		if _is_sitting():
			pose = "type" if _at_computer and can_type else "sit"
			facing = _seat_facing
		elif is_mopping():
			pose = "mop"
			# Cada casilla hacia otro lado, así se le ve trapear de frente y de espaldas.
			facing = posmod(_seat_cell.x + 3 * _seat_cell.y, 4)
		if FRAME_SECONDS.has(pose):
			frame = int(_anim_time / FRAME_SECONDS[pose]) % maxi(SpriteLibrary.get_character_frames(pose), 1)
	if pose != _pose or facing != _facing or frame != _frame:
		_pose = pose
		_facing = facing
		_frame = frame
		queue_redraw()
		if _hands != null:
			_hands.queue_redraw()
		_place_bucket()
	_update_chair_claim()


# Dirección (0–3) hacia la que avanza.
static func _facing_of(moved: Vector2) -> int:
	if absf(moved.x) >= absf(moved.y):
		return 1 if moved.x > 0.0 else 3
	return 2 if moved.y > 0.0 else 0


# Si su lugar es un asiento, hacia dónde mira sentado: al escritorio o mostrador de delante
# (arrimado como su silla); si no, al frente del asiento.
func _refresh_seat() -> void:
	_refresh_entrance()
	_seat_facing = -1
	_at_computer = false
	_seat_item = ""
	_tuck = Vector2.ZERO
	var index: int = OfficeState.find_furniture_at(_seat_cell)
	if index >= 0:
		var seat: Dictionary = OfficeState.furniture[index]
		var info: Dictionary = FurnitureCatalog.get_item(seat["id"])
		if bool(info.get("is_seat", false)) or bool(info.get("waiting_seat", false)):
			_seat_facing = posmod(int(seat["rotation"]), 4)
			_seat_item = String(seat["id"])
			var desk: Dictionary = OfficeState.get_desk_facing(_seat_cell) if FurnitureView.has_backrest(seat["id"]) else {}
			if not desk.is_empty():
				_seat_facing = int(desk["direction"])
				_at_computer = bool(desk["computer"])
				_tuck = Vector2(FurnitureCatalog.get_front(_seat_facing)) * FurnitureView.SEAT_TUCK \
					+ FurnitureView.get_seat_shift(_seat_cell)
	_animate(0.0, Vector2.ZERO)
	_update_position()


# La entrada puede moverse (terreno frente a la puerta): toma la actual.
func _refresh_entrance() -> void:
	_entrance = OfficeState.entrance
	_outside = OfficeState.get_outside_of_entrance()


# Lleva el suape: de limpieza en su turno y con las poses del suape en su aspecto.
func _has_mop() -> bool:
	return cleaning and SpriteLibrary.has_tool_look(look)


## Indica si está trapeando: llegó a su lugar (que no es un asiento) con el suape.
func is_mopping() -> bool:
	return _has_mop() and activity == Activity.SEATED and not _is_sitting()


# El cubo, a la izquierda de hacia donde mira y un poco atrás; solo se ve mientras trapea.
func _place_bucket() -> void:
	if _bucket == null or _grid == null:
		return
	_bucket.visible = is_mopping() and not SpriteLibrary.get_bucket_sprite().is_empty()
	if not _bucket.visible:
		return
	var front := Vector2(FurnitureCatalog.get_front(_facing))
	var side := Vector2(front.y, -front.x)
	_bucket.position = _grid.grid_to_world(grid_position + side * BUCKET_SIDE - front * BUCKET_BACK) - position
	_bucket.queue_redraw()


func _draw_bucket() -> void:
	var sprite: String = SpriteLibrary.get_bucket_sprite()
	SpriteLibrary.draw_shadow(_bucket, sprite + "_shadow")
	SpriteLibrary.draw(_bucket, sprite)


# Indica si se dibuja sentado en su asiento.
func _is_sitting() -> bool:
	return activity == Activity.SEATED and not standing and _seat_facing >= 0


# Mirando a +x o +y el escritorio se dibuja después y taparía las manos: esta pieza repite
# la franja de antebrazos justo después del escritorio.
func _draw_hands() -> void:
	if _hands_shown():
		SpriteLibrary.draw_character(_hands, look, _drawn_pose(), _facing, _frame, -_hands.position, HANDS_BAND)


func _hands_shown() -> bool:
	return _pose == "type" and _tuck != Vector2.ZERO and (_facing == 1 or _facing == 2) and SpriteLibrary.has_character_look(look)


func _exit_tree() -> void:
	if _chairs_drawn.get(_claimed_chair) == self:
		_chairs_drawn.erase(_claimed_chair)
		get_tree().call_group(FurnitureView.CHAIR_GROUP, "queue_redraw")
	_claimed_chair = NO_CELL
	if EventBus.office_changed.is_connected(_refresh_seat):
		EventBus.office_changed.disconnect(_refresh_seat)
	_release_cells()
	_door_queue.erase(self)


# El primero de la fila de la puerta que sigue esperando (quita a los que no).
func _door_queue_front() -> OfficeCharacter:
	while not _door_queue.is_empty():
		var first: Variant = _door_queue[0]
		if is_instance_valid(first) and (first as OfficeCharacter).activity != Activity.AWAY \
				and not (first as OfficeCharacter)._grid.is_in_lot((first as OfficeCharacter).get_cell()):
			return first
		_door_queue.pop_front()
	return null


## Indica si otro personaje ocupa una casilla.
func is_cell_taken(cell: Vector2i) -> bool:
	var other: Variant = _occupants.get(cell)
	return other != null and is_instance_valid(other) and other != self and (other as OfficeCharacter)._held.has(cell)


## Casillas del local que ocupa (la suya y, caminando, la siguiente).
func get_held_cells() -> Array[Vector2i]:
	return _held.duplicate()


## Casillas que ocupan los demás personajes.
func get_taken_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _occupants:
		if is_cell_taken(cell):
			cells.append(cell)
	return cells


# Toma una casilla del local si está libre (o si force). Fuera del local no hay límite.
func _claim(cell: Vector2i, force: bool) -> bool:
	if _held.has(cell) or not _grid.is_in_lot(cell):
		return true
	if not force and is_cell_taken(cell):
		return false
	_occupants[cell] = self
	_held.append(cell)
	return true


# Suelta las casillas que ocupa, salvo keep.
func _release_cells(keep: Vector2i = NO_CELL) -> void:
	var kept: Array[Vector2i] = []
	for cell: Vector2i in _held:
		if cell == keep:
			kept.append(cell)
		elif _occupants.get(cell) == self:
			_occupants.erase(cell)
	_held = kept


# Siguiente casilla ocupada: espera y cada tanto busca otro camino. Afuera, esperando para
# entrar, no se ve.
func _on_blocked(scaled_delta: float) -> void:
	_blocked_time += scaled_delta
	if not _grid.is_in_lot(get_cell()):
		visible = false
	if _blocked_time < _next_repath:
		return
	_next_repath = _blocked_time + GameConstants.CHARACTER_REPATH_WAIT
	if _grid.is_in_lot(get_cell()):
		_replan_avoiding(get_taken_cells())


## Estado para guardar.
func export_state() -> Dictionary:
	var cell: Vector2i = get_cell()
	return {"activity": activity, "cell": [cell.x, cell.y]}


## Restaura el estado; si iba caminando, recalcula el camino desde la casilla guardada.
func import_state(state: Dictionary) -> void:
	var cell: Array = state.get("cell", [_entrance.x, _entrance.y])
	grid_position = Vector2(int(cell[0]), int(cell[1]))
	var saved: Activity = int(state.get("activity", Activity.AWAY)) as Activity
	_path.clear()
	match saved:
		Activity.WALKING_TO_DESK, Activity.STEPPING_OUT:
			_walk_to(_seat_cell, Activity.WALKING_TO_DESK)
		Activity.WALKING_OUT:
			_walk_to(_entrance, Activity.WALKING_OUT, [_outside])
		Activity.SEATED:
			if grid_position == Vector2(_seat_cell):
				_set_activity(saved)
			else:
				_walk_to(_seat_cell, Activity.WALKING_TO_DESK)
		_:
			_set_activity(saved)
	visible = activity != Activity.AWAY
	_update_position()


# Camino hasta destination más extra_steps (p. ej. el paso que sale por la entrada); esquiva avoid si puede.
func _walk_to(destination: Vector2i, new_activity: Activity, extra_steps: Array[Vector2i] = [],
		avoid: Array[Vector2i] = []) -> void:
	# Fuera del local (recién salido) primero vuelve a entrar.
	if not _grid.is_in_lot(get_cell()):
		if new_activity == Activity.WALKING_OUT:
			# Ya afuera y saliendo: sigue a la calle sin cruzar la puerta.
			_door_queue.erase(self)
			_path = [_outside] as Array[Vector2i]
			_set_activity(new_activity)
			_update_position()
			return
		_path = [_entrance] as Array[Vector2i]
		if destination != _entrance:
			var inside: Array[Vector2i] = _find_path(_entrance, destination, avoid)
			if inside.is_empty():
				push_warning("%s no encuentra camino de %s a %s" % [display_name, _entrance, destination])
				inside = _path_to_closest(_entrance, destination)
			if not inside.is_empty():
				inside.pop_front()
				_path.append_array(inside)
		_path.append_array(extra_steps)
		_set_activity(new_activity)
		_update_position()
		return
	_path = _find_path(get_cell(), destination, avoid)
	if _path.is_empty() and get_cell() != destination:
		push_warning("%s no encuentra camino de %s a %s" % [display_name, get_cell(), destination])
		_path = _path_to_closest(get_cell(), destination)
	if not _path.is_empty():
		_path.pop_front()  # La primera casilla es en la que ya está.
		# Si iba entre dos casillas, primero vuelve al centro de la suya.
		if grid_position != Vector2(get_cell()):
			_path.push_front(get_cell())
	_path.append_array(extra_steps)
	_set_activity(new_activity)
	_update_position()
	if _path.is_empty():
		_on_destination_reached()


# Sin camino a to: camino a la casilla pisable más cercana a to, para no esperar en la puerta.
# Vacío si ya está en ella.
func _path_to_closest(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var best: Vector2i = from
	var best_distance: int = _distance(from, to)
	for cell: Vector2i in _pathfinder.get_reachable(from):
		var distance: int = _distance(cell, to)
		if distance < best_distance or (distance == best_distance and cell < best):
			best = cell
			best_distance = distance
	if best == from:
		return []
	return _pathfinder.find_path(from, best)


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# Camino que esquiva avoid; si así no hay, el de siempre.
func _find_path(from: Vector2i, to: Vector2i, avoid: Array[Vector2i]) -> Array[Vector2i]:
	if not avoid.is_empty():
		var around: Array[Vector2i] = _pathfinder.find_path(from, to, avoid)
		if not around.is_empty():
			return around
	return _pathfinder.find_path(from, to)


func _on_destination_reached() -> void:
	hurry = false
	match activity:
		Activity.WALKING_TO_DESK:
			# Sin camino a su lugar se queda de pie lo más cerca posible; replan lo reintenta al cambiar la oficina.
			if get_cell() != _seat_cell:
				_animate(0.0, Vector2.ZERO)
				return
			_set_activity(Activity.SEATED)
			sat_down.emit()
		Activity.WALKING_OUT:
			_set_activity(Activity.AWAY)
			visible = false
			_release_cells()
			left_office.emit()
		Activity.STEPPING_OUT:
			# Ya afuera: vuelve a entrar y a su silla.
			_walk_to(_seat_cell, Activity.WALKING_TO_DESK)


func _set_activity(new_activity: Activity) -> void:
	activity = new_activity
	if activity == Activity.SEATED:
		_refresh_seat()
	_animate(0.0, Vector2.ZERO)
	_update_position()
	queue_redraw()


## Cambia el icono de estado (lo calcula la escena).
func set_status_icon(icon: String) -> void:
	if icon == status_icon:
		return
	status_icon = icon if STATUS_ICONS.has(icon) else ""
	queue_redraw()


func _update_position() -> void:
	if _grid == null:
		return
	position = _grid.grid_to_world(grid_position + (_tuck if _is_sitting() else Vector2.ZERO))
	if _hands != null:
		# Justo después del escritorio de delante (el mueble se ordena 1 px antes de su centro).
		_hands.position = _grid.grid_to_world(Vector2(_seat_cell + FurnitureCatalog.get_front(maxi(_seat_facing, 0)))) - position
		_hands.queue_redraw()
	_place_bucket()


# Muñeco provisional; origen en el apoyo. Sentado, la cadera sobre el asiento y las piernas por delante.
func _draw() -> void:
	if _draw_sprite():
		return
	var seated: bool = activity == Activity.SEATED and not standing
	# La cadera queda sobre el asiento aunque el cuerpo se achique.
	var lift: float = -SEAT_HEIGHT_PX * (1.0 - BODY_SCALE) if seated else 0.0
	var body := Transform2D(0.0, Vector2.ONE * BODY_SCALE, 0.0, Vector2(0.0, lift))
	draw_set_transform_matrix(body)
	var hip_y: float = -24.0
	if seated:
		hip_y = -SEAT_HEIGHT_PX
		draw_rect(Rect2(-7.0, hip_y - 4.0, 14.0, 6.0), PANTS_COLOR)
		draw_rect(Rect2(-6.0, hip_y + 2.0, 4.0, 10.0), PANTS_COLOR)
		draw_rect(Rect2(2.0, hip_y + 2.0, 4.0, 10.0), PANTS_COLOR)
		hip_y -= 4.0
	else:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(BODY_SCALE, 0.5 * BODY_SCALE))
		draw_circle(Vector2.ZERO, 10.0, SHADOW_COLOR)
		draw_set_transform_matrix(body)
		draw_rect(Rect2(-7.0, hip_y, 6.0, 24.0), PANTS_COLOR)
		draw_rect(Rect2(1.0, hip_y, 6.0, 24.0), PANTS_COLOR)
	var torso := Rect2(-9.0, hip_y - 22.0, 18.0, 22.0)
	draw_rect(torso, shirt_color)
	if tie_color.a > 0.0:
		draw_rect(Rect2(-1.5, torso.position.y + 2.0, 3.0, 14.0), tie_color)
	var head_center := Vector2(0.0, torso.position.y - 8.0)
	draw_circle(head_center, 8.0, skin_color)
	draw_rect(Rect2(head_center.x - 8.0, head_center.y - 9.0, 16.0, 6.0), hair_color)
	draw_set_transform(Vector2.ZERO)
	if not status_icon.is_empty():
		_draw_status_icon(body * head_center + Vector2(9.0, -12.0))


# Dibuja sombra (de pie), cuadro e icono con su hoja. False si no tiene aspecto u hoja.
func _draw_sprite() -> bool:
	if not SpriteLibrary.has_character_look(look):
		return false
	var sitting: bool = _pose == "sit" or _pose == "type"
	if not sitting:
		SpriteLibrary.draw_character_shadow(self)
	# Sentado de espaldas las piernas quedan tras el asiento: solo de la cadera para arriba.
	var pose: String = _drawn_pose()
	# Sin cuadro con silla, de espaldas se dibuja de la cadera para arriba.
	var band: Vector2 = SEATED_BACK_BAND if sitting and pose == _pose and (_facing == 0 or _facing == 3) else Vector2.ZERO
	if not SpriteLibrary.draw_character(self, look, pose, _facing, _frame, Vector2.ZERO, band):
		return false
	if not status_icon.is_empty():
		_draw_status_icon(SPRITE_ICON_SEATED if sitting else SPRITE_ICON_STANDING)
	return true


# Globo del icono de estado, arriba a la derecha de la cabeza.
func _draw_status_icon(center: Vector2) -> void:
	var icon: Array = STATUS_ICONS[status_icon]
	draw_circle(center, ICON_RADIUS + 1.0, Color(0.1, 0.1, 0.12, 0.9))
	draw_circle(center, ICON_RADIUS, icon[0])
	var font: Font = ThemeDB.fallback_font
	var glyph: String = String(icon[1])
	var size: Vector2 = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ICON_FONT_SIZE)
	draw_string(font, center + Vector2(-size.x / 2.0, size.y * 0.32), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		ICON_FONT_SIZE, Color.WHITE)
