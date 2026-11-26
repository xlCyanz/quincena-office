# Banco: calificación A–E por puntaje (data/bank.json), que fija tasa y límite; préstamos de interés
# simple con cuota el día 1, mora con recargo, embargo y préstamo de emergencia para la nómina.
# Se recalcula el día 1 (después del mantenimiento de Economy) y al haber un atraso.
extends Node

const DATA_PATH: String = "res://data/bank.json"
const CONCEPT_LOAN: String = "Préstamo"
const CONCEPT_INSTALLMENT: String = "Cuota de préstamo"
const CONCEPT_PREPAYMENT: String = "Pago anticipado de préstamo"
const CONCEPT_OVERDUE: String = "Cuota atrasada"
const CONCEPT_SURPLUS: String = "Sobrante del embargo"
const CONCEPT_EMERGENCY: String = "Préstamo de emergencia"
## Conceptos del inversionista: el efectivo que pone (no es ingreso) y su pago mensual.
const CONCEPT_INVESTMENT: String = "Inversión"
const CONCEPT_INVESTOR: String = "Pago al inversionista"
## Letra actual ("A" … "E").
var rating: String = "C"
## Puntaje con el que se calculó la letra (0 a 100).
var score: int = 50
## Ingresos de contratos del mes pasado (lo que vale para el límite).
var monthly_income: int = 0
## Pagos obligatorios hechos a tiempo.
var on_time_payments: int = 0
var late_payments: int = 0
## Préstamos activos: {"id", "amount", "base" (capital repartido en las cuotas), "rate",
## "months", "paid" (cuotas pagadas), "refinanced", "taken_day"}.
var loans: Array[Dictionary] = []
var _next_loan_id: int = 1
## Días 1 seguidos con alguna cuota atrasada (0 = al día).
var overdue_months: int = 0
## La partida terminó por embargo (el banco ya no hace nada).
var game_over: bool = false
## Préstamo de emergencia ofrecido y sin responder: {"amount", "shortfall", "rate",
## "months", "installment", "total", "first_due_day"}; vacío si no hay.
var emergency_offer: Dictionary = {}
## Inversionista activo, o {}: {"cash", "share", "months", "paid_months", "paid_total",
## "income_before" (ingresos del mes en que se aceptó, que no le tocan), "day"}.
var investor: Dictionary = {}
## Solo para pruebas: false deja fuera el evento del inversionista. No se guarda.
var investor_enabled: bool = true
# Evita pagar atrasos dentro de otro pago (cada pago cambia el saldo).
var _paying_overdue: bool = false

var _data: Dictionary = {}


func _ready() -> void:
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.payment_recorded.connect(_on_payment_recorded)
	EventBus.balance_changed.connect(func(_balance: int) -> void: _pay_overdue())
	EventBus.payroll_short.connect(_on_payroll_short)


## Deja el banco como en una partida nueva: sin historial, en la letra que da la base.
func new_game() -> void:
	monthly_income = 0
	on_time_payments = 0
	late_payments = 0
	loans.clear()
	_next_loan_id = 1
	overdue_months = 0
	game_over = false
	emergency_offer = {}
	investor = {}
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


## Interés mensual de un préstamo nuevo (0.045 = 4.5 %): el de la letra menos el descuento del contador, con mínimo.
func get_monthly_rate() -> float:
	var rate: float = float(get_rating_info().get("monthly_rate", 0.0))
	var discount: float = Staff.get_loan_rate_discount()
	if discount <= 0.0:
		return rate
	return maxf(rate - discount, minf(rate, float(StaffCatalog.get_accounting("min_loan_rate"))))


## Lo que se cobraría el próximo día 1: las cuotas que tocan y las atrasadas.
func get_due_on_first() -> int:
	var day_count: int = GameClock.get_day_count()
	var next_first: int = day_count + GameConstants.DAYS_PER_MONTH - (GameClock.get_day() - 1)
	var total: int = get_overdue()
	for loan: Dictionary in loans:
		if get_remaining_months(loan) > 0 and next_first >= int(loan.get("first_due_day", 0)):
			total += get_installment(loan)
	return total


