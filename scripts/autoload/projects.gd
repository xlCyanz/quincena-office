# Proyectos: la bandeja de ofertas, las visitas de clientes y los contratos en curso, con su
# producción por hora, errores, entrega o cancelación y la reputación. Un equipo (o el CEO) lleva
# un proyecto a la vez; el tope es equipos + 1. Todo el azar sale de _rng (se guarda).
extends Node

const CONCEPT_ADVANCE: String = "Anticipo de contrato"
const CONCEPT_DELIVERY: String = "Pago de contrato"
const CONCEPT_REFUND: String = "Devolución de anticipo"
## cancel_day de un contrato que todavía no se atrasó.
const NO_CANCEL_DAY: int = -1
## team_id de un contrato que lleva el CEO trabajando solo.
const CEO_TEAM: int = 0
## team_id de un contrato que no lleva nadie.
const NO_TEAM: int = -1
## Contadores de errores de un contrato.
const BUG_KEYS: Array[String] = ["bugs_hidden", "bugs_found", "bugs_fixed"]

var offers: Array[Dictionary] = []
## Clientes esperando en la Recepción con su oferta.
var visits: Array[Dictionary] = []
var contracts: Array[Dictionary] = []
## Reputación de la empresa, de 1 a 5 estrellas.
var reputation: float = 1.0
## Últimas entregas y cancelaciones: {"title", "result", "paid", "reputation_change", "day"}.
var history: Array[Dictionary] = []
## Contratos entregados en toda la partida.
var delivered_count: int = 0
## Contratos aceptados en toda la partida (para los objetivos).
var accepted_count: int = 0
## La mejor reputación que tuvo la empresa (para la pantalla de fin).
var best_reputation: float = 1.0
## Ya llegó una oferta que exige Sala de reuniones: desde entonces se puede construir.
var meeting_room_unlocked: bool = false

var _next_id: int = 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.staff_changed.connect(_drop_missing_teams)


## Prepara una partida nueva: sin contratos, reputación inicial y una oferta pequeña.
func new_game() -> void:
	offers.clear()
	visits.clear()
	contracts.clear()
	history.clear()
	delivered_count = 0
	accepted_count = 0
	meeting_room_unlocked = false
	reputation = float(ContractCatalog.get_offers("start_reputation"))
	best_reputation = reputation
	_next_id = 1
	_rng.randomize()
	offers.append(_make_offer(GameClock.get_day_count(), "small"))
	EventBus.projects_changed.emit()
	EventBus.rooms_unlocked.emit()


# Partidas viejas: algo ya usa la Sala de reuniones.
func _meeting_room_in_use() -> bool:
	for room: Dictionary in OfficeState.rooms:
		if RoomCatalog.is_unlocked_by_offer(room["type"]):
			return true
	for project: Dictionary in offers + contracts:
		if not ContractCatalog.get_required_room(String(project.get("size", ""))).is_empty():
			return true
	return false


## Fija la semilla del azar (pruebas).
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Tope de proyectos en curso (contratos y productos): uno por equipo con miembros y uno del CEO.
func get_contract_limit() -> int:
	return get_team_count() + 1


## Proyectos en curso: contratos más productos en desarrollo (comparten el tope).
func get_project_count() -> int:
	return contracts.size() + Products.get_development_count()


## Por qué no se puede empezar otro proyecto ("" si se puede).
func limit_problem() -> String:
	var count: int = get_project_count()
	var limit: int = get_contract_limit()
	if count < limit:
		return ""
	return "Ya tienes %d %s en curso y el tope es %d: uno por equipo con miembros más el del CEO." % [
		count, "proyecto" if count == 1 else "proyectos", limit]


## Equipos de la empresa que tienen al menos un miembro.
func get_team_count() -> int:
	return Staff.get_active_team_count()


## Tamaños de contrato que pueden llegar ahora según la reputación, la etapa y los vendedores.
func get_allowed_sizes() -> Array[String]:
	var sizes: Array[String] = []
	var sellers: int = get_salesperson_count()
	for size: String in ContractCatalog.get_size_ids():
		var info: Dictionary = ContractCatalog.get_size(size)
		var earned: bool = reputation >= float(info.get("min_reputation", 0)) and Company.stage + 1 >= int(info.get("min_stage", 1))
		if earned or (bool(info.get("with_salesperson", false)) and sellers > 0):
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
	var limit_text: String = limit_problem()
	if not limit_text.is_empty():
		return limit_text
	var room: String = String(ContractCatalog.get_size(offer["size"]).get("requires_room", ""))
	if not room.is_empty() and not _has_working_room(room):
		return "Un contrato %s exige una %s que funcione." % [ContractCatalog.get_size_name(offer["size"]).to_lower(),
			RoomCatalog.get_display_name(room)]
	return ""


