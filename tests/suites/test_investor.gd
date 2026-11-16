# Inversionista: aceptar da el efectivo y cobra su parte cada día 1 hasta terminar; el valor
# descuenta lo que falta; rechazar no cambia nada.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=investor
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261158
## Ingresos de contratos del primer mes (el inversionista pide al menos min_income).
const FIRST_INCOME: int = 20000

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_data()
	_check_share()
	_check_conditions()
	_check_reject()
	_check_accept()
	_check_payments()
	_check_save()
	await _check_ui()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva en Pequeña empresa con FIRST_INCOME de entregas el mes pasado.
func _new_game(income: int = FIRST_INCOME) -> void:
	GameClock.stop()
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	Events.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(50000, "Prueba")
	Economy.earn(income, Projects.CONCEPT_DELIVERY)
	_to_next_month()
	Company.stage = 2


func _to_next_month() -> void:
	var start: int = Economy.get_current_month()
	while Economy.get_current_month() == start:
		GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY)


func _check_data() -> void:
	var ratio: Array = Bank.get_investor_config("cash_ratio")
	var months: Array = Bank.get_investor_config("months")
	_expect(is_equal_approx(float(ratio[0]), 0.10) and is_equal_approx(float(ratio[1]), 0.25), "efectivo del 10 al 25 % del valor")
	_expect(int(months[0]) == 12 and int(months[1]) == 24, "de 12 a 24 meses")
	var event: Dictionary = Events._get_event("investor")
	_expect(int(event["conditions"]["min_stage"]) == 2 and event["target"] == "investor", "desde Pequeña empresa")
	_expect((event["options"] as Array).size() == 2 and (event["options"][1]["effects"] as Array).is_empty(), "aceptar o rechazar")


func _check_share() -> void:
	_expect(is_equal_approx(Bank.investor_share(20000, 20, 10000), 0.16), "parte: 20,000 × 1.6 / (10,000 × 20) = 16 %")
	_expect(is_equal_approx(Bank.investor_share(1000, 24, 100000), 0.05), "al menos 5 %")
	_expect(is_equal_approx(Bank.investor_share(100000, 12, 5000), 0.4), "como mucho 40 %")


func _check_conditions() -> void:
	_new_game()
	_expect(Bank.investor_problem().is_empty(), "puede llegar: %s" % Bank.investor_problem())
	_expect(Events.get_eligible_ids().has("investor"), "es elegible en Pequeña empresa")
	Company.stage = 1
	_expect(not Events.get_eligible_ids().has("investor"), "no en Startup")
	Company.stage = 2
	Bank.investor_enabled = false
	_expect(not Events.get_eligible_ids().has("investor"), "apagado para las pruebas viejas")
	Bank.investor_enabled = true
	_new_game(4000)
	_expect(not Bank.investor_problem().is_empty() and not Events.get_eligible_ids().has("investor"), "sin ingresos suficientes, no")
	_new_game()
	Economy.charge(Company.get_value() + 1000, "Prueba")
	_expect(Company.get_value() < 0 and not Events.get_eligible_ids().has("investor"), "con valor negativo, no")


func _check_reject() -> void:
	_new_game()
	var balance: int = Economy.balance
	var value: int = Company.get_value()
	_expect(Events.trigger("investor"), "llega el inversionista")
	_expect(Events.card["text"].contains("%") and not Events.card["text"].contains("{"), "el texto: %s" % Events.card["text"])
	Events.choose(1)
	_expect(Bank.investor.is_empty() and Economy.balance == balance and Company.get_value() == value, "rechazar no cambia nada")


