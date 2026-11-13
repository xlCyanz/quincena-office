# Eventos (diseño 10 y 19.2; hitos 43 y 44): situaciones que llegan como una tarjeta con un
# texto corto y opciones. Cada hora de juego que pasa con el reloj andando y sin otra tarjeta
# abierta se sortea si llega uno (en promedio uno cada mean_days días según la etapa) entre
# los que cumplen sus condiciones (data/events.json), por su peso y sus modificadores. El
# jugador tiene answer_seconds segundos reales para elegir, que solo corren con el reloj
# andando (a cualquier velocidad; en pausa o en construcción la cuenta se detiene); si no
# elige, se toma una opción al azar. Los efectos llaman a las funciones públicas de los
# otros sistemas y todo pago pasa por Economy.
#
# La tarjeta abierta (card) es {"event_id", "title", "text", "options": [{"label",
# "effects"}], "target", "seconds_left"}. target guarda sobre qué cae el evento (un
# contrato, un producto, un equipo, un empleado, un monto), elegido al abrirla; los efectos
# que dependen de él ya llevan su monto calculado. scheduled son los pagos que un cliente
# atrasado devuelve más tarde: [{"day", "amount"}].
#
# Solo sortea con el reloj de una partida corriendo (GameClock.start, que hace la escena de
# juego): las pruebas que adelantan el reloj con fast_forward_hours y el reloj detenido no
# reciben eventos.
extends Node

const EVENTS_PATH: String = "res://data/events.json"
const CONCEPT_EVENT: String = "Evento"
const CONCEPT_WITHHELD: String = "Pago retenido"
const CONCEPT_LATE_PAYMENT: String = "Pago atrasado"

## Tarjeta abierta, o vacía.
var card: Dictionary = {}
## Pagos retenidos por devolver: [{"day", "amount"}].
var scheduled: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _data: Dictionary = {}


func _ready() -> void:
	EventBus.hour_changed.connect(func(_hour: int) -> void: _roll())
	EventBus.day_changed.connect(func(_day: int, _month: int) -> void: _pay_scheduled())


func _process(delta: float) -> void:
	if not card.is_empty() and _clock_running():
		advance_countdown(delta)


## Prepara una partida nueva: sin tarjeta abierta ni pagos pendientes.
func new_game() -> void:
	card = {}
	scheduled.clear()
	_rng.randomize()
	EventBus.event_changed.emit()


## Fija la semilla del azar (las pruebas la usan para tener resultados repetibles).
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Promedio de días entre eventos en la etapa actual.
func get_mean_days() -> float:
	var means: Array = _events_data()["mean_days"]
	return float(means[clampi(Company.stage, 0, means.size() - 1)])


## Probabilidad de que llegue un evento al pasar una hora.
func get_hourly_chance() -> float:
	return 1.0 / (get_mean_days() * GameConstants.HOURS_PER_DAY)


## Ids de los eventos que pueden salir ahora (cumplen sus condiciones y tienen sobre qué caer).
func get_eligible_ids() -> Array[String]:
	var ids: Array[String] = []
	for event: Dictionary in _events_data()["events"]:
		if _meets(event.get("conditions", {})) and not _available_options(event).is_empty() \
				and _find_target(String(event.get("target", "")), event.get("target_args", {})) != null:
			ids.append(String(event["id"]))
	return ids


## Peso de un evento ahora: su weight por los factores de los weight_if que se cumplen.
func get_weight(event_id: String) -> float:
	var event: Dictionary = _get_event(event_id)
	var weight: float = float(event.get("weight", 1.0))
	for modifier: Dictionary in event.get("weight_if", []):
		if _meets(modifier.get("conditions", {})):
			weight *= float(modifier.get("factor", 1.0))
	return weight