## Acepta una oferta y cobra el anticipo si tiene. Devuelve {"ok", "message"}.
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
	contract["progress"] = {"design": 0.0, "programming": 0.0, "testing": 0.0}
	for key: String in BUG_KEYS:
		contract[key] = 0
	contract["fix_progress"] = 0.0
	contract["cancel_day"] = NO_CANCEL_DAY
	contract["team_id"] = first_free_team()
	contract["worked_by"] = []
	contracts.append(contract)
	accepted_count += 1
	EventBus.contract_accepted.emit()
	var message: String = "Contrato aceptado: %s para %s, %d días; %s." % [
		ContractCatalog.get_type_name(offer["type"]), offer["client"], offer["days"], describe_owner(contract)]
	if int(offer["advance"]) > 0:
		Economy.earn(int(offer["advance"]), CONCEPT_ADVANCE)
		message += " Anticipo cobrado: %s." % MoneyFormat.format(offer["advance"])
	EventBus.projects_changed.emit()
	EventBus.send_notice(EventBus.target_contract(int(contract["id"])), message)
	return {"ok": true, "message": message}


## Rechaza una oferta (desaparece de la bandeja). Devuelve false si no existe.
func reject(offer_id: int) -> bool:
	var offer: Dictionary = get_offer(offer_id)
	if offer.is_empty():
		return false
	offers.erase(offer)
	EventBus.projects_changed.emit()
	return true


## Parte del trabajo hecha (0 a 1), sumando las tres fases.
static func get_done_ratio(contract: Dictionary) -> float:
	var total: float = 0.0
	var done: float = 0.0
	for phase: String in ContractCatalog.PHASES:
		total += float(contract["points"][phase])
		done += minf(float(contract["progress"][phase]), float(contract["points"][phase]))
	return 1.0 if total <= 0.0 else clampf(done / total, 0.0, 1.0)


## Errores que le llegarían al cliente: los ocultos y los encontrados sin corregir.
static func get_delivered_bugs(contract: Dictionary) -> int:
	return int(contract["bugs_hidden"]) + int(contract["bugs_found"])


## Días de atraso de un contrato hoy (0 si va a tiempo).
func get_days_late(contract: Dictionary) -> int:
	return maxi(0, -contract_days_left(contract))


## Qué pasaría si se entrega hoy: {"done", "late_days", "bugs", "late_penalty", "bug_penalty",
## "gross", "paid", "reputation_change", "result"}; paid = gross − anticipo (mín. 0).
## known_only cuenta solo los errores que conoce el jugador; la entrega real suma los ocultos.
func preview_delivery(contract: Dictionary, known_only: bool = false) -> Dictionary:
	var done: float = get_done_ratio(contract)
	var late_days: int = get_days_late(contract)
	var bugs: int = int(contract["bugs_found"]) if known_only else get_delivered_bugs(contract)
	var late_penalty: float = minf(late_days * float(ContractCatalog.get_offers("late_penalty_per_day")),
		float(ContractCatalog.get_offers("late_penalty_max")))
	var bug_penalty: float = minf(bugs * float(ContractCatalog.get_offers("bug_penalty_each")),
		float(ContractCatalog.get_offers("bug_penalty_max")))
	var gross: int = roundi(int(contract["pay"]) * done * maxf(0.0, 1.0 - late_penalty - bug_penalty))
	var change: float = 0.0
	var result: String
	var complete: bool = done >= 1.0 - Production.EPSILON
	if complete and bugs == 0 and late_days == 0:
		change = float(ContractCatalog.get_delivery("clean_reputation"))
		result = "a tiempo y limpio"
	else:
		change = maxf(bugs * float(ContractCatalog.get_delivery("bug_reputation"))
			+ late_days * float(ContractCatalog.get_delivery("late_reputation")),
			float(ContractCatalog.get_delivery("max_reputation_loss")))
		var parts: Array[String] = []
		parts.append("tarde (%d %s)" % [late_days, "día" if late_days == 1 else "días"] if late_days > 0 else "a tiempo")
		if bugs > 0:
			parts.append("con %d %s" % [bugs, "error" if bugs == 1 else "errores"])
		if not complete:
			parts.append("incompleto (%d%%)" % floori(done * 100.0 + Production.EPSILON))
		result = ", ".join(parts)
	return {"done": done, "late_days": late_days, "bugs": bugs, "late_penalty": late_penalty, "bug_penalty": bug_penalty,
		"gross": gross, "paid": maxi(0, gross - int(contract["advance"])), "reputation_change": change, "result": result}


## Entrega un contrato: cobra lo que falta con penalidades y mueve la reputación.
func deliver(contract_id: int) -> Dictionary:
	var contract: Dictionary = get_contract(contract_id)
	if contract.is_empty():
		return {"ok": false, "message": "Ese contrato ya no está."}
	var preview: Dictionary = preview_delivery(contract)
	contracts.erase(contract)
	if int(preview["paid"]) > 0:
		Economy.earn(int(preview["paid"]), CONCEPT_DELIVERY)
	delivered_count += 1
	EventBus.contract_delivered.emit((contract.get("worked_by", []) as Array).duplicate())
	var message: String = "Entregaste %s %s: cobras %s. %s" % [describe_title(contract), preview["result"],
		MoneyFormat.format(preview["paid"]), _change_reputation(float(preview["reputation_change"]))]
	_finish(contract, "Entregado " + String(preview["result"]), int(preview["paid"]), float(preview["reputation_change"]), message)
	return {"ok": true, "message": message}


