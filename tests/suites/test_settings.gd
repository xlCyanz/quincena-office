# Opciones y Ajustes: una opción cambiada se aplica y sigue al reiniciar; un archivo roto vuelve
# a los valores por defecto; cargar desde la partida pide confirmación y carga la ranura.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=settings
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TEST_SAVE_DIR: String = "user://test_saves"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	SaveManager.save_dir = TEST_SAVE_DIR
	_expect(Settings.path != "user://settings.cfg", "las pruebas no usan el archivo del jugador: %s" % Settings.path)
	_check_defaults()
	_check_persist()
	_check_invalid()
	_check_broken_file()
	await _check_effects()
	await _check_panel()
	await _check_load_and_quit()
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


func _check_defaults() -> void:
	Settings.reset_to_defaults()
	var defaults: Dictionary = Settings.get_defaults()
	for key: String in ["fullscreen", "autosave", "start_speed", "pause_on_build", "pause_on_focus_loss"]:
		_expect(defaults.has(key), "opción %s en data/settings.json" % key)
	_expect(not bool(Settings.get_value("fullscreen")) and bool(Settings.get_value("autosave")) and int(Settings.get_value("start_speed")) == 0
		and bool(Settings.get_value("pause_on_build")) and bool(Settings.get_value("pause_on_focus_loss")), "valores por defecto")


# Al leer el archivo de nuevo (como al reiniciar) sigue igual.
func _check_persist() -> void:
	Settings.reset_to_defaults()
	var changes: Array[String] = []
	EventBus.settings_changed.connect(func(key: String) -> void: changes.append(key))
	_expect(Settings.set_value("autosave", false) and Settings.set_value("start_speed", 2) and Settings.set_value("fullscreen", true),
		"cambiar opciones")
	_expect(changes == ["autosave", "start_speed", "fullscreen"], "avisa cada cambio: %s" % [changes])
	var config := ConfigFile.new()
	_expect(config.load(Settings.path) == OK and config.get_value(Settings.SECTION, "start_speed") == 2
		and config.get_value(Settings.SECTION, "autosave") == false, "se escribe en el archivo")
	Settings.set("_values", {})
	Settings.load_settings()
	_expect(not bool(Settings.get_value("autosave")) and int(Settings.get_value("start_speed")) == 2 and bool(Settings.get_value("fullscreen")),
		"al reiniciar siguen igual")
	Settings.reset_to_defaults()
	Settings.load_settings()
	_expect(bool(Settings.get_value("autosave")) and int(Settings.get_value("start_speed")) == 0, "valores por defecto otra vez")


func _check_invalid() -> void:
	Settings.reset_to_defaults()
	_expect(not Settings.set_value("start_speed", GameConstants.CLOCK_SPEEDS.size()), "velocidad que no existe")
	_expect(not Settings.set_value("start_speed", -1) and not Settings.set_value("start_speed", 1.5), "velocidad negativa o con decimales")
	_expect(not Settings.set_value("autosave", "no"), "texto en una opción de sí o no")
	_expect(not Settings.set_value("volumen", 3), "opción que no existe")
	_expect(Settings.set_value("start_speed", 1.0) and Settings.get_value("start_speed") is int, "un número entero en decimal sirve y queda entero")
	_expect(int(Settings.get_value("start_speed")) == 1 and bool(Settings.get_value("autosave")), "lo que no sirve no cambia nada")
	Settings.reset_to_defaults()


