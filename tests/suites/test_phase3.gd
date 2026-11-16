# Comprobación de la fase 3: simula meses con una política simple (aceptar lo que se pueda,
# entregar lo terminado): CEO solo 3 meses; primer equipo con $5,000 a 12 meses; empresa
# que deja de pagar (embargo al tercer mes). Imprime un resumen por mes para ajustar los datos.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=phase3
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 29

var _failures: int = 0
var _checks: int = 0
var _late_installments: int = 0
var _emergencies: int = 0
var _game_over_day: int = 0
var _month_rows: Array[String] = []
# Ingresos de contratos de cada mes cerrado (tabla 13.8).
var _month_income: Array[int] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Carpeta aparte para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	EventBus.payment_recorded.connect(func(concept: String, on_time: bool) -> void:
		if concept == Bank.CONCEPT_INSTALLMENT and not on_time:
			_late_installments += 1)
	EventBus.emergency_loan_offered.connect(func(_offer: Dictionary) -> void:
		_emergencies += 1
		Bank.accept_emergency())
	EventBus.game_over.connect(func(_stats: Dictionary) -> void: _game_over_day = GameClock.get_day_count())
	_check_ceo_alone()
	_check_first_team()
	_check_default()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	# La primera oferta salió antes de fijar la semilla: se cambia por una sorteada con ella para repetir siempre igual.
	Projects.offers.clear()
	Projects.create_offer("small")
	_late_installments = 0
	_emergencies = 0
	_game_over_day = 0
	_month_rows.clear()
	_month_income.clear()


func _sum(concepts: Array[String], totals: Dictionary[String, int]) -> int:
	var total: int = 0
	for concept: String in concepts:
		total += totals.get(concept, 0)
	return total


# Cada día entrega lo terminado y acepta lo que pueda; el CEO trabaja de 8 a 17 (tabla 13.8);
# al cambiar de mes anota el resumen.
func _play_days(days: int, work: bool = true) -> void:
	for day: int in range(days):
		if Bank.game_over:
			return
		if work:
			_manage_contracts()
		else:
			for offer: Dictionary in Projects.offers.duplicate():
				Projects.reject(offer["id"])
		var month: int = Economy.get_current_month()
		_ceo_workday()
		if Economy.get_current_month() != month:
			_record_month(month)


# Un día desde las 8: el CEO trabaja hasta las 17 y se va a casa (vuelve el próximo día hábil).
func _ceo_workday() -> void:
	GameClock.fast_forward_hours(9)
	if Staff.ceo_at_work:
		Staff.set_ceo_at_work(false)
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY - 9)


func _manage_contracts() -> void:
	for contract: Dictionary in Projects.contracts.duplicate():
		if Projects.get_done_ratio(contract) >= 1.0 - Production.EPSILON:
			Projects.deliver(contract["id"])
	for offer: Dictionary in Projects.offers.duplicate():
		if Projects.accept_problem(offer["id"]).is_empty():
			Projects.accept(offer["id"])


func _record_month(month: int) -> void:
	var totals: Dictionary[String, int] = Economy.get_month_totals(month)
	var income: int = _sum(Bank.get_income_concepts(), totals)
	_month_income.append(income)
	var payroll: int = -_sum([Staff.CONCEPT_PAYROLL], totals)
	var maintenance: int = -_sum([Economy.CONCEPT_MAINTENANCE], totals)
	var installments: int = -_sum([Bank.CONCEPT_INSTALLMENT, Bank.CONCEPT_OVERDUE], totals)
	_month_rows.append("  mes %d: contratos +%d · nómina −%d · mantenimiento −%d · cuotas −%d · saldo %d · deuda %d · %s (%d) · %d entregados · %.1f ★" % [
		month, income, payroll, maintenance, installments, Economy.balance, Bank.get_debt(), Bank.rating, Bank.score,
		Projects.delivered_count, Projects.reputation])


func _print_report(title: String) -> void:
	print(title)
	for row: String in _month_rows:
		print(row)


# Área de trabajo 3×3 al este de la Oficina Ejecutiva con tres puestos básicos.
func _build_team_office() -> void:
	var builder := Builder.new()
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(builder.apply(walls)["ok"] and builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "área de trabajo")
	for x: int in [3, 4, 5]:
		_expect(builder.place("simple_desk", Vector2i(x, 0), 2)["ok"] and builder.place("basic_chair", Vector2i(x, 1), 0)["ok"]
			and builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "puesto en x %d" % x)


# Contrata un Junior por lo que pide.
func _hire(role: String) -> Dictionary:
	var vacancy_id: int = Staff.open_vacancy(role, "junior", StaffCatalog.get_salary(role, "junior"), true)["id"]
	for attempt: int in range(10):
		if not Staff.get_vacancy(vacancy_id)["candidates"].is_empty():
			break
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)
	var candidate: Dictionary = Staff.get_vacancy(vacancy_id)["candidates"][0]
	var result: Dictionary = Staff.make_offer(candidate["id"], candidate["asked_salary"])
	_expect(result["ok"], "contratar %s: %s" % [role, result.get("message", "")])
	return Staff.employees[-1] if result["ok"] else {}


