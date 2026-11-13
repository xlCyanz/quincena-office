# Plugin del editor (hito 66): al exportar quita los autoloads de las herramientas de
# desarrollo, porque los presets de export_presets.cfg excluyen sus archivos
# (addons/panku_console/* y scripts/debug/*). Sin esto la exportación arrancaría con un
# autoload que apunta a un archivo que no está. Al terminar los vuelve a poner.
# Solo corre en el editor; los presets también excluyen esta carpeta.
@tool
extends EditorPlugin

## Autoloads de desarrollo que no viajan en ninguna exportación: nombre → ruta.
const DEV_AUTOLOADS: Dictionary[String, String] = {
	"Panku": "res://addons/panku_console/console.tscn",
	"DevTools": "res://scripts/debug/dev_tools.gd",
}

var _exporter: DevToolsExporter


class DevToolsExporter extends EditorExportPlugin:
	var owner: EditorPlugin
	# Autoloads quitados en esta exportación, en su orden, para devolverlos al terminar.
	var _removed: Array[String] = []


	func _get_name() -> String:
		return "QuincenaExport"


	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		_removed.clear()
		for autoload_name: String in DEV_AUTOLOADS:
			if ProjectSettings.has_setting("autoload/" + autoload_name):
				owner.remove_autoload_singleton(autoload_name)
				_removed.append(autoload_name)


	func _export_end() -> void:
		for autoload_name: String in _removed:
			if not ProjectSettings.has_setting("autoload/" + autoload_name):
				owner.add_autoload_singleton(autoload_name, DEV_AUTOLOADS[autoload_name])
		_removed.clear()


func _enter_tree() -> void:
	_exporter = DevToolsExporter.new()
	_exporter.owner = self
	add_export_plugin(_exporter)


func _exit_tree() -> void:
	remove_export_plugin(_exporter)
	_exporter = null
