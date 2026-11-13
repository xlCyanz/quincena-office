# Reloj del juego: hora de 24 horas, fecha (día, mes de 30 días y día de la semana),
# pausa y velocidades 1x, 2x y 4x. Avisa de cada hora y cada día por EventBus.
extends Node

const MINUTES_PER_HOUR: int = 60

## Índice de la velocidad actual dentro de GameConstants.CLOCK_SPEEDS (0 = 1x).
var speed_index: int = 0

## Si está en pausa no avanza nada. Al quitar la pausa se recupera la velocidad que había.
var is_paused: bool = false
# Un salto de horas en curso debe cortarse (ver interrupt).
var _interrupted: bool = false
## true mientras los sistemas reaccionan al cambio de hora: OfficeState y Staff solo usan
## sus cachés por hora entonces (fuera, por ejemplo en las pruebas que cambian cosas a mano,
## calculan de nuevo).
var in_hour_tick: bool = false

# Días completos desde el inicio de la partida (0 = día 1 del mes 1).
var _day_count: int = 0
var _hour: int = GameConstants.START_HOUR
# Segundos reales acumulados dentro de la hora actual, ya multiplicados por la velocidad.
var _seconds_into_hour: float = 0.0
# El primer fotograma después de start() trae en su delta lo que tardó en cargar la
# escena; ese tiempo no es de juego y se descarta.
var _skip_next_frame: bool = false


func _ready() -> void:
	# Fuera de una partida (por ejemplo, en el menú) el reloj no corre.
	set_process(false)


func _process(delta: float) -> void:
	if _skip_next_frame:
		_skip_next_frame = false
		return
	advance(delta)


## Hace que el reloj corra con los fotogramas. Lo llama la escena de juego al abrirse.
func start() -> void:
	_skip_next_frame = true
	set_process(true)


## Detiene el reloj (no es una pausa del jugador: lo usa la escena al cerrarse).
func stop() -> void:
	set_process(false)


## Avanza el reloj según los segundos reales transcurridos, aplicando pausa y velocidad.
## Si en un solo paso pasan varias horas, avisa de cada una en orden.
func advance(real_seconds: float) -> void:
	_seconds_into_hour += real_seconds * get_time_scale()
	while _seconds_into_hour >= GameConstants.SECONDS_PER_GAME_HOUR:
		_seconds_into_hour -= GameConstants.SECONDS_PER_GAME_HOUR
		_next_hour()


## Salta hasta el inicio de la hora que está `hours` horas por delante de la actual
## (1 = el inicio de la próxima hora). Avisa de cada hora y cada día intermedios, para
## que nada que dependa de ellos (por ejemplo, la nómina) se pierda. Se usa cuando la
## oficina queda vacía, para saltar hasta la próxima hora de entrada.
## Se corta si algo llama a interrupt() en medio (por ejemplo, una ventana que pausa).
func fast_forward_hours(hours: int) -> void:
	_seconds_into_hour = 0.0
	_interrupted = false
	for i: int in range(hours):
		if _interrupted:
			break
		_next_hour()
	_interrupted = false


## Adelanta el reloj dentro de la hora actual hasta ese minuto (sin pasar de hora); no
## retrocede. Lo usa el salto de la oficina vacía para llegar a la primera entrada.
func skip_to_minute(minute: int) -> void:
	var seconds: float = clampi(minute, 0, 59) * GameConstants.SECONDS_PER_GAME_HOUR / 60.0
	_seconds_into_hour = maxf(_seconds_into_hour, seconds)


## Corta el salto de fast_forward_hours en curso después de la hora actual.
func interrupt() -> void:
	_interrupted = true


func _next_hour() -> void:
	_hour += 1
	if _hour >= GameConstants.HOURS_PER_DAY:
		_hour = 0
		_day_count += 1
		EventBus.day_changed.emit(get_day(), get_month())
	in_hour_tick = true
	EventBus.hour_changed.emit(_hour)
	in_hour_tick = false


## Multiplicador del tiempo: 0 en pausa; si no, la velocidad actual. Los sistemas que
## se mueven con el tiempo (por ejemplo, los personajes) lo usan para ir al mismo ritmo.
func get_time_scale() -> float:
	return 0.0 if is_paused else get_speed()


## Velocidad seleccionada (1, 2 o 4), aunque esté en pausa.
func get_speed() -> float:
	return GameConstants.CLOCK_SPEEDS[speed_index]


## Elige una velocidad por su índice en CLOCK_SPEEDS y quita la pausa.
func set_speed_index(index: int) -> void:
	speed_index = clampi(index, 0, GameConstants.CLOCK_SPEEDS.size() - 1)
	is_paused = false


## Pone o quita la pausa.
func set_paused(paused: bool) -> void:
	is_paused = paused


## Alterna entre pausa y la última velocidad elegida.
func toggle_pause() -> void:
	set_paused(not is_paused)


## Hora actual, de 0 a 23.
func get_hour() -> int:
	return _hour


## Minuto actual dentro de la hora, de 0 a 59.
func get_minute() -> int:
	var fraction: float = _seconds_into_hour / GameConstants.SECONDS_PER_GAME_HOUR
	return mini(floori(fraction * MINUTES_PER_HOUR), MINUTES_PER_HOUR - 1)


## Día del mes, de 1 a DAYS_PER_MONTH.
func get_day() -> int:
	return _day_count % GameConstants.DAYS_PER_MONTH + 1


## Mes desde el inicio de la partida, empezando en 1.
func get_month() -> int:
	@warning_ignore("integer_division")
	return _day_count / GameConstants.DAYS_PER_MONTH + 1


## Día de la semana: 0 = lunes … 6 = domingo. El día 1 de la partida es lunes.
func get_weekday() -> int:
	return _day_count % GameConstants.DAYS_PER_WEEK


## Días completos desde el inicio de la partida (0 el primer día).
func get_day_count() -> int:
	return _day_count


## Prepara el reloj de una partida nueva: día 1, mes 1, a la hora de entrada, a la velocidad
## inicial de las opciones.
func new_game() -> void:
	_day_count = 0
	_hour = GameConstants.START_HOUR
	_seconds_into_hour = 0.0
	# La velocidad con que empieza una partida nueva es una opción del jugador (hito 60).
	speed_index = clampi(int(Settings.get_value("start_speed")), 0, GameConstants.CLOCK_SPEEDS.size() - 1)
	is_paused = false


## Devuelve el estado del reloj para guardarlo (hito 9).
func export_state() -> Dictionary:
	return {
		"day_count": _day_count,
		"hour": _hour,
		"seconds_into_hour": _seconds_into_hour,
		"speed_index": speed_index,
		"is_paused": is_paused,
	}


## Restaura el estado del reloj desde una partida guardada (hito 9).
func import_state(state: Dictionary) -> void:
	_day_count = maxi(int(state.get("day_count", 0)), 0)
	_hour = clampi(int(state.get("hour", GameConstants.START_HOUR)), 0, GameConstants.HOURS_PER_DAY - 1)
	_seconds_into_hour = clampf(float(state.get("seconds_into_hour", 0.0)), 0.0, GameConstants.SECONDS_PER_GAME_HOUR)
	speed_index = clampi(int(state.get("speed_index", 0)), 0, GameConstants.CLOCK_SPEEDS.size() - 1)
	is_paused = bool(state.get("is_paused", false))
