# Prueba del hito 39: comprobación de la fase 4. Simula una empresa que empieza con el
# CEO solo y crece como un jugador con una política simple:
#   - cada mañana entrega lo terminado (sin errores conocidos, o el día del plazo), le da a
#     cada equipo libre la oferta más grande y al CEO solo pequeñas;
#   - construye por pasos (puestos en el local inicial, Recepción, terreno al este con
#     puestos, terreno al norte con oficinas únicas y Cuarto de limpieza, más terreno al
#     este) cuando hacen falta puestos y el saldo cubre la obra y una reserva;
#   - contrata con vacantes (sin publicidad, al sueldo que piden) siguiendo un plan:
#     cuatro equipos de 8 (2 diseñadores, 4 programadores, 2 QA) con su líder desde Startup,
#     vendedores, contador, recepcionista, limpieza, un gerente desde Pequeña empresa que
#     dirige a los líderes y un ejecutivo en Mediana empresa;
#   - el CEO trabaja de 8 a 17.
# Criterio: llega a Mediana empresa sin quebrar; dirigir 4 departamentos se nota en los
# ingresos (con un ejecutivo, el mismo mes rinde más). Imprime un resumen por mes para
# ajustar data/staff.json, data/stages.json y data/contracts.json.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=phase4
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const SEED: int = 39
## Tope de la simulación (meses de 30 días).
const MAX_MONTHS: int = 48
## Meses de gastos que la política guarda antes de contratar o construir.
const RESERVE_MONTHS: float = 1.5
const TEAM: Array[String] = ["designer", "programmer", "programmer", "qa", "programmer", "designer", "programmer", "qa"]
const TEAM_COUNT: int = 4
## Un equipo recibe contratos desde que tiene estos miembros.
const TEAM_READY: int = 4

var _failures: int = 0
var _checks: int = 0
var _month_rows: Array[String] = []
var _game_over_day: int = 0
var _builder := Builder.new()
var _build_steps: Array[Callable] = []
var _built: int = 0
# Cargos por contratar, en orden; cada uno {"role", "level", "team"} (team = índice o -1).
var _plan: Array[Dictionary] = []
var _pending: Dictionary = {}
var _team_ids: Array[int] = []
var _stage_months: Dictionary[int, int] = {}


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	EventBus.emergency_loan_offered.connect(func(_offer: Dictionary) -> void: Bank.accept_emergency())
	EventBus.game_over.connect(func(_stats: Dictionary) -> void: _game_over_day = GameClock.get_day_count())
	EventBus.stage_changed.connect(func(stage: int) -> void: _stage_months[stage] = Economy.get_current_month())
	_check_growth()
	_check_departments()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# --- Crecimiento ------------------------------------------------------------------


func _check_growth() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	# La primera oferta salió antes de fijar la semilla: se cambia por una sorteada con ella
	# para que la simulación dé siempre lo mismo.
	Projects.offers.clear()
	Projects.create_offer("small")
	_make_plan()
	_build_steps = [_build_start_desks, _build_reception, _build_east, _build_north, _build_east_more]
	var months: int = 0
	while months < MAX_MONTHS and not Bank.game_over and Company.stage < 3:
		var month: int = Economy.get_current_month()
		_play_day()
		if Economy.get_current_month() != month:
			_record_month(month)
			months += 1
	print("Fase 4: crecimiento con la política simple")
	for row: String in _month_rows:
		print(row)
	print("  etapas (mes en que llegó): %s" % [_stage_months])
	_expect(not Bank.game_over, "no quiebra (día %d)" % _game_over_day)
	_expect(Company.stage >= 3, "llega a Mediana empresa en %d meses (etapa %d, %d empleados)" % [months, Company.stage, Staff.employees.size()])
	_expect(not Staff.get_leaders().is_empty() and not Staff.get_managers().is_empty(), "con líderes y un gerente")
	if Company.stage >= 3:
		# Ya en Mediana empresa: contrata un ejecutivo (cuando la reserva alcance) y sigue un
		# mes más.
		_plan.push_front({"role": StaffCatalog.get_executive_role(), "level": "senior", "team": -1})
		var days: int = 0
		while Staff.get_executives().is_empty() and days < 3 * GameConstants.DAYS_PER_MONTH:
			_play_day()
			days += 1
		_expect(not Staff.get_executives().is_empty(), "contrata un ejecutivo en %d días" % days)
		for day: int in range(GameConstants.DAYS_PER_MONTH):
			var month: int = Economy.get_current_month()
			_play_day()
			if Economy.get_current_month() != month:
				_record_month(month)
		print(_month_rows[-1])
		_expect(not Bank.game_over and Economy.balance > 0, "sigue sin quebrar con el ejecutivo: saldo %d" % Economy.balance)


