# Comandos de la consola Panku (`qo.add_money(50000)`): dinero, tiempo y barras de los empleados.
# Usan las funciones públicas de los sistemas. DevTools no los registra en release.
class_name DevCommands
extends RefCounted

## Concepto con que aparecen en el Banco los movimientos hechos desde la consola.
const CONCEPT_CONSOLE: String = "Consola de desarrollo"
const HOURS_PER_DAY: int = 24
const BAR_MIN: int = 0
const BAR_MAX: int = 100

## Textos de ayuda: Panku los muestra como pista al escribir `qo.` (convención _HELP_<función>).
const _HELP_help: String = "Muestra la lista de comandos."
const _HELP_add_money: String = "add_money(cantidad): suma (o resta, si es negativa) dinero a la cuenta."
const _HELP_skip_hours: String = "skip_hours(horas): adelanta el reloj esas horas, como si pasaran jugando."
const _HELP_skip_days: String = "skip_days(días): adelanta el reloj esos días completos."
const _HELP_set_mood: String = "set_mood(valor): fija el ánimo (0–100) de todos los empleados."
const _HELP_set_stress: String = "set_stress(valor): fija el estrés (0–100) de todos los empleados."
const _HELP_set_energy: String = "set_energy(valor): fija la energía (0–100) de todos los empleados."
const _HELP_event: String = "event(id): abre la tarjeta de ese evento (blackout, tax, dirty_office, scope_change… ver data/events.json)."


## Lista de comandos disponibles.
func help() -> String:
	return "\n".join([
		"Comandos de Quincena Office (qo.):",
		_HELP_add_money, _HELP_skip_hours, _HELP_skip_days,
		_HELP_set_mood, _HELP_set_stress, _HELP_set_energy, _HELP_event,
	])


## Suma dinero a la cuenta; con una cantidad negativa lo cobra.
func add_money(amount: int) -> String:
	if amount >= 0:
		Economy.earn(amount, CONCEPT_CONSOLE)
	else:
		Economy.charge(-amount, CONCEPT_CONSOLE)
	return "Saldo: $%d" % Economy.balance


## Adelanta el reloj hora por hora (cobra todo lo que toque).
func skip_hours(hours: int) -> String:
	GameClock.fast_forward_hours(maxi(hours, 0))
	return "Día %d, %02d:00" % [GameClock.get_day_count(), GameClock.get_hour()]


## Adelanta el reloj días completos.
func skip_days(days: int) -> String:
	return skip_hours(maxi(days, 0) * HOURS_PER_DAY)


## Fija el ánimo de todos los empleados.
func set_mood(value: int) -> String:
	return _set_bar("mood", value)


## Fija el estrés de todos los empleados.
func set_stress(value: int) -> String:
	return _set_bar("stress", value)


## Fija la energía de todos los empleados.
func set_energy(value: int) -> String:
	return _set_bar("energy", value)


## Abre la tarjeta de un evento.
func event(event_id: String) -> String:
	if Events.trigger(event_id):
		return "Evento %s abierto." % event_id
	return "No se abrió: ya hay una tarjeta o «%s» no existe." % event_id


func _set_bar(key: String, value: int) -> String:
	var clamped: int = clampi(value, BAR_MIN, BAR_MAX)
	for employee: Dictionary in Staff.employees:
		employee[key] = clamped
	EventBus.staff_changed.emit()
	return "%s = %d en %d empleados" % [key, clamped, Staff.employees.size()]
