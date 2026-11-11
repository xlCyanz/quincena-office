# Estado de la oficina: casillas, paredes, muebles y habitaciones, en coordenadas de cuadrícula.
# Se construye entre los hitos 1 y 7 (cuadrícula, construcción, muebles y habitaciones).
extends Node


## Devuelve el estado de la oficina para guardarlo (hito 9).
func export_state() -> Dictionary:
	return {}


## Restaura el estado de la oficina desde una partida guardada (hito 9).
func import_state(_state: Dictionary) -> void:
	pass
