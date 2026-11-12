# Proyectos (diseño, 7.1 y 13.4): la bandeja de ofertas de contratos y los contratos
# aceptados. La producción (hito 16), los errores (17) y la entrega (18) llegan después.
#
# Cada día, a la hora de llegada (data/contracts.json, offers.arrival_hour), primero
# caducan las ofertas viejas y después pueden llegar nuevas: con probabilidad chance,
# más chance_per_salesperson por cada vendedor. Qué tamaños llegan depende de la
# reputación (y de tener vendedores). La primera partida empieza con una oferta pequeña.
# Todo el azar sale de _rng, cuyo estado se guarda con la partida.
#
# Una oferta es {"id", "client", "type", "size", "points": {"design", "programming",
# "testing"}, "total_points", "days", "pay", "advance", "arrived_day", "expires_day"}.
# advance es el anticipo (0 si no tiene) y los días se cuentan con GameClock.get_day_count.
# Un contrato es la oferta aceptada más "accepted_day", "deadline_day" y "progress"
# (puntos hechos de cada fase). Se pueden tener a la vez tantos contratos como equipos
# (uno mientras no haya equipos: el CEO).
extends Node

const CONCEPT_ADVANCE: String = "Anticipo de contrato"

var offers: Array[Dictionary] = []
var contracts: Array[Dictionary] = []
## Reputación de la empresa, de 1 a 5 estrellas (se mueve con las entregas, hito 18).
var reputation: float = 1.0

var _next_id: int = 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.hour_changed.connect(_on_hour_changed)


## Prepara los proyectos de una partida nueva: sin contratos, con la reputación inicial
## y una primera oferta pequeña para no empezar sin trabajo.
func new_game() -> void:
	offers.clear()
	contracts.clear()
	reputation = float(ContractCatalog.get_offers("start_reputation"))
	_next_id = 1
	_rng.randomize()
	offers.append(_make_offer(GameClock.get_day_count(), "small"))
	EventBus.projects_changed.emit()


## Fija la semilla del azar (las pruebas la usan para tener resultados repetibles).
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Cuántos contratos se pueden tener en curso: uno por equipo, y uno (el CEO) mientras
## no haya equipos.
func get_contract_limit() -> int:
	return maxi(1, get_team_count())


## Equipos de la empresa (llegan en el hito 15).
func get_team_count() -> int:
	return 0


## Tamaños de contrato que pueden llegar ahora según la reputación y los vendedores.
func get_allowed_sizes() -> Array[String]:
	var sizes: Array[String] = []
	var sellers: int = get_salesperson_count()
	for size: String in ContractCatalog.get_size_ids():
		var info: Dictionary = ContractCatalog.get_size(size)
		if reputation >= float(info["min_reputation"]) or (bool(info.get("with_salesperson", false)) and sellers > 0):
			sizes.append(size)
	return sizes


## Vendedores contratados.
func get_salesperson_count() -> int:
	var count: int = 0
	for employee: Dictionary in Staff.employees:
		if employee["role"] == "salesperson":
			count += 1
	return count


## Por qué no se puede aceptar una oferta ahora ("" si se puede).
func accept_problem(offer_id: int) -> String:
	var offer: Dictionary = get_offer(offer_id)
	if offer.is_empty():
		return "Esa oferta ya no está."
	var limit: int = get_contract_limit()
	if contracts.size() >= limit:
		return "Ya tienes %d %s en curso y el tope es %d: uno por equipo (sin equipos, el del CEO)." % [
			contracts.size(), "contrato" if contracts.size() == 1 else "contratos", limit]
	var room: String = String(ContractCatalog.get_size(offer["size"]).get("requires_room", ""))
	if not room.is_empty() and not _has_working_room(room):
		return "Un contrato %s exige una %s que funcione." % [ContractCatalog.get_size_name(offer["size"]).to_lower(),
			RoomCatalog.get_display_name(room)]
	return ""


## Acepta una oferta: pasa a contratos en curso con su plazo y cobra el anticipo si
## tiene. Devuelve {"ok": bool, "message": String}.
func accept(offer_id: int) -> Dictionary:
	var problem: String = accept_problem(offer_id)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var offer: Dictionary = get_offer(offer_id)
	offers.erase(offer)
	var today: int = GameClock.get_day_count()
	var contract: Dictionary = offer.duplicate(true)
	contract["accepted_day"] = today
	contract["deadline_day"] = today + int(offer["days"])
	contract["progress"] = {"design": 0, "programming": 0, "testing": 0}
	contracts.append(contract)
	var message: String = "Contrato aceptado: %s para %s, %d días." % [
		ContractCatalog.get_type_name(offer["type"]), offer["client"], offer["days"]]
	if int(offer["advance"]) > 0:
		Economy.earn(int(offer["advance"]), CONCEPT_ADVANCE)
		message += " Anticipo cobrado: %s." % MoneyFormat.format(offer["advance"])
	EventBus.projects_changed.emit()
	EventBus.notice.emit(message)
	return {"ok": true, "message": message}


