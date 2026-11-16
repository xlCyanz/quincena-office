# Comprobación de la fase 5: sigue la empresa de test_phase4 desde Mediana empresa hasta la bolsa.
# Política: agranda la Sala de servidores, compra terreno al oeste (oficinas únicas y Sala de
# reuniones) y al sur (puestos); suma vendedores y 3 equipos; 3 equipos hacen productos medianos
# (lanzar sin errores conocidos, actualizar al caer) y los demás el contrato más grande a tiempo;
# retiene gente, pide prestado con poca caja, responde eventos al azar y sale a bolsa en cuanto puede.
# Criterio: bolsa sin quebrar en ~2 años; productos 40–70 % de los ingresos del último año.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=phase5
extends "res://tests/suites/test_phase4.gd"

const SEED_5: int = 49
## Tope de meses desde Mediana empresa (de 30 días) y meta: unos dos años.
const MAX_MONTHS_5: int = 40
const TARGET_MONTHS: Array[int] = [18, 30]
## Parte de los ingresos del último año que deben dar los productos.
const PRODUCT_SHARE: Array[float] = [0.4, 0.7]
## Meses de gastos que guarda antes de contratar o construir.
const RESERVE_MONTHS_5: float = 1.0
## Equipos que la política tiene desarrollando o actualizando productos.
const PRODUCT_TEAMS: int = 3
## Tamaño de los productos (los grandes tardan medio año con un equipo).
const PRODUCT_SIZE: String = "medium"
## Días desde el lanzamiento o la última actualización para actualizar: cuando empieza a caer.
const UPDATE_AFTER_DAYS: int = 90
## Un equipo toma contratos grandes y de élite desde estos miembros.
const LARGE_TEAM: int = 8
## Puntos por día de calendario que la política espera de cada miembro (juniors).
const TEAM_MEMBER_RATE: float = 10.0
## Días que QA revisa un contrato terminado antes de entregarlo.
const REVIEW_DAYS: int = 4
## Equipos de la plantilla (test_phase4 llega con TEAM_COUNT).
const TEAM_COUNT_5: int = 7
## Vendedores de la plantilla.
const SALESPEOPLE: int = 6
## Plazo de los préstamos que pide.
const LOAN_MONTHS: int = 24
const MEETING_ROOM: String = "meeting_room"
## Terreno al oeste (filas 3 a 7, x −12 a −1): pasillo en la fila 5, cuatro oficinas únicas (escritorio
## a la izquierda, puerta a la derecha), Sala de reuniones arriba a la izquierda y un depósito abajo.
const OFFICE_DESKS: Array[Vector2i] = [Vector2i(-3, 3), Vector2i(-6, 3), Vector2i(-3, 7), Vector2i(-6, 7)]
const MEETING_CELL := Vector2i(-12, 3)
## Racks en la Sala de servidores agrandada (x 3 a 4, y −16 a −7), del fondo hacia la puerta.
const RACK_ROWS: Array[int] = [-16, -15, -14, -13, -12, -11, -10, -9, -8, -7]
## Los ejecutivos que faltan entran con el valor en esta parte de lo que pide la bolsa.
const EXECUTIVES_AT_VALUE: float = 0.6
## Calificaciones con que pide préstamos (con D y E la tasa es muy alta).
const LOAN_RATINGS: Array[String] = ["A", "B", "C"]

var _event_rng := RandomNumberGenerator.new()
var _rack_cells: Array[Vector2i] = []
var _product_types: Array[String] = ["saas", "mobile_app", "game"]
var _started_products: int = 0
## Día del último lanzamiento o actualización empezada de cada producto.
var _refreshed: Dictionary[int, int] = {}
var _events_seen: int = 0
var _public_month: int = 0
var _start_month: int = 0
var _meeting_built: bool = false
var _executives_planned: bool = false
## Día en que la política vio terminado cada contrato.
var _done_day: Dictionary[int, int] = {}
## Rige la política de la fase 5 (antes, la de test_phase4 lleva a Mediana empresa).
var _phase5: bool = false
## Ingresos de cada mes de la fase 5: {"contracts", "products"}.
var _income: Dictionary[int, Dictionary] = {}
## Meses desde Mediana empresa para llegar a la bolsa (test_phase6 pone el suyo).
var _target_months: Array[int] = TARGET_MONTHS


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	EventBus.emergency_loan_offered.connect(func(_offer: Dictionary) -> void: Bank.accept_emergency())
	EventBus.game_over.connect(func(_stats: Dictionary) -> void: _game_over_day = GameClock.get_day_count())
	EventBus.stage_changed.connect(func(stage: int) -> void: _stage_months[stage] = Economy.get_current_month())
	EventBus.event_started.connect(func(_card: Dictionary) -> void: _events_seen += 1)
	_check_growth()
	if Company.stage >= 3 and not Bank.game_over:
		_check_ipo_run()
	finished.emit(_failures, _checks)


