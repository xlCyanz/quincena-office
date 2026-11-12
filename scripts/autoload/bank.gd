# Banco (diseño, 8 y 13.6). Hito 21: la calificación de crédito, una letra de la A a la
# E que sale de un puntaje: base_score (C) más ingresos de contratos del mes pasado,
# bienes (reventa de muebles y computadoras), antigüedad y pagos puntuales, menos los
# atrasos (data/bank.json). Cada letra da un interés mensual y un límite de préstamo
# (múltiplo del ingreso mensual, nunca menos de min_limit). Los préstamos, la mora y el
# embargo llegan en los hitos 22 a 24.
#
# Se recalcula el día 1 de cada mes (después del mantenimiento, porque Economy va antes
# en la lista de autoloads) y en el momento de un atraso. Los pagos llegan por
# EventBus.payment_recorded: la nómina (Staff) y el mantenimiento (Economy).
extends Node

const DATA_PATH: String = "res://data/bank.json"
## Letra actual ("A" … "E").
var rating: String = "C"
## Puntaje con el que se calculó la letra (0 a 100).
var score: int = 50
## Ingresos de contratos del mes pasado (lo que vale para el límite).
var monthly_income: int = 0
## Historial de pagos obligatorios.
var on_time_payments: int = 0
var late_payments: int = 0

var _data: Dictionary = {}


func _ready() -> void:
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.payment_recorded.connect(_on_payment_recorded)


## Deja el banco como en una partida nueva: sin historial, en la letra que da la base.
func new_game() -> void:
	monthly_income = 0
	on_time_payments = 0
	late_payments = 0
	_recalculate(false)


## Valor de configuración de data/bank.json.
func get_config(key: String) -> Variant:
	return _config_data().get(key)


## Fila de la letra actual en la tabla: {"letter", "min_score", "monthly_rate", "limit_multiple"}.
func get_rating_info(letter: String = "") -> Dictionary:
	var wanted: String = rating if letter.is_empty() else letter
	for row: Dictionary in _config_data().get("ratings", []):
		if row["letter"] == wanted:
			return row
	return {}


## Interés mensual de la letra actual (0.045 = 4.5 %).
func get_monthly_rate() -> float:
	return float(get_rating_info().get("monthly_rate", 0.0))


## Cuánto presta el banco como máximo: múltiplo de la letra × ingreso del mes pasado,
## nunca menos de min_limit.
func get_limit() -> int:
	var multiple: float = float(get_rating_info().get("limit_multiple", 0))
	return maxi(int(_config_data().get("min_limit", 0)), roundi(multiple * monthly_income))


## Valor de reventa de los muebles y computadoras de la oficina (lo que cuenta como bienes).
func get_assets_value() -> int:
	var total: int = 0
	for item: Dictionary in OfficeState.furniture:
		total += FurnitureCatalog.get_resale(item["id"])
		if not String(item.get("computer", "")).is_empty():
			total += FurnitureCatalog.get_resale(item["computer"])
	return total


## Conceptos de la cuenta que cuentan como ingresos de contratos (la devolución de un
## anticipo resta).
func get_income_concepts() -> Array[String]:
	return [Projects.CONCEPT_DELIVERY, Projects.CONCEPT_ADVANCE, Projects.CONCEPT_REFUND]


## Meses completos desde el inicio de la partida.
func get_age_months() -> int:
	return GameClock.get_month() - 1


## Lo que suma cada factor al puntaje: lista de {"label", "detail", "points"}.
func get_score_parts() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	parts.append({"label": "Base", "detail": "", "points": int(_config_data().get("base_score", 0))})
	parts.append({"label": "Ingresos del mes pasado", "detail": MoneyFormat.format(monthly_income),
		"points": _scaled(monthly_income, "income_for_max_points", "income_points_max")})
	var assets: int = get_assets_value()
	parts.append({"label": "Bienes", "detail": MoneyFormat.format(assets),
		"points": _scaled(assets, "assets_for_max_points", "assets_points_max")})
	var months: int = get_age_months()
	parts.append({"label": "Antigüedad", "detail": "%d %s" % [months, "mes" if months == 1 else "meses"],
		"points": mini(months * int(_config_data().get("age_points_per_month", 0)), int(_config_data().get("age_points_max", 0)))})
	parts.append({"label": "Pagos a tiempo", "detail": str(on_time_payments),
		"points": mini(on_time_payments * int(_config_data().get("on_time_points", 0)), int(_config_data().get("on_time_points_max", 0)))})
	parts.append({"label": "Atrasos", "detail": str(late_payments),
		"points": late_payments * int(_config_data().get("late_points", 0))})
	return parts


## Puntaje que daría la situación de hoy (0 a 100).
func compute_score() -> int:
	var total: int = 0
	for part: Dictionary in get_score_parts():
		total += int(part["points"])
	return clampi(total, 0, 100)


## Letra que corresponde a un puntaje.
func letter_for(value: int) -> String:
	for row: Dictionary in _config_data().get("ratings", []):
		if value >= int(row["min_score"]):
			return row["letter"]
	return "E"


# Puntos proporcionales: value / for_max × max, sin pasar de max.
func _scaled(value: int, for_max_key: String, max_key: String) -> int:
	var for_max: float = maxf(1.0, float(_config_data().get(for_max_key, 1)))
	var max_points: int = int(_config_data().get(max_key, 0))
	return clampi(floori(float(value) / for_max * max_points), 0, max_points)


func _on_day_changed(day: int, month: int) -> void:
	if day != 1:
		return
	var totals: Dictionary[String, int] = Economy.get_month_totals(month - 1)
	monthly_income = 0
	for concept: String in get_income_concepts():
		monthly_income += totals.get(concept, 0)
	monthly_income = maxi(0, monthly_income)
	_recalculate(true)


func _on_payment_recorded(_concept: String, on_time: bool) -> void:
	if on_time:
		# Los pagos puntuales suben la nota recién el día 1.
		on_time_payments += 1
		return
	late_payments += 1
	_recalculate(true)


# Recalcula puntaje y letra; si announce y cambia la letra, avisa.
func _recalculate(announce: bool) -> void:
	var previous: String = rating
	score = compute_score()
	rating = letter_for(score)
	if announce and rating != previous:
		var up: bool = rating < previous  # "A" < "B": una letra menor es mejor.
		EventBus.notice.emit("La calificación de crédito %s a %s." % ["sube" if up else "baja", rating])
	EventBus.bank_changed.emit()


## Devuelve el estado del banco para guardarlo.
func export_state() -> Dictionary:
	return {"rating": rating, "score": score, "monthly_income": monthly_income,
		"on_time_payments": on_time_payments, "late_payments": late_payments}


## Restaura el banco. Una partida de antes del hito 21 se calcula con lo que hay.
func import_state(state: Dictionary) -> void:
	monthly_income = int(state.get("monthly_income", 0))
	on_time_payments = int(state.get("on_time_payments", 0))
	late_payments = int(state.get("late_payments", 0))
	if state.has("rating"):
		rating = String(state["rating"])
		score = int(state.get("score", compute_score()))
	else:
		_recalculate(false)
	EventBus.bank_changed.emit()


# Los datos se leen al usarlos por primera vez: así sirven aunque alguien llame a Bank
# antes de su _ready (por ejemplo, un script que prepara la partida al arrancar).
func _config_data() -> Dictionary:
	if _data.is_empty():
		_data = _load(DATA_PATH)
	return _data


static func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("No se pudo leer %s" % path)
		return {}
	return parsed
