# Escena principal del juego: reúne la oficina y la cámara.
# Sigue la regla de Godot "llamar hacia abajo, avisar hacia arriba": el nodo padre
# configura a sus hijos directamente, y los hijos avisarán con señales cuando haga falta.
extends Node2D

@onready var _office_grid: OfficeGrid = $OfficeGrid
@onready var _camera: OfficeCamera = $OfficeCamera


func _ready() -> void:
	var game_name: String = ProjectSettings.get_setting("application/config/name")
	var godot_version: String = Engine.get_version_info().string
	print("%s — Godot %s" % [game_name, godot_version])
	_camera.set_bounds(_office_grid.get_lot_world_rect())
	# Provisional hasta el hito 8 (interfaz): el reloj se muestra en la salida.
	EventBus.hour_changed.connect(_on_hour_changed)
	_print_clock()


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
