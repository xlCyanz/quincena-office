# Eventos: no salen en pausa ni construyendo; sin elegir se toma una opción al azar a los
# 2 minutos reales a cualquier velocidad; la frecuencia sube con la empresa.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=events
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261143

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []
var _started: int = 0


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	EventBus.event_started.connect(func(_card: Dictionary) -> void: _started += 1)
	_check_data()
	_check_conditions()
	_check_choose()
	_check_countdown()
	_check_rolls()
	_check_save()
	await _check_ui()
	GameClock.stop()
	GameClock.set_paused(false)
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	GameClock.stop()
	GameClock.set_paused(false)
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	Events.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(50000, "Prueba")


func _add_employee(employee_id: int, name: String) -> void:
	Staff.employees.append({"id": employee_id, "name": name, "role": "programmer", "level": "junior", "salary": 0,
		"schedule": StaffCatalog.get_role_schedule("programmer"), "energy": 80, "mood": 60, "stress": 20, "paid_until": 0, "owed": 0})


func _check_data() -> void:
	_new_game()
	_expect(Events.card.is_empty(), "partida nueva sin tarjeta")
	_expect(is_equal_approx(Events.get_mean_days(), 5.0), "Emprendimiento: uno cada 5 días")
	_expect(is_equal_approx(Events.get_hourly_chance(), 1.0 / 120.0), "probabilidad por hora")
	Company.stage = 4
	_expect(is_equal_approx(Events.get_mean_days(), 1.5), "Corporación: uno cada día y medio")


func _check_conditions() -> void:
	_new_game()
	var eligible: Array[String] = Events.get_eligible_ids()
	_expect(not eligible.has("birthday") and not eligible.has("coffee"), "sin empleados no hay cumpleaños ni café: %s" % [eligible])
	_expect(eligible.has("referral") and not eligible.has("award"), "recomendación sí; premio pide 2 estrellas: %s" % [eligible])
	_add_employee(901, "Ana")
	Projects.add_reputation(1.5)
	eligible = Events.get_eligible_ids()
	_expect(eligible.has("birthday") and eligible.has("coffee") and eligible.has("award"), "con empleados y reputación: %s" % [eligible])
	while Projects.has_offer_room():
		Projects.create_offer("small")
	_expect(not Events.get_eligible_ids().has("referral"), "con la bandeja llena no llega una recomendación")


func _check_choose() -> void:
	_new_game()
	_add_employee(901, "Ana")
	_expect(Events.trigger("birthday"), "abrir el cumpleaños")
	_expect(String(Events.card["text"]).contains("Ana"), "el texto nombra a un empleado: %s" % Events.card["text"])
	_expect(not Events.trigger("coffee"), "uno a la vez")
	_expect(Events.describe_effects(Events.card["options"][0]["effects"]) == "−$150, ánimo +8", "describe la opción: %s" %
		Events.describe_effects(Events.card["options"][0]["effects"]))
	var balance: int = Economy.balance
	_notices.clear()
	var message: String = Events.choose(0)
	_expect(Events.card.is_empty() and Economy.balance == balance - 150 and int(Staff.employees[0]["mood"]) == 68, "bizcocho: −$150 y ánimo +8")
	_expect(Economy.get_month_totals(GameClock.get_month()).get(Events.CONCEPT_EVENT, 0) == -150, "con el concepto Evento")
	_expect(message.begins_with("Cumpleaños en la oficina: Comprar bizcocho") and _notices.size() == 1, "avisa: %s" % message)
	Events.trigger("coffee")
	Events.choose(1)
	_expect(int(Staff.employees[0]["energy"]) == 60, "esperar el café: energía −20")
	Projects.add_reputation(1.5)
	var reputation: float = Projects.reputation
	Events.trigger("award")
	Events.choose(0)
	_expect(is_equal_approx(Projects.reputation, reputation + 0.3), "premio: reputación +0.3")
	var offers: int = Projects.offers.size()
	Events.trigger("referral")
	message = Events.choose(0)
	_expect(Projects.offers.size() == offers + 1 and message.contains("llegó una oferta"), "recomendación: llega una oferta: %s" % message)
	_expect(Events.choose(0).is_empty(), "sin tarjeta no se elige nada")


func _check_countdown() -> void:
	_new_game()
	_add_employee(901, "Ana")
	Events.trigger("birthday")
	Events.advance_countdown(119.0)
	_expect(not Events.card.is_empty() and Events.describe_countdown() == "0:01", "a los 119 s sigue abierta: %s" % Events.describe_countdown())
	_notices.clear()
	Events.advance_countdown(2.0)
	_expect(Events.card.is_empty() and _notices.size() == 1 and _notices[0].begins_with("Se acabó el tiempo. Cumpleaños"),
		"a los 2 minutos elige al azar: %s" % [_notices])
	# La cuenta va en segundos reales con el reloj andando, a cualquier velocidad, y se detiene
	# en pausa (construir pausa).
	Events.trigger("coffee")
	GameClock.start()
	GameClock.set_speed_index(GameConstants.CLOCK_SPEEDS.size() - 1)
	Events._process(10.0)
	_expect(is_equal_approx(float(Events.card["seconds_left"]), 110.0), "a la mayor velocidad descuenta 10 s reales")
	GameClock.set_paused(true)
	Events._process(10.0)
	_expect(is_equal_approx(float(Events.card["seconds_left"]), 110.0), "en pausa no corre")
	GameClock.stop()
	GameClock.set_paused(false)
	Events._process(10.0)
	_expect(is_equal_approx(float(Events.card["seconds_left"]), 110.0), "con el reloj detenido tampoco")
	Events.choose(0)


