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

# El jugador pidió las paredes arriba (botón ↕ o tecla P).
var _walls_wanted: bool = false
var ceo: Ceo
## Personaje de cada empleado, por id.
var employees: Dictionary[int, Employee] = {}
# Despedidos que todavía caminan hacia la salida; desaparecen al salir.
var _departing: Array[Employee] = []
## Personaje de cada cliente que espera en la Recepción, por id de visita.
var visitors: Dictionary[int, Visitor] = {}
# Clientes que ya se van; desaparecen al salir.
var _leaving_visitors: Array[Visitor] = []
## El candidato que está en su entrevista (camina hasta el escritorio de quien lo
## entrevista, el CEO o el ejecutivo, y se va al terminar); null si no hay entrevista.
var interviewee: Visitor = null
## Candidatos citados que ya llegaron y esperan su entrevista: id del candidato → personaje.
## Al empezar la entrevista el suyo pasa a ser interviewee.
var appointment_visitors: Dictionary[int, Visitor] = {}
var pathfinder := OfficePathfinder.new()
# Llegadas escalonadas: clave → minuto absoluto (hora absoluta × 60 + minuto) en que entra
# quien todavía no llegó. Se recalcula en cada _update_routines.
var _arrivals: Dictionary[String, int] = {}
# Salidas escalonadas: clave → minuto absoluto en que se va quien terminó su jornada.
var _departures: Dictionary[String, int] = {}
# Quienes llegaron antes de su hora: esperan en la Sala de descanso o dan vueltas.
var _early: Dictionary[String, bool] = {}
# Último minuto (o tramo de vueltas) en que se revisaron las llegadas.
var _last_arrival_check: int = -1

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
	_sync_interview()
	SaveManager.scene_state_provider = _export_scene_state
	_build_controller.setup(_office_grid)
	_build_controller.status_changed.connect(_build_panel.show_status)
	_build_panel.build_mode_changed.connect(_on_build_mode_changed)
	_build_panel.tool_selected.connect(_build_controller.set_tool)
	_build_controller.confirm_changed.connect(_build_panel.show_confirm)
	_build_panel.confirm_answered.connect(func(accept: bool) -> void: _build_controller.answer_confirm(accept))
	_build_panel.tool_selected.connect(func(_tool: String) -> void: _apply_walls())
	_build_panel.build_mode_changed.connect(func(_active: bool) -> void: _apply_walls())
	_hud.pause_pressed.connect(_on_pause_pressed)
	_hud.speed_pressed.connect(_on_speed_pressed)
	_hud.notice_clicked.connect(open_notice_target)
	_add_frame_button(_build_panel.get_menu_bar())
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
	EventBus.staff_changed.connect(_sync_interview)
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
	return {"camera": _camera.export_state(), "ceo": ceo.export_state(), "employees": saved_employees}


# Al abrir una partida cargada: la cámara y los personajes como estaban. Si la oficina
# estaba vacía, el tiempo salta hasta la próxima llegada, igual que al irse el último.
func _restore_scene_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	# La vista ya no se gira: una partida guardada con la vista girada vuelve a la esquina de
	# siempre y la cámara encuadra la oficina.
	if int(state.get("view_rotation", 0)) != 0:
		frame_office()
	else:
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
	var used: Dictionary[Vector2i, bool] = {}
	for index: int in range(Projects.visits.size()):
		var visit: Dictionary = Projects.visits[index]
		var visit_id: int = visit["id"]
		waiting.append(visit_id)
		var spot: Vector2i = _free_spot_near(spots[index % spots.size()], used) if not spots.is_empty() \
			else OfficeState.entrance
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


