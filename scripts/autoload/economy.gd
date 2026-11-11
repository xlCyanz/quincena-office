# Economía: saldo de la cuenta empresarial, cobros y pagos.
# Se implementa en el hito 8 (el hito 3 fija el capital inicial y el 5 empieza a cobrar).
extends Node


## Devuelve el estado de la economía para guardarlo (hito 9).
func export_state() -> Dictionary:
	return {}


## Restaura el estado de la economía desde una partida guardada (hito 9).
func import_state(_state: Dictionary) -> void:
	pass
