# Prueba del hito 13: nómina y despidos.
# Criterio: el día 15 el saldo baja exactamente la mitad de la suma de sueldos; un
# despido el día 10 cobra 10/30 del sueldo.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=payroll
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261111
const FRAME: float = 1.0 / 60.0

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
	# Estas pruebas son de la nómina sin préstamo de emergencia (hito 24): se rechaza.
	EventBus.emergency_loan_offered.connect(func(_offer: Dictionary) -> void: Bank.reject_emergency())
	_check_payroll_days()
	_check_firing()
	_check_prorated()
	_check_unpaid()
	_check_save()
	await _check_card()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva con un área de trabajo de tres puestos (escritorios en x 3–5).
func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Economy.earn(20000, "Prueba")
	var builder := Builder.new()
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	for x: int in [3, 4, 5]:
		_expect(builder.place("simple_desk", Vector2i(x, 0), 2)["ok"], "escritorio en %d" % x)
		_expect(builder.place("basic_chair", Vector2i(x, 1), 0)["ok"], "silla en %d" % x)
		_expect(builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "computadora en %d" % x)
	_notices.clear()


# Contrata a count empleados (uno por vacante) en la próxima llegada de candidatos.
func _hire(count: int) -> Array[Dictionary]:
	var roles: Array[String] = ["programmer", "designer", "qa"]
	var vacancy_ids: Array[int] = []
	for i: int in range(count):
		vacancy_ids.append(Staff.open_vacancy(roles[i], "junior", 1000, true)["id"])
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	var hired: Array[Dictionary] = []
	for vacancy_id: int in vacancy_ids:
		var candidate: Dictionary = Staff.get_vacancy(vacancy_id)["candidates"][0]
		Staff.make_offer(candidate["id"], candidate["asked_salary"])
		hired.append(Staff.get_employee(candidate["id"]))
	_expect(Staff.employees.size() >= count, "contratados %d" % count)
	return hired


