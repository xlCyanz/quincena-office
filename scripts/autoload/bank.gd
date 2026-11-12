# Banco (diseño, 8 y 13.6). Hito 21: la calificación de crédito, una letra de la A a la
# E que sale de un puntaje: base_score (C) más ingresos de contratos del mes pasado,
# bienes (reventa de muebles y computadoras), antigüedad y pagos puntuales, menos los
# atrasos (data/bank.json). Cada letra da un interés mensual y un límite de préstamo
# (múltiplo del ingreso mensual, nunca menos de min_limit).
#
# Hito 22: préstamos con interés simple. Un préstamo guarda el capital con que se
# reparte (base), la tasa, los meses y cuántas cuotas se pagaron; la cuota se cobra el
# día 1 de cada mes siguiente. Se puede saldar antes (capital pendiente + interés de un
# mes) y refinanciar una vez (más meses, tasa más alta). La mora y el embargo llegan en
# el hito 23: hasta entonces una cuota sin dinero se cobra igual y cuenta como atraso.
#
# Se recalcula el día 1 de cada mes (después del mantenimiento, porque Economy va antes
# en la lista de autoloads) y en el momento de un atraso. Los pagos llegan por
# EventBus.payment_recorded: la nómina (Staff) y el mantenimiento (Economy).
extends Node

const DATA_PATH: String = "res://data/bank.json"
const CONCEPT_LOAN: String = "Préstamo"
const CONCEPT_INSTALLMENT: String = "Cuota de préstamo"
const CONCEPT_PREPAYMENT: String = "Pago anticipado de préstamo"
## Letra actual ("A" … "E").
var rating: String = "C"
## Puntaje con el que se calculó la letra (0 a 100).
var score: int = 50
## Ingresos de contratos del mes pasado (lo que vale para el límite).
var monthly_income: int = 0
## Historial de pagos obligatorios.
var on_time_payments: int = 0
var late_payments: int = 0
## Préstamos activos: {"id", "amount" (lo pedido), "base" (capital que se reparte en las
## cuotas), "rate", "months", "paid" (cuotas pagadas), "refinanced", "taken_day"}.
var loans: Array[Dictionary] = []
var _next_loan_id: int = 1

var _data: Dictionary = {}


func _ready() -> void:
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.payment_recorded.connect(_on_payment_recorded)


## Deja el banco como en una partida nueva: sin historial, en la letra que da la base.
func new_game() -> void:
	monthly_income = 0
	on_time_payments = 0
	late_payments = 0
	loans.clear()
	_next_loan_id = 1
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


# --- Préstamos -------------------------------------------------------------------


## Total a pagar y cuota de un préstamo: {"rate", "total", "installment", "interest"}.
static func quote(amount: int, months: int, rate: float) -> Dictionary:
	var total: int = roundi(amount * (1.0 + rate * months))
	return {"rate": rate, "total": total, "installment": roundi(float(total) / months), "interest": total - amount}


## Cuánto se debe de capital, sumando todos los préstamos.
func get_debt() -> int:
	var total: int = 0
	for loan: Dictionary in loans:
		total += get_remaining_principal(loan)
	return total


## Lo que todavía se puede pedir: el límite menos el capital pendiente.
func get_available() -> int:
	return maxi(0, get_limit() - get_debt())


## Capital pendiente de un préstamo (la parte de capital de las cuotas que faltan).
func get_remaining_principal(loan: Dictionary) -> int:
	var months: int = loan["months"]
	return int(loan["base"]) - roundi(float(loan["base"]) * int(loan["paid"]) / months)


## Cuotas que faltan.
func get_remaining_months(loan: Dictionary) -> int:
	return int(loan["months"]) - int(loan["paid"])


## Cuota mensual de un préstamo. La última ajusta el redondeo para cerrar el total justo.
func get_installment(loan: Dictionary) -> int:
	var terms: Dictionary = quote(loan["base"], loan["months"], loan["rate"])
	if get_remaining_months(loan) == 1:
		return int(terms["total"]) - int(terms["installment"]) * (int(loan["months"]) - 1)
	return terms["installment"]


## Lo que falta pagar en cuotas.
func get_remaining_total(loan: Dictionary) -> int:
	var terms: Dictionary = quote(loan["base"], loan["months"], loan["rate"])
	return int(terms["total"]) - int(terms["installment"]) * int(loan["paid"])


## Saldar hoy: capital pendiente más el interés de un mes.
func get_prepay_cost(loan: Dictionary) -> int:
	return get_remaining_principal(loan) + roundi(float(loan["base"]) * float(loan["rate"]))


func get_loan(loan_id: int) -> Dictionary:
	for loan: Dictionary in loans:
		if int(loan["id"]) == loan_id:
			return loan
	return {}


## Por qué no se puede pedir ese préstamo, o "" si se puede.
func loan_problem(amount: int, months: int) -> String:
	var min_amount: int = int(get_config("loan_min_amount"))
	if amount < min_amount:
		return "El monto mínimo es %s." % MoneyFormat.format(min_amount)
	if months < int(get_config("loan_min_months")) or months > int(get_config("loan_max_months")):
		return "El plazo va de %d a %d meses." % [int(get_config("loan_min_months")), int(get_config("loan_max_months"))]
	if amount > get_available():
		return "El banco te presta hasta %s más (límite %s, debes %s)." % [
			MoneyFormat.format(get_available()), MoneyFormat.format(get_limit()), MoneyFormat.format(get_debt())]
	return ""


