# Escena de juego: reúne la oficina, la cámara, el CEO y los empleados, el modo
# construcción y la interfaz superpuesta, y los prepara con el estado de la partida.
# Cada hora (y cuando cambia quién tiene que estar) les dice a los personajes si les
# toca estar en la oficina (Staff.is_expected); cuando todos se fueron, la oficina
# queda vacía y el tiempo salta hasta que llegue el próximo.
# Desde el hito 36 también dibuja a los clientes que esperan en la Recepción
# (Projects.visits): no cuentan para saber si la oficina está vacía.
# Sigue la regla de Godot "llamar hacia abajo, avisar hacia arriba": el nodo padre
# configura a sus hijos directamente, y los hijos le avisan con señales.
extends Node2D

const CEO_SCENE: PackedScene = preload("res://scenes/ceo.tscn")
const EMPLOYEE_SCENE: PackedScene = preload("res://scenes/employee.tscn")
const VISITOR_SCENE: PackedScene = preload("res://scenes/visitor.tscn")
## Lo que puede moverse el ratón entre apretar y soltar para que cuente como clic.
const CLICK_TOLERANCE_PX: float = 8.0
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

var ceo: Ceo
## Personaje de cada empleado, por id.
var employees: Dictionary[int, Employee] = {}
# Despedidos que todavía caminan hacia la salida; desaparecen al salir.
var _departing: Array[Employee] = []
## Personaje de cada cliente que espera en la Recepción, por id de visita.
var visitors: Dictionary[int, Visitor] = {}
# Clientes que ya se van; desaparecen al salir.
var _leaving_visitors: Array[Visitor] = []
var pathfinder := OfficePathfinder.new()

