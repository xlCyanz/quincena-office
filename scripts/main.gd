# Escena de juego: reúne la oficina, la cámara, el CEO y los empleados, el modo
# construcción y la interfaz superpuesta, y los prepara con el estado de la partida.
# Cada hora (y cuando cambia quién tiene que estar) les dice a los personajes si les
# toca estar en la oficina (Staff.is_expected); cuando todos se fueron, la oficina
# queda vacía y el tiempo salta hasta que llegue el próximo.
# Sigue la regla de Godot "llamar hacia abajo, avisar hacia arriba": el nodo padre
# configura a sus hijos directamente, y los hijos le avisan con señales.
extends Node2D

const CEO_SCENE: PackedScene = preload("res://scenes/ceo.tscn")
const EMPLOYEE_SCENE: PackedScene = preload("res://scenes/employee.tscn")
## Lo que puede moverse el ratón entre apretar y soltar para que cuente como clic.
const CLICK_TOLERANCE_PX: float = 8.0
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

var ceo: Ceo
## Personaje de cada empleado, por id.
var employees: Dictionary[int, Employee] = {}
# Despedidos que todavía caminan hacia la salida; desaparecen al salir.
var _departing: Array[Employee] = []
var pathfinder := OfficePathfinder.new()

# Si el reloj estaba en pausa antes de abrir el modo construcción o Ajustes.
var _was_paused_before_menu: bool = false
# Dónde se apretó el botón izquierdo (para distinguir un clic de un arrastre).
var _press_position := Vector2.INF
var _ceo_button: Button

@onready var _office_grid: OfficeGrid = $OfficeGrid
@onready var _camera: OfficeCamera = $OfficeCamera
@onready var _build_controller: BuildController = $BuildController
@onready var _build_panel: BuildPanel = $BuildPanel
@onready var _hud: Hud = $Hud
@onready var _settings_panel: SettingsPanel = $SettingsPanel
@onready var _staff_panel: StaffPanel = $StaffPanel
@onready var _projects_panel: ProjectsPanel = $ProjectsPanel
@onready var _employee_card: EmployeeCard = $EmployeeCard


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
	_sync_employees()
	_update_routines()
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
	_staff_panel.employee_selected.connect(_employee_card.open_employee)
	_projects_panel.attach_button(_build_panel.get_menu_bar())
	# Personal y Proyectos ocupan el mismo lado: abrir uno cierra el otro.
	_staff_panel.staff_mode_changed.connect(func(active: bool) -> void:
		if active:
			_projects_panel.set_open(false))
	_projects_panel.projects_mode_changed.connect(func(active: bool) -> void:
		if active:
			_staff_panel.set_open(false))
	_add_ceo_button(_build_panel.get_menu_bar())
	_employee_card.status_provider = describe_employee_activity
	_settings_panel.attach_button(_build_panel.get_menu_bar())
	_settings_panel.settings_mode_changed.connect(_on_settings_mode_changed)
	_settings_panel.save_requested.connect(_on_save_requested)
	_settings_panel.quit_requested.connect(_on_quit_requested)
	EventBus.office_changed.connect(_on_office_changed)
	EventBus.staff_changed.connect(_sync_employees)
	EventBus.hour_changed.connect(func(_hour: int) -> void: _update_routines())
	EventBus.presence_changed.connect(_update_routines)
	GameClock.start()


func _exit_tree() -> void:
	GameClock.stop()
	SaveManager.scene_state_provider = Callable()


# Lo que se guarda de la escena (el resto vive en los autoloads).
func _export_scene_state() -> Dictionary:
	var saved_employees: Dictionary = {}
	for employee_id: int in employees:
		saved_employees[str(employee_id)] = employees[employee_id].export_state()
	return {"camera": _camera.export_state(), "ceo": ceo.export_state(), "employees": saved_employees}


# Al abrir una partida cargada: la cámara y los personajes como estaban. Si la oficina
# estaba vacía, el tiempo salta hasta la próxima llegada, igual que al irse el último.
func _restore_scene_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	_camera.import_state(state.get("camera", {}))
	ceo.import_state(state.get("ceo", {}))
	var saved_employees: Dictionary = state.get("employees", {})
	for employee_id: int in employees:
		employees[employee_id].import_state(saved_employees.get(str(employee_id), {}))
	_update_routines()
	_on_character_left_office()


func _rebuild_office() -> void:
	_office_grid.set_site(OfficeState.site_rect)
	_office_grid.build(OfficeState.lot_rect, OfficeState.floors, OfficeState.edges, OfficeState.furniture,
		OfficeState.rooms)
	pathfinder.build(OfficeState.lot_rect, OfficeState.get_furniture_cells(), OfficeState.edges)


func _spawn_ceo() -> void:
	ceo = CEO_SCENE.instantiate()
	_office_grid.add_object(ceo)
	ceo.sat_down.connect(func() -> void: print("El CEO se sentó en su escritorio."))
	ceo.left_office.connect(_on_character_left_office)
	ceo.setup(_office_grid, pathfinder, _seat_of("ceo"), OfficeState.entrance,
		OfficeState.get_outside_of_entrance())


