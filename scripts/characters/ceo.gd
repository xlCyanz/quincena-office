# El CEO: un personaje de la oficina con camisa blanca y corbata roja. No tiene
# horario: llega solo a su hora en días hábiles y se queda hasta que el jugador lo
# manda a casa (Staff.ceo_at_work). Su silla es la asignada a "ceo".
class_name Ceo
extends OfficeCharacter


func _init() -> void:
	person_key = "ceo"
	display_name = "El CEO"
	shirt_color = Color("e8e4dc")
	tie_color = Color("b03a2e")
