# Economía: saldo de la cuenta empresarial, cobros y pagos.
# Hito 3: el capital inicial; hito 5: compras y ventas de la construcción.
# Cada cambio del saldo se avisa con EventBus.balance_changed.
extends Node

## Saldo de la cuenta empresarial, en dólares enteros.
var balance: int = 0


## Prepara la economía de una partida nueva.
func new_game() -> void:
	_set_balance(GameConstants.STARTING_CAPITAL)


## Indica si alcanza el dinero para pagar amount.
func can_afford(amount: int) -> bool:
	return amount <= balance


## Cobra amount si alcanza el saldo. Devuelve false (y no cobra) si no alcanza.
## Un amount negativo es un ingreso.
func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	_set_balance(balance - amount)
	return true


## Suma amount al saldo (por ejemplo, lo que se recupera al vender).
func earn(amount: int) -> void:
	_set_balance(balance + amount)


func _set_balance(value: int) -> void:
	balance = value
	EventBus.balance_changed.emit(balance)


## Devuelve el estado de la economía para guardarlo (hito 9).
func export_state() -> Dictionary:
	return {"balance": balance}


## Restaura el estado de la economía desde una partida guardada (hito 9).
func import_state(state: Dictionary) -> void:
	_set_balance(int(state.get("balance", 0)))
