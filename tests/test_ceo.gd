# Prueba sin ventana del hito 4: el CEO llega a su escritorio por un camino válido,
# esquiva obstáculos, queda bien ordenado respecto a los muebles, se va al terminar
# la jornada y, con la oficina vacía, el tiempo salta a su próxima entrada.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_ceo.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const FRAME: float = 1.0 / 60.0

var _failures: int = 0
var _checks: int = 0
var _game: Node
var _ceo: Ceo
var _grid: OfficeGrid
var _blocked: Array[Vector2i] = []
var _seat := Vector2i.ZERO
var _sat_count: int = 0
var _left_count: int = 0
var _days_seen: Array[int] = []
# Si el CEO estaba visible al empezar cada hora (se reinicia en cada comprobación).
var _visible_at_hour: Dictionary[int, bool] = {}


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	_check_schedule()
	_check_pathfinder_detour()

	SaveManager.new_game()
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	_ceo = _game.ceo
	_grid = _game.get_node("OfficeGrid")
	_blocked = OfficeState.get_furniture_cells()
	_seat = OfficeState.find_furniture_assigned_to("ceo")["cell"]
	_ceo.sat_down.connect(func() -> void: _sat_count += 1)
	_ceo.left_office.connect(func() -> void: _left_count += 1)
	EventBus.hour_changed.connect(func(hour: int) -> void: _visible_at_hour[hour] = _ceo.visible)
	EventBus.day_changed.connect(func(day: int, _month: int) -> void: _days_seen.append(day))
	# Desde aquí el tiempo se mueve a mano: así la prueba no depende de los fotogramas.
	GameClock.stop()
	_ceo.set_process(false)

	_check_arrival()
	_check_pause_freezes()
	_walk_until(func() -> bool: return _ceo.activity == Ceo.Activity.SEATED, 30.0, "llegar al escritorio")
	_check_seated()
	_check_sorting()
	_check_leaving_and_skip()
	_check_weekend_skip()
	_check_state_round_trip()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Avanza el reloj y al CEO fotograma a fotograma hasta que se cumpla la condición.
func _walk_until(condition: Callable, max_seconds: float, label: String) -> void:
	var lot: Rect2i = OfficeState.lot_rect
	var elapsed: float = 0.0
	var previous_cell: Vector2i = _ceo.get_cell()
	while not condition.call() and elapsed < max_seconds:
		GameClock.advance(FRAME)
		_ceo._process(FRAME)
		elapsed += FRAME
		var cell: Vector2i = _ceo.get_cell()
		if _ceo.visible and lot.has_point(cell):
			_expect(not _blocked.has(cell) or cell == _seat,
				"%s: el CEO atravesó un mueble en %s" % [label, cell])
		if _ceo.visible and cell != previous_cell and lot.has_point(previous_cell):
			var crossed: Vector3i = GridEdge.between(previous_cell, cell)
			_expect(not OfficeState.blocks_passage(crossed), "%s: el CEO atravesó la pared %s" % [label, crossed])
		previous_cell = cell
	_expect(condition.call(), "%s: no ocurrió en %.0f s" % [label, max_seconds])


# Comprueba que un camino sea válido: pasos de una casilla, dentro del local, sin
# atravesar muebles (salvo la silla de destino) ni paredes, y tan corto como el mejor posible.
func _check_path(start: Vector2i, path: Array[Vector2i], goal: Vector2i, label: String) -> void:
	_expect(not path.is_empty(), "%s: camino vacío" % label)
	if path.is_empty():
		return
	_expect(path[path.size() - 1] == goal, "%s: el camino acaba en %s" % [label, path[path.size() - 1]])
	var previous: Vector2i = start
	for cell: Vector2i in path:
		var step: Vector2i = (cell - previous).abs()
		_expect(step.x + step.y == 1, "%s: salto de %s a %s" % [label, previous, cell])
		_expect(OfficeState.lot_rect.has_point(cell), "%s: %s fuera del local" % [label, cell])
		_expect(not _blocked.has(cell) or cell == goal, "%s: atraviesa el mueble en %s" % [label, cell])
		if step.x + step.y == 1:
			_expect(not OfficeState.blocks_passage(GridEdge.between(previous, cell)),
				"%s: atraviesa la pared entre %s y %s" % [label, previous, cell])
		previous = cell
	var best: int = _bfs_distance(start, goal, OfficeState.lot_rect, _blocked)
	_expect(path.size() == best, "%s: %d pasos, el más corto tiene %d" % [label, path.size(), best])


# Búsqueda en anchura independiente de AStarGrid2D, para comparar longitudes.
func _bfs_distance(start: Vector2i, goal: Vector2i, lot: Rect2i, blocked: Array[Vector2i]) -> int:
	var distances: Dictionary[Vector2i, int] = {start: 0}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell == goal:
			return distances[cell]
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = cell + direction
			if lot.has_point(next) and not distances.has(next) and (next == goal or not blocked.has(next)) \
					and not OfficeState.blocks_passage(GridEdge.between(cell, next)):
				distances[next] = distances[cell] + 1
				queue.append(next)
	return -1


