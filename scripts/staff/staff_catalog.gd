# Cargos, niveles, sueldos y valores de contratación leídos de data/staff.json, y
# nombres y rasgos de data/names.json, una sola vez. Se usa por su nombre de clase,
# por ejemplo StaffCatalog.get_salary("programmer", "junior").
class_name StaffCatalog
extends RefCounted

const STAFF_PATH: String = "res://data/staff.json"
const NAMES_PATH: String = "res://data/names.json"

static var _staff: Dictionary = {}
static var _names: Dictionary = {}


## Ids de los cargos que se pueden pedir en una vacante, en el orden del archivo.
static func get_role_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_staff_data()["roles"].keys())
	return ids


## Ids de los niveles, de Pasante a Senior.
static func get_level_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_staff_data()["levels"].keys())
	return ids


## Ids de las habilidades (programming, design, testing, sales, leadership).
static func get_skill_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_staff_data()["skills"].keys())
	return ids


static func get_role_name(role: String) -> String:
	return String(_staff_data()["roles"].get(role, {}).get("name", role))


static func get_level_name(level: String) -> String:
	return String(_staff_data()["levels"].get(level, {}).get("name", level))


static func get_skill_name(skill: String) -> String:
	return String(_staff_data()["skills"].get(skill, skill))


## Habilidad principal de un cargo (la que usa para trabajar).
static func get_main_skill(role: String) -> String:
	return String(_staff_data()["roles"][role]["main_skill"])


## Sueldo mensual de la tabla (diseño, 13.2) para un cargo y un nivel.
static func get_salary(role: String, level: String) -> int:
	var data: Dictionary = _staff_data()["roles"][role]
	if data.has("fixed_salary"):
		return int(data["fixed_salary"])
	var salaries: Array = data["salaries"]
	return int(salaries[get_level_ids().find(level)])


## Lo que pide ascender a un nivel: {"projects", "days"}, o vacío si nadie asciende a él.
static func get_promotion(level: String) -> Dictionary:
	var promotion: Dictionary = _staff_data().get("promotion", {}).get(level, {})
	if promotion.is_empty():
		return {}
	return {"projects": int(promotion.get("projects", 0)), "days": int(promotion.get("days", 0))}


## Nivel siguiente (de Pasante a Senior), o "" si ya es el más alto.
static func get_next_level(level: String) -> String:
	var levels: Array[String] = get_level_ids()
	var index: int = levels.find(level)
	return levels[index + 1] if index >= 0 and index + 1 < levels.size() else ""


## Indica si un cargo tiene niveles (los de sueldo fijo no los tienen).
static func has_levels(role: String) -> bool:
	return not _staff_data()["roles"].get(role, {}).has("fixed_salary")


## Etapa de la empresa (índice) desde la que existe un cargo.
static func get_role_min_stage(role: String) -> int:
	return int(_staff_data()["roles"].get(role, {}).get("min_stage", 0))


## Nombre de un cargo con su nivel ("Programador Junior") o solo el cargo si no tiene
## niveles ("Líder de equipo").
static func describe_title(role: String, level: String) -> String:
	if not has_levels(role):
		return get_role_name(role)
	return "%s %s" % [get_role_name(role), get_level_name(level)]


## Tipo de habitación donde trabaja un cargo (work_area si no dice otra cosa).
static func get_workplace(role: String) -> String:
	return String(_staff_data()["roles"].get(role, {}).get("workplace", Workstations.WORK_AREA))


## Valor de data/staff.json, management (gerentes y escalera de cargos).
static func get_management(key: String) -> Variant:
	return _staff_data()["management"][key]


## Cargo al que asciende alguien: un Senior (de un cargo con niveles) al primero de la
## escalera de dirección y cada cargo de la escalera al siguiente; "" si no hay.
static func get_next_role(role: String, level: String) -> String:
	var ladder: Array = get_management("ladder")
	if has_levels(role):
		return String(ladder[0]) if get_next_level(level).is_empty() else ""
	var index: int = ladder.find(role)
	return String(ladder[index + 1]) if index >= 0 and index + 1 < ladder.size() else ""


## Valor de data/staff.json, departments.
static func get_departments(key: String) -> Variant:
	return _staff_data()["departments"][key]


## Ids de los departamentos, en orden.
static func get_department_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(get_departments("order"))
	return ids


static func get_department_name(department: String) -> String:
	return String(get_departments("names").get(department, department))


## Departamento de un cargo, o "" (líderes, gerentes y ejecutivos no son de ninguno).
static func get_role_department(role: String) -> String:
	return String(get_departments("roles").get(role, ""))