func _check_ceo_alone() -> void:
	_new_game()
	# Tabla 13.8: $240 al mes por los 48 m² del local inicial.
	_expect(Economy.get_maintenance(OfficeState.lot.get_area()) == 240, "mantenimiento $240")
	var start: int = Economy.balance
	# El CEO hace 24 puntos por día hábil (8 h de 3 puntos, SemiSenior).
	while GameClock.get_weekday() > 3:
		_play_days(1)
	_manage_contracts()
	var contract: Dictionary = Projects.contracts[0]
	var before: float = _progress(contract)
	_ceo_workday()
	var points: float = _progress(contract) - before
	_expect(absf(points - 24.0) < 0.5, "el CEO produce 24 puntos al día: %.1f" % points)
	_play_days(89)
	_print_report("CEO solo (3 meses):")
	_expect(Projects.delivered_count >= 5, "entrega al menos 5 contratos pequeños: %d" % Projects.delivered_count)
	# Tabla 13.8: un pequeño de 200 puntos paga $1,600; unos $3,000–$6,000 al mes (el primer
	# mes cobra poco y un mes puede quedar con una sola entrega).
	var income: int = 0
	for month: int in range(1, _month_income.size()):
		income += _month_income[month]
	income /= maxi(1, _month_income.size() - 1)
	_expect(income >= 3000 and income <= 6000, "ingresos medios del CEO desde el mes 2: $%d" % income)
	_expect(Economy.balance > start, "termina con más dinero: %d → %d" % [start, Economy.balance])
	_expect(Bank.loans.is_empty() and Bank.rating <= "C" and Company.stage == 0, "sin préstamos, calificación C o mejor, Emprendimiento")


func _progress(contract: Dictionary) -> float:
	var total: float = 0.0
	for phase: String in contract["progress"]:
		total += float(contract["progress"][phase])
	return total + float(contract.get("fix_progress", 0.0))


func _check_first_team() -> void:
	_new_game()
	var request: Dictionary = Bank.request_loan(5000, 12)
	_expect(request["ok"], "préstamo de $5,000 a 12 meses: %s" % request["message"])
	var installment: int = Bank.get_installment(Bank.loans[0])
	_build_team_office()
	var team: Dictionary = Staff.create_team()
	var salaries: int = 0
	for role: String in ["programmer", "programmer", "designer"]:
		var employee: Dictionary = _hire(role)
		if not employee.is_empty():
			Staff.add_to_team(team["id"], employee["id"])
			salaries += int(employee["salary"])
	_expect(Staff.employees.size() == 3 and (team["members"] as Array).size() == 3, "equipo de 3")
	# Tabla 13.8: unos $3,400 de sueldos (piden del 90 % al 120 % de su nivel).
	_expect(salaries >= 2800 and salaries <= 4200, "sueldos del equipo: $%d" % salaries)
	_play_days(180)
	_print_report("Primer equipo con préstamo de $5,000 a 12 meses (cuota $%d, sueldos $%d):" % [installment, salaries])
	_expect(_late_installments == 0 and Bank.overdue_months == 0, "todas las cuotas a tiempo: %d atrasadas" % _late_installments)
	_expect(_emergencies == 0, "sin préstamos de emergencia: %d" % _emergencies)
	var loan: Dictionary = Bank.get_loan(1)
	_expect(not loan.is_empty() and int(loan["paid"]) == 6, "6 cuotas pagadas: %s" % loan.get("paid", "saldado"))
	_expect(Economy.balance >= Bank.get_seizable_debt(), "el saldo cubre la deuda: %d contra %d" % [Economy.balance, Bank.get_seizable_debt()])
	_expect(Staff.employees.size() == 3, "el equipo sigue completo: %d" % Staff.employees.size())
	# Tabla 13.8: el equipo hace ~1,050 puntos al mes ($8,400) más los del CEO; desde el segundo
	# mes deja más de lo que cuestan sueldos, local y cuota.
	var total: int = 0
	for month: int in range(1, _month_income.size()):
		total += _month_income[month]
		_expect(_month_income[month] > salaries + 240 + installment, "mes %d: ingresos $%d cubren los gastos" % [month + 1, _month_income[month]])
	var average: int = total / maxi(1, _month_income.size() - 1)
	_expect(average >= 7000 and average <= 13000, "ingresos medios con el equipo: $%d" % average)


func _check_default() -> void:
	_new_game()
	_expect(Bank.request_loan(5000, 6)["ok"], "préstamo de $5,000")
	Economy.charge(Economy.balance, "Prueba")
	Staff.set_ceo_at_work(false)
	# Cuotas el día 1 de los meses 2, 3 y 4: a la tercera sin pagar, embargo.
	_play_days(30 * 2, false)
	_expect(Bank.overdue_months == 2 and not Bank.loan_problem(1000, 6).is_empty(), "al segundo mes avisa y no presta: %d" % Bank.overdue_months)
	_expect(not Bank.game_over, "todavía no embarga")
	_play_days(30, false)
	_print_report("Empresa que deja de pagar ($5,000 a 6 meses, saldo en 0):")
	# Solo hay lo del CEO, que no se embarga: termina la partida.
	_expect(Bank.game_over and _game_over_day == 3 * GameConstants.DAYS_PER_MONTH,
		"embargo y fin el día 1 del mes 4 (tercera cuota): día %d" % _game_over_day)
