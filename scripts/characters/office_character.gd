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

# Arte provisional: colores y medidas del muñeco (dibujado a unos 32×64 px de pie y
# achicado por BODY_SCALE para que quede a la escala de los muebles).
const PANTS_COLOR := Color("2f3b52")
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.25)
const SEAT_HEIGHT_PX: float = 14.0
## Escala del muñeco: con 0.8 mide unos 50 px de pie, 1.7 m al lado de un escritorio de
## 22 px (75 cm). El asiento queda a la altura de la silla y el icono de estado no se achica.
const BODY_SCALE: float = 0.8
## Iconos de estado (hito 57, Staff.get_status_icon): color del globo y signo.
const STATUS_ICONS: Dictionary[String, Array] = {
	"no_station": [Color("8a8f99"), "?"],
	"tired": [Color("5b8bd9"), "z"],
	"upset": [Color("d9534f"), "!"],
	"stressed": [Color("e08a2c"), "#"],
	"idle": [Color("a6a6a6"), "…"],
}
const ICON_RADIUS: float = 7.0
const ICON_FONT_SIZE: int = 11
## Zona en la que un clic toca al personaje, relativa a su punto de apoyo (ya con BODY_SCALE).
const CLICK_AREA := Rect2(-10.0, -52.0, 20.0, 56.0)
## Ninguna casilla (para _release_cells).
const NO_CELL := Vector2i(-1000000, -1000000)

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
## Icono de estado que se dibuja sobre la cabeza ("" ninguno; claves de STATUS_ICONS).
var status_icon: String = ""
## Posición en la cuadrícula; con decimales mientras camina entre dos casillas.
var grid_position := Vector2.ZERO

var _grid: OfficeGrid
var _pathfinder: OfficePathfinder
var _seat_cell := Vector2i.ZERO
var _entrance := Vector2i.ZERO
var _outside := Vector2i.ZERO
# Casillas que faltan por recorrer; la primera es la siguiente.
var _path: Array[Vector2i] = []
# Una persona por casilla del local: casilla → personaje que la ocupa (la suya y, mientras
# camina, la siguiente). Compartido entre todos los personajes.
static var _occupants: Dictionary = {}
# Casillas del local que ocupa este personaje.
var _held: Array[Vector2i] = []
# Segundos (a 1x) que lleva esperando a que se libere la siguiente casilla.
var _blocked_time: float = 0.0
var _next_repath: float = GameConstants.CHARACTER_REPATH_WAIT


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
			# Aparece en la entrada; si hay alguien, espera en la calle a que se libere.
			_release_cells()
			grid_position = Vector2(_entrance) if _claim(_entrance, false) else Vector2(_outside)
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
	_replan_avoiding([])


# Como replan, esquivando las casillas avoid si se puede.
func _replan_avoiding(avoid: Array[Vector2i]) -> void:
	match activity:
		Activity.WALKING_TO_DESK:
			_walk_to(_seat_cell, Activity.WALKING_TO_DESK, [], avoid)
		Activity.WALKING_OUT:
			_walk_to(_entrance, Activity.WALKING_OUT, [_outside], avoid)
		Activity.STEPPING_OUT:
			_walk_to(_entrance, Activity.STEPPING_OUT, [_outside], avoid)


func _process(delta: float) -> void:
	if activity == Activity.AWAY:
		_release_cells()
		return
	# Parado en una casilla que todavía no tiene (al cargar, al aparecer): la toma.
	if _held.is_empty() and grid_position == Vector2(get_cell()):
		_claim(get_cell(), true)
	if _path.is_empty():
		return
	var scaled_delta: float = GameClock.get_time_scale() * delta
	var step: float = GameConstants.CHARACTER_WALK_SPEED * scaled_delta
	while step > 0.0 and not _path.is_empty():
		var next: Vector2i = _path[0]
		# Dentro del local, tras esperar mucho, pasa igual; afuera espera siempre (nadie
		# de afuera le cierra el paso a quien está en la entrada).
		var force: bool = _blocked_time >= GameConstants.CHARACTER_PASS_WAIT and _grid.is_in_lot(get_cell())
		if not _claim(next, force):
			_on_blocked(scaled_delta)
			break
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