## Abre la tarjeta de ese evento si puede salir ahora (y no hay otra abierta). Lo usan el
## sorteo, las pruebas y la consola de desarrollo. Devuelve si se abrió.
func trigger(event_id: String) -> bool:
	if not card.is_empty() or not get_eligible_ids().has(event_id):
		return false
	var event: Dictionary = _get_event(event_id)
	var found: Variant = _find_target(String(event.get("target", "")), event.get("target_args", {}))
	var target: Dictionary = found if found is Dictionary else {}
	var options: Array[Dictionary] = []
	for option: Dictionary in _available_options(event):
		var effects: Array[Dictionary] = []
		for effect: Dictionary in option.get("effects", []):
			var resolved: Dictionary = _resolve(effect, target)
			if not resolved.is_empty():
				effects.append(resolved)
		options.append({"label": String(option["label"]), "effects": effects})
	card = {"event_id": event_id, "title": String(event["title"]), "text": _fill(String(event["text"]), target),
		"options": options, "target": target, "seconds_left": float(_events_data()["answer_seconds"])}
	EventBus.event_changed.emit()
	EventBus.event_started.emit(card)
	return true


## Elige una opción de la tarjeta abierta: aplica sus efectos y la cierra. Devuelve el
## texto del resultado ("" si no había tarjeta o la opción no existe).
func choose(index: int, by_timeout: bool = false) -> String:
	if card.is_empty() or index < 0 or index >= (card["options"] as Array).size():
		return ""
	var option: Dictionary = card["options"][index]
	var title: String = card["title"]
	var target: Dictionary = card["target"]
	card = {}
	var results: Array[String] = []
	for effect: Dictionary in option["effects"]:
		var result: String = _apply(effect, target, title)
		if not result.is_empty():
			results.append(result)
	var message: String = "%s%s: %s%s" % ["Se acabó el tiempo. " if by_timeout else "", title, option["label"],
		"" if results.is_empty() else " (%s)" % ", ".join(PackedStringArray(results))]
	EventBus.event_changed.emit()
	EventBus.notice.emit(message + ".")
	return message


## Descuenta segundos reales de la cuenta atrás; al llegar a 0 elige una opción al azar.
## Lo llama _process con el reloj andando; las pruebas lo usan para no esperar.
func advance_countdown(seconds: float) -> void:
	if card.is_empty():
		return
	card["seconds_left"] = float(card["seconds_left"]) - seconds
	if float(card["seconds_left"]) <= 0.0:
		choose(_rng.randi_range(0, (card["options"] as Array).size() - 1), true)


## "1:45": lo que queda para elegir.
func describe_countdown() -> String:
	var seconds: int = ceili(maxf(0.0, float(card.get("seconds_left", 0.0))))
	return "%d:%02d" % [seconds / 60, seconds % 60]


## Lo que hace una opción, para el jugador: "−$150, ánimo +8".
static func describe_effects(effects: Array) -> String:
	var parts: Array[String] = []
	for effect: Dictionary in effects:
		var text: String = describe_effect(effect)
		if not text.is_empty():
			parts.append(text)
	return ", ".join(PackedStringArray(parts))


