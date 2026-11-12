# Prueba del hito 19: ánimo y renuncias.
# Criterio: un empleado con ánimo bajo varios días avisa y, si no se le retiene, se va;
# con un aumento a tiempo se queda.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=morale
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261111

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
	_check_targets()
	_check_drift()
	_check_resignation()
	_check_retention()
	_check_raise_request()
	_check_save()
	await _check_card()
	await _check_notice()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _morale(key: String) -> int:
	return int(StaffCatalog.get_morale(key))


# Partida nueva con un área de trabajo de dos puestos y dinero de sobra.
func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	Economy.earn(50000, "Prueba")
	var builder := Builder.new()
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
	]
	_expect(builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	for x: int in [3, 4]:
		_expect(builder.place("simple_desk", Vector2i(x, 0), 2)["ok"], "escritorio en %d" % x)
		_expect(builder.place("basic_chair", Vector2i(x, 1), 0)["ok"], "silla en %d" % x)
		_expect(builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "computadora en %d" % x)
	_notices.clear()


# Contrata a un programador Junior en la próxima llegada de candidatos.
func _hire() -> Dictionary:
	var vacancy_id: int = Staff.open_vacancy("programmer", "junior", 1000, true)["id"]
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	var candidate: Dictionary = Staff.get_vacancy(vacancy_id)["candidates"][0]
	Staff.make_offer(candidate["id"], candidate["asked_salary"])
	var employee: Dictionary = Staff.get_employee(candidate["id"])
	_expect(not employee.is_empty(), "contratado")
	return employee


# Pasa un día entero (una medianoche).
func _next_day() -> void:
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)


func _set_ratio(employee: Dictionary, ratio: float) -> void:
	employee["salary"] = roundi(Staff.get_market_salary(employee) * ratio)


# Un contrato llevado por el equipo de employee.
func _give_contract(employee: Dictionary) -> Dictionary:
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], employee["id"])
	if Projects.offers.is_empty():
		Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	var result: Dictionary = Projects.accept(Projects.offers[0]["id"])
	_expect(result["ok"], "aceptar el contrato: %s" % result.get("message", ""))
	var contract: Dictionary = Projects.contracts[-1]
	Projects.assign(contract["id"], team["id"])
	_expect(Staff._contract_of(employee) == contract, "el equipo lleva el contrato")
	return contract


func _check_targets() -> void:
	_new_game()
	var employee: Dictionary = _hire()
	var base: int = _morale("mood_base")
	var idle: int = _morale("idle_mood")
	_expect(Staff.is_idle(employee), "sin equipo no tiene trabajo")
	_set_ratio(employee, 1.0)
	_expect(Staff.get_mood_target(employee) == base + _morale("fair_mood") + idle, "sueldo justo y sin trabajo: %d" % Staff.get_mood_target(employee))
	_set_ratio(employee, 1.1)
	_expect(Staff.get_mood_target(employee) == base + _morale("well_paid_mood") + idle, "bien pagado: %d" % Staff.get_mood_target(employee))
	_set_ratio(employee, 0.95)
	_expect(Staff.get_mood_target(employee) == base + _morale("slightly_underpaid_mood") + idle, "algo por debajo")
	_set_ratio(employee, 0.8)
	_expect(Staff.get_mood_target(employee) == base + _morale("underpaid_mood") + idle, "mal pagado")
	employee["owed"] = 100
	_expect(Staff.get_mood_target(employee) == base + _morale("underpaid_mood") + idle + _morale("owed_mood"), "con nómina debida")
	employee["owed"] = 0
	employee["stress"] = _morale("stressed_from")
	_expect(Staff.get_mood_target(employee) == base + _morale("underpaid_mood") + idle + _morale("stressed_mood"), "estresado")
	employee["stress"] = 20
	# Con contrato ya no está ocioso; atrasado o cansado sube la meta del estrés.
	_set_ratio(employee, 1.0)
	var contract: Dictionary = _give_contract(employee)
	_expect(not Staff.is_idle(employee), "con contrato tiene trabajo")
	_expect(Staff.get_mood_target(employee) == base + _morale("fair_mood"), "sueldo justo y con trabajo: %d" % Staff.get_mood_target(employee))
	_expect(Staff.get_stress_target(employee) == _morale("stress_base"), "estrés base")
	contract["deadline_day"] = GameClock.get_day_count() - 1
	_expect(Staff.get_stress_target(employee) == _morale("stress_base") + _morale("late_stress"), "contrato atrasado: %d" % Staff.get_stress_target(employee))
	employee["min_energy"] = _morale("tired_below") - 1
	_expect(Staff.get_stress_target(employee) == _morale("stress_base") + _morale("late_stress") + _morale("tired_stress"), "y cansado")


