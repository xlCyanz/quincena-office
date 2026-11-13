# Revisión de una exportación (hito 66): se corre sobre el .pck exportado, fuera del proyecto:
#   Godot --headless --main-pack build/linux/quincena_office.pck -s <ruta absoluta>/tests/export_check.gd
# (tests/export_desktop.sh lo hace con cada plataforma). Mira que el paquete no traiga las
# herramientas de desarrollo ni sus autoloads, que estén los sistemas del juego y sus datos, y
# que el menú principal cargue. Imprime «EXPORTACIÓN: OK» y sale con 0, o los fallos y 1.
extends SceneTree

const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
## Autoloads del juego (los de project.godot sin los de desarrollo).
const GAME_AUTOLOADS: Array[String] = [
	"EventBus", "Settings", "GameClock", "Economy", "OfficeState", "Staff", "Projects", "Products", "Bank",
	"Company", "Events", "Tutorial", "SaveManager",
]
const DEV_AUTOLOADS: Array[String] = ["Panku", "DevTools"]
## Archivos que no deben viajar.
const EXCLUDED_FILES: Array[String] = [
	"res://addons/panku_console/console.tscn", "res://scripts/debug/dev_tools.gd", "res://scripts/debug/dev_commands.gd",
	"res://tests/test_all.tscn", "res://addons/quincena_export/plugin.gd",
]
## Datos que el juego lee con FileAccess (si faltan, la partida no arranca).
const DATA_FILES: Array[String] = [
	"res://data/settings.json", "res://data/staff.json", "res://data/contracts.json", "res://data/furniture.json",
	"res://data/tutorial.json", "res://data/help.json", "res://data/starting_office.json",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("FALLO: " + message)


func _run() -> void:
	for autoload_name: String in DEV_AUTOLOADS:
		_expect(not ProjectSettings.has_setting("autoload/" + autoload_name), "el paquete trae el autoload %s" % autoload_name)
		_expect(root.get_node_or_null(autoload_name) == null, "se cargó %s" % autoload_name)
	for autoload_name: String in GAME_AUTOLOADS:
		_expect(root.get_node_or_null(autoload_name) != null, "falta el sistema %s" % autoload_name)
	for path: String in EXCLUDED_FILES:
		_expect(not ResourceLoader.exists(path) and not FileAccess.file_exists(path), "el paquete trae %s" % path)
	for path: String in DATA_FILES:
		_expect(not FileAccess.get_file_as_string(path).is_empty(), "falta el dato %s" % path)
	_expect(ProjectSettings.get_setting("application/config/name") == "Quincena Office", "el nombre del juego")
	_expect(String(ProjectSettings.get_setting("application/run/main_scene")) == MENU_SCENE_PATH, "la escena inicial es el menú")
	# El menú principal carga y muestra sus botones.
	_expect(change_scene_to_file(MENU_SCENE_PATH) == OK, "no se pudo abrir el menú principal")
	for i: int in range(5):
		await process_frame
	var menu: Node = current_scene
	_expect(menu != null and menu.scene_file_path == MENU_SCENE_PATH, "no llegó al menú principal")
	if menu != null:
		var buttons: Array[Node] = menu.find_children("*", "Button", true, false)
		_expect(buttons.size() >= 4, "el menú principal tiene %d botones" % buttons.size())
	if _failures.is_empty():
		print("EXPORTACIÓN: OK")
	else:
		print("EXPORTACIÓN: FALLO (%d)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
