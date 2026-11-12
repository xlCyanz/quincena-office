# Herramientas de desarrollo: monitores del depurador y comandos de la consola Panku.
# Solo trabaja en compilaciones de depuración (editor o exportación debug); en una
# exportación release no registra nada. No es parte del juego: es ayuda para probar y balancear.
#
# - Monitores: aparecen en el editor, en Depurador → Monitores, grupo «Quincena», mientras el
#   juego corre desde el editor. Se pueden graficar a 4x para ver el balance.
# - Comandos: en la consola Panku (tecla ` o ~) se escribe `qo.help()` para ver la lista.
extends Node

## Nombre con el que los comandos quedan disponibles en la consola Panku.
const CONSOLE_ENV_NAME: String = "qo"
## Grupo de los monitores en la pestaña Monitores del depurador.
const MONITOR_GROUP: String = "Quincena"

var commands: DevCommands = DevCommands.new()


func _ready() -> void:
	if not OS.is_debug_build():
		return
	_register_monitors()
	_register_console_commands()


## Valores que se registran como monitores: {"Nombre visible": Callable que devuelve un número}.
func get_monitor_sources() -> Dictionary[String, Callable]:
	return {
		"Saldo": func() -> int: return Economy.balance,
		"Deuda con el banco": func() -> int: return Bank.get_debt(),
		"Nómina por pagar": func() -> int: return Staff.get_total_owed(),
		"Valor de la empresa": func() -> int: return Company.get_value(),
		"Reputación": func() -> float: return Projects.reputation,
		"Empleados": func() -> int: return Staff.employees.size(),
		"Puntos por hora": _production_per_hour,
		"Ánimo medio": func() -> float: return _average("mood"),
		"Estrés medio": func() -> float: return _average("stress"),
		"Energía media": func() -> float: return _average("energy"),
		"Día de partida": func() -> int: return GameClock.get_day_count(),
	}


var _monitor_ids: Array[StringName] = []


# Al cerrar el juego hay que quitar los monitores: si Performance los sigue leyendo cuando
# los autoloads ya no existen, Godot se cae al salir (signal 11).
func _exit_tree() -> void:
	for id: StringName in _monitor_ids:
		if Performance.has_custom_monitor(id):
			Performance.remove_custom_monitor(id)
	_monitor_ids.clear()


func _register_monitors() -> void:
	var sources: Dictionary[String, Callable] = get_monitor_sources()
	for label: String in sources:
		var id: StringName = StringName("%s/%s" % [MONITOR_GROUP, label])
		if not Performance.has_custom_monitor(id):
			Performance.add_custom_monitor(id, sources[label])
			_monitor_ids.append(id)


# La consola es otro autoload (Panku). Se busca por ruta para no depender de él al compilar:
# si se quita el addon, el juego sigue funcionando sin comandos.
func _register_console_commands() -> void:
	var console: Node = get_node_or_null("/root/Panku")
	if console == null:
		return
	var env: Object = console.get("gd_exprenv")
	if env != null and env.has_method("register_env"):
		env.call("register_env", CONSOLE_ENV_NAME, commands)


# Puntos por hora que suman ahora todos los contratos en curso.
func _production_per_hour() -> float:
	var total: float = 0.0
	for contract: Dictionary in Projects.contracts:
		total += Projects.get_hourly_rate(contract)
	return total


# Promedio de una barra (0–100) entre los empleados; 0 si no hay ninguno.
func _average(key: String) -> float:
	if Staff.employees.is_empty():
		return 0.0
	var total: float = 0.0
	for employee: Dictionary in Staff.employees:
		total += float(employee.get(key, 0))
	return total / Staff.employees.size()