func _check_drift() -> void:
	_new_game()
	var employee: Dictionary = _hire()
	_set_ratio(employee, 1.0)
	var target: int = Staff.get_mood_target(employee)
	employee["mood"] = target + 10
	_next_day()
	_expect(int(employee["mood"]) == target + 10 - _morale("mood_step"), "el ánimo baja %d por día hacia su meta: %d" % [
		_morale("mood_step"), employee["mood"]])
	_next_day()
	_next_day()
	_next_day()
	_expect(int(employee["mood"]) == target, "y se queda en la meta: %d" % employee["mood"])
	employee["mood"] = target - 2
	_next_day()
	_expect(int(employee["mood"]) == target, "sube sin pasarse: %d" % employee["mood"])
	# Un contrato atrasado sube el estrés de a stress_step.
	var contract: Dictionary = _give_contract(employee)
	contract["deadline_day"] = GameClock.get_day_count() - 1
	contract["cancel_day"] = GameClock.get_day_count() + 100
	var stress: int = employee["stress"]
	_next_day()
	_expect(int(employee["stress"]) == stress + _morale("stress_step"), "atrasado, el estrés sube: %d → %d" % [stress, employee["stress"]])


func _check_resignation() -> void:
	_new_game()
	var employee: Dictionary = _hire()
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], employee["id"])
	var key: String = Staff.employee_key(employee["id"])
	_expect(_seat_of(key) != null, "tiene puesto")
	# Mal pagado y sin trabajo: la meta queda en el borde y el ánimo arranca muy bajo.
	_set_ratio(employee, 0.5)
	employee["mood"] = 5
	for day: int in range(_morale("quit_bad_days") - 1):
		_next_day()
		_expect(int(employee["quit_day"]) == Staff.NO_QUIT, "el día %d todavía no avisa" % (day + 1))
	_notices.clear()
	_next_day()
	_expect(int(employee["bad_days"]) == _morale("quit_bad_days"), "días mal: %d" % employee["bad_days"])
	_expect(Staff.quit_days_left(employee) == _morale("notice_days"), "avisa que se va en %d días: %d" % [
		_morale("notice_days"), Staff.quit_days_left(employee)])
	_expect(_notices.has("%s avisa que renuncia: se va en %d días si no le das un aumento." % [employee["name"], _morale("notice_days")]),
		"aviso de renuncia: %s" % [_notices])
	for day: int in range(_morale("notice_days") - 1):
		_next_day()
	_expect(Staff.quit_days_left(employee) == 1 and not Staff.get_employee(employee["id"]).is_empty(), "le queda un día")
	_next_day()
	_expect(Staff.get_employee(employee["id"]).is_empty(), "sin aumento, se va")
	var cost: int = Staff.get_firing_cost(employee)
	var movement: Dictionary = Economy.movements[-1]
	_expect(movement["concept"] == Staff.CONCEPT_RESIGNATION and int(movement["amount"]) == -cost and cost > 0,
		"se le paga lo ganado: %s, esperado %d" % [movement, cost])
	_expect(_seat_of(key) == null, "su puesto queda libre")
	_expect(not (Staff.get_team(team["id"])["members"] as Array).has(employee["id"]), "sale de su equipo")
	_expect(_notices[-1].begins_with("%s renunció y se fue" % employee["name"]), "aviso: %s" % _notices[-1])


