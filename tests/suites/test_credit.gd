# Prueba del hito 21: calificación de crédito.
# Criterio: una empresa nueva está en C con límite de $5,000; con ingresos y pagos
# puntuales sube; un atraso la baja una letra.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=credit
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261111

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
	# Estas pruebas son de la nómina sin préstamo de emergencia (hito 24): se rechaza.
	EventBus.emergency_loan_offered.connect(func(_offer: Dictionary) -> void: Bank.reject_emergency())
	_check_new_company()
	_check_rise()
	_check_late()
	_check_payroll()
	_check_save()
	await _check_panel()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _config(key: String) -> int:
	return int(Bank.get_config(key))


func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	_notices.clear()


# Avanza hasta las 0:00 del día 1 del mes siguiente.
func _to_next_month() -> void:
	var target: int = GameClock.get_month() * GameConstants.DAYS_PER_MONTH
	GameClock.fast_forward_hours((target - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY - GameClock.get_hour())


func _part(label: String) -> int:
	for part: Dictionary in Bank.get_score_parts():
		if part["label"] == label:
			return part["points"]
	return -999


func _check_new_company() -> void:
	_new_game()
	_expect(Bank.rating == "C", "una empresa nueva está en C: %s (%d)" % [Bank.rating, Bank.score])
	_expect(Bank.get_limit() == 5000, "límite inicial $5,000: %d" % Bank.get_limit())
	_expect(is_equal_approx(Bank.get_monthly_rate(), 0.045), "interés de C 4.5 %")
	_expect(Bank.get_assets_value() > 0 and _part("Bienes") == 0, "los muebles iniciales valen poco: %d" % Bank.get_assets_value())
	_expect(Bank.letter_for(75) == "A" and Bank.letter_for(74) == "B" and Bank.letter_for(60) == "B" and Bank.letter_for(59) == "C"
		and Bank.letter_for(45) == "C" and Bank.letter_for(30) == "D" and Bank.letter_for(29) == "E" and Bank.letter_for(0) == "E", "umbrales")
	# Los ingresos de este mes no cuentan hasta el día 1.
	Economy.earn(10000, Projects.CONCEPT_DELIVERY)
	_expect(Bank.monthly_income == 0 and Bank.rating == "C", "a mitad de mes no cambia")


func _check_rise() -> void:
	_new_game()
	Economy.earn(int(Bank.get_config("income_for_max_points")), Projects.CONCEPT_DELIVERY)
	Economy.earn(5000, "Prueba")  # otros ingresos no cuentan
	_to_next_month()
	_expect(Bank.monthly_income == int(Bank.get_config("income_for_max_points")), "ingreso del mes pasado: %d" % Bank.monthly_income)
	_expect(_part("Ingresos del mes pasado") == _config("income_points_max"), "ingresos al máximo")
	_expect(_part("Antigüedad") == _config("age_points_per_month"), "un mes de antigüedad")
	_expect(Bank.on_time_payments == 1 and _part("Pagos a tiempo") == _config("on_time_points"), "el mantenimiento pagado cuenta a tiempo")
	_expect(Bank.rating == "B", "con ingresos y pagos puntuales sube a B: %s (%d)" % [Bank.rating, Bank.score])
	_expect(_notices.has("La calificación de crédito sube a B."), "aviso: %s" % [_notices])
	_expect(Bank.get_limit() == 4 * Bank.monthly_income, "límite de B: 4 veces el ingreso: %d" % Bank.get_limit())
	# Con ingresos bajos el límite nunca baja de $5,000.
	Bank.monthly_income = 1000
	_expect(Bank.get_limit() == 5000, "nunca menos de $5,000: %d" % Bank.get_limit())


func _check_late() -> void:
	_new_game()
	Economy.earn(int(Bank.get_config("income_for_max_points")), Projects.CONCEPT_DELIVERY)
	_to_next_month()
	_expect(Bank.rating == "B", "parte en B")
	# Un atraso a mitad de mes baja la nota en el momento: 15 puntos, una letra.
	var score: int = Bank.score
	_notices.clear()
	EventBus.payment_recorded.emit(Staff.CONCEPT_PAYROLL, false)
	_expect(Bank.score == score + _config("late_points"), "un atraso resta %d: %d → %d" % [-_config("late_points"), score, Bank.score])
	_expect(Bank.rating == "C", "un atraso baja una letra: %s" % Bank.rating)
	_expect(_notices.has("La calificación de crédito baja a C."), "aviso: %s" % [_notices])
	# Un pago a tiempo no sube la nota hasta el día 1.
	EventBus.payment_recorded.emit(Staff.CONCEPT_PAYROLL, true)
	_expect(Bank.score == score + _config("late_points"), "el pago a tiempo espera al día 1")
	# El mantenimiento que deja el saldo negativo también es un atraso.
	Economy.charge(Economy.balance, "Prueba")
	_to_next_month()
	_expect(Bank.late_payments == 2 and Economy.balance < 0, "el mantenimiento sin dinero es un atraso: %d" % Bank.late_payments)


# La nómina: pagada cuenta a tiempo; sin pagar baja la letra en el momento.
func _check_payroll() -> void:
	_new_game()
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
	GameClock.fast_forward_hours((14 - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY - GameClock.get_hour())
	_expect(GameClock.get_day() == 15 and Bank.on_time_payments == 1, "la nómina pagada cuenta a tiempo: %d" % Bank.on_time_payments)
	var rating: String = Bank.rating
	Economy.charge(Economy.balance, "Prueba")
	GameClock.fast_forward_hours(15 * GameConstants.HOURS_PER_DAY)
	_expect(GameClock.get_day() == 30 and Bank.late_payments == 1, "la nómina sin pagar es un atraso: %d" % Bank.late_payments)
	_expect(Bank.score == Bank.compute_score() and Bank.rating == Bank.letter_for(Bank.score), "se recalcula en el momento")
	_expect(Bank.rating != rating, "la letra baja en el momento: %s → %s" % [rating, Bank.rating])


func _check_save() -> void:
	_new_game()
	Economy.earn(4000, Projects.CONCEPT_DELIVERY)
	_to_next_month()
	var before: String = JSON.stringify(Bank.export_state())
	_expect(SaveManager.save_game("slot_5"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(JSON.stringify(Bank.export_state()) == before, "el banco vuelve igual")
	# Una partida de antes del hito 21 se calcula con lo que hay.
	Bank.import_state({})
	_expect(Bank.rating == Bank.letter_for(Bank.compute_score()) and Bank.late_payments == 0, "partida vieja: %s" % [Bank.export_state()])


func _check_panel() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var bank: BankPanel = game.get_node("BankPanel")
	bank.set_open(true)
	await get_tree().process_frame
	var text: String = bank.get_credit_text()
	_expect(text.begins_with("Crédito: C (%d puntos) · interés 4.5 %% al mes · presta hasta $5,000" % Bank.score), "título: %s" % text)
	_expect(text.contains("Base | +%d" % _config("base_score")) and text.contains("Antigüedad (0 meses) | +0")
		and text.contains("Atrasos (0) | +0"), "factores: %s" % text)
	Economy.charge(Economy.balance + 100, "Prueba")
	_to_next_month()
	await get_tree().process_frame
	text = bank.get_credit_text()
	_expect(text.contains("Atrasos (1) | −15"), "el atraso se ve: %s" % text)
	game.queue_free()
	await get_tree().process_frame