static func describe_effect(effect: Dictionary) -> String:
	var names: Dictionary = {"mood": "ánimo", "energy": "energía", "stress": "estrés"}
	match String(effect["type"]):
		"money":
			var amount: int = int(effect["amount"])
			return ("+" if amount > 0 else "") + MoneyFormat.format(amount)
		"mood", "energy", "stress":
			return "%s %s%d" % [names[effect["type"]], "+" if int(effect["amount"]) > 0 else "−", absi(int(effect["amount"]))]
		"mood_some":
			return "ánimo −%d a %d %s" % [absi(int(effect["amount"])), int(effect["count"]),
				"persona" if int(effect["count"]) == 1 else "personas"]
		"reputation":
			return "reputación %s%s" % ["+" if float(effect["amount"]) > 0.0 else "−", String.num(absf(float(effect["amount"])), 1)]
		"offer":
			return "una oferta con %d %% más de pago" % roundi((float(effect["pay_factor"]) - 1.0) * 100.0)
		"lose_work":
			var hours: int = int(effect["hours"])
			match String(effect["scope"]):
				"ceo":
					return "el CEO pierde %d horas" % hours
				"target_team":
					return "el equipo pierde %d horas" % hours
			return "se pierden %d horas de trabajo en todos los proyectos" % hours
		"product_loss":
			return "%s %d %% de los usuarios" % ["pierde" if String(effect["scope"]) == "target" else "los productos pierden",
				roundi(float(effect["amount"]) * 100.0)]
		"contract_change":
			var parts: Array[String] = ["%+d %% de trabajo" % roundi((float(effect["points_factor"]) - 1.0) * 100.0)]
			if not is_equal_approx(float(effect.get("pay_factor", 1.0)), 1.0):
				parts.append("%+d %% de pago" % roundi((float(effect["pay_factor"]) - 1.0) * 100.0))
			if int(effect.get("extra_days", 0)) > 0:
				parts.append("+%d días" % int(effect["extra_days"]))
			return ", ".join(PackedStringArray(parts))
		"withhold":
			return "te devuelven %s en %d días" % [MoneyFormat.format(int(effect["amount"])), int(effect["days"])]
		"clean_all":
			return "limpia toda la oficina"
		"coffee_out":
			return "los adictos al café rinden menos hoy"
		"break_toilet":
			return "un inodoro deja de funcionar hasta repararlo (%s en Empresa)" % MoneyFormat.format(int(StaffCatalog.get_bathrooms("repair_cost")))
	return ""


func export_state() -> Dictionary:
	return {"card": card.duplicate(true), "scheduled": scheduled.duplicate(true), "rng_state": str(_rng.state)}


## Restaura la tarjeta abierta y los pagos pendientes de una partida guardada. Sin datos
## (partidas anteriores al hito 43) queda sin tarjeta.
func import_state(state: Dictionary) -> void:
	card = {}
	var saved: Variant = state.get("card", {})
	if saved is Dictionary and not (saved as Dictionary).is_empty() and not _get_event(String(saved.get("event_id", ""))).is_empty():
		var options: Array[Dictionary] = []
		for option: Dictionary in saved.get("options", []):
			options.append(option.duplicate(true))
		var target: Dictionary = {}
		var saved_target: Variant = saved.get("target", {})
		if saved_target is Dictionary:
			for key: String in saved_target:
				# JSON guarda los números como float: los ids vuelven a int.
				var value: Variant = saved_target[key]
				target[key] = int(value) if value is float and key != "amount_ratio" else value
		if not options.is_empty():
			card = {"event_id": String(saved["event_id"]), "title": String(saved.get("title", "")), "text": String(saved.get("text", "")),
				"options": options, "target": target, "seconds_left": float(saved.get("seconds_left", _events_data()["answer_seconds"]))}
	scheduled.clear()
	for payment: Dictionary in state.get("scheduled", []):
		scheduled.append({"day": int(payment.get("day", 0)), "amount": int(payment.get("amount", 0))})
	var rng_state: String = String(state.get("rng_state", ""))
	if rng_state.is_valid_int():
		_rng.state = rng_state.to_int()
	EventBus.event_changed.emit()


# Al pasar una hora con el reloj de la partida andando: quizá llega un evento.
func _roll() -> void:
	if not card.is_empty() or not _clock_running() or Bank.game_over:
		return
	if _rng.randf() >= get_hourly_chance():
		return
	var eligible: Array[String] = get_eligible_ids()
	if eligible.is_empty():
		return
	var total: float = 0.0
	for event_id: String in eligible:
		total += get_weight(event_id)
	var pick: float = _rng.randf() * total
	for event_id: String in eligible:
		pick -= get_weight(event_id)
		if pick <= 0.0:
			trigger(event_id)
			return
	trigger(eligible[-1])


# El reloj de una partida corre (la escena de juego lo arrancó) y no está en pausa.
func _clock_running() -> bool:
	return GameClock.is_processing() and not GameClock.is_paused


