# Prueba del hito 30: ascensos por experiencia.
# Criterio: un Pasante con 3 contratos y 30 días puede ascender a Junior: produce 16
# puntos por jornada y su sueldo cambia en la nómina; antes de los umbrales no puede.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=promotions
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261112

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_thresholds()
	_check_counting()
	_check_promotion()
	_check_retention()
	_check_save()
	await _check_card()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva con un área de trabajo de tres puestos, dinero de sobra y los
# objetivos ya cumplidos (para que sus recompensas no cambien el saldo).
func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(50000, "Prueba")
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


# Contrata a alguien de ese cargo y nivel en la próxima llegada de candidatos.
func _hire(role: String, level: String) -> Dictionary:
	var vacancy_id: int = Staff.open_vacancy(role, level, StaffCatalog.get_salary(role, level), true)["id"]
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)
	var candidate: Dictionary = Staff.get_vacancy(vacancy_id)["candidates"][0]
	Staff.make_offer(candidate["id"], candidate["asked_salary"])
	var employee: Dictionary = Staff.get_employee(candidate["id"])
	# Sin rasgos (hito 50): esta prueba mide rendimientos exactos.
	(employee.get("traits", []) as Array).clear()
	_expect(not employee.is_empty(), "contratado: %s %s" % [role, level])
	return employee


# Lleva al equipo un contrato pequeño, lo trabaja unas horas de un día hábil y lo
# entrega (o lo cancela).
func _work_contract(team_id: int, deliver: bool) -> void:
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	var result: Dictionary = Projects.accept(Projects.offers[-1]["id"])
	_expect(result["ok"], "aceptar: %s" % result.get("message", ""))
	var contract: Dictionary = Projects.contracts[-1]
	Projects.assign(contract["id"], team_id)
	# Hasta las 10 del próximo día hábil.
	while true:
		GameClock.fast_forward_hours(1)
		if GameClock.get_hour() == 10 and GameClock.get_weekday() < 5:
			break
	var outcome: Dictionary = Projects.deliver(contract["id"]) if deliver else Projects.cancel(contract["id"])
	_expect(outcome["ok"], "terminar el contrato")


func _check_thresholds() -> void:
	_new_game()
	var employee: Dictionary = _hire("programmer", "intern")
	var progress: Dictionary = Staff.get_promotion_progress(employee)
	_expect(progress["next_level"] == "junior", "un Pasante asciende a Junior")
	_expect(int(progress["projects_needed"]) == 3 and int(progress["days_needed"]) == 30, "pide 3 contratos y 30 días: %s" % progress)
	_expect(not bool(progress["ready"]), "recién contratado no cumple")
	_expect(not Staff.promote_problem(employee["id"], 2000).is_empty(), "no se puede ascender todavía")
	# Con los días pero sin los contratos tampoco.
	employee["hired_day"] = GameClock.get_day_count() - 30
	_expect(not bool(Staff.get_promotion_progress(employee)["ready"]), "30 días sin contratos no alcanza")
	employee["projects_worked"] = 3
	employee["hired_day"] = GameClock.get_day_count() - 29
	_expect(not bool(Staff.get_promotion_progress(employee)["ready"]), "3 contratos y 29 días no alcanza")
	employee["hired_day"] = GameClock.get_day_count() - 30
	_expect(bool(Staff.get_promotion_progress(employee)["ready"]), "3 contratos y 30 días cumple")
	# Los días cuentan solos con el reloj.
	employee["hired_day"] = GameClock.get_day_count()
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY * 3)
	_expect(int(Staff.get_promotion_progress(employee)["days"]) == 3, "días en la empresa: %d" % Staff.get_promotion_progress(employee)["days"])
	# Los niveles siguientes piden más; un Senior ya no asciende.
	employee["level"] = "junior"
	progress = Staff.get_promotion_progress(employee)
	_expect(progress["next_level"] == "semi_senior" and int(progress["projects_needed"]) == 8 and int(progress["days_needed"]) == 90, "Junior → SemiSenior: 8 y 90")
	employee["level"] = "semi_senior"
	progress = Staff.get_promotion_progress(employee)
	_expect(progress["next_level"] == "senior" and int(progress["projects_needed"]) == 15 and int(progress["days_needed"]) == 180, "SemiSenior → Senior: 15 y 180")
	employee["level"] = "senior"
	employee["projects_worked"] = 99
	employee["hired_day"] = -999
	progress = Staff.get_promotion_progress(employee)
	_expect(String(progress["next_level"]).is_empty() and not bool(progress["ready"]), "un Senior no asciende de nivel (ni a líder en Emprendimiento)")
	_expect(Staff.promote_problem(employee["id"], 9999).contains("Startup"), "y dice que ser líder llega en Startup")


