# Escena de juego: reúne la oficina, la cámara, el CEO, el modo construcción y la
# interfaz superpuesta, y los prepara con el estado de la partida.
# Sigue la regla de Godot "llamar hacia abajo, avisar hacia arriba": el nodo padre
# configura a sus hijos directamente, y los hijos le avisan con señales.
extends Node2D

const CEO_SCENE: PackedScene = preload("res://scenes/ceo.tscn")

var ceo: Ceo
var pathfinder := OfficePathfinder.new()
var ceo_schedule: WorkSchedule

# Si el reloj estaba en pausa antes de entrar al modo construcción.
var _was_paused_before_building: bool = false

@onready var _office_grid: OfficeGrid = $OfficeGrid
@onready var _camera: OfficeCamera = $OfficeCamera
@onready var _build_controller: BuildController = $BuildController
@onready var _build_panel: BuildPanel = $BuildPanel
@onready var _hud: Hud = $Hud


func _ready() -> void:
	var game_name: String = ProjectSettings.get_setting("application/config/name")
	var godot_version: String = Engine.get_version_info().string
	print("%s — Godot %s" % [game_name, godot_version])
	# Si se abre esta escena sin pasar por el menú (por ejemplo, con Cmd+R en el
	# editor), se empieza una partida nueva para poder probarla.
	if not OfficeState.has_game():
		SaveManager.new_game()
	_rebuild_office()
	_camera.set_bounds(_office_grid.get_lot_world_rect())
	_spawn_ceo()
	_build_controller.setup(_office_grid)
	_build_controller.status_changed.connect(_build_panel.show_status)
	_build_panel.build_mode_changed.connect(_on_build_mode_changed)
	_build_panel.tool_selected.connect(_build_controller.set_tool)
	_hud.pause_pressed.connect(_on_pause_pressed)
	_hud.speed_pressed.connect(_on_speed_pressed)
	EventBus.office_changed.connect(_on_office_changed)
	GameClock.start()


func _exit_tree() -> void:
	GameClock.stop()


func _rebuild_office() -> void:
	_office_grid.build(OfficeState.lot_rect, OfficeState.floors, OfficeState.edges, OfficeState.furniture,
		OfficeState.rooms)
	pathfinder.build(OfficeState.lot_rect, OfficeState.get_furniture_cells(), OfficeState.edges)


func _spawn_ceo() -> void:
	ceo_schedule = WorkSchedule.from_dict(OfficeState.ceo_schedule)
	var chair: Dictionary = OfficeState.find_furniture_assigned_to("ceo")
	var seat_cell: Vector2i = chair.get("cell", OfficeState.entrance)
	ceo = CEO_SCENE.instantiate()
	_office_grid.add_object(ceo)
	ceo.sat_down.connect(func() -> void: print("El CEO se sentó en su escritorio."))
	ceo.left_office.connect(_on_ceo_left_office)
	ceo.setup(_office_grid, pathfinder, ceo_schedule, seat_cell, OfficeState.entrance,
		OfficeState.get_outside_of_entrance())


func _on_office_changed() -> void:
	_rebuild_office()
	ceo.replan()


# El modo construcción pausa el tiempo y, al salir, lo deja como estaba.
func _on_build_mode_changed(active: bool) -> void:
	_build_controller.set_active(active)
	_hud.set_controls_enabled(not active)
	_office_grid.set_rooms_visible(active)
	_camera.left_drag_enabled = not active
	# Con el tiempo en pausa el CEO no se mueve: su casilla queda reservada.
	var occupied: Array[Vector2i] = []
	if active and ceo.visible:
		occupied.append(ceo.get_cell())
	_build_controller.builder.occupied_cells = occupied
	if active:
		_was_paused_before_building = GameClock.is_paused
		GameClock.set_paused(true)
	else:
		GameClock.set_paused(_was_paused_before_building)


# Con el CEO fuera, la oficina queda vacía: el tiempo salta hasta su próxima entrada.
func _on_ceo_left_office() -> void:
	var hours: int = ceo_schedule.hours_until_next_work(GameClock.get_weekday(), GameClock.get_hour())
	print("El CEO se fue; la oficina está vacía.")
	if hours > 0:
		GameClock.fast_forward_hours(hours)


# Botones del reloj. En modo construcción están desactivados: el tiempo queda en pausa.
func _on_pause_pressed() -> void:
	if not _build_panel.is_build_mode():
		GameClock.toggle_pause()


func _on_speed_pressed(index: int) -> void:
	if not _build_panel.is_build_mode():
		GameClock.set_speed_index(index)


# Atajos de teclado (un extra: los botones del reloj hacen lo mismo).
# Espacio: pausa · 1, 2, 3: velocidad 1x, 2x, 4x. En modo construcción no cambian
# nada, porque el tiempo tiene que quedarse en pausa.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _build_panel.is_build_mode():
		return
	match key.keycode:
		KEY_SPACE:
			GameClock.toggle_pause()
		KEY_1, KEY_2, KEY_3:
			GameClock.set_speed_index(key.keycode - KEY_1)
		_:
			return
	get_viewport().set_input_as_handled()
