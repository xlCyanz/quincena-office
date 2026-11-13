# Personaje de la oficina (CEO o empleado): entra por la entrada, camina hasta su silla
# esquivando los muebles, se sienta y sale por la entrada. No decide cuándo: la escena
# de juego le dice con update_routine si tiene que estar en la oficina (Staff.is_expected).
# Toda la lógica va en coordenadas de cuadrícula (grid_position); solo al final se
# convierte a píxeles para dibujarlo dentro de la capa ordenada por Y.
class_name OfficeCharacter
extends Node2D

## Llegó a su silla y se sentó.
signal sat_down
## Salió del local por la entrada.
signal left_office

## STEPPING_OUT: sale del edificio a buscar un baño (faltan inodoros, hito 52) y vuelve.
enum Activity { AWAY, WALKING_TO_DESK, SEATED, WALKING_OUT, STEPPING_OUT }

# Arte provisional: colores y medidas del muñeco (unos 32×64 px de pie).
const PANTS_COLOR := Color("2f3b52")
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.25)
const SEAT_HEIGHT_PX: float = 14.0
## Zona en la que un clic toca al personaje, relativa a su punto de apoyo.
const CLICK_AREA := Rect2(-12.0, -62.0, 24.0, 66.0)

## Quién es: "ceo" o Staff.employee_key(id) (lo mismo que assigned_to en su silla).
var person_key: String = ""
## Nombre para los avisos ("El CEO", "Ana Pérez").
var display_name: String = ""
var shirt_color := Color("e8e4dc")
## Corbata; transparente si no lleva.
var tie_color := Color(0.0, 0.0, 0.0, 0.0)
var skin_color := Color("d9a47a")
var hair_color := Color("3b2a20")

var activity: Activity = Activity.AWAY
## Posición en la cuadrícula; con decimales mientras camina entre dos casillas.
var grid_position := Vector2.ZERO

var _grid: OfficeGrid
var _pathfinder: OfficePathfinder
var _seat_cell := Vector2i.ZERO
var _entrance := Vector2i.ZERO
var _outside := Vector2i.ZERO
# Casillas que faltan por recorrer; la primera es la siguiente.
var _path: Array[Vector2i] = []


## Prepara al personaje con lo que necesita de la oficina. Lo llama la escena de juego.
## outside es la casilla de fuera del local a la que sale por la puerta de entrada.
## Empieza fuera; update_routine lo hace entrar.
func setup(grid: OfficeGrid, pathfinder: OfficePathfinder, seat_cell: Vector2i,
		entrance: Vector2i, outside: Vector2i) -> void:
	_grid = grid
	_pathfinder = pathfinder
	_seat_cell = seat_cell
	_entrance = entrance
	_outside = outside
	grid_position = Vector2(entrance)
	_set_activity(Activity.AWAY)
	visible = false
	_update_position()


## Casilla en la que está (la más cercana si va entre dos).
func get_cell() -> Vector2i:
	return Vector2i(grid_position.round())


## Casilla de su silla.
func get_seat_cell() -> Vector2i:
	return _seat_cell


## Casillas que le faltan por recorrer.
func get_path_cells() -> Array[Vector2i]:
	return _path.duplicate()


## Indica si un punto del mundo cae sobre el personaje (para elegirlo con un clic).
func contains_point(world_point: Vector2) -> bool:
	return visible and CLICK_AREA.has_point(world_point - position)


## Entra si tiene que estar en la oficina (expected) y está fuera o saliendo; sale si
## no tiene que estar y está dentro o llegando.
func update_routine(expected: bool) -> void:
	if expected and (activity == Activity.AWAY or activity == Activity.WALKING_OUT):
		if activity == Activity.AWAY:
			grid_position = Vector2(_entrance)
			visible = true
		_walk_to(_seat_cell, Activity.WALKING_TO_DESK)
	elif not expected and (activity == Activity.SEATED or activity == Activity.WALKING_TO_DESK
			or activity == Activity.STEPPING_OUT):
		_walk_to(_entrance, Activity.WALKING_OUT, [_outside])


## Sentado, sale del edificio a buscar un baño y vuelve a su silla. Devuelve false si no
## estaba sentado.
func step_out() -> bool:
	if activity != Activity.SEATED:
		return false
	_walk_to(_entrance, Activity.STEPPING_OUT, [_outside])
	return true


## Cambia su silla (por ejemplo, si le asignan otro puesto). Si estaba en la oficina,
## camina hasta la nueva.
func set_seat(seat_cell: Vector2i) -> void:
	if seat_cell == _seat_cell:
		return
	_seat_cell = seat_cell
	if activity == Activity.SEATED or activity == Activity.WALKING_TO_DESK:
		_walk_to(_seat_cell, Activity.WALKING_TO_DESK)


## Vuelve a calcular el camino hacia donde iba (por ejemplo, después de construir).
func replan() -> void:
	match activity:
		Activity.WALKING_TO_DESK:
			_walk_to(_seat_cell, Activity.WALKING_TO_DESK)
		Activity.WALKING_OUT:
			_walk_to(_entrance, Activity.WALKING_OUT, [_outside])
		Activity.STEPPING_OUT:
			_walk_to(_entrance, Activity.STEPPING_OUT, [_outside])


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


## Devuelve el estado del personaje para guardarlo (hito 9).
func export_state() -> Dictionary:
	var cell: Vector2i = get_cell()
	return {"activity": activity, "cell": [cell.x, cell.y]}


## Restaura el estado desde una partida guardada (hito 9). Si iba caminando, vuelve a
## calcular el camino desde la casilla guardada.
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
		_:
			_set_activity(saved)
	visible = activity != Activity.AWAY
	_update_position()


# Calcula el camino hasta destination y, al final, añade extra_steps (por ejemplo, el
# paso que lo saca del local por la entrada).
func _walk_to(destination: Vector2i, new_activity: Activity, extra_steps: Array[Vector2i] = []) -> void:
	# Fuera del local (recién salido por la entrada) primero vuelve a entrar.
	if not _grid.is_in_lot(get_cell()):
		_path = [_entrance] as Array[Vector2i]
		if destination != _entrance:
			var inside: Array[Vector2i] = _pathfinder.find_path(_entrance, destination)
			if inside.is_empty():
				push_warning("%s no encuentra camino de %s a %s" % [display_name, _entrance, destination])
			else:
				inside.pop_front()
				_path.append_array(inside)
		_path.append_array(extra_steps)
		_set_activity(new_activity)
		_update_position()
		return
	_path = _pathfinder.find_path(get_cell(), destination)
	if _path.is_empty() and get_cell() != destination:
		push_warning("%s no encuentra camino de %s a %s" % [display_name, get_cell(), destination])
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
		Activity.STEPPING_OUT:
			# Ya afuera: vuelve a entrar y a su silla.
			_walk_to(_seat_cell, Activity.WALKING_TO_DESK)


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
	draw_rect(torso, shirt_color)
	if tie_color.a > 0.0:
		draw_rect(Rect2(-1.5, torso.position.y + 2.0, 3.0, 14.0), tie_color)
	var head_center := Vector2(0.0, torso.position.y - 8.0)
	draw_circle(head_center, 8.0, skin_color)
	draw_rect(Rect2(head_center.x - 8.0, head_center.y - 9.0, 16.0, 6.0), hair_color)
