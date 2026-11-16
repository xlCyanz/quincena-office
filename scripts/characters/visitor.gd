# Cliente que visita la Recepción: entra, espera (sofá o casilla libre) y se va al ser
# atendido o cansarse. Lo maneja la escena a partir de Projects.visits.
class_name Visitor
extends OfficeCharacter

const SUIT_COLOR := Color("5b6170")
const TIE_COLOR := Color("2d6a9f")
const CANDIDATE_SHIRT_COLOR := Color("8fb8a0")

## Id de la visita (el de su oferta).
var visit_id: int = 0


## Toma los datos de una visita de Projects.visits.
func configure(visit: Dictionary) -> void:
	visit_id = visit["id"]
	person_key = "visitor_%d" % visit_id
	display_name = "Cliente de %s" % visit["offer"]["client"]
	shirt_color = SUIT_COLOR
	tie_color = TIE_COLOR
	can_type = false
	look = make_look(visit_id % 2 == 1, "executive" if (visit_id >> 1) % 2 == 0 else "office", visit_id)
	queue_redraw()


## Candidato que viene a su entrevista (va frente al escritorio de quien entrevista).
func configure_candidate(candidate: Dictionary) -> void:
	visit_id = -int(candidate["id"])
	person_key = "candidate_%d" % int(candidate["id"])
	display_name = "Candidato %s" % candidate["name"]
	shirt_color = CANDIDATE_SHIRT_COLOR
	tie_color = Color(0.0, 0.0, 0.0, 0.0)
	standing = true
	can_type = false
	look = make_look(String(candidate.get("sex", "")) == "female", "office", int(candidate["id"]))
	queue_redraw()