## Máximo que presta el banco: múltiplo de la letra × ingreso del mes pasado, al menos min_limit.
func get_limit() -> int:
	var multiple: float = float(get_rating_info().get("limit_multiple", 0))
	return maxi(int(_config_data().get("min_limit", 0)), roundi(multiple * monthly_income))


## Valor de reventa de muebles y computadoras (los bienes), los puestos y los del inventario.
func get_assets_value() -> int:
	var total: int = 0
	for item: Dictionary in OfficeState.furniture:
		total += FurnitureCatalog.get_resale(item["id"])
		if not String(item.get("computer", "")).is_empty():
			total += FurnitureCatalog.get_resale(item["computer"])
		if not String(item.get("monitor", "")).is_empty():
			total += FurnitureCatalog.get_resale(item["monitor"]) * FurnitureCatalog.get_monitor_count(item)
	for id: String in OfficeState.inventory:
		total += FurnitureCatalog.get_resale(id) * OfficeState.inventory[id]
	return total


## Conceptos que cuentan como ingresos de contratos (devolver un anticipo resta).
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


## Cuotas atrasadas (con recargo), sumando todos los préstamos.
func get_overdue() -> int:
	var total: int = 0
	for loan: Dictionary in loans:
		total += int(loan.get("overdue", 0))
	return total


## Lo que se embarga: cuotas atrasadas más capital pendiente.
func get_seizable_debt() -> int:
	return get_overdue() + get_debt()


## Cuánto se debe de capital, sumando todos los préstamos.
func get_debt() -> int:
	var total: int = 0
	for loan: Dictionary in loans:
		total += get_remaining_principal(loan)
	return total


## Capital pendiente que cuenta para el límite (sin los préstamos de emergencia).
func get_limit_debt() -> int:
	var total: int = 0
	for loan: Dictionary in loans:
		if not bool(loan.get("emergency", false)):
			total += get_remaining_principal(loan)
	return total


## Lo que todavía se puede pedir: el límite menos el capital pendiente.
func get_available() -> int:
	return maxi(0, get_limit() - get_limit_debt())


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


## Saldar hoy: capital pendiente más el interés de un mes y las cuotas atrasadas.
func get_prepay_cost(loan: Dictionary) -> int:
	var interest: int = roundi(float(loan["base"]) * float(loan["rate"])) if get_remaining_months(loan) > 0 else 0
	return get_remaining_principal(loan) + interest + int(loan.get("overdue", 0))


func get_loan(loan_id: int) -> Dictionary:
	for loan: Dictionary in loans:
		if int(loan["id"]) == loan_id:
			return loan
	return {}


## Por qué no se puede pedir ese préstamo, o "" si se puede.
func loan_problem(amount: int, months: int) -> String:
	if overdue_months >= int(get_config("warning_months")):
		return "El banco no presta: llevas %d meses con cuotas atrasadas." % overdue_months
	var min_amount: int = int(get_config("loan_min_amount"))
	if amount < min_amount:
		return "El monto mínimo es %s." % MoneyFormat.format(min_amount)
	if months < int(get_config("loan_min_months")) or months > int(get_config("loan_max_months")):
		return "El plazo va de %d a %d meses." % [int(get_config("loan_min_months")), int(get_config("loan_max_months"))]
	var stage_cap: int = Company.get_max_loan()
	if stage_cap > 0 and amount > stage_cap:
		return "En %s el banco presta hasta %s por préstamo." % [Company.get_stage_name(), MoneyFormat.format(stage_cap)]
	if amount > get_available():
		return "El banco te presta hasta %s más (límite %s, debes %s)." % [
			MoneyFormat.format(get_available()), MoneyFormat.format(get_limit()), MoneyFormat.format(get_limit_debt())]
	return ""


## Lo más que se puede pedir hoy: lo disponible del límite, con el tope por préstamo de la etapa.
func get_max_request() -> int:
	var stage_cap: int = Company.get_max_loan()
	return get_available() if stage_cap <= 0 else mini(get_available(), stage_cap)


