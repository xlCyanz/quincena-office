# Sonido: cada efecto y pista de data/audio.json existe, las señales de EventBus suenan, los botones
# hacen clic, construir y vender suenan, la música cambia entre menú y partida y los volúmenes se
# guardan, se validan y llegan a los buses. Sin ventana no se oye nada: se mira el historial de Audio.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=audio
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const WALL: String = "wall"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	Settings.reset_to_defaults()
	_check_files()
	_check_volumes()
	_check_play()
	await _check_buttons_and_options()
	await _check_game()
	Settings.reset_to_defaults()
	Audio.play_music("")
	Audio.clear_history()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _last() -> String:
	var history: Array[String] = Audio.get_history()
	return history[-1] if not history.is_empty() else ""


func _check_files() -> void:
	var data: Dictionary = Audio.get_data()
	_expect(Audio.get_sound_ids().size() >= 10, "hay efectos: %s" % [Audio.get_sound_ids()])
	for id: String in Audio.get_sound_ids():
		_expect(Audio.get_stream(id + ".wav") != null, "el efecto %s tiene archivo" % id)
	for track: String in data["music"]:
		var stream := Audio.get_stream(String(data["music"][track])) as AudioStreamWAV
		_expect(stream != null and stream.get_length() > 10.0, "la pista %s existe y dura más de 10 s" % track)
		_expect(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "la pista %s se importa en bucle" % track)
	var signal_names: Array[String] = []
	for info: Dictionary in EventBus.get_signal_list():
		signal_names.append(String(info["name"]))
	for signal_name: String in data["signals"]:
		_expect(signal_names.has(signal_name), "EventBus tiene la señal %s" % signal_name)
		_expect(Audio.get_sound_ids().has(String(data["signals"][signal_name])), "la señal %s pide un efecto que existe" % signal_name)
	for key: String in ["payroll_sound", "late_payment_sound"]:
		_expect(Audio.get_sound_ids().has(String(data[key])), "%s es un efecto que existe" % key)
	for kind: String in ["music", "sfx"]:
		var index: int = AudioServer.get_bus_index(Audio.get_bus(kind))
		_expect(index > 0 and AudioServer.get_bus_send(index) == &"Master", "el bus %s existe y va a Master" % kind)


func _bus_db(kind: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Audio.get_bus(kind)))


func _bus_muted(kind: String) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(Audio.get_bus(kind)))


func _check_volumes() -> void:
	_expect(Settings.get_value("master_volume") == 80 and Settings.get_value("music_volume") == 60
		and Settings.get_value("sfx_volume") == 80, "volúmenes por defecto 80, 60 y 80")
	_expect(is_equal_approx(_bus_db("music"), linear_to_db(0.6)) and is_equal_approx(_bus_db("Master"), linear_to_db(0.8)),
		"los volúmenes por defecto llegan a los buses (música %.1f dB)" % _bus_db("music"))
	_expect(not Settings.set_value("music_volume", 101) and not Settings.set_value("music_volume", -1)
		and not Settings.set_value("music_volume", "50") and not Settings.set_value("music_volume", 50.5),
		"un volumen fuera de 0 a 100 o que no es entero no sirve")
	_expect(Settings.set_value("sfx_volume", 50) and is_equal_approx(_bus_db("sfx"), linear_to_db(0.5)) and not _bus_muted("sfx"),
		"efectos al 50 %")
	_expect(Settings.set_value("music_volume", 0) and _bus_muted("music"), "música en 0 la silencia")
	Settings.load_settings()
	_expect(Settings.get_value("music_volume") == 0 and Settings.get_value("sfx_volume") == 50, "los volúmenes se guardan")
	Settings.reset_to_defaults()
	_expect(not _bus_muted("music") and is_equal_approx(_bus_db("sfx"), linear_to_db(0.8)), "Valores por defecto los devuelve")