# Cuántos eventos llegan en esas horas con el reloj andando (eligiendo enseguida).
func _count_events(hours: int) -> int:
	_started = 0
	GameClock.start()
	for hour: int in range(hours):
		# El empleado de mentira termina renunciando: vuelve otro.
		if Staff.employees.is_empty():
			_add_employee(900 + hour, "Ana")
		GameClock.fast_forward_hours(1)
		if not Events.card.is_empty():
			Events.choose(0)
	GameClock.stop()
	return _started


func _check_rolls() -> void:
	_new_game()
	_add_employee(901, "Ana")
	# Con el reloj de la partida detenido (como adelantan las pruebas) no llega ninguno.
	GameClock.fast_forward_hours(24 * 60)
	_expect(Events.card.is_empty(), "con el reloj detenido no salen")
	# En pausa tampoco (construir pausa el reloj).
	GameClock.start()
	GameClock.set_paused(true)
	_started = 0
	GameClock.fast_forward_hours(24 * 60)
	_expect(_started == 0, "en pausa no salen: %d" % _started)
	GameClock.set_paused(false)
	GameClock.stop()
	var early: int = _count_events(24 * 200)
	_expect(early >= 25 and early <= 60, "Emprendimiento: ~40 en 200 días: %d" % early)
	Company.stage = 4
	var late: int = _count_events(24 * 200)
	_expect(late >= 100 and late <= 170, "Corporación: ~133 en 200 días: %d" % late)
	_expect(late > early * 2, "la frecuencia sube con la empresa")


func _check_save() -> void:
	# Sin empleados de mentira: el guardado pide empleados completos.
	_new_game()
	Events.trigger("referral")
	Events.advance_countdown(30.0)
	var text: String = Events.card["text"]
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(Events.card.is_empty(), "partida nueva sin tarjeta")
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(Events.card.get("event_id", "") == "referral" and Events.card["text"] == text
		and is_equal_approx(float(Events.card["seconds_left"]), 90.0) and (Events.card["options"] as Array).size() == 1,
		"la tarjeta abierta se guarda: %s" % [Events.card])
	Events.import_state({})
	_expect(Events.card.is_empty(), "partida de antes del hito 43: sin tarjeta")
	Events.import_state({"card": {"event_id": "no_existe", "options": [{"label": "x", "effects": []}]}})
	_expect(Events.card.is_empty(), "un evento que ya no existe no se carga")


func _check_ui() -> void:
	_new_game()
	_add_employee(901, "Ana")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var card: EventCard = game.get_node("EventCard")
	_expect(not card.is_showing(), "sin evento no se ve")
	Events.trigger("birthday")
	await get_tree().process_frame
	_expect(card.is_showing() and card.get_text().contains("Cumpleaños en la oficina") and card.get_text().contains("elige en 2:00"),
		"la tarjeta se ve: %s" % card.get_text())
	var buttons: Array[Button] = card.get_option_buttons()
	_expect(buttons.size() == 2 and buttons[0].text == "Comprar bizcocho (−$150, ánimo +8)", "opciones con lo que hacen: %s" %
		(buttons[0].text if not buttons.is_empty() else ""))
	card.get_fold_button().pressed.emit()
	await get_tree().process_frame
	_expect(card.is_folded() and card.get_text().contains("Cumpleaños"), "se pliega y muestra el título en la cabecera")
	card.get_fold_button().pressed.emit()
	await get_tree().process_frame
	card.get_option_buttons()[1].pressed.emit()
	await get_tree().process_frame
	_expect(Events.card.is_empty() and not card.is_showing(), "elegir cierra la tarjeta")
	var opener: Callable = func(hour: int) -> void:
		if hour == 3:
			Events.trigger("coffee")
	EventBus.hour_changed.connect(opener)
	var start: int = GameClock.get_day_count() * 24 + GameClock.get_hour()
	GameClock.fast_forward_hours(48)
	var jumped: int = GameClock.get_day_count() * 24 + GameClock.get_hour() - start
	EventBus.hour_changed.disconnect(opener)
	_expect(not Events.card.is_empty() and jumped < 48, "el evento corta el salto: %d horas" % jumped)
	Events.choose(0)
	game.queue_free()
	await get_tree().process_frame