# Crea el personaje de cada empleado nuevo (entra por la entrada si le toca estar),
# quita el de los que ya no están y le avisa a cada uno si cambió su silla.
func _sync_employees() -> void:
	for employee: Dictionary in Staff.employees:
		var employee_id: int = employee["id"]
		if employees.has(employee_id):
			employees[employee_id].set_seat(_seat_of(Staff.employee_key(employee_id)))
			continue
		var character: Employee = EMPLOYEE_SCENE.instantiate()
		character.configure(employee)
		_office_grid.add_object(character)
		character.left_office.connect(_on_character_left_office)
		character.setup(_office_grid, pathfinder, _seat_of(character.person_key), OfficeState.entrance,
			OfficeState.get_outside_of_entrance())
		employees[employee_id] = character
		character.update_routine(Staff.is_expected_now(character.person_key))
	for employee_id: int in employees.keys():
		if Staff.get_employee(employee_id).is_empty():
			var leaving: Employee = employees[employee_id]
			employees.erase(employee_id)
			_departing.append(leaving)
			leaving.update_routine(false)
	_remove_departed()


# Quita a los despedidos que ya salieron del local.
func _remove_departed() -> void:
	for leaving: Employee in _departing.duplicate():
		if leaving.activity == OfficeCharacter.Activity.AWAY:
			_departing.erase(leaving)
			leaving.queue_free()


func _seat_of(key: String) -> Vector2i:
	return OfficeState.find_furniture_assigned_to(key).get("cell", OfficeState.entrance)


## Todos los personajes: el CEO y los empleados.
func get_characters() -> Array[OfficeCharacter]:
	var characters: Array[OfficeCharacter] = [ceo]
	for employee_id: int in employees:
		characters.append(employees[employee_id])
	characters.append_array(_departing)
	return characters


# Cada personaje entra o sale según si le toca estar en la oficina ahora.
func _update_routines() -> void:
	for character: OfficeCharacter in get_characters():
		var leaving: bool = character is Employee and _departing.has(character)
		character.update_routine(not leaving and Staff.is_expected_now(character.person_key))
	_update_ceo_button()


## Qué está haciendo un empleado, para su ficha.
func describe_employee_activity(employee_id: int) -> String:
	var character: Employee = employees.get(employee_id)
	if character == null:
		return "—"
	var lunch: bool = Staff.is_at_lunch(character.person_key)
	match character.activity:
		OfficeCharacter.Activity.WALKING_TO_DESK:
			return "llegando a su puesto"
		OfficeCharacter.Activity.SEATED:
			return "trabajando"
		OfficeCharacter.Activity.WALKING_OUT:
			return "saliendo a almorzar" if lunch else "yéndose a casa"
	return "almorzando fuera" if lunch else "fuera de su horario"


func _on_office_changed() -> void:
	_rebuild_office()
	for character: OfficeCharacter in get_characters():
		character.replan()


# El modo construcción pausa el tiempo y, al salir, lo deja como estaba.
func _on_build_mode_changed(active: bool) -> void:
	if active:
		_staff_panel.set_open(false)
		_projects_panel.set_open(false)
	_build_controller.set_active(active)
	_hud.set_controls_enabled(not active)
	_office_grid.set_rooms_visible(active)
	_camera.left_drag_enabled = not active
	# Con el tiempo en pausa los personajes no se mueven: sus casillas quedan reservadas.
	var occupied: Array[Vector2i] = []
	for character: OfficeCharacter in get_characters():
		if active and character.visible:
			occupied.append(character.get_cell())
	_build_controller.builder.occupied_cells = occupied
	_set_menu_pause(active)


func _on_settings_mode_changed(active: bool) -> void:
	if active:
		_staff_panel.set_open(false)
		_projects_panel.set_open(false)
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


## Indica si no queda nadie en la oficina (todos fuera, ninguno llegando ni saliendo).
func is_office_empty() -> bool:
	for character: OfficeCharacter in get_characters():
		if character.activity != OfficeCharacter.Activity.AWAY:
			return false
	return true


# Cuando se va el último, la oficina queda vacía: el tiempo salta hasta que llegue alguien.
func _on_character_left_office() -> void:
	_remove_departed()
	if not is_office_empty():
		return
	var hours: int = Staff.hours_until_anyone_expected()
	print("La oficina está vacía.")
	if hours > 0:
		GameClock.fast_forward_hours(hours)


# Botón del CEO en la barra de menús: lo manda a casa o a la oficina.
func _add_ceo_button(menu_bar: Container) -> void:
	_ceo_button = Button.new()
	_ceo_button.name = "CeoButton"
	_ceo_button.custom_minimum_size = Vector2(200.0, 44.0)
	_ceo_button.focus_mode = Control.FOCUS_NONE
	_ceo_button.pressed.connect(func() -> void: Staff.set_ceo_at_work(not Staff.ceo_at_work))
	menu_bar.add_child(_ceo_button)
	menu_bar.move_child(_ceo_button, _projects_panel.get_open_button().get_index() + 1)
	_update_ceo_button()


func _update_ceo_button() -> void:
	if _ceo_button != null:
		_ceo_button.text = "CEO: irse a casa" if Staff.ceo_at_work else "CEO: ir a la oficina"


## Botón que manda al CEO a casa o a la oficina.
func get_ceo_button() -> Button:
	return _ceo_button


# Un clic (sin arrastrar) sobre un empleado abre su ficha.
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or _is_menu_open():
		return
	if button.pressed:
		_press_position = button.position
		return
	if _press_position.distance_to(button.position) > CLICK_TOLERANCE_PX:
		return
	var world_point: Vector2 = get_canvas_transform().affine_inverse() * button.position
	var picked: Employee = employee_at(world_point)
	if picked != null:
		_employee_card.open_employee(picked.employee_id)
		get_viewport().set_input_as_handled()


## Empleado que se dibuja en ese punto del mundo (el de más adelante), o null.
func employee_at(world_point: Vector2) -> Employee:
	var picked: Employee = null
	for employee_id: int in employees:
		var character: Employee = employees[employee_id]
		if character.contains_point(world_point) and (picked == null or character.position.y > picked.position.y):
			picked = character
	return picked


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