# El candidato de la entrevista entra y va frente al escritorio de quien lo entrevista;
# al terminar (o cortarse) la entrevista se va.
func _sync_interview() -> void:
	var candidate: Dictionary = Staff.get_interviewed_now()
	var candidate_key: String = "" if candidate.is_empty() else "candidate_%d" % int(candidate["id"])
	if interviewee != null and interviewee.person_key != candidate_key:
		_leaving_visitors.append(interviewee)
		interviewee.update_routine(false)
		interviewee = null
		_remove_left_visitors()
	if candidate.is_empty() or interviewee != null:
		_sync_appointments()
		return
	var by: String = String(Staff.interview.get("by", "ceo"))
	var waiting: Visitor = appointment_visitors.get(int(candidate["id"]))
	if waiting != null:
		# Ya estaba esperando: camina hasta la silla de visita.
		appointment_visitors.erase(int(candidate["id"]))
		interviewee = waiting
		interviewee.hurry = not Staff.is_interview_started()
		interviewee.sat_down.connect(_on_interviewee_seated.bind(interviewee))
		interviewee.standing = Staff.get_guest_chair(by).is_empty()
		interviewee.set_seat(_interview_spot(by))
		_sync_appointments()
		return
	interviewee = VISITOR_SCENE.instantiate()
	interviewee.configure_candidate(candidate)
	interviewee.standing = Staff.get_guest_chair(String(Staff.interview.get("by", "ceo"))).is_empty()
	_office_grid.add_object(interviewee)
	interviewee.left_office.connect(_remove_left_visitors)
	interviewee.sat_down.connect(_on_interviewee_seated.bind(interviewee))
	interviewee.hurry = not Staff.is_interview_started()
	interviewee.setup(_office_grid, pathfinder, _interview_spot(String(Staff.interview.get("by", "ceo"))),
		OfficeState.entrance, OfficeState.get_outside_of_entrance())
	interviewee.update_routine(true)
	_sync_appointments()


# El candidato llamado llegó a la silla de visita: empieza la entrevista.
func _on_interviewee_seated(character: Visitor) -> void:
	if character == interviewee and character.person_key == "candidate_%d" % int(Staff.interview.get("candidate_id", -1)):
		Staff.start_called_interview()


# Los candidatos citados llegan antes de su hora (Staff.get_appointment_arrival) y esperan
# de pie en la Recepción o junto a la entrada; si se cancela la cita se van.
func _sync_appointments() -> void:
	var now: int = get_arrival_minute()
	var due: Array[int] = []
	for appointment: Dictionary in Staff.appointments:
		if Staff.get_appointment_arrival(appointment) <= now:
			due.append(int(appointment["candidate_id"]))
	var used: Dictionary[Vector2i, bool] = {}
	for visitor: Visitor in visitors.values():
		used[visitor.get_seat_cell()] = true
	var spots: Array[Vector2i] = Projects.get_waiting_spots()
	if spots.is_empty() and not due.is_empty():
		spots = _cells_near(OfficeState.entrance, due.size() + used.size() + 1)
		spots.erase(OfficeState.entrance)
	for index: int in range(due.size()):
		var candidate_id: int = due[index]
		var spot: Vector2i = _free_spot_near(spots[index % spots.size()], used) if not spots.is_empty() \
			else OfficeState.entrance
		if appointment_visitors.has(candidate_id):
			appointment_visitors[candidate_id].set_seat(spot)
			continue
		var character: Visitor = VISITOR_SCENE.instantiate()
		character.configure_candidate(Staff.get_candidate(candidate_id))
		_office_grid.add_object(character)
		character.left_office.connect(_remove_left_visitors)
		character.setup(_office_grid, pathfinder, spot, OfficeState.entrance, OfficeState.get_outside_of_entrance())
		appointment_visitors[candidate_id] = character
		character.update_routine(true)
	for candidate_id: int in appointment_visitors.keys():
		if not due.has(candidate_id):
			var leaving: Visitor = appointment_visitors[candidate_id]
			appointment_visitors.erase(candidate_id)
			_leaving_visitors.append(leaving)
			leaving.update_routine(false)
	_remove_left_visitors()


