# Empresa con la que empieza la partida (data/starting_company.json): local grande con
# Oficina Ejecutiva, oficinas únicas, Recepción, Cuarto de limpieza y un Área de trabajo
# llena de puestos; 40 empleados con equipos, líderes, gerentes, ejecutivos y personal de
# apoyo, y contratos en curso. Se arma encima de una partida vacía (SaveManager.new_game)
# usando las mismas reglas del juego: Builder marca las habitaciones y pone los muebles, y
# Staff y Projects contratan, arman equipos y aceptan contratos.
class_name StartingCompany
extends RefCounted

const DATA_PATH: String = "res://data/starting_company.json"
## Concepto del saldo con que empieza la empresa.
const CONCEPT_CAPITAL: String = "Capital inicial"
## Dinero para pagar la obra y los muebles mientras se arma (después el saldo se fija).
const BUILD_BUDGET: int = 1000000


## Arma la empresa. Devuelve los problemas encontrados (vacío si todo salió bien).
static func apply() -> Array[String]:
	var data: Dictionary = _load()
	var problems: Array[String] = []
	Company.stage = int(data.get("stage", 0))
	for objective: Dictionary in Company.get_objectives():
		if not Company.objectives_done.has(String(objective["id"])):
			Company.objectives_done.append(String(objective["id"]))
	Economy.earn(BUILD_BUDGET, CONCEPT_CAPITAL)
	_build_office(data, problems)
	_hire_staff(data, problems)
	# El saldo empieza limpio: sin la obra en los movimientos.
	Economy.new_game()
	Economy.earn(int(data.get("money", 0)) - Economy.balance, CONCEPT_CAPITAL)
	Projects.reputation = float(data.get("reputation", 1.0))
	Projects.best_reputation = Projects.reputation
	_start_contracts(data, problems)
	Bank.new_game()
	EventBus.office_changed.emit()
	EventBus.staff_changed.emit()
	EventBus.projects_changed.emit()
	for problem: String in problems:
		push_warning("Empresa inicial: " + problem)
	return problems


# --- Oficina -----------------------------------------------------------------------


static func _build_office(data: Dictionary, problems: Array[String]) -> void:
	var lot_data: Array = data["lot"]
	var lot_rect := Rect2i(int(lot_data[0]), int(lot_data[1]), int(lot_data[2]), int(lot_data[3]))
	var entrance_door: Vector3i = GridEdge.from_data([OfficeState.entrance.x, OfficeState.entrance.y, "y"])
	OfficeState.lot = Lot.from_rect(lot_rect)
	OfficeState.rooms.clear()
	OfficeState.furniture.clear()
	OfficeState.floors.clear()
	OfficeState.edges.clear()
	for cell: Vector2i in OfficeState.lot.get_cells():
		OfficeState.floors[cell] = String(data.get("floor", ConstructionCatalog.BARE_FLOOR))
	for edge: Vector3i in GridEdge.get_lot_outline(OfficeState.lot):
		OfficeState.edges[edge] = ConstructionCatalog.WALL
	# La entrada de la Recepción con la puerta doble de vidrio, como ejemplo (hito 69).
	OfficeState.edges[entrance_door] = ConstructionCatalog.GLASS_DOOR
	# Paredes de cada habitación hacia el resto del local, y su puerta.
	for room: Dictionary in data.get("rooms", []):
		var rect: Rect2i = _rect(room["rect"])
		for x: int in range(rect.position.x, rect.end.x):
			for y: int in range(rect.position.y, rect.end.y):
				var cell := Vector2i(x, y)
				OfficeState.floors[cell] = String(room.get("floor", data.get("floor", ConstructionCatalog.BARE_FLOOR)))
				for edge: Vector3i in _inner_edges(cell, rect, lot_rect):
					OfficeState.edges[edge] = ConstructionCatalog.WALL
		OfficeState.edges[GridEdge.from_data(room["door"])] = ConstructionCatalog.DOOR
	EventBus.office_changed.emit()
	var builder := Builder.new()
	for room: Dictionary in data.get("rooms", []):
		var rect: Rect2i = _rect(room["rect"])
		_check(builder.mark_room(String(room["type"]), rect.position), "habitación %s" % room["type"], problems)
	_check(builder.mark_room(Workstations.WORK_AREA, _cell(data["work_area_cell"])), "Área de trabajo", problems)
	for item: Dictionary in data.get("furniture", []):
		_place(builder, item, problems)
	var rows: Dictionary = data.get("desk_rows", {})
	for row: int in range(int(rows.get("rows", 0))):
		var y: int = int(rows["y"]) + row * int(rows["row_step"])
		for i: int in range(int(rows["per_row"])):
			var x: int = int(rows["x"]) + i
			_place(builder, {"id": rows["desk"], "cell": [x, y], "rotation": 2, "computer": rows.get("computer", "")}, problems)
			_place(builder, {"id": "basic_chair", "cell": [x, y + 1], "rotation": 0}, problems)


