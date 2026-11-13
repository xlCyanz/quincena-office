# Prueba de las llegadas escalonadas (pedido después del hito 69): al empezar la jornada
# cada empleado entra entre 30 minutos antes y 10 después de la hora en punto, fijo por
# persona y día; los impuntuales llegan tarde más seguido y nunca muy temprano. Quien llega
# antes espera de pie en la Sala de descanso y a la hora va a su puesto. Con la oficina
# vacía el reloj salta hasta el primero que entra.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=arrivals
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
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	_check_offsets()
	await _check_in_game()
	SaveManager.start_with_demo = demo_before
	SaveManager.new_game()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _is_unpunctual(employee: Dictionary) -> bool:
	return Array(employee.get("traits", [])).has("unpunctual")


func _check_offsets() -> void:
	var earliest: int = int(StaffCatalog.get_arrivals("earliest"))
	var latest: int = int(StaffCatalog.get_arrivals("latest"))
	_expect(earliest == -30 and latest == 10, "entre 30 minutos antes y 10 después")
	var counts: Dictionary[String, int] = {"normal": 0, "normal_late": 0, "unpunctual": 0, "unpunctual_late": 0}
	var in_range: bool = true
	var unpunctual_range: bool = true
	var fixed: bool = true
	var spread: Dictionary[int, bool] = {}
	var someone: Dictionary = Staff.employees[0].duplicate(true)
	someone["traits"] = []
	var unpunctual: Dictionary = someone.duplicate(true)
	unpunctual["traits"] = ["unpunctual"]
	for at: int in range(2000):
		for employee: Dictionary in [someone, unpunctual]:
			var offset: int = Staff.get_arrival_offset(employee, at)
			fixed = fixed and offset == Staff.get_arrival_offset(employee, at)
			in_range = in_range and offset >= earliest and offset <= latest
			var group: String = "unpunctual" if employee == unpunctual else "normal"
			counts[group] += 1
			if offset > 0:
				counts[group + "_late"] += 1
			if group == "unpunctual":
				unpunctual_range = unpunctual_range and offset >= int(StaffCatalog.get_arrivals("unpunctual_earliest"))
			else:
				spread[offset] = true
	_expect(_is_unpunctual(unpunctual) and not _is_unpunctual(someone), "uno impuntual y otro no")
	_expect(fixed, "fijo por persona y hora")
	_expect(in_range, "siempre entre −30 y +10")
	_expect(unpunctual_range, "el impuntual no llega más de 10 minutos antes")
	var normal_late: float = float(counts["normal_late"]) / counts["normal"]
	var unpunctual_late: float = float(counts["unpunctual_late"]) / counts["unpunctual"]
	_expect(absf(normal_late - 0.1) < 0.03, "10 %% llega después de la hora: %.2f" % normal_late)
	_expect(absf(unpunctual_late - 0.5) < 0.05, "el impuntual, la mitad: %.2f" % unpunctual_late)
	_expect(spread.has(-30) and spread.has(0) and spread.has(10) and spread.size() == 41, "se reparten en todo el rango")
	Staff.arrival_spread_enabled = false
	_expect(Staff.get_arrival_offset(someone, 5) == 0, "sin la regla, a la hora en punto")
	Staff.arrival_spread_enabled = true