# Si el reloj estaba en pausa antes de abrir el modo construcción o Ajustes.
var _was_paused_before_menu: bool = false
# El modo construcción pausó el tiempo al entrar (opción pause_on_build, hito 60).
var _build_paused: bool = false
var _was_paused_before_emergency: bool = false
var _was_paused_before_ipo: bool = false
# Si el reloj estaba en pausa antes de abrir el menú de pausa (hito 62).
var _was_paused_before_pause: bool = false
# Ajustes se abrió desde el menú de pausa: al cerrarlo se vuelve a la pausa.
var _settings_from_pause: bool = false
# Menú de pausa (hito 62); se arma en código.
var _pause_menu: PauseMenu
# Tarjeta del tutorial (hito 63); se arma en código.
var _tutorial_panel: TutorialPanel
# Ayuda de los menús (hito 64, botones «?»); se arma en código.
var _help_dialog: HelpDialog
# Pantalla de cierre al salir a bolsa (hito 48); se arma en código.
var _ipo_screen: IpoScreen
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
@onready var _teams_panel: TeamsPanel = $TeamsPanel
@onready var _bank_panel: BankPanel = $BankPanel
@onready var _company_panel: CompanyPanel = $CompanyPanel
@onready var _objectives_panel: ObjectivesPanel = $ObjectivesPanel
@onready var _game_over_screen: GameOverScreen = $GameOverScreen
@onready var _emergency_dialog: EmergencyLoanDialog = $EmergencyLoanDialog
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
	update_status_icons()
	_restore_scene_state(SaveManager.take_scene_state())
	_sync_visitors()
	SaveManager.scene_state_provider = _export_scene_state
	_build_controller.setup(_office_grid)
	_build_controller.status_changed.connect(_build_panel.show_status)
	_build_panel.build_mode_changed.connect(_on_build_mode_changed)
	_build_panel.tool_selected.connect(_build_controller.set_tool)
	_build_panel.land_changed.connect(_build_controller.set_land)
	_build_panel.land_buy_requested.connect(func() -> void: _build_controller.buy_land())
	_hud.pause_pressed.connect(_on_pause_pressed)
	_hud.speed_pressed.connect(_on_speed_pressed)
	_hud.notice_clicked.connect(open_notice_target)
	_add_frame_button(_build_panel.get_menu_bar())
	_add_rotate_button(_build_panel.get_menu_bar())
	_camera.pan_blocker = _is_camera_locked
	_staff_panel.attach_button(_build_panel.get_menu_bar())
	_staff_panel.employee_selected.connect(_employee_card.open_employee)
	_projects_panel.attach_button(_build_panel.get_menu_bar())
	_teams_panel.attach_button(_build_panel.get_menu_bar())
	_bank_panel.attach_button(_build_panel.get_menu_bar())
	_company_panel.attach_button(_build_panel.get_menu_bar())
	# Personal, Proyectos, Equipos, Banco y Empresa ocupan el mismo lado: abrir uno cierra los otros.
	_staff_panel.staff_mode_changed.connect(func(active: bool) -> void:
		if active:
			_close_side_panels(_staff_panel))
	_projects_panel.projects_mode_changed.connect(func(active: bool) -> void:
		if active:
			_close_side_panels(_projects_panel))
	_teams_panel.teams_mode_changed.connect(func(active: bool) -> void:
		if active:
			_close_side_panels(_teams_panel))
	_bank_panel.bank_mode_changed.connect(func(active: bool) -> void:
		if active:
			_close_side_panels(_bank_panel))
	_company_panel.company_mode_changed.connect(func(active: bool) -> void:
		if active:
			_close_side_panels(_company_panel))
	# Los objetivos se pliegan mientras hay un panel izquierdo abierto.
	for panel: Signal in [_staff_panel.staff_mode_changed, _projects_panel.projects_mode_changed,
			_teams_panel.teams_mode_changed, _bank_panel.bank_mode_changed, _company_panel.company_mode_changed]:
		panel.connect(func(_active: bool) -> void: _update_objectives_fold())
	_add_ceo_button(_build_panel.get_menu_bar())
	_employee_card.status_provider = describe_employee_activity
	_settings_panel.attach_button(_build_panel.get_menu_bar())
	_settings_panel.settings_mode_changed.connect(_on_settings_mode_changed)
	_settings_panel.save_requested.connect(_on_save_requested)
	_settings_panel.quit_requested.connect(_on_quit_requested)
	_settings_panel.load_requested.connect(_on_load_requested)
	_pause_menu = PauseMenu.new()
	_pause_menu.name = "PauseMenu"
	add_child(_pause_menu)
	_pause_menu.resume_requested.connect(func() -> void: set_pause_menu_open(false))
	_pause_menu.settings_requested.connect(_open_settings_from_pause)
	_pause_menu.quit_requested.connect(_on_quit_requested)
	_tutorial_panel = TutorialPanel.new()
	_tutorial_panel.name = "TutorialPanel"
	_tutorial_panel.target_provider = tutorial_target_rect
	_tutorial_panel.corners_provider = _hud.get_corner_rects
	add_child(_tutorial_panel)
	_help_dialog = HelpDialog.new()
	_help_dialog.name = "HelpDialog"
	add_child(_help_dialog)
	_bank_panel.bank_mode_changed.connect(func(active: bool) -> void:
		if active:
			EventBus.ui_action.emit("bank_opened"))
	EventBus.office_changed.connect(_on_office_changed)
	EventBus.staff_changed.connect(_sync_employees)
	EventBus.staff_changed.connect(update_status_icons)
	EventBus.office_changed.connect(update_status_icons)
	EventBus.projects_changed.connect(update_status_icons)
	EventBus.visits_changed.connect(_sync_visitors)
	EventBus.dirt_changed.connect(_on_dirt_changed)
	EventBus.hour_changed.connect(func(_hour: int) -> void:
		_update_routines()
		update_status_icons()
		_send_bathroom_trips())
	EventBus.presence_changed.connect(_update_routines)
	EventBus.game_over.connect(_on_game_over)
	_game_over_screen.menu_requested.connect(_on_quit_requested)
	_ipo_screen = IpoScreen.new()
	_ipo_screen.name = "IpoScreen"
	add_child(_ipo_screen)
	_ipo_screen.menu_requested.connect(_on_quit_requested)
	_ipo_screen.continue_requested.connect(func() -> void: GameClock.set_paused(_was_paused_before_ipo))
	EventBus.went_public.connect(_on_went_public)
	EventBus.emergency_loan_offered.connect(_on_emergency_loan_offered)
	_emergency_dialog.closed.connect(_on_emergency_dialog_closed)
	# Un evento corta el salto de horas de la oficina vacía para que el jugador lo vea.
	EventBus.event_started.connect(func(_card: Dictionary) -> void: GameClock.interrupt())
	GameClock.start()
	# Una partida guardada con el préstamo de emergencia sin responder vuelve a preguntar.
	if not Bank.emergency_offer.is_empty():
		_on_emergency_loan_offered(Bank.emergency_offer)


