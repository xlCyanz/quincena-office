# Prueba del hito 9: autoguardado al final de cada día, guardado manual en
# 5 ranuras y carga desde el menú. Criterio: tras guardar, cerrar y cargar, la oficina,
# el dinero y la fecha son idénticos.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=save
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const TEST_SAVE_DIR: String = "user://test_saves"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	SaveManager.save_dir = TEST_SAVE_DIR
	_clear_saves()
	_check_round_trip()
	_check_bad_files()
	await _check_autosave_in_game()
	await _check_settings_and_reload()
	await _check_menu()
	_clear_saves()

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


# Todo lo que tiene que quedar idéntico: oficina, dinero (con sus movimientos) y fecha.
func _snapshot() -> String:
	return JSON.stringify({"office": OfficeState.export_state(), "economy": Economy.export_state(),
		"clock": GameClock.export_state()})


# Una partida con cambios en todo: paredes, piso, muebles, habitación, dinero y fecha.
func _play_a_while() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	builder.apply([{"edge": Vector3i(1, 6, GridEdge.AXIS_X), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(1, 7, GridEdge.AXIS_X), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(0, 5, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(1, 5, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL}])
	builder.apply([{"cell": Vector2i(4, 4), "kind": "carpet"}])
	builder.place("simple_desk", Vector2i(4, 4), 1)
	builder.install_computer("basic_computer", Vector2i(4, 4))
	builder.place("basic_chair", Vector2i(3, 4), 1)
	builder.mark_room("reception", OfficeState.entrance)
	builder.mark_room("bathroom", Vector2i(0, 7))
	GameClock.fast_forward_hours(24 * 31 + 5)  # mes 2, con el mantenimiento cobrado
	GameClock.advance(2.5)
	GameClock.set_speed_index(2)


func _check_round_trip() -> void:
	_play_a_while()
	var before: String = _snapshot()
	_expect(SaveManager.save_game("slot_3"), "guardar en la ranura 3")
	_expect(SaveManager.has_save("slot_3") and not SaveManager.has_save("slot_1"), "solo existe la ranura 3")
	var summary: Dictionary = SaveManager.get_summary("slot_3")
	_expect(summary["month"] == 2 and summary["day"] == 2 and summary["hour"] == 13 and summary["balance"] == Economy.balance,
		"resumen de la ranura: %s" % [summary])
	_expect(SaveManager.describe_slot("slot_3").begins_with("Ranura 3 — Mes 2, día 2, 13:00 · $"),
		"texto de la ranura: %s" % SaveManager.describe_slot("slot_3"))
	_expect(SaveManager.describe_slot("slot_1") == "Ranura 1 — vacía", "ranura vacía: %s" % SaveManager.describe_slot("slot_1"))

	# "Cerrar": se borra todo con una partida nueva; luego se carga.
	SaveManager.new_game()
	_expect(_snapshot() != before, "la partida nueva debería ser distinta")
	_expect(SaveManager.load_game("slot_3"), "cargar la ranura 3")
	_expect(_snapshot() == before, "tras cargar, la oficina, el dinero y la fecha no son idénticos")
	_expect(Economy.movements.size() > 5 and GameClock.get_time_scale() == 4.0, "movimientos y velocidad restaurados")


func _check_bad_files() -> void:
	_expect(not SaveManager.load_game("slot_5"), "cargar una ranura vacía")
	var file := FileAccess.open(TEST_SAVE_DIR.path_join("slot_4.json"), FileAccess.WRITE)
	file.store_string("{esto no es json")
	file.close()
	var before: String = _snapshot()
	_expect(not SaveManager.load_game("slot_4") and _snapshot() == before, "un archivo dañado no cambia nada")
	file = FileAccess.open(TEST_SAVE_DIR.path_join("slot_4.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 999}))
	file.close()
	_expect(not SaveManager.load_game("slot_4") and SaveManager.get_summary("slot_4").is_empty(),
		"un archivo de otra versión no se carga")
	DirAccess.remove_absolute(TEST_SAVE_DIR.path_join("slot_4.json"))


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


func _check_autosave_in_game() -> void:
	_clear_saves()
	SaveManager.new_game()
	# Sin escena de juego abierta no se autoguarda (por ejemplo, en el menú).
	GameClock.fast_forward_hours(24)
	_expect(not SaveManager.has_save(SaveManager.AUTOSAVE), "se autoguardó sin partida abierta")
	SaveManager.new_game()
	var game: Node = await _open_game()
	GameClock.fast_forward_hours(15)  # hasta las 23:00 del día 1
	_expect(not SaveManager.has_save(SaveManager.AUTOSAVE), "se autoguardó antes de terminar el día")
	GameClock.fast_forward_hours(1)
	var summary: Dictionary = SaveManager.get_summary(SaveManager.AUTOSAVE)
	_expect(summary.get("day") == 2 and summary.get("hour") == 0, "autoguardado al terminar el día 1: %s" % [summary])
	# El del día 1 del mes 2 ya incluye el mantenimiento.
	GameClock.fast_forward_hours(24 * 29)
	summary = SaveManager.get_summary(SaveManager.AUTOSAVE)
	_expect(summary.get("month") == 2 and summary.get("day") == 1 and summary.get("balance") == 20000 - 240,
		"autoguardado del día 1 del mes 2: %s" % [summary])
	await _close_game(game)


func _check_settings_and_reload() -> void:
	_clear_saves()
	_play_a_while()
	GameClock.fast_forward_hours(24 - GameClock.get_hour() + 10)  # 10:00, el CEO trabajando
	var game: Node = await _open_game()
	var panel: BuildPanel = game.get_node("BuildPanel")
	var settings: SettingsPanel = game.get_node("SettingsPanel")
	var camera: OfficeCamera = game.get_node("OfficeCamera")
	_expect(settings.get_open_button().get_parent() == panel.get_menu_bar(), "Ajustes va en la barra de menús")

	camera.set_zoom_index(2, Vector2(400, 300))
	for i: int in range(120):
		game.ceo._process(0.1)
	var ceo_state: Dictionary = game.ceo.export_state()
	var camera_state: Dictionary = camera.export_state()

	await _click(settings.get_open_button())
	_expect(settings.is_open() and GameClock.is_paused and not panel.get_menu_bar().visible,
		"Ajustes abierto pausa el tiempo")
	_expect(settings.get_slot_button("slot_2").text == "Ranura 2 — vacía", "ranura 2 vacía al abrir")
	var before: String = _snapshot()
	await _click(settings.get_slot_button("slot_2"))
	_expect(SaveManager.has_save("slot_2") and settings.get_slot_button("slot_2").text.begins_with("Ranura 2 — Mes 2"),
		"guardar en la ranura 2 con el ratón: %s" % settings.get_slot_button("slot_2").text)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE_DIR.path_join("slot_2.json")))
	_expect(not bool(saved["clock"]["is_paused"]), "se guardó la pausa de Ajustes en vez de la del jugador")
	await _click(settings.get_close_button())
	_expect(not settings.is_open() and not GameClock.is_paused and panel.get_menu_bar().visible,
		"al cerrar Ajustes vuelve el tiempo")
	await _close_game(game)

	# Cerrar y cargar: la oficina, el dinero, la fecha, la cámara y el CEO, iguales.
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_2"), "cargar la ranura 2")
	# Se guardó sin la pausa de Ajustes (el jugador no estaba en pausa).
	var expected: String = before.replace("\"is_paused\":true", "\"is_paused\":false")
	_expect(_snapshot() == expected, "tras cargar, la oficina, el dinero y la fecha no son idénticos")
	game = await _open_game()
	camera = game.get_node("OfficeCamera")
	_expect(camera.export_state() == camera_state, "la cámara no se restauró: %s" % [camera.export_state()])
	_expect(game.ceo.export_state() == ceo_state, "el CEO no se restauró: %s vs %s" % [game.ceo.export_state(), ceo_state])
	_expect(game.get_node("Hud").get_balance_text() == MoneyFormat.format(Economy.balance), "el dinero en pantalla")
	await _close_game(game)


func _check_menu() -> void:
	# El menú muestra las ranuras: las vacías no se pueden pulsar.
	var menu: Control = MENU_SCENE.instantiate()
	add_child(menu)
	await get_tree().process_frame
	var load_button: Button = menu.get_node("%LoadButton")
	_expect(not load_button.disabled, "Cargar partida debería estar activo")
	await _click(load_button)
	_expect(menu.get_node("%LoadList").visible, "se abre la lista de partidas")
	_expect(not menu.get_slot_button("slot_2").disabled and menu.get_slot_button("slot_1").disabled
		and menu.get_slot_button(SaveManager.AUTOSAVE).disabled, "ranuras activas e inactivas")
	_expect(menu.get_slot_button("slot_2").text.begins_with("Ranura 2 — Mes 2"), "texto en el menú")
	menu.queue_free()
	await get_tree().process_frame
	_clear_saves()
	menu = MENU_SCENE.instantiate()
	add_child(menu)
	await get_tree().process_frame
	_expect(menu.get_node("%LoadButton").disabled, "sin partidas guardadas, Cargar partida no se puede pulsar")
	menu.queue_free()
	await get_tree().process_frame