## Pide un préstamo con la tasa de la letra actual. Devuelve {"ok", "message"}.
func request_loan(amount: int, months: int) -> Dictionary:
	var problem: String = loan_problem(amount, months)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var loan: Dictionary = {"id": _next_loan_id, "amount": amount, "base": amount, "rate": get_monthly_rate(),
		"months": months, "paid": 0, "refinanced": false, "taken_day": GameClock.get_day_count(), "overdue": 0,
		"emergency": false, "first_due_day": 0}
	_next_loan_id += 1
	loans.append(loan)
	Economy.earn(amount, CONCEPT_LOAN)
	var message: String = "Préstamo de %s a %d meses: cuota de %s desde el día 1." % [
		MoneyFormat.format(amount), months, MoneyFormat.format(get_installment(loan))]
	EventBus.bank_changed.emit()
	EventBus.send_notice(EventBus.target_menu("bank"), message)
	return {"ok": true, "message": message}


## Salda un préstamo antes de tiempo. Devuelve {"ok", "message"}.
func prepay(loan_id: int) -> Dictionary:
	var loan: Dictionary = get_loan(loan_id)
	if loan.is_empty():
		return {"ok": false, "message": "Ese préstamo ya no está."}
	var cost: int = get_prepay_cost(loan)
	if not Economy.spend(cost, CONCEPT_PREPAYMENT):
		return {"ok": false, "message": "No alcanza: saldarlo cuesta %s." % MoneyFormat.format(cost)}
	var saved: int = get_remaining_total(loan) + int(loan.get("overdue", 0)) - cost
	loans.erase(loan)
	var message: String = "Préstamo saldado por %s (ahorras %s de intereses)." % [MoneyFormat.format(cost), MoneyFormat.format(maxi(0, saved))]
	EventBus.bank_changed.emit()
	EventBus.send_notice(EventBus.target_menu("bank"), message)
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
	if bool(loan.get("emergency", false)):
		return "El préstamo de emergencia no se refinancia."
	if bool(loan["refinanced"]):
		return "Este préstamo ya se refinanció una vez."
	if get_remaining_months(loan) <= 0:
		return "Ya no le quedan cuotas por venir."
	var min_extra: int = int(get_config("refinance_min_extra"))
	var max_extra: int = mini(int(get_config("refinance_max_extra")), int(get_config("loan_max_months")) - get_remaining_months(loan))
	if max_extra < min_extra:
		return "Ya tiene el plazo máximo de %d meses." % int(get_config("loan_max_months"))
	if extra_months < min_extra or extra_months > max_extra:
		return "Se puede alargar de %d a %d meses." % [min_extra, max_extra]
	return ""


## Mayor alargue posible para un préstamo (0 si no se puede refinanciar).
func get_max_refinance_extra(loan: Dictionary) -> int:
	if loan.is_empty() or bool(loan["refinanced"]) or bool(loan.get("emergency", false)) or get_remaining_months(loan) <= 0:
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
	EventBus.send_notice(EventBus.target_menu("bank"), message)
	return {"ok": true, "message": message}


