# Eventos (diseño 10 y 19.2; hito 43): situaciones que llegan como una tarjeta con un texto
# corto y opciones. Cada hora de juego que pasa con el reloj andando y sin otra tarjeta
# abierta se sortea si llega uno (en promedio uno cada mean_days días según la etapa) entre
# los que cumplen sus condiciones (data/events.json). El jugador tiene answer_seconds
# segundos reales para elegir, que solo corren con el reloj andando (a cualquier
# velocidad; en pausa o en construcción la cuenta se detiene); si no elige, se toma una
# opción al azar. Los efectos llaman a las funciones públicas de los otros sistemas y todo
# pago pasa por Economy.
#
# La tarjeta abierta (card) es {"event_id", "title", "text", "options": [{"label",
# "effects"}], "seconds_left"}. Solo sortea con el reloj de una partida corriendo
# (GameClock.start, que hace la escena de juego): las pruebas que adelantan el reloj con
# fast_forward_hours y el reloj detenido no reciben eventos.
extends Node

const EVENTS_PATH: String = "res://data/events.json"
const CONCEPT_EVENT: String = "Evento"

## Tarjeta abierta, o vacía.
var card: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _data: Dictionary = {}


func _ready() -> void:
	EventBus.hour_changed.connect(func(_hour: int) -> void: _roll())


func _process(delta: float) -> void:
	if not card.is_empty() and _clock_running():
		advance_countdown(delta)


## Prepara una partida nueva: sin tarjeta abierta.
func new_game() -> void:
	card = {}
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


## Ids de los eventos que pueden salir ahora (cumplen sus condiciones).
func get_eligible_ids() -> Array[String]:
	var ids: Array[String] = []
	for event: Dictionary in _events_data()["events"]:
		if _meets(event.get("conditions", {})):
			ids.append(String(event["id"]))
	return ids


## Abre la tarjeta de ese evento (si no hay otra abierta). Lo usan el sorteo, las pruebas y
## la consola de desarrollo. Devuelve si se abrió.
func trigger(event_id: String) -> bool:
	if not card.is_empty():
		return false
	var event: Dictionary = _get_event(event_id)
	if event.is_empty():
		return false
	var text: String = String(event["text"])
	if text.contains("{employee}"):
		var name: String = "alguien del equipo"
		if not Staff.employees.is_empty():
			name = String(Staff.employees[_rng.randi_range(0, Staff.employees.size() - 1)]["name"])
		text = text.replace("{employee}", name)
	var options: Array[Dictionary] = []
	for option: Dictionary in event["options"]:
		options.append({"label": String(option["label"]), "effects": (option.get("effects", []) as Array).duplicate(true)})
	card = {"event_id": event_id, "title": String(event["title"]), "text": text, "options": options,
		"seconds_left": float(_events_data()["answer_seconds"])}
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
	card = {}
	var results: Array[String] = []
	for effect: Dictionary in option["effects"]:
		var result: String = _apply(effect, title)
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
		match String(effect["type"]):
			"money":
				var amount: int = int(effect["amount"])
				parts.append(("+" if amount > 0 else "") + MoneyFormat.format(amount))
			"mood", "energy", "stress":
				var names: Dictionary = {"mood": "ánimo", "energy": "energía", "stress": "estrés"}
				parts.append("%s %s%d" % [names[effect["type"]], "+" if int(effect["amount"]) > 0 else "−", absi(int(effect["amount"]))])
			"reputation":
				parts.append("reputación %s%s" % ["+" if float(effect["amount"]) > 0.0 else "−", String.num(absf(float(effect["amount"])), 1)])
			"offer":
				parts.append("una oferta con %d %% más de pago" % roundi((float(effect["pay_factor"]) - 1.0) * 100.0))
	return ", ".join(PackedStringArray(parts))


func export_state() -> Dictionary:
	return {"card": card.duplicate(true), "rng_state": str(_rng.state)}


## Restaura la tarjeta abierta de una partida guardada. Sin datos (partidas anteriores al
## hito 43) queda sin tarjeta.
func import_state(state: Dictionary) -> void:
	card = {}
	var saved: Variant = state.get("card", {})
	if saved is Dictionary and not (saved as Dictionary).is_empty() and not _get_event(String(saved.get("event_id", ""))).is_empty():
		var options: Array[Dictionary] = []
		for option: Dictionary in saved.get("options", []):
			options.append(option.duplicate(true))
		card = {"event_id": String(saved["event_id"]), "title": String(saved.get("title", "")), "text": String(saved.get("text", "")),
			"options": options, "seconds_left": float(saved.get("seconds_left", _events_data()["answer_seconds"]))}
		if options.is_empty():
			card = {}
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
		total += float(_get_event(event_id).get("weight", 1.0))
	var pick: float = _rng.randf() * total
	for event_id: String in eligible:
		pick -= float(_get_event(event_id).get("weight", 1.0))
		if pick <= 0.0:
			trigger(event_id)
			return
	trigger(eligible[-1])


# El reloj de una partida corre (la escena de juego lo arrancó) y no está en pausa.
func _clock_running() -> bool:
	return GameClock.is_processing() and not GameClock.is_paused


func _meets(conditions: Dictionary) -> bool:
	if Staff.employees.size() < int(conditions.get("min_employees", 0)):
		return false
	if Company.stage < int(conditions.get("min_stage", 0)):
		return false
	if Projects.reputation < float(conditions.get("min_reputation", 0.0)):
		return false
	if bool(conditions.get("offer_room", false)) and not Projects.has_offer_room():
		return false
	return true


# Aplica un efecto y devuelve el texto de lo que pasó ("" si no hizo nada).
func _apply(effect: Dictionary, title: String) -> String:
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
			return describe_effects([effect])
		"reputation":
			return Projects.add_reputation(float(effect["amount"])).trim_suffix(".")
		"offer":
			var offer: Dictionary = Projects.create_bonus_offer(float(effect["pay_factor"]))
			if offer.is_empty():
				return ""
			return "llegó una oferta de %s por %s" % [offer["client"], MoneyFormat.format(int(offer["pay"]))]
	push_error("Efecto de evento desconocido en %s: %s" % [title, effect])
	return ""


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
