# Menú de pausa: Esc cierra el panel abierto o, sin ninguno, abre la pausa y detiene el reloj;
# Seguir lo deja como estaba; Guardar, Cargar y Ajustes abren Ajustes y vuelven a la pausa; salir pregunta.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=pause_menu
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TEST_SAVE_DIR: String = "user://test_saves"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	SaveManager.save_dir = TEST_SAVE_DIR
	Settings.reset_to_defaults()
	_clear_saves()
	SaveManager.new_game()
	var game: Node = await _open_game()
	await _check_open_and_resume(game)
	await _check_panels_first(game)
	await _check_settings_from_pause(game)
	await _check_quit(game)
	_check_blocking_screens(game)
	await _close_game(game)
	await _check_employee_card()
	_clear_saves()
	Settings.reset_to_defaults()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _clear_saves() -> void:
	var dir := DirAccess.open(TEST_SAVE_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame


func _escape() -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
		key.pressed = pressed
		await _push(key)


func _click(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	await _push(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _push(event)


func _open_game() -> Node:
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameClock.stop()
	return game


func _close_game(game: Node) -> void:
	game.queue_free()
	await get_tree().process_frame


func _check_open_and_resume(game: Node) -> void:
	var pause: PauseMenu = game.get_pause_menu()
	var hud: Hud = game.get_node("Hud")
	var menu_bar: Control = game.get_node("BuildPanel").get_menu_bar()
	_expect(not pause.is_open(), "la partida empieza sin la pausa")
	GameClock.set_paused(false)
	GameClock.set_speed_index(1)
	await _escape()
	_expect(pause.is_open() and GameClock.is_paused, "sin panel, Esc abre la pausa y detiene el reloj")
	_expect(not menu_bar.visible and hud.get_pause_button().disabled, "la pausa oculta la barra y apaga el reloj del Hud")
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_expect(screen.encloses(pause.get_panel_rect()), "la pausa cabe en la pantalla: %s" % pause.get_panel_rect())
	for key: String in ["resume", "save", "load", "settings", "quit"]:
		_expect(pause.get_button(key).is_visible_in_tree() and pause.get_button(key).size.y >= 44.0,
			"botón %s visible y de 44 px" % key)
	await _click(pause.get_button("resume"))
	_expect(not pause.is_open() and not GameClock.is_paused and GameClock.speed_index == 1,
		"Seguir vuelve a como estaba (corriendo a 2x)")
	_expect(menu_bar.visible and not hud.get_pause_button().disabled, "y vuelven la barra y el reloj")
	GameClock.set_paused(true)
	await _escape()
	_expect(pause.is_open(), "Esc abre la pausa con el reloj ya en pausa")
	await _escape()
	_expect(not pause.is_open() and GameClock.is_paused, "Esc en la pausa la cierra y sigue la pausa del jugador")
	# Perder el foco con la pausa abierta: al seguir no vuelve a correr solo.
	Settings.set_value("pause_on_focus_loss", true)
	GameClock.set_paused(false)
	await _escape()
	game.on_focus_lost()
	await _click(pause.get_button("resume"))
	_expect(GameClock.is_paused, "perder el foco en la pausa deja el reloj en pausa al seguir")
	Settings.reset_to_defaults()
	GameClock.set_paused(false)
	await _escape()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	await _push(space)
	_expect(GameClock.is_paused and pause.is_open(), "Espacio no quita la pausa del menú")
	await _escape()
	_expect(not GameClock.is_paused, "y al seguir corre otra vez")
	GameClock.set_speed_index(0)


func _check_panels_first(game: Node) -> void:
	var pause: PauseMenu = game.get_pause_menu()
	GameClock.set_paused(false)
	for name: String in ["StaffPanel", "ProjectsPanel", "TeamsPanel", "BankPanel", "CompanyPanel"]:
		var panel: CanvasLayer = game.get_node(name)
		panel.call("set_open", true)
		await _escape()
		_expect(not bool(panel.call("is_open")) and not pause.is_open() and not GameClock.is_paused,
			"con %s abierto Esc lo cierra sin pausar" % name)
	var build: BuildPanel = game.get_node("BuildPanel")
	build.set_build_mode(true)
	_expect(GameClock.is_paused, "construir pausa")
	await _escape()
	_expect(not build.is_build_mode() and not pause.is_open() and not GameClock.is_paused,
		"Esc sale del modo construcción y el tiempo vuelve")
	var settings: SettingsPanel = game.get_node("SettingsPanel")
	settings.set_open(true)
	await get_tree().process_frame
	await _click(settings.get_quit_button())
	_expect(settings.is_confirming(), "Ajustes pregunta antes de salir")
	await _escape()
	_expect(settings.is_open() and not settings.is_confirming(), "Esc cancela la pregunta de Ajustes")
	await _escape()
	_expect(not settings.is_open() and not pause.is_open() and not GameClock.is_paused,
		"Esc cierra Ajustes (abierto con su botón) sin abrir la pausa")
	game.get_node("BankPanel").call("set_open", true)
	game.set_pause_menu_open(true)
	_expect(not bool(game.get_node("BankPanel").call("is_open")), "abrir la pausa cierra los paneles")
	game.set_pause_menu_open(false)


func _check_settings_from_pause(game: Node) -> void:
	var pause: PauseMenu = game.get_pause_menu()
	var settings: SettingsPanel = game.get_node("SettingsPanel")
	var expected_tabs: Dictionary[String, String] = {
		"save": SettingsPanel.TAB_SAVE, "load": SettingsPanel.TAB_LOAD, "settings": SettingsPanel.TAB_OPTIONS}
	GameClock.set_paused(false)
	for key: String in expected_tabs:
		await _escape()
		await _click(pause.get_button(key))
		_expect(settings.is_open() and settings.get_tab() == expected_tabs[key] and not pause.is_open(),
			"%s abre Ajustes en la pestaña %s" % [key, expected_tabs[key]])
		_expect(GameClock.is_paused, "con Ajustes abierto desde la pausa el tiempo sigue detenido")
		await _escape()
		_expect(not settings.is_open() and pause.is_open() and GameClock.is_paused, "al cerrar Ajustes se vuelve a la pausa")
		await _click(pause.get_button("resume"))
		_expect(not GameClock.is_paused, "y Seguir vuelve al reloj corriendo")
	# Guardar desde la pausa guarda el reloj como estaba antes de ella.
	await _escape()
	await _click(pause.get_button("save"))
	await _click(settings.get_slot_button("slot_1"))
	var file := FileAccess.open(TEST_SAVE_DIR.path_join("slot_1.json"), FileAccess.READ)
	var data: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	var clock: Dictionary = data.get("clock", {}) if data is Dictionary else {}
	_expect(SaveManager.has_save("slot_1") and clock.has("is_paused") and not bool(clock["is_paused"]),
		"guardar desde la pausa guarda el reloj corriendo: %s" % clock)
	await _click(settings.get_close_button())
	_expect(pause.is_open() and GameClock.is_paused, "Cerrar en Ajustes vuelve a la pausa")
	await _escape()
	_expect(not pause.is_open() and not GameClock.is_paused, "Esc sigue la partida")


func _check_quit(game: Node) -> void:
	var pause: PauseMenu = game.get_pause_menu()
	pause.quit_requested.disconnect(game._on_quit_requested)
	var quits: Array[bool] = []
	pause.quit_requested.connect(func() -> void: quits.append(true))
	await _escape()
	await _click(pause.get_button("quit"))
	_expect(pause.is_confirming() and quits.is_empty() and pause.get_cancel_button().is_visible_in_tree(),
		"Salir al menú pregunta antes")
	await _escape()
	_expect(pause.is_open() and not pause.is_confirming() and quits.is_empty(), "Esc cancela la pregunta y queda la pausa")
	await _click(pause.get_button("quit"))
	await _click(pause.get_cancel_button())
	_expect(pause.is_open() and not pause.is_confirming() and quits.is_empty(), "Cancelar vuelve a los botones")
	await _click(pause.get_button("quit"))
	await _click(pause.get_confirm_button())
	_expect(quits.size() == 1, "confirmar sale al menú")
	game.set_pause_menu_open(false)
	pause.quit_requested.connect(game._on_quit_requested)


func _check_blocking_screens(game: Node) -> void:
	var game_over: GameOverScreen = game.get_node("GameOverScreen")
	game_over.show_stats({})
	_expect(game.handle_escape() == "none" and not game.is_pause_menu_open(), "con la pantalla de fin Esc no hace nada")


func _check_employee_card() -> void:
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	SaveManager.start_with_demo = false
	var game: Node = await _open_game()
	var card: EmployeeCard = game.get_node("EmployeeCard")
	var staff_panel: CanvasLayer = game.get_node("StaffPanel")
	staff_panel.call("set_open", true)
	card.open_employee(Staff.employees[0]["id"])
	_expect(card.is_open(), "la ficha se abre")
	await _escape()
	_expect(not card.is_open() and bool(staff_panel.call("is_open")) and not game.is_pause_menu_open(),
		"Esc cierra primero la ficha y deja Personal")
	await _escape()
	_expect(not bool(staff_panel.call("is_open")) and not game.is_pause_menu_open(), "después Personal")
	await _escape()
	_expect(game.is_pause_menu_open(), "y después abre la pausa")
	game.set_pause_menu_open(false)
	card.open_employee(Staff.employees[0]["id"])
	game.set_pause_menu_open(true)
	_expect(not card.is_open(), "abrir la pausa cierra la ficha")
	await _close_game(game)
