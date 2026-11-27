# Partida, capa 2: paneles, pausa, Esc, Ajustes, tutorial, ayuda, avisos y botones de la barra.
extends "res://scripts/game/main_characters.gd"


## Abre el destino de un aviso: ficha, Proyectos en su pestaña, un menú o la cámara en la habitación.
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


# Pliega los objetivos si hay un panel izquierdo abierto.
func _update_objectives_fold() -> void:
	_objectives_panel.set_suppressed(_staff_panel.is_open() or _projects_panel.is_open() or _teams_panel.is_open()
		or _bank_panel.is_open() or _company_panel.is_open())


# Desde la ficha: cierra Personal (tapa el mapa) y empieza a elegir el puesto nuevo en el mapa.
func _start_station_change(employee_id: int) -> void:
	_staff_panel.set_open(false)
	var result: Dictionary = _station_picker.start(employee_id)
	if result["ok"]:
		_employee_card.set_station_picking(true)
	else:
		EventBus.notice.emit(result["message"])


# Con Personal abierto, la ficha empieza donde empiezan sus pestañas (columna derecha de Empleados); si ahí
# no queda alto para leerla, va en su lugar de siempre.
func _place_card_in_staff() -> void:
	if not _staff_panel.is_open():
		return
	var top: float = _staff_panel.get_body_top()
	var room: float = UiLayout.available_height(_staff_panel.get_viewport().get_visible_rect().size, top)
	_employee_card.set_top(top if room >= MIN_CARD_ROOM else -1.0)


# Cierra los paneles izquierdos menos uno (null: todos).
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


# Construcción pausa el tiempo (si la opción lo pide) y al salir lo deja como estaba.
func _on_build_mode_changed(active: bool) -> void:
	if active:
		_close_side_panels(null)
		_station_picker.cancel()
		EventBus.ui_action.emit("build_opened")
	_build_controller.set_active(active)
	_hud.set_controls_enabled(not active)
	_office_grid.set_rooms_visible(active)
	_camera.left_drag_enabled = not active
	# En pausa los personajes no se mueven: sus casillas quedan reservadas.
	var occupied: Array[Vector2i] = []
	for character: OfficeCharacter in get_characters():
		if active and character.visible:
			occupied.append(character.get_cell())
	_build_controller.builder.occupied_cells = occupied
	# Se recuerda si pausó al entrar para devolver el tiempo como estaba.
	if active:
		_build_paused = bool(Settings.get_value("pause_on_build"))
	if _build_paused:
		_set_menu_pause(active)


## Rectángulo en pantalla de lo que resalta el tutorial (claves de tutorial.json), o Rect2().
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
			# En otra pestaña se resalta Vacantes.
			return _staff_panel.get_publish_target_rect() if _staff_panel.is_open() else Rect2()
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
				# Con su sección o categoría cerrada, se resalta la que hay que abrir.
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


## Abre o cierra el menú de pausa: cierra paneles, oculta la barra y detiene el tiempo; al cerrar
## el tiempo vuelve a como estaba.
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


# Guardar, Cargar o Ajustes desde la pausa: la pausa devuelve el tiempo y Ajustes lo pausa
# por su cuenta (se guarda con la pausa de antes del menú).
func _open_settings_from_pause(tab: String) -> void:
	set_pause_menu_open(false)
	_settings_from_pause = true
	_settings_panel.set_open(true)
	_settings_panel.set_tab(tab)


## Esc: cierra lo abierto, de lo más reciente a lo más general (ayuda, pregunta, Ajustes, pausa,
## construcción, ficha, panel izquierdo); sin nada abre la pausa. Devuelve qué hizo.
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
	if _build_panel.is_shop_open():
		_build_panel.set_shop_open(false)
		return "shop"
	if _station_picker.is_active():
		_station_picker.cancel()
		return "station"
	if _build_panel.is_build_mode():
		if _build_controller.is_moving():
			_build_controller.cancel_move()
			return "move"
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


# Un menú que pausa detiene el tiempo; al cerrarlo vuelve a como estaba.
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
	# Se guarda con la pausa de antes de abrir Ajustes.
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