## Rechaza una oferta (desaparece de la bandeja). Devuelve false si no existe.
func reject(offer_id: int) -> bool:
	var offer: Dictionary = get_offer(offer_id)
	if offer.is_empty():
		return false
	offers.erase(offer)
	EventBus.projects_changed.emit()
	return true


func get_offer(offer_id: int) -> Dictionary:
	for offer: Dictionary in offers:
		if offer["id"] == offer_id:
			return offer
	return {}


func get_contract(contract_id: int) -> Dictionary:
	for contract: Dictionary in contracts:
		if contract["id"] == contract_id:
			return contract
	return {}


## Días que le quedan a una oferta en la bandeja (se va a la hora de llegada de ese día).
func offer_days_left(offer: Dictionary) -> int:
	return maxi(int(offer["expires_day"]) - GameClock.get_day_count(), 0)


## Días que faltan para el plazo de un contrato (negativo si está atrasado).
func contract_days_left(contract: Dictionary) -> int:
	return int(contract["deadline_day"]) - GameClock.get_day_count()


## "Sitio web · Pequeño · Panadería La Espiga".
static func describe_title(offer: Dictionary) -> String:
	return "%s · %s · %s" % [ContractCatalog.get_type_name(offer["type"]),
		ContractCatalog.get_size_name(offer["size"]), offer["client"]]


## "240 puntos: diseño 84 · programación 108 · pruebas 48".
static func describe_points(offer: Dictionary) -> String:
	var parts: Array[String] = []
	for phase: String in ContractCatalog.PHASES:
		parts.append("%s %d" % [ContractCatalog.PHASE_NAMES[phase], int(offer["points"][phase])])
	return "%d puntos: %s" % [offer["total_points"], " · ".join(parts)]


## "Plazo 9 días · Pago $1,900 · Anticipo 30%: $550 · Atraso −5% por día (máx. 50%)".
static func describe_terms(offer: Dictionary) -> String:
	var advance: String = "sin anticipo"
	if int(offer["advance"]) > 0:
		advance = "anticipo %d%%: %s" % [roundi(float(ContractCatalog.get_offers("advance_ratio")) * 100.0),
			MoneyFormat.format(offer["advance"])]
	return "Plazo %d días · Pago %s · %s · Atraso −%d%% por día (máx. %d%%)" % [offer["days"],
		MoneyFormat.format(offer["pay"]), advance,
		roundi(float(ContractCatalog.get_offers("late_penalty_per_day")) * 100.0),
		roundi(float(ContractCatalog.get_offers("late_penalty_max")) * 100.0)]


func _on_hour_changed(hour: int) -> void:
	if hour == int(ContractCatalog.get_offers("arrival_hour")):
		_process_arrivals(GameClock.get_day_count())


# Primero caducan las ofertas viejas; después llegan las nuevas.
func _process_arrivals(today: int) -> void:
	var staying: Array[Dictionary] = []
	for offer: Dictionary in offers:
		if today < int(offer["expires_day"]):
			staying.append(offer)
	offers = staying
	var max_offers: int = int(ContractCatalog.get_offers("max_offers"))
	for i: int in range(_roll_arrivals()):
		if offers.size() >= max_offers:
			break
		offers.append(_make_offer(today))
	EventBus.projects_changed.emit()


# Cuántas ofertas llegan hoy: la parte entera de la probabilidad es segura y la
# decimal es una tirada.
func _roll_arrivals() -> int:
	var chance: float = float(ContractCatalog.get_offers("chance")) \
		+ float(ContractCatalog.get_offers("chance_per_salesperson")) * get_salesperson_count()
	var count: int = floori(chance)
	if _rng.randf() < chance - count:
		count += 1
	return count


