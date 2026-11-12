# Escena de juego: reúne la oficina, la cámara, el CEO, el modo construcción y la
# interfaz superpuesta, y los prepara con el estado de la partida.
# Sigue la regla de Godot "llamar hacia abajo, avisar hacia arriba": el nodo padre
# configura a sus hijos directamente, y los hijos le avisan con señales.
extends Node2D

const CEO_SCENE: PackedScene = preload("res://scenes/ceo.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

var ceo: Ceo
var pathfinder := OfficePathfinder.new()
var ceo_schedule: WorkSchedule

# Si el reloj estaba en pausa antes de abrir el modo construcción o Ajustes.
var _was_paused_before_menu: bool = false

@onready var _office_grid: OfficeGrid = $OfficeGrid
@onready var _camera: OfficeCamera = $OfficeCamera
@onready var _build_controller: BuildController = $BuildController
@onready var _build_panel: BuildPanel = $BuildPanel
@onready var _hud: Hud = $Hud
@onready var _settings_panel: SettingsPanel = $SettingsPanel
@onready var _staff_panel: StaffPanel = $StaffPanel


func _ready() -> void:
	var game_name: String = ProjectSettings.get_setting("application/config/name")
	var godot_version: String = Engine.get_version_info().string
	print("%s — Godot %s" % [game_name, godot_version])
	# Si se abre esta escena sin pasar por el menú (por ejemplo, con Cmd+R en el
	# editor), se empieza una partida nueva para poder probarla.
	if not OfficeState.has_game():
		SaveManager.new_game()
	_rebuild_office()
	_camera.set_map_area(_office_grid.get_site_world_area())
	_camera.fit_rect(_office_grid.get_lot_world_rect())
	_spawn_ceo()
	_restore_scene_state(SaveManager.take_scene_state())
	SaveManager.scene_state_provider = _export_scene_state
	_build_controller.setup(_office_grid)
	_build_controller.status_changed.connect(_build_panel.show_status)
	_build_panel.build_mode_changed.connect(_on_build_mode_changed)
	_build_panel.tool_selected.connect(_build_controller.set_tool)
	_hud.pause_pressed.connect(_on_pause_pressed)
	_hud.speed_pressed.connect(_on_speed_pressed)
	_add_frame_button(_build_panel.get_menu_bar())
	_staff_panel.attach_button(_build_panel.get_menu_bar())
	_settings_panel.attach_button(_build_panel.get_menu_bar())
	_settings_panel.settings_mode_changed.connect(_on_settings_mode_changed)
	_settings_panel.save_requested.connect(_on_save_requested)
	_settings_panel.quit_requested.connect(_on_quit_requested)
	EventBus.office_changed.connect(_on_office_changed)
	GameClock.start()


func _exit_tree() -> void:
	GameClock.stop()
	SaveManager.scene_state_provider = Callable()


# Lo que se guarda de la escena (el resto vive en los autoloads).
func _export_scene_state() -> Dictionary:
	return {"camera": _camera.export_state(), "ceo": ceo.export_state()}


# Al abrir una partida cargada: la cámara y el CEO como estaban. Si el CEO estaba
# fuera de su horario, el tiempo salta hasta su próxima entrada, igual que al irse.
func _restore_scene_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	_camera.import_state(state.get("camera", {}))
	ceo.import_state(state.get("ceo", {}))
	if ceo.activity == Ceo.Activity.AWAY:
		_on_ceo_left_office()


func _rebuild_office() -> void:
	_office_grid.set_site(OfficeState.site_rect)
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
	if active:
		_staff_panel.set_open(false)
	_build_controller.set_active(active)
	_hud.set_controls_enabled(not active)
	_office_grid.set_rooms_visible(active)
	_camera.left_drag_enabled = not active
	# Con el tiempo en pausa el CEO no se mueve: su casilla queda reservada.
	var occupied: Array[Vector2i] = []
	if active and ceo.visible:
		occupied.append(ceo.get_cell())
	_build_controller.builder.occupied_cells = occupied
	_set_menu_pause(active)


func _on_settings_mode_changed(active: bool) -> void:
	if active:
		_staff_panel.set_open(false)
	_build_panel.get_menu_bar().visible = not active
	_hud.set_controls_enabled(not active)
	_set_menu_pause(active)


# Mientras un menú que pausa está abierto, el tiempo se detiene; al cerrarlo vuelve a
# como estaba.
func _set_menu_pause(active: bool) -> void:
	if active:
		_was_paused_before_menu = GameClock.is_paused
		GameClock.set_paused(true)
	else:
		GameClock.set_paused(_was_paused_before_menu)


func _is_menu_open() -> bool:
	return _build_panel.is_build_mode() or _settings_panel.is_open()


func _on_save_requested(slot: String) -> void:
	# Se guarda con la pausa que había antes de abrir Ajustes, no con la del menú.
	var paused_now: bool = GameClock.is_paused
	GameClock.set_paused(_was_paused_before_menu)
	var saved: bool = SaveManager.save_game(slot)
	GameClock.set_paused(paused_now)
	_settings_panel.refresh_slots()
	_settings_panel.show_status("Guardado en la %s." % SaveManager.get_slot_name(slot).to_lower()
		if saved else "No se pudo guardar.")


func _on_quit_requested() -> void:
	get_tree().change_scene_to_file(MENU_SCENE_PATH)


# Con el CEO fuera, la oficina queda vacía: el tiempo salta hasta su próxima entrada.
func _on_ceo_left_office() -> void:
	var hours: int = ceo_schedule.hours_until_next_work(GameClock.get_weekday(), GameClock.get_hour())
	print("El CEO se fue; la oficina está vacía.")
	if hours > 0:
		GameClock.fast_forward_hours(hours)


# Botones del reloj. En modo construcción están desactivados: el tiempo queda en pausa.
func _on_pause_pressed() -> void:
	if not _is_menu_open():
		GameClock.toggle_pause()


# Botón «Ver oficina» de la barra de menús: vuelve a encuadrar la oficina completa.
func _add_frame_button(menu_bar: Container) -> void:
	var button := Button.new()
	button.name = "FrameOfficeButton"
	button.text = "Ver oficina"
	button.custom_minimum_size = Vector2(160.0, 44.0)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(frame_office)
	menu_bar.add_child(button)


## Encuadra la oficina completa (botón «Ver oficina» o tecla F).
func frame_office() -> void:
	_camera.fit_rect(_office_grid.get_lot_world_rect())


func _on_speed_pressed(index: int) -> void:
	if not _is_menu_open():
		GameClock.set_speed_index(index)


# Atajos de teclado (un extra: los botones del reloj hacen lo mismo).
# Espacio: pausa · 1, 2, 3: velocidad 1x, 2x, 4x. En modo construcción no cambian
# nada, porque el tiempo tiene que quedarse en pausa. F: ver la oficina completa
# (funciona siempre).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F:
		frame_office()
		get_viewport().set_input_as_handled()
		return
	if _is_menu_open():
		return
	match key.keycode:
		KEY_SPACE:
			GameClock.toggle_pause()
		KEY_1, KEY_2, KEY_3:
			GameClock.set_speed_index(key.keycode - KEY_1)
		_:
			return
	get_viewport().set_input_as_handled()
