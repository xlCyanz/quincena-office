# Prueba sin ventana del hito 2: duración del día a cada velocidad, pausa, cambio de
# mes y de semana, señales en orden y guardado del estado del reloj.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_game_clock.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const FRAME_SECONDS: float = 1.0 / 60.0
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"

var _failures: int = 0
var _checks: int = 0
var _hours: Array[int] = []
var _days: Array[Vector2i] = []
var _elapsed: float = 0.0
var _hour_times: Array[float] = []
var _day_times: Array[float] = []


func _ready() -> void:
	# Con ventana (por ejemplo, Cmd+R en el editor) se abre el juego normal.
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE_PATH)
		return
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.day_changed.connect(_on_day_changed)

	# Todo lo que sigue corre en un solo fotograma, así el _process real del reloj
	# no se mezcla con los pasos simulados.
	_check_start()
	for index: int in range(GameConstants.CLOCK_SPEEDS.size()):
		_check_day_length(index)
	_check_pause()
	_check_big_step()
	_check_calendar()
	_check_state_round_trip()

	# Por último, que el reloj avance solo con los fotogramas reales.
	GameClock.new_game()
	GameClock.start()
	var before: float = float(GameClock.export_state()["seconds_into_hour"])
	for i: int in range(10):
		await get_tree().process_frame
	var after: float = float(GameClock.export_state()["seconds_into_hour"])
	_expect(after > before, "el reloj no avanza con los fotogramas reales")

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _on_hour_changed(hour: int) -> void:
	_hours.append(hour)
	_hour_times.append(_elapsed)


func _on_day_changed(day: int, month: int) -> void:
	_days.append(Vector2i(day, month))
	_day_times.append(_elapsed)


func _clear_records() -> void:
	_hours.clear()
	_days.clear()
	_hour_times.clear()
	_day_times.clear()
	_elapsed = 0.0


# Simula fotogramas de 1/60 s durante los segundos reales indicados.
func _run_frames(seconds: float) -> void:
	var frames: int = roundi(seconds / FRAME_SECONDS)
	for i: int in range(frames):
		_elapsed += FRAME_SECONDS
		GameClock.advance(FRAME_SECONDS)


func _check_start() -> void:
	GameClock.new_game()
	_expect(GameClock.get_day() == 1 and GameClock.get_month() == 1, "la partida no empieza el día 1 del mes 1")
	_expect(GameClock.get_hour() == GameConstants.START_HOUR and GameClock.get_minute() == 0,
		"la partida no empieza a las %d:00" % GameConstants.START_HOUR)
	_expect(GameClock.get_weekday() == 0, "el día 1 no es lunes")
	_expect(GameClock.get_speed() == 1.0 and not GameClock.is_paused, "la partida no empieza a 1x")


# Mide el tiempo real entre dos medianoches seguidas y entre horas seguidas.
func _check_day_length(speed_index: int) -> void:
	GameClock.new_game()
	GameClock.set_speed_index(speed_index)
	var speed: float = GameClock.get_speed()
	var expected_day: float = GameConstants.SECONDS_PER_GAME_HOUR * GameConstants.HOURS_PER_DAY / speed
	_clear_records()
	_run_frames(expected_day * 2.5)
	var label := "a %dx" % int(speed)
	_expect(_day_times.size() >= 2, "%s no pasaron dos días" % label)
	if _day_times.size() >= 2:
		var day_length: float = _day_times[1] - _day_times[0]
		_expect(absf(day_length - expected_day) <= FRAME_SECONDS * 1.5,
			"%s un día duró %.3f s, se esperaban %.1f s" % [label, day_length, expected_day])
		print("Día %s: %.3f s reales (esperado %.1f s)" % [label, day_length, expected_day])
	var expected_hour: float = GameConstants.SECONDS_PER_GAME_HOUR / speed
	for i: int in range(1, _hour_times.size()):
		var hour_length: float = _hour_times[i] - _hour_times[i - 1]
		_expect(absf(hour_length - expected_hour) <= FRAME_SECONDS * 1.5,
			"%s una hora duró %.3f s, se esperaban %.2f s" % [label, hour_length, expected_hour])
	# Las horas llegan seguidas y la medianoche pasa a las 0.
	for i: int in range(1, _hours.size()):
		_expect(_hours[i] == (_hours[i - 1] + 1) % GameConstants.HOURS_PER_DAY,
			"%s horas fuera de orden: %d tras %d" % [label, _hours[i], _hours[i - 1]])