func _check_play() -> void:
	Audio.clear_history()
	_expect(not Audio.play("no_existe"), "un efecto que no existe no suena")
	_expect(Audio.play("notice") and not Audio.play("notice"), "dos avisos seguidos suenan una vez")
	EventBus.sound_requested.emit("hire")
	_expect(_last() == "hire", "sound_requested suena")
	Audio.clear_history()
	EventBus.notice.emit("Prueba de sonido")
	_expect(_last() == "notice", "un aviso suena")
	EventBus.contract_accepted.emit()
	_expect(_last() == "contract", "aceptar un contrato suena")
	EventBus.payment_recorded.emit(Staff.CONCEPT_PAYROLL, true)
	_expect(_last() == "cash", "pagar la nómina suena a caja")
	EventBus.payment_recorded.emit(Staff.CONCEPT_PAYROLL, false)
	_expect(_last() == "alarm", "no poder pagar suena a alarma")


func _check_buttons_and_options() -> void:
	Audio.clear_history()
	var button := Button.new()
	add_child(button)
	button.pressed.emit()
	_expect(_last() == "click", "un botón hace clic")
	button.queue_free()
	var options := OptionsList.new()
	add_child(options)
	await get_tree().process_frame
	_expect(options.get_volume_slider("music_volume").value == 60.0, "el control de música muestra 60")
	options.get_volume_slider("music_volume").value = 30.0
	_expect(Settings.get_value("music_volume") == 30 and is_equal_approx(_bus_db("music"), linear_to_db(0.3)),
		"mover el control cambia el volumen")
	Settings.set_value("sfx_volume", 40)
	_expect(options.get_volume_slider("sfx_volume").value == 40.0, "el control sigue a la opción")
	Settings.reset_to_defaults()
	options.queue_free()


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame


func _mouse(at: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _push(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	await _push(event)


func _click(at: Vector2) -> void:
	await _mouse(at, true)
	await _mouse(at, false)


func _check_game() -> void:
	Audio.play_music("menu")
	_expect(Audio.get_music_track() == "menu", "suena la música del menú")
	SaveManager.new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameClock.stop()
	_expect(Audio.get_music_track() == "office" and Audio.get_music_player().stream == Audio.get_stream("music_office.wav"),
		"en la partida suena la música de la oficina")
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var controller: BuildController = game.get_node("BuildController")
	var to_screen: Callable = func(grid_position: Vector2) -> Vector2:
		return grid.get_canvas_transform() * grid.grid_to_world(grid_position)
	# Una pared en un borde libre del local.
	var edge := Vector3i(-1, -1, -1)
	var cells: Array[Vector2i] = OfficeState.lot.get_cells()
	for cell: Vector2i in cells:
		var candidate := Vector3i(cell.x, cell.y, GridEdge.AXIS_X)
		if cells.has(cell + Vector2i(1, 0)) and OfficeState.get_edge(candidate).is_empty() \
				and controller.builder.quote([{"edge": candidate, "kind": WALL}])["ok"]:
			edge = candidate
			break
	_expect(edge.z >= 0, "hay un borde libre para la pared")
	if edge.z < 0:
		game.queue_free()
		return
	var point := Vector2(edge.x + 0.5, edge.y)
	controller.set_active(true)
	controller.set_tool(BuildController.TOOL_WALL)
	Audio.clear_history()
	await _click(to_screen.call(point))
	_expect(OfficeState.get_edge(edge) == WALL and _last() == "build", "poner una pared suena (%s)" % [Audio.get_history()])
	controller.set_tool(BuildController.TOOL_SELL)
	Audio.clear_history()
	await _click(to_screen.call(point))
	_expect(OfficeState.get_edge(edge).is_empty() and _last() == "sell", "vender la pared suena (%s)" % [Audio.get_history()])
	Economy.charge(Economy.balance + 1000, "Prueba")
	controller.set_tool(BuildController.TOOL_WALL)
	Audio.clear_history()
	await _click(to_screen.call(point))
	_expect(OfficeState.get_edge(edge).is_empty() and _last() == "error", "sin dinero la pared suena a error (%s)" % [Audio.get_history()])
	controller.set_active(false)
	game.queue_free()
	await get_tree().process_frame