func _exit_tree() -> void:
	_release_cells()


## Indica si otro personaje ocupa una casilla (la suya o la siguiente mientras camina).
func is_cell_taken(cell: Vector2i) -> bool:
	var other: Variant = _occupants.get(cell)
	return other != null and is_instance_valid(other) and other != self and (other as OfficeCharacter)._held.has(cell)


## Casillas del local que ocupa (la suya y, mientras camina, la siguiente).
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


# La siguiente casilla está ocupada: espera; cada tanto busca otro camino que esquive a
# los demás. Afuera, esperando para entrar, no se ve (no se amontonan en la vereda).
func _on_blocked(scaled_delta: float) -> void:
	_blocked_time += scaled_delta
	if not _grid.is_in_lot(get_cell()):
		visible = false
	if _blocked_time < _next_repath:
		return
	_next_repath = _blocked_time + GameConstants.CHARACTER_REPATH_WAIT
	if _grid.is_in_lot(get_cell()):
		_replan_avoiding(get_taken_cells())


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
# paso que lo saca del local por la entrada). Si puede, esquiva las casillas avoid.
func _walk_to(destination: Vector2i, new_activity: Activity, extra_steps: Array[Vector2i] = [],
		avoid: Array[Vector2i] = []) -> void:
	# Fuera del local (recién salido por la entrada) primero vuelve a entrar.
	if not _grid.is_in_lot(get_cell()):
		_path = [_entrance] as Array[Vector2i]
		if destination != _entrance:
			var inside: Array[Vector2i] = _find_path(_entrance, destination, avoid)
			if inside.is_empty():
				push_warning("%s no encuentra camino de %s a %s" % [display_name, _entrance, destination])
			else:
				inside.pop_front()
				_path.append_array(inside)
		_path.append_array(extra_steps)
		_set_activity(new_activity)
		_update_position()
		return
	_path = _find_path(get_cell(), destination, avoid)
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


# Camino que esquiva avoid; si así no hay, el de siempre.
func _find_path(from: Vector2i, to: Vector2i, avoid: Array[Vector2i]) -> Array[Vector2i]:
	if not avoid.is_empty():
		var around: Array[Vector2i] = _pathfinder.find_path(from, to, avoid)
		if not around.is_empty():
			return around
	return _pathfinder.find_path(from, to)


func _on_destination_reached() -> void:
	match activity:
		Activity.WALKING_TO_DESK:
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
	queue_redraw()


## Cambia el icono de estado (lo calcula la escena de juego al cambiar la hora).
func set_status_icon(icon: String) -> void:
	if icon == status_icon:
		return
	status_icon = icon if STATUS_ICONS.has(icon) else ""
	queue_redraw()


func _update_position() -> void:
	position = _grid.grid_to_world(grid_position)


## Vuelve a ponerse en su lugar de la cuadrícula (al girar la vista).
func refresh_position() -> void:
	if _grid != null:
		_update_position()


# Muñeco provisional. El origen es el punto de apoyo en el centro de su casilla.
# Sentado, la cadera queda sobre el asiento y las piernas cuelgan por delante.
func _draw() -> void:
	var seated: bool = activity == Activity.SEATED
	# Sentado, la cadera tiene que quedar sobre el asiento aunque el cuerpo se achique.
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


# Globo con el signo del icono de estado, arriba a la derecha de la cabeza.
func _draw_status_icon(center: Vector2) -> void:
	var icon: Array = STATUS_ICONS[status_icon]
	draw_circle(center, ICON_RADIUS + 1.0, Color(0.1, 0.1, 0.12, 0.9))
	draw_circle(center, ICON_RADIUS, icon[0])
	var font: Font = ThemeDB.fallback_font
	var glyph: String = String(icon[1])
	var size: Vector2 = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ICON_FONT_SIZE)
	draw_string(font, center + Vector2(-size.x / 2.0, size.y * 0.32), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		ICON_FONT_SIZE, Color.WHITE)
