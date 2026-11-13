# Prueba de las entrevistas citadas (pedido después del hito 69): «Entrevistar» cita al
# candidato para el próximo día de quien entrevista a su hora de entrada (las siguientes,
# cada media hora); el candidato llega antes, espera de pie y a la hora camina a la silla
# de visita y empieza la entrevista. Si quien entrevista no está, la cita se cancela con
# aviso. Un candidato citado no se va. Las citas se guardan en la partida.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=appointments
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MINUTES_PER_DAY: int = 24 * 60

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_packed.call_deferred(GAME_SCENE)
		return
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	var demo_before: bool = SaveManager.start_with_demo
	SaveManager.start_with_demo = false
	SaveManager.new_game()
	await _check_ceo()
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	await _check_executive()
	SaveManager.start_with_demo = demo_before
	SaveManager.new_game()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _start_game() -> Node:
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	GameClock.set_paused(false)
	return game


func _candidates(count: int) -> Array[Dictionary]:
	var vacancy: Dictionary = Staff.open_vacancy("qa", "junior", 1200, true)
	GameClock.fast_forward_hours(1)  # A las 9:00 llegan los candidatos.
	var hours: int = 0
	while (Staff.get_vacancy(int(vacancy["id"]))["candidates"] as Array).size() < count and hours < 24 * 6:
		GameClock.fast_forward_hours(1)
		hours += 1
	var found: Array[Dictionary] = Staff.get_vacancy(int(vacancy["id"]))["candidates"]
	return found


# Adelanta el reloj hasta ese minuto absoluto: de a horas mientras se pueda y después de a
# minutos, dejando correr cuadros para que la escena dibuje a los candidatos.
func _advance_to(minute: int) -> void:
	while Staff.get_absolute_minute() < minute:
		if minute - Staff.get_absolute_minute() > 60 and GameClock.get_minute() == 0:
			GameClock.fast_forward_hours(1)
		else:
			GameClock.advance(GameConstants.SECONDS_PER_GAME_HOUR / 60.0 / GameClock.get_time_scale())
			await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _check_ceo() -> void:
	var game: Node = await _start_game()
	var found: Array[Dictionary] = _candidates(3)
	_expect(found.size() >= 3, "llegan 3 candidatos: %d" % found.size())
	if found.size() < 3:
		game.queue_free()
		return
	var first: Dictionary = found[0]
	var second: Dictionary = found[1]
	var third: Dictionary = found[2]
	var now: int = Staff.get_absolute_minute()
	var result: Dictionary = Staff.schedule_interview(int(first["id"]))
	_expect(result["ok"] and String(result["message"]).contains("a las 08:00"), "cita al primero: %s" % result["message"])
	var appointment: Dictionary = Staff.get_appointment(int(first["id"]))
	var at: int = int(appointment.get("at", -1))
	@warning_ignore("integer_division")
	var day_gap: int = at / MINUTES_PER_DAY - now / MINUTES_PER_DAY
	_expect(posmod(at, MINUTES_PER_DAY) == StaffCatalog.get_ceo_arrival_hour() * 60 and day_gap >= 1,
		"a la hora de llegada del CEO de otro día: %s" % Staff.format_clock_minute(at))
	_expect(Staff.interview.is_empty(), "citar no empieza la entrevista")
	_expect(Staff.appointment_problem(int(first["id"])) == "Ya tiene entrevista citada.", "no se cita dos veces")
	_expect(Staff.schedule_interview(int(second["id"]))["ok"], "cita al segundo")
	_expect(int(Staff.get_appointment(int(second["id"]))["at"]) == at + 30, "el segundo media hora después")

	# Guardar y cargar conserva las citas.
	var saved: Dictionary = Staff.export_state()
	Staff.import_state(JSON.parse_string(JSON.stringify(saved)))
	_expect(Staff.appointments.size() == 2 and int(Staff.get_appointment(int(first["id"]))["at"]) == at,
		"las citas se guardan: %s" % [Staff.appointments])

	# Un candidato citado no se va aunque se le acaben los días.
	first["arrived_day"] = GameClock.get_day_count() - 30
	Staff.call("_process_arrivals", GameClock.get_day_count())
	_expect(not Staff.get_candidate(int(first["id"])).is_empty(), "el citado espera su entrevista")
	first = Staff.get_candidate(int(first["id"]))
	second = Staff.get_candidate(int(second["id"]))
	var arrival: int = Staff.get_appointment_arrival(Staff.get_appointment(int(first["id"])))
	_expect(at - arrival >= 10 and at - arrival <= 25, "llega entre 10 y 25 minutos antes: %d" % (at - arrival))

	# Llega antes y espera de pie, no en la silla de visita.
	await _advance_to(arrival - 1)
	_expect(not game.appointment_visitors.has(int(first["id"])), "antes de su hora de llegada no está")
	await _advance_to(arrival)
	var waiting: Visitor = game.appointment_visitors.get(int(first["id"]))
	# Entra cuando la puerta está libre (la prueba no deja caminar al CEO): basta que exista.
	_expect(waiting != null and waiting.standing and waiting.activity == OfficeCharacter.Activity.WALKING_TO_DESK,
		"llega temprano y espera de pie")
	var guest: Vector2i = Staff.get_guest_chair("ceo").get("cell", Vector2i(-99, -99))
	_expect(waiting != null and waiting.get_seat_cell() != guest, "no espera en la silla de visita")
	_expect(Staff.interview.is_empty(), "todavía no empieza")

	# A la hora citada empieza: camina a la silla de visita y se sienta.
	await _advance_to(at)
	_expect(int(Staff.interview.get("candidate_id", -1)) == int(first["id"]) and int(Staff.interview["starts_at"]) == at,
		"a las 8 empieza la entrevista: %s" % [Staff.interview])
	_expect(game.interviewee != null and game.interviewee == waiting, "el que esperaba es el entrevistado")
	_expect(waiting != null and waiting.get_seat_cell() == guest and not waiting.standing, "va a la silla de visita")
	_expect(Staff.get_appointment(int(first["id"])).is_empty(), "la cita se cumple")

	# A la media hora termina y empieza la siguiente; el segundo ya esperaba su turno.
	await _advance_to(at + 29)
	_expect(game.appointment_visitors.has(int(second["id"])), "el segundo ya espera su turno")
	await _advance_to(at + 30)
	Staff.check_interview()
	Staff.call("_check_appointments")
	_expect(bool(first["interviewed"]), "el primero quedó entrevistado")
	_expect(int(Staff.interview.get("candidate_id", -1)) == int(second["id"]), "a las 8:30 el segundo")
	await _advance_to(at + 60)
	Staff.check_interview()

	# Si quien entrevista no está, la cita se cancela con aviso: el CEO se fue a casa.
	_expect(Staff.schedule_interview(int(third["id"]))["ok"], "cita al tercero")
	var soon: int = Staff.get_absolute_minute() + 10
	Staff.get_appointment(int(third["id"]))["at"] = soon
	Staff.set_ceo_at_work(false)
	_notices.clear()
	await _advance_to(soon + int(StaffCatalog.get_hiring("appointment_grace_minutes")))
	Staff.call("_check_appointments")
	_expect(Staff.get_appointment(int(third["id"])).is_empty() and not bool(third["interviewed"]),
		"sin el CEO la cita se cancela")
	_expect(_notices.any(func(text: String) -> bool: return text.contains("vuelve a citarlo")), "avisa: %s" % [_notices])
	await get_tree().process_frame
	_expect(not game.appointment_visitors.has(int(third["id"])), "el candidato se va")
	_expect(Staff.appointment_problem(int(third["id"])).is_empty(), "se lo puede volver a citar")
	game.queue_free()
	await get_tree().process_frame


