# Prueba del hito 63: tutorial, primeros pasos.
# Criterio: una partida nueva muestra el primer paso; al cumplir la condición pasa al
# siguiente; saltarlo lo cierra y se guarda. También: resalta con un marco lo que pide,
# no tapa los paneles, se retoma desde Ajustes y una partida sin tutorial carga sin él.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=tutorial
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TEST_SAVE_DIR: String = "user://test_saves"
const STEP_IDS: Array[String] = ["camera", "build", "work_area", "workstation", "vacancy", "hire"]
const AREA_CELL := Vector2i(4, 4)
const DESK_CELL := Vector2i(4, 0)
const CHAIR_CELL := Vector2i(4, 1)

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []


func _ready() -> void:
	SaveManager.save_dir = TEST_SAVE_DIR
	Settings.reset_to_defaults()
	_clear_saves()
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_data()
	await _check_walkthrough()
	await _check_skip_and_resume()
	_check_save_and_load()
	_check_already_met()
	_check_demo()
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


# Arrastra la oficina con el botón izquierdo desde un punto libre de la pantalla.
func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	await _push(press)
	var steps: int = 5
	var last: Vector2 = from
	for index: int in range(1, steps + 1):
		var at: Vector2 = from.lerp(to, float(index) / steps)
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.relative = at - last
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		last = at
		await _push(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to
	release.global_position = to
	await _push(release)


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


func _step_id() -> String:
	return String(Tutorial.get_current_step().get("id", ""))


func _check_data() -> void:
	var ids: Array[String] = []
	for step: Dictionary in Tutorial.get_steps():
		ids.append(String(step["id"]))
		_expect(not String(step.get("text", "")).is_empty() and step.has("condition"), "el paso %s tiene texto y condición" % step.get("id"))
	_expect(ids == STEP_IDS, "pasos del tutorial: %s" % [ids])


func _check_walkthrough() -> void:
	SaveManager.new_game()
	_expect(Tutorial.active and not Tutorial.finished and _step_id() == "camera", "una partida nueva empieza en el primer paso")
	var game: Node = await _open_game()
	var panel: TutorialPanel = game.get_tutorial_panel()
	var build: BuildPanel = game.get_node("BuildPanel")
	var staff_panel: StaffPanel = game.get_node("StaffPanel")
	await get_tree().process_frame
	_expect(panel.is_showing() and panel.get_text() == String(Tutorial.get_current_step()["text"]), "la tarjeta muestra el paso: %s" % panel.get_text())
	_expect(panel.get_header() == "Tutorial · paso 1 de 6", "cabecera: %s" % panel.get_header())
	_expect(panel.get_target_key() == "office" and panel.get_frame_rect().has_area(), "resalta el local")
	# La tarjeta no tapa el panel izquierdo, el reloj ni la barra.
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var card: Rect2 = panel.get_panel_rect()
	var hud_clock: Control = (game.get_node("Hud") as Hud).get_pause_button()
	_expect(screen.encloses(card), "la tarjeta cabe en la pantalla: %s" % card)
	_expect(card.position.x >= StaffPanel.MARGIN + StaffPanel.PANEL_WIDTH, "la tarjeta queda a la derecha de los paneles izquierdos: %s" % card)
	_expect(not card.intersects(hud_clock.get_global_rect()) and not card.intersects(build.get_menu_bar().get_global_rect()),
		"la tarjeta no tapa el reloj ni la barra")
	# 1. Cámara.
	var start: Vector2 = screen.size * Vector2(0.5, 0.6)
	await _drag(start, start + Vector2(120, 40))
	_expect(_step_id() == "build" and panel.get_header() == "Tutorial · paso 2 de 6", "arrastrar la cámara pasa al paso Construir")
	await get_tree().process_frame
	_expect(panel.get_target_key() == "build" and panel.get_frame_rect().encloses(build.get_open_button().get_global_rect()),
		"el marco rodea el botón Construir")
	# 2. Construir: el clic atraviesa el marco.
	await _click(build.get_open_button())
	_expect(build.is_build_mode() and _step_id() == "work_area", "abrir Construir (bajo el marco) pasa al Área de trabajo")
	await get_tree().process_frame
	_expect(panel.get_target_key() == "tool:work_area" and panel.get_frame_rect().encloses(build.get_tool_button("work_area").get_global_rect()),
		"en Construir resalta la herramienta Área de trabajo: %s" % panel.get_target_key())
	# 3. Área de trabajo.
	var builder: Builder = game.get_node("BuildController").builder
	_expect(builder.mark_room("work_area", AREA_CELL)["ok"], "marcar el Área de trabajo")
	_expect(_step_id() == "workstation", "marcar el Área de trabajo pasa al puesto")
	# 4. Puesto: escritorio y silla no bastan sin computadora.
	builder.place("simple_desk", DESK_CELL, 2)
	builder.place("basic_chair", CHAIR_CELL, 0)
	_expect(_step_id() == "workstation", "sin computadora todavía no hay puesto")
	builder.install_computer("basic_computer", DESK_CELL)
	_expect(_step_id() == "vacancy", "con la computadora hay puesto y pasa a la vacante")
	await get_tree().process_frame
	_expect(panel.get_target_key() == "build_exit", "en Construir resalta Salir: %s" % panel.get_target_key())
	await _click(build.get_exit_button())
	await get_tree().process_frame
	_expect(panel.get_target_key() == "staff", "fuera de Construir resalta Personal: %s" % panel.get_target_key())
	# 5. Vacante.
	await _click(staff_panel.get_open_button())
	await get_tree().process_frame
	_expect(panel.get_target_key() == "staff_publish", "con Personal abierto resalta Publicar: %s" % panel.get_target_key())
	staff_panel.select_role_and_level("programmer", "junior")
	await _click(staff_panel.get_publish_button())
	_expect(Staff.vacancies.size() == 1 and _step_id() == "hire", "publicar la vacante pasa a contratar")
	# 6. Contratar: termina el tutorial.
	_notices.clear()
	_expect(not Staff.hire_directly("programmer", "junior").is_empty(), "contratar un programador")
	_expect(not Tutorial.active and Tutorial.finished and not panel.is_showing() and not panel.get_frame_rect().has_area(),
		"con el primer empleado termina el tutorial y se oculta")
	_expect(_notices.filter(func(text: String) -> bool: return text.begins_with("Terminaste el tutorial")).size() == 1,
		"avisa una vez al terminar: %s" % [_notices])
	_expect(bool(Settings.get_value("tutorial_seen")), "terminarlo se recuerda en las opciones")
	await _close_game(game)
	# La partida siguiente empieza sin tutorial.
	SaveManager.new_game()
	_expect(not Tutorial.active and not Tutorial.is_showing(), "después de terminarlo, una partida nueva no lo muestra")
	Settings.reset_to_defaults()


func _check_skip_and_resume() -> void:
	Settings.reset_to_defaults()
	SaveManager.new_game()
	var game: Node = await _open_game()
	var panel: TutorialPanel = game.get_tutorial_panel()
	EventBus.ui_action.emit("camera_moved")
	_expect(_step_id() == "build", "la cámara lleva al paso 2")
	_notices.clear()
	await _click(panel.get_skip_button())
	_expect(not Tutorial.active and not panel.is_showing() and bool(Settings.get_value("tutorial_seen")),
		"Saltar cierra el tutorial y lo recuerda")
	_expect(_notices.size() == 1 and _notices[0].contains("Ajustes"), "y avisa cómo retomarlo: %s" % [_notices])
	# Se guarda saltado.
	SaveManager.save_game("slot_1")
	var settings: SettingsPanel = game.get_node("SettingsPanel")
	settings.set_open(true)
	settings.set_tab(SettingsPanel.TAB_OPTIONS)
	await get_tree().process_frame
	var button: Button = settings.get_tutorial_button()
	_expect(button.is_visible_in_tree() and not button.disabled and button.text == "Retomar el tutorial", "Ajustes ofrece retomarlo: %s" % button.text)
	await _click(button)
	_expect(Tutorial.active and _step_id() == "build" and not settings.is_open() and panel.is_showing(),
		"retomar vuelve al paso donde quedó y cierra Ajustes")
	_expect(settings.get_tutorial_button().disabled and settings.get_tutorial_button().text == "El tutorial está en curso",
		"con el tutorial en curso el botón no se usa")
	await _close_game(game)
	# La partida guardada lo tiene saltado.
	_expect(SaveManager.load_game("slot_1") and not Tutorial.active and _step_id() == "" and Tutorial.step_index == 1,
		"al cargar sigue saltado, en el paso 2")
	Tutorial.resume()
	_expect(_step_id() == "build", "y retomarlo vuelve al paso 2")
	# Terminado, se vuelve a empezar desde el principio.
	Tutorial.import_state({"finished": true, "step": "hire"})
	Tutorial.resume()
	_expect(Tutorial.active and Tutorial.step_index == 0, "volver a empezar arranca en el paso 1")
	Settings.reset_to_defaults()


func _check_save_and_load() -> void:
	Settings.reset_to_defaults()
	SaveManager.new_game()
	EventBus.ui_action.emit("camera_moved")
	EventBus.ui_action.emit("build_opened")
	_expect(_step_id() == "work_area", "dos acciones llevan al paso 3")
	_expect(SaveManager.save_game("slot_2"), "guardar con el tutorial a medias")
	SaveManager.new_game()
	_expect(_step_id() == "camera", "una partida nueva vuelve al principio")
	_expect(SaveManager.load_game("slot_2") and Tutorial.active and _step_id() == "work_area", "cargar vuelve al paso 3")
	# Partida sin tutorial (de antes del hito 63): carga sin él.
	var file := FileAccess.open(TEST_SAVE_DIR.path_join("slot_2.json"), FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	data.erase("tutorial")
	file = FileAccess.open(TEST_SAVE_DIR.path_join("slot_3.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	_expect(SaveManager.load_game("slot_3") and not Tutorial.active and Tutorial.finished and not Tutorial.is_showing(),
		"una partida sin tutorial carga sin él, como terminado")
	# Un paso que ya no existe vuelve al primero.
	Tutorial.import_state({"active": true, "finished": false, "step": "no_existe"})
	_expect(Tutorial.active and Tutorial.step_index == 0, "un paso desconocido vuelve al primero")


func _check_already_met() -> void:
	Settings.reset_to_defaults()
	SaveManager.new_game()
	var builder := Builder.new()
	builder.mark_room("work_area", AREA_CELL)
	Tutorial.begin_load()
	Tutorial.import_state({"active": true, "finished": false, "step": "camera", "actions": ["camera_moved", "build_opened"]})
	EventBus.office_changed.emit()
	_expect(_step_id() == "camera", "mientras carga no revisa")
	Tutorial.finish_load()
	_expect(_step_id() == "workstation", "los pasos que ya se cumplen se saltan solos, varios seguidos: %s" % _step_id())


func _check_demo() -> void:
	Settings.reset_to_defaults()
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	SaveManager.start_with_demo = false
	_expect(not Tutorial.active, "la empresa de prueba empieza sin tutorial")
	SaveManager.new_game()