func _check_ipo_run() -> void:
	_phase5 = true
	_month_rows.clear()
	Staff.set_seed(SEED_5)
	Projects.set_seed(SEED_5)
	Products.set_seed(SEED_5)
	Events.set_seed(SEED_5)
	_event_rng.seed = SEED_5
	_team_sizes = ["elite", "large", "medium", "small"]
	_reserve_months = RESERVE_MONTHS_5
	_extend_plan()
	_rack_cells.clear()
	for y: int in RACK_ROWS:
		_rack_cells.append_array([Vector2i(3, y), Vector2i(4, y)])
	_build_steps = [_build_servers_north, _build_west, _build_south]
	_built = 0
	_start_month = Economy.get_current_month()
	# Con el reloj «andando» salen eventos (la simulación no deja pasar fotogramas).
	GameClock.start()
	var months: int = 0
	while months < MAX_MONTHS_5 and not Bank.game_over and not Company.is_public():
		var month: int = Economy.get_current_month()
		_play_day()
		_answer_event()
		_retain()
		_borrow()
		if Company.ipo_problem().is_empty():
			Company.go_public()
			_public_month = month
		if Economy.get_current_month() != month:
			_record_month(month)
			months += 1
	GameClock.stop()
	print("Fase 5: de Mediana empresa (mes %d) a la bolsa con la política simple" % _start_month)
	for row: String in _month_rows:
		print(row)
	var share: float = _product_share(12)
	var months_to_ipo: int = _public_month - _start_month
	print("  etapas (mes en que llegó): %s · bolsa en el mes %d (%d desde Mediana empresa) · %d eventos · productos: %d lanzados, %d activos · parte del último año %d %%" % [
		_stage_months, _public_month, months_to_ipo, _events_seen, Products.launched_count, Products.get_active_count(), roundi(share * 100)])
	_expect(not Bank.game_over, "no quiebra (día %d)" % _game_over_day)
	_expect(Company.stage == 4, "llega a Corporación (etapa %d, %d ejecutivos, %d productos activos)" % [
		Company.stage, Staff.get_executives().size(), Products.get_active_count()])
	_expect(Company.is_public(), "sale a bolsa (valor %s)" % MoneyFormat.format(Company.get_value()))
	_expect(months_to_ipo >= _target_months[0] and months_to_ipo <= _target_months[1],
		"llega a la bolsa en unos dos años desde Mediana empresa: %d meses" % months_to_ipo)
	_expect(share >= PRODUCT_SHARE[0] and share <= PRODUCT_SHARE[1], "los productos dan una parte visible de los ingresos: %d %%" % roundi(share * 100))
	_expect(_events_seen > 0, "salen eventos")


func _answer_event() -> void:
	if Events.card.is_empty():
		return
	Events.choose(_event_rng.randi_range(0, (Events.card["options"] as Array).size() - 1))


# Iguala ofertas de afuera, da los aumentos pedidos y un 10 % a quien avisó que renuncia.
func _retain() -> void:
	for employee: Dictionary in Staff.employees.duplicate():
		if not (employee.get("outside_offer", {}) as Dictionary).is_empty():
			Staff.match_offer(employee["id"])
		elif not (employee["raise_request"] as Dictionary).is_empty():
			Staff.give_raise(employee["id"], int(employee["salary"]) + int(employee["raise_request"]["amount"]))
		elif int(employee["quit_day"]) != Staff.NO_QUIT:
			Staff.give_raise(employee["id"], roundi(int(employee["salary"]) * 1.1))


# Con menos de medio mes de gastos pide hasta un mes a 24 meses si la nota es buena:
# grandes y productos pagan tarde.
func _borrow() -> void:
	if Economy.balance >= 0.5 * _monthly_costs() or not LOAN_RATINGS.has(Bank.rating):
		return
	var step: int = int(Bank.get_config("loan_amount_step"))
	var amount: int = mini(Bank.get_max_request(), _monthly_costs()) / step * step
	if Bank.loan_problem(amount, LOAN_MONTHS).is_empty():
		Bank.request_loan(amount, LOAN_MONTHS)