func _check_executive() -> void:
	var game: Node = await _start_game()
	var executive: Dictionary = {}
	for employee: Dictionary in Staff.employees:
		if employee["role"] == "executive":
			executive = employee
	Staff.set_executive_department(int(executive["id"]), "administration")
	var found: Array[Dictionary] = _candidates(1)
	var candidate: Dictionary = found[0]
	var result: Dictionary = Staff.schedule_interview(int(candidate["id"]), true)
	_expect(result["ok"], "se delega con cita: %s" % result["message"])
	var appointment: Dictionary = Staff.get_appointment(int(candidate["id"]))
	var key: String = Staff.employee_key(int(executive["id"]))
	var start: int = Staff.get_schedule(executive).start_hour
	_expect(String(appointment.get("by", "")) == key and posmod(int(appointment["at"]), MINUTES_PER_DAY) == start * 60,
		"a la hora de entrada del ejecutivo: %s" % [appointment])
	await _advance_to(int(appointment["at"]))
	_expect(String(Staff.interview.get("by", "")) == key and int(Staff.interview.get("candidate_id", -1)) == int(candidate["id"]),
		"el ejecutivo entrevista a su hora: %s" % [Staff.interview])
	var visitor: Visitor = game.interviewee
	_expect(visitor != null and visitor.get_seat_cell() == Staff.get_guest_chair(key).get("cell", Vector2i(-99, -99)),
		"el candidato va a la silla de visita del ejecutivo")
	# Si el ejecutivo se va de la empresa, sus citas se borran.
	var other: Dictionary = _candidates(1)[0]
	Staff.check_interview()
	if Staff.interview.is_empty() and Staff.schedule_interview(int(other["id"]), true)["ok"]:
		Staff.call("_remove_employee", executive, "Liquidación")
		_expect(Staff.get_appointment(int(other["id"])).is_empty(), "sin el ejecutivo no quedan sus citas")
	game.queue_free()
	await get_tree().process_frame