# Cada día: devuelve los pagos retenidos que vencen.
func _pay_scheduled() -> void:
	var today: int = GameClock.get_day_count()
	var due: Array[Dictionary] = scheduled.filter(func(payment: Dictionary) -> bool: return int(payment["day"]) <= today)
	for payment: Dictionary in due:
		scheduled.erase(payment)
		Economy.earn(int(payment["amount"]), CONCEPT_LATE_PAYMENT)
		EventBus.notice.emit("El cliente pagó lo que retenía: %s." % MoneyFormat.format(int(payment["amount"])))


func _meets(conditions: Dictionary) -> bool:
	if Staff.employees.size() < int(conditions.get("min_employees", 0)):
		return false
	if Company.stage < int(conditions.get("min_stage", 0)):
		return false
	if Projects.reputation < float(conditions.get("min_reputation", 0.0)):
		return false
	if bool(conditions.get("offer_room", false)) and not Projects.has_offer_room():
		return false
	if conditions.has("has_role") and not _has_role(String(conditions["has_role"])):
		return false
	if conditions.has("no_role") and _has_role(String(conditions["no_role"])):
		return false
	if conditions.has("no_furniture") and OfficeState.has_furniture(String(conditions["no_furniture"])):
		return false
	if conditions.has("working_room") and not Projects.has_working_room(String(conditions["working_room"])):
		return false
	if bool(conditions.get("launched_product", false)) and Products.get_launched().is_empty():
		return false
	if bool(conditions.get("tired", false)) and not _is_tired():
		return false
	return true


func _has_role(role: String) -> bool:
	return Staff.employees.any(func(employee: Dictionary) -> bool: return employee["role"] == role)


# La energía media de los empleados está baja.
func _is_tired() -> bool:
	if Staff.employees.is_empty():
		return false
	var total: float = 0.0
	for employee: Dictionary in Staff.employees:
		total += float(employee["energy"])
	return total / Staff.employees.size() < float(_events_data().get("tired_below", 50))


func _available_options(event: Dictionary) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for option: Dictionary in event.get("options", []):
		if _meets(option.get("conditions", {})):
			options.append(option)
	return options


