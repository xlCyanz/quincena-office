# Guardado y carga: reúne el export_state() de cada sistema en un archivo y lo
# reparte con import_state() al cargar (hito 9). También prepara una partida nueva.
extends Node


## Deja todos los sistemas como al empezar una partida nueva: el local inicial con
## la Oficina Ejecutiva, el capital inicial y el reloj en el día 1 a la hora de entrada.
func new_game() -> void:
	Economy.new_game()
	OfficeState.new_game()
	GameClock.new_game()
