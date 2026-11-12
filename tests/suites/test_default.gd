# Prueba del hito 23: mora y embargo.
# Criterio: una cuota sin pagar cobra 5 % de recargo y baja la letra; a los 2 meses el banco
# no presta; a los 3, con muebles suficientes, se salda la deuda y los puestos quedan; sin
# muebles suficientes sale la pantalla de fin y se borra el autoguardado.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=default
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261112
const LETTERS: String = "ABCDE"

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_late_fee()
	_check_warning()
	_check_plan()
	_check_seizure()
	_check_save()
	await _check_panel()
	await _check_game_over()

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
	_notices.clear()


func _to_next_month() -> void:
	var target: int = GameClock.get_month() * GameConstants.DAYS_PER_MONTH
	GameClock.fast_forward_hours((target - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY - GameClock.get_hour())


func _sum(concept: String) -> int:
	var total: int = 0
	for movement: Dictionary in Economy.movements:
		if movement["concept"] == concept:
			total += int(movement["amount"])
	return total


func _has_notice(part: String) -> bool:
	for text: String in _notices:
		if text.contains(part):
			return true
	return false


# Un préstamo de $1,000 a 12 meses y la cuenta en cero: la cuota del día 1 no alcanza.
func _take_loan_and_go_broke() -> int:
	_expect(Bank.request_loan(1000, 12)["ok"], "pedir el préstamo")
	Economy.charge(Economy.balance, "Prueba")
	return Bank.get_installment(Bank.loans[0])


func _check_late_fee() -> void:
	_new_game()
	var installment: int = _take_loan_and_go_broke()
	var letter: String = Bank.rating
	_to_next_month()
	var late: int = roundi(installment * (1.0 + float(Bank.get_config("late_fee_ratio"))))
	_expect(Bank.get_overdue() == late, "la cuota queda atrasada con 5 %% de recargo: %d (cuota %d)" % [Bank.get_overdue(), installment])
	_expect(_sum(Bank.CONCEPT_INSTALLMENT) == 0, "la cuota no se cobra sin dinero")
	_expect(Bank.overdue_months == 1, "un mes debiendo: %d" % Bank.overdue_months)
	_expect(LETTERS.find(Bank.rating) > LETTERS.find(letter), "la letra baja: %s → %s" % [letter, Bank.rating])
	_expect(_has_notice("queda atrasada con recargo"), "aviso del atraso: %s" % [_notices])
	_expect(Bank.loan_problem(1000, 3).is_empty() or not Bank.loan_problem(1000, 3).contains("no presta"), "con un mes todavía presta")
	# Al llegar dinero se paga sola la cuota atrasada y se vuelve a estar al día.
	_notices.clear()
	Economy.earn(5000, "Prueba")
	_expect(Bank.get_overdue() == 0 and Bank.overdue_months == 0, "se paga sola: %d" % Bank.get_overdue())
	_expect(_sum(Bank.CONCEPT_OVERDUE) == -late, "movimiento «Cuota atrasada»: %d" % _sum(Bank.CONCEPT_OVERDUE))
	_expect(_has_notice("estás al día"), "aviso de al día: %s" % [_notices])
	# La cuota del mes siguiente ya se paga normal.
	_to_next_month()
	_expect(_sum(Bank.CONCEPT_INSTALLMENT) == -installment and Bank.get_overdue() == 0, "la cuota siguiente se paga")


func _check_warning() -> void:
	_new_game()
	_take_loan_and_go_broke()
	_to_next_month()
	_to_next_month()
	_expect(Bank.overdue_months == 2 and int(Bank.loans[0]["paid"]) == 2, "dos meses debiendo: %d" % Bank.overdue_months)
	_expect(_has_notice("Aviso de embargo"), "aviso de embargo: %s" % [_notices])
	var result: Dictionary = Bank.request_loan(1000, 3)
	_expect(not result["ok"] and String(result["message"]).contains("no presta"), "el banco no presta: %s" % result)


# Arma un Área de trabajo con dos puestos (escritorio + computadora + silla), plantas y
# escritorios con computadora fuera del área (decoración: no forman un puesto).
func _build_office() -> Dictionary:
	var builder := Builder.new()
	var y: int = GridEdge.AXIS_Y
	builder.apply([{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL}, {"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL}])
	builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))
	for x: int in [3, 5]:
		_expect(builder.place("simple_desk", Vector2i(x, 0), 2)["ok"], "escritorio del puesto en %d" % x)
		_expect(builder.place("basic_chair", Vector2i(x, 1), 0)["ok"], "silla del puesto en %d" % x)
		_expect(builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "computadora del puesto en %d" % x)
	var decor: Array[Vector2i] = [Vector2i(0, 4), Vector2i(0, 6), Vector2i(5, 4), Vector2i(5, 6)]
	for cell: Vector2i in decor:
		var placed: Dictionary = builder.place("simple_desk", cell, 1)
		_expect(placed["ok"], "escritorio suelto en %s: %s" % [cell, placed.get("message", "")])
		_expect(builder.install_computer("basic_computer", cell)["ok"], "computadora suelta en %s" % cell)
	for cell: Vector2i in [Vector2i(2, 4), Vector2i(2, 6)]:
		_expect(builder.place("small_plant", cell, 0)["ok"], "planta en %s" % cell)
	_expect(Workstations.find_all(OfficeState.furniture, OfficeState.rooms).size() == 2, "dos puestos que funcionan")
	return {"desks": decor}


func _count(id: String) -> int:
	var total: int = 0
	for item: Dictionary in OfficeState.furniture:
		if item["id"] == id:
			total += 1
	return total


# El orden del embargo con funciones puras: decoración, puestos libres, puestos ocupados.
func _check_plan() -> void:
	_new_game()
	_build_office()
	var furniture: Array[Dictionary] = []
	for item: Dictionary in OfficeState.furniture:
		furniture.append(item.duplicate())
	# Se ocupa el puesto de x = 5.
	var occupied_chair: int = OfficeState.find_furniture_at(Vector2i(5, 1))
	furniture[occupied_chair]["assigned_to"] = "employee_99"
	var protected: Dictionary[int, bool] = Embargo.get_protected(furniture)
	_expect(protected.size() == 2, "la silla y el escritorio del CEO no se embargan: %s" % protected)
	var desk_value: int = Embargo.get_value({"id": "simple_desk", "computer": "basic_computer"})
	_expect(desk_value == 325, "escritorio con computadora vale %d de reventa" % desk_value)
	var rooms: Array[Dictionary] = OfficeState.rooms
	var plan: Dictionary = Embargo.plan(furniture, rooms, 1)
	_expect(plan["covers"] and (plan["take"] as Array).size() == 1 and furniture[plan["take"][0]]["id"] == "simple_desk"
		and not String(furniture[plan["take"][0]].get("computer", "")).is_empty(), "primero lo que más vale de la decoración: %s" % plan)
	var decor_value: int = 4 * desk_value + 2 * Embargo.get_value({"id": "small_plant"})
	var station_indices: Array[int] = []
	for station: Dictionary in Workstations.find_all(furniture, rooms):
		station_indices.append_array([station["chair"], station["desk"]])
	plan = Embargo.plan(furniture, rooms, decor_value)
	for index: int in plan["take"]:
		_expect(not station_indices.has(index), "si alcanza la decoración, los puestos quedan: %d" % index)
	plan = Embargo.plan(furniture, rooms, decor_value + 1)
	var take: Array = plan["take"]
	var free_desk: int = OfficeState.find_furniture_at(Vector2i(3, 0))
	_expect(take.size() == 7 and take[6] == free_desk, "después, el puesto libre (escritorio primero): %s" % [take])
	_expect(not take.has(occupied_chair), "el puesto ocupado queda para el final")
	plan = Embargo.plan(furniture, rooms, int(plan["value"]) + 1)
	_expect(not plan["covers"] and (plan["take"] as Array).is_empty(), "si no alcanza no se lleva nada: %s" % plan)
	for index: int in protected:
		_expect(not (Embargo.plan(furniture, rooms, int(plan["value"]))["take"] as Array).has(index), "lo del CEO nunca")


func _check_seizure() -> void:
	_new_game()
	_build_office()
	var desks: int = _count("simple_desk")
	_take_loan_and_go_broke()
	_to_next_month()
	_to_next_month()
	var debt_before: int = Bank.get_seizable_debt()
	_notices.clear()
	_to_next_month()
	_expect(not Bank.game_over, "con muebles suficientes no se pierde")
	_expect(Bank.loans.is_empty() and Bank.overdue_months == 0 and Bank.get_overdue() == 0, "la deuda queda saldada: %s" % [Bank.loans])
	_expect(debt_before > 0 and _has_notice("Embargo: el banco se llevó"), "aviso del embargo: %s" % [_notices])
	_expect(Workstations.find_all(OfficeState.furniture, OfficeState.rooms).size() == 2, "los dos puestos quedan")
	_expect(_count("small_plant") == 2 and _count("simple_desk") == desks - 4, "se lleva los 4 escritorios sueltos: %d" % _count("simple_desk"))
	_expect(_count("executive_desk") == 1 and OfficeState.find_furniture_at(Vector2i(1, 1)) >= 0, "el escritorio y la silla del CEO quedan")
	_expect(_sum(Bank.CONCEPT_SURPLUS) > 0, "el sobrante vuelve a la cuenta: %d" % _sum(Bank.CONCEPT_SURPLUS))
	# Con todo saldado el banco vuelve a prestar.
	_expect(not Bank.loan_problem(1000, 3).contains("no presta"), "vuelve a prestar")


func _check_save() -> void:
	_new_game()
	_take_loan_and_go_broke()
	_to_next_month()
	Staff.hired_count = 3
	Projects.best_reputation = 3.4
	var before: String = JSON.stringify(Bank.export_state())
	_expect(SaveManager.save_game("slot_5"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(JSON.stringify(Bank.export_state()) == before and Bank.overdue_months == 1 and Bank.get_overdue() > 0, "la mora vuelve igual")
	_expect(Staff.hired_count == 3 and is_equal_approx(Projects.best_reputation, 3.4), "estadísticas del fin guardadas")
	var state: Dictionary = Bank.export_state()
	state.erase("overdue_months")
	for loan: Dictionary in state["loans"]:
		loan.erase("overdue")
	Bank.import_state(state)
	_expect(Bank.overdue_months == 0 and Bank.get_overdue() == 0, "una partida del hito 22 carga al día")


func _check_panel() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var bank: BankPanel = game.get_node("BankPanel")
	bank.set_open(true)
	_take_loan_and_go_broke()
	await get_tree().process_frame
	_expect(bank.get_overdue_text().is_empty(), "al día no hay aviso")
	_to_next_month()
	await get_tree().process_frame
	var text: String = bank.get_overdue_text()
	_expect(text.begins_with("Cuotas atrasadas: ") and text.contains("1 mes seguido") and text.contains("perderías la empresa"), "aviso: %s" % text)
	_expect(bank.get_loans_text().contains("atrasado"), "el préstamo muestra lo atrasado: %s" % bank.get_loans_text())
	game.queue_free()
	await get_tree().process_frame


func _check_game_over() -> void:
	_new_game()
	Staff.hired_count = 2
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var screen: GameOverScreen = game.get_node("GameOverScreen")
	_expect(not screen.is_open(), "la pantalla de fin empieza cerrada")
	_take_loan_and_go_broke()
	_to_next_month()
	_expect(SaveManager.has_save(SaveManager.AUTOSAVE), "hay autoguardado")
	_to_next_month()
	var stats: Array[Dictionary] = []
	EventBus.game_over.connect(func(value: Dictionary) -> void: stats.append(value), CONNECT_ONE_SHOT)
	_to_next_month()
	await get_tree().process_frame
	_expect(Bank.game_over and stats.size() == 1, "sin muebles que alcancen se pierde la empresa")
	_expect(not SaveManager.has_save(SaveManager.AUTOSAVE), "se borra el autoguardado")
	_expect(screen.is_open(), "sale la pantalla de fin")
	var text: String = screen.get_text()
	_expect(text.contains("La empresa quebró") and text.contains("Días jugados: %d" % (GameClock.get_day_count() + 1))
		and text.contains("Empleados contratados: 2") and text.contains("Contratos entregados: 0") and text.contains("Mejor reputación"),
		"estadísticas: %s" % text)
	_expect(int(stats[0]["assets"]) == 0 and int(stats[0]["debt"]) > 0 if not stats.is_empty() else false, "deuda y bienes: %s" % [stats])
	# Después del fin no se autoguarda más ni se cobran cuotas.
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY * GameConstants.DAYS_PER_MONTH)
	_expect(not SaveManager.has_save(SaveManager.AUTOSAVE), "no vuelve a autoguardar")
	game.queue_free()
	await get_tree().process_frame
