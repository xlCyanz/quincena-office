# Economía: saldo de la cuenta empresarial, cobros y pagos.
# Hito 3: el capital inicial. Los cobros y pagos llegan en los hitos 5 y 8.
extends Node

## Saldo de la cuenta empresarial, en dólares enteros.
var balance: int = 0


## Prepara la economía de una partida nueva.
func new_game() -> void:
	balance = GameConstants.STARTING_CAPITAL


## Devuelve el estado de la economía para guardarlo (hito 9).
func export_state() -> Dictionary:
	return {"balance": balance}


## Restaura el estado de la economía desde una partida guardada (hito 9).
func import_state(state: Dictionary) -> void:
	balance = int(state.get("balance", 0))