# Bordes de una casilla de la habitación que dan a otra casilla del local fuera de ella.
static func _inner_edges(cell: Vector2i, rect: Rect2i, lot_rect: Rect2i) -> Array[Vector3i]:
	var edges: Array[Vector3i] = []
	var x: int = GridEdge.AXIS_X
	var y: int = GridEdge.AXIS_Y
	var sides: Array[Array] = [
		[Vector2i(1, 0), Vector3i(cell.x, cell.y, x)], [Vector2i(-1, 0), Vector3i(cell.x - 1, cell.y, x)],
		[Vector2i(0, 1), Vector3i(cell.x, cell.y, y)], [Vector2i(0, -1), Vector3i(cell.x, cell.y - 1, y)],
	]
	for side: Array in sides:
		var neighbor: Vector2i = cell + side[0]
		if lot_rect.has_point(neighbor) and not rect.has_point(neighbor):
			edges.append(side[1])
	return edges


static func _place(builder: Builder, item: Dictionary, problems: Array[String]) -> void:
	var cell: Vector2i = _cell(item["cell"])
	if not _check(builder.place(String(item["id"]), cell, int(item.get("rotation", 0))), "%s en %s" % [item["id"], cell], problems):
		return
	var computer: String = String(item.get("computer", ""))
	if not computer.is_empty():
		_check(builder.install_computer(computer, cell), "computadora en %s" % cell, problems)
	if bool(item.get("ceo", false)):
		OfficeState.furniture[OfficeState.find_furniture_at(cell)]["assigned_to"] = "ceo"


# --- Personal y contratos ------------------------------------------------------------


static func _hire_staff(data: Dictionary, problems: Array[String]) -> void:
	var leader_role: String = StaffCatalog.get_leader_role()
	var team_ids: Array[int] = []
	var leaders: Array[int] = []
	for team_data: Dictionary in data.get("teams", []):
		var team: Dictionary = Staff.create_team()
		team_ids.append(int(team["id"]))
		var template_index: int = int(team_data.get("template", 0))
		if template_index < Staff.shift_templates.size():
			Staff.set_team_template(team["id"], int(Staff.shift_templates[template_index]["id"]))
		for member: Array in team_data["members"]:
			var employee: Dictionary = _hire(String(member[0]), String(member[1]), problems)
			if not employee.is_empty():
				_check(Staff.add_to_team(team["id"], employee["id"]), "sumar %s al equipo" % employee["name"], problems)
		var leader: Dictionary = _hire(leader_role, "", problems)
		leaders.append(-1 if leader.is_empty() else int(leader["id"]))
	# Los gerentes primero: el CEO dirige solo hasta 5 líderes con equipo.
	var per_manager: int = int(data.get("leaders_per_manager", 0))
	for index: int in range(int(data.get("managers", 0))):
		var manager: Dictionary = _hire(StaffCatalog.get_manager_role(), "", problems)
		if manager.is_empty():
			continue
		for leader_id: int in leaders.slice(index * per_manager, (index + 1) * per_manager):
			if leader_id >= 0:
				_check(Staff.set_manager(leader_id, manager["id"]), "gerente de un líder", problems)
	for index: int in range(leaders.size()):
		if leaders[index] >= 0:
			_check(Staff.add_to_team(team_ids[index], leaders[index]), "líder del equipo", problems)
	for department: Variant in data.get("executives", []):
		var executive: Dictionary = _hire(StaffCatalog.get_executive_role(), "", problems)
		if not executive.is_empty() and String(executive.get("department", "")) != String(department):
			_check(Staff.set_executive_department(executive["id"], String(department)), "ejecutivo de %s" % department, problems)
	for other: Array in data.get("others", []):
		_hire(String(other[0]), String(other[1]), problems)


static func _hire(role: String, level: String, problems: Array[String]) -> Dictionary:
	var employee: Dictionary = Staff.hire_directly(role, level if not level.is_empty() else StaffCatalog.get_level_ids()[-1])
	if employee.is_empty():
		problems.append("no se pudo contratar %s: %s" % [role, Staff.get_station_problem(role) + Staff.role_problem(role)])
	return employee


static func _start_contracts(data: Dictionary, problems: Array[String]) -> void:
	var sizes: Dictionary = data.get("contracts", {})
	if sizes.is_empty():
		return
	for team: Dictionary in Staff.teams:
		var offer: Dictionary = Projects.create_offer(String(sizes["team"]))
		_check(Projects.accept(offer["id"]), "contrato del equipo %s" % team["name"], problems)
		var contract: Dictionary = Projects.contracts[-1]
		Projects.assign(contract["id"], team["id"])
	var ceo_offer: Dictionary = Projects.create_offer(String(sizes["ceo"]))
	_check(Projects.accept(ceo_offer["id"]), "contrato del CEO", problems)
	Projects.assign(Projects.contracts[-1]["id"], Projects.CEO_TEAM)


# --- Ayudas --------------------------------------------------------------------------


static func _check(result: Dictionary, what: String, problems: Array[String]) -> bool:
	if bool(result.get("ok", false)):
		return true
	problems.append("%s: %s" % [what, result.get("message", "")])
	return false


static func _rect(values: Array) -> Rect2i:
	return Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))


static func _cell(values: Array) -> Vector2i:
	return Vector2i(int(values[0]), int(values[1]))


static func _load() -> Dictionary:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
