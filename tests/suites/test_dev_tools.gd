# Herramientas de desarrollo: los monitores Quincena devuelven los valores de los sistemas y
# los comandos de la consola cambian dinero, reloj y barras.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=dev_tools
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261112

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	SaveManager.save_dir = "user://test_saves"
	_check_monitors()
	_check_console()
	_check_console_overlay()
	_check_commands()
	finished.emit(_failures, _checks)


# Opción de Ajustes: los renglones de la consola sobre el juego, a la vista o no.
func _check_console_overlay() -> void:
	if not has_node("/root/Panku"):
		return
	_expect(not bool(Settings.get_defaults()["console_overlay"]), "por defecto la consola no se ve sobre el juego")
	Settings.set_value("console_overlay", true)
	_expect(DevTools.is_console_overlay_shown(), "con la opción, los renglones de la consola quedan a la vista")
	Settings.set_value("console_overlay", false)
	_expect(not DevTools.is_console_overlay_shown(), "sin la opción, solo se ven con la consola abierta")
	var options := OptionsList.new()
	add_child(options)
	_expect(options.get_toggle("console_overlay").visible, "Ajustes muestra la opción cuando hay consola")
	options.queue_free()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)


func _check_monitors() -> void:
	_new_game()
	var labels: Array[String] = DevTools.get_monitor_sources().keys()
	for label: String in labels:
		var id := StringName("%s/%s" % [DevTools.MONITOR_GROUP, label])
		_expect(Performance.has_custom_monitor(id), "monitor registrado: %s" % id)
	var balance_id := StringName("%s/Saldo" % DevTools.MONITOR_GROUP)
	_expect(int(Performance.get_custom_monitor(balance_id)) == Economy.balance,
		"el monitor Saldo lee Economy.balance: %s" % Performance.get_custom_monitor(balance_id))
	var mood_id := StringName("%s/Ánimo medio" % DevTools.MONITOR_GROUP)
	_expect(is_zero_approx(float(Performance.get_custom_monitor(mood_id))), "sin empleados, ánimo medio 0")


func _check_console() -> void:
	var console: Node = get_node_or_null("/root/Panku")
	_expect(console != null, "la consola Panku está cargada")
	if console == null:
		return
	var env: Object = console.get("gd_exprenv")
	var result: Dictionary = env.call("execute", "qo.add_money(1)")
	_expect(not bool(result.get("failed", true)), "la consola ejecuta qo.add_money: %s" % result)


func _check_commands() -> void:
	_new_game()
	var commands: DevCommands = DevTools.commands
	var balance: int = Economy.balance
	commands.add_money(5000)
	_expect(Economy.balance == balance + 5000, "add_money suma: %d" % Economy.balance)
	commands.add_money(-2000)
	_expect(Economy.balance == balance + 3000, "add_money negativo cobra: %d" % Economy.balance)
	_expect(Economy.movements[-1]["concept"] == DevCommands.CONCEPT_CONSOLE, "el movimiento dice que vino de la consola")

	var day: int = GameClock.get_day_count()
	commands.skip_days(2)
	_expect(GameClock.get_day_count() == day + 2, "skip_days(2) adelanta 2 días: %d → %d" % [day, GameClock.get_day_count()])

	# Empleados reales: la empresa inicial de demostración.
	SaveManager.start_with_demo = true
	_new_game()
	SaveManager.start_with_demo = false
	_expect(not Staff.employees.is_empty(), "la empresa inicial trae empleados")
	commands.set_mood(150)
	commands.set_stress(-5)
	commands.set_energy(40)
	var ok: bool = true
	for employee: Dictionary in Staff.employees:
		ok = ok and int(employee["mood"]) == 100 and int(employee["stress"]) == 0 and int(employee["energy"]) == 40
	_expect(ok, "set_mood/set_stress/set_energy fijan y limitan las barras de todos")
	var mood_id := StringName("%s/Ánimo medio" % DevTools.MONITOR_GROUP)
	_expect(is_equal_approx(float(Performance.get_custom_monitor(mood_id)), 100.0), "el monitor Ánimo medio lo refleja")
	_expect(commands.help().contains("skip_days"), "help lista los comandos")