# Un día con la política: contratos, obra, vacantes; el CEO de 8 a 17.
func _play_day() -> void:
	if Bank.game_over:
		return
	_manage_contracts()
	_grow()
	GameClock.fast_forward_hours(9)
	if Staff.ceo_at_work:
		Staff.set_ceo_at_work(false)
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY - 9)


func _manage_contracts() -> void:
	var today: int = GameClock.get_day_count()
	for contract: Dictionary in Projects.contracts.duplicate():
		if Projects.get_done_ratio(contract) >= 1.0 - Production.EPSILON \
				and (int(contract["bugs_found"]) == 0 or today >= int(contract["deadline_day"]) - 1):
			Projects.deliver(contract["id"])
	for team: Dictionary in Staff.teams:
		if (team["members"] as Array).size() >= TEAM_READY and Projects.get_contract_of(team["id"]).is_empty():
			_take_offer(team["id"], ["medium", "small"])
	if Projects.get_contract_of(Projects.CEO_TEAM).is_empty():
		_take_offer(Projects.CEO_TEAM, ["small"])


# Acepta la oferta más grande de esos tamaños (en orden) y se la da a ese equipo o al CEO.
func _take_offer(team_id: int, sizes: Array) -> void:
	for size: String in sizes:
		for offer: Dictionary in Projects.offers:
			if String(offer["size"]) == size and Projects.accept_problem(offer["id"]).is_empty():
				var contract_id: int = offer["id"]
				Projects.accept(contract_id)
				Projects.assign(contract_id, team_id)
				return


# Gastos de un mes: sueldos más mantenimiento (más la cuota de los préstamos).
func _monthly_costs(extra_salary: int = 0) -> int:
	var total: int = extra_salary + Economy.get_monthly_maintenance()
	for employee: Dictionary in Staff.employees:
		total += int(employee["salary"])
	for loan: Dictionary in Bank.loans:
		total += Bank.get_installment(loan)
	return total


func _grow() -> void:
	_hire_arrived()
	if not _pending.is_empty():
		return
	# El primero de la plantilla que falta y ya se puede contratar (los líderes esperan a
	# Startup y el gerente a Pequeña empresa). Quien se va vuelve a faltar.
	var next: Dictionary = {}
	for entry: Dictionary in _missing():
		if Staff.role_problem(entry["role"]).is_empty():
			next = entry
			break
	if next.is_empty():
		return
	if not Staff.get_station_problem(next["role"]).is_empty():
		_build_next(next["role"])
		return
	var salary: int = StaffCatalog.get_salary(next["role"], next["level"])
	if Economy.balance < RESERVE_MONTHS * _monthly_costs(salary):
		return
	var opened: Dictionary = Staff.open_vacancy(next["role"], next["level"], salary, false)
	if opened["ok"]:
		_pending = {"vacancy": opened["id"], "plan": next}


# Lo que falta de la plantilla (_plan), en orden: compara cuántos de cada cargo pide cada
# equipo (o la empresa, con team −1) con los que hay.
func _missing() -> Array[Dictionary]:
	var have: Dictionary = {}
	for employee: Dictionary in Staff.employees:
		var team_index: int = -1
		var team: Dictionary = Staff.get_team_of(employee["id"])
		if not team.is_empty():
			team_index = _team_ids.find(int(team["id"]))
		var key: String = "%s/%d" % [employee["role"], team_index]
		have[key] = int(have.get(key, 0)) + 1
	var missing: Array[Dictionary] = []
	for entry: Dictionary in _plan:
		var key: String = "%s/%d" % [entry["role"], entry["team"]]
		if int(have.get(key, 0)) > 0:
			have[key] = int(have[key]) - 1
		else:
			missing.append(entry)
	return missing


