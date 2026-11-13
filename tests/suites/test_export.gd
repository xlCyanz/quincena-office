# Prueba del hito 66: exportación de escritorio.
# Criterio (lo que se puede ver sin exportar): hay presets de macOS, Windows y Linux que dejan
# fuera las herramientas de desarrollo; el plugin QuincenaExport quita sus autoloads de toda
# exportación; ningún archivo del juego depende de lo que se excluye; nombre, versión e icono
# propios. La exportación real y su arranque los mira tests/export_desktop.sh (necesita las
# plantillas de exportación; si faltan, esta parte lo avisa sin fallar).
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=export
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const PRESETS_PATH: String = "res://export_presets.cfg"
const PLUGIN_CFG: String = "res://addons/quincena_export/plugin.cfg"
const PLUGIN_SCRIPT: String = "res://addons/quincena_export/plugin.gd"
const GAME_NAME: String = "Quincena Office"
## Plataforma de cada preset → archivo de la plantilla de lanzamiento que necesita.
const PLATFORMS: Dictionary[String, String] = {
	"macOS": "macos.zip",
	"Windows Desktop": "windows_release_x86_64.exe",
	"Linux": "linux_release.x86_64",
}
## Lo que ninguna exportación lleva (ver CLAUDE.md, herramientas de desarrollo).
const REQUIRED_EXCLUDES: Array[String] = ["addons/panku_console/*", "scripts/debug/*", "tests/*", "addons/quincena_export/*"]
## Carpetas que no se revisan al buscar dependencias (caché, exportaciones, addons de terceros).
const SKIP_DIRS: Array[String] = [".godot", "build", ".git"]
## Color del logo de Godot: el icono por defecto lo usa, el propio no.
const GODOT_LOGO_COLOR: String = "#478cbf"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	var presets := ConfigFile.new()
	_expect(presets.load(PRESETS_PATH) == OK, "se lee export_presets.cfg")
	var excludes: Array[String] = _check_presets(presets)
	_check_plugin(excludes)
	_check_dependencies(excludes)
	_check_identity(presets)
	_check_templates()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _preset_sections(presets: ConfigFile) -> Array[String]:
	var sections: Array[String] = []
	for section: String in presets.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			sections.append(section)
	return sections


func _split_filter(text: String) -> Array[String]:
	var parts: Array[String] = []
	for part: String in text.split(",", false):
		parts.append(part.strip_edges())
	return parts


# Un preset por plataforma, ejecutable, a build/, con todos los recursos, los JSON de data/ y
# sin las herramientas. Devuelve lo que excluyen (igual en los tres).
func _check_presets(presets: ConfigFile) -> Array[String]:
	var sections: Array[String] = _preset_sections(presets)
	var platforms: Array[String] = []
	var excludes: Array[String] = []
	for section: String in sections:
		var platform: String = String(presets.get_value(section, "platform", ""))
		platforms.append(platform)
		var name: String = String(presets.get_value(section, "name", ""))
		var path: String = String(presets.get_value(section, "export_path", ""))
		_expect(bool(presets.get_value(section, "runnable", false)), "%s se puede ejecutar" % name)
		_expect(path.begins_with("build/") and path.get_file().to_lower().contains("quincena"),
			"%s exporta a build/ con el nombre del juego: %s" % [name, path])
		_expect(String(presets.get_value(section, "export_filter", "")) == "all_resources", "%s exporta todos los recursos" % name)
		_expect(_split_filter(String(presets.get_value(section, "include_filter", ""))).has("data/*.json"),
			"%s lleva los datos de data/" % name)
		var preset_excludes: Array[String] = _split_filter(String(presets.get_value(section, "exclude_filter", "")))
		for pattern: String in REQUIRED_EXCLUDES:
			_expect(preset_excludes.has(pattern), "%s excluye %s" % [name, pattern])
		if excludes.is_empty():
			excludes = preset_excludes
		_expect(preset_excludes == excludes, "%s excluye lo mismo que los demás" % name)
	platforms.sort()
	var wanted: Array[String] = PLATFORMS.keys()
	wanted.sort()
	_expect(platforms == wanted, "un preset por plataforma de escritorio: %s" % [platforms])
	return excludes


func _is_excluded(res_path: String, excludes: Array[String]) -> bool:
	var relative: String = res_path.trim_prefix("res://")
	for pattern: String in excludes:
		if relative.match(pattern):
			return true
	return false