func _seat_of(key: String) -> Variant:
	for item: Dictionary in OfficeState.furniture:
		if item["assigned_to"] == key:
			return item
	return null


func _check_retention() -> void:
	_new_game()
	var employee: Dictionary = _hire()
	_set_ratio(employee, 0.5)
	employee["mood"] = 5
	for day: int in range(_morale("quit_bad_days")):
		_next_day()
	_expect(Staff.quit_days_left(employee) > 0, "avisó que renuncia")
	var salary: int = employee["salary"]
	# Lo ganado hasta hoy queda con el sueldo anterior.
	var earned: int = Staff.get_earned(employee)
	var small: Dictionary = Staff.give_raise(employee["id"], salary + 10)
	_expect(small["ok"] and small["message"].contains("No le alcanza"), "un aumento chico no lo retiene: %s" % small["message"])
	_expect(Staff.quit_days_left(employee) > 0, "sigue con el aviso")
	_expect(Staff.get_earned(employee) == earned, "lo ganado no cambia con el aumento: %d" % Staff.get_earned(employee))
	_expect(not Staff.give_raise(employee["id"], employee["salary"])["ok"], "un sueldo igual no es aumento")
	var mood: int = employee["mood"]
	salary = employee["salary"]
	var big: Dictionary = Staff.give_raise(employee["id"], ceili(salary * (1.0 + StaffCatalog.get_morale("retain_raise_ratio"))))
	_expect(big["ok"] and big["message"].contains("Se queda"), "un aumento del 10 %% lo retiene: %s" % big["message"])
	_expect(int(employee["quit_day"]) == Staff.NO_QUIT and int(employee["bad_days"]) == 0, "ya no renuncia")
	_expect(int(employee["mood"]) == mood + _morale("retain_mood"), "el ánimo sube %d: %d" % [_morale("retain_mood"), employee["mood"]])
	_expect(int(employee["last_raise_day"]) == GameClock.get_day_count(), "anota el día del aumento")
	for day: int in range(_morale("notice_days") + 2):
		_next_day()
	_expect(not Staff.get_employee(employee["id"]).is_empty(), "días después sigue en la empresa")
	# Lo ganado sigue sumando: el sueldo viejo hasta el aumento y el nuevo desde ahí.
	_expect(Staff.get_earned(employee) > earned, "sigue ganando")