# Salida a bolsa: corta el salto, pausa, cierra menús y abre la pantalla; «Seguir jugando» vuelve.
func _on_went_public(stats: Dictionary) -> void:
	GameClock.interrupt()
	if not _ipo_screen.is_open():
		_was_paused_before_ipo = GameClock.is_paused
	GameClock.set_paused(true)
	_close_side_panels(null)
	_employee_card.close()
	_ipo_screen.show_stats(stats)


# Préstamo de emergencia: corta el salto, pausa y pregunta.
func _on_emergency_loan_offered(offer: Dictionary) -> void:
	# Otro oyente pudo haberla respondido ya.
	if Bank.emergency_offer.is_empty():
		return
	GameClock.interrupt()
	if not _emergency_dialog.is_open():
		_was_paused_before_emergency = GameClock.is_paused
	GameClock.set_paused(true)
	_employee_card.close()
	_emergency_dialog.show_offer(offer)


# Respondida la oferta, el tiempo vuelve a como estaba y sigue el salto si la oficina está vacía.
func _on_emergency_dialog_closed() -> void:
	GameClock.set_paused(_was_paused_before_emergency)
	_on_character_left_office()


func _on_quit_requested() -> void:
	get_tree().change_scene_to_file(MENU_SCENE_PATH)


# Cargar desde Ajustes (ya confirmado): reabre la escena con la ranura; si no sirve, sigue igual.
func _on_load_requested(slot: String) -> void:
	if SaveManager.load_game(slot):
		get_tree().change_scene_to_file(scene_file_path)
	else:
		_settings_panel.show_status("No se pudo cargar la %s." % SaveManager.get_slot_name(slot).to_lower())


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		on_focus_lost()


## Al perder el foco pausa si la opción lo pide; sigue en pausa hasta que el jugador la quite.
func on_focus_lost() -> void:
	if not bool(Settings.get_value("pause_on_focus_loss")):
		return
	if _is_menu_open():
		# Con un menú que pausa abierto, no debe volver a correr solo al cerrarlo.
		_was_paused_before_menu = true
	if _pause_menu.is_open():
		_was_paused_before_pause = true
	GameClock.set_paused(true)


# Botones del reloj; en construcción se desactivan (tiempo en pausa).
func _on_pause_pressed() -> void:
	if not _is_menu_open():
		GameClock.toggle_pause()


# Botón «Ver oficina»: encuadra la oficina completa.
func _add_frame_button(menu_bar: Container) -> void:
	var button := Button.new()
	button.name = "FrameOfficeButton"
	button.text = "Ver oficina"
	Hud.style_bar_button(button, "frame")
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(frame_office)
	menu_bar.add_child(button)


## Sube las paredes a su alto o las baja para ver el interior. Solo la vista; no se guarda.
func set_walls_up(up: bool) -> void:
	_walls_wanted = up
	_apply_walls()


## Indica si las paredes están arriba (por el botón o por colgar algo).
func are_walls_up() -> bool:
	return _office_grid.walls_up


# Arriba si el jugador lo pidió o si en Construir hay un objeto de pared elegido.
func _apply_walls() -> void:
	var hanging: bool = _build_panel.is_build_mode() and (FurnitureCatalog.is_wall_mounted(_build_controller.tool)
		or _build_controller.is_moving_wall_item())
	var up: bool = _walls_wanted or hanging
	_build_panel.get_walls_button().set_pressed_no_signal(_walls_wanted)
	if up == _office_grid.walls_up:
		return
	_office_grid.walls_up = up
	_rebuild_office()


## Encuadra la oficina completa (botón o tecla F), animada si la cámara es suave.
func frame_office() -> void:
	_camera.fit_rect(_office_grid.get_lot_world_rect(), true)


## Un botón de la barra de menús por su nombre.
func menu_bar_button(button_name: String) -> Button:
	return _build_panel.get_menu_bar().get_node_or_null(button_name) as Button


# Teclado y borde de pantalla no mueven la cámara con un menú encima (construcción sí).
func _is_camera_locked() -> bool:
	return (_settings_panel.is_open() or _game_over_screen.is_open() or _emergency_dialog.is_open()
		or _ipo_screen.is_open() or _pause_menu.is_open())


func _on_speed_pressed(index: int) -> void:
	if not _is_menu_open():
		GameClock.set_speed_index(index)
		EventBus.ui_action.emit("speed_changed")