func _check_broken_file() -> void:
	Settings.set_value("autosave", false)
	var file := FileAccess.open(Settings.path, FileAccess.WRITE)
	file.store_string("esto no es un archivo de opciones [[[")
	file.close()
	Settings.load_settings()
	_expect(bool(Settings.get_value("autosave")) and int(Settings.get_value("start_speed")) == 0, "archivo roto: valores por defecto")
	var config := ConfigFile.new()
	config.set_value(Settings.SECTION, "start_speed", 7)
	config.set_value(Settings.SECTION, "autosave", "quizás")
	config.set_value(Settings.SECTION, "pause_on_build", false)
	config.save(Settings.path)
	Settings.load_settings()
	_expect(int(Settings.get_value("start_speed")) == 0 and bool(Settings.get_value("autosave")) and not bool(Settings.get_value("pause_on_build")),
		"un valor que no sirve vuelve al suyo y los demás quedan")
	DirAccess.remove_absolute(Settings.path)
	Settings.load_settings()
	_expect(bool(Settings.get_value("pause_on_build")), "sin archivo: valores por defecto")
	Settings.reset_to_defaults()


func _check_effects() -> void:
	_clear_saves()
	Settings.set_value("start_speed", 2)
	SaveManager.new_game()
	_expect(GameClock.speed_index == 2 and not GameClock.is_paused, "una partida nueva empieza a 4x")
	Settings.set_value("start_speed", 0)
	SaveManager.new_game()
	_expect(GameClock.speed_index == 0, "y a 1x con la opción por defecto")
	var game: Node = await _open_game()
	Settings.set_value("autosave", false)
	GameClock.fast_forward_hours(24)
	_expect(not SaveManager.has_save(SaveManager.AUTOSAVE), "sin autoguardado no se guarda al empezar el día")
	Settings.set_value("autosave", true)
	GameClock.fast_forward_hours(24)
	_expect(SaveManager.has_save(SaveManager.AUTOSAVE), "con autoguardado sí")
	var build: BuildPanel = game.get_node("BuildPanel")
	GameClock.set_paused(false)
	build.set_build_mode(true)
	_expect(GameClock.is_paused, "construir pausa")
	build.set_build_mode(false)
	_expect(not GameClock.is_paused, "al salir vuelve el tiempo")
	Settings.set_value("pause_on_build", false)
	build.set_build_mode(true)
	_expect(not GameClock.is_paused, "sin la opción construir no pausa")
	build.set_build_mode(false)
	_expect(not GameClock.is_paused, "y al salir sigue corriendo")
	GameClock.set_paused(true)
	build.set_build_mode(true)
	build.set_build_mode(false)
	_expect(GameClock.is_paused, "sin la opción tampoco quita una pausa del jugador")
	Settings.set_value("pause_on_build", true)
	GameClock.set_paused(false)
	game.on_focus_lost()
	_expect(GameClock.is_paused, "al perder el foco se pausa")
	GameClock.set_paused(false)
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_expect(GameClock.is_paused, "con la notificación de la ventana también")
	# Con Ajustes abierto, al cerrarlo sigue en pausa.
	var settings: SettingsPanel = game.get_node("SettingsPanel")
	GameClock.set_paused(false)
	settings.set_open(true)
	game.on_focus_lost()
	settings.set_open(false)
	_expect(GameClock.is_paused, "perder el foco con un menú abierto deja la pausa al cerrarlo")
	Settings.set_value("pause_on_focus_loss", false)
	GameClock.set_paused(false)
	game.on_focus_lost()
	_expect(not GameClock.is_paused, "sin la opción no se pausa")
	Settings.reset_to_defaults()
	await _close_game(game)


