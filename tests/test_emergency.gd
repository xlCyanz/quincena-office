# Prueba sin ventana del hito 24: préstamo de emergencia.
# Criterio: el día 15 sin dinero aparece la ventana con el tiempo en pausa; aceptar paga
# la nómina y crea el préstamo al 12 %; rechazar deja la deuda de nómina; con 2 meses de
# cuotas atrasadas no se ofrece.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_emergency.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261112

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_offer()
	_check_accept()
	_check_reject()
	_check_day_30()
	_check_not_offered()
	_check_save()
	await _check_window()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _sum(concept: String) -> int:
	var total: int = 0
	for movement: Dictionary in Economy.movements:
		if movement["concept"] == concept:
			total += int(movement["amount"])
	return total


func _has_notice(part: String) -> bool:
	for text: String in _notices:
		if text.contains(part):
			return true
	return false


# Partida nueva con un programador contratado en un puesto y la cuenta en cero.
func _new_game_with_employee() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	var builder := Builder.new()
	var y: int = GridEdge.AXIS_Y
	builder.apply([{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL}, {"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR}])
	builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))
	builder.place("simple_desk", Vector2i(3, 0), 2)
	builder.place("basic_chair", Vector2i(3, 1), 0)
	builder.install_computer("basic_computer", Vector2i(3, 0))
	var vacancy_id: int = Staff.open_vacancy("programmer", "junior", 1000, true)["id"]
	GameClock.fast_forward_hours(1)
	var candidate: Dictionary = Staff.get_vacancy(vacancy_id)["candidates"][0]
	Staff.make_offer(candidate["id"], candidate["asked_salary"])
	_expect(Staff.employees.size() == 1, "contratado")
	Economy.charge(Economy.balance, "Prueba")
	_notices.clear()


# Avanza hasta las 0:00 del día del mes indicado (en este mes o el siguiente).
func _to_day(day: int) -> void:
	var target: int = (GameClock.get_month() - 1) * GameConstants.DAYS_PER_MONTH + day - 1
	if target <= GameClock.get_day_count():
		target += GameConstants.DAYS_PER_MONTH
	GameClock.fast_forward_hours((target - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY - GameClock.get_hour())


func _mood() -> int:
	return int(Staff.employees[0]["mood"])


func _check_offer() -> void:
	_new_game_with_employee()
	var late: int = Bank.late_payments
	_to_day(15)
	var offer: Dictionary = Bank.emergency_offer
	_expect(not offer.is_empty() and Staff.payroll_held, "el día 15 sin dinero el banco ofrece: %s" % offer)
	var owed: int = Staff.get_total_owed()
	_expect(owed > 0 and int(offer["shortfall"]) == owed, "falta toda la nómina: %d / %s" % [owed, offer])
	_expect(int(offer["amount"]) % 100 == 0 and int(offer["amount"]) >= owed and int(offer["amount"]) - owed < 100,
		"monto redondeado de a $100: %s" % offer)
	_expect(is_equal_approx(float(offer["rate"]), 0.12) and int(offer["months"]) == 3, "12 %% a 3 meses: %s" % offer)
	var terms: Dictionary = Bank.quote(offer["amount"], 3, 0.12)
	_expect(int(offer["installment"]) == int(terms["installment"]) and int(offer["total"]) == int(terms["total"]), "cuota y total")
	_expect(Bank.late_payments == late and not _has_notice("No alcanza el dinero para la nómina"), "esperando no hay atraso ni aviso")


func _check_accept() -> void:
	_new_game_with_employee()
	var available: int = Bank.get_available()
	var on_time: int = Bank.on_time_payments
	var late: int = Bank.late_payments
	_to_day(14)
	var mood: int = _mood()
	_to_day(15)
	var amount: int = int(Bank.emergency_offer["amount"])
	var owed: int = Staff.get_total_owed()
	var paid_before: int = _sum(Staff.CONCEPT_PAYROLL)
	_expect(Bank.accept_emergency()["ok"], "aceptar")
	_expect(Bank.emergency_offer.is_empty() and not Staff.payroll_held, "la oferta queda respondida")
	_expect(Staff.get_total_owed() == 0 and _sum(Staff.CONCEPT_PAYROLL) == paid_before - owed, "aceptar paga la nómina: %d" % _sum(Staff.CONCEPT_PAYROLL))
	_expect(_sum(Bank.CONCEPT_EMERGENCY) == amount and Economy.balance == amount - owed, "llega el dinero: %d" % Economy.balance)
	_expect(Bank.on_time_payments == on_time + 1 and Bank.late_payments == late, "la nómina cuenta a tiempo")
	_expect(_mood() >= mood - 5, "sin golpe al ánimo: %d → %d" % [mood, _mood()])
	_expect(Bank.loans.size() == 1 and bool(Bank.loans[0]["emergency"]) and is_equal_approx(float(Bank.loans[0]["rate"]), 0.12),
		"préstamo al 12 %%: %s" % [Bank.loans])
	_expect(Bank.get_available() == available and Bank.get_debt() == amount, "no cuenta para el límite")
	_expect(not Bank.refinance_problem(Bank.loans[0], 3).is_empty(), "no se refinancia")
	# Del día 15 al día 1 hay 16 días: la primera cuota es el día 1 siguiente.
	_expect(int(Bank.loans[0]["first_due_day"]) == GameConstants.DAYS_PER_MONTH, "primera cuota el día 1 del mes 2")
	Economy.earn(10000, "Prueba")
	_to_day(1)
	_expect(_sum(Bank.CONCEPT_INSTALLMENT) == -int(Bank.quote(amount, 3, 0.12)["installment"]), "cuota del 12 %% el día 1")


func _check_reject() -> void:
	_new_game_with_employee()
	var late: int = Bank.late_payments
	_to_day(14)
	var mood: int = _mood()
	_to_day(15)
	var owed: int = Staff.get_total_owed()
	Bank.reject_emergency()
	_expect(Bank.emergency_offer.is_empty() and not Staff.payroll_held and Bank.loans.is_empty(), "rechazar no crea préstamo")
	_expect(Staff.get_total_owed() == owed and owed > 0, "rechazar deja la deuda de nómina")
	_expect(Bank.late_payments == late + 1, "es un atraso")
	_expect(_mood() <= mood - 15, "baja el ánimo: %d → %d" % [mood, _mood()])
	_expect(_has_notice("No alcanza el dinero para la nómina"), "aviso de nómina: %s" % [_notices])


# La nómina del 30: la primera cuota se corre al mes siguiente (faltan menos de 15 días).
func _check_day_30() -> void:
	_new_game_with_employee()
	_to_day(15)
	Bank.reject_emergency()
	_to_day(30)
	_expect(not Bank.emergency_offer.is_empty(), "el día 30 también ofrece")
	Bank.accept_emergency()
	_expect(int(Bank.loans[0]["first_due_day"]) == 2 * GameConstants.DAYS_PER_MONTH, "primera cuota el día 1 del mes 3")
	Economy.earn(20000, "Prueba")
	_to_day(1)
	_expect(_sum(Bank.CONCEPT_INSTALLMENT) == 0 and int(Bank.loans[0]["paid"]) == 0, "el día 1 siguiente no cobra")
	_to_day(1)
	_expect(_sum(Bank.CONCEPT_INSTALLMENT) < 0 and int(Bank.loans[0]["paid"]) == 1, "cobra el día 1 del mes 3")


func _check_not_offered() -> void:
	_new_game_with_employee()
	Bank.overdue_months = int(Bank.get_config("warning_months"))
	_to_day(15)
	_expect(Bank.emergency_offer.is_empty() and not Staff.payroll_held and Staff.get_total_owed() > 0,
		"con 2 meses de cuotas atrasadas no se ofrece")
	_expect(_has_notice("No alcanza el dinero para la nómina"), "queda la deuda de nómina")


func _check_save() -> void:
	_new_game_with_employee()
	_to_day(15)
	var offer: String = JSON.stringify(Bank.emergency_offer)
	_expect(SaveManager.save_game("slot_5"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(JSON.stringify(Bank.emergency_offer) == offer and Staff.payroll_held, "la oferta sin responder vuelve")
	Bank.accept_emergency()
	_expect(Staff.get_total_owed() == 0 and not Staff.payroll_held, "y se puede aceptar después de cargar")
	var before: String = JSON.stringify(Bank.export_state())
	SaveManager.save_game("slot_5")
	SaveManager.load_game("slot_5")
	_expect(JSON.stringify(Bank.export_state()) == before, "el préstamo de emergencia vuelve igual")


func _check_window() -> void:
	_new_game_with_employee()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var dialog: EmergencyLoanDialog = game.get_node("EmergencyLoanDialog")
	_expect(not dialog.is_open(), "la ventana empieza cerrada")
	# Un salto largo se corta al aparecer la oferta.
	GameClock.fast_forward_hours((20 - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY)
	_expect(GameClock.get_day() == 15 and GameClock.get_hour() == 0, "el salto se corta el día 15: día %d %d:00" % [GameClock.get_day(), GameClock.get_hour()])
	_expect(dialog.is_open() and GameClock.is_paused, "la ventana abre con el tiempo en pausa")
	var text: String = dialog.get_text()
	_expect(text.contains("Préstamo de emergencia") and text.contains("12 % al mes · 3 meses") and text.contains("Cuota: ")
		and text.contains(MoneyFormat.format(int(Bank.emergency_offer["amount"]))), "texto: %s" % text)
	dialog.get_accept_button().pressed.emit()
	await get_tree().process_frame
	_expect(not dialog.is_open() and Staff.get_total_owed() == 0 and Bank.loans.size() == 1, "aceptar desde la ventana")
	_expect(not GameClock.is_paused, "el tiempo vuelve a correr")
	game.queue_free()
	await get_tree().process_frame
	# Cargar una partida con la oferta pendiente vuelve a abrir la ventana.
	_new_game_with_employee()
	_to_day(15)
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	SaveManager.load_game("slot_5")
	game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	dialog = game.get_node("EmergencyLoanDialog")
	_expect(dialog.is_open() and GameClock.is_paused, "al cargar vuelve a preguntar")
	dialog.get_reject_button().pressed.emit()
	await get_tree().process_frame
	_expect(not dialog.is_open() and Staff.get_total_owed() > 0 and Bank.loans.is_empty(), "rechazar desde la ventana")
	game.queue_free()
	await get_tree().process_frame