func _check_in_game() -> void:
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	# Del lunes 8:00 al martes 7:00.
	GameClock.fast_forward_hours(23)
	_expect(GameClock.get_weekday() == 1 and GameClock.get_hour() == 7, "martes 7:00")
	# El salto no mueve a los personajes: los que salían el lunes quedan ya fuera.
	_send_all_home(game)
	game.call("_update_routines")
	var day_shift: Array[Employee] = []
	for employee: Dictionary in Staff.employees:
		var schedule: WorkSchedule = Staff.get_schedule(employee)
		if schedule.start_hour == 8 and schedule.days.has(1):
			day_shift.append(game.employees[int(employee["id"])])
	_expect(day_shift.size() >= 10, "hay al menos 10 que entran a las 8: %d" % day_shift.size())
	var pending: Dictionary[String, int] = game.get_pending_arrivals()
	var hour_start: int = Staff.get_absolute_hour() * 60
	var early_count: int = 0
	var early_ok: bool = true
	for character: Employee in day_shift:
		var minutes: int = Staff.get_early_minutes(character.person_key)
		if minutes > 0:
			early_count += 1
			early_ok = early_ok and pending.get(character.person_key, -1) == hour_start + 60 - minutes
		early_ok = early_ok and character.activity == OfficeCharacter.Activity.AWAY
	_expect(early_count >= day_shift.size() / 2, "la mayoría llega antes de las 8: %d de %d" % [early_count, day_shift.size()])
	_expect(early_ok, "a las 7:00 nadie entró y cada uno tiene su minuto")
	for key: String in pending:
		_expect(pending[key] >= hour_start + 30 and pending[key] < hour_start + 60, "%s entra entre 7:30 y 7:59" % key)

	# Minuto a minuto: cada uno entra en su minuto y espera de pie en la Sala de descanso.
	# Sin Sala de descanso que funcione dan vueltas por la oficina.
	var break_room: Dictionary = OfficeState.get_working_room(OfficeState.BREAK_ROOM)
	var waiting_cells: Array = break_room["cells"] if not break_room.is_empty() \
		else (game.get("pathfinder") as OfficePathfinder).get_reachable(OfficeState.entrance).keys()
	var wander_seats: Dictionary[String, Dictionary] = {}
	var entered: Dictionary[String, int] = {}
	var waiting_ok: bool = true
	for minute: int in range(1, 60):
		_advance_minute(game)
		for character: Employee in day_shift:
			var key: String = character.person_key
			if character.activity != OfficeCharacter.Activity.AWAY and not entered.has(key):
				entered[key] = game.get_arrival_minute()
				waiting_ok = waiting_ok and game.is_waiting_shift(key) and character.standing \
					and waiting_cells.has(character.get_seat_cell())
			if game.is_waiting_shift(key):
				if not wander_seats.has(key):
					wander_seats[key] = {}
				wander_seats[key][character.get_seat_cell()] = true
	var on_time: bool = true
	for key: String in pending:
		on_time = on_time and entered.get(key, -1) == pending[key]
	_expect(entered.size() == pending.size() and on_time, "cada uno entra en su minuto: %d de %d" % [entered.size(), pending.size()])
	_expect(waiting_ok, "los que llegan antes esperan de pie (Sala de descanso o dando vueltas)")
	if break_room.is_empty():
		var moved: int = 0
		for key: String in wander_seats:
			if wander_seats[key].size() > 1:
				moved += 1
		_expect(moved > 0, "sin Sala de descanso dan vueltas: %d cambiaron de lugar" % moved)
	var describe: String = game.describe_employee_activity(int(Staff.get_employee_by_key(pending.keys()[0])["id"]))
	_expect(describe == "llegó temprano y espera su hora", "la ficha lo dice: %s" % describe)

	# A las 8: van a su puesto; los que llegan después entran hasta las 8:10.
	_advance_minute(game)
	_expect(GameClock.get_hour() == 8, "las 8:00")
	var to_desk: bool = true
	for key: String in pending:
		var character: Employee = game.employees[int(Staff.get_employee_by_key(key)["id"])]
		to_desk = to_desk and not game.is_waiting_shift(key) and not character.standing \
			and character.get_seat_cell() == game.call("_home_spot", key)
	_expect(to_desk, "a las 8 los que esperaban van a su puesto")
	var late: Dictionary[String, int] = game.get_pending_arrivals()
	var late_ok: bool = true
	for key: String in late:
		if not day_shift.any(func(character: Employee) -> bool: return character.person_key == key):
			continue  # Otro turno (el de las 9) que llega antes.
		late_ok = late_ok and late[key] > Staff.get_absolute_hour() * 60 and late[key] <= Staff.get_absolute_hour() * 60 + 10
	_expect(late_ok, "los que llegan tarde, hasta las 8:10: %s" % [late.values()])
	for minute: int in range(10):
		_advance_minute(game)
	var all_in: bool = true
	for character: Employee in day_shift:
		if Staff.is_expected_now(character.person_key):
			all_in = all_in and character.activity != OfficeCharacter.Activity.AWAY
	_expect(all_in, "a las 8:10 llegaron todos los que tenían que estar")

	# Oficina vacía: el reloj salta a la hora anterior y hasta el primero que entra.
	# Una hora en que nadie trabaja y la próxima llegada es en más de una hora.
	Staff.set_ceo_at_work(false)
	for hour: int in range(7 * 24):
		GameClock.fast_forward_hours(1)
		Staff.set_ceo_at_work(false)
		if Staff.hours_until_anyone_expected() > 2 and not Staff.employees.any(
				func(employee: Dictionary) -> bool: return Staff.is_expected_now(Staff.employee_key(employee["id"]))):
			break
	var expected_in: int = Staff.hours_until_anyone_expected()
	var arrival_hour: int = Staff.get_absolute_hour() + expected_in
	_send_all_home(game)
	game.call("_on_character_left_office")
	var arrivals: Dictionary[String, int] = game.get_pending_arrivals()
	_expect(Staff.get_absolute_hour() == arrival_hour - 1, "salta hasta la hora anterior a la llegada")
	_expect(not arrivals.is_empty(), "salta hasta una hora con llegadas antes de la hora en punto")
	if not arrivals.is_empty():
		_expect(game.get_arrival_minute() == arrivals.values().min(),
			"y hasta el minuto del primero: %d:%02d" % [GameClock.get_hour(), GameClock.get_minute()])
	game.queue_free()
	await get_tree().process_frame


# Un minuto de juego: el reloj y la revisión de llegadas de la escena.
func _advance_minute(game: Node) -> void:
	GameClock.advance(GameConstants.SECONDS_PER_GAME_HOUR / 60.0 / GameClock.get_time_scale())
	game._process(0.0)


func _send_all_home(game: Node) -> void:
	for character: OfficeCharacter in game.get_characters():
		character.call("_release_cells")
		character.call("_set_activity", OfficeCharacter.Activity.AWAY)
		character.get_path_cells()
		character.set("_path", [] as Array[Vector2i])
		character.visible = false
