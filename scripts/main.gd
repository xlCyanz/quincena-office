# Escena de juego: reúne oficina, cámara, personajes, modo construcción e interfaz.
# Cada hora les dice a los personajes si les toca estar (Staff.is_expected); con la oficina
# vacía el tiempo salta a la próxima llegada. Los clientes en espera no cuentan.
extends "res://scripts/game/main_menus.gd"


func _ready() -> void:
	var game_name: String = ProjectSettings.get_setting("application/config/name")
	var godot_version: String = Engine.get_version_info().string
	print("%s — Godot %s" % [game_name, godot_version])
	# Abierta sin pasar por el menú (Cmd+R en el editor): partida nueva.
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
	_build_panel.walls_toggled.connect(set_walls_up)
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
	# Paneles del lado izquierdo: abrir uno cierra los otros.
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
	# Un evento corta el salto de horas para que el jugador lo vea.
	EventBus.event_started.connect(func(_card: Dictionary) -> void: GameClock.interrupt())
	GameClock.start()
	# Préstamo de emergencia guardado sin responder: vuelve a preguntar.
	if not Bank.emergency_offer.is_empty():
		_on_emergency_loan_offered(Bank.emergency_offer)


func _exit_tree() -> void:
	GameClock.stop()
	SaveManager.scene_state_provider = Callable()


# Estado de la escena (el resto vive en los autoloads).
func _export_scene_state() -> Dictionary:
	var saved_employees: Dictionary = {}
	for employee_id: int in employees:
		saved_employees[str(employee_id)] = employees[employee_id].export_state()
	return {"camera": _camera.export_state(), "ceo": ceo.export_state(), "employees": saved_employees}


# Restaura cámara y personajes; con la oficina vacía salta a la próxima llegada.
func _restore_scene_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	# La vista ya no se gira: una partida con vista girada encuadra la oficina.
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


# Cada minuto de juego revisa quién entra; cada wander_minutes mueve a los que dan vueltas y cada
# mop_minutes a la limpieza.
func _process(_delta: float) -> void:
	if _arrivals.is_empty() and _departures.is_empty() and _early.is_empty() and not _cleaners_on_duty \
			and _cleaning_starts.is_empty() \
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
	for key: String in _cleaning_starts:
		if _cleaning_starts[key] <= now:
			due = true
	var wander: bool = not _early.is_empty() and now % int(StaffCatalog.get_arrivals("wander_minutes")) == 0 \
		and OfficeState.get_working_room(OfficeState.BREAK_ROOM).is_empty()
	# La limpieza trapea por partes: cada mop_minutes pasa a otra casilla.
	var mop: bool = _cleaners_on_duty and now % maxi(1, int(StaffCatalog.get_cleaning("mop_minutes"))) == 0
	if due or wander or mop:
		_update_routines()


func _on_office_changed() -> void:
	_rebuild_office()
	# La silla del CEO puede haber cambiado (oficina mudada).
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


# Un clic sin arrastrar sobre un empleado abre su ficha.
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


# Atajos (extra): Esc cierra o abre la pausa; Espacio pausa; 1–5 velocidad (no en construcción);
# F ver la oficina; P paredes; WASD y flechas mueven la cámara (OfficeCamera).
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
