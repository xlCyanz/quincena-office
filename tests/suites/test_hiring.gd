# Prueba del hito 11: contratación.
# Criterio: sin puesto de trabajo libre no se puede contratar; con puesto, el empleado
# queda asignado a él y ningún puesto queda con dos empleados.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=hiring
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261111

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_workstations()
	_check_no_station()
	_check_offers()
	_check_second_hire()
	_check_protected_furniture()
	_check_interview()
	_check_save()
	await _check_panel()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Economy.earn(10000, "Prueba")


# Avanza el reloj hasta la próxima hora de llegada de candidatos.
func _to_next_arrival() -> void:
	var arrival: int = int(StaffCatalog.get_hiring("arrival_hour"))
	var hours: int = posmod(arrival - GameClock.get_hour(), GameConstants.HOURS_PER_DAY)
	GameClock.fast_forward_hours(hours if hours > 0 else GameConstants.HOURS_PER_DAY)


# Publica una vacante con publicidad y espera hasta que haya al menos count candidatos.
func _vacancy_with_candidates(count: int) -> Dictionary:
	var vacancy_id: int = Staff.open_vacancy("programmer", "junior", 1200, true)["id"]
	for day: int in range(10):
		if Staff.get_vacancy(vacancy_id)["candidates"].size() >= count:
			break
		_to_next_arrival()
	var vacancy: Dictionary = Staff.get_vacancy(vacancy_id)
	_expect(vacancy["candidates"].size() >= count, "llegan %d candidatos" % count)
	return vacancy