func _make_offer(today: int, forced_size: String = "") -> Dictionary:
	var size: String = forced_size if not forced_size.is_empty() else _pick_size()
	var types: Array[String] = ContractCatalog.get_type_ids()
	var type_id: String = types[_rng.randi_range(0, types.size() - 1)]
	var points_range: Vector2i = ContractCatalog.get_size_range(size, "points")
	var total: int = _rng.randi_range(points_range.x, points_range.y)
	var split: Array[int] = ContractCatalog.get_split(type_id)
	var design: int = roundi(total * split[0] / 100.0)
	var programming: int = roundi(total * split[1] / 100.0)
	var days: Vector2i = ContractCatalog.get_size_range(size, "days")
	# El pago crece con el trabajo dentro de su rango, con un poco de azar.
	var pay_range: Vector2i = ContractCatalog.get_size_range(size, "pay")
	var ratio: float = float(total - points_range.x) / maxf(1.0, points_range.y - points_range.x)
	var variation: float = float(ContractCatalog.get_offers("pay_variation"))
	var step: int = int(ContractCatalog.get_offers("pay_step"))
	var raw_pay: float = lerpf(pay_range.x, pay_range.y, ratio) * (1.0 + _rng.randf_range(-variation, variation))
	var pay: int = clampi(roundi(raw_pay / step) * step, pay_range.x, pay_range.y)
	var advance: int = 0
	if _rng.randf() < float(ContractCatalog.get_offers("advance_chance")):
		advance = roundi(pay * float(ContractCatalog.get_offers("advance_ratio")))
	var clients: Array[String] = ContractCatalog.get_clients()
	var offer: Dictionary = {
		"id": _take_id(), "client": clients[_rng.randi_range(0, clients.size() - 1)], "type": type_id,
		"size": size, "points": {"design": design, "programming": programming, "testing": total - design - programming},
		"total_points": total, "days": _rng.randi_range(days.x, days.y), "pay": pay, "advance": advance,
		"arrived_day": today, "expires_day": today + int(ContractCatalog.get_offers("expire_days")),
	}
	return offer


# Elige un tamaño entre los permitidos según su peso.
func _pick_size() -> String:
	var sizes: Array[String] = get_allowed_sizes()
	var total: int = 0
	for size: String in sizes:
		total += int(ContractCatalog.get_size(size)["weight"])
	var roll: int = _rng.randi_range(1, total)
	for size: String in sizes:
		roll -= int(ContractCatalog.get_size(size)["weight"])
		if roll <= 0:
			return size
	return sizes[0]


func _has_working_room(room_type: String) -> bool:
	for room: Dictionary in OfficeState.rooms:
		if room["type"] == room_type and RoomRules.function_problems(room, OfficeState.furniture).is_empty():
			return true
	return false


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


## Devuelve el estado de los proyectos para guardarlo. El estado del azar va como texto
## (JSON guarda los números como decimales y perdería precisión).
func export_state() -> Dictionary:
	return {"offers": offers.duplicate(true), "contracts": contracts.duplicate(true), "reputation": reputation,
		"next_id": _next_id, "rng_state": str(_rng.state)}


## Restaura los proyectos desde una partida guardada. Sin datos (partidas anteriores al
## hito 14) queda sin ofertas ni contratos y con la reputación inicial.
func import_state(state: Dictionary) -> void:
	offers.clear()
	for saved: Dictionary in state.get("offers", []):
		offers.append(_import_offer(saved))
	contracts.clear()
	for saved: Dictionary in state.get("contracts", []):
		var contract: Dictionary = _import_offer(saved)
		contract["accepted_day"] = int(saved.get("accepted_day", 0))
		contract["deadline_day"] = int(saved.get("deadline_day", contract["accepted_day"] + contract["days"]))
		var progress: Dictionary = {}
		for phase: String in ContractCatalog.PHASES:
			progress[phase] = int(saved.get("progress", {}).get(phase, 0))
		contract["progress"] = progress
		contracts.append(contract)
	reputation = float(state.get("reputation", ContractCatalog.get_offers("start_reputation")))
	_next_id = int(state.get("next_id", 1))
	var rng_state: String = String(state.get("rng_state", ""))
	if rng_state.is_valid_int():
		_rng.state = rng_state.to_int()
	else:
		_rng.randomize()
	EventBus.projects_changed.emit()


func _import_offer(saved: Dictionary) -> Dictionary:
	var points: Dictionary = {}
	for phase: String in ContractCatalog.PHASES:
		points[phase] = int(saved.get("points", {}).get(phase, 0))
	return {
		"id": int(saved["id"]), "client": String(saved["client"]), "type": String(saved["type"]),
		"size": String(saved["size"]), "points": points, "total_points": int(saved["total_points"]),
		"days": int(saved["days"]), "pay": int(saved["pay"]), "advance": int(saved.get("advance", 0)),
		"arrived_day": int(saved.get("arrived_day", 0)), "expires_day": int(saved.get("expires_day", 0)),
	}
