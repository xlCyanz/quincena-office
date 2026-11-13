# Prueba del hito 64: tutorial del negocio y ayuda en los menús.
# Criterio: el tutorial llega hasta la primera entrega; cada menú abre su ayuda; una partida
# vieja carga sin tutorial (eso último lo mira también test_tutorial).
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=help
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TEST_SAVE_DIR: String = "user://test_saves"
const PANEL_TOPICS: Dictionary[String, String] = {
	"StaffPanel": "staff", "ProjectsPanel": "projects", "TeamsPanel": "teams", "BankPanel": "bank", "CompanyPanel": "company",
}

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []


func _ready() -> void:
	SaveManager.save_dir = TEST_SAVE_DIR
	Settings.reset_to_defaults()
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	await _check_business_steps()
	await _check_help()
	_check_old_save()
	Settings.reset_to_defaults()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


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


func _escape() -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = pressed
		await _push(key)


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


# El jugador ya contrató (pasos del hito 63): sigue con contratos, nómina, Banco y entrega.
func _check_business_steps() -> void:
	SaveManager.new_game()
	Tutorial.import_state({"active": true, "finished": false, "step": "contract",
		"actions": ["camera_moved", "build_opened"]})
	var game: Node = await _open_game()
	var panel: TutorialPanel = game.get_tutorial_panel()
	var projects_panel: ProjectsPanel = game.get_node("ProjectsPanel")
	var bank_panel: BankPanel = game.get_node("BankPanel")
	var hud: Hud = game.get_node("Hud")
	await get_tree().process_frame
	_expect(_step_id() == "contract" and panel.get_header() == "Tutorial · paso 7 de 10", "paso del contrato: %s" % panel.get_header())
	_expect(panel.get_target_key() == "projects", "sin Proyectos abierto resalta Proyectos: %s" % panel.get_target_key())
	# 7. Contrato.
	Projects.create_offer("small")
	# Se resalta la primera oferta de la bandeja.
	var offer: Dictionary = Projects.offers[0]
	await _click(projects_panel.get_open_button())
	await get_tree().process_frame
	_expect(panel.get_target_key() == "projects_accept"
		and panel.get_frame_rect().encloses(projects_panel.get_accept_button(int(offer["id"])).get_global_rect()),
		"con Proyectos abierto resalta Aceptar de la primera oferta: %s" % panel.get_target_key())
	await _click(projects_panel.get_accept_button(int(offer["id"])))
	_expect(Projects.contracts.size() == 1 and _step_id() == "payroll", "aceptar el contrato pasa a la nómina: %s" % _step_id())
	await _click(projects_panel.get_open_button())
	# 8. Nómina y velocidad.
	await get_tree().process_frame
	_expect(panel.get_target_key() == "speed" and panel.get_frame_rect().encloses(hud.get_speed_button(1).get_global_rect()),
		"resalta 2x: %s" % panel.get_target_key())
	_expect(panel.get_text().contains("nómina"), "el paso explica la nómina: %s" % panel.get_text())
	GameClock.set_paused(false)
	await _click(hud.get_speed_button(1))
	_expect(GameClock.speed_index == 1 and _step_id() == "bank", "cambiar la velocidad pasa al Banco: %s" % _step_id())
	# 9. Banco.
	await get_tree().process_frame
	_expect(panel.get_target_key() == "bank", "resalta el Banco: %s" % panel.get_target_key())
	await _click(bank_panel.get_open_button())
	_expect(bank_panel.is_open() and _step_id() == "delivery", "abrir el Banco pasa a la entrega: %s" % _step_id())
	# 10. Entrega.
	await get_tree().process_frame
	_expect(panel.get_target_key() == "projects", "con el Banco abierto resalta Proyectos: %s" % panel.get_target_key())
	await _click(projects_panel.get_open_button())
	await get_tree().process_frame
	var contract_id: int = int(Projects.contracts[0]["id"])
	_expect(panel.get_target_key() == "projects_deliver"
		and panel.get_frame_rect().encloses(projects_panel.get_deliver_button(contract_id).get_global_rect()),
		"con Proyectos abierto resalta Entregar: %s" % panel.get_target_key())
	_notices.clear()
	_expect(Projects.deliver(contract_id)["ok"], "entregar el contrato")
	_expect(not Tutorial.active and Tutorial.finished and not panel.is_showing() and not panel.get_frame_rect().has_area(),
		"con la primera entrega termina el tutorial")
	_expect(_notices.filter(func(text: String) -> bool: return text.begins_with("Terminaste el tutorial")).size() == 1,
		"avisa una vez al terminar: %s" % [_notices])
	_expect(bool(Settings.get_value("tutorial_seen")), "terminarlo se recuerda en las opciones")
	GameClock.set_speed_index(0)
	await _close_game(game)
	SaveManager.new_game()
	_expect(not Tutorial.active and not Tutorial.is_showing(), "después de terminarlo, una partida nueva no lo muestra")
	Settings.reset_to_defaults()
	# Con la tecla de velocidad también cuenta.
	SaveManager.new_game()
	game = await _open_game()
	Tutorial.import_state({"active": true, "finished": false, "step": "payroll"})
	var key := InputEventKey.new()
	key.keycode = KEY_3
	key.pressed = true
	await _push(key)
	_expect(GameClock.speed_index == 2 and _step_id() == "bank", "la tecla 3 también cuenta: %s" % _step_id())
	GameClock.set_speed_index(0)
	await _close_game(game)