func _check_schedule() -> void:
	var schedule := WorkSchedule.from_dict({"days": [0, 1, 2, 3, 4], "start_hour": 8, "end_hour": 17})
	_expect(schedule.is_working(0, 8) and schedule.is_working(4, 16), "debería trabajar lun 8 y vie 16")
	_expect(not schedule.is_working(0, 17) and not schedule.is_working(0, 7) and not schedule.is_working(5, 10),
		"no debería trabajar lun 17, lun 7 ni sáb 10")
	_expect(schedule.hours_until_next_work(0, 17) == 15, "lun 17 → mar 8 son 15 h")
	_expect(schedule.hours_until_next_work(4, 17) == 63, "vie 17 → lun 8 son 63 h")
	_expect(schedule.hours_until_next_work(6, 23) == 9, "dom 23 → lun 8 son 9 h")
	_expect(schedule.hours_until_next_work(0, 7) == 1, "lun 7 → lun 8 es 1 h")
	_expect(WorkSchedule.from_dict({}).hours_until_next_work(0, 0) == -1, "un horario vacío no tiene próxima hora")


# Un muro de obstáculos obliga a rodear; un destino encerrado no tiene camino.
func _check_pathfinder_detour() -> void:
	var lot := Rect2i(0, 0, 6, 8)
	var wall: Array[Vector2i] = []
	for x: int in range(0, 5):
		wall.append(Vector2i(x, 3))
	var finder := OfficePathfinder.new()
	finder.build(lot, wall)
	var path: Array[Vector2i] = finder.find_path(Vector2i(0, 0), Vector2i(0, 6))
	_expect(path.size() > 0 and path[0] == Vector2i(0, 0), "el camino no empieza en el origen")
	var previous_blocked: Array[Vector2i] = _blocked
	_blocked = wall
	var saved_lot: Rect2i = OfficeState.lot_rect
	var saved_edges: Dictionary[Vector3i, String] = OfficeState.edges.duplicate()
	OfficeState.edges.clear()
	OfficeState.lot_rect = lot
	if path.size() > 0:
		path.pop_front()
		_check_path(Vector2i(0, 0), path, Vector2i(0, 6), "rodeo")
		_expect(path.has(Vector2i(5, 3)), "el rodeo no pasa por el único hueco (5, 3)")
	OfficeState.lot_rect = saved_lot
	OfficeState.edges = saved_edges
	_blocked = previous_blocked
	wall.append(Vector2i(5, 3))
	finder.build(lot, wall)
	_expect(finder.find_path(Vector2i(0, 0), Vector2i(0, 6)).is_empty(), "con el paso cerrado no debe haber camino")


func _check_arrival() -> void:
	_expect(GameClock.get_weekday() == 0 and GameClock.get_hour() == 8, "la partida no empieza el lunes a las 8")
	_expect(_ceo.visible and _ceo.activity == Ceo.Activity.WALKING_TO_DESK, "a las 8 el CEO no va hacia su escritorio")
	_expect(_ceo.get_cell() == OfficeState.entrance, "el CEO no aparece en la entrada")
	_check_path(OfficeState.entrance, _ceo.get_path_cells(), _seat, "llegada")


func _check_pause_freezes() -> void:
	var before: Vector2 = _ceo.grid_position
	GameClock.set_paused(true)
	for i: int in range(120):
		_ceo._process(FRAME)
	_expect(_ceo.grid_position == before, "en pausa el CEO se movió")
	GameClock.set_paused(false)


func _check_seated() -> void:
	_expect(_sat_count == 1, "sat_down se emitió %d veces" % _sat_count)
	_expect(_ceo.get_cell() == _seat and _ceo.grid_position == Vector2(_seat), "el CEO no quedó en la silla")
	_expect(_ceo.position.distance_to(_grid.cell_to_world(_seat)) < 0.01, "el CEO no se dibuja sobre la silla")
	var walk_seconds: float = 8.0 / GameConstants.CHARACTER_WALK_SPEED
	_expect(GameClock.get_hour() == 8, "llegar (%.0f s) no debería pasar de las 8:59" % walk_seconds)


# En la capa ordenada por Y, quien tiene mayor y se dibuja encima. Sentado, el CEO
# va delante de su silla y del escritorio; caminando, va delante de un mueble si está
# más cerca de quien mira (x + y mayor) y detrás si está más lejos.
func _check_sorting() -> void:
	var objects: Node = _grid.get_node("Objects")
	_expect(objects.y_sort_enabled and _ceo.get_parent() == objects, "el CEO no está en la capa ordenada por Y")
	var views: Array[FurnitureView] = []
	for child: Node in objects.get_children():
		if child is FurnitureView:
			views.append(child)
	_expect(views.size() == OfficeState.furniture.size(), "se dibujan %d muebles" % views.size())
	for view: FurnitureView in views:
		_expect(_ceo.position.y > view.position.y, "sentado, el CEO queda detrás de %s" % view.item_id)
	var saved: Vector2 = _ceo.grid_position
	for x: int in range(OfficeState.lot_rect.size.x):
		for y: int in range(OfficeState.lot_rect.size.y):
			var cell := Vector2i(x, y)
			if _blocked.has(cell):
				continue
			var ceo_y: float = _grid.cell_to_world(cell).y
			for view: FurnitureView in views:
				var nearest: int = -1000
				var farthest: int = 1000
				for part: Vector2i in view.footprint:
					nearest = maxi(nearest, part.x + part.y)
					farthest = mini(farthest, part.x + part.y)
				if x + y > nearest:
					_expect(ceo_y > view.position.y, "en %s el CEO debería ir delante de %s" % [cell, view.item_id])
				elif x + y < farthest:
					_expect(ceo_y < view.position.y, "en %s el CEO debería ir detrás de %s" % [cell, view.item_id])
	_ceo.grid_position = saved


