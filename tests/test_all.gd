# Prueba única sin ventana: corre en orden las comprobaciones de todos los hitos
# (tests/suites/, una parte por hito) y al final dice cuántas fallaron.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_all.tscn
# Solo algunas partes (separadas por coma, sin «test_»):
#   Godot --headless --path . res://tests/test_all.tscn -- --only=reception,administration
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SUITES_DIR: String = "res://tests/suites/"
## Partes en el orden de los hitos (1 a 56) y la empresa inicial.
const SUITES: Array[String] = [
	"grid_camera", "game_clock", "new_game", "ceo", "construction", "furniture", "rooms", "money_ui",
	"save", "vacancies", "hiring", "workday", "payroll", "contracts", "teams", "production", "bugs",
	"delivery", "morale", "bank", "credit", "loans", "default", "emergency", "land", "company_value",
	"stages", "objectives", "phase3", "promotions", "leaders", "managers", "departments", "overtime",
	"agenda", "reception", "administration", "competition", "phase4", "servers", "products", "launch", "events", "event_list", "ambiance", "furniture_quality", "meetings", "ipo", "phase5", "traits", "conduct", "bathrooms", "lunch", "breaks", "office_extras", "candidates", "starting_company", "dev_tools",
]
## Primera parte que cuenta los baños (hito 52): las anteriores miden números exactos en
## oficinas sin baño y corren con Staff.bathrooms_enabled en false.
const FIRST_BATHROOM_SUITE: String = "bathrooms"
## Primera parte con candidatos según la empresa (hito 56): las anteriores cuentan
## candidatos y habilidades exactos y corren con Staff.company_hiring_enabled en false.
const FIRST_CANDIDATES_SUITE: String = "candidates"
## Nodos globales cuyas conexiones de señales deja cada parte (se quitan al terminarla).
const AUTOLOADS: Array[String] = [
	"EventBus", "GameClock", "Economy", "OfficeState", "Staff", "Projects", "Products", "Bank", "Company", "Events", "SaveManager",
]


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las partes esperan una partida nueva con el CEO solo y guardan en otra carpeta.
	SaveManager.save_dir = "user://test_saves"
	SaveManager.start_with_demo = false
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
	# Cada parte empieza como al abrir el juego: sin partida y con el reloj parado.
	OfficeState.lot = Lot.new()
	GameClock.stop()
	Staff.bathrooms_enabled = SUITES.find(suite) >= SUITES.find(FIRST_BATHROOM_SUITE)
	Staff.company_hiring_enabled = SUITES.find(suite) >= SUITES.find(FIRST_CANDIDATES_SUITE)
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
	# Las escenas que abrió la parte (menú o juego) se cierran; test_all vuelve a ser la actual.
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


# Quita las conexiones que hizo una parte (por ejemplo, lambdas que escuchan avisos).
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