## Cancela un contrato: devuelve el anticipo (aunque deje saldo negativo) y baja la reputación.
func cancel(contract_id: int) -> Dictionary:
	var contract: Dictionary = get_contract(contract_id)
	if contract.is_empty():
		return {"ok": false, "message": "Ese contrato ya no está."}
	contracts.erase(contract)
	var advance: int = int(contract["advance"])
	if advance > 0:
		Economy.charge(advance, CONCEPT_REFUND)
	var change: float = float(ContractCatalog.get_delivery("cancel_reputation"))
	var message: String = "Cancelaste %s%s. %s" % [describe_title(contract),
		": devuelves el anticipo de %s" % MoneyFormat.format(advance) if advance > 0 else "",
		_change_reputation(change)]
	_finish(contract, "Cancelado por la empresa", -advance, change, message)
	return {"ok": true, "message": message}


## Le da un contrato a un equipo, al CEO o a nadie (NO_TEAM); lo que llevaba ese equipo queda
## sin equipo. Devuelve {"ok", "message"}.
func assign(contract_id: int, team_id: int) -> Dictionary:
	var contract: Dictionary = get_contract(contract_id)
	if contract.is_empty():
		return {"ok": false, "message": "Ese contrato ya no está."}
	if team_id > CEO_TEAM and Staff.get_team(team_id).is_empty():
		return {"ok": false, "message": "Ese equipo ya no está."}
	if team_id != NO_TEAM:
		var previous: Dictionary = get_contract_of(team_id)
		if not previous.is_empty() and previous["id"] != contract_id:
			previous["team_id"] = NO_TEAM
		# Un equipo lleva un proyecto a la vez.
		Products.release_team(team_id)
	contract["team_id"] = team_id
	EventBus.projects_changed.emit()
	return {"ok": true, "message": "%s: %s." % [describe_title(contract), describe_owner(contract)]}


## Contrato que lleva un equipo (o el CEO con CEO_TEAM), o vacío.
func get_contract_of(team_id: int) -> Dictionary:
	if team_id == NO_TEAM:
		return {}
	for contract: Dictionary in contracts:
		if int(contract["team_id"]) == team_id:
			return contract
	return {}


## "lo lleva el CEO", "lo lleva Equipo 1" o "sin equipo".
func describe_owner(contract: Dictionary) -> String:
	var team_id: int = int(contract.get("team_id", NO_TEAM))
	if team_id == CEO_TEAM:
		return "lo lleva el CEO"
	var team: Dictionary = Staff.get_team(team_id)
	return "sin equipo" if team.is_empty() else "lo lleva %s" % team["name"]


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


## Días que le quedan a una oferta (se va a la hora de llegada de ese día).
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
	return "Plazo %d días · Pago %s · %s · Atraso −%d%% por día (máx. %d%%) · errores −%d%% c/u (máx. %d%%)" % [offer["days"],
		MoneyFormat.format(offer["pay"]), advance,
		roundi(float(ContractCatalog.get_offers("late_penalty_per_day")) * 100.0),
		roundi(float(ContractCatalog.get_offers("late_penalty_max")) * 100.0),
		roundi(float(ContractCatalog.get_offers("bug_penalty_each")) * 100.0),
		roundi(float(ContractCatalog.get_offers("bug_penalty_max")) * 100.0)]


func _on_hour_changed(hour: int) -> void:
	_produce()
	_update_visits()
	if hour == int(ContractCatalog.get_offers("arrival_hour")):
		_check_late_contracts(GameClock.get_day_count())
		_process_arrivals(GameClock.get_day_count())


# Primero caducan las ofertas viejas; después llegan las nuevas.
func _process_arrivals(today: int) -> void:
	var staying: Array[Dictionary] = []
	for offer: Dictionary in offers:
		if today < int(offer["expires_day"]):
			staying.append(offer)
	offers = staying
	var max_offers: int = int(ContractCatalog.get_offers("max_offers"))
	var visited: bool = false
	for i: int in range(_roll_arrivals()):
		if offers.size() + visits.size() >= max_offers:
			break
		var offer: Dictionary = _make_offer(today)
		if visits_enabled() and _rng.randf() < float(ContractCatalog.get_visits("chance")):
			_add_visit(offer)
			visited = true
		else:
			offers.append(offer)
	EventBus.projects_changed.emit()
	if visited:
		EventBus.visits_changed.emit()


## Indica si pueden venir clientes: desde visits.min_stage y con una Recepción que funciona.
func visits_enabled() -> bool:
	return Company.stage >= int(ContractCatalog.get_visits("min_stage")) and _has_working_room(Workstations.RECEPTION)


## Horas que espera un cliente: más si la Recepción tiene un sofá de espera.
func get_visit_wait_hours() -> int:
	return int(ContractCatalog.get_visits("sofa_wait_hours" if not get_waiting_seats().is_empty() else "wait_hours"))


## Casillas de los sofás de espera de una Recepción que funciona.
func get_waiting_seats() -> Array[Vector2i]:
	var seats: Array[Vector2i] = []
	var room_cells: Array = _reception_cells()
	for item: Dictionary in OfficeState.furniture:
		if not bool(FurnitureCatalog.get_item(item["id"]).get("waiting_seat", false)):
			continue
		for cell: Vector2i in FurnitureCatalog.get_footprint(item["id"], item["cell"], item["rotation"]):
			if room_cells.has(cell):
				seats.append(cell)
	return seats