func _check_counting() -> void:
	_new_game()
	var worker: Dictionary = _hire("programmer", "intern")
	var outsider: Dictionary = _hire("designer", "intern")
	var seller: Dictionary = _hire("salesperson", "intern")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], worker["id"])
	_work_contract(team["id"], true)
	_expect(int(worker["projects_worked"]) == 1, "el que trabajó cuenta el contrato entregado: %d" % worker["projects_worked"])
	_expect(int(outsider["projects_worked"]) == 0, "el que no trabajó en él no lo cuenta")
	_expect(int(seller["projects_worked"]) == 1, "el vendedor cuenta el contrato aceptado: %d" % seller["projects_worked"])
	_work_contract(team["id"], false)
	_expect(int(worker["projects_worked"]) == 1, "un contrato cancelado no cuenta: %d" % worker["projects_worked"])
	_expect(int(seller["projects_worked"]) == 2, "pero el vendedor sí cuenta haberlo aceptado")
	# Aceptado y entregado sin que nadie trabaje: no cuenta para nadie.
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	Projects.assign(contract["id"], Projects.NO_TEAM)
	Projects.deliver(contract["id"])
	_expect(int(worker["projects_worked"]) == 1, "sin trabajar no cuenta")
	# Quien deja la empresa no rompe la cuenta de los demás.
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	contract = Projects.contracts[-1]
	contract["worked_by"] = [Staff.employee_key(worker["id"]), Staff.employee_key(999)]
	Projects.deliver(contract["id"])
	_expect(int(worker["projects_worked"]) == 2, "un empleado que ya no está se ignora")


func _check_promotion() -> void:
	_new_game()
	var employee: Dictionary = _hire("programmer", "intern")
	var team: Dictionary = Staff.create_team()
	Staff.add_to_team(team["id"], employee["id"])
	for i: int in range(3):
		_work_contract(team["id"], true)
	_expect(int(employee["projects_worked"]) == 3, "3 contratos trabajados")
	employee["hired_day"] = GameClock.get_day_count() - 30
	var salary: int = employee["salary"]
	_expect(Staff.promote(employee["id"], salary)["ok"] == false, "con el mismo sueldo no asciende")
	_expect(employee["level"] == "intern", "sigue de Pasante")
	# Lo ganado hasta hoy queda con el sueldo anterior.
	var earned_before: int = Staff.get_earned(employee)
	var new_salary: int = StaffCatalog.get_salary("programmer", "junior")
	var skill_before: int = int(employee["skills"]["programming"])
	var result: Dictionary = Staff.promote(employee["id"], new_salary)
	_expect(result["ok"], "asciende: %s" % result["message"])
	_expect(String(result["message"]).contains("asciende a Programador Junior"), "aviso: %s" % result["message"])
	_expect(employee["level"] == "junior" and int(employee["salary"]) == new_salary, "ahora es Junior con %d" % employee["salary"])
	_expect(int(employee["skills"]["programming"]) >= StaffCatalog.get_main_skill_range("junior").x
		and int(employee["skills"]["programming"]) >= skill_before, "su habilidad principal llega al mínimo de Junior: %d" % employee["skills"]["programming"])
	_expect(int(employee["projects_worked"]) == 3, "conserva sus contratos para el próximo ascenso")
	_expect(not bool(Staff.get_promotion_progress(employee)["ready"]), "para SemiSenior le falta")
	# Produce como Junior: 2 puntos por hora, 16 por jornada de 8 horas.
	employee["energy"] = 100
	employee["mood"] = 100
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	Projects.assign(contract["id"], team["id"])
	var at: int = Staff.get_absolute_hour()
	while not Staff.is_expected(Staff.employee_key(employee["id"]), Staff.get_weekday_at(at), posmod(at, 24)) or Staff.is_at_lunch(Staff.employee_key(employee["id"])):
		at += 1
	var workers: Array[Dictionary] = Projects.get_workers(contract, at)
	_expect(workers.size() == 1 and is_equal_approx(float(workers[0]["rate"]) * 8.0, 16.0), "rinde 16 puntos por jornada: %s" % [workers])
	_expect(is_equal_approx(float(workers[0]["bug_chance"]), Projects.get_bug_chance("junior", 100.0)), "comete errores como Junior")
	# La nómina paga lo de antes con el sueldo viejo y lo nuevo con el nuevo.
	_expect(int(employee["carry"]) == earned_before, "lo ganado como Pasante queda aparte: %d" % employee["carry"])
	var promoted_day: int = GameClock.get_day_count()
	var count: int = Economy.movements.size()
	var paid: int = 0
	while paid == 0:
		GameClock.fast_forward_hours(1)
		for movement: Dictionary in Economy.movements.slice(count):
			if movement["concept"] == Staff.CONCEPT_PAYROLL:
				paid = absi(int(movement["amount"]))
		count = Economy.movements.size()
	var expected: int = earned_before + roundi(new_salary * (GameClock.get_day_count() - promoted_day) / 30.0)
	_expect(paid == expected, "la nómina paga lo de Pasante más lo nuevo como Junior: %d de %d" % [paid, expected])