func _check_raise_request() -> void:
	_new_game()
	var employee: Dictionary = _hire()
	_set_ratio(employee, 1.0)
	var today: int = GameClock.get_day_count()
	# Recién contratado no pide aumento.
	for i: int in range(300):
		Staff._maybe_ask_raise(employee, today)
	_expect((employee["raise_request"] as Dictionary).is_empty(), "antes de %d días no pide" % _morale("raise_request_min_days"))
	employee["last_raise_day"] = today - _morale("raise_request_min_days")
	# Bien pagado tampoco.
	_set_ratio(employee, StaffCatalog.get_morale("raise_request_below_ratio"))
	for i: int in range(300):
		Staff._maybe_ask_raise(employee, today)
	_expect((employee["raise_request"] as Dictionary).is_empty(), "bien pagado no pide")
	_set_ratio(employee, 1.0)
	var tries: int = 0
	while (employee["raise_request"] as Dictionary).is_empty() and tries < 1000:
		Staff._maybe_ask_raise(employee, today)
		tries += 1
	var chance: float = StaffCatalog.get_morale("raise_request_chance")
	_expect(tries > 1 and tries < 10.0 / chance, "pide aumento cada tanto: tras %d días" % tries)
	var request: Dictionary = employee["raise_request"]
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	_expect(int(request["amount"]) % step == 0 and absi(int(request["amount"]) - roundi(employee["salary"] * StaffCatalog.get_morale("raise_request_ratio"))) <= step / 2,
		"pide un 10 %%: %d de %d" % [request["amount"], employee["salary"]])
	_expect(int(request["until_day"]) == today + _morale("raise_request_days"), "tiene %d días para responder" % _morale("raise_request_days"))
	_expect(_notices[-1] == "%s pide un aumento de %s." % [employee["name"], MoneyFormat.format(int(request["amount"]))], "aviso: %s" % _notices[-1])
	# Negarlo baja el ánimo.
	var mood: int = employee["mood"]
	_expect(Staff.deny_raise(employee["id"]), "negar")
	_expect(int(employee["mood"]) == mood + _morale("raise_deny_mood") and (employee["raise_request"] as Dictionary).is_empty(),
		"negado baja %d: %d" % [_morale("raise_deny_mood"), employee["mood"]])
	_expect(not Staff.deny_raise(employee["id"]), "sin pedido no hay nada que negar")
	# Dejarlo pasar también.
	employee["raise_request"] = {"amount": 100, "until_day": today + 1}
	employee["mood"] = Staff.get_mood_target(employee)
	mood = employee["mood"]
	_next_day()
	_expect((employee["raise_request"] as Dictionary).is_empty() and int(employee["mood"]) == mood + _morale("raise_deny_mood"),
		"sin respuesta vence y baja el ánimo: %d → %d" % [mood, employee["mood"]])
	# Aceptarlo lo sube.
	employee["raise_request"] = {"amount": 100, "until_day": GameClock.get_day_count() + 3}
	mood = employee["mood"]
	var salary: int = employee["salary"]
	_expect(Staff.give_raise(employee["id"], salary + 100)["ok"], "dar el aumento pedido")
	_expect((employee["raise_request"] as Dictionary).is_empty() and int(employee["mood"]) == mood + _morale("raise_accept_mood")
		and int(employee["salary"]) == salary + 100, "aceptado sube %d: %d" % [_morale("raise_accept_mood"), employee["mood"]])