## Dónde esperan los clientes: sofás primero y después casillas libres de la Recepción.
func get_waiting_spots() -> Array[Vector2i]:
	var spots: Array[Vector2i] = get_waiting_seats()
	var used: Array[Vector2i] = OfficeState.get_blocking_cells()
	for cell: Vector2i in _reception_cells():
		if not used.has(cell) and cell != OfficeState.entrance:
			spots.append(cell)
	return spots


func _reception_cells() -> Array:
	for room: Dictionary in OfficeState.rooms:
		if room["type"] == Workstations.RECEPTION and RoomRules.function_problems(room, OfficeState.furniture).is_empty():
			return room["cells"]
	return []


func _add_visit(offer: Dictionary) -> void:
	var now: int = Staff.get_absolute_hour()
	var wait: int = get_visit_wait_hours()
	visits.append({"id": offer["id"], "offer": offer, "arrived_at": now, "leaves_at": now + wait})
	EventBus.send_notice(EventBus.target_menu("projects"), "Llegó un cliente de %s a la Recepción: espera hasta las %d:00." % [offer["client"],
		posmod(now + wait, GameConstants.HOURS_PER_DAY)])


# Al terminar cada hora: con recepcionista en su puesto las visitas dejan su oferta; sin él,
# las que ya esperaron todo su tiempo se van.
func _update_visits() -> void:
	if visits.is_empty():
		return
	var now: int = Staff.get_absolute_hour()
	var ended: int = now - 1
	var attended: bool = Staff.is_reception_attended(Staff.get_weekday_at(ended), posmod(ended, GameConstants.HOURS_PER_DAY))
	var staying: Array[Dictionary] = []
	for visit: Dictionary in visits:
		var offer: Dictionary = visit["offer"]
		if int(visit["arrived_at"]) > ended:
			staying.append(visit)
		elif attended:
			offers.append(offer)
			EventBus.send_notice(EventBus.target_menu("projects"), "Atendieron al cliente de %s: su oferta está en Proyectos." % offer["client"])
		elif now >= int(visit["leaves_at"]):
			EventBus.send_notice(EventBus.target_menu("projects"), "El cliente de %s se fue sin que nadie lo atendiera: perdiste su oferta." % offer["client"])
		else:
			staying.append(visit)
	if staying.size() == visits.size():
		return
	visits = staying
	EventBus.projects_changed.emit()
	EventBus.visits_changed.emit()


## Ofertas por día en promedio: la base más lo de cada vendedor según cómo rinde Ventas.
func get_offer_chance() -> float:
	return float(ContractCatalog.get_offers("chance")) \
		+ float(ContractCatalog.get_offers("chance_per_salesperson")) * get_salesperson_count() \
		* Staff.get_department_factor(StaffCatalog.get_role_department(Staff.SALES_ROLE))


# Cuántas ofertas llegan hoy: la parte entera es segura y la decimal, una tirada.
func _roll_arrivals() -> int:
	var chance: float = get_offer_chance()
	var count: int = floori(chance)
	if _rng.randf() < chance - count:
		count += 1
	return count


## Indica si cabe una oferta más en la bandeja (las visitas también cuentan).
func has_offer_room() -> bool:
	return offers.size() + visits.size() < int(ContractCatalog.get_offers("max_offers"))


## Una oferta de tamaño sorteado con el pago × pay_factor (eventos). Vacía si la bandeja está llena.
func create_bonus_offer(pay_factor: float) -> Dictionary:
	if not has_offer_room():
		return {}
	var offer: Dictionary = _make_offer(GameClock.get_day_count())
	var step: int = int(ContractCatalog.get_offers("pay_step"))
	offer["pay"] = roundi(int(offer["pay"]) * pay_factor / step) * step
	if int(offer["advance"]) > 0:
		offer["advance"] = roundi(int(offer["pay"]) * float(ContractCatalog.get_offers("advance_ratio")))
	offers.append(offer)
	EventBus.projects_changed.emit()
	return offer


func create_offer(size: String) -> Dictionary:
	var offer: Dictionary = _make_offer(GameClock.get_day_count(), size)
	offers.append(offer)
	EventBus.projects_changed.emit()
	return offer


