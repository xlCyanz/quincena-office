# Prueba única sin ventana: corre en orden las partes de tests/suites/ y cuenta los fallos.
#   Godot --headless --path . res://tests/test_all.tscn [-- --only=reception,administration]
# Sale con 0 si todo pasa y 1 si algo falla.
extends Node

const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SUITES_DIR: String = "res://tests/suites/"
## Partes en el orden de los hitos; las agregadas después van al final.
const SUITES: Array[String] = [
	"grid_camera", "game_clock", "new_game", "ceo", "construction", "furniture", "rooms", "money_ui",
	"save", "vacancies", "hiring", "workday", "payroll", "contracts", "teams", "production", "bugs",
	"delivery", "morale", "bank", "credit", "loans", "default", "emergency", "land", "company_value",
	"stages", "objectives", "phase3", "promotions", "leaders", "managers", "departments", "overtime",
	"agenda", "reception", "administration", "competition", "phase4", "servers", "products", "launch", "events", "event_list", "ambiance", "furniture_quality", "meetings", "ipo", "phase5", "traits", "conduct", "bathrooms", "lunch", "breaks", "office_extras", "candidates", "status_icons", "investor", "phase6", "settings", "main_menu", "pause_menu", "tutorial", "help", "ui_scale", "export", "phase7", "camera_view", "glass_door", "walking", "arrivals", "office_chairs", "interview_view", "appointments", "cleaning_view", "build_sections", "quarters", "ground", "sprites", "starting_company", "dev_tools", "cleaning_shift", "laptop_glass_table", "seating", "glass_door_double", "audio",
]
## Desde aquí cuentan los baños; las anteriores corren con Staff.bathrooms_enabled en false.
const FIRST_BATHROOM_SUITE: String = "bathrooms"
## Desde aquí, candidatos según la empresa; antes Staff.company_hiring_enabled en false.
const FIRST_CANDIDATES_SUITE: String = "candidates"
## Desde aquí sale el inversionista; antes Bank.investor_enabled en false.
const FIRST_INVESTOR_SUITE: String = "investor"
## Desde aquí la cámara es suave; antes OfficeCamera.smoothing_enabled en false.
const FIRST_CAMERA_VIEW_SUITE: String = "camera_view"
## Desde aquí las llegadas son escalonadas; antes Staff.arrival_spread_enabled en false.
const FIRST_ARRIVALS_SUITE: String = "arrivals"
## Desde aquí las oficinas piden silla de visita; antes RoomRules.counts_enabled en false.
const FIRST_OFFICE_CHAIRS_SUITE: String = "office_chairs"
## Desde aquí limpieza entra y limpia a su minuto; antes Staff.cleaning_shift_enabled en false.
const FIRST_CLEANING_SHIFT_SUITE: String = "cleaning_shift"
## Desde aquí la entrada lleva la puerta de vidrio doble; antes OfficeState.double_door_enabled en false.
const FIRST_DOUBLE_DOOR_SUITE: String = "glass_door_double"
## Desde aquí los personajes tienen sus tres formas; antes OfficeCharacter.forms_enabled en false.
const FIRST_FORMS_SUITE: String = "sprites"
## Tope por parte; las más largas son las simulaciones de fase.
const MAX_SUITE_SECONDS: float = 60.0
## Autoloads cuyas conexiones de señales se quitan al terminar cada parte.
const AUTOLOADS: Array[String] = [
	"EventBus", "GameClock", "Economy", "OfficeState", "Staff", "Projects", "Products", "Bank", "Company", "Events", "SaveManager",
]


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Se pinta una vez (~1 s) antes de la primera parte.
	OfficeGrid.prepare_tile_set()
	# Partida nueva con el CEO solo; guardado y opciones en archivos de prueba.
	SaveManager.save_dir = "user://test_saves"
	SaveManager.start_with_demo = false
	Settings.path = "user://test_settings.cfg"
	Settings.reset_to_defaults()
	var only: Array[String] = _only_suites()
	var failed: Array[String] = []
	var total_checks: int = 0
	var total_failures: int = 0
	var started: int = Time.get_ticks_msec()
	for suite: String in SUITES:
		if not only.is_empty() and not only.has(suite):
			continue
		var suite_started: int = Time.get_ticks_msec()
		var result: Vector2i = await _run_suite(suite)
		var seconds: float = (Time.get_ticks_msec() - suite_started) / 1000.0
		result.y += 1
		if seconds > MAX_SUITE_SECONDS:
			printerr("FALLO: %s tardó %.1f s (el tope es %d s)" % [suite, seconds, int(MAX_SUITE_SECONDS)])
			result.x += 1
		total_failures += result.x
		total_checks += result.y
		if result.x > 0:
			failed.append(suite)
		print("[%s] %s: %d comprobaciones, %d fallos · %.1f s" % ["OK" if result.x == 0 else "FALLO", suite, result.y, result.x, seconds])
	print("Partes: %d · comprobaciones: %d · fallos: %d · %d s" % [
		SUITES.size() if only.is_empty() else only.size(), total_checks, total_failures, (Time.get_ticks_msec() - started) / 1000])
	if not failed.is_empty():
		print("Partes con fallos: %s" % ", ".join(failed))
	print("RESULTADO: %s" % ("OK" if total_failures == 0 else "FALLO"))
	get_tree().quit(0 if total_failures == 0 else 1)