## Casilla donde se para el candidato: del otro lado del escritorio de quien entrevista
## ("ceo" o la clave del ejecutivo), dentro de su habitación; si no hay, junto a su silla.
func _interview_spot(by: String) -> Vector2i:
	# En la silla de visita de su oficina, si tiene.
	var guest: Dictionary = Staff.get_guest_chair(by)
	if not guest.is_empty():
		return guest["cell"]
	var chair: Vector2i = _seat_of(by)
	var desk_cells: Array[Vector2i] = []
	for item: Dictionary in OfficeState.furniture:
		if bool(FurnitureCatalog.get_item(String(item["id"])).get("accepts_computer", false)):
			var cells: Array[Vector2i] = FurnitureCatalog.get_footprint(item["id"], item["cell"], int(item["rotation"]))
			for cell: Vector2i in cells:
				if (cell - chair).abs().x + (cell - chair).abs().y == 1:
					desk_cells = cells
	var room: Dictionary = Staff.get_workplace_room(by)
	var room_cells: Array = room.get("cells", [])
	var best := chair
	var best_score: int = -1000000
	var around: Array[Vector2i] = desk_cells if not desk_cells.is_empty() else [chair] as Array[Vector2i]
	for base: Vector2i in around:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var cell: Vector2i = base + direction
			if cell == chair or desk_cells.has(cell) or not pathfinder.is_walkable(cell) or cell == OfficeState.entrance:
				continue
			if not room_cells.is_empty() and not room_cells.has(cell):
				continue
			# Frente a la silla, del otro lado del escritorio: lo más lejos posible de ella.
			var score: int = (cell - chair).abs().x + (cell - chair).abs().y
			if score > best_score:
				best_score = score
				best = cell
	if best == chair:
		return _cells_near(chair, 2)[-1] if pathfinder.is_walkable(chair) else OfficeState.entrance
	return best


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
		# Si limpian varios la misma habitación, cada uno en su casilla.
		var before: int = 0
		for other: Dictionary in Staff.employees:
			if int(other["id"]) < int(employee["id"]) and Staff.get_cleaning_room(other) == room_index:
				before += 1
		var near: Array[Vector2i] = _cells_near(OfficeState.get_room_spot(room_index), before + 1)
		return near[mini(before, near.size() - 1)]
	return _seat_of(Staff.employee_key(employee["id"]))