# Área de trabajo de 3×3 al este de la Oficina Ejecutiva (x 3–5, y 0–2) con una puerta
# al sur. Las paredes del oeste son las de la Oficina Ejecutiva.
func _build_work_area(builder: Builder) -> void:
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(builder.apply(walls)["ok"], "construir las paredes del área de trabajo")
	_expect(builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")


# Escritorio con computadora mirando al sur y silla delante.
func _build_station(builder: Builder, desk: Vector2i) -> void:
	_expect(builder.place("simple_desk", desk, 2)["ok"], "poner el escritorio en %s" % desk)
	_expect(builder.place("basic_chair", desk + Vector2i(0, 1), 0)["ok"], "poner la silla en %s" % (desk + Vector2i(0, 1)))
	_expect(builder.install_computer("basic_computer", desk)["ok"], "instalar la computadora en %s" % desk)


func _assigned_chairs() -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {}
	for item: Dictionary in OfficeState.furniture:
		var who: String = item["assigned_to"]
		if not who.is_empty():
			counts[who] = counts.get(who, 0) + 1
	return counts


func _check_workstations() -> void:
	_new_game()
	_expect(Workstations.find_all(OfficeState.furniture, OfficeState.rooms).is_empty(),
		"la oficina inicial no tiene puestos (el del CEO no cuenta)")
	var builder := Builder.new()
	_build_work_area(builder)
	_expect(builder.place("simple_desk", Vector2i(4, 0), 2)["ok"], "poner el escritorio")
	_expect(builder.place("basic_chair", Vector2i(4, 1), 0)["ok"], "poner la silla")
	_expect(Staff.get_free_workstations().is_empty(), "sin computadora no hay puesto")
	_expect(builder.install_computer("basic_computer", Vector2i(4, 0))["ok"], "instalar la computadora")
	var free: Array[Dictionary] = Staff.get_free_workstations()
	_expect(free.size() == 1 and free[0]["cell"] == Vector2i(4, 1), "un puesto libre en la silla: %s" % [free])
	# Una silla que no está delante del escritorio no hace puesto.
	_expect(builder.place("basic_chair", Vector2i(5, 0), 0)["ok"], "poner una silla al lado")
	_expect(Staff.get_free_workstations().size() == 1, "la silla de al lado no es un puesto")
	# Sin el área de trabajo no hay puesto.
	_expect(builder.unmark_room(Vector2i(4, 1))["ok"], "quitar el área de trabajo")
	_expect(Staff.get_free_workstations().is_empty(), "fuera de un área de trabajo no hay puesto")


func _check_no_station() -> void:
	_new_game()
	var vacancy: Dictionary = _vacancy_with_candidates(1)
	var candidate: Dictionary = vacancy["candidates"][0]
	var result: Dictionary = Staff.make_offer(candidate["id"], candidate["asked_salary"] * 2)
	_expect(not result["ok"] and result["message"].contains("puesto de trabajo libre"),
		"sin puesto no se contrata: %s" % result["message"])
	_expect(Staff.employees.is_empty() and not Staff.get_candidate(candidate["id"]).is_empty(),
		"el candidato sigue esperando")


func _check_offers() -> void:
	_new_game()
	var builder := Builder.new()
	_build_work_area(builder)
	_build_station(builder, Vector2i(4, 0))
	var vacancy: Dictionary = _vacancy_with_candidates(2)
	var vacancy_id: int = vacancy["id"]
	var low: Dictionary = vacancy["candidates"][0]
	var fair: Dictionary = vacancy["candidates"][1]
	var ratio: float = float(StaffCatalog.get_hiring("counter_offer_ratio"))

	# Muy por debajo: rechaza y se va.
	var low_offer: int = floori(low["asked_salary"] * ratio) - 1
	var result: Dictionary = Staff.make_offer(low["id"], low_offer)
	_expect(result["ok"] and result["result"] == "rejected", "una oferta baja se rechaza: %s" % [result])
	_expect(Staff.get_candidate(low["id"]).is_empty(), "el que rechaza se va")
	_expect(Staff.employees.is_empty(), "nadie contratado tras el rechazo")

	# Un poco por debajo: contraoferta con lo que pide.
	var asked: int = fair["asked_salary"]
	var near_offer: int = ceili(asked * ratio)
	result = Staff.make_offer(fair["id"], near_offer)
	_expect(result["result"] == "counter" and fair["counter_offer"] == asked,
		"una oferta cercana trae contraoferta: %s" % [result])
	_expect(not Staff.get_candidate(fair["id"]).is_empty() and Staff.employees.is_empty(), "la contraoferta no contrata")

	result = Staff.accept_counter_offer(fair["id"])
	_expect(result["ok"] and result["result"] == "hired", "aceptar la contraoferta contrata: %s" % [result])
	_expect(Staff.employees.size() == 1 and Staff.employees[0]["salary"] == asked, "contratado por lo que pidió")
	var key: String = Staff.employee_key(fair["id"])
	var seat: Dictionary = OfficeState.find_furniture_assigned_to(key)
	_expect(not seat.is_empty() and seat["cell"] == Vector2i(4, 1), "el empleado queda en la silla del puesto")
	_expect(Staff.has_working_station(Staff.employees[0]), "su puesto funciona")
	_expect(Staff.get_vacancy(vacancy_id).is_empty(), "la vacante se cierra al contratar")
	_expect(Staff.get_free_workstations().is_empty(), "ya no quedan puestos libres")
	_expect(not Staff.employees[0].has("arrived_day") and not Staff.employees[0].has("counter_offer"),
		"el empleado no guarda datos de candidato")


func _check_second_hire() -> void:
	# Sigue con la partida de _check_offers: un empleado y ningún puesto libre.
	var builder := Builder.new()
	var vacancy: Dictionary = _vacancy_with_candidates(1)
	var candidate: Dictionary = vacancy["candidates"][0]
	var result: Dictionary = Staff.make_offer(candidate["id"], candidate["asked_salary"] + 500)
	_expect(not result["ok"] and Staff.employees.size() == 1, "con el único puesto ocupado no se contrata")
	_build_station(builder, Vector2i(3, 0))
	result = Staff.make_offer(candidate["id"], candidate["asked_salary"])
	_expect(result["ok"] and result["result"] == "hired", "con un puesto nuevo se contrata: %s" % [result])
	_expect(Staff.employees.size() == 2 and Staff.employees[1]["salary"] == candidate["asked_salary"],
		"pagar lo que pide basta")
	var seat: Dictionary = OfficeState.find_furniture_assigned_to(Staff.employee_key(candidate["id"]))
	_expect(not seat.is_empty() and seat["cell"] == Vector2i(3, 1), "el segundo queda en el otro puesto")
	var counts: Dictionary[String, int] = _assigned_chairs()
	_expect(counts.size() == 3, "CEO y dos empleados con silla: %s" % [counts])
	for who: String in counts:
		_expect(counts[who] == 1, "%s tiene una sola silla" % who)
	var stations: Array[Dictionary] = Workstations.find_all(OfficeState.furniture, OfficeState.rooms)
	var chairs: Dictionary[int, bool] = {}
	var desks: Dictionary[int, bool] = {}
	for station: Dictionary in stations:
		chairs[station["chair"]] = true
		desks[station["desk"]] = true
	_expect(stations.size() == 2 and chairs.size() == 2 and desks.size() == 2, "dos puestos, cada uno con su silla y escritorio")


func _check_protected_furniture() -> void:
	# Sigue con la partida anterior: los dos puestos están ocupados.
	var builder := Builder.new()
	var balance: int = Economy.balance
	var count: int = OfficeState.furniture.size()
	var result: Dictionary = builder.sell_furniture_at(Vector2i(4, 1))
	_expect(not result["ok"] and result["message"].contains("puesto de"), "la silla de un empleado no se vende: %s" % result["message"])
	_expect(not builder.sell_furniture_at(Vector2i(4, 0))["ok"], "ni su computadora ni su escritorio")
	_expect(not builder.rotate(Vector2i(4, 0))["ok"], "ni se gira su escritorio")
	_expect(not builder.rotate(Vector2i(4, 1))["ok"], "ni se gira su silla")
	_expect(not builder.sell_furniture_at(Vector2i(1, 1))["ok"], "la silla del CEO sigue sin venderse")
	_expect(Economy.balance == balance and OfficeState.furniture.size() == count, "nada cambió")
	# Lo que no es de un puesto se sigue vendiendo.
	_expect(builder.place("small_plant", Vector2i(5, 0), 0)["ok"] and builder.sell_furniture_at(Vector2i(5, 0))["ok"],
		"una planta se compra y se vende")


func _check_interview() -> void:
	_new_game()
	var vacancy: Dictionary = _vacancy_with_candidates(2)
	_expect(GameClock.get_hour() == 9 and GameClock.get_weekday() < 5, "es un día hábil a las 9:00")
	var first: Dictionary = vacancy["candidates"][0]
	var second: Dictionary = vacancy["candidates"][1]
	_expect(Staff.describe_skills(first).contains("–"), "antes de la entrevista se ven rangos")
	var result: Dictionary = Staff.start_interview(first["id"])
	_expect(result["ok"] and Staff.get_interviewed_now() == first, "empieza la entrevista: %s" % result["message"])
	_expect(not Staff.interview_problem(second["id"]).is_empty(), "una entrevista a la vez")
	_expect(int(StaffCatalog.get_hiring("interview_minutes")) == 30 and String(result["message"]).ends_with("hasta las 09:30."),
		"dura media hora desde que empieza: %s" % result["message"])
	_expect(is_equal_approx(Staff.get_ceo_interview_factor(Staff.get_absolute_hour()), 0.5), "el CEO rinde media hora")
	_advance_minutes(29)
	_expect(not first["interviewed"], "a los 29 minutos todavía no termina")
	_advance_minutes(1)
	_expect(first["interviewed"] and Staff.interview.is_empty() and GameClock.get_minute() == 30, "termina a las 9:30")
	_expect(is_equal_approx(Staff.get_ceo_interview_factor(Staff.get_absolute_hour()), 0.5)
		and Staff.get_ceo_interview_factor(Staff.get_absolute_hour() + 1) == 1.0, "esa hora el CEO rinde la mitad, la siguiente entera")
	_expect(first["known_traits"].size() == 1 and first["traits"].has(first["known_traits"][0]),
		"revela un rasgo: %s" % [first["known_traits"]])
	var skills: String = Staff.describe_skills(first)
	_expect(not skills.contains("–") and skills.contains(str(first["skills"]["programming"])),
		"revela los valores reales: %s" % skills)
	_expect(not Staff.interview_problem(first["id"]).is_empty(), "no se entrevista dos veces")

	# La entrevista no cruza el almuerzo: a las 11:45 terminaría a las 12:15.
	GameClock.fast_forward_hours(2)
	_expect(GameClock.get_hour() == 11, "son las 11: %d" % GameClock.get_hour())
	_expect(Staff.interview_problem(second["id"]).is_empty(), "a las 11:00 sí cabe antes del almuerzo")
	_advance_minutes(45)
	_expect(Staff.interview_problem(second["id"]).contains("almuerzo"), "11:45 cruza el almuerzo: %s" % Staff.interview_problem(second["id"]))
	GameClock.fast_forward_hours(2)
	_expect(Staff.start_interview(second["id"])["ok"], "a las 13:00 sí")
	# Si el CEO se va a casa, la entrevista se corta y no puede empezar otra.
	Staff.set_ceo_at_work(false)
	_expect(Staff.interview.is_empty() and not second["interviewed"], "mandar al CEO a casa corta la entrevista")
	_expect(not Staff.interview_problem(second["id"]).is_empty(), "sin el CEO no se entrevista")
	Staff.set_ceo_at_work(true)
	_expect(Staff.start_interview(second["id"])["ok"], "con el CEO de vuelta sí")
	Staff.discard_candidate(second["id"])
	_expect(Staff.interview.is_empty(), "descartar al entrevistado termina la entrevista")


# Adelanta el reloj unos minutos de juego y revisa si terminó la entrevista.
func _advance_minutes(minutes: int) -> void:
	GameClock.set_paused(false)
	GameClock.advance(minutes * GameConstants.SECONDS_PER_GAME_HOUR / 60.0 / GameClock.get_time_scale())
	Staff.check_interview()


func _check_save() -> void:
	_new_game()
	var builder := Builder.new()
	_build_work_area(builder)
	_build_station(builder, Vector2i(4, 0))
	var vacancy: Dictionary = _vacancy_with_candidates(2)
	var hired: Dictionary = vacancy["candidates"][0]
	var other: Dictionary = vacancy["candidates"][1]
	_expect(Staff.start_interview(hired["id"])["ok"], "entrevistar antes de contratar")
	GameClock.fast_forward_hours(1)  # Dura media hora.
	_expect(Staff.make_offer(hired["id"], hired["asked_salary"])["result"] == "hired", "contratar al entrevistado")
	_expect(Staff.employees[0]["interviewed"] and Staff.employees[0]["known_traits"].size() == 1,
		"el empleado conserva lo que reveló la entrevista")
	var vacancy2: Dictionary = _vacancy_with_candidates(1)
	var waiting: Dictionary = vacancy2["candidates"][0]
	Staff.make_offer(waiting["id"], 50)
	if GameClock.get_weekday() < 5:
		Staff.start_interview(waiting["id"])
	var before: Dictionary = Staff.export_state()
	_expect(SaveManager.save_game("slot_1"), "guardar la partida")
	_new_game()
	_expect(Staff.employees.is_empty(), "la partida nueva no tiene empleados")
	_expect(SaveManager.load_game("slot_1"), "cargar la partida")
	_expect(JSON.stringify(Staff.export_state()) == JSON.stringify(before), "el personal vuelve igual")
	_expect(OfficeState.find_furniture_assigned_to(Staff.employee_key(hired["id"]))["cell"] == Vector2i(4, 1),
		"la silla sigue asignada")
	_expect(Staff.has_working_station(Staff.employees[0]), "su puesto sigue funcionando")
	_expect(other.is_empty() or Staff.get_candidate(other["id"]).is_empty(), "los demás candidatos se fueron al contratar")
	# Una partida del hito 10 no tiene empleados ni entrevista.
	Staff.import_state({"vacancies": [], "next_id": 5})
	_expect(Staff.employees.is_empty() and Staff.interview.is_empty(), "partida vieja sin empleados")


func _check_panel() -> void:
	_new_game()
	var builder := Builder.new()
	_build_work_area(builder)
	_build_station(builder, Vector2i(4, 0))
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameClock.stop()
	var panel: StaffPanel = game.get_node("StaffPanel")
	await _click(panel.get_open_button())
	_expect(panel.get_list_text().contains("Empleados (0) · puestos libres: 1"), "cabecera de empleados: %s" % panel.get_list_text())
	var vacancy: Dictionary = _vacancy_with_candidates(1)
	await get_tree().process_frame
	var candidate: Dictionary = vacancy["candidates"][0]
	var candidate_id: int = candidate["id"]
	_expect(panel.get_offer(candidate_id) == 1200, "la oferta arranca en el sueldo de la vacante: %d" % panel.get_offer(candidate_id))

	await _click(panel.get_interview_button(candidate_id))
	_expect(not Staff.get_appointment(candidate_id).is_empty(), "entrevistar desde el panel la cita")
	await get_tree().process_frame
	_expect(panel.get_list_text().contains("Entrevista citada ") and panel.get_list_text().contains("con el CEO"),
		"se ve la cita: %s" % panel.get_list_text())
	_expect(panel.get_interview_button(candidate_id).disabled, "no se cita otra vez")
	var hours: int = 0
	while not bool(candidate["interviewed"]) and hours < 80:
		GameClock.fast_forward_hours(1)
		hours += 1
	await get_tree().process_frame
	_expect(panel.get_list_text().contains("Rasgos: "), "se ve el rasgo revelado: %s" % panel.get_list_text())

	# Subir la oferta hasta lo que pide.
	while panel.get_offer(candidate_id) < candidate["asked_salary"]:
		await _click(panel.get_offer_step_buttons(candidate_id)[1])
	while panel.get_offer(candidate_id) > candidate["asked_salary"]:
		await _click(panel.get_offer_step_buttons(candidate_id)[0])
	_expect(panel.get_offer(candidate_id) == candidate["asked_salary"], "botones −/+ de la oferta")
	await _click(panel.get_offer_button(candidate_id))
	_expect(Staff.employees.size() == 1, "contratar desde el panel")
	_expect(panel.get_status_text().contains("aceptó"), "aviso: %s" % panel.get_status_text())
	await get_tree().process_frame
	_expect(panel.get_list_text().contains("Empleados (1) · puestos libres: 0") and panel.get_list_text().contains(candidate["name"]),
		"el empleado en la lista: %s" % panel.get_list_text())

	# Sin puesto libre, ofrecer avisa por qué.
	var vacancy2: Dictionary = _vacancy_with_candidates(1)
	await get_tree().process_frame
	var other_id: int = vacancy2["candidates"][0]["id"]
	await _click(panel.get_offer_button(other_id))
	_expect(panel.get_status_text().contains("puesto de trabajo libre") and Staff.employees.size() == 1,
		"aviso sin puesto: %s" % panel.get_status_text())
	panel.set_open(false)
	game.queue_free()
	await get_tree().process_frame


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
