# Un empleado: personaje de la oficina con la camisa del color de su cargo. Sigue su
# horario (Staff.is_expected) hasta la silla de su puesto.
class_name Employee
extends OfficeCharacter

# Tonos de piel y pelo provisionales; cada empleado toma uno según su id.
const SKIN_TONES: Array[Color] = [Color("f1c7a1"), Color("d9a47a"), Color("b07a52"), Color("7a4e32")]
const HAIR_TONES: Array[Color] = [Color("3b2a20"), Color("1e1a18"), Color("8a5a2b"), Color("c9a45c"), Color("6b3a2a")]

var employee_id: int = 0


## Toma los datos de un empleado de Staff.employees.
func configure(employee: Dictionary) -> void:
	employee_id = employee["id"]
	person_key = Staff.employee_key(employee_id)
	display_name = employee["name"]
	shirt_color = StaffCatalog.get_shirt_color(employee["role"])
	skin_color = SKIN_TONES[employee_id % SKIN_TONES.size()]
	hair_color = HAIR_TONES[(employee_id * 7) % HAIR_TONES.size()]
	queue_redraw()