func _check_accept() -> void:
	_new_game()
	var value: int = Company.get_value()
	var balance: int = Economy.balance
	_expect(Events.trigger("investor"), "llega el inversionista")
	var target: Dictionary = Events.card["target"]
	var cash: int = int(target["amount"])
	_expect(cash >= roundi(value * 0.1 / 1000.0) * 1000 and cash <= roundi(value * 0.25 / 1000.0) * 1000 and cash % 1000 == 0,
		"ofrece %s de un valor de %s" % [cash, value])
	_expect(int(target["months"]) >= 12 and int(target["months"]) <= 24, "meses: %d" % target["months"])
	_expect(is_equal_approx(float(target["share"]), Bank.investor_share(cash, int(target["months"]), FIRST_INCOME)), "la parte sale de la fórmula")
	var result: String = Events.choose(0)
	_expect(result.contains("recibes"), "el aviso: %s" % result)
	_expect(Economy.balance == balance + cash, "llega el efectivo")
	_expect(Economy.get_month_totals(Economy.get_current_month()).get(Bank.CONCEPT_INVESTMENT, 0) == cash, "como «Inversión»")
	_expect(not Bank.investor.is_empty() and Bank.get_investor_months_left() == int(target["months"]), "inversionista activo")
	var pending: int = roundi(float(target["share"]) * FIRST_INCOME * int(target["months"]))
	_expect(Bank.get_investor_remaining() == pending, "falta %s (estimado con el mes pasado)" % Bank.get_investor_remaining())
	_expect(Company.get_value() == value + cash - pending, "el valor descuenta lo que falta: %d" % Company.get_value())
	var parts: Array[Dictionary] = Company.get_value_parts()
	_expect(String(parts[-1]["label"]).contains("inversionista") and int(parts[-1]["amount"]) == -pending, "y se ve en el detalle")
	_expect(not Events.get_eligible_ids().has("investor") and not Events.trigger("investor"), "uno a la vez")


func _check_payments() -> void:
	_new_game()
	Events.trigger("investor")
	var share: float = float(Events.card["target"]["share"])
	# Lo que llegó este mes antes de aceptar no le toca.
	Economy.earn(3000, Projects.CONCEPT_DELIVERY)
	Events.choose(0)
	Bank.investor["months"] = 2
	Economy.earn(10000, Projects.CONCEPT_DELIVERY)
	Economy.earn(2000, Products.CONCEPT_INCOME)
	Economy.earn(5000, "Prueba")
	var month: int = Economy.get_current_month()
	_to_next_month()
	var paid: int = -Economy.get_month_totals(month + 1).get(Bank.CONCEPT_INVESTOR, 0)
	_expect(paid == roundi(12000 * share), "el día 1 cobra el %d %% de contratos y productos: %d" % [roundi(share * 100), paid])
	_expect(int(Bank.investor["paid_months"]) == 1 and Bank.get_investor_months_left() == 1, "queda 1 mes")
	Economy.earn(8000, Projects.CONCEPT_DELIVERY)
	_to_next_month()
	paid = -Economy.get_month_totals(month + 2).get(Bank.CONCEPT_INVESTOR, 0)
	_expect(paid == roundi(8000 * share), "segundo pago: %d" % paid)
	_expect(Bank.investor.is_empty() and Bank.get_investor_remaining() == 0, "termina al cumplir los meses")
	var value_parts: Array[Dictionary] = Company.get_value_parts()
	_expect(not String(value_parts[-1]["label"]).contains("inversionista"), "el valor ya no lo descuenta")
	# Sin ingresos no paga, pero el mes cuenta.
	_new_game()
	Events.trigger("investor")
	Events.choose(0)
	_to_next_month()
	_expect(Economy.get_month_totals(Economy.get_current_month()).get(Bank.CONCEPT_INVESTOR, 0) == 0
		and int(Bank.investor["paid_months"]) == 1, "sin ingresos, pago 0")
	Economy.earn(20000, Projects.CONCEPT_DELIVERY)
	Economy.charge(Economy.balance + 100, "Prueba")
	_to_next_month()
	_expect(Economy.get_month_totals(Economy.get_current_month()).get(Bank.CONCEPT_INVESTOR, 0) < 0 and Economy.balance < 0,
		"se cobra aunque deje el saldo negativo")


func _check_save() -> void:
	_new_game()
	Events.trigger("investor")
	Events.choose(0)
	var state: Dictionary = Bank.export_state()
	var deal: Dictionary = Bank.investor.duplicate()
	_new_game()
	_expect(Bank.investor.is_empty(), "partida nueva sin inversionista")
	Bank.import_state(state)
	_expect(Bank.investor == deal, "se guarda el inversionista")
	state.erase("investor")
	Bank.import_state(state)
	_expect(Bank.investor.is_empty(), "una partida vieja carga sin inversionista")


func _check_ui() -> void:
	_new_game()
	Events.trigger("investor")
	Events.choose(0)
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var bank: BankPanel = game.get_node("BankPanel")
	bank.set_open(true)
	_expect(bank.get_investor_text().begins_with("Inversionista: puso"), "el Banco lo muestra: %s" % bank.get_investor_text())
	game.queue_free()
	await get_tree().process_frame