# Cobra las cuotas del día 1; la que no alcanza queda atrasada con recargo. Luego cuenta los
# meses seguidos debiendo: aviso y, al final, embargo.
func _charge_installments() -> void:
	var fee: float = float(get_config("late_fee_ratio"))
	for loan: Dictionary in loans.duplicate():
		if get_remaining_months(loan) <= 0 or GameClock.get_day_count() < int(loan.get("first_due_day", 0)):
			continue
		var installment: int = get_installment(loan)
		loan["paid"] = int(loan["paid"]) + 1
		# Con atrasos previos tampoco se paga la nueva: va a la cola.
		if int(loan.get("overdue", 0)) == 0 and Economy.spend(installment, CONCEPT_INSTALLMENT):
			EventBus.payment_recorded.emit(CONCEPT_INSTALLMENT, true)
			if get_remaining_months(loan) <= 0:
				loans.erase(loan)
				EventBus.send_notice(EventBus.target_menu("bank"), "Pagaste la última cuota de un préstamo de %s." % MoneyFormat.format(int(loan["amount"])))
			continue
		var late: int = roundi(installment * (1.0 + fee))
		loan["overdue"] = int(loan.get("overdue", 0)) + late
		EventBus.payment_recorded.emit(CONCEPT_INSTALLMENT, false)
		EventBus.send_notice(EventBus.target_menu("bank"), "No alcanza para la cuota de %s: queda atrasada con recargo (%s)." % [
			MoneyFormat.format(installment), MoneyFormat.format(late)])
	if get_overdue() == 0:
		overdue_months = 0
		return
	overdue_months += 1
	if overdue_months >= int(get_config("seizure_months")):
		_seize()
	elif overdue_months >= int(get_config("warning_months")):
		EventBus.send_notice(EventBus.target_menu("bank"), "Aviso de embargo: llevas %d meses con cuotas atrasadas. El banco no presta más y al tercero embarga." % overdue_months)
	EventBus.bank_changed.emit()


# Paga las cuotas atrasadas que alcance el saldo, de la más vieja a la más nueva.
func _pay_overdue() -> void:
	if _paying_overdue or game_over or get_overdue() == 0:
		return
	_paying_overdue = true
	for loan: Dictionary in loans.duplicate():
		var owed: int = int(loan.get("overdue", 0))
		if owed == 0:
			continue
		if not Economy.spend(owed, CONCEPT_OVERDUE):
			break
		loan["overdue"] = 0
		if get_remaining_months(loan) <= 0:
			loans.erase(loan)
	_paying_overdue = false
	if get_overdue() == 0:
		overdue_months = 0
		EventBus.send_notice(EventBus.target_menu("bank"), "Pagaste las cuotas atrasadas: estás al día con el banco.")
	EventBus.bank_changed.emit()


## Lo que pasaría con un embargo hoy (ver Embargo.plan).
func preview_seizure() -> Dictionary:
	return Embargo.plan(OfficeState.furniture, OfficeState.rooms, get_seizable_debt())


# El embargo: se lleva muebles para saldar todo o, si no alcanzan, termina la partida.
func _seize() -> void:
	var debt: int = get_seizable_debt()
	var result: Dictionary = preview_seizure()
	if not bool(result["covers"]):
		game_over = true
		EventBus.send_notice(EventBus.target_menu("bank"), "El banco embargó la empresa: los muebles (%s) no cubren la deuda (%s)." % [
			MoneyFormat.format(int(result["value"])), MoneyFormat.format(debt)])
		EventBus.game_over.emit(get_game_over_stats(debt, int(result["value"])))
		return
	var take: Array[int] = result["take"]
	var indices: Array[int] = take.duplicate()
	indices.sort()
	indices.reverse()
	for index: int in indices:
		OfficeState.furniture.remove_at(index)
	loans.clear()
	overdue_months = 0
	var surplus: int = int(result["recovered"]) - debt
	EventBus.office_changed.emit()
	if surplus > 0:
		Economy.earn(surplus, CONCEPT_SURPLUS)
	EventBus.send_notice(EventBus.target_menu("bank"), "Embargo: el banco se llevó %d %s (%s) y saldó la deuda de %s; te devuelve %s." % [
		take.size(), "mueble" if take.size() == 1 else "muebles", MoneyFormat.format(int(result["recovered"])),
		MoneyFormat.format(debt), MoneyFormat.format(maxi(0, surplus))])


# --- Inversionista ---

## Valor de configuración del inversionista (data/bank.json, investor).
func get_investor_config(key: String) -> Variant:
	return _config_data()["investor"][key]


## Conceptos que cuentan como ingresos para el inversionista: contratos y productos.
func get_investor_income_concepts() -> Array[String]:
	var concepts: Array[String] = get_income_concepts()
	concepts.append(Products.CONCEPT_INCOME)
	return concepts