# Sobre qué cae un evento: un diccionario, {} si no necesita nada, o null si no hay sobre qué
# caer (entonces no puede salir).
func _find_target(kind: String, args: Dictionary) -> Variant:
	match kind:
		"":
			return {}
		"employee":
			if Staff.employees.is_empty():
				return null
			var picked: Dictionary = Staff.employees[_rng.randi_range(0, Staff.employees.size() - 1)]
			return {"employee_id": picked["id"], "employee": picked["name"]}
		"two_employees":
			if Staff.employees.size() < 2:
				return null
			var pool: Array[Dictionary] = Staff.employees.duplicate()
			var first: Dictionary = pool.pop_at(_rng.randi_range(0, pool.size() - 1))
			var second: Dictionary = pool.pop_at(_rng.randi_range(0, pool.size() - 1))
			return {"employee_ids": [first["id"], second["id"]], "employee": first["name"], "employee2": second["name"]}
		"product":
			var launched: Array[Dictionary] = Products.get_launched()
			if launched.is_empty():
				return null
			var product: Dictionary = launched[_rng.randi_range(0, launched.size() - 1)]
			return {"product_id": product["id"], "product": product["name"]}
		"contract":
			var open: Array[Dictionary] = Projects.contracts.filter(func(contract: Dictionary) -> bool:
				return not Production.is_finished(contract))
			if open.is_empty():
				return null
			var contract: Dictionary = open[_rng.randi_range(0, open.size() - 1)]
			return {"contract_id": contract["id"], "client": contract["client"]}
		"weak_leader_team":
			var teams: Array[Dictionary] = []
			for team: Dictionary in Staff.teams:
				if not (team["members"] as Array).is_empty() and not _has_good_leader(team):
					teams.append(team)
			if teams.is_empty():
				return null
			var chosen: Dictionary = teams[_rng.randi_range(0, teams.size() - 1)]
			return {"team_id": chosen["id"], "team": chosen["name"]}
		"programmer_team":
			for team: Dictionary in Staff.teams:
				for member: Variant in team["members"]:
					if Staff.get_employee(int(member)).get("role", "") == "programmer":
						return {"team_id": team["id"], "team": team["name"]}
			return {"team_id": Projects.CEO_TEAM, "team": "el CEO"}
		"computer":
			var users: Array[Dictionary] = []
			for employee: Dictionary in Staff.employees:
				var computer: String = Workstations.computer_of(OfficeState.furniture, Staff.employee_key(employee["id"]))
				if not computer.is_empty():
					users.append({"employee_id": employee["id"], "employee": employee["name"], "computer": computer})
			if users.is_empty():
				return null
			var user: Dictionary = users[_rng.randi_range(0, users.size() - 1)]
			var team: Dictionary = Staff.get_team_of(int(user["employee_id"]))
			user["team_id"] = Projects.NO_TEAM if team.is_empty() else int(team["id"])
			return user
		"delivery":
			var today: int = GameClock.get_day_count()
			for entry: Dictionary in Projects.history:
				if String(entry["result"]).begins_with("Entregado") and int(entry["paid"]) > 0 \
						and today - int(entry["day"]) <= int(args.get("within_days", 7)):
					return {"amount": roundi(int(entry["paid"]) * float(args.get("ratio", 0.3))), "client": String(entry["title"])}
			return null
		"tax":
			# Ingresos de contratos del mes pasado (los préstamos no son ingreso).
			var income: int = 0
			var totals: Dictionary[String, int] = Economy.get_month_totals(Economy.get_current_month() - 1)
			for concept: String in Bank.get_income_concepts():
				income += maxi(0, totals.get(concept, 0))
			var fine: int = maxi(int(args.get("min_fine", 500)), roundi(income * float(args.get("ratio", 0.1))))
			if OfficeState.has_furniture(String(args.get("halved_by", ""))):
				fine = roundi(fine / 2.0)
			return {"amount": fine}
	push_error("Objetivo de evento desconocido: %s" % kind)
	return null


func _has_good_leader(team: Dictionary) -> bool:
	var leader: Dictionary = Staff.get_employee(int(team.get("leader_id", 0)))
	if leader.is_empty():
		return false
	return float(leader.get("skills", {}).get("leadership", 0.0)) >= float(_events_data().get("good_leader_from", 60))


# Pone los datos del objetivo en el texto: {employee}, {employee2}, {product}, {client},
# {team}, {amount}.
func _fill(text: String, target: Dictionary) -> String:
	var result: String = text
	for key: String in ["employee", "employee2", "product", "client", "team"]:
		result = result.replace("{%s}" % key, String(target.get(key, "")))
	if target.has("amount"):
		result = result.replace("{amount}", MoneyFormat.format(int(target["amount"])))
	return result


# Calcula al abrir la tarjeta lo que depende del momento: el costo de las horas extra, la
# multa, el precio de la computadora o lo retenido. Devuelve {} si no hace nada.
func _resolve(effect: Dictionary, target: Dictionary) -> Dictionary:
	var resolved: Dictionary = effect.duplicate(true)
	match String(effect["type"]):
		"overtime":
			var cost: float = 0.0
			for employee: Dictionary in Staff.employees:
				if not Production.get_role_phase(employee["role"]).is_empty():
					cost += float(employee["salary"]) / GameConstants.DAYS_PER_MONTH / 8.0 * float(effect.get("factor", 1.5)) * int(effect["hours"])
			return {"type": "money", "amount": -roundi(cost)} if roundi(cost) > 0 else {}
		"fine":
			return {"type": "money", "amount": -int(target.get("amount", 0))}
		"replace_computer":
			return {"type": "money", "amount": -FurnitureCatalog.get_price(String(target.get("computer", "")))}
		"withhold":
			resolved["amount"] = int(target.get("amount", 0))
	return resolved


