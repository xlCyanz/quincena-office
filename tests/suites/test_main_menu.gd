# Prueba del hito 61: menú principal.
# Criterio: Continuar abre la partida más reciente; sin partidas no aparece; nueva partida
# avisa si hay autoguardado.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=main_menu
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const GAME_SCENE_PATH: String = "res://scenes/main.tscn"
const TEST_SAVE_DIR: String = "user://test_saves"

var _failures: int = 0
var _checks: int = 0
## Escenas que el menú pidió abrir y veces que pidió salir.
var _opened: Array[String] = []
var _quits: int = 0


func _ready() -> void:
	SaveManager.save_dir = TEST_SAVE_DIR
	_clear_saves()
	_check_latest_slot()
	await _check_without_saves()
	await _check_continue()
	await _check_new_game_warning()
	await _check_options_and_quit()
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


func _open_menu() -> Control:
	_opened.clear()
	_quits = 0
	var menu: Control = MENU_SCENE.instantiate()
	menu.change_scene = func(path: String) -> void: _opened.append(path)
	menu.quit_action = func() -> void: _quits += 1
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	return menu


func _close_menu(menu: Control) -> void:
	menu.queue_free()
	await get_tree().process_frame


# Guarda una partida con un saldo reconocible y una hora de guardado dada.
func _save(slot: String, balance: int, saved_at: int) -> void:
	SaveManager.new_game()
	Economy.earn(balance - Economy.balance, "Prueba")
	SaveManager.save_game(slot)
	var path: String = TEST_SAVE_DIR.path_join(slot + ".json")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["saved_at"] = saved_at
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _check_latest_slot() -> void:
	_expect(SaveManager.get_latest_slot() == "", "sin partidas no hay más reciente")
	_save("slot_2", 22000, 1000)
	_save("slot_4", 44000, 3000)
	_save(SaveManager.AUTOSAVE, 11000, 2000)
	_expect(SaveManager.get_latest_slot() == "slot_4", "la más reciente es la ranura 4: %s" % SaveManager.get_latest_slot())
	_save(SaveManager.AUTOSAVE, 11000, 3000)
	_expect(SaveManager.get_latest_slot() == SaveManager.AUTOSAVE, "con la misma hora gana el autoguardado")
	_clear_saves()


func _check_without_saves() -> void:
	var menu: Control = await _open_menu()
	_expect(not menu.get_continue_button().visible, "sin partidas no aparece Continuar")
	_expect(menu.get_new_game_button().visible and menu.get_settings_button().visible and menu.get_quit_button().visible
		and menu.get_node("%LoadButton").disabled, "Nueva partida, Ajustes y Salir; Cargar sin partidas no se puede pulsar")
	await _click(menu.get_new_game_button())
	_expect(_opened == [GAME_SCENE_PATH] and menu.get_view() == "buttons", "sin autoguardado empieza sin preguntar")
	await _close_menu(menu)


func _check_continue() -> void:
	_save("slot_1", 31000, 1000)
	_save(SaveManager.AUTOSAVE, 12000, 5000)
	_save("slot_3", 33000, 3000)
	var menu: Control = await _open_menu()
	var button: Button = menu.get_continue_button()
	_expect(button.visible and button.tooltip_text.begins_with("Autoguardado"), "Continuar aparece con la más reciente: %s" % button.tooltip_text)
	_expect(menu.get_viewport().gui_get_focus_owner() == button, "Continuar tiene el foco")
	SaveManager.new_game()
	await _click(button)
	_expect(_opened == [GAME_SCENE_PATH] and Economy.balance == 12000, "Continuar carga el autoguardado: %d" % Economy.balance)
	await _close_menu(menu)
	# Si la más reciente es una ranura manual, esa.
	_save("slot_3", 33000, 9000)
	menu = await _open_menu()
	SaveManager.new_game()
	await _click(menu.get_continue_button())
	_expect(Economy.balance == 33000, "Continuar carga la ranura 3: %d" % Economy.balance)
	await _close_menu(menu)
	# Un archivo dañado no abre nada.
	var file := FileAccess.open(TEST_SAVE_DIR.path_join("slot_3.json"), FileAccess.WRITE)
	file.store_string("{roto")
	file.close()
	menu = await _open_menu()
	SaveManager.new_game()
	await _click(menu.get_continue_button())
	_expect(_opened == [GAME_SCENE_PATH] and Economy.balance == 12000, "la ranura rota no cuenta: sigue el autoguardado")
	await _close_menu(menu)
	_clear_saves()


func _check_new_game_warning() -> void:
	_save(SaveManager.AUTOSAVE, 12000, 5000)
	_save("slot_2", 22000, 1000)
	var menu: Control = await _open_menu()
	await _click(menu.get_new_game_button())
	_expect(_opened.is_empty() and menu.get_view() == "confirm", "con autoguardado, Nueva partida pregunta")
	_expect(menu.get_confirm_text().contains("Mes 1") and menu.get_confirm_text().contains("reemplazará el autoguardado"),
		"y dice qué se reemplaza: %s" % menu.get_confirm_text())
	_expect(not menu.get_new_game_button().visible, "la pregunta reemplaza a los botones")
	await _click(menu.get_cancel_button())
	_expect(_opened.is_empty() and menu.get_view() == "buttons" and menu.get_new_game_button().visible, "cancelar vuelve sin empezar")
	_expect(SaveManager.has_save(SaveManager.AUTOSAVE), "y el autoguardado queda")
	await _click(menu.get_new_game_button())
	Economy.earn(777, "Prueba")
	await _click(menu.get_confirm_button())
	_expect(_opened == [GAME_SCENE_PATH] and Economy.balance != 12000 + 777, "confirmar empieza una partida nueva")
	_expect(SaveManager.has_save("slot_2"), "las ranuras manuales quedan")
	await _close_menu(menu)
	_clear_saves()


func _check_options_and_quit() -> void:
	Settings.reset_to_defaults()
	var menu: Control = await _open_menu()
	await _click(menu.get_settings_button())
	_expect(menu.get_view() == "options" and menu.get_options().is_visible_in_tree() and not menu.get_new_game_button().visible,
		"Ajustes muestra las opciones")
	var autosave: CheckBox = menu.get_options().get_toggle("autosave")
	_expect(autosave.button_pressed, "con los valores actuales")
	await _click(autosave)
	_expect(not bool(Settings.get_value("autosave")), "cambiar una opción desde el menú")
	await _click(menu.get_back_button())
	_expect(menu.get_view() == "buttons" and menu.get_new_game_button().visible, "Volver")
	Settings.reset_to_defaults()
	await _click(menu.get_quit_button())
	_expect(_quits == 1, "Salir cierra el juego")
	await _close_menu(menu)