# Corre una parte y devuelve (fallos, comprobaciones).
func _run_suite(suite: String) -> Vector2i:
	var before: Dictionary = _connections()
	# Cada parte empieza sin partida y con el reloj parado.
	OfficeState.lot = Lot.new()
	GameClock.stop()
	Staff.bathrooms_enabled = SUITES.find(suite) >= SUITES.find(FIRST_BATHROOM_SUITE)
	Staff.company_hiring_enabled = SUITES.find(suite) >= SUITES.find(FIRST_CANDIDATES_SUITE)
	Bank.investor_enabled = SUITES.find(suite) >= SUITES.find(FIRST_INVESTOR_SUITE)
	OfficeCamera.smoothing_enabled = SUITES.find(suite) >= SUITES.find(FIRST_CAMERA_VIEW_SUITE)
	Staff.arrival_spread_enabled = SUITES.find(suite) >= SUITES.find(FIRST_ARRIVALS_SUITE)
	RoomRules.counts_enabled = SUITES.find(suite) >= SUITES.find(FIRST_OFFICE_CHAIRS_SUITE)
	Staff.cleaning_shift_enabled = SUITES.find(suite) >= SUITES.find(FIRST_CLEANING_SHIFT_SUITE)
	OfficeState.double_door_enabled = SUITES.find(suite) >= SUITES.find(FIRST_DOUBLE_DOOR_SUITE)
	OfficeCharacter.forms_enabled = SUITES.find(suite) >= SUITES.find(FIRST_FORMS_SUITE)
	var script: GDScript = load("%stest_%s.gd" % [SUITES_DIR, suite])
	var node := Node.new()
	node.name = suite
	node.set_script(script)
	var result: Array[int] = [-1, 0]
	node.connect("finished", func(failures: int, checks: int) -> void:
		result[0] = failures
		result[1] = checks)
	add_child(node)
	while result[0] < 0:
		await get_tree().process_frame
	_drop_new_connections(before)
	GameClock.stop()
	node.queue_free()
	# Se cierran las escenas que abrió la parte.
	for child: Node in get_tree().root.get_children():
		if child != self and not ProjectSettings.has_setting("autoload/%s" % child.name):
			child.queue_free()
	get_tree().current_scene = self
	await get_tree().process_frame
	return Vector2i(result[0], result[1])


# Conexiones actuales de las señales de los autoloads: {"Nodo.señal": [Callable, …]}.
func _connections() -> Dictionary:
	var found: Dictionary = {}
	for autoload: String in AUTOLOADS:
		var node: Node = get_node("/root/%s" % autoload)
		for info: Dictionary in node.get_signal_list():
			var callables: Array = []
			for connection: Dictionary in node.get_signal_connection_list(info["name"]):
				callables.append(connection["callable"])
			found["%s.%s" % [autoload, info["name"]]] = callables
	return found


# Quita las conexiones que dejó una parte (por ejemplo, lambdas que escuchan avisos).
func _drop_new_connections(before: Dictionary) -> void:
	for autoload: String in AUTOLOADS:
		var node: Node = get_node("/root/%s" % autoload)
		for info: Dictionary in node.get_signal_list():
			var old: Array = before.get("%s.%s" % [autoload, info["name"]], [])
			for connection: Dictionary in node.get_signal_connection_list(info["name"]):
				var callable: Callable = connection["callable"]
				if not old.has(callable) and node.is_connected(info["name"], callable):
					node.disconnect(info["name"], callable)


func _only_suites() -> Array[String]:
	var only: Array[String] = []
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			for suite: String in argument.trim_prefix("--only=").split(",", false):
				only.append(suite.strip_edges().trim_prefix("test_"))
	return only
