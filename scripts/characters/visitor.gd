# Un cliente que visita la Recepción (hito 36): entra por la entrada, espera en su lugar
# (un sofá de espera o una casilla libre de la Recepción) y se va cuando lo atienden o
# se cansa de esperar. Lo maneja la escena de juego a partir de Projects.visits.
class_name Visitor
extends OfficeCharacter

const SUIT_COLOR := Color("5b6170")
const TIE_COLOR := Color("2d6a9f")

## Id de la visita (el de su oferta) en Projects.visits.
var visit_id: int = 0


## Toma los datos de una visita de Projects.visits.
func configure(visit: Dictionary) -> void:
	visit_id = visit["id"]
	person_key = "visitor_%d" % visit_id
	display_name = "Cliente de %s" % visit["offer"]["client"]
	shirt_color = SUIT_COLOR
	tie_color = TIE_COLOR
	queue_redraw()