# Parte de los ingresos de los últimos meses completos que dieron los productos.
func _product_share(months: int) -> float:
	var products: int = 0
	var total: int = 0
	var recorded: Array[int] = _income.keys()
	for month: int in recorded.slice(maxi(0, recorded.size() - months)):
		products += int(_income[month]["products"])
		total += int(_income[month]["contracts"]) + int(_income[month]["products"])
	return 0.0 if total <= 0 else float(products) / total


# Resumen del mes, contratos aparte de productos (Economy solo guarda dos meses).
func _record_month(month: int) -> void:
	if not _phase5:
		super._record_month(month)
		return
	var totals: Dictionary[String, int] = Economy.get_month_totals(month)
	var products: int = totals.get(Products.CONCEPT_INCOME, 0)
	var contracts: int = 0
	for concept: String in Bank.get_income_concepts():
		contracts += totals.get(concept, 0)
	var spent: int = 0
	for concept: String in totals:
		if totals[concept] < 0:
			spent -= totals[concept]
	_income[month] = {"contracts": contracts, "products": products}
	_month_rows.append("  mes %d: contratos +%d · productos +%d (%d lanzados, %d racks) · gastos −%d · saldo %d · deuda %d · valor %d · %d empleados · %d ejecutivos · %s · %.1f ★" % [
		month, contracts, products, Products.get_launched().size(), OfficeState.get_server_capacity(), spent, Economy.balance, Bank.get_debt(),
		Company.get_value(), Staff.employees.size(), Staff.get_executives().size(), Company.get_stage_name(), Projects.reputation])


# --- Plantilla y contratos ----------------------------------------------------------


# Suma a la plantilla de test_phase4 vendedores (un cuarto de oferta por día cada uno) y equipos.
func _extend_plan() -> void:
	var salespeople: int = _plan.filter(func(entry: Dictionary) -> bool: return entry["role"] == "salesperson").size()
	for index: int in range(SALESPEOPLE - salespeople):
		_plan.push_front({"role": "salesperson", "level": "junior", "team": -1})
	# Equipos nuevos, con líder desde el cuarto miembro.
	for team: int in range(TEAM_COUNT, TEAM_COUNT_5):
		for index: int in range(TEAM.size()):
			_plan.append({"role": TEAM[index], "level": "junior", "team": team})
			if index == TEAM_READY - 1:
				_plan.append({"role": StaffCatalog.get_leader_role(), "level": "senior", "team": team})


# Terminado, QA lo revisa unos días y se entrega sin errores conocidos, o el día antes del plazo.
func _ready_to_deliver(contract: Dictionary, today: int) -> bool:
	if not _phase5:
		return super._ready_to_deliver(contract, today)
	if Projects.get_done_ratio(contract) < 1.0 - Production.EPSILON:
		return false
	var id: int = int(contract["id"])
	if not _done_day.has(id):
		_done_day[id] = today
	if today >= int(contract["deadline_day"]) - 1:
		return true
	return int(contract["bugs_found"]) == 0 and today - _done_day[id] >= REVIEW_DAYS


# Equipos de 8: grandes y de élite; los más chicos, medianos o pequeños.
func _sizes_for(team: Dictionary) -> Array[String]:
	if not _phase5:
		return super._sizes_for(team)
	if (team["members"] as Array).size() >= LARGE_TEAM:
		return _team_sizes
	return ["medium", "small"]


# La oferta más grande de esos tamaños que el equipo llegue a hacer a tiempo.
func _take_offer(team_id: int, sizes: Array) -> void:
	if not _phase5:
		super._take_offer(team_id, sizes)
		return
	var team: Dictionary = Staff.get_team(team_id)
	var rate: float = TEAM_MEMBER_RATE * (team.get("members", []) as Array).size()
	for size: String in sizes:
		for offer: Dictionary in Projects.offers:
			if String(offer["size"]) != size or not Projects.accept_problem(offer["id"]).is_empty():
				continue
			if team_id != Projects.CEO_TEAM and int(offer["total_points"]) > rate * int(offer["days"]):
				continue
			var contract_id: int = offer["id"]
			Projects.accept(contract_id)
			Projects.assign(contract_id, team_id)
			return


# --- Productos --------------------------------------------------------------------


