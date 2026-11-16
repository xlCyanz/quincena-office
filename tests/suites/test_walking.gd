# Caminar: una casilla por segundo a 1x (el doble con prisa) y nunca dos en la misma casilla del local;
# quien encuentra ocupada la siguiente espera y busca otro camino; dos de frente en un pasillo se
# destraban tras CHARACTER_PASS_WAIT; con la entrada ocupada el que llega espera en la calle sin verse.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=walking
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const STEP_SECONDS: float = 0.05

var _failures: int = 0
var _checks: int = 0
var _game: Node
var _grid: OfficeGrid
var _origin := Vector2i.ZERO
var _made: Array[OfficeCharacter] = []
# Veces que dos quedaron en la misma casilla o tomaron la misma.
var _overlaps: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_packed.call_deferred(GAME_SCENE)
		return
	SaveManager.save_dir = "user://test_saves"
	SaveManager.new_game()
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	GameClock.stop()
	GameClock.set_paused(false)
	GameClock.set_speed_index(0)
	_grid = _game.get_node("OfficeGrid")
	_origin = OfficeState.lot_rect.position
	# El CEO no se mete: la prueba usa sus propios personajes.
	var ceo: OfficeCharacter = _game.get("ceo")
	ceo.set_process(false)
	ceo.call("_release_cells")
	ceo.activity = OfficeCharacter.Activity.AWAY
	ceo.visible = false
	_check_speed()
	_check_detour()
	_check_corridor()
	_check_entrance()
	_check_release()
	_check_unreachable()
	_check_spots()
	_game.queue_free()
	await get_tree().process_frame
	SaveManager.new_game()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _cell(x: int, y: int) -> Vector2i:
	return _origin + Vector2i(x, y)


# Personaje parado en start (visible) con su silla en seat.
func _make(start: Vector2i, seat: Vector2i, finder: OfficePathfinder = null) -> OfficeCharacter:
	var character := OfficeCharacter.new()
	character.display_name = "Prueba %d" % _made.size()
	character.setup(_grid, finder if finder != null else _game.get("pathfinder"), seat, OfficeState.entrance,
		OfficeState.get_outside_of_entrance())
	_game.add_child(character)
	character.set_process(false)
	character.grid_position = Vector2(start)
	character.visible = true
	character.activity = OfficeCharacter.Activity.SEATED
	character._process(0.0)  # Toma su casilla.
	_made.append(character)
	return character


func _send(character: OfficeCharacter, goal: Vector2i) -> void:
	character.call("_walk_to", goal, OfficeCharacter.Activity.WALKING_TO_DESK)


func _clear() -> void:
	for character: OfficeCharacter in _made:
		character.free()
	_made.clear()


# Avanza seconds (reales a 1x) moviendo a todos y anota cada vez que dos se pisan.
func _run(seconds: float) -> void:
	for i: int in range(roundi(seconds / STEP_SECONDS)):
		for character: OfficeCharacter in _made:
			character._process(STEP_SECONDS)
		_note_overlaps()


func _note_overlaps() -> void:
	for i: int in range(_made.size()):
		for j: int in range(i + 1, _made.size()):
			var a: OfficeCharacter = _made[i]
			var b: OfficeCharacter = _made[j]
			if not (a.visible and b.visible):
				continue
			if _grid.is_in_lot(a.get_cell()) and a.get_cell() == b.get_cell():
				_overlaps += 1
			for cell: Vector2i in a.get_held_cells():
				if b.get_held_cells().has(cell):
					_overlaps += 1


func _check_speed() -> void:
	var walker: OfficeCharacter = _make(_cell(4, 3), _cell(4, 3))
	_send(walker, _cell(4, 6))
	_run(2.0)
	_expect(is_equal_approx(GameConstants.CHARACTER_WALK_SPEED, 1.0), "una casilla por segundo a 1x")
	_expect(absf(walker.grid_position.distance_to(Vector2(_cell(4, 3))) - 2.0) < 0.06,
		"en 2 s camina 2 casillas: %s" % [walker.grid_position - Vector2(_origin)])
	GameClock.set_speed_index(1)
	var speed: float = GameClock.get_speed()
	walker.grid_position = Vector2(_cell(4, 3))
	walker.call("_release_cells")
	_send(walker, _cell(4, 6))
	_run(1.0 / speed)
	_expect(absf(walker.grid_position.distance_to(Vector2(_cell(4, 3))) - 1.0) < 0.06,
		"a %sx camina %s casillas por segundo" % [speed, speed])
	GameClock.set_speed_index(0)
	# Con prisa camina el doble y al llegar vuelve a su paso.
	walker.grid_position = Vector2(_cell(4, 3))
	walker.call("_release_cells")
	walker.hurry = true
	_send(walker, _cell(4, 7))
	_run(1.0)
	_expect(absf(walker.grid_position.distance_to(Vector2(_cell(4, 3))) - GameConstants.CHARACTER_HURRY_FACTOR) < 0.06,
		"con prisa camina %s casillas por segundo" % GameConstants.CHARACTER_HURRY_FACTOR)
	_run(2.0)
	_expect(not walker.hurry and walker.get_cell() == _cell(4, 7), "al llegar se le pasa la prisa")
	_clear()


