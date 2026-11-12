# Economía: la cuenta empresarial (diseño, 8.1). Hay una sola cuenta con todo el
# dinero: ahí entran los cobros y de ahí salen las compras y los gastos mensuales.
# Cada cambio del saldo se avisa con EventBus.balance_changed y queda en el historial
# de movimientos, que muestra el menú Banco (hito 20). Aparte del historial (que guarda
# solo los últimos MAX_MOVEMENTS) se llevan los totales por concepto del mes actual y
# del anterior, para que el resumen del mes no dependa de lo que se recorta.
#
# El día 1 de cada mes cobra el mantenimiento del local (13.1) y el de los racks de
# servidores (13.5, hito 40), los dos con el descuento del contador. La partida empieza el
# día 1 del mes 1, así que el primer cobro llega el día 1 del mes 2.
extends Node

## Concepto de los movimientos de la cuenta.
const CONCEPT_MAINTENANCE: String = "Mantenimiento del local"
const CONCEPT_SERVERS: String = "Mantenimiento de servidores"
const CONCEPT_PURCHASE: String = "Compras"
const CONCEPT_SALE: String = "Ventas"

## Movimientos que se guardan en el historial (los más viejos se descartan).
const MAX_MOVEMENTS: int = 200

## Saldo de la cuenta empresarial, en dólares enteros. Puede quedar negativo si un
## gasto obligatorio (como el mantenimiento) llega sin dinero; las compras no.
var balance: int = 0

## Historial: cada movimiento es {"day": int, "month": int, "concept": String,
## "amount": int}; amount es negativo si sale dinero.
var movements: Array[Dictionary] = []

## Totales por concepto: mes → {concepto: monto}. Solo el mes actual y el anterior.
var month_totals: Dictionary[int, Dictionary] = {}

# Fecha actual según los avisos del reloj (EventBus.day_changed).
var _day: int = 1
var _month: int = 1


func _ready() -> void:
	EventBus.day_changed.connect(_on_day_changed)


## Prepara la economía de una partida nueva.
func new_game() -> void:
	movements.clear()
	month_totals.clear()
	_day = 1
	_month = 1
	_set_balance(GameConstants.STARTING_CAPITAL)


## Indica si alcanza el dinero para pagar amount.
func can_afford(amount: int) -> bool:
	return amount <= balance


## Cobra amount si alcanza el saldo. Devuelve false (y no cobra) si no alcanza.
func spend(amount: int, concept: String = CONCEPT_PURCHASE) -> bool:
	if not can_afford(amount):
		return false
	_add_movement(concept, -amount)
	return true


## Suma amount al saldo (por ejemplo, lo que se recupera al vender).
func earn(amount: int, concept: String = CONCEPT_SALE) -> void:
	_add_movement(concept, amount)


## Cobra un gasto obligatorio aunque no alcance el saldo (puede quedar negativo).
func charge(amount: int, concept: String) -> void:
	_add_movement(concept, -amount)


## Mes actual de la cuenta (desde el inicio de la partida, empezando en 1).
func get_current_month() -> int:
	return _month


## Totales por concepto de un mes (solo el actual y el anterior; otro da {}).
func get_month_totals(month: int) -> Dictionary[String, int]:
	var totals: Dictionary[String, int] = {}
	var saved: Dictionary = month_totals.get(month, {})
	for concept: String in saved:
		totals[concept] = int(saved[concept])
	return totals


## Mantenimiento mensual de un local de area m².
static func get_maintenance(area: int) -> int:
	return area * GameConstants.MAINTENANCE_PER_M2


## Mantenimiento de este local con el descuento del contador (hito 37).
func get_monthly_maintenance() -> int:
	var base: int = get_maintenance(OfficeState.lot.get_area())
	return roundi(base * (1.0 - Staff.get_maintenance_discount()))


## Mantenimiento de los racks de servidores de un mes, con el descuento del contador.
func get_monthly_server_cost() -> int:
	return roundi(OfficeState.get_furniture_monthly_cost() * (1.0 - Staff.get_maintenance_discount()))


func _on_day_changed(day: int, month: int) -> void:
	_day = day
	_month = month
	_drop_old_months()
	if day == 1:
		# Lee el tamaño del local y el descuento del contador (solo lectura).
		charge(get_monthly_maintenance(), CONCEPT_MAINTENANCE)
		EventBus.payment_recorded.emit(CONCEPT_MAINTENANCE, balance >= 0)
		charge(get_monthly_server_cost(), CONCEPT_SERVERS)


func _add_movement(concept: String, amount: int) -> void:
	if amount == 0:
		return
	movements.append({"day": _day, "month": _month, "concept": concept, "amount": amount})
	_add_to_totals(_month, concept, amount)
	if movements.size() > MAX_MOVEMENTS:
		movements.pop_front()
	_set_balance(balance + amount)


func _add_to_totals(month: int, concept: String, amount: int) -> void:
	if not month_totals.has(month):
		month_totals[month] = {}
	var totals: Dictionary = month_totals[month]
	totals[concept] = int(totals.get(concept, 0)) + amount


# Deja solo el mes actual y el anterior.
func _drop_old_months() -> void:
	for month: int in month_totals.keys():
		if month < _month - 1:
			month_totals.erase(month)


func _set_balance(value: int) -> void:
	balance = value
	EventBus.balance_changed.emit(balance)


## Devuelve el estado de la economía para guardarlo (hito 9).
func export_state() -> Dictionary:
	var totals: Array[Dictionary] = []
	for month: int in month_totals:
		totals.append({"month": month, "concepts": month_totals[month].duplicate()})
	return {"balance": balance, "movements": movements.duplicate(true), "day": _day, "month": _month,
		"month_totals": totals}


## Restaura el estado de la economía desde una partida guardada (hito 9).
func import_state(state: Dictionary) -> void:
	movements.clear()
	for movement: Dictionary in state.get("movements", []):
		movements.append({"day": int(movement["day"]), "month": int(movement["month"]),
			"concept": String(movement["concept"]), "amount": int(movement["amount"])})
	_day = int(state.get("day", 1))
	_month = int(state.get("month", 1))
	month_totals.clear()
	if state.has("month_totals"):
		for saved: Dictionary in state["month_totals"]:
			var concepts: Dictionary = saved.get("concepts", {})
			for concept: String in concepts:
				_add_to_totals(int(saved.get("month", 0)), concept, int(concepts[concept]))
	else:
		# Partidas de antes del hito 20: se rearman con el historial.
		for movement: Dictionary in movements:
			_add_to_totals(int(movement["month"]), movement["concept"], int(movement["amount"]))
	_drop_old_months()
	_set_balance(int(state.get("balance", 0)))