func _make_offer(today: int, forced_size: String = "") -> Dictionary:
	var size: String = forced_size if not forced_size.is_empty() else _pick_size()
	var types: Array[String] = ContractCatalog.get_type_ids()
	var type_id: String = types[_rng.randi_range(0, types.size() - 1)]
	var points_range: Vector2i = ContractCatalog.get_size_range(size, "points")
	var total: int = _rng.randi_range(points_range.x, points_range.y)
	var split: Array[int] = ContractCatalog.get_split(type_id)
	var design: int = roundi(total * split[0] / 100.0)
	var programming: int = roundi(total * split[1] / 100.0)
	var days: Vector2i = ContractCatalog.get_days_range(size, total)
	# El pago crece con el trabajo dentro de su rango, con algo de azar.
	var pay_range: Vector2i = ContractCatalog.get_size_range(size, "pay")
	var ratio: float = float(total - points_range.x) / maxf(1.0, points_range.y - points_range.x)
	var variation: float = float(ContractCatalog.get_offers("pay_variation"))
	var step: int = int(ContractCatalog.get_offers("pay_step"))
	var raw_pay: float = lerpf(pay_range.x, pay_range.y, ratio) * (1.0 + _rng.randf_range(-variation, variation))
	var pay: int = clampi(roundi(raw_pay / step) * step, pay_range.x, pay_range.y)
	var advance: int = 0
	if _rng.randf() < float(ContractCatalog.get_offers("advance_chance")):
		advance = roundi(pay * float(ContractCatalog.get_offers("advance_ratio")))
	var clients: Array[String] = ContractCatalog.get_elite_clients() if ContractCatalog.is_elite(size) else ContractCatalog.get_clients()
	_unlock_room_for(size)
	var offer: Dictionary = {
		"id": _take_id(), "client": clients[_rng.randi_range(0, clients.size() - 1)], "type": type_id,
		"size": size, "points": {"design": design, "programming": programming, "testing": total - design - programming},
		"total_points": total, "days": _offer_days(size, _rng.randi_range(days.x, days.y)), "pay": pay, "advance": advance,
		"arrived_day": today, "expires_day": today + int(ContractCatalog.get_offers("expire_days")),
	}
	return offer


# Elige un tamaño entre los permitidos según su peso.
func _pick_size() -> String:
	var sizes: Array[String] = get_allowed_sizes()
	var total: float = 0.0
	var whole: bool = true
	for size: String in sizes:
		total += get_size_weight(size)
		whole = whole and is_equal_approx(get_size_weight(size), roundf(get_size_weight(size)))
	# Con pesos enteros se sortea un entero para no cambiar el azar de partidas y simulaciones.
	var roll: float = (_rng.randi_range(1, roundi(total)) - 0.5) if whole else _rng.randf() * total
	for size: String in sizes:
		roll -= get_size_weight(size)
		if roll < 0.0:
			return size
	return sizes[sizes.size() - 1]


## Peso de un tamaño entre las ofertas: × pantalla de presentaciones si exige Sala de reuniones.
func get_size_weight(size: String) -> float:
	var weight: float = float(ContractCatalog.get_size(size)["weight"])
	var room: String = ContractCatalog.get_required_room(size)
	if not room.is_empty() and has_presentation_screen(room):
		weight *= float(ContractCatalog.get_meetings("screen_weight_factor"))
	return weight


# Plazo de una oferta: con pizarra en la Sala de reuniones, los tamaños que la exigen traen
# 10 % más, hacia arriba.
func _offer_days(size: String, days: int) -> int:
	var room: String = ContractCatalog.get_required_room(size)
	if room.is_empty() or not has_room_item(room, "meeting_board"):
		return days
	return ceili(days * float(ContractCatalog.get_meetings("board_days_factor")))


## Indica si una habitación de ese tipo que funciona tiene un mueble con ese campo (p. ej. "meeting_board").
func has_room_item(room_type: String, field: String) -> bool:
	for room: Dictionary in OfficeState.rooms:
		if room["type"] != room_type or not RoomRules.function_problems(room, OfficeState.furniture).is_empty():
			continue
		for item: Dictionary in OfficeState.furniture:
			if FurnitureCatalog.get_number(item["id"], field) > 0.0 and (room["cells"] as Array).has(item["cell"]):
				return true
	return false


## Indica si hay una pantalla de presentaciones en una habitación de ese tipo que funciona.
func has_presentation_screen(room_type: String) -> bool:
	return has_room_item(room_type, "presentation_screen")


# La primera oferta de un tamaño que exige Sala de reuniones la deja construir.
func _unlock_room_for(size: String) -> void:
	var room: String = ContractCatalog.get_required_room(size)
	if room.is_empty() or not RoomCatalog.is_unlocked_by_offer(room) or meeting_room_unlocked:
		return
	meeting_room_unlocked = true
	EventBus.send_notice(EventBus.target_menu("projects"), "Llegó la primera oferta %s: ya puedes construir una %s (con mesa de reuniones) para aceptarla." % [
		ContractCatalog.get_size_name(size).to_lower(), RoomCatalog.get_display_name(room)])
	EventBus.rooms_unlocked.emit()


## Indica si hay una habitación de ese tipo que funciona.
func has_working_room(room_type: String) -> bool:
	return _has_working_room(room_type)


## Puntos por hora de un proyecto con todo su equipo presente y en forma (eventos que quitan horas).
func get_nominal_rate(project: Dictionary) -> float:
	var team_id: int = int(project.get("team_id", NO_TEAM))
	if team_id == CEO_TEAM:
		return Production.get_rate(String(StaffCatalog.get_production("ceo_level")), 100.0,
			Workstations.bonus_of(OfficeState.furniture, "ceo"))
	var team: Dictionary = Staff.get_team(team_id)
	if team.is_empty():
		return 0.0
	var total: float = 0.0
	for member: Variant in team["members"]:
		var employee: Dictionary = Staff.get_employee(int(member))
		if employee.is_empty() or Production.get_role_phase(employee["role"]).is_empty():
			continue
		total += Production.get_rate(employee["level"], 100.0,
			Workstations.bonus_of(OfficeState.furniture, Staff.employee_key(int(member))))
	return total