# El plugin está activo y quita todo autoload cuyo archivo no viaja en la exportación.
func _check_plugin(excludes: Array[String]) -> void:
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	_expect(enabled.has(PLUGIN_CFG), "el plugin QuincenaExport está activo: %s" % [enabled])
	var source: String = FileAccess.get_file_as_string(PLUGIN_SCRIPT)
	_expect(source.contains("_export_begin") and source.contains("remove_autoload_singleton")
		and source.contains("_export_end") and source.contains("add_autoload_singleton"),
		"el plugin quita los autoloads al exportar y los devuelve al terminar")
	var stripped: Array[String] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var setting: String = String(property["name"])
		if not setting.begins_with("autoload/"):
			continue
		var autoload_name: String = setting.trim_prefix("autoload/")
		var path: String = String(ProjectSettings.get_setting(setting)).trim_prefix("*")
		if _is_excluded(path, excludes):
			stripped.append(autoload_name)
			_expect(source.contains("\"%s\": \"%s\"" % [autoload_name, path]),
				"el plugin quita el autoload %s (%s), que no viaja" % [autoload_name, path])
		else:
			_expect(ResourceLoader.exists(path), "el autoload %s del juego existe: %s" % [autoload_name, path])
	stripped.sort()
	_expect(stripped == (["DevTools", "Panku"] as Array[String]), "autoloads que se quitan al exportar: %s" % [stripped])


# Ningún archivo que viaja nombra lo que se excluye (rutas, DevTools, DevCommands ni la consola).
func _check_dependencies(excludes: Array[String]) -> void:
	var files: Array[String] = []
	_collect_files("res://", files)
	var shipped: Array[String] = files.filter(func(path: String) -> bool: return not _is_excluded(path, excludes))
	_expect(shipped.size() > 50 and shipped.has("res://scripts/main.gd") and shipped.has("res://scenes/main_menu.tscn"),
		"se revisan los archivos que viajan: %d" % shipped.size())
	var uses := RegEx.create_from_string("\\b(DevTools|DevCommands|PankuConsole)\\b|\\bPanku\\s*\\.|res://(addons/panku_console|scripts/debug|tests|addons/quincena_export)/")
	var offenders: Array[String] = []
	for path: String in shipped:
		var line_number: int = 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			line_number += 1
			if line.strip_edges().begins_with("#"):
				continue
			if uses.search(line) != null:
				offenders.append("%s:%d" % [path, line_number])
	_expect(offenders.is_empty(), "archivos del juego que dependen de lo excluido: %s" % [offenders.slice(0, 8)])


func _collect_files(dir_path: String, files: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if sub.begins_with(".") or SKIP_DIRS.has(sub):
			continue
		_collect_files(dir_path.path_join(sub), files)
	for file: String in dir.get_files():
		if file.get_extension() in ["gd", "tscn", "tres", "cfg", "json"] and dir_path.path_join(file) != PRESETS_PATH:
			files.append(dir_path.path_join(file))


# Nombre, versión e icono del juego, iguales en los presets.
func _check_identity(presets: ConfigFile) -> void:
	var version: String = String(ProjectSettings.get_setting("application/config/version", ""))
	_expect(ProjectSettings.get_setting("application/config/name") == GAME_NAME, "el juego se llama %s" % GAME_NAME)
	_expect(version.split(".").size() == 3, "el juego tiene versión: %s" % version)
	var icon_path: String = String(ProjectSettings.get_setting("application/config/icon", ""))
	var icon: Texture2D = load(icon_path) as Texture2D
	_expect(icon != null and icon.get_width() >= 128 and icon.get_height() == icon.get_width(), "el icono se carga y es cuadrado: %s" % icon_path)
	_expect(not FileAccess.get_file_as_string(icon_path).contains(GODOT_LOGO_COLOR), "el icono es propio, no el de Godot")
	for section: String in _preset_sections(presets):
		var options: String = section + ".options"
		match String(presets.get_value(section, "platform", "")):
			"macOS":
				_expect(presets.get_value(options, "application/short_version", "") == version
					and presets.get_value(options, "application/version", "") == version, "macOS lleva la versión del juego")
				_expect(String(presets.get_value(options, "application/bundle_identifier", "")).count(".") >= 2,
					"macOS tiene identificador de paquete")
				_expect(presets.get_value(options, "binary_format/architecture", "") == "universal", "macOS sale para Intel y Apple")
			"Windows Desktop":
				_expect(presets.get_value(options, "application/product_name", "") == GAME_NAME, "Windows lleva el nombre del juego")
				_expect(String(presets.get_value(options, "application/product_version", "")).begins_with(version),
					"Windows lleva la versión del juego")


# Las plantillas de exportación no son parte del proyecto: si faltan solo se avisa.
func _check_templates() -> void:
	var info: Dictionary = Engine.get_version_info()
	var folder: String = "%s.%s.%s.%s" % [info["major"], info["minor"], info["patch"], info["status"]]
	var dir: String = OS.get_data_dir().path_join("Godot/export_templates").path_join(folder)
	if OS.get_name() != "macOS" or not DirAccess.dir_exists_absolute(dir):
		print("AVISO: no están las plantillas de exportación de %s; tests/export_desktop.sh no puede exportar." % folder)
		return
	for platform: String in PLATFORMS:
		_expect(FileAccess.file_exists(dir.path_join(PLATFORMS[platform])), "está la plantilla de %s" % platform)