## Pide un préstamo con la tasa de la letra actual. Devuelve {"ok", "message"}.
func request_loan(amount: int, months: int) -> Dictionary:
	var problem: String = loan_problem(amount, months)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var loan: Dictionary = {"id": _next_loan_id, "amount": amount, "base": amount, "rate": get_monthly_rate(),
		"months": months, "paid": 0, "refinanced": false, "taken_day": GameClock.get_day_count()}
	_next_loan_id += 1
	loans.append(loan)
	Economy.earn(amount, CONCEPT_LOAN)
	var message: String = "Préstamo de %s a %d meses: cuota de %s desde el día 1." % [
		MoneyFormat.format(amount), months, MoneyFormat.format(get_installment(loan))]
	EventBus.bank_changed.emit()
	EventBus.notice.emit(message)
	return {"ok": true, "message": message}


## Salda un préstamo antes de tiempo. Devuelve {"ok", "message"}.
func prepay(loan_id: int) -> Dictionary:
	var loan: Dictionary = get_loan(loan_id)
	if loan.is_empty():
		return {"ok": false, "message": "Ese préstamo ya no está."}
	var cost: int = get_prepay_cost(loan)
	if not Economy.spend(cost, CONCEPT_PREPAYMENT):
		return {"ok": false, "message": "No alcanza: saldarlo cuesta %s." % MoneyFormat.format(cost)}
	var saved: int = get_remaining_total(loan) - cost
	loans.erase(loan)
	var message: String = "Préstamo saldado por %s (ahorras %s de intereses)." % [MoneyFormat.format(cost), MoneyFormat.format(maxi(0, saved))]
	EventBus.bank_changed.emit()
	EventBus.notice.emit(message)
	return {"ok": true, "message": message}


## Cómo quedaría refinanciado: {"months", "rate", "installment", "total"} o vacío si no se puede.
func preview_refinance(loan: Dictionary, extra_months: int) -> Dictionary:
	if not refinance_problem(loan, extra_months).is_empty():
		return {}
	var months: int = get_remaining_months(loan) + extra_months
	var rate: float = float(loan["rate"]) + float(get_config("refinance_rate_increase"))
	var terms: Dictionary = quote(get_remaining_principal(loan), months, rate)
	return {"months": months, "rate": rate, "installment": terms["installment"], "total": terms["total"]}


## Por qué no se puede refinanciar así, o "".
func refinance_problem(loan: Dictionary, extra_months: int) -> String:
	if loan.is_empty():
		return "Ese préstamo ya no está."
	if bool(loan["refinanced"]):
		return "Este préstamo ya se refinanció una vez."
	var min_extra: int = int(get_config("refinance_min_extra"))
	var max_extra: int = mini(int(get_config("refinance_max_extra")), int(get_config("loan_max_months")) - get_remaining_months(loan))
	if max_extra < min_extra:
		return "Ya tiene el plazo máximo de %d meses." % int(get_config("loan_max_months"))
	if extra_months < min_extra or extra_months > max_extra:
		return "Se puede alargar de %d a %d meses." % [min_extra, max_extra]
	return ""


## Mayor alargue posible para un préstamo (0 si no se puede refinanciar).
func get_max_refinance_extra(loan: Dictionary) -> int:
	if loan.is_empty() or bool(loan["refinanced"]):
		return 0
	var max_extra: int = mini(int(get_config("refinance_max_extra")), int(get_config("loan_max_months")) - get_remaining_months(loan))
	return max_extra if max_extra >= int(get_config("refinance_min_extra")) else 0


## Refinancia un préstamo: el capital pendiente se reparte en más meses con la tasa más alta.
func refinance(loan_id: int, extra_months: int) -> Dictionary:
	var loan: Dictionary = get_loan(loan_id)
	var problem: String = refinance_problem(loan, extra_months)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var terms: Dictionary = preview_refinance(loan, extra_months)
	loan["base"] = get_remaining_principal(loan)
	loan["months"] = terms["months"]
	loan["rate"] = terms["rate"]
	loan["paid"] = 0
	loan["refinanced"] = true
	var message: String = "Préstamo refinanciado: %d cuotas de %s." % [terms["months"], MoneyFormat.format(terms["installment"])]
	EventBus.bank_changed.emit()
	EventBus.notice.emit(message)
	return {"ok": true, "message": message}


# Cobra la cuota de cada préstamo (el día 1). Sin dinero se cobra igual y es un atraso.
func _charge_installments() -> void:
	for loan: Dictionary in loans.duplicate():
		Economy.charge(get_installment(loan), CONCEPT_INSTALLMENT)
		loan["paid"] = int(loan["paid"]) + 1
		if get_remaining_months(loan) <= 0:
			loans.erase(loan)
			EventBus.notice.emit("Pagaste la última cuota de un préstamo de %s." % MoneyFormat.format(int(loan["amount"])))
		EventBus.payment_recorded.emit(CONCEPT_INSTALLMENT, Economy.balance >= 0)


func _on_day_changed(day: int, month: int) -> void:
	if day != 1:
		return
	_charge_installments()
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
		"on_time_payments": on_time_payments, "late_payments": late_payments,
		"loans": loans.duplicate(true), "next_loan_id": _next_loan_id}


## Restaura el banco. Una partida de antes del hito 21 se calcula con lo que hay.
func import_state(state: Dictionary) -> void:
	monthly_income = int(state.get("monthly_income", 0))
	on_time_payments = int(state.get("on_time_payments", 0))
	late_payments = int(state.get("late_payments", 0))
	loans.clear()
	for saved: Dictionary in state.get("loans", []):
		loans.append({"id": int(saved["id"]), "amount": int(saved["amount"]), "base": int(saved.get("base", saved["amount"])),
			"rate": float(saved["rate"]), "months": int(saved["months"]), "paid": int(saved.get("paid", 0)),
			"refinanced": bool(saved.get("refinanced", false)), "taken_day": int(saved.get("taken_day", 0))})
	_next_loan_id = int(state.get("next_loan_id", loans.size() + 1))
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