# Contrata al primer candidato que llegó (con el sueldo que pide).
func _hire_arrived() -> void:
	if _pending.is_empty():
		return
	var vacancy: Dictionary = Staff.get_vacancy(_pending["vacancy"])
	if vacancy.is_empty():
		_pending = {}
		return
	var candidates: Array = vacancy["candidates"]
	if candidates.is_empty():
		return
	var candidate: Dictionary = candidates[0]
	var before: int = Staff.employees.size()
	Staff.make_offer(candidate["id"], candidate["asked_salary"])
	if Staff.employees.size() == before:
		return
	var employee: Dictionary = Staff.employees[-1]
	var plan: Dictionary = _pending["plan"]
	_pending = {}
	if String(plan["role"]) == StaffCatalog.get_manager_role():
		for leader: Dictionary in Staff.get_leaders():
			Staff.set_manager(leader["id"], employee["id"])
		return
	var team_index: int = int(plan["team"])
	if team_index < 0:
		return
	while _team_ids.size() <= team_index:
		_team_ids.append(int(Staff.create_team()["id"]))
	Staff.add_to_team(_team_ids[team_index], employee["id"])
	var manager: Array[Dictionary] = Staff.get_managers()
	if Staff.is_leader(employee) and not manager.is_empty():
		Staff.set_manager(employee["id"], manager[0]["id"])


func _make_plan() -> void:
	_plan.clear()
	var leader: String = StaffCatalog.get_leader_role()
	for team: int in range(TEAM_COUNT):
		for index: int in range(TEAM.size()):
			_plan.append({"role": TEAM[index], "level": "junior", "team": team})
			if index == TEAM_READY - 1:
				_plan.append({"role": leader, "level": "senior", "team": team})
		if team == 0:
			_plan.append({"role": "salesperson", "level": "junior", "team": -1})
			_plan.append({"role": "accountant", "level": "senior", "team": -1})
		if team == 1:
			_plan.append({"role": "receptionist", "level": "senior", "team": -1})
			_plan.append({"role": "salesperson", "level": "junior", "team": -1})
			_plan.append({"role": StaffCatalog.get_manager_role(), "level": "senior", "team": -1})
		if team == 2:
			_plan.append({"role": "cleaner", "level": "senior", "team": -1})


# --- Obra -------------------------------------------------------------------------


# Construye el siguiente paso de obra que da puestos para ese cargo, si alcanza.
func _build_next(role: String) -> void:
	while _built < _build_steps.size():
		var cost: int = int(_build_steps[_built].call(true))
		if Economy.balance < cost + RESERVE_MONTHS * _monthly_costs():
			return
		_build_steps[_built].call(false)
		_built += 1
		if Staff.get_station_problem(role).is_empty():
			return


func _wall(x: int, y: int, axis: int, kind: String = ConstructionCatalog.WALL) -> Dictionary:
	return {"edge": Vector3i(x, y, axis), "kind": kind}


# Puestos: escritorio con computadora y silla. rotation 2 = la silla queda al sur.
func _stations(cells: Array[Vector2i], rotation: int, quote: bool) -> int:
	var cost: int = 0
	var front: Vector2i = FurnitureCatalog.get_front(rotation)
	for cell: Vector2i in cells:
		cost += FurnitureCatalog.get_price("simple_desk") + FurnitureCatalog.get_price("basic_chair") + FurnitureCatalog.get_price("basic_computer")
		if not quote:
			_ok(_builder.place("simple_desk", cell, rotation), "escritorio en %s" % cell)
			_ok(_builder.install_computer("basic_computer", cell), "computadora en %s" % cell)
			_ok(_builder.place("basic_chair", cell + front, 0), "silla en %s" % (cell + front))
	return cost


func _ok(result: Dictionary, what: String) -> void:
	_expect(bool(result.get("ok", false)), "obra: %s: %s" % [what, result.get("message", "")])