## Ingresos de contratos y productos de un mes de la cuenta (0 si es negativo).
func get_investor_income(month: int) -> int:
	var totals: Dictionary[String, int] = Economy.get_month_totals(month)
	var income: int = 0
	for concept: String in get_investor_income_concepts():
		income += totals.get(concept, 0)
	return maxi(0, income)


## Por qué no puede llegar un inversionista ahora ("" si puede).
func investor_problem() -> String:
	if not investor_enabled or game_over:
		return "No hay inversionistas."
	if not investor.is_empty():
		return "Ya hay un inversionista."
	if Company.get_value() <= 0:
		return "El valor de la empresa no es positivo."
	if get_investor_income(Economy.get_current_month() - 1) < int(get_investor_config("min_income")):
		return "Faltan ingresos el mes pasado."
	return ""


## Oferta de un inversionista sorteada con rng: {"amount" (efectivo), "share" (0–1),
## "months"}, o {} si no puede llegar uno.
func make_investor_offer(rng: RandomNumberGenerator) -> Dictionary:
	if not investor_problem().is_empty():
		return {}
	var ratios: Array = get_investor_config("cash_ratio")
	var step: int = int(get_investor_config("cash_step"))
	var cash: int = maxi(step, roundi(Company.get_value() * rng.randf_range(float(ratios[0]), float(ratios[1])) / step) * step)
	var range_months: Array = get_investor_config("months")
	var months: int = rng.randi_range(int(range_months[0]), int(range_months[1]))
	return {"amount": cash, "months": months, "share": investor_share(cash, months, get_investor_income(Economy.get_current_month() - 1))}


## Parte de los ingresos que le devuelve return_ratio veces cash en months meses, dentro de share_range, a 1 %.
func investor_share(cash: int, months: int, monthly: int) -> float:
	var limits: Array = get_investor_config("share_range")
	var share: float = cash * float(get_investor_config("return_ratio")) / maxf(1.0, float(monthly) * months)
	return clampf(snappedf(share, 0.01), float(limits[0]), float(limits[1]))


## Acepta una oferta de make_investor_offer: llega el efectivo y empieza a cobrar el día 1.
func accept_investor(offer: Dictionary) -> String:
	if not investor.is_empty() or not offer.has("amount"):
		return ""
	investor = {"cash": int(offer["amount"]), "share": float(offer["share"]), "months": int(offer["months"]),
		"paid_months": 0, "paid_total": 0, "day": GameClock.get_day_count(),
		"income_before": get_investor_income(Economy.get_current_month())}
	Economy.earn(int(offer["amount"]), CONCEPT_INVESTMENT)
	EventBus.bank_changed.emit()
	return describe_investor(investor)


## «recibes $X por el 12 % de los ingresos durante 18 meses».
static func describe_investor(deal: Dictionary) -> String:
	return "recibes %s por el %d %% de los ingresos de contratos y productos durante %d meses" % [
		MoneyFormat.format(int(deal.get("cash", deal.get("amount", 0)))), roundi(float(deal["share"]) * 100.0), int(deal["months"])]


## Estado del inversionista para Empresa y Banco ("" si no hay).
func describe_investor_status() -> String:
	if investor.is_empty():
		return ""
	return "Inversionista: puso %s por el %d %% de los ingresos de contratos y productos. Quedan %d de %d meses; pagado %s, falta unos %s (con el ingreso del mes pasado). Se cobra cada día 1." % [
		MoneyFormat.format(int(investor["cash"])), roundi(float(investor["share"]) * 100.0), get_investor_months_left(),
		int(investor["months"]), MoneyFormat.format(int(investor["paid_total"])), MoneyFormat.format(get_investor_remaining())]


## Meses que faltan por pagarle (0 sin inversionista).
func get_investor_months_left() -> int:
	return 0 if investor.is_empty() else int(investor["months"]) - int(investor["paid_months"])


## Lo que falta por pagarle, estimado con los ingresos del mes pasado (0 sin inversionista).
func get_investor_remaining() -> int:
	if investor.is_empty():
		return 0
	return roundi(float(investor["share"]) * get_investor_income(Economy.get_current_month() - 1) * get_investor_months_left())