func _manage_product() -> void:
	if not _phase5:
		super._manage_product()
		return
	_build_meeting_room()
	_build_steps_now()
	var today: int = GameClock.get_day_count()
	for product: Dictionary in Products.get_in_development():
		if Projects.get_done_ratio(product) >= 0.5:
			_ensure_racks(ProductCatalog.get_racks(product["size"]))
		if Products.launch_problem(product["id"]).is_empty() and int(product["bugs_found"]) == 0:
			Products.launch(product["id"])
			_refreshed[int(product["id"])] = today
	for product: Dictionary in Products.get_launched():
		var id: int = int(product["id"])
		if not product.has("update") and _refreshed.has(id) and today - _refreshed[id] >= UPDATE_AFTER_DAYS \
				and Products.get_active_projects().size() < PRODUCT_TEAMS:
			var team_id: int = _free_ready_team()
			if team_id != Projects.NO_TEAM and Products.update_problem(id).is_empty():
				Products.start_update(id)
				Products.assign(id, team_id)
				_refreshed[id] = today
	if not _executives_planned and Products.get_active_count() >= 3 \
			and Company.get_value() >= EXECUTIVES_AT_VALUE * Company.get_ipo_value():
		# Cerca de la bolsa: los ejecutivos que faltan para Corporación.
		_executives_planned = true
		for index: int in range(4 - Staff.get_executives().size()):
			_plan.push_front({"role": StaffCatalog.get_executive_role(), "level": "senior", "team": -1})
	if Products.get_active_projects().size() >= PRODUCT_TEAMS or not Products.start_problem().is_empty():
		return
	# Sin lugar para sus racks no se lanzaría: esos equipos vuelven a los contratos.
	var racks_needed: int = ProductCatalog.get_racks(PRODUCT_SIZE) * (Products.get_in_development().size() + 1)
	if Products.get_free_racks() + _free_rack_cells() < racks_needed:
		return
	var team_id: int = _free_ready_team()
	if team_id == Projects.NO_TEAM:
		return
	var started: Dictionary = Products.start(_product_types[_started_products % _product_types.size()], PRODUCT_SIZE)
	if started["ok"]:
		_started_products += 1
		Products.assign(started["id"], team_id)


func _free_ready_team() -> int:
	for team: Dictionary in Staff.teams:
		if (team["members"] as Array).size() >= TEAM_READY and Projects.is_team_free(team["id"]):
			return int(team["id"])
	return Projects.NO_TEAM


# Compra los racks que falten para lanzar uno de ese tamaño, si hay lugar y dinero.
func _ensure_racks(needed: int) -> void:
	while Products.get_free_racks() < needed:
		var cell: Vector2i = _next_rack_cell()
		# Sin racks no se lanza: no espera a tener la reserva.
		if cell == Vector2i.MAX or Economy.balance < FurnitureCatalog.get_price("server_rack"):
			return
		_ok(_builder.place("server_rack", cell, 0), "rack en %s" % cell)


func _free_rack_cells() -> int:
	if _built < 1:
		return 0
	return _rack_cells.filter(func(cell: Vector2i) -> bool: return OfficeState.find_furniture_at(cell) < 0).size()


# Primera casilla libre para un rack (Vector2i.MAX si no hay o la sala no se agrandó).
func _next_rack_cell() -> Vector2i:
	if _built < 1:
		return Vector2i.MAX
	for cell: Vector2i in _rack_cells:
		if OfficeState.find_furniture_at(cell) < 0:
			return cell
	return Vector2i.MAX


# --- Obra -------------------------------------------------------------------------


# Obras en orden en cuanto alcanza, sin esperar a que falte un puesto.
func _build_steps_now() -> void:
	while _built < _build_steps.size():
		var cost: int = int(_build_steps[_built].call(true))
		if Economy.balance < cost + _reserve_months * _monthly_costs():
			return
		_build_steps[_built].call(false)
		_built += 1