# Uno parado en medio: el otro espera un momento y lo rodea sin pisarlo.
func _check_detour() -> void:
	_overlaps = 0
	var blocker: OfficeCharacter = _make(_cell(3, 4), _cell(3, 4))
	var walker: OfficeCharacter = _make(_cell(1, 4), _cell(5, 4))
	_expect(blocker.get_held_cells().size() == 1 and blocker.get_held_cells()[0] == _cell(3, 4), "el que está parado ocupa su casilla")
	_expect(walker.is_cell_taken(_cell(3, 4)) and not walker.is_cell_taken(_cell(1, 4)),
		"para el otro esa casilla está ocupada y la suya no")
	_send(walker, _cell(5, 4))
	_expect(walker.get_path_cells().has(_cell(3, 4)), "el camino corto pasa por donde está el otro")
	var visited: Dictionary[Vector2i, bool] = {}
	var elapsed: float = 0.0
	while elapsed < 10.0 and walker.activity != OfficeCharacter.Activity.SEATED:
		_run(STEP_SECONDS)
		elapsed += STEP_SECONDS
		visited[walker.get_cell()] = true
	_expect(walker.activity == OfficeCharacter.Activity.SEATED and walker.get_cell() == _cell(5, 4),
		"llega rodeándolo (%.1f s)" % elapsed)
	_expect(not visited.has(_cell(3, 4)), "nunca pisa la casilla del otro")
	# El rodeo son 6 pasos en vez de 4, más la espera antes de buscarlo.
	_expect(elapsed < 6.0 + GameConstants.CHARACTER_REPATH_WAIT + 0.5, "el rodeo no espera de más: %.1f s" % elapsed)
	_expect(_overlaps == 0, "nunca hay dos en la misma casilla: %d" % _overlaps)
	_clear()


# Dos de frente en un pasillo de una casilla: esperan y se destraban.
func _check_corridor() -> void:
	_overlaps = 0
	var corridor := OfficePathfinder.new()
	corridor.build(Lot.from_rect(Rect2i(_cell(0, 5), Vector2i(5, 1))), [])
	var a: OfficeCharacter = _make(_cell(0, 5), _cell(4, 5), corridor)
	var b: OfficeCharacter = _make(_cell(4, 5), _cell(0, 5), corridor)
	_send(a, _cell(4, 5))
	_send(b, _cell(0, 5))
	_run(GameConstants.CHARACTER_PASS_WAIT * 0.8)
	_expect(_overlaps == 0, "mientras esperan no se pisan")
	_expect(a.get_cell() != b.get_cell() and a.activity == OfficeCharacter.Activity.WALKING_TO_DESK
		and b.activity == OfficeCharacter.Activity.WALKING_TO_DESK, "se quedan esperando frente a frente")
	_run(GameConstants.CHARACTER_PASS_WAIT + 8.0)
	_expect(a.activity == OfficeCharacter.Activity.SEATED and a.get_cell() == _cell(4, 5)
		and b.activity == OfficeCharacter.Activity.SEATED and b.get_cell() == _cell(0, 5),
		"tras esperar pasan y llegan los dos")
	_clear()


# Dos que llegan a la vez: el segundo espera en la calle sin verse y entra después.
func _check_entrance() -> void:
	_overlaps = 0
	var first: OfficeCharacter = _make(OfficeState.entrance, _cell(5, 3))
	var second: OfficeCharacter = _make(OfficeState.entrance, _cell(5, 5))
	for character: OfficeCharacter in [first, second]:
		character.call("_release_cells")
		character.activity = OfficeCharacter.Activity.AWAY
		character.visible = false
	first.update_routine(true)
	second.update_routine(true)
	_expect(first.get_cell() == OfficeState.entrance and first.visible, "el primero aparece en la entrada")
	_expect(second.get_cell() == OfficeState.get_outside_of_entrance(), "el segundo, en la calle")
	_run(STEP_SECONDS)
	_expect(not second.visible, "esperando en la calle no se ve")
	_run(10.0)
	_expect(first.activity == OfficeCharacter.Activity.SEATED and second.activity == OfficeCharacter.Activity.SEATED
		and second.visible and second.get_cell() == _cell(5, 5), "entran los dos y llegan a su lugar")
	_expect(_overlaps == 0, "sin pisarse en la entrada: %d" % _overlaps)
	_clear()


