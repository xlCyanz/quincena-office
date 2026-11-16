# El CEO: sin horario, llega a su hora en días hábiles y se queda hasta que el jugador lo
# manda a casa (Staff.ceo_at_work). Su silla es la asignada a "ceo".
class_name Ceo
extends OfficeCharacter


func _init() -> void:
	person_key = "ceo"
	display_name = "El CEO"
	shirt_color = Color("e8e4dc")
	tie_color = Color("b03a2e")
	look = "executive"