## Quita puntos hechos de un proyecto, de la última fase hacia atrás, sin bajar de 0. Devuelve lo quitado.
static func remove_work(project: Dictionary, points: float) -> float:
	var left: float = points
	var phases: Array[String] = ContractCatalog.PHASES.duplicate()
	phases.reverse()
	for phase: String in phases:
		var take: float = minf(float(project["progress"][phase]), left)
		project["progress"][phase] = float(project["progress"][phase]) - take
		left -= take
	return points - left


## Cambia el trabajo, el pago y el plazo de un contrato en curso (evento).
func change_scope(contract_id: int, points_factor: float, pay_factor: float, extra_days: int) -> void:
	var contract: Dictionary = get_contract(contract_id)
	if contract.is_empty():
		return
	var total: int = 0
	for phase: String in ContractCatalog.PHASES:
		contract["points"][phase] = roundi(int(contract["points"][phase]) * points_factor)
		total += int(contract["points"][phase])
	contract["total_points"] = total
	var step: int = int(ContractCatalog.get_offers("pay_step"))
	contract["pay"] = roundi(int(contract["pay"]) * pay_factor / step) * step
	contract["days"] = int(contract["days"]) + extra_days
	contract["deadline_day"] = int(contract["deadline_day"]) + extra_days
	EventBus.projects_changed.emit()


func _has_working_room(room_type: String) -> bool:
	for room: Dictionary in OfficeState.rooms:
		if room["type"] == room_type and RoomRules.function_problems(room, OfficeState.furniture).is_empty():
			return true
	return false


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


## Estado para guardar. El azar va como texto: JSON perdería precisión.
func export_state() -> Dictionary:
	return {"offers": offers.duplicate(true), "contracts": contracts.duplicate(true), "reputation": reputation,
		"history": history.duplicate(true), "delivered_count": delivered_count, "accepted_count": accepted_count, "best_reputation": best_reputation,
		"next_id": _next_id, "rng_state": str(_rng.state), "visits": visits.duplicate(true),
		"meeting_room_unlocked": meeting_room_unlocked}


## Restaura los proyectos de una partida guardada; sin datos queda sin ofertas ni contratos.
func import_state(state: Dictionary) -> void:
	offers.clear()
	for saved: Dictionary in state.get("offers", []):
		offers.append(_import_offer(saved))
	# Partidas viejas sin visitas.
	visits.clear()
	for saved: Dictionary in state.get("visits", []):
		if not saved.has("offer"):
			continue
		var offer: Dictionary = _import_offer(saved["offer"])
		visits.append({"id": offer["id"], "offer": offer, "arrived_at": int(saved.get("arrived_at", 0)),
			"leaves_at": int(saved.get("leaves_at", 0))})
	contracts.clear()
	for saved: Dictionary in state.get("contracts", []):
		var contract: Dictionary = _import_offer(saved)
		contract["accepted_day"] = int(saved.get("accepted_day", 0))
		contract["deadline_day"] = int(saved.get("deadline_day", contract["accepted_day"] + contract["days"]))
		var progress: Dictionary = {}
		for phase: String in ContractCatalog.PHASES:
			progress[phase] = float(saved.get("progress", {}).get(phase, 0.0))
		contract["progress"] = progress
		for key: String in BUG_KEYS:
			contract[key] = int(saved.get(key, 0))
		contract["fix_progress"] = float(saved.get("fix_progress", 0.0))
		contract["cancel_day"] = int(saved.get("cancel_day", NO_CANCEL_DAY))
		# Partidas viejas sin quién trabajó.
		var worked_by: Array = []
		for key: Variant in saved.get("worked_by", []):
			worked_by.append(String(key))
		contract["worked_by"] = worked_by
		# Partidas viejas: un solo contrato, el del CEO.
		var team_id: int = int(saved.get("team_id", CEO_TEAM))
		contract["team_id"] = team_id if team_id <= CEO_TEAM or not Staff.get_team(team_id).is_empty() else NO_TEAM
		contracts.append(contract)
	reputation = float(state.get("reputation", ContractCatalog.get_offers("start_reputation")))
	best_reputation = maxf(float(state.get("best_reputation", reputation)), reputation)
	history.clear()
	for saved: Dictionary in state.get("history", []):
		history.append({"title": String(saved.get("title", "")), "result": String(saved.get("result", "")),
			"paid": int(saved.get("paid", 0)), "reputation_change": float(saved.get("reputation_change", 0.0)),
			"day": int(saved.get("day", 0))})
	delivered_count = int(state.get("delivered_count", 0))
	# Partidas viejas: al menos los que están en curso o en el historial.
	accepted_count = int(state.get("accepted_count", contracts.size() + history.size()))
	# Partidas viejas: se habilita si ya hay una Sala de reuniones o algo que la exige.
	meeting_room_unlocked = bool(state.get("meeting_room_unlocked", false)) or _meeting_room_in_use()
	EventBus.rooms_unlocked.emit()
	_next_id = int(state.get("next_id", 1))
	var rng_state: String = String(state.get("rng_state", ""))
	if rng_state.is_valid_int():
		_rng.state = rng_state.to_int()
	else:
		_rng.randomize()
	EventBus.projects_changed.emit()
	EventBus.visits_changed.emit()