# Al salir del local o desaparecer suelta sus casillas.
func _check_release() -> void:
	var walker: OfficeCharacter = _make(_cell(4, 6), _cell(4, 6))
	var other: OfficeCharacter = _make(_cell(5, 6), _cell(5, 6))
	_expect(other.is_cell_taken(_cell(4, 6)), "ocupa su casilla")
	walker.update_routine(false)
	_run(12.0)
	_expect(walker.activity == OfficeCharacter.Activity.AWAY and not other.is_cell_taken(_cell(4, 6))
		and walker.get_held_cells().is_empty(), "al irse la suelta")
	var leaving: OfficeCharacter = _make(_cell(4, 4), _cell(4, 4))
	_made.erase(leaving)
	leaving.free()
	_expect(not other.is_cell_taken(_cell(4, 4)), "al quitarlo de la escena también")
	_clear()


# Sin camino a su silla no se sienta en la puerta: espera de pie lo más cerca posible y va al haber camino;
# sentado fuera de su silla (partida vieja), también va a ella.
func _check_unreachable() -> void:
	var seat: Vector2i = _cell(5, 3)
	var walls: Array[Vector2i] = [seat + Vector2i.LEFT, seat + Vector2i.RIGHT, seat + Vector2i.UP, seat + Vector2i.DOWN]
	var closed := OfficePathfinder.new()
	closed.build(OfficeState.lot, OfficeState.get_blocking_cells() + walls, OfficeState.edges)
	var walker: OfficeCharacter = _make(OfficeState.entrance, seat, closed)
	walker.call("_release_cells")
	walker.activity = OfficeCharacter.Activity.AWAY
	walker.visible = false
	walker.update_routine(true)
	_run(15.0)
	var distance: int = absi(walker.get_cell().x - seat.x) + absi(walker.get_cell().y - seat.y)
	_expect(walker.activity != OfficeCharacter.Activity.SEATED, "sin camino a su silla no se sienta")
	_expect(walker.get_cell() != OfficeState.entrance and distance == 2,
		"espera de pie lo más cerca de su silla, no en la puerta: %s" % [walker.get_cell() - _origin])
	_expect(walker.get_sprite_state().get("pose", "") != "sit", "no se dibuja sentado")
	closed.build(OfficeState.lot, OfficeState.get_blocking_cells(), OfficeState.edges)
	walker.replan()
	_run(6.0)
	_expect(walker.activity == OfficeCharacter.Activity.SEATED and walker.get_cell() == seat,
		"con camino, va a su silla y se sienta")
	var moved: OfficeCharacter = _make(_cell(1, 5), _cell(4, 5))
	moved.replan()
	_run(6.0)
	_expect(moved.activity == OfficeCharacter.Activity.SEATED and moved.get_cell() == _cell(4, 5),
		"sentado fuera de su silla, al cambiar la oficina va a ella")
	_clear()


# La escena no manda a dos a la misma casilla (limpieza, almuerzo, pausas y visitas reparten las libres cercanas).
func _check_spots() -> void:
	var near: Array[Vector2i] = _game.call("_cells_near", _cell(4, 4), 5)
	var distinct: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in near:
		distinct[cell] = true
	_expect(near.size() == 5 and distinct.size() == 5 and near[0] == _cell(4, 4), "5 casillas distintas, la pedida primero")
	var finder: OfficePathfinder = _game.get("pathfinder")
	var walkable: bool = true
	for cell: Vector2i in near:
		walkable = walkable and finder.is_walkable(cell) and cell != OfficeState.entrance
	_expect(walkable, "todas se pisan y ninguna es la entrada")
	var used: Dictionary[Vector2i, bool] = {}
	var first: Vector2i = _game.call("_free_spot_near", _cell(4, 4), used)
	var second: Vector2i = _game.call("_free_spot_near", _cell(4, 4), used)
	_expect(first == _cell(4, 4) and second != first and (second - first).abs().x + (second - first).abs().y == 1,
		"el segundo que pide el mismo lugar va al de al lado")