# El día 1: le paga su parte de los ingresos del mes que terminó (el primer mes, solo los
# que llegaron después de aceptar) aunque deje el saldo negativo; al cumplir los meses termina.
func _charge_investor(month: int) -> void:
	if investor.is_empty():
		return
	var income: int = maxi(0, get_investor_income(month) - int(investor["income_before"]))
	investor["income_before"] = 0
	var payment: int = roundi(income * float(investor["share"]))
	if payment > 0:
		Economy.charge(payment, CONCEPT_INVESTOR)
	investor["paid_months"] = int(investor["paid_months"]) + 1
	investor["paid_total"] = int(investor["paid_total"]) + payment
	if get_investor_months_left() <= 0:
		EventBus.send_notice(EventBus.target_menu("bank"), "Último pago al inversionista: %s. En total le pagaste %s por %s." % [
			MoneyFormat.format(payment), MoneyFormat.format(int(investor["paid_total"])), MoneyFormat.format(int(investor["cash"]))])
		investor = {}
	else:
		EventBus.send_notice(EventBus.target_menu("bank"), "Pago al inversionista: %s (%d %% de %s). Quedan %d meses." % [
			MoneyFormat.format(payment), roundi(float(investor["share"]) * 100.0), MoneyFormat.format(income), get_investor_months_left()])
	EventBus.bank_changed.emit()


## Indica si hoy el banco ofrecería un préstamo de emergencia (no con meses debiendo).
func can_offer_emergency() -> bool:
	return not game_over and overdue_months < int(get_config("warning_months"))


## Condiciones del préstamo de emergencia para cubrir shortfall.
func make_emergency_offer(shortfall: int) -> Dictionary:
	var step: int = int(get_config("emergency_amount_step"))
	var amount: int = ceili(float(shortfall) / step) * step
	var months: int = int(get_config("emergency_months"))
	var terms: Dictionary = quote(amount, months, float(get_config("emergency_rate")))
	var today: int = GameClock.get_day_count()
	var first_due: int = GameClock.get_month() * GameConstants.DAYS_PER_MONTH
	if first_due - today < int(get_config("emergency_min_days")):
		first_due += GameConstants.DAYS_PER_MONTH
	return {"amount": amount, "shortfall": shortfall, "rate": terms["rate"], "months": months,
		"installment": terms["installment"], "total": terms["total"], "first_due_day": first_due}


## Acepta el préstamo de emergencia ofrecido: llega el dinero y con él se paga la nómina.
func accept_emergency() -> Dictionary:
	if emergency_offer.is_empty():
		return {"ok": false, "message": "No hay ningún préstamo de emergencia ofrecido."}
	var offer: Dictionary = emergency_offer
	emergency_offer = {}
	loans.append({"id": _next_loan_id, "amount": offer["amount"], "base": offer["amount"], "rate": offer["rate"],
		"months": offer["months"], "paid": 0, "refinanced": false, "taken_day": GameClock.get_day_count(), "overdue": 0,
		"emergency": true, "first_due_day": offer["first_due_day"]})
	_next_loan_id += 1
	Economy.earn(int(offer["amount"]), CONCEPT_EMERGENCY)
	EventBus.emergency_loan_resolved.emit(true)
	var message: String = "Préstamo de emergencia de %s: %d cuotas de %s desde el %s." % [
		MoneyFormat.format(int(offer["amount"])), int(offer["months"]), MoneyFormat.format(int(offer["installment"])),
		describe_day(int(offer["first_due_day"]))]
	EventBus.bank_changed.emit()
	EventBus.send_notice(EventBus.target_menu("bank"), message)
	return {"ok": true, "message": message}


## Rechaza el préstamo de emergencia: la nómina queda debida.
func reject_emergency() -> void:
	if emergency_offer.is_empty():
		return
	emergency_offer = {}
	EventBus.emergency_loan_resolved.emit(false)
	EventBus.bank_changed.emit()