## Cargo de ejecutivo.
static func get_executive_role() -> String:
	return String(get_departments("executive_role"))


## Cargo de gerente.
static func get_manager_role() -> String:
	return String(get_management("manager_role"))


## Cargo de líder de equipo.
static func get_leader_role() -> String:
	return String(get_teams("leader_role"))


## Horario por defecto de un cargo: {"days", "start_hour", "end_hour"} (ver WorkSchedule).
static func get_role_schedule(role: String) -> Dictionary:
	return WorkSchedule.from_dict(_staff_data()["roles"][role].get("schedule", {})).to_dict()


## Color de camisa de un cargo (arte provisional).
static func get_shirt_color(role: String) -> Color:
	return Color(String(_staff_data()["roles"].get(role, {}).get("shirt_color", "888888")))


## Valor de la jornada (data/staff.json, workday): lunch_offset, start_energy, …
static func get_workday(key: String) -> Variant:
	return _staff_data()["workday"][key]


## Valor de los equipos y sus turnos (data/staff.json, teams).
static func get_teams(key: String) -> Variant:
	return _staff_data()["teams"][key]


## Días de la semana con que empieza el turno de un equipo nuevo.
static func get_default_team_days() -> Array[int]:
	var days: Array[int] = []
	for day: Variant in _staff_data()["teams"]["default_days"]:
		days.append(int(day))
	return days


## Valor de la nómina y los despidos (data/staff.json, payroll).
static func get_payroll(key: String) -> int:
	return int(_staff_data()["payroll"][key])


## Valor del ánimo, el estrés, las renuncias y los aumentos (data/staff.json, morale).
static func get_morale(key: String) -> float:
	return float(_staff_data()["morale"][key])


## Valor de la producción (data/staff.json, production).
static func get_production(key: String) -> Variant:
	return _staff_data()["production"][key]


## Puntos por hora de trabajo de un nivel (diseño, 13.3).
static func get_points_per_hour(level: String) -> float:
	return float(_staff_data()["production"]["points_per_hour"].get(level, 0.0))


## Hora a la que el CEO se queda dormido si sigue en la oficina.
static func get_ceo_sleep_hour() -> int:
	return int(_staff_data()["ceo"]["sleep_hour"])


## Hora a la que llega solo el CEO (data/staff.json, ceo.arrival_hour).
static func get_ceo_arrival_hour() -> int:
	return int(_staff_data()["ceo"]["arrival_hour"])


## Días de la semana (0 = lunes) en que el CEO llega solo.
static func get_ceo_arrival_days() -> Array[int]:
	var days: Array[int] = []
	for day: Variant in _staff_data()["ceo"]["arrival_days"]:
		days.append(int(day))
	return days


## Rango [mínimo, máximo] de la habilidad principal en un nivel.
static func get_main_skill_range(level: String) -> Vector2i:
	return _pair(_staff_data()["levels"][level]["main_skill_range"])


static func get_age_range(level: String) -> Vector2i:
	return _pair(_staff_data()["levels"][level]["age_range"])


static func get_other_skill_range() -> Vector2i:
	return _pair(_staff_data()["other_skill_range"])


## Ancho del rango con que se muestra cada habilidad de un candidato.
static func get_skill_range_width() -> int:
	return int(_staff_data()["skill_range_width"])


## Un valor de la sección "hiring" de data/staff.json.
static func get_hiring(key: String) -> Variant:
	return _staff_data()["hiring"][key]


## Rango [mínimo, máximo] de un valor de "hiring" guardado como par.
static func get_hiring_range(key: String) -> Vector2i:
	return _pair(get_hiring(key))


static func get_first_names(sex: String) -> Array[String]:
	var names: Array[String] = []
	names.assign(_names_data()[sex])
	return names


static func get_last_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(_names_data()["last"])
	return names


static func get_trait_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_names_data()["traits"].keys())
	return ids


static func get_trait_name(trait_id: String) -> String:
	return String(_names_data()["traits"].get(trait_id, trait_id))


static func get_traits_per_person() -> Vector2i:
	return _pair(_names_data()["traits_per_person"])


static func _pair(values: Array) -> Vector2i:
	return Vector2i(int(values[0]), int(values[1]))


static func _staff_data() -> Dictionary:
	if _staff.is_empty():
		_staff = _load(STAFF_PATH)
	return _staff


static func _names_data() -> Dictionary:
	if _names.is_empty():
		_names = _load(NAMES_PATH)
	return _names


static func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("No se pudo leer %s" % path)
		return {}
	return parsed