## Quienes trabajan en un contrato en una hora absoluta: {"key", "phase" ("" generalista), "level",
## "rate", "bug_chance"} y "find_factor" en empleados. shared guarda lo común a todos los contratos
## de esa hora para no recalcularlo; vacío = calcular todo.
func get_workers(contract: Dictionary, at: int, shared: Dictionary = {}) -> Array[Dictionary]:
	var weekday: int = Staff.get_weekday_at(at)
	var hour: int = posmod(at, GameConstants.HOURS_PER_DAY)
	var workers: Array[Dictionary] = []
	var team_id: int = int(contract["team_id"])
	# Por cada inodoro que falta baja la producción de todos.
	if not shared.has("bathroom"):
		shared["bathroom"] = Staff.get_bathroom_factor(Staff.get_bathroom_shortage(at))
	var bathroom: float = shared["bathroom"]
	# Quien almuerza en la Sala de descanso trabaja media hora.
	if not shared.has("lunch"):
		shared["lunch"] = Staff.get_lunch_inside(at)
	var lunch: Dictionary[String, bool] = shared["lunch"]
	# Quien descansa no suma; el ping pong distrae a todos.
	if not shared.has("breaks"):
		shared["breaks"] = Staff.get_breaks(at)
		shared["distraction"] = OfficeState.get_break_room_effect("distraction")
	var on_break: Array[String] = shared["breaks"]
	var focus: float = 1.0 - float(shared["distraction"])
	var lunch_factor: float = StaffCatalog.get_lunch("work_factor")
	if team_id == CEO_TEAM:
		var ceo_lunch: bool = lunch.has("ceo")
		if Staff.is_ceo_producing(at) or ceo_lunch:
			var ceo_bonus: float = Workstations.bonus_of(OfficeState.furniture, "ceo")
			var ceo_level: String = String(StaffCatalog.get_production("ceo_level"))
			# La entrevista le quita media hora.
			var interview_factor: float = 1.0 if ceo_lunch else Staff.get_ceo_interview_factor(at)
			workers.append({"key": "ceo", "phase": "", "level": ceo_level, "rate": (lunch_factor if ceo_lunch else interview_factor) * bathroom * Production.get_rate(ceo_level, 100.0,
				ceo_bonus), "bug_chance": get_bug_chance(ceo_level, 100.0)})
		return workers
	var team: Dictionary = Staff.get_team(team_id)
	if team.is_empty():
		return workers
	# Desde Startup, sin su líder presente el equipo rinde menos.
	var factor: float = Staff.get_team_factor(team, at)
	if not shared.has("stations"):
		shared["stations"] = Staff.get_working_station_keys()
		shared["bonuses"] = Workstations.bonuses_by_owner(OfficeState.furniture)
		shared["departments"] = {}
		shared["coffee"] = Staff.has_coffee()
	var stations: Dictionary = shared["stations"]
	var bonuses: Dictionary = shared["bonuses"]
	var departments: Dictionary = shared["departments"]
	var mentored: Dictionary[int, float] = Staff.get_team_mentor_factors(team, weekday, hour)
	for member: Variant in team["members"]:
		var employee: Dictionary = Staff.get_employee(int(member))
		var key: String = Staff.employee_key(int(member))
		var phase: String = Production.get_role_phase(employee["role"])
		var eating: bool = lunch.has(key)
		if phase.is_empty() or not (eating or Staff.is_expected(key, weekday, hour)) or not stations.has(key) or on_break.has(key):
			continue
		var department_id: String = StaffCatalog.get_role_department(employee["role"])
		if not departments.has(department_id):
			departments[department_id] = Staff.get_department_factor(department_id)
		var department: float = departments[department_id]
		# Rasgos: puntos según la hora, mentor, errores al programar y al probar.
		var traits: float = Staff.get_trait_points_factor(employee, hour, bool(shared["coffee"])) * mentored.get(int(member), 1.0)
		workers.append({"key": key, "phase": phase, "level": employee["level"], "rate": factor * department * traits * bathroom * focus * (lunch_factor if eating else 1.0)
			* Production.get_rate(employee["level"], float(employee["energy"]), bonuses.get(key, 0.0), float(employee["mood"])),
			"bug_chance": get_bug_chance(employee["level"], float(employee["energy"]), float(employee["stress"]))
			* Staff.get_trait_bug_factor(employee), "find_factor": Staff.get_trait_find_factor(employee)})
	return workers


## Errores por punto de programación: el doble cansado o estresado (no se acumula).
static func get_bug_chance(level: String, energy: float, stress: float = 0.0) -> float:
	var chance: float = 1.0 / ContractCatalog.get_points_per_bug(level)
	if energy < float(ContractCatalog.get_bugs("tired_below")) or stress >= float(ContractCatalog.get_bugs("stressed_from")):
		chance *= float(ContractCatalog.get_bugs("tired_multiplier"))
	return chance


## "Errores: 3 encontrados · 1 por corregir · 2 corregidos" (los ocultos no se ven).
static func describe_bugs(contract: Dictionary) -> String:
	var found: int = int(contract.get("bugs_found", 0))
	var fixed: int = int(contract.get("bugs_fixed", 0))
	if found + fixed == 0:
		return "Errores: ninguno encontrado"
	return "Errores: %d encontrados · %d por corregir · %d corregidos" % [found + fixed, found, fixed]