func _check_leaving_and_skip() -> void:
	# Hasta las 17:00 sigue sentado.
	GameClock.advance((16 - GameClock.get_hour()) * GameConstants.SECONDS_PER_GAME_HOUR)
	_expect(GameClock.get_hour() == 16 and _ceo.activity == Ceo.Activity.SEATED, "a las 16 el CEO debería seguir sentado")
	_days_seen.clear()
	_visible_at_hour.clear()
	_walk_until(func() -> bool: return GameClock.get_hour() == 17, 10.0, "llegar a las 17")
	_expect(_ceo.activity == Ceo.Activity.WALKING_OUT, "a las 17 el CEO no sale")
	var path: Array[Vector2i] = _ceo.get_path_cells()
	_expect(path.size() >= 2, "el camino de salida es demasiado corto")
	if path.size() >= 2:
		var outside: Vector2i = path.pop_back()
		_check_path(_seat, path, OfficeState.entrance, "salida")
		_expect(not OfficeState.lot_rect.has_point(outside), "el último paso no sale del local")
	_walk_until(func() -> bool: return _left_count == 1, 30.0, "salir del local")
	# Durante el salto (por ejemplo, a las 18:00 y a las 3:00) no está en la oficina.
	_expect(_visible_at_hour.get(18, true) == false and _visible_at_hour.get(3, true) == false,
		"el CEO seguía en la oficina de noche: %s" % [_visible_at_hour])
	# Al quedar vacía, el tiempo saltó al martes a las 8 y el CEO ya viene de nuevo.
	_expect(GameClock.get_weekday() == 1 and GameClock.get_hour() == 8 and GameClock.get_minute() == 0,
		"tras salir el lunes, el reloj está en el día %d a las %d:%02d" % [
			GameClock.get_weekday(), GameClock.get_hour(), GameClock.get_minute()])
	_expect(_days_seen == [2], "días avisados en el salto: %s" % [_days_seen])
	_expect(_ceo.visible and _ceo.activity == Ceo.Activity.WALKING_TO_DESK, "el martes a las 8 el CEO no vuelve")
	_walk_until(func() -> bool: return _ceo.activity == Ceo.Activity.SEATED, 30.0, "volver al escritorio")


# El viernes al irse, el salto pasa el fin de semana y avisa de cada día.
func _check_weekend_skip() -> void:
	var friday: int = 4 - GameClock.get_weekday()
	GameClock.advance(friday * GameConstants.HOURS_PER_DAY * GameConstants.SECONDS_PER_GAME_HOUR)
	# Durante esos días el CEO entra y sale; se le deja terminar cada trayecto.
	_walk_until(func() -> bool: return GameClock.get_weekday() == 4 and _ceo.activity == Ceo.Activity.SEATED,
		600.0, "llegar al viernes sentado")
	GameClock.advance((16 - GameClock.get_hour()) * GameConstants.SECONDS_PER_GAME_HOUR)
	_days_seen.clear()
	var left_before: int = _left_count
	_walk_until(func() -> bool: return _left_count == left_before + 1, 60.0, "salir el viernes")
	_expect(GameClock.get_weekday() == 0 and GameClock.get_hour() == 8, "tras el viernes el reloj no está en lunes a las 8")
	_expect(_days_seen.size() == 3, "en el fin de semana se avisaron %d días" % _days_seen.size())


func _check_state_round_trip() -> void:
	_walk_until(func() -> bool: return _ceo.activity == Ceo.Activity.SEATED, 30.0, "sentarse el lunes")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_ceo.export_state()))
	_ceo.import_state({"activity": Ceo.Activity.AWAY, "cell": [OfficeState.entrance.x, OfficeState.entrance.y]})
	_expect(not _ceo.visible, "import_state de AWAY no oculta al CEO")
	_ceo.import_state(saved)
	_expect(_ceo.activity == Ceo.Activity.SEATED and _ceo.get_cell() == _seat and _ceo.visible,
		"el CEO no se restauró sentado en su silla")
	# Restaurado a medio camino, recalcula la ruta.
	_ceo.import_state({"activity": Ceo.Activity.WALKING_TO_DESK, "cell": [3, 5]})
	_check_path(Vector2i(3, 5), _ceo.get_path_cells(), _seat, "camino restaurado")
