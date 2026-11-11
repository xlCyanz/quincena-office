# Economía: la cuenta empresarial (diseño, 8.1). Hay una sola cuenta con todo el
# dinero: ahí entran los cobros y de ahí salen las compras y los gastos mensuales.
# Cada cambio del saldo se avisa con EventBus.balance_changed y queda en el historial
# de movimientos (el menú Banco lo mostrará en una fase siguiente).
#
# El día 1 de cada mes cobra el mantenimiento del local (13.1). La partida empieza el
# día 1 del mes 1, así que el primer cobro llega el día 1 del mes 2.
extends Node

## Concepto de los movimientos de la cuenta.
const CONCEPT_MAINTENANCE: String = "Mantenimiento del local"
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

# Fecha actual según los avisos del reloj (EventBus.day_changed).
var _day: int = 1
var _month: int = 1


func _ready() -> void:
	EventBus.day_changed.connect(_on_day_changed)


## Prepara la economía de una partida nueva.
func new_game() -> void:
	movements.clear()
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


## Mantenimiento mensual de un local de area m².
static func get_maintenance(area: int) -> int:
	return area * GameConstants.MAINTENANCE_PER_M2


func _on_day_changed(day: int, month: int) -> void:
	_day = day
	_month = month
	if day == 1:
		# Lee el tamaño del local del estado de la oficina (solo lectura).
		charge(get_maintenance(OfficeState.lot_rect.get_area()), CONCEPT_MAINTENANCE)


func _add_movement(concept: String, amount: int) -> void:
	if amount == 0:
		return
	movements.append({"day": _day, "month": _month, "concept": concept, "amount": amount})
	if movements.size() > MAX_MOVEMENTS:
		movements.pop_front()
	_set_balance(balance + amount)


func _set_balance(value: int) -> void:
	balance = value
	EventBus.balance_changed.emit(balance)


## Devuelve el estado de la economía para guardarlo (hito 9).
func export_state() -> Dictionary:
	return {"balance": balance, "movements": movements.duplicate(true), "day": _day, "month": _month}


## Restaura el estado de la economía desde una partida guardada (hito 9).
func import_state(state: Dictionary) -> void:
	movements.clear()
	for movement: Dictionary in state.get("movements", []):
		movements.append({"day": int(movement["day"]), "month": int(movement["month"]),
			"concept": String(movement["concept"]), "amount": int(movement["amount"])})
	_day = int(state.get("day", 1))
	_month = int(state.get("month", 1))
	_set_balance(int(state.get("balance", 0)))
