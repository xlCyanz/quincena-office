# El CEO: llega por la entrada en su horario, camina hasta su silla esquivando los
# muebles, se sienta y, al terminar la jornada, sale por la entrada.
# Toda la lógica va en coordenadas de cuadrícula (grid_position); solo al final se
# convierte a píxeles para dibujarlo dentro de la capa ordenada por Y.
class_name Ceo
extends Node2D

## Llegó a su silla y se sentó.
signal sat_down
## Salió del local por la entrada.
signal left_office

enum Activity { AWAY, WALKING_TO_DESK, SEATED, WALKING_OUT }

# Arte provisional: colores y medidas del muñeco (unos 32×64 px de pie).
const SHIRT_COLOR := Color("e8e4dc")
const TIE_COLOR := Color("b03a2e")
const PANTS_COLOR := Color("2f3b52")
const SKIN_COLOR := Color("d9a47a")
const HAIR_COLOR := Color("3b2a20")
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.25)
const SEAT_HEIGHT_PX: float = 14.0

var activity: Activity = Activity.AWAY
## Posición en la cuadrícula; con decimales mientras camina entre dos casillas.
var grid_position := Vector2.ZERO

var _grid: OfficeGrid
var _pathfinder: OfficePathfinder
var _schedule: WorkSchedule
var _seat_cell := Vector2i.ZERO
var _entrance := Vector2i.ZERO
var _outside := Vector2i.ZERO
# Casillas que faltan por recorrer; la primera es la siguiente.
var _path: Array[Vector2i] = []


## Prepara al CEO con lo que necesita de la oficina. Lo llama la escena de juego.
## outside es la casilla de fuera del local a la que sale por la puerta de entrada.
func setup(grid: OfficeGrid, pathfinder: OfficePathfinder, schedule: WorkSchedule,
		seat_cell: Vector2i, entrance: Vector2i, outside: Vector2i) -> void:
	_grid = grid
	_pathfinder = pathfinder
	_schedule = schedule
	_seat_cell = seat_cell
	_entrance = entrance
	_outside = outside
	if not EventBus.hour_changed.is_connected(_on_hour_changed):
		EventBus.hour_changed.connect(_on_hour_changed)
	_set_activity(Activity.AWAY)
	update_routine()


## Casilla en la que está (la más cercana si va entre dos).
func get_cell() -> Vector2i:
	return Vector2i(grid_position.round())


## Casillas que le faltan por recorrer.
func get_path_cells() -> Array[Vector2i]:
	return _path.duplicate()


## Mira el reloj y el horario y decide si tiene que llegar o irse.
func update_routine() -> void:
	var working: bool = _schedule.is_working(GameClock.get_weekday(), GameClock.get_hour())
	if working and (activity == Activity.AWAY or activity == Activity.WALKING_OUT):
		if activity == Activity.AWAY:
			grid_position = Vector2(_entrance)
			visible = true
		_walk_to(_seat_cell, Activity.WALKING_TO_DESK)
	elif not working and (activity == Activity.SEATED or activity == Activity.WALKING_TO_DESK):
		_walk_to(_entrance, Activity.WALKING_OUT, [_outside])


## Vuelve a calcular el camino hacia donde iba (por ejemplo, después de construir).
func replan() -> void:
	match activity:
		Activity.WALKING_TO_DESK:
			_walk_to(_seat_cell, Activity.WALKING_TO_DESK)
		Activity.WALKING_OUT:
			_walk_to(_entrance, Activity.WALKING_OUT, [_outside])


func _process(delta: float) -> void:
	if _path.is_empty():
		return
	var step: float = GameConstants.CHARACTER_WALK_SPEED * GameClock.get_time_scale() * delta
	while step > 0.0 and not _path.is_empty():
		var target := Vector2(_path[0])
		var distance: float = grid_position.distance_to(target)
		if distance <= step:
			grid_position = target
			step -= distance
			_path.pop_front()
		else:
			grid_position = grid_position.move_toward(target, step)
			step = 0.0
	_update_position()
	if _path.is_empty():
		_on_destination_reached()