func _exit_tree() -> void:
	GameClock.stop()
	SaveManager.scene_state_provider = Callable()


# Lo que se guarda de la escena (el resto vive en los autoloads).
func _export_scene_state() -> Dictionary:
	var saved_employees: Dictionary = {}
	for employee_id: int in employees:
		saved_employees[str(employee_id)] = employees[employee_id].export_state()
	return {"camera": _camera.export_state(), "view_rotation": _office_grid.view_rotation,
		"ceo": ceo.export_state(), "employees": saved_employees}


# Al abrir una partida cargada: la cámara y los personajes como estaban. Si la oficina
# estaba vacía, el tiempo salta hasta la próxima llegada, igual que al irse el último.
func _restore_scene_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	# Primero la orientación: la cámara guarda su centro en píxeles de la vista girada.
	if int(state.get("view_rotation", 0)) != _office_grid.view_rotation:
		_apply_view_rotation(int(state.get("view_rotation", 0)))
	_camera.import_state(state.get("camera", {}))
	ceo.import_state(state.get("ceo", {}))
	var saved_employees: Dictionary = state.get("employees", {})
	for employee_id: int in employees:
		employees[employee_id].import_state(saved_employees.get(str(employee_id), {}))
	_update_routines()
	_on_character_left_office()


func _rebuild_office() -> void:
	_office_grid.set_site(OfficeState.site_rect, OfficeState.get_outside_of_entrance())
	_office_grid.build(OfficeState.lot, OfficeState.floors, OfficeState.edges, OfficeState.furniture,
		OfficeState.rooms)
	pathfinder.build(OfficeState.lot, OfficeState.get_blocking_cells(), OfficeState.edges)


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
			employees[employee_id].set_seat(_spot_of(employee))
			employees[employee_id].update_role(employee)
			continue
		var character: Employee = EMPLOYEE_SCENE.instantiate()
		character.configure(employee)
		_office_grid.add_object(character)
		character.left_office.connect(_on_character_left_office)
		character.setup(_office_grid, pathfinder, _spot_of(employee), OfficeState.entrance,
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


# Crea el personaje de cada cliente que llegó (entra y va a su lugar de espera), manda
# a casa a los que ya no esperan y reparte los lugares si cambió la Recepción.
func _sync_visitors() -> void:
	var spots: Array[Vector2i] = Projects.get_waiting_spots()
	var waiting: Array[int] = []
	for index: int in range(Projects.visits.size()):
		var visit: Dictionary = Projects.visits[index]
		var visit_id: int = visit["id"]
		waiting.append(visit_id)
		var spot: Vector2i = spots[index % spots.size()] if not spots.is_empty() else OfficeState.entrance
		if visitors.has(visit_id):
			visitors[visit_id].set_seat(spot)
			continue
		var character: Visitor = VISITOR_SCENE.instantiate()
		character.configure(visit)
		_office_grid.add_object(character)
		character.left_office.connect(_remove_left_visitors)
		character.setup(_office_grid, pathfinder, spot, OfficeState.entrance, OfficeState.get_outside_of_entrance())
		visitors[visit_id] = character
		character.update_routine(true)
	for visit_id: int in visitors.keys():
		if not waiting.has(visit_id):
			var leaving: Visitor = visitors[visit_id]
			visitors.erase(visit_id)
			_leaving_visitors.append(leaving)
			leaving.update_routine(false)
	_remove_left_visitors()


func _remove_left_visitors() -> void:
	for leaving: Visitor in _leaving_visitors.duplicate():
		if leaving.activity == OfficeCharacter.Activity.AWAY:
			_leaving_visitors.erase(leaving)
			leaving.queue_free()


# Quita a los despedidos que ya salieron del local.
func _remove_departed() -> void:
	for leaving: Employee in _departing.duplicate():
		if leaving.activity == OfficeCharacter.Activity.AWAY:
			_departing.erase(leaving)
			leaving.queue_free()


func _on_dirt_changed() -> void:
	_office_grid.set_dirt(OfficeState.rooms)
	_sync_employees()


# Adónde va un empleado: el personal de limpieza en su turno, a la habitación que limpia
# (hito 37); los demás, a su silla.
func _spot_of(employee: Dictionary) -> Vector2i:
	var room_index: int = Staff.get_cleaning_room(employee)
	if room_index >= 0:
		return OfficeState.get_room_spot(room_index)
	return _seat_of(Staff.employee_key(employee["id"]))


# Adónde va alguien cuando trabaja: el CEO a su silla y cada empleado a su lugar.
func _home_spot(key: String) -> Vector2i:
	if key == "ceo":
		return _seat_of(key)
	var employee: Dictionary = Staff.get_employee_by_key(key)
	return _seat_of(key) if employee.is_empty() else _spot_of(employee)


func _seat_of(key: String) -> Vector2i:
	return OfficeState.find_furniture_assigned_to(key).get("cell", OfficeState.entrance)


## Todos los personajes: el CEO y los empleados.
func get_characters() -> Array[OfficeCharacter]:
	var characters: Array[OfficeCharacter] = [ceo]
	for employee_id: int in employees:
		characters.append(employees[employee_id])
	characters.append_array(_departing)
	return characters


# Cada personaje entra o sale según si le toca estar en la oficina ahora. Quien almuerza
# dentro (hito 53) camina a una mesa de la Sala de descanso y después vuelve a su silla.
func _update_routines() -> void:
	var lunch: Dictionary[String, bool] = Staff.get_lunch_inside(Staff.get_absolute_hour())
	var spots: Array[Vector2i] = []
	if not lunch.is_empty():
		spots = OfficeState.get_lunch_spots()
	var next_spot: int = 0
	# Pausas (hito 54): los cansados van junto a un sofá.
	var resting: Array[String] = Staff.get_breaks(Staff.get_absolute_hour())
	var rest_spots: Array[Vector2i] = []
	if not resting.is_empty():
		rest_spots = OfficeState.get_rest_spots()
	var next_rest: int = 0
	for character: OfficeCharacter in get_characters():
		var leaving: bool = character is Employee and _departing.has(character)
		if leaving:
			character.update_routine(false)
			continue
		var eating: bool = lunch.has(character.person_key) and not spots.is_empty()
		if eating:
			character.set_seat(spots[next_spot % spots.size()])
			next_spot += 1
		elif resting.has(character.person_key) and not rest_spots.is_empty():
			character.set_seat(rest_spots[next_rest % rest_spots.size()])
			next_rest += 1
		else:
			character.set_seat(_home_spot(character.person_key))
		character.update_routine(eating or Staff.is_expected_now(character.person_key))
	_update_ceo_button()


## Faltan inodoros (hito 52): cada hora algunos de los que están sentados salen del
## edificio a buscar un baño y vuelven (solo se ve; la producción ya lo cuenta).
## Devuelve cuántos salieron.
func _send_bathroom_trips(hour: int = -1) -> int:
	if hour < 0:
		hour = Staff.get_absolute_hour()
	var shortage: int = Staff.get_bathroom_shortage(hour)
	if shortage <= 0:
		return 0
	var seated: Array[OfficeCharacter] = get_characters().filter(func(character: OfficeCharacter) -> bool:
		return character.activity == OfficeCharacter.Activity.SEATED and not (character is Employee and _departing.has(character)))
	# Cada uno sale una vez cada trip_every_hours horas, en su turno (repartidos por su clave);
	# por hora salen como mucho los que no caben divididos por esas horas.
	var every: int = maxi(1, int(StaffCatalog.get_bathrooms("trip_every_hours")))
	var unfit: int = mini(Staff.count_present(hour), shortage * int(StaffCatalog.get_bathrooms("people_per_toilet")))
	var limit: int = ceili(float(unfit) / every)
	var count: int = 0
	for character: OfficeCharacter in seated:
		if count >= limit:
			break
		if posmod(character.person_key.hash() + hour, every) == 0:
			character.step_out()
			count += 1
	return count


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
			if lunch:
				return "almorzando en la Sala de descanso"
			return "descansando en la Sala de descanso" if Staff.is_on_break(character.person_key) else "trabajando"
		OfficeCharacter.Activity.WALKING_OUT:
			return "saliendo a almorzar" if lunch else "yéndose a casa"
		OfficeCharacter.Activity.STEPPING_OUT:
			return "buscando un baño fuera del edificio"
	return "almorzando fuera" if lunch else "fuera de su horario"


## Pone a cada empleado su icono de estado (hito 57). Se llama al cambiar la hora, el
## personal, la oficina o los proyectos; no cada cuadro.
func update_status_icons() -> void:
	for employee_id: int in employees:
		var employee: Dictionary = Staff.get_employee(employee_id)
		employees[employee_id].set_status_icon("" if employee.is_empty() else Staff.get_status_icon(employee))


## Abre lo que señala un aviso (EventBus.send_notice): la ficha del empleado, Proyectos en
## su pestaña, el menú o la cámara sobre la habitación.
func open_notice_target(target: Dictionary) -> void:
	match String(target.get("type", "")):
		"employee":
			if not Staff.get_employee(int(target["id"])).is_empty():
				_employee_card.open_employee(int(target["id"]))
		"contract":
			_projects_panel.set_open(true)
			_projects_panel.set_tab(ProjectsPanel.TAB_CONTRACTS)
		"product":
			_projects_panel.set_open(true)
			_projects_panel.set_tab(ProjectsPanel.TAB_PRODUCTS)
		"room":
			var cell: Vector2i = target["cell"]
			_camera.center_on(_office_grid.grid_to_world(Vector2(cell)), true)
		"menu":
			var panels: Dictionary[String, CanvasLayer] = {"staff": _staff_panel, "projects": _projects_panel,
				"teams": _teams_panel, "bank": _bank_panel, "company": _company_panel}
			var panel: CanvasLayer = panels.get(String(target["menu"]))
			if panel != null:
				panel.call("set_open", true)


func _on_office_changed() -> void:
	_rebuild_office()
	for character: OfficeCharacter in get_characters():
		character.replan()
	_sync_visitors()
	for visitor: Visitor in _leaving_visitors:
		visitor.replan()


# Pliega los objetivos si hay algún panel del lado izquierdo abierto.
func _update_objectives_fold() -> void:
	_objectives_panel.set_suppressed(_staff_panel.is_open() or _projects_panel.is_open() or _teams_panel.is_open()
		or _bank_panel.is_open() or _company_panel.is_open())


# Cierra los paneles del lado izquierdo menos uno (null los cierra todos).
func _close_side_panels(keep: CanvasLayer) -> void:
	if keep != _staff_panel:
		_staff_panel.set_open(false)
	if keep != _projects_panel:
		_projects_panel.set_open(false)
	if keep != _teams_panel:
		_teams_panel.set_open(false)
	if keep != _bank_panel:
		_bank_panel.set_open(false)
	if keep != _company_panel:
		_company_panel.set_open(false)


# El modo construcción pausa el tiempo (si la opción lo pide) y, al salir, lo deja como estaba.
func _on_build_mode_changed(active: bool) -> void:
	if active:
		_close_side_panels(null)
		EventBus.ui_action.emit("build_opened")
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
	# Pausar al construir es una opción (hito 60); se recuerda si pausó al entrar para
	# devolver el tiempo como estaba al salir.
	if active:
		_build_paused = bool(Settings.get_value("pause_on_build"))
	if _build_paused:
		_set_menu_pause(active)


## Rectángulo en pantalla de lo que el tutorial resalta (claves de data/tutorial.json), o
## Rect2() si no se ve.
func tutorial_target_rect(key: String) -> Rect2:
	if key == "office":
		return get_canvas_transform() * _office_grid.get_lot_world_rect()
	var control: Control = null
	match key:
		"build":
			control = _build_panel.get_open_button()
		"build_exit":
			control = _build_panel.get_exit_button()
		"staff":
			control = _staff_panel.get_open_button()
		"staff_publish":
			control = _staff_panel.get_publish_button()
		"projects":
			control = _projects_panel.get_open_button()
		"projects_accept":
			if not Projects.offers.is_empty():
				control = _projects_panel.get_accept_button(int(Projects.offers[0]["id"]))
		"projects_deliver":
			if not Projects.contracts.is_empty():
				control = _projects_panel.get_deliver_button(int(Projects.contracts[0]["id"]))
		"speed":
			control = _hud.get_speed_button(1)
		"bank":
			control = _bank_panel.get_open_button()
		_:
			if key.begins_with("tool:"):
				control = _build_panel.get_tool_button(key.trim_prefix("tool:"))
	if control == null or not control.is_visible_in_tree():
		return Rect2()
	return control.get_global_rect()


func get_tutorial_panel() -> TutorialPanel:
	return _tutorial_panel


func get_help_dialog() -> HelpDialog:
	return _help_dialog


func _on_settings_mode_changed(active: bool) -> void:
	if active:
		_close_side_panels(null)
	_build_panel.get_menu_bar().visible = not active
	_hud.set_controls_enabled(not active)
	_set_menu_pause(active)
	# Abierto desde la pausa: al cerrarlo se vuelve a ella.
	if not active and _settings_from_pause:
		_settings_from_pause = false
		set_pause_menu_open(true)


## Abre o cierra el menú de pausa (hito 62): al abrirlo se cierran los paneles, se oculta la
## barra y se detiene el tiempo; al cerrarlo (Seguir) el tiempo vuelve a como estaba.
func set_pause_menu_open(open: bool) -> void:
	if open == _pause_menu.is_open():
		return
	if open:
		_close_side_panels(null)
		_employee_card.close()
		_was_paused_before_pause = GameClock.is_paused
		GameClock.set_paused(true)
	else:
		GameClock.set_paused(_was_paused_before_pause)
	_pause_menu.set_open(open)
	_build_panel.get_menu_bar().visible = not open
	_hud.set_controls_enabled(not open)


func is_pause_menu_open() -> bool:
	return _pause_menu.is_open()


func get_pause_menu() -> PauseMenu:
	return _pause_menu


# Guardar, Cargar o Ajustes desde la pausa: la pausa deja el tiempo como estaba antes y
# Ajustes lo pausa por su cuenta (así guarda la partida con la pausa de antes del menú).
func _open_settings_from_pause(tab: String) -> void:
	set_pause_menu_open(false)
	_settings_from_pause = true
	_settings_panel.set_open(true)
	_settings_panel.set_tab(tab)


## Esc (hito 62): cierra primero lo que esté abierto, de lo más reciente a lo más general
## (la ayuda, una pregunta, Ajustes, la pausa, el modo construcción, la ficha, un panel izquierdo);
## si no hay nada, abre la pausa. Las pantallas que piden una respuesta no se cierran.
## Devuelve qué hizo, para las pruebas.
func handle_escape() -> String:
	if _game_over_screen.is_open() or _emergency_dialog.is_open() or _ipo_screen.is_open():
		return "none"
	if _help_dialog.is_open():
		_help_dialog.close()
		return "help"
	if _settings_panel.is_open():
		if _settings_panel.is_confirming():
			_settings_panel.cancel_confirm()
			return "settings_confirm"
		_settings_panel.set_open(false)
		return "settings"
	if _pause_menu.is_open():
		if _pause_menu.is_confirming():
			_pause_menu.cancel_confirm()
			return "pause_confirm"
		set_pause_menu_open(false)
		return "resume"
	if _build_panel.is_build_mode():
		_build_panel.set_build_mode(false)
		return "build"
	if _employee_card.is_open():
		_employee_card.close()
		return "card"
	if _staff_panel.is_open() or _projects_panel.is_open() or _teams_panel.is_open() or _bank_panel.is_open() \
			or _company_panel.is_open():
		_close_side_panels(null)
		return "panel"
	set_pause_menu_open(true)
	return "pause"


# Mientras un menú que pausa está abierto, el tiempo se detiene; al cerrarlo vuelve a
# como estaba.
func _set_menu_pause(active: bool) -> void:
	if active:
		_was_paused_before_menu = GameClock.is_paused
		GameClock.set_paused(true)
	else:
		GameClock.set_paused(_was_paused_before_menu)


func _is_menu_open() -> bool:
	return (_build_panel.is_build_mode() or _settings_panel.is_open() or _game_over_screen.is_open()
		or _emergency_dialog.is_open() or _ipo_screen.is_open() or _pause_menu.is_open())


func _on_save_requested(slot: String) -> void:
	# Se guarda con la pausa que había antes de abrir Ajustes, no con la del menú.
	var paused_now: bool = GameClock.is_paused
	GameClock.set_paused(_was_paused_before_menu)
	var saved: bool = SaveManager.save_game(slot)
	GameClock.set_paused(paused_now)
	_settings_panel.refresh_slots()
	_settings_panel.show_status("Guardado en la %s." % SaveManager.get_slot_name(slot).to_lower()
		if saved else "No se pudo guardar.")


# Embargo total: se detiene el tiempo, se cierran los menús y queda la pantalla de fin.
func _on_game_over(stats: Dictionary) -> void:
	GameClock.stop()
	_close_side_panels(null)
	_employee_card.close()
	_hud.set_controls_enabled(false)
	_game_over_screen.show_stats(stats)


# Salida a bolsa: se corta el salto, se pausa, se cierran los menús y queda la pantalla de
# cierre; «Seguir jugando» vuelve a la partida como estaba (modo libre).
func _on_went_public(stats: Dictionary) -> void:
	GameClock.interrupt()
	if not _ipo_screen.is_open():
		_was_paused_before_ipo = GameClock.is_paused
	GameClock.set_paused(true)
	_close_side_panels(null)
	_employee_card.close()
	_ipo_screen.show_stats(stats)


# El banco ofrece el préstamo de emergencia: se corta el salto de tiempo, se pausa y se
# pregunta.
func _on_emergency_loan_offered(offer: Dictionary) -> void:
	# Otro que escucha la señal pudo haberla respondido ya.
	if Bank.emergency_offer.is_empty():
		return
	GameClock.interrupt()
	if not _emergency_dialog.is_open():
		_was_paused_before_emergency = GameClock.is_paused
	GameClock.set_paused(true)
	_employee_card.close()
	_emergency_dialog.show_offer(offer)


# Respondida la oferta, el tiempo vuelve a como estaba y, si la oficina sigue vacía,
# sigue el salto hasta la próxima llegada.
func _on_emergency_dialog_closed() -> void:
	GameClock.set_paused(_was_paused_before_emergency)
	_on_character_left_office()


func _on_quit_requested() -> void:
	get_tree().change_scene_to_file(MENU_SCENE_PATH)


# Cargar desde Ajustes (hito 60, ya confirmado): se lee la ranura y se vuelve a abrir la
# escena de juego con ella; si no sirve, la partida sigue como estaba.
func _on_load_requested(slot: String) -> void:
	if SaveManager.load_game(slot):
		get_tree().change_scene_to_file(scene_file_path)
	else:
		_settings_panel.show_status("No se pudo cargar la %s." % SaveManager.get_slot_name(slot).to_lower())


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		on_focus_lost()


## La ventana perdió el foco: si la opción lo pide, se pausa (hito 60). Al volver sigue en
## pausa hasta que el jugador la quite.
func on_focus_lost() -> void:
	if not bool(Settings.get_value("pause_on_focus_loss")):
		return
	if _is_menu_open():
		# Con un menú que pausa abierto, al cerrarlo no debe volver a correr solo.
		_was_paused_before_menu = true
	if _pause_menu.is_open():
		_was_paused_before_pause = true
	GameClock.set_paused(true)


## Indica si no queda nadie en la oficina (todos fuera, ninguno llegando ni saliendo).
func is_office_empty() -> bool:
	for character: OfficeCharacter in get_characters():
		if character.activity != OfficeCharacter.Activity.AWAY:
			return false
	return true


# Cuando se va el último, la oficina queda vacía: el tiempo salta hasta que llegue alguien.
func _on_character_left_office() -> void:
	_remove_departed()
	if not is_office_empty() or Bank.game_over:
		return
	var hours: int = Staff.hours_until_anyone_expected()
	print("La oficina está vacía.")
	if hours > 0:
		GameClock.fast_forward_hours(hours)


# Botón del CEO en la barra de menús: lo manda a casa o a la oficina.
func _add_ceo_button(menu_bar: Container) -> void:
	_ceo_button = Button.new()
	_ceo_button.name = "CeoButton"
	_ceo_button.custom_minimum_size = Vector2(172.0, Hud.MENU_BUTTON_SIZE.y)
	_ceo_button.focus_mode = Control.FOCUS_NONE
	_ceo_button.pressed.connect(func() -> void: Staff.set_ceo_at_work(not Staff.ceo_at_work))
	menu_bar.add_child(_ceo_button)
	menu_bar.move_child(_ceo_button, _company_panel.get_open_button().get_index() + 1)
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
	# Más angosto que los demás: junto al botón de girar entran en una fila a 1280 de ancho.
	button.custom_minimum_size = Vector2(Hud.MENU_BUTTON_SIZE.x - Hud.MENU_BUTTON_SIZE.y, Hud.MENU_BUTTON_SIZE.y)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(frame_office)
	menu_bar.add_child(button)


## Encuadra la oficina completa (botón «Ver oficina» o tecla F), con animación si la
## cámara es suave.
func frame_office() -> void:
	_camera.fit_rect(_office_grid.get_lot_world_rect(), true)


# Botón de girar la vista (↻) de la barra de menús: un cuarto de vuelta en el sentido del reloj
# (Q y E giran hacia cada lado).
func _add_rotate_button(menu_bar: Container) -> void:
	var button := Button.new()
	button.name = "RotateViewButton"
	button.text = "↻"
	button.tooltip_text = "Girar la vista un cuarto de vuelta (teclas Q y E)"
	button.custom_minimum_size = Vector2(Hud.MENU_BUTTON_SIZE.y, Hud.MENU_BUTTON_SIZE.y)
	button.add_theme_font_size_override("font_size", 22)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(rotate_view.bind(1))
	menu_bar.add_child(button)


## Botón de girar la vista (↻).
func get_rotate_button() -> Button:
	return menu_bar_button("RotateViewButton")


## Un botón de la barra de menús por su nombre.
func menu_bar_button(button_name: String) -> Button:
	return _build_panel.get_menu_bar().get_node_or_null(button_name) as Button


## Gira la vista quarter_turns cuartos de vuelta (positivo: como las agujas del reloj)
## dejando en el centro de la pantalla lo mismo que había.
func rotate_view(quarter_turns: int) -> void:
	_apply_view_rotation(_office_grid.view_rotation + quarter_turns)
	EventBus.ui_action.emit("view_rotated")


func _apply_view_rotation(quarter_turns: int) -> void:
	_camera.finish_motion()
	var center: Vector2 = _office_grid.world_to_grid(_camera.position)
	_office_grid.set_view_rotation(quarter_turns)
	_rebuild_office()
	_camera.set_map_area(_office_grid.get_site_world_area())
	_camera.center_on(_office_grid.grid_to_world(center))
	for character: OfficeCharacter in get_characters():
		character.refresh_position()
	for visitor: Visitor in visitors.values() + _leaving_visitors:
		if is_instance_valid(visitor):
			visitor.refresh_position()
	_build_controller.queue_redraw()


# El teclado y el borde de la pantalla no mueven la cámara con un menú encima (el modo
# construcción sí la deja moverse).
func _is_camera_locked() -> bool:
	return (_settings_panel.is_open() or _game_over_screen.is_open() or _emergency_dialog.is_open()
		or _ipo_screen.is_open() or _pause_menu.is_open())


func _on_speed_pressed(index: int) -> void:
	if not _is_menu_open():
		GameClock.set_speed_index(index)
		EventBus.ui_action.emit("speed_changed")


# Atajos de teclado (un extra: los botones del reloj hacen lo mismo).
# Esc: cierra lo abierto o abre el menú de pausa (handle_escape, hito 62).
# Espacio: pausa · 1, 2, 3: velocidad 1x, 2x, 4x. En modo construcción no cambian
# nada, porque el tiempo tiene que quedarse en pausa. F: ver la oficina completa
# (funciona siempre). Q y E: girar la vista. WASD y flechas mueven la cámara (OfficeCamera).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		handle_escape()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_F:
		frame_office()
		get_viewport().set_input_as_handled()
		return
	if (key.physical_keycode == KEY_Q or key.physical_keycode == KEY_E) and not _is_camera_locked() \
			and not key.ctrl_pressed and not key.meta_pressed:
		rotate_view(1 if key.physical_keycode == KEY_E else -1)
		get_viewport().set_input_as_handled()
		return
	if _is_menu_open():
		return
	match key.keycode:
		KEY_SPACE:
			GameClock.toggle_pause()
		KEY_1, KEY_2, KEY_3:
			GameClock.set_speed_index(key.keycode - KEY_1)
			EventBus.ui_action.emit("speed_changed")
		_:
			return
	get_viewport().set_input_as_handled()