func _check_panel() -> void:
	Settings.reset_to_defaults()
	_clear_saves()
	SaveManager.new_game()
	var game: Node = await _open_game()
	var settings: SettingsPanel = game.get_node("SettingsPanel")
	await _click(settings.get_open_button())
	_expect(settings.is_open() and settings.get_tab() == SettingsPanel.TAB_SAVE, "abre en Guardar")
	await _click(settings.get_tab_button(SettingsPanel.TAB_OPTIONS))
	_expect(settings.get_tab() == SettingsPanel.TAB_OPTIONS and settings.get_option_toggle("autosave").is_visible_in_tree()
		and not settings.get_slot_button("slot_1").is_visible_in_tree(), "pestaña Opciones")
	_expect(settings.get_option_toggle("autosave").button_pressed and not settings.get_option_toggle("fullscreen").button_pressed,
		"los controles muestran las opciones")
	await _click(settings.get_option_toggle("pause_on_build"))
	_expect(not bool(Settings.get_value("pause_on_build")), "un clic cambia la opción")
	settings.get_speed_button().select(1)
	settings.get_speed_button().item_selected.emit(1)
	_expect(int(Settings.get_value("start_speed")) == 1, "elegir la velocidad inicial")
	Settings.reset_to_defaults()
	_expect(settings.get_option_toggle("pause_on_build").button_pressed and settings.get_speed_button().selected == 0,
		"los controles siguen a las opciones")
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for tab: String in SettingsPanel.TAB_NAMES:
		settings.set_tab(tab)
		await get_tree().process_frame
		_expect(screen.encloses(settings.get_panel_rect()) and settings.get_panel_rect().size.y < screen.size.y * 0.8,
			"la pestaña %s cabe en la pantalla: %s" % [tab, settings.get_panel_rect()])
	await _click(settings.get_tab_button(SettingsPanel.TAB_LOAD))
	_expect(settings.get_load_button(SaveManager.AUTOSAVE).disabled and settings.get_load_button("slot_1").disabled,
		"sin partidas guardadas no se puede cargar")
	await _close_game(game)


func _check_load_and_quit() -> void:
	Settings.reset_to_defaults()
	_clear_saves()
	SaveManager.new_game()
	var game: Node = await _open_game()
	var settings: SettingsPanel = game.get_node("SettingsPanel")
	# La escena cambiaría al cargar o salir: la prueba escucha en su lugar.
	settings.load_requested.disconnect(game._on_load_requested)
	settings.quit_requested.disconnect(game._on_quit_requested)
	var loads: Array[String] = []
	var quits: Array[bool] = []
	settings.load_requested.connect(func(slot: String) -> void: loads.append(slot))
	settings.quit_requested.connect(func() -> void: quits.append(true))
	Economy.earn(1234, "Prueba")
	var saved_balance: int = Economy.balance
	await _click(settings.get_open_button())
	await _click(settings.get_slot_button("slot_1"))
	_expect(SaveManager.has_save("slot_1"), "guardar en la ranura 1")
	Economy.earn(5000, "Prueba")
	await _click(settings.get_tab_button(SettingsPanel.TAB_LOAD))
	var load_button: Button = settings.get_load_button("slot_1")
	_expect(not load_button.disabled and load_button.text.begins_with("Ranura 1 —"), "la ranura 1 se puede cargar: %s" % load_button.text)
	await _click(load_button)
	_expect(settings.is_confirming() and loads.is_empty(), "cargar pide confirmación")
	_expect(settings.get_confirm_text().contains("ranura 1") and settings.get_confirm_text().contains("se pierde"),
		"y avisa: %s" % settings.get_confirm_text())
	await _click(settings.get_cancel_button())
	_expect(not settings.is_confirming() and loads.is_empty() and settings.get_load_button("slot_1").is_visible_in_tree(), "cancelar no carga")
	await _click(load_button)
	await _click(settings.get_confirm_button())
	_expect(loads == ["slot_1"] and not settings.is_confirming(), "confirmar pide cargar la ranura 1")
	await _click(settings.get_quit_button())
	_expect(settings.is_confirming() and quits.is_empty(), "salir pide confirmación")
	await _click(settings.get_confirm_button())
	_expect(quits.size() == 1, "confirmar sale")
	# Lo que hace la escena al cargar, sin cambiar de escena aquí.
	_expect(SaveManager.load_game(loads[0]) and Economy.balance == saved_balance, "se carga lo guardado: %d" % Economy.balance)
	game._on_load_requested("slot_3")
	_expect(game.is_inside_tree() and Economy.balance == saved_balance, "una ranura vacía no cambia nada")
	await _close_game(game)
	_clear_saves()