## Puntos por hora de un contrato ahora, con quienes deberían trabajar (sin topes de fase).
func get_hourly_rate(contract: Dictionary) -> float:
	var total: float = 0.0
	for worker: Dictionary in get_workers(contract, Staff.get_absolute_hour()):
		total += float(worker["rate"])
	return total


# Suma la hora que acaba de terminar a cada contrato en curso.
func _produce() -> void:
	var ended: int = Staff.get_absolute_hour() - 1
	var changed: bool = false
	var shared: Dictionary = {}
	for contract: Dictionary in contracts:
		var workers: Array[Dictionary] = get_workers(contract, ended, shared)
		if workers.is_empty():
			continue
		var was_finished: bool = Production.is_finished(contract)
		var done: Array[Dictionary] = Production.apply(contract, workers)
		Production.handle_bugs(contract, done, _rng)
		Production.note_workers(contract, done)
		Staff.note_bugs_caused(done)
		changed = true
		if not was_finished and Production.is_finished(contract):
			EventBus.send_notice(EventBus.target_contract(int(contract["id"])), "Terminado: %s. Listo para entregar." % describe_title(contract))
	if changed:
		EventBus.projects_changed.emit()


# A la hora de llegada: a cada contrato recién atrasado se le sortea cuántos días aguanta el
# cliente; al llegar a ellos, lo cancela.
func _check_late_contracts(today: int) -> void:
	var limits: Array = ContractCatalog.get_delivery("client_cancel_days")
	for contract: Dictionary in contracts.duplicate():
		if get_days_late(contract) <= 0:
			continue
		if int(contract["cancel_day"]) == NO_CANCEL_DAY:
			contract["cancel_day"] = int(contract["deadline_day"]) + _rng.randi_range(int(limits[0]), int(limits[1]))
			EventBus.send_notice(EventBus.target_contract(int(contract["id"])), "%s está atrasado: el cliente puede cancelarlo en cualquier momento." % describe_title(contract))
		if today >= int(contract["cancel_day"]):
			_client_cancel(contract)
	EventBus.projects_changed.emit()


# El cliente cancela: se lleva el contrato sin pagar más (el anticipo queda).
func _client_cancel(contract: Dictionary) -> void:
	contracts.erase(contract)
	var change: float = float(ContractCatalog.get_delivery("cancel_reputation"))
	var message: String = "%s canceló %s por el atraso: no paga nada más. %s" % [contract["client"],
		describe_title(contract), _change_reputation(change)]
	_finish(contract, "Cancelado por el cliente", 0, change, message)


## Suma (o resta) reputación desde otro sistema; devuelve el texto, como «Reputación +0.1.».
func add_reputation(change: float) -> String:
	var text: String = _change_reputation(change)
	EventBus.projects_changed.emit()
	return text


func _change_reputation(change: float) -> String:
	var before: float = reputation
	reputation = clampf(reputation + change, float(ContractCatalog.get_delivery("min_reputation")),
		float(ContractCatalog.get_delivery("max_reputation")))
	var applied: float = reputation - before
	best_reputation = maxf(best_reputation, reputation)
	if absf(applied) < Production.EPSILON:
		return "La reputación no cambia."
	return "Reputación %s%s." % ["+" if applied > 0.0 else "−", String.num(absf(applied), 2)]


# Anota el resultado en el historial y avisa.
func _finish(contract: Dictionary, result: String, paid: int, change: float, message: String) -> void:
	history.push_front({"title": describe_title(contract), "result": result, "paid": paid,
		"reputation_change": change, "day": GameClock.get_day_count()})
	history.resize(mini(history.size(), int(ContractCatalog.get_delivery("history_size"))))
	EventBus.projects_changed.emit()
	EventBus.send_notice(EventBus.target_menu("projects"), message)


## Quién lleva un proyecto nuevo: el primer equipo con miembros libre, si no el CEO libre, si no nadie.
func first_free_team() -> int:
	for team: Dictionary in Staff.teams:
		if not (team["members"] as Array).is_empty() and is_team_free(team["id"]):
			return team["id"]
	return CEO_TEAM if is_team_free(CEO_TEAM) else NO_TEAM


## Indica si un equipo (o el CEO) no lleva ningún contrato ni producto.
func is_team_free(team_id: int) -> bool:
	return get_contract_of(team_id).is_empty() and Products.get_product_of(team_id).is_empty()


## Suelta el contrato que lleva un equipo (Products lo llama al darle un producto).
func release_team(team_id: int) -> void:
	var contract: Dictionary = get_contract_of(team_id)
	if not contract.is_empty():
		contract["team_id"] = NO_TEAM
		EventBus.projects_changed.emit()


# Los contratos de un equipo que se borró quedan sin equipo.
func _drop_missing_teams() -> void:
	var changed: bool = false
	for contract: Dictionary in contracts:
		var team_id: int = int(contract["team_id"])
		if team_id > CEO_TEAM and Staff.get_team(team_id).is_empty():
			contract["team_id"] = NO_TEAM
			changed = true
	if changed:
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
