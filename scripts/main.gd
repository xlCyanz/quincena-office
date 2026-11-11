# Escena de juego: reúne la oficina, la cámara y el CEO, y los prepara con el estado
# de la partida.
# Sigue la regla de Godot "llamar hacia abajo, avisar hacia arriba": el nodo padre
# configura a sus hijos directamente, y los hijos le avisan con señales.
extends Node2D

const CEO_SCENE: PackedScene = preload("res://scenes/ceo.tscn")

var ceo: Ceo
var pathfinder := OfficePathfinder.new()
var ceo_schedule: WorkSchedule

@onready var _office_grid: OfficeGrid = $OfficeGrid
@onready var _camera: OfficeCamera = $OfficeCamera


func _ready() -> void:
	var game_name: String = ProjectSettings.get_setting("application/config/name")
	var godot_version: String = Engine.get_version_info().string
	print("%s — Godot %s" % [game_name, godot_version])
	# Si se abre esta escena sin pasar por el menú (por ejemplo, con Cmd+R en el
	# editor), se empieza una partida nueva para poder probarla.
	if not OfficeState.has_game():
		SaveManager.new_game()
	_office_grid.build(OfficeState.lot_rect, OfficeState.rooms, OfficeState.furniture)
	pathfinder.build(OfficeState.lot_rect, OfficeState.get_furniture_cells())
	_camera.set_bounds(_office_grid.get_lot_world_rect())
	_spawn_ceo()
	GameClock.start()
	# Provisional hasta el hito 8 (interfaz): el saldo y el reloj se muestran en la salida.
	EventBus.hour_changed.connect(_on_hour_changed)
	print("Saldo: $%d" % Economy.balance)
	_print_clock()


func _exit_tree() -> void:
	GameClock.stop()


func _spawn_ceo() -> void:
	ceo_schedule = WorkSchedule.from_dict(OfficeState.ceo_schedule)
	var chair: Dictionary = OfficeState.find_furniture_assigned_to("ceo")
	var seat_cell: Vector2i = chair.get("cell", OfficeState.entrance)
	ceo = CEO_SCENE.instantiate()
	_office_grid.add_object(ceo)
	ceo.sat_down.connect(func() -> void: print("El CEO se sentó en su escritorio."))
	ceo.left_office.connect(_on_ceo_left_office)
	ceo.setup(_office_grid, pathfinder, ceo_schedule, seat_cell, OfficeState.entrance)


# Con el CEO fuera, la oficina queda vacía: el tiempo salta hasta su próxima entrada.
func _on_ceo_left_office() -> void:
	var hours: int = ceo_schedule.hours_until_next_work(GameClock.get_weekday(), GameClock.get_hour())
	print("El CEO se fue; la oficina está vacía.")
	if hours > 0:
		GameClock.fast_forward_hours(hours)


# Atajos de teclado (un extra: en el hito 8 la interfaz tendrá botones para esto).
# Espacio: pausa · 1, 2, 3: velocidad 1x, 2x, 4x.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			GameClock.toggle_pause()
		KEY_1, KEY_2, KEY_3:
			GameClock.set_speed_index(key.keycode - KEY_1)
		_:
			return
	get_viewport().set_input_as_handled()
	_print_clock()


func _on_hour_changed(_hour: int) -> void:
	_print_clock()


func _print_clock() -> void:
	var speed: String = "pausa" if GameClock.is_paused else "%dx" % int(GameClock.get_speed())
	print("Día %d, mes %d — %02d:%02d (%s)" % [GameClock.get_day(), GameClock.get_month(),
		GameClock.get_hour(), GameClock.get_minute(), speed])