func _check_save() -> void:
	_new_game()
	var employee: Dictionary = _hire()
	_set_ratio(employee, 0.5)
	employee["mood"] = 5
	for day: int in range(_morale("quit_bad_days")):
		_next_day()
	Staff.give_raise(employee["id"], employee["salary"] + 10)
	employee["raise_request"] = {"amount": 150, "until_day": GameClock.get_day_count() + 2}
	_expect(int(employee["carry"]) > 0 and int(employee["quit_day"]) != Staff.NO_QUIT, "estado con aviso, pedido y lo ganado aparte")
	var before: String = JSON.stringify(Staff.export_state())
	_expect(SaveManager.save_game("slot_4"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_4"), "cargar")
	_expect(JSON.stringify(Staff.export_state()) == before, "el ánimo y los avisos vuelven igual")
	# Una partida de antes del hito 19 carga sin avisos ni pedidos.
	var old: Dictionary = Staff.export_state()
	for saved: Dictionary in old["employees"]:
		for field: String in ["carry", "bad_days", "quit_day", "min_energy", "last_raise_day", "raise_request"]:
			saved.erase(field)
	Staff.import_state(old)
	var loaded: Dictionary = Staff.employees[0]
	_expect(int(loaded["quit_day"]) == Staff.NO_QUIT and (loaded["raise_request"] as Dictionary).is_empty()
		and int(loaded["carry"]) == 0 and int(loaded["bad_days"]) == 0, "partida vieja: %s" % [loaded])


func _check_card() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var employee: Dictionary = _hire()
	var card: EmployeeCard = game.get_node("EmployeeCard")
	employee["quit_day"] = GameClock.get_day_count() + 4
	employee["raise_request"] = {"amount": 100, "until_day": GameClock.get_day_count() + 2}
	card.open_employee(employee["id"])
	await get_tree().process_frame
	employee["mood"] = 25
	card.refresh()
	var text: String = card.get_text()
	_expect(text.contains("Rinde 85 % (desanimado)"), "la ficha muestra el rendimiento: %s" % text)
	_expect(text.contains("Renuncia: se va en 4 días"), "la ficha muestra el aviso: %s" % text)
	_expect(text.contains("Pide un aumento de %s (2 días para responder" % MoneyFormat.format(100)), "y el pedido: %s" % text)
	_expect(card.get_accept_raise_button().is_visible_in_tree() and card.get_deny_raise_button().is_visible_in_tree(), "botones del pedido")
	# Aceptar el pedido (100 de 1000 y algo no llega al 10 %: sigue el aviso).
	var salary: int = employee["salary"]
	await _click(card.get_accept_raise_button())
	_expect(int(employee["salary"]) == salary + 100 and (employee["raise_request"] as Dictionary).is_empty(), "aceptado desde la ficha: %d" % employee["salary"])
	await get_tree().process_frame
	_expect(not card.get_accept_raise_button().is_visible_in_tree(), "sin pedido no hay botones")
	# La fila Aumento arranca en lo justo para retener y cambia de a salary_step.
	salary = employee["salary"]
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	var retain: int = ceili(salary * StaffCatalog.get_morale("retain_raise_ratio") / step) * step
	_expect(card.get_raise_amount() == retain, "aumento propuesto %d, esperado %d" % [card.get_raise_amount(), retain])
	await _click(card.get_raise_plus_button())
	_expect(card.get_raise_amount() == retain + step, "+ suma %d" % step)
	await _click(card.get_raise_minus_button())
	_expect(card.get_raise_amount() == retain, "− resta")
	_expect(card.get_text().contains("Aumento +%s → %s" % [MoneyFormat.format(retain), MoneyFormat.format(salary + retain)]), "fila Aumento: %s" % card.get_text())
	await _click(card.get_raise_button())
	_expect(int(employee["salary"]) == salary + retain and int(employee["quit_day"]) == Staff.NO_QUIT, "Dar aumento lo retiene: %d" % employee["salary"])
	await get_tree().process_frame
	_expect(not card.get_text().contains("Renuncia: se va"), "la ficha ya no muestra el aviso")
	game.queue_free()
	await get_tree().process_frame


# El aviso del Hud no tapa el dinero ni el reloj: un texto largo se parte en líneas.
func _check_notice() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var hud: Hud = game.get_node("Hud")
	Economy.earn(9000000, "Prueba")  # un saldo largo ensancha el panel del dinero
	EventBus.notice.emit("Un aviso muy largo que antes se metía debajo del reloj: " + "bla ".repeat(40))
	await get_tree().process_frame
	await get_tree().process_frame
	var rect: Rect2 = hud.get_notice_rect()
	_expect(get_viewport().get_visible_rect().encloses(rect) and rect.size.y < 200.0, "el aviso entra en pantalla: %s" % rect)
	for corner: Rect2 in hud.get_corner_rects():
		_expect(not rect.intersects(corner), "el aviso no tapa %s: %s" % [corner, rect])
	EventBus.notice.emit("Corto.")
	await get_tree().process_frame
	await get_tree().process_frame
	rect = hud.get_notice_rect()
	_expect(hud.get_notice_text() == "Corto." and rect.size.x < 200.0 and absf(rect.get_center().x - get_viewport().get_visible_rect().size.x / 2.0) < 2.0,
		"un aviso corto queda chico y centrado: %s" % rect)
	game.queue_free()
	await get_tree().process_frame


func _click(control: Control) -> void:
	var card: Node = control.get_parent()
	while card != null and not card is EmployeeCard:
		card = card.get_parent()
	if card != null:
		(card as EmployeeCard).reveal(control)
		await get_tree().process_frame
	var at: Vector2 = control.get_global_rect().get_center()
	_expect(get_viewport().get_visible_rect().has_point(at), "%s visible en pantalla" % control.text)
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