## «día 1 del mes N» para un día absoluto (GameClock.get_day_count).
static func describe_day(day_count: int) -> String:
	@warning_ignore("integer_division")
	return "día %d del mes %d" % [day_count % GameConstants.DAYS_PER_MONTH + 1, day_count / GameConstants.DAYS_PER_MONTH + 1]


func _on_payroll_short(shortfall: int, response: Dictionary) -> void:
	if not emergency_offer.is_empty() or not can_offer_emergency() or shortfall <= 0:
		return
	emergency_offer = make_emergency_offer(shortfall)
	response["held"] = true
	EventBus.emergency_loan_offered.emit(emergency_offer)


## Estadísticas para la pantalla de fin.
func get_game_over_stats(debt: int, value: int) -> Dictionary:
	return {"days": GameClock.get_day_count() + 1, "hired": Staff.hired_count, "delivered": Projects.delivered_count,
		"best_reputation": Projects.best_reputation, "debt": debt, "assets": value}


func _on_day_changed(day: int, month: int) -> void:
	if day != 1 or game_over:
		return
	_charge_installments()
	_charge_investor(month - 1)
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
		EventBus.send_notice(EventBus.target_menu("bank"), "La calificación de crédito %s a %s." % ["sube" if up else "baja", rating])
	EventBus.bank_changed.emit()


## Devuelve el estado del banco para guardarlo.
func export_state() -> Dictionary:
	return {"rating": rating, "score": score, "monthly_income": monthly_income,
		"on_time_payments": on_time_payments, "late_payments": late_payments,
		"loans": loans.duplicate(true), "next_loan_id": _next_loan_id, "overdue_months": overdue_months,
		"emergency_offer": emergency_offer.duplicate(), "investor": investor.duplicate()}


## Restaura el banco; sin datos de calificación la calcula con lo que hay.
func import_state(state: Dictionary) -> void:
	monthly_income = int(state.get("monthly_income", 0))
	on_time_payments = int(state.get("on_time_payments", 0))
	late_payments = int(state.get("late_payments", 0))
	loans.clear()
	for saved: Dictionary in state.get("loans", []):
		loans.append({"id": int(saved["id"]), "amount": int(saved["amount"]), "base": int(saved.get("base", saved["amount"])),
			"rate": float(saved["rate"]), "months": int(saved["months"]), "paid": int(saved.get("paid", 0)),
			"refinanced": bool(saved.get("refinanced", false)), "taken_day": int(saved.get("taken_day", 0)),
			"overdue": int(saved.get("overdue", 0)), "emergency": bool(saved.get("emergency", false)),
			"first_due_day": int(saved.get("first_due_day", 0))})
	_next_loan_id = int(state.get("next_loan_id", loans.size() + 1))
	overdue_months = int(state.get("overdue_months", 0))
	game_over = false
	emergency_offer = {}
	var offer: Dictionary = state.get("emergency_offer", {})
	if offer.has("amount"):
		emergency_offer = {"amount": int(offer["amount"]), "shortfall": int(offer.get("shortfall", offer["amount"])),
			"rate": float(offer["rate"]), "months": int(offer["months"]), "installment": int(offer["installment"]),
			"total": int(offer["total"]), "first_due_day": int(offer.get("first_due_day", 0))}
	investor = {}
	var saved_investor: Dictionary = state.get("investor", {})
	if saved_investor.has("cash"):
		investor = {"cash": int(saved_investor["cash"]), "share": float(saved_investor["share"]),
			"months": int(saved_investor["months"]), "paid_months": int(saved_investor.get("paid_months", 0)),
			"paid_total": int(saved_investor.get("paid_total", 0)), "income_before": int(saved_investor.get("income_before", 0)),
			"day": int(saved_investor.get("day", 0))}
	if state.has("rating"):
		rating = String(state["rating"])
		score = int(state.get("score", compute_score()))
	else:
		_recalculate(false)
	EventBus.bank_changed.emit()


# Se leen al usarlos: sirven aunque llamen a Bank antes de su _ready.
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