# Terreno al oeste (filas 3 a 7, x −12 a −1): pasillo en la fila 5, cuatro oficinas únicas de 3×2,
# Sala de reuniones (x −12 a −7, filas 3 y 4) y depósito (filas 6 y 7).
func _build_west(quote: bool) -> int:
	var x_axis: int = GridEdge.AXIS_X
	var y_axis: int = GridEdge.AXIS_Y
	var offset: int = 3 - OfficeState.lot_rect.position.y
	var land: Dictionary = _builder.quote_land(Builder.SIDE_WEST, 5, 12, offset)
	var walls: Array[Dictionary] = []
	for y: int in [3, 4, 6, 7]:
		walls.append(_wall(-1, y, x_axis))
		walls.append(_wall(-4, y, x_axis))
		walls.append(_wall(-7, y, x_axis))
	for x: int in range(-12, 0):
		walls.append(_wall(x, 4, y_axis, ConstructionCatalog.DOOR if [-1, -4, -8].has(x) else ConstructionCatalog.WALL))
		walls.append(_wall(x, 5, y_axis, ConstructionCatalog.DOOR if [-1, -4, -9].has(x) else ConstructionCatalog.WALL))
	var cost: int = int(land["cost"]) + int(_builder.quote(walls)["cost"]) \
		+ OFFICE_DESKS.size() * (FurnitureCatalog.get_price("simple_desk") + FurnitureCatalog.get_price("basic_chair"))
	if quote:
		return cost
	_ok(_builder.buy_land(Builder.SIDE_WEST, 5, 12, offset), "terreno al oeste")
	_ok(_builder.apply(walls), "paredes del oeste")
	for desk: Vector2i in OFFICE_DESKS:
		# Arriba el escritorio mira al sur (silla debajo); abajo, al norte (silla encima).
		var rotation: int = 2 if desk.y == 3 else 0
		var chair: Vector2i = desk + FurnitureCatalog.get_front(rotation)
		_ok(_builder.mark_room(Workstations.SINGLE_OFFICE, chair), "oficina única en %s" % chair)
		_ok(_builder.place("simple_desk", desk, rotation), "escritorio de oficina en %s" % desk)
		_ok(_builder.place("basic_chair", chair, 0), "silla de oficina en %s" % chair)
	return cost


# Terreno al norte de la Sala de servidores (x 3 a 4, y −16 a −7): la sala crece hacia él.
func _build_servers_north(quote: bool) -> int:
	var offset: int = 3 - OfficeState.lot_rect.position.x
	var land: Dictionary = _builder.quote_land(Builder.SIDE_NORTH, 2, RACK_ROWS.size(), offset)
	if quote:
		return int(land["cost"]) + FurnitureCatalog.get_price("air_conditioner")
	# El terreno abre la pared norte del aire: se vende y se cuelga en la pared norte nueva.
	_ok(_builder.sell_wall_item(Vector2i(4, -6), 2), "aire acondicionado viejo")
	_ok(_builder.buy_land(Builder.SIDE_NORTH, 2, RACK_ROWS.size(), offset), "terreno de la Sala de servidores")
	_ok(_builder.place("air_conditioner", Vector2i(4, RACK_ROWS[0]), 2), "aire acondicionado")
	var room: Dictionary = OfficeState.get_server_room()
	_expect(not room.is_empty() and (room["cells"] as Array).size() >= 12, "la Sala de servidores crece: %s" % [room.get("cells", []).size()])
	return int(land["cost"]) + FurnitureCatalog.get_price("air_conditioner")


# Terreno al sur (x 7 a 21, filas 6 a 11; no tapa la entrada) con 28 puestos: escritorios en 7 y
# sillas en 8, sillas en 10 y escritorios en 11 mirando al norte; pasillos en 6 y 9, unidos por x 21.
func _build_south(quote: bool) -> int:
	var xs: Array = range(7, 21)
	var offset: int = 7 - OfficeState.lot_rect.position.x
	var land: Dictionary = _builder.quote_land(Builder.SIDE_SOUTH, xs.size() + 1, 6, offset)
	var cost: int = int(land["cost"]) + _stations(_row(xs, 7), 2, true) + _stations(_row(xs, 11), 0, true)
	if quote:
		return cost
	_ok(_builder.buy_land(Builder.SIDE_SOUTH, xs.size() + 1, 6, offset), "terreno al sur")
	_stations(_row(xs, 7), 2, false)
	_stations(_row(xs, 11), 0, false)
	return cost


# Sala de reuniones con mesa y pantalla, desde la primera oferta grande.
func _build_meeting_room() -> void:
	if _meeting_built or not Projects.meeting_room_unlocked or _built < 2:
		return
	var cost: int = FurnitureCatalog.get_price("meeting_table") + FurnitureCatalog.get_price("presentation_screen")
	if Economy.balance < cost + _reserve_months * _monthly_costs():
		return
	_ok(_builder.mark_room(MEETING_ROOM, MEETING_CELL + Vector2i(3, 0)), "Sala de reuniones")
	_ok(_builder.place("meeting_table", MEETING_CELL, 0), "mesa de reuniones")
	_ok(_builder.place("presentation_screen", MEETING_CELL + Vector2i(2, 0), 2), "pantalla de presentaciones")
	_meeting_built = true