func _row(xs: Array, y: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in xs:
		cells.append(Vector2i(x, y))
	return cells


# 1. Área de trabajo en el local inicial: 3 puestos junto a la Oficina Ejecutiva y 3 más abajo
# (la casilla (5, 3) queda libre para pasar al pasillo de la fila 2).
func _build_start_desks(quote: bool) -> int:
	var cost: int = _stations(_row([3, 4, 5], 0), 2, true) + _stations(_row([2, 3, 4], 3), 2, true)
	if quote:
		return cost
	_ok(_builder.mark_room(Workstations.WORK_AREA, Vector2i(3, 5)), "Área de trabajo")
	_stations(_row([3, 4, 5], 0), 2, false)
	_stations(_row([2, 3, 4], 3), 2, false)
	return cost


# 2. Recepción alrededor de la entrada (filas 6 y 7) con mostrador, silla y sofá.
func _build_reception(quote: bool) -> int:
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = []
	for x: int in [1, 2, 4, 5]:
		walls.append(_wall(x, 5, y))
	walls.append(_wall(3, 5, y, ConstructionCatalog.DOOR))
	walls.append(_wall(0, 6, GridEdge.AXIS_X))
	walls.append(_wall(0, 7, GridEdge.AXIS_X))
	var cost: int = int(_builder.quote(walls)["cost"]) + FurnitureCatalog.get_price("reception_counter") \
		+ FurnitureCatalog.get_price("basic_chair") + FurnitureCatalog.get_price("waiting_sofa")
	if quote:
		return cost
	_ok(_builder.apply(walls), "paredes de la Recepción")
	_ok(_builder.mark_room(Workstations.RECEPTION, Vector2i(3, 7)), "Recepción")
	_ok(_builder.place("reception_counter", Vector2i(1, 6), 2), "mostrador")
	_ok(_builder.place("basic_chair", Vector2i(1, 7), 0), "silla del mostrador")
	_ok(_builder.place("waiting_sofa", Vector2i(4, 6), 2), "sofá")
	return cost


# Dos filas de puestos en un terreno de las filas 0 a 5 (junto al Área de trabajo, no a la
# Recepción): escritorios en y 0 con la silla en 1 y sillas en 3 con escritorios en 4 mirando
# al norte; las filas 2 y 5 son pasillos.
func _east_block(top_xs: Array, bottom_xs: Array, quote: bool) -> int:
	return _stations(_row(top_xs, 0), 2, quote) + _stations(_row(bottom_xs, 4), 0, quote)


# 3. Terreno al este (x 6 a 15) con 19 puestos; (15, 0) queda libre para pasar al norte.
func _build_east(quote: bool) -> int:
	var land: Dictionary = _builder.quote_land(Builder.SIDE_EAST, 6, 10, 0)
	var cost: int = int(land["cost"]) + _east_block(range(6, 15), range(6, 16), true)
	if quote:
		return cost
	_ok(_builder.buy_land(Builder.SIDE_EAST, 6, 10, 0), "terreno al este")
	_east_block(range(6, 15), range(6, 16), false)
	return cost


# 4. Terreno al norte (x 3 a 15, y −4 a −1): dos oficinas únicas, un Área de trabajo con 6
# puestos y un Cuarto de limpieza, con puertas al pasillo de la fila −1.
func _build_north(quote: bool) -> int:
	var land: Dictionary = _builder.quote_land(Builder.SIDE_NORTH, 13, 4, 3)
	var walls: Array[Dictionary] = []
	for x: int in range(3, 16):
		walls.append(_wall(x, -2, GridEdge.AXIS_Y, ConstructionCatalog.DOOR if [4, 7, 10, 15].has(x) else ConstructionCatalog.WALL))
	for x: int in [5, 8, 14]:
		for y: int in range(-4, -1):
			walls.append(_wall(x, y, GridEdge.AXIS_X))
	var offices: Array[int] = [3, 6]
	var desks: Array[Vector2i] = _row(range(9, 15), -4)
	var cost: int = int(land["cost"]) + int(_builder.quote(walls)["cost"]) \
		+ offices.size() * (FurnitureCatalog.get_price("simple_desk") + FurnitureCatalog.get_price("basic_chair")) \
		+ _stations(desks, 2, true) + FurnitureCatalog.get_price("cleaning_closet")
	if quote:
		return cost
	_ok(_builder.buy_land(Builder.SIDE_NORTH, 13, 4, 3), "terreno al norte")
	_ok(_builder.apply(walls), "paredes del norte")
	for x: int in offices:
		_ok(_builder.mark_room(Workstations.SINGLE_OFFICE, Vector2i(x + 1, -3)), "oficina única en %d" % x)
		_ok(_builder.place("simple_desk", Vector2i(x + 1, -4), 2), "escritorio de oficina")
		_ok(_builder.place("basic_chair", Vector2i(x + 1, -3), 0), "silla de oficina")
	_ok(_builder.mark_room(Workstations.WORK_AREA, Vector2i(10, -2)), "Área de trabajo del norte")
	_stations(desks, 2, false)
	_ok(_builder.mark_room(Workstations.CLEANING_ROOM, Vector2i(15, -3)), "Cuarto de limpieza")
	_ok(_builder.place("cleaning_closet", Vector2i(15, -4), 2), "armario")
	return cost


# 5. Más terreno al este (x 16 a 21, hasta el borde del solar) con 12 puestos más.
func _build_east_more(quote: bool) -> int:
	var xs: Array = range(16, 22)
	# El terreno del norte corrió el borde de arriba del local a y −4: las filas 0 a 5 están en 4.
	var land: Dictionary = _builder.quote_land(Builder.SIDE_EAST, 6, 6, 4)
	var cost: int = int(land["cost"]) + _east_block(xs, xs, true)
	if quote:
		return cost
	_ok(_builder.buy_land(Builder.SIDE_EAST, 6, 6, 4), "más terreno al este")
	_east_block(xs, xs, false)
	return cost


# --- Departamentos ----------------------------------------------------------------


# Desde la empresa a la que llegó (guardada sin ejecutivos): tres meses con el CEO dirigiendo
# los 4 departamentos contra los mismos tres meses con un ejecutivo en Desarrollo.
func _check_departments() -> void:
	if Company.stage < 3:
		return
	for executive: Dictionary in Staff.get_executives().duplicate():
		Staff.fire(executive["id"])
	_plan.clear()
	_pending = {}
	_expect(Staff.get_departments().size() == 4, "la empresa tiene 4 departamentos: %s" % [Staff.get_departments()])
	_expect(is_equal_approx(Staff.get_department_factor("development"), 0.55), "el CEO con 4 departamentos rinde 55 %%: %.2f" % Staff.get_department_factor("development"))
	SaveManager.save_game("slot_5")
	var without: int = _income_over_months(3)
	SaveManager.load_game("slot_5")
	var executive: Dictionary = Staff.hire_directly(StaffCatalog.get_executive_role(), "senior")
	_expect(not executive.is_empty(), "un ejecutivo para la comparación")
	if not executive.is_empty():
		Staff.set_executive_department(executive["id"], "development")
	_expect(Staff.get_department_factor("development") > 1.0 and is_equal_approx(Staff.get_department_factor("design"), 0.7),
		"con ejecutivo: Desarrollo %.2f, Diseño %.2f" % [Staff.get_department_factor("development"), Staff.get_department_factor("design")])
	var with_executive: int = _income_over_months(3)
	print("  Ingresos de contratos en 3 meses: el CEO con 4 departamentos %s · con un ejecutivo en Desarrollo %s ($9,000/mes)" % [
		MoneyFormat.format(without), MoneyFormat.format(with_executive)])
	_expect(with_executive - without > 3 * StaffCatalog.get_salary(StaffCatalog.get_executive_role(), "senior"),
		"dirigir 4 departamentos se nota en los ingresos: %d contra %d (el ejecutivo se paga solo)" % [without, with_executive])


# Ingresos de contratos de los próximos meses completos, con la política de contratos y sin
# contratar ni construir.
func _income_over_months(months: int) -> int:
	Staff.set_seed(SEED + 1)
	Projects.set_seed(SEED + 1)
	var income: int = 0
	var counted: int = 0
	var month: int = Economy.get_current_month()
	while counted <= months:
		_manage_contracts()
		GameClock.fast_forward_hours(9)
		if Staff.ceo_at_work:
			Staff.set_ceo_at_work(false)
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY - 9)
		if Economy.get_current_month() != month:
			# El mes en que empieza está a medias: no cuenta.
			if counted > 0:
				var totals: Dictionary[String, int] = Economy.get_month_totals(month)
				for concept: String in Bank.get_income_concepts():
					income += totals.get(concept, 0)
			counted += 1
			month = Economy.get_current_month()
	return income


# --- Resumen ----------------------------------------------------------------------


func _record_month(month: int) -> void:
	var totals: Dictionary[String, int] = Economy.get_month_totals(month)
	var income: int = 0
	for concept: String in Bank.get_income_concepts():
		income += totals.get(concept, 0)
	var spent: int = 0
	for concept: String in totals:
		if totals[concept] < 0:
			spent -= totals[concept]
	_month_rows.append("  mes %d: contratos +%d · gastos −%d · saldo %d · %d empleados · %d equipos · %s · %d entregados · %.1f ★ · %s" % [
		month, income, spent, Economy.balance, Staff.employees.size(), Staff.get_active_team_count(), Company.get_stage_name(),
		Projects.delivered_count, Projects.reputation, Bank.rating])
