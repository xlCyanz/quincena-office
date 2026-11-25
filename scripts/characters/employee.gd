# Un empleado: sigue su horario (Staff.is_expected) hasta la silla de su puesto.
class_name Employee
extends OfficeCharacter

# Tonos de piel y pelo provisionales; cada uno toma uno según su id.
const SKIN_TONES: Array[Color] = [Color("f1c7a1"), Color("d9a47a"), Color("b07a52"), Color("7a4e32")]
const HAIR_TONES: Array[Color] = [Color("3b2a20"), Color("1e1a18"), Color("8a5a2b"), Color("c9a45c"), Color("6b3a2a")]

## Cargos de traje y de oficina; los demás, de oficina uno de cada tres y si no casual.
const EXECUTIVE_ROLES: Array[String] = ["manager", "executive"]
## El personal de limpieza lleva su uniforme (overol verde).
const CLEANING_ROLE: String = "cleaner"
const OFFICE_ROLES: Array[String] = ["team_leader", "salesperson", "accountant", "receptionist"]

var employee_id: int = 0


## Toma los datos de un empleado de Staff.employees.
func configure(employee: Dictionary) -> void:
	employee_id = employee["id"]
	person_key = Staff.employee_key(employee_id)
	display_name = employee["name"]
	shirt_color = StaffCatalog.get_shirt_color(employee["role"])
	skin_color = SKIN_TONES[employee_id % SKIN_TONES.size()]
	hair_color = HAIR_TONES[(employee_id * 7) % HAIR_TONES.size()]
	look = look_for(employee)
	queue_redraw()


## Pone la camisa del color de su cargo (cambia al ascender).
func update_role(employee: Dictionary) -> void:
	look = look_for(employee)
	var color: Color = StaffCatalog.get_shirt_color(employee["role"])
	if color != shirt_color:
		shirt_color = color
		queue_redraw()


## Aspecto de un empleado: ropa según su cargo y paleta según su id (también lo usa su foto).
static func look_for(employee: Dictionary) -> String:
	var role: String = String(employee["role"])
	var id: int = int(employee["id"])
	var outfit: String = "casual"
	if role == CLEANING_ROLE:
		outfit = "cleaning"
	elif EXECUTIVE_ROLES.has(role):
		outfit = "executive"
	elif OFFICE_ROLES.has(role) or id % 3 == 0:
		outfit = "office"
	return make_look(is_woman_name(String(employee["name"])), outfit, id * 7)