# Una persona por casilla: casillas libres para pisar alrededor de spot (spot primero),
# las más cercanas caminando, hasta count; nunca la entrada.
func _cells_near(spot: Vector2i, count: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = [spot]
	var index: int = 0
	while index < found.size() and found.size() < count:
		var cell: Vector2i = found[index]
		index += 1
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = cell + direction
			if found.size() < count and not found.has(next) and next != OfficeState.entrance \
					and pathfinder.is_walkable(next) and pathfinder.can_cross(cell, next):
				found.append(next)
	return found


# La casilla libre más cercana a spot que nadie más tiene en used (y la anota).
func _free_spot_near(spot: Vector2i, used: Dictionary[Vector2i, bool]) -> Vector2i:
	var count: int = used.size() + 1
	for cell: Vector2i in _cells_near(spot, count):
		if not used.has(cell):
			used[cell] = true
			return cell
	return spot


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


## Minuto absoluto del reloj (hora absoluta × 60 + minuto), el de _arrivals.
func get_arrival_minute() -> int:
	return Staff.get_absolute_hour() * 60 + GameClock.get_minute()


## Minuto absoluto en que entra cada empleado que todavía no llegó (copia).
func get_pending_arrivals() -> Dictionary[String, int]:
	return _arrivals.duplicate()


## Minuto absoluto en que se va cada empleado que terminó su jornada y sigue (copia).
func get_pending_departures() -> Dictionary[String, int]:
	return _departures.duplicate()


## Indica si alguien llegó antes de su hora y está esperando.
func is_waiting_shift(key: String) -> bool:
	return _early.has(key)


# Llegadas escalonadas (data/staff.json, arrivals): al empezar la jornada cada empleado
# entra unos minutos antes o después de la hora en punto. Quien llega antes espera de pie
# en la Sala de descanso (o da vueltas por la oficina si no hay) hasta su hora. Devuelve
# true si ya se ocupó del personaje (no hay que hacer lo de siempre).
func _arrive_staggered(character: OfficeCharacter, eating: bool, now: int, hour_start: int,
		used: Dictionary[Vector2i, bool]) -> bool:
	var key: String = character.person_key
	if eating or Staff.is_expected_now(key):
		_early.erase(key)
		character.standing = false
		if eating or character.activity != OfficeCharacter.Activity.AWAY:
			return false
		var late_at: int = hour_start + Staff.get_late_minutes(key)
		if late_at <= now:
			# Entra después de su hora: llega apurado.
			character.hurry = now > hour_start or Staff.get_late_minutes(key) > 0
			return false
		_arrivals[key] = late_at
		character.set_seat(_home_spot(key))
		return true
	# Terminó su jornada: se queda unos minutos antes de irse (sigue como estaba).
	var leave_at: int = hour_start + Staff.get_leave_minutes(key)
	if leave_at > now and character.activity != OfficeCharacter.Activity.AWAY \
			and character.activity != OfficeCharacter.Activity.WALKING_OUT:
		_departures[key] = leave_at
		return true
	var early: int = Staff.get_early_minutes(key)
	if early <= 0:
		_early.erase(key)
		character.standing = false
		return false
	var early_at: int = hour_start + 60 - early
	if early_at > now and character.activity == OfficeCharacter.Activity.AWAY:
		_arrivals[key] = early_at
		return true
	_early[key] = true
	character.standing = true
	character.set_seat(_waiting_spot(key, now, used))
	character.update_routine(true)
	return true


# El CEO llega siempre puntual open_minutes antes de su hora y abre la oficina: va a su
# silla (rinde desde su hora). Devuelve true si ya se ocupó de él.
func _ceo_opens(now: int, hour_start: int) -> bool:
	var early: int = Staff.get_ceo_early_minutes()
	if early <= 0:
		return false
	var open_at: int = hour_start + 60 - early
	if open_at > now:
		if ceo.activity == OfficeCharacter.Activity.AWAY:
			_arrivals["ceo"] = open_at
		return ceo.activity == OfficeCharacter.Activity.AWAY
	ceo.set_seat(_home_spot("ceo"))
	ceo.update_routine(true)
	return true


# Dónde espera quien llegó antes: una casilla libre de la Sala de descanso que funciona o,
# sin ella, una casilla cualquiera de la oficina que cambia cada wander_minutes (da vueltas).
func _waiting_spot(key: String, now: int, used: Dictionary[Vector2i, bool]) -> Vector2i:
	var cells: Array[Vector2i] = []
	var bucket: int = 0
	var room: Dictionary = OfficeState.get_working_room(OfficeState.BREAK_ROOM)
	if not room.is_empty():
		cells.assign(room["cells"])
	else:
		cells.assign(pathfinder.get_reachable(OfficeState.entrance).keys())
		@warning_ignore("integer_division")
		bucket = now / int(StaffCatalog.get_arrivals("wander_minutes"))
	var free: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if cell != OfficeState.entrance and pathfinder.is_walkable(cell):
			free.append(cell)
	if free.is_empty():
		return _home_spot(key)
	return _free_spot_near(free[posmod(hash([key, bucket]), free.size())], used)


# Revisa una vez por minuto de juego si le toca entrar a alguien y, cada wander_minutes,
# mueve a los que dan vueltas esperando su hora.
func _process(_delta: float) -> void:
	if _arrivals.is_empty() and _departures.is_empty() and _early.is_empty() \
			and Staff.appointments.is_empty() and appointment_visitors.is_empty():
		return
	var now: int = get_arrival_minute()
	if now == _last_arrival_check:
		return
	_last_arrival_check = now
	if not Staff.appointments.is_empty() or not appointment_visitors.is_empty():
		_sync_appointments()
	var due: bool = false
	for key: String in _arrivals:
		if _arrivals[key] <= now:
			due = true
	for key: String in _departures:
		if _departures[key] <= now:
			due = true
	var wander: bool = not _early.is_empty() and now % int(StaffCatalog.get_arrivals("wander_minutes")) == 0 \
		and OfficeState.get_working_room(OfficeState.BREAK_ROOM).is_empty()
	if due or wander:
		_update_routines()


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
	# Lugares para comer o descansar ya repartidos: si hay más gente que lugares, cada uno
	# en una casilla distinta (una persona por casilla).
	var used: Dictionary[Vector2i, bool] = {}
	var now: int = get_arrival_minute()
	var hour_start: int = Staff.get_absolute_hour() * 60
	_arrivals.clear()
	_departures.clear()
	for character: OfficeCharacter in get_characters():
		var leaving: bool = character is Employee and _departing.has(character)
		if leaving:
			_early.erase(character.person_key)
			character.update_routine(false)
			continue
		var eating: bool = lunch.has(character.person_key) and not spots.is_empty()
		if character is Employee and _arrive_staggered(character, eating, now, hour_start, used):
			continue
		if character == ceo and _ceo_opens(now, hour_start):
			continue
		if eating:
			character.set_seat(_free_spot_near(spots[next_spot % spots.size()], used))
			next_spot += 1
		elif resting.has(character.person_key) and not rest_spots.is_empty():
			character.set_seat(_free_spot_near(rest_spots[next_rest % rest_spots.size()], used))
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
			return "llegó temprano y espera su hora" if _early.has(character.person_key) else "llegando a su puesto"
		OfficeCharacter.Activity.SEATED:
			if _early.has(character.person_key):
				return "llegó temprano y espera su hora"
			if _departures.has(character.person_key):
				return "terminando antes de irse"
			if String(Staff.interview.get("by", "")) == character.person_key:
				return "entrevistando a %s" % Staff.get_interviewed_now().get("name", "un candidato")
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
	# La silla del CEO puede haber cambiado (Oficina Ejecutiva mudada).
	if ceo != null:
		ceo.set_seat(_home_spot("ceo"))
	for character: OfficeCharacter in get_characters():
		character.replan()
	_sync_visitors()
	if interviewee != null:
		interviewee.set_seat(_interview_spot(String(Staff.interview.get("by", "ceo"))))
		interviewee.standing = Staff.get_guest_chair(String(Staff.interview.get("by", "ceo"))).is_empty()
	for visitor: Visitor in _leaving_visitors:
		visitor.replan()
	_sync_appointments()


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
				# Si su sección o su categoría está cerrada, se resalta la que hay que abrir.
				control = _build_panel.get_button_toward(key.trim_prefix("tool:"))
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
	if hours <= 0:
		return
	# Salta hasta la hora anterior a la próxima llegada y, dentro de ella, hasta el primero
	# que entra antes de la hora en punto; si nadie llega antes, hasta la hora en punto.
	var target: int = Staff.get_absolute_hour() + hours - 1
	if hours > 1:
		GameClock.fast_forward_hours(hours - 1)
		if Staff.get_absolute_hour() != target:
			return  # Un evento cortó el salto.
	_update_routines()
	if _arrivals.is_empty():
		GameClock.fast_forward_hours(1)
		return
	var first: int = _arrivals.values().min()
	GameClock.skip_to_minute(first - target * 60)


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
	# Paredes arriba / abajo: cuadrado, con su descripción emergente.
	var walls := Button.new()
	walls.name = "WallsButton"
	walls.text = "↕"
	walls.tooltip_text = "Paredes arriba / abajo (P)"
	walls.toggle_mode = true
	walls.custom_minimum_size = Vector2(Hud.MENU_BUTTON_SIZE.y, Hud.MENU_BUTTON_SIZE.y)
	walls.focus_mode = Control.FOCUS_NONE
	walls.toggled.connect(func(pressed: bool) -> void: set_walls_up(pressed))
	menu_bar.add_child(walls)


## Sube todas las paredes a su alto (para colgar cosas y ver lo colgado) o las vuelve a bajar
## (se ve el interior). Es solo la vista; no se guarda.
func set_walls_up(up: bool) -> void:
	_walls_wanted = up
	_apply_walls()


## Indica si las paredes están arriba (por el botón o porque se está colgando algo).
func are_walls_up() -> bool:
	return _office_grid.walls_up


# Las paredes van arriba si el jugador lo pidió o si en Construir está elegido un objeto de pared.
func _apply_walls() -> void:
	var hanging: bool = _build_panel.is_build_mode() and FurnitureCatalog.is_wall_mounted(_build_controller.tool)
	var up: bool = _walls_wanted or hanging
	var button: Button = menu_bar_button("WallsButton")
	if button != null:
		button.set_pressed_no_signal(_walls_wanted)
	if up == _office_grid.walls_up:
		return
	_office_grid.walls_up = up
	_rebuild_office()


## Encuadra la oficina completa (botón «Ver oficina» o tecla F), con animación si la
## cámara es suave.
func frame_office() -> void:
	_camera.fit_rect(_office_grid.get_lot_world_rect(), true)


## Un botón de la barra de menús por su nombre.
func menu_bar_button(button_name: String) -> Button:
	return _build_panel.get_menu_bar().get_node_or_null(button_name) as Button


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
# Espacio: pausa · 1 a 5: velocidad 1x, 2x, 4x, 8x, 16x. En modo construcción no cambian
# nada, porque el tiempo tiene que quedarse en pausa. F: ver la oficina completa
# (funciona siempre). P: paredes arriba / abajo. WASD y flechas mueven la cámara (OfficeCamera).
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
	if key.keycode == KEY_P and not _is_camera_locked():
		set_walls_up(not _walls_wanted)
		get_viewport().set_input_as_handled()
		return
	if _is_menu_open():
		return
	match key.keycode:
		KEY_SPACE:
			GameClock.toggle_pause()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			GameClock.set_speed_index(key.keycode - KEY_1)
			EventBus.ui_action.emit("speed_changed")
		_:
			return
	get_viewport().set_input_as_handled()
