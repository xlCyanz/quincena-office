# Cómo se ve una entrevista: el candidato se sienta en la silla de visita de quien entrevista
# (CEO o ejecutivo de Administración) y se va al terminar; la ficha dice a quién entrevista.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=interview_view
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_packed.call_deferred(GAME_SCENE)
		return
	SaveManager.save_dir = "user://test_saves"
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


func _candidate() -> Dictionary:
	var vacancy: Dictionary = Staff.open_vacancy("qa", "junior", 1200, true)
	GameClock.fast_forward_hours(1)  # A las 9:00 llegan los candidatos.
	var candidates: Array[Dictionary] = Staff.get_vacancy(int(vacancy["id"]))["candidates"]
	return {} if candidates.is_empty() else candidates[0]


# Sentado en la silla de visita de la oficina de quien entrevista.
func _check_spot(game: Node, by: String, label: String) -> void:
	var visitor: Visitor = game.interviewee
	_expect(visitor != null and visitor.person_key == "candidate_%d" % int(Staff.get_interviewed_now()["id"]),
		"%s: el candidato aparece" % label)
	if visitor == null:
		return
	var chair: Vector2i = OfficeState.find_furniture_assigned_to(by)["cell"]
	var spot: Vector2i = visitor.get_seat_cell()
	var room: Dictionary = Staff.get_workplace_room(by)
	var finder: OfficePathfinder = game.get("pathfinder")
	_expect(not room.is_empty() and Array(room["cells"]).has(spot), "%s: espera en la habitación de quien entrevista" % label)
	var guest: Dictionary = Staff.get_guest_chair(by)
	_expect(not guest.is_empty() and spot == guest["cell"] and spot != chair and finder != null,
		"%s: en la silla de visita: %s / %s" % [label, spot, chair])
	_expect(visitor.activity == OfficeCharacter.Activity.WALKING_TO_DESK and not visitor.standing and visitor.visible,
		"%s: camina hasta ahí y se sienta" % label)


func _check_ceo() -> void:
	var game: Node = await _start_game()
	var candidate: Dictionary = _candidate()
	_expect(not candidate.is_empty(), "hay candidato")
	_expect(game.interviewee == null, "sin entrevista no hay candidato en la oficina")
	_expect(Staff.start_interview(int(candidate["id"]))["ok"], "el CEO entrevista")
	_check_spot(game, "ceo", "CEO")
	var visitor: Visitor = game.interviewee
	GameClock.advance(30 * GameConstants.SECONDS_PER_GAME_HOUR / 60.0 / GameClock.get_time_scale())
	Staff.check_interview()
	_expect(Staff.interview.is_empty() and game.interviewee == null, "al terminar ya no hay entrevista")
	_expect(visitor != null and visitor.activity == OfficeCharacter.Activity.WALKING_OUT, "el candidato se va")
	# Cortarla (el CEO se va a casa) también lo saca.
	var other: Dictionary = _candidate()
	if not other.is_empty() and Staff.start_interview(int(other["id"]))["ok"]:
		var second: Visitor = game.interviewee
		Staff.set_ceo_at_work(false)
		_expect(game.interviewee == null and second.activity == OfficeCharacter.Activity.WALKING_OUT,
			"si el CEO se va, el candidato también")
	game.queue_free()
	await get_tree().process_frame


func _check_executive() -> void:
	var game: Node = await _start_game()
	var executive: Dictionary = {}
	for employee: Dictionary in Staff.employees:
		if employee["role"] == "executive":
			executive = employee
	_expect(not executive.is_empty(), "la empresa de prueba tiene ejecutivos")
	Staff.set_executive_department(int(executive["id"]), "administration")
	var candidate: Dictionary = _candidate()
	var key: String = Staff.employee_key(int(executive["id"]))
	_expect(Staff.start_interview(int(candidate["id"]), true)["ok"], "el ejecutivo entrevista: %s" % Staff.interview_problem(int(candidate["id"]), true))
	_check_spot(game, key, "ejecutivo")
	var character: Employee = game.employees[int(executive["id"])]
	character.call("_set_activity", OfficeCharacter.Activity.SEATED)
	var text: String = game.describe_employee_activity(int(executive["id"]))
	_expect(text == "entrevistando a %s" % candidate["name"], "la ficha del ejecutivo lo dice: %s" % text)
	game.queue_free()
	await get_tree().process_frame