# Aplica un efecto y devuelve el texto de lo que pasó ("" si no hizo nada).
func _apply(effect: Dictionary, target: Dictionary, title: String) -> String:
	match String(effect["type"]):
		"money":
			var amount: int = int(effect["amount"])
			if amount >= 0:
				Economy.earn(amount, CONCEPT_EVENT)
			else:
				Economy.charge(-amount, CONCEPT_EVENT)
			return ("+" if amount > 0 else "") + MoneyFormat.format(amount)
		"mood", "energy", "stress":
			if Staff.employees.is_empty():
				return ""
			Staff.change_all(String(effect["type"]), int(effect["amount"]))
			return describe_effect(effect)
		"mood_some":
			var ids: Array[int] = []
			for value: Variant in target.get("employee_ids", []):
				ids.append(int(value))
			if ids.is_empty():
				return ""
			Staff.change_all("mood", int(effect["amount"]), ids)
			return describe_effect(effect)
		"reputation":
			return Projects.add_reputation(float(effect["amount"])).trim_suffix(".")
		"offer":
			var offer: Dictionary = Projects.create_bonus_offer(float(effect["pay_factor"]))
			if offer.is_empty():
				return ""
			return "llegó una oferta de %s por %s" % [offer["client"], MoneyFormat.format(int(offer["pay"]))]
		"lose_work":
			var lost: float = 0.0
			for project: Dictionary in _projects_in_scope(String(effect["scope"]), target):
				lost += Projects.remove_work(project, Projects.get_nominal_rate(project) * int(effect["hours"]))
			EventBus.projects_changed.emit()
			EventBus.products_changed.emit()
			return "se perdieron %d puntos de trabajo" % roundi(lost)
		"product_loss":
			var amount: float = float(effect["amount"])
			if String(effect["scope"]) == "target":
				Products.add_user_loss(int(target.get("product_id", 0)), amount)
			else:
				for product: Dictionary in Products.get_launched():
					Products.add_user_loss(int(product["id"]), amount)
			return describe_effect(effect)
		"contract_change":
			Projects.change_scope(int(target.get("contract_id", 0)), float(effect["points_factor"]),
				float(effect.get("pay_factor", 1.0)), int(effect.get("extra_days", 0)))
			return describe_effect(effect)
		"withhold":
			var withheld: int = int(effect["amount"])
			Economy.charge(withheld, CONCEPT_WITHHELD)
			scheduled.append({"day": GameClock.get_day_count() + int(effect["days"]), "amount": withheld})
			return describe_effect(effect)
		"clean_all":
			OfficeState.clean_all()
			return describe_effect(effect)
		"coffee_out":
			Staff.run_out_of_coffee()
			return describe_effect(effect)
		"break_toilet":
			return describe_effect(effect) if Staff.break_toilet() else ""
	push_error("Efecto de evento desconocido en %s: %s" % [title, effect])
	return ""


# Proyectos en curso (contratos y de productos) que alcanza un efecto: los del CEO, los del
# equipo del objetivo o todos.
func _projects_in_scope(scope: String, target: Dictionary) -> Array[Dictionary]:
	var all: Array[Dictionary] = Projects.contracts.duplicate()
	all.append_array(Products.get_active_projects())
	match scope:
		"ceo":
			return all.filter(func(project: Dictionary) -> bool: return int(project["team_id"]) == Projects.CEO_TEAM)
		"target_team":
			var team_id: int = int(target.get("team_id", Projects.NO_TEAM))
			if team_id == Projects.NO_TEAM:
				return []
			return all.filter(func(project: Dictionary) -> bool: return int(project["team_id"]) == team_id)
	return all


func _get_event(event_id: String) -> Dictionary:
	for event: Dictionary in _events_data()["events"]:
		if String(event["id"]) == event_id:
			return event
	return {}


func _events_data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_PATH))
		if not parsed is Dictionary:
			push_error("No se pudo leer %s" % EVENTS_PATH)
			return {"events": [], "mean_days": [5], "answer_seconds": 120}
		_data = parsed
	return _data