func _check_retention() -> void:
	_new_game()
	var employee: Dictionary = _hire("programmer", "intern")
	employee["projects_worked"] = 3
	employee["hired_day"] = GameClock.get_day_count() - 30
	employee["quit_day"] = GameClock.get_day_count() + 3
	employee["raise_request"] = {"amount": 60, "until_day": GameClock.get_day_count() + 2}
	var salary: int = employee["salary"]
	Staff.promote(employee["id"], salary * 2)
	_expect(int(employee["quit_day"]) == Staff.NO_QUIT, "el ascenso con aumento lo retiene")
	_expect((employee["raise_request"] as Dictionary).is_empty(), "y cubre el aumento que pidió")
	_expect(int(employee["last_raise_day"]) == GameClock.get_day_count(), "cuenta como aumento")


func _check_save() -> void:
	_new_game()
	var employee: Dictionary = _hire("programmer", "intern")
	employee["projects_worked"] = 2
	Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[-1]["id"])
	Projects.contracts[-1]["worked_by"] = [Staff.employee_key(employee["id"])]
	var staff_before: String = JSON.stringify(Staff.export_state())
	var projects_before: String = JSON.stringify(Projects.export_state())
	_expect(SaveManager.save_game("slot_4"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_4"), "cargar")
	_expect(JSON.stringify(Staff.export_state()) == staff_before, "los contratos trabajados vuelven igual")
	_expect(JSON.stringify(Projects.export_state()) == projects_before, "quién trabajó en cada contrato vuelve igual")
	# Una partida de antes del hito 30 carga sin contratos trabajados.
	var old_staff: Dictionary = Staff.export_state()
	for saved: Dictionary in old_staff["employees"]:
		saved.erase("projects_worked")
	Staff.import_state(old_staff)
	_expect(int(Staff.employees[0]["projects_worked"]) == 0, "partida vieja: 0 contratos trabajados")
	var old_projects: Dictionary = Projects.export_state()
	for saved: Dictionary in old_projects["contracts"]:
		saved.erase("worked_by")
	Projects.import_state(old_projects)
	_expect((Projects.contracts[0]["worked_by"] as Array).is_empty(), "partida vieja: nadie anotado en el contrato")


func _check_card() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var employee: Dictionary = _hire("programmer", "intern")
	var card: EmployeeCard = game.get_node("EmployeeCard")
	employee["projects_worked"] = 1
	employee["hired_day"] = GameClock.get_day_count() - 12
	card.open_employee(employee["id"])
	await get_tree().process_frame
	var text: String = card.get_text()
	_expect(text.contains("Ascenso a Junior: contratos trabajados 1/3 · días en la empresa 12/30"), "progreso en la ficha: %s" % text)
	_expect(not card.is_promote_visible(), "sin cumplir no hay fila Ascender")
	# Cumple: aparece la fila con el sueldo de Junior sugerido.
	employee["projects_worked"] = 3
	employee["hired_day"] = GameClock.get_day_count() - 30
	card.refresh()
	await get_tree().process_frame
	var junior: int = StaffCatalog.get_salary("programmer", "junior")
	text = card.get_text()
	_expect(card.is_promote_visible(), "cumple: se ve la fila Ascender")
	_expect(text.contains("Puede ascender a Junior"), "lo dice: %s" % text)
	_expect(card.get_promote_salary() == junior, "sugiere el sueldo de Junior: %d" % card.get_promote_salary())
	var step: int = int(StaffCatalog.get_hiring("salary_step"))
	await _click(card.get_promote_plus_button())
	_expect(card.get_promote_salary() == junior + step, "+ suma %d" % step)
	await _click(card.get_promote_minus_button())
	_expect(card.get_promote_salary() == junior, "− resta")
	# No baja hasta el sueldo actual.
	var salary: int = employee["salary"]
	for i: int in range(50):
		card._change_promote_salary(-1)
	_expect(card.get_promote_salary() == salary + step, "el mínimo es el sueldo actual + %d: %d" % [step, card.get_promote_salary()])
	await get_tree().process_frame
	_expect(card.get_promote_minus_button().disabled, "− deshabilitado en el mínimo")
	await _click(card.get_promote_plus_button())
	await _click(card.get_promote_button())
	_expect(employee["level"] == "junior" and int(employee["salary"]) == salary + 2 * step, "Ascender desde la ficha: %s %d" % [employee["level"], employee["salary"]])
	await get_tree().process_frame
	_expect(not card.is_promote_visible(), "ya no se ve la fila")
	_expect(card.get_text().contains("Ascenso a SemiSenior: contratos trabajados 3/8"), "progreso al siguiente: %s" % card.get_text())
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