func _check_help() -> void:
	Settings.reset_to_defaults()
	SaveManager.new_game()
	var game: Node = await _open_game()
	var dialog: HelpDialog = game.get_help_dialog()
	var topics: Dictionary = dialog.get_topics()
	_expect(topics.size() == 6, "temas de ayuda: %s" % [topics.keys()])
	for topic: String in topics:
		var entry: Dictionary = topics[topic]
		_expect(not String(entry.get("title", "")).is_empty() and String(entry.get("text", "")).length() > 80,
			"el tema %s tiene título y texto" % topic)
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	GameClock.set_paused(false)
	for panel_name: String in PANEL_TOPICS:
		var topic: String = PANEL_TOPICS[panel_name]
		var panel: CanvasLayer = game.get_node(panel_name)
		panel.call("set_open", true)
		await get_tree().process_frame
		var button: Button = panel.call("get_help_button")
		_expect(button.is_visible_in_tree() and button.text == "?" and button.size.y >= 44.0 and button.tooltip_text == "Ayuda",
			"%s tiene su «?»" % panel_name)
		await _click(button)
		await get_tree().process_frame
		_expect(dialog.is_open() and dialog.get_topic() == topic and dialog.get_title() == String(topics[topic]["title"])
			and dialog.get_text() == String(topics[topic]["text"]), "«?» de %s abre su ayuda: %s" % [panel_name, dialog.get_title()])
		_expect(screen.encloses(dialog.get_panel_rect()), "la ayuda de %s cabe en la pantalla: %s" % [topic, dialog.get_panel_rect()])
		_expect(not GameClock.is_paused and bool(panel.call("is_open")), "la ayuda no pausa ni cierra el panel")
		await _click(dialog.get_close_button())
		_expect(not dialog.is_open() and bool(panel.call("is_open")), "Entendido cierra la ayuda y deja %s" % panel_name)
		panel.call("set_open", false)
	# Construir.
	var build: BuildPanel = game.get_node("BuildPanel")
	build.set_build_mode(true)
	await get_tree().process_frame
	await _click(build.get_help_button())
	_expect(dialog.is_open() and dialog.get_topic() == "build", "el «?» de Construir abre su ayuda")
	# Esc cierra primero la ayuda y después lo demás.
	await _escape()
	_expect(not dialog.is_open() and build.is_build_mode(), "Esc cierra la ayuda y deja Construir")
	await _escape()
	_expect(not build.is_build_mode(), "otro Esc sale de Construir")
	dialog.show_topic("no_existe")
	_expect(not dialog.is_open(), "un tema desconocido no abre nada")
	await _close_game(game)


# Una partida de la fase 6 (sin tutorial guardado) carga sin él.
func _check_old_save() -> void:
	Settings.reset_to_defaults()
	SaveManager.new_game()
	SaveManager.save_game("slot_4")
	var path: String = TEST_SAVE_DIR.path_join("slot_4.json")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.erase("tutorial")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	SaveManager.new_game()
	_expect(Tutorial.active, "una partida nueva lo muestra")
	_expect(SaveManager.load_game("slot_4") and not Tutorial.active and not Tutorial.is_showing(), "la partida vieja carga sin tutorial")
	DirAccess.remove_absolute(path)