## Devuelve el estado del CEO para guardarlo (hito 9).
func export_state() -> Dictionary:
	var cell: Vector2i = get_cell()
	return {"activity": activity, "cell": [cell.x, cell.y]}


## Restaura el estado del CEO desde una partida guardada (hito 9). Si iba caminando,
## vuelve a calcular el camino desde la casilla guardada.
func import_state(state: Dictionary) -> void:
	var cell: Array = state.get("cell", [_entrance.x, _entrance.y])
	grid_position = Vector2(int(cell[0]), int(cell[1]))
	var saved: Activity = int(state.get("activity", Activity.AWAY)) as Activity
	_path.clear()
	match saved:
		Activity.WALKING_TO_DESK:
			_walk_to(_seat_cell, Activity.WALKING_TO_DESK)
		Activity.WALKING_OUT:
			_walk_to(_entrance, Activity.WALKING_OUT, [_outside])
		_:
			_set_activity(saved)
	visible = activity != Activity.AWAY
	_update_position()


# Calcula el camino hasta destination y, al final, añade extra_steps (por ejemplo, el
# paso que lo saca del local por la entrada).
func _walk_to(destination: Vector2i, new_activity: Activity, extra_steps: Array[Vector2i] = []) -> void:
	_path = _pathfinder.find_path(get_cell(), destination)
	if _path.is_empty() and get_cell() != destination:
		push_warning("El CEO no encuentra camino de %s a %s" % [get_cell(), destination])
	elif not _path.is_empty():
		_path.pop_front()  # La primera casilla es en la que ya está.
		# Si iba entre dos casillas, primero vuelve al centro de la suya.
		if grid_position != Vector2(get_cell()):
			_path.push_front(get_cell())
	_path.append_array(extra_steps)
	_set_activity(new_activity)
	_update_position()
	if _path.is_empty():
		_on_destination_reached()


func _on_destination_reached() -> void:
	match activity:
		Activity.WALKING_TO_DESK:
			_set_activity(Activity.SEATED)
			sat_down.emit()
		Activity.WALKING_OUT:
			_set_activity(Activity.AWAY)
			visible = false
			left_office.emit()


func _on_hour_changed(_hour: int) -> void:
	update_routine()


func _set_activity(new_activity: Activity) -> void:
	activity = new_activity
	queue_redraw()


func _update_position() -> void:
	position = _grid.grid_to_world(grid_position)


# Muñeco provisional. El origen es el punto de apoyo en el centro de su casilla.
# Sentado, la cadera queda sobre el asiento y las piernas cuelgan por delante.
func _draw() -> void:
	var seated: bool = activity == Activity.SEATED
	var hip_y: float = -24.0
	if seated:
		hip_y = -SEAT_HEIGHT_PX
		draw_rect(Rect2(-7.0, hip_y - 4.0, 14.0, 6.0), PANTS_COLOR)
		draw_rect(Rect2(-6.0, hip_y + 2.0, 4.0, 10.0), PANTS_COLOR)
		draw_rect(Rect2(2.0, hip_y + 2.0, 4.0, 10.0), PANTS_COLOR)
		hip_y -= 4.0
	else:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 10.0, SHADOW_COLOR)
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(-7.0, hip_y, 6.0, 24.0), PANTS_COLOR)
		draw_rect(Rect2(1.0, hip_y, 6.0, 24.0), PANTS_COLOR)
	var torso := Rect2(-9.0, hip_y - 22.0, 18.0, 22.0)
	draw_rect(torso, SHIRT_COLOR)
	draw_rect(Rect2(-1.5, torso.position.y + 2.0, 3.0, 14.0), TIE_COLOR)
	var head_center := Vector2(0.0, torso.position.y - 8.0)
	draw_circle(head_center, 8.0, SKIN_COLOR)
	draw_rect(Rect2(head_center.x - 8.0, head_center.y - 9.0, 16.0, 6.0), HAIR_COLOR)