func _check_pause() -> void:
	GameClock.new_game()
	GameClock.set_speed_index(2)
	_run_frames(1.0)
	var before: Dictionary = GameClock.export_state()
	GameClock.set_paused(true)
	_clear_records()
	_run_frames(600.0)
	var after: Dictionary = GameClock.export_state()
	_expect(_hours.is_empty() and _days.is_empty(), "en pausa se emitieron señales")
	_expect(before["hour"] == after["hour"] and before["day_count"] == after["day_count"]
		and before["seconds_into_hour"] == after["seconds_into_hour"], "en pausa el reloj avanzó")
	_expect(GameClock.get_time_scale() == 0.0, "en pausa la escala de tiempo no es 0")
	GameClock.toggle_pause()
	_expect(not GameClock.is_paused and GameClock.get_speed() == 4.0,
		"al quitar la pausa no se recuperó la velocidad 4x")


# Un fotograma muy largo debe emitir todas las horas intermedias, en orden.
func _check_big_step() -> void:
	GameClock.new_game()
	_clear_records()
	GameClock.advance(GameConstants.SECONDS_PER_GAME_HOUR * 20.0 + 0.5)
	_expect(_hours.size() == 20, "un paso de 20 horas emitió %d horas" % _hours.size())
	var expected: Array[int] = []
	for i: int in range(20):
		expected.append((GameConstants.START_HOUR + 1 + i) % GameConstants.HOURS_PER_DAY)
	_expect(_hours == expected, "horas del paso largo: %s" % [_hours])
	_expect(_days == [Vector2i(2, 1)], "días del paso largo: %s" % [_days])
	_expect(GameClock.get_hour() == (GameConstants.START_HOUR + 20) % GameConstants.HOURS_PER_DAY,
		"hora tras el paso largo: %d" % GameClock.get_hour())
	_expect(GameClock.get_minute() == 6, "minuto tras el paso largo: %d" % GameClock.get_minute())


# Recorre 61 días: cambio de mes en el día 31 y de semana cada 7 días.
func _check_calendar() -> void:
	GameClock.new_game()
	_clear_records()
	var day_seconds: float = GameConstants.SECONDS_PER_GAME_HOUR * GameConstants.HOURS_PER_DAY
	for i: int in range(GameConstants.DAYS_PER_MONTH * 2 + 1):
		GameClock.advance(day_seconds)
	_expect(_days.size() == GameConstants.DAYS_PER_MONTH * 2 + 1, "días recorridos: %d" % _days.size())
	_expect(_days.has(Vector2i(GameConstants.DAYS_PER_MONTH, 1)), "no hubo día %d del mes 1" % GameConstants.DAYS_PER_MONTH)
	_expect(_days.has(Vector2i(1, 2)) and _days.has(Vector2i(1, 3)), "no se cambió de mes tras el día 30")
	_expect(not _days.has(Vector2i(GameConstants.DAYS_PER_MONTH + 1, 1)), "hubo un día 31")
	for payday: int in GameConstants.PAYROLL_DAYS:
		_expect(_days.has(Vector2i(payday, 1)), "no hubo día de nómina %d" % payday)
	_expect(GameClock.get_day() == 2 and GameClock.get_month() == 3,
		"tras 61 días la fecha es día %d, mes %d" % [GameClock.get_day(), GameClock.get_month()])
	_expect(GameClock.get_weekday() == (GameConstants.DAYS_PER_MONTH * 2 + 1) % GameConstants.DAYS_PER_WEEK,
		"día de la semana: %d" % GameClock.get_weekday())


func _check_state_round_trip() -> void:
	GameClock.new_game()
	GameClock.set_speed_index(1)
	GameClock.advance(1234.5)
	GameClock.set_paused(true)
	var saved: Dictionary = GameClock.export_state()
	# Como en un guardado real, el estado pasa por JSON.
	var restored: Dictionary = JSON.parse_string(JSON.stringify(saved))
	GameClock.new_game()
	GameClock.import_state(restored)
	_expect(GameClock.export_state() == saved, "el estado del reloj no se restauró igual: %s vs %s" % [
		GameClock.export_state(), saved])