# Avanza hasta las 0:00 del día day del mes actual (o del siguiente si ya pasó).
func _to_day(day: int, month: int) -> void:
	var target: int = (month - 1) * GameConstants.DAYS_PER_MONTH + day - 1
	var hours: int = (target - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY - GameClock.get_hour()
	GameClock.fast_forward_hours(hours)
	_expect(GameClock.get_day() == day and GameClock.get_month() == month and GameClock.get_hour() == 0,
		"llegar al día %d del mes %d" % [day, month])


func _salary_sum() -> int:
	var total: int = 0
	for employee: Dictionary in Staff.employees:
		total += int(employee["salary"])
	return total


func _last_movement() -> Dictionary:
	return Economy.movements[-1]


func _check_payroll_days() -> void:
	_new_game()
	var hired: Array[Dictionary] = _hire(3)
	_expect(GameClock.get_day() == 1, "contratados el día 1")
	for employee: Dictionary in hired:
		_expect(int(employee["paid_until"]) == -1 and int(employee["owed"]) == 0, "nadie cobró todavía")
	var sum: int = _salary_sum()
	_to_day(14, 1)
	var before: int = Economy.balance
	_to_day(15, 1)
	_expect(before - Economy.balance == sum / 2, "el día 15 se paga la mitad de los sueldos: %d de %d" % [before - Economy.balance, sum])
	_expect(_last_movement()["concept"] == Staff.CONCEPT_PAYROLL and _last_movement()["amount"] == -sum / 2,
		"movimiento de nómina: %s" % [_last_movement()])
	_expect(_notices.has("Nómina pagada: %s." % MoneyFormat.format(sum / 2)), "aviso de nómina: %s" % [_notices])
	var earned: int = Staff.get_earned(hired[0])
	_expect(earned == 0, "tras la nómina no tiene nada ganado sin pagar: %d" % earned)
	before = Economy.balance
	_to_day(30, 1)
	_expect(before - Economy.balance == sum / 2, "el día 30 otra mitad")
	# El día 1 del mes 2 solo se cobra el mantenimiento.
	before = Economy.balance
	_to_day(1, 2)
	_expect(before - Economy.balance == Economy.get_maintenance(OfficeState.lot_rect.get_area()), "el día 1 no hay nómina")


func _check_firing() -> void:
	# Sigue la partida anterior: tres empleados pagados hasta el día 30 del mes 1.
	_to_day(10, 2)
	var first: Dictionary = Staff.employees[0]
	var salary: int = first["salary"]
	var cost: int = roundi(salary * 10 / 30.0)
	_expect(Staff.get_firing_cost(first) == cost, "despedir el día 10 cuesta 10/30 del sueldo: %d" % Staff.get_firing_cost(first))
	var free_before: int = Staff.get_free_workstations().size()
	var before: int = Economy.balance
	# Desde el hito 19 el ánimo cambia cada día: se compara con el de justo antes.
	var moods: Dictionary[int, int] = {}
	for other: Dictionary in Staff.employees:
		moods[other["id"]] = int(other["mood"])
	var result: Dictionary = Staff.fire(first["id"])
	_expect(result["ok"] and before - Economy.balance == cost, "el despido cobra %d: %d" % [cost, before - Economy.balance])
	_expect(_last_movement()["concept"] == Staff.CONCEPT_FIRING, "movimiento de despido")
	_expect(Staff.get_employee(first["id"]).is_empty() and Staff.employees.size() == 2, "deja de ser empleado")
	_expect(OfficeState.find_furniture_assigned_to(Staff.employee_key(first["id"])).is_empty()
		and Staff.get_free_workstations().size() == free_before + 1, "su puesto queda libre")
	for other: Dictionary in Staff.employees:
		_expect(int(other["mood"]) == moods[other["id"]] - 5, "los compañeros bajan 5 de ánimo: %d" % other["mood"])
	# Otro despido dentro de los 7 días baja más.
	_to_day(12, 2)
	var survivor_mood: int = int(Staff.employees[1]["mood"])
	Staff.fire(Staff.employees[0]["id"])
	_expect(int(Staff.employees[0]["mood"]) == survivor_mood - 10, "seguidos bajan 10: %d" % Staff.employees[0]["mood"])
	_expect(not Staff.fire(first["id"])["ok"], "no se despide dos veces")


func _check_prorated() -> void:
	_new_game()
	_to_day(10, 1)
	var hired: Array[Dictionary] = _hire(1)
	var salary: int = hired[0]["salary"]
	var before: int = Economy.balance
	_to_day(15, 1)
	_expect(before - Economy.balance == roundi(salary * 6 / 30.0),
		"contratado el día 10, el 15 cobra 6/30: %d" % [before - Economy.balance])


func _check_unpaid() -> void:
	# Sigue la partida anterior: un empleado pagado hasta el 15.
	var employee: Dictionary = Staff.employees[0]
	# Bien pagado para que el ánimo no baje tanto como para renunciar (hito 19).
	employee["salary"] = roundi(Staff.get_market_salary(employee) * 1.2)
	var half: int = int(employee["salary"]) / 2
	Economy.charge(Economy.balance - 10, "Prueba")
	_expect(Economy.balance == 10, "saldo casi vacío")
	_notices.clear()
	_to_day(29, 1)
	var mood_before: int = int(employee["mood"])
	_to_day(30, 1)
	_expect(Economy.balance == 10 and int(employee["owed"]) == half and Staff.get_total_owed() == half,
		"sin dinero no se paga y queda la deuda: %d" % employee["owed"])
	# −20 de golpe y después el paso diario hacia su meta (como mucho 3).
	_expect(absi(int(employee["mood"]) - (mood_before - 20)) <= 3, "la nómina sin pagar baja 20 el ánimo: %d → %d" % [
		mood_before, employee["mood"]])
	_expect(not _notices.is_empty() and _notices[-1].begins_with("No alcanza el dinero para la nómina"), "aviso: %s" % [_notices])
	# El despido incluye lo debido.
	_expect(Staff.get_firing_cost(employee) == half, "despedir hoy cuesta lo debido: %d" % Staff.get_firing_cost(employee))
	# Otra nómina sin dinero acumula deuda y vuelve a bajar el ánimo.
	mood_before = int(employee["mood"])
	_to_day(15, 2)
	_expect(int(employee["owed"]) == half * 2 and int(employee["mood"]) < mood_before, "deuda acumulada: %d, ánimo %d" % [
		employee["owed"], employee["mood"]])
	# Apenas entra dinero suficiente se paga sola, toda junta. (El día 1 se cobró el
	# mantenimiento: el saldo vuelve a $10 para que las cuentas sean claras.)
	Economy.earn(10 - Economy.balance, "Prueba")
	Economy.earn(half, "Cobro parcial")
	_expect(int(employee["owed"]) == half * 2, "si todavía no alcanza, sigue la deuda")
	Economy.earn(half * 2, "Cobro")
	_expect(int(employee["owed"]) == 0 and Economy.balance == 10 + half, "la deuda se paga sola: saldo %d" % Economy.balance)
	_expect(_last_movement()["concept"] == Staff.CONCEPT_PAYROLL and _last_movement()["amount"] == -half * 2, "movimiento de la deuda")
	# Un despido con poco dinero deja el saldo negativo.
	_to_day(20, 2)
	var cost: int = Staff.get_firing_cost(employee)
	Economy.charge(Economy.balance, "Prueba")
	Staff.fire(employee["id"])
	_expect(Economy.balance == -cost and cost > 0, "el despido se cobra aunque no alcance: %d" % Economy.balance)


func _check_save() -> void:
	_new_game()
	_hire(2)
	_to_day(15, 1)
	Economy.charge(Economy.balance, "Prueba")
	_to_day(30, 1)
	Staff.fire(Staff.employees[0]["id"])
	var before: String = JSON.stringify(Staff.export_state())
	_expect(Staff.get_total_owed() > 0 and Staff.last_firing_day == 29, "estado con deuda y un despido")
	_expect(SaveManager.save_game("slot_3"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_3"), "cargar")
	_expect(JSON.stringify(Staff.export_state()) == before, "la nómina vuelve igual")
	# Un empleado de una partida del hito 12 gana desde su contratación.
	var old: Dictionary = Staff.export_state()
	for saved: Dictionary in old["employees"]:
		saved.erase("paid_until")
		saved.erase("owed")
	old.erase("last_firing_day")
	Staff.import_state(old)
	var employee: Dictionary = Staff.employees[0]
	_expect(int(employee["paid_until"]) == int(employee["hired_day"]) - 1 and int(employee["owed"]) == 0
		and Staff.last_firing_day == Staff.NO_FIRING, "partida vieja: %s" % [employee])


func _check_card() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var hired: Array[Dictionary] = _hire(2)
	var target: Dictionary = hired[0]
	var character: Employee = game.employees[target["id"]]
	for employee_id: int in game.employees:
		game.employees[employee_id].set_process(false)
	_walk(game, func() -> bool: return character.activity == OfficeCharacter.Activity.SEATED, 60.0)
	GameClock.fast_forward_hours(24 * 2)  # día 3 a las 9:00
	var hud: Hud = game.get_node("Hud")
	var card: EmployeeCard = game.get_node("EmployeeCard")
	card.open_employee(target["id"])
	await get_tree().process_frame
	var cost: int = Staff.get_firing_cost(target)
	_expect(card.get_text().contains("Ganado desde el último pago: %s" % MoneyFormat.format(cost)), "la ficha muestra lo ganado: %s" % card.get_text())
	await _click(card.get_fire_button())
	await get_tree().process_frame
	_expect(Staff.get_employee(target["id"]).size() > 0, "Despedir pide confirmación")
	_expect(card.get_text().contains("¿Despedir a %s? Cuesta %s" % [target["name"], MoneyFormat.format(cost)]),
		"la confirmación muestra el costo: %s" % card.get_text())
	await _click(card.get_confirm_fire_button())
	_expect(Staff.get_employee(target["id"]).is_empty(), "confirmado, queda despedido")
	await get_tree().process_frame
	_expect(not card.is_open(), "la ficha se cierra")
	_expect(hud.get_notice_text() == "Despediste a %s: %s." % [target["name"], MoneyFormat.format(cost)], "aviso: %s" % hud.get_notice_text())
	_expect(not game.employees.has(target["id"]) and character.activity == OfficeCharacter.Activity.WALKING_OUT,
		"el despedido sale caminando")
	_walk(game, func() -> bool: return not is_instance_valid(character) or character.is_queued_for_deletion(), 60.0)
	_expect(not is_instance_valid(character) or character.is_queued_for_deletion(), "al salir desaparece")
	_expect(game.get_characters().size() == 2, "quedan el CEO y un empleado")
	# Con deuda el reloj lo muestra.
	Economy.charge(Economy.balance, "Prueba")
	_to_day(15, 1)
	await get_tree().process_frame
	_expect(hud.get_clock_text().contains("Nómina pendiente: %s" % MoneyFormat.format(Staff.get_total_owed())), "reloj: %s" % hud.get_clock_text())
	game.queue_free()
	await get_tree().process_frame


func _walk(game: Node, condition: Callable, max_seconds: float) -> void:
	var elapsed: float = 0.0
	while not condition.call() and elapsed < max_seconds:
		GameClock.advance(FRAME)
		for character: OfficeCharacter in game.get_characters():
			if is_instance_valid(character):
				character._process(FRAME)
		elapsed += FRAME


func _click(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	await _push(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _push(event)


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame
