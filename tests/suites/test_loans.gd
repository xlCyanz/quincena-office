# Prueba del hito 22: préstamos.
# Criterio: $10,000 a 10 meses en C cuesta $14,500 en cuotas de $1,450 cobradas el día
# 1; no se puede pedir más que el límite; el pago anticipado ahorra intereses;
# refinanciar no se puede dos veces.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=loans
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261111

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_quote()
	_check_limit()
	_check_installments()
	_check_prepay()
	_check_refinance()
	_check_late()
	_check_save()
	await _check_panel()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Partida nueva en C con $4,000 de ingresos del mes pasado: límite 3 × 4,000 = $12,000.
func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	Bank.monthly_income = 4000
	Company.stage = 3  # Mediana empresa: sin tope por préstamo de la etapa (hito 27).
	_expect(Bank.rating == "C" and Bank.get_limit() == 12000, "parte en C con límite $12,000: %s %d" % [Bank.rating, Bank.get_limit()])


func _to_next_month() -> void:
	var target: int = GameClock.get_month() * GameConstants.DAYS_PER_MONTH
	GameClock.fast_forward_hours((target - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY - GameClock.get_hour())
	# Que la nota no cambie a mitad de la prueba: el ingreso queda fijo.
	Bank.monthly_income = 4000


func _sum(concept: String) -> int:
	var total: int = 0
	for movement: Dictionary in Economy.movements:
		if movement["concept"] == concept:
			total += int(movement["amount"])
	return total


func _check_quote() -> void:
	var terms: Dictionary = Bank.quote(10000, 10, 0.045)
	_expect(terms["total"] == 14500 and terms["installment"] == 1450 and terms["interest"] == 4500, "cotización: %s" % [terms])


func _check_limit() -> void:
	SaveManager.new_game()
	_expect(not Bank.request_loan(10000, 10)["ok"] and Bank.loans.is_empty(), "una empresa nueva no recibe $10,000 (límite $5,000)")
	_new_game()
	_expect(not Bank.request_loan(500, 10)["ok"], "menos del mínimo no")
	_expect(not Bank.request_loan(1000, 2)["ok"] and not Bank.request_loan(1000, 25)["ok"], "plazo de 3 a 24 meses")
	var before: int = Economy.balance
	var result: Dictionary = Bank.request_loan(10000, 10)
	_expect(result["ok"] and Economy.balance == before + 10000, "préstamo de $10,000: %s" % result["message"])
	_expect(Economy.movements[-1]["concept"] == Bank.CONCEPT_LOAN, "movimiento del préstamo")
	_expect(Bank.get_debt() == 10000 and Bank.get_available() == 2000, "debe $10,000, quedan $2,000: %d" % Bank.get_available())
	var too_much: Dictionary = Bank.request_loan(2500, 6)
	_expect(not too_much["ok"] and too_much["message"].contains("hasta $2,000"), "no pasa el límite: %s" % too_much["message"])
	_expect(Bank.request_loan(2000, 6)["ok"] and Bank.loans.size() == 2, "varios préstamos dentro del límite")


func _check_installments() -> void:
	_new_game()
	Bank.request_loan(10000, 10)
	var loan: Dictionary = Bank.loans[0]
	_expect(Bank.get_installment(loan) == 1450, "cuota $1,450")
	# El mismo día no se cobra nada; la primera cuota llega el día 1.
	_expect(_sum(Bank.CONCEPT_INSTALLMENT) == 0, "sin cuota el día del préstamo")
	_to_next_month()
	_expect(_sum(Bank.CONCEPT_INSTALLMENT) == -1450 and int(loan["paid"]) == 1, "el día 1 cobra $1,450")
	_expect(Bank.get_remaining_principal(loan) == 9000 and Bank.get_remaining_months(loan) == 9, "faltan 9 cuotas y $9,000 de capital")
	var on_time: int = Bank.on_time_payments
	for month: int in range(9):
		_to_next_month()
	_expect(_sum(Bank.CONCEPT_INSTALLMENT) == -14500, "en total paga $14,500: %d" % _sum(Bank.CONCEPT_INSTALLMENT))
	_expect(Bank.loans.is_empty() and Bank.get_debt() == 0, "pagado, el préstamo desaparece")
	_expect(Bank.on_time_payments >= on_time + 9, "cada cuota cuenta a tiempo")


func _check_prepay() -> void:
	_new_game()
	Bank.request_loan(10000, 10)
	for month: int in range(3):
		_to_next_month()
	var loan: Dictionary = Bank.loans[0]
	var cost: int = Bank.get_prepay_cost(loan)
	_expect(cost == 7000 + 450, "saldar cuesta capital + un mes de interés: %d" % cost)
	_expect(Bank.get_remaining_total(loan) == 14500 - 3 * 1450, "en cuotas faltarían $10,150")
	var before: int = Economy.balance
	var result: Dictionary = Bank.prepay(loan["id"])
	_expect(result["ok"] and Economy.balance == before - cost and Bank.loans.is_empty(), "saldado: %s" % result["message"])
	_expect(result["message"].contains("ahorras $2,700"), "ahorra intereses: %s" % result["message"])
	# Sin dinero no se puede saldar.
	Bank.request_loan(5000, 6)
	Economy.charge(Economy.balance, "Prueba")
	_expect(not Bank.prepay(Bank.loans[0]["id"])["ok"] and Bank.loans.size() == 1, "sin dinero no se salda")


func _check_refinance() -> void:
	_new_game()
	Bank.request_loan(10000, 10)
	for month: int in range(3):
		_to_next_month()
	var loan: Dictionary = Bank.loans[0]
	_expect(not Bank.refinance(loan["id"], 2)["ok"] and not Bank.refinance(loan["id"], 13)["ok"], "se alarga de 3 a 12 meses")
	var preview: Dictionary = Bank.preview_refinance(loan, 6)
	_expect(preview["months"] == 13 and is_equal_approx(preview["rate"], 0.055) and preview["total"] == 12005 and preview["installment"] == 923,
		"vista previa: %s" % [preview])
	var result: Dictionary = Bank.refinance(loan["id"], 6)
	_expect(result["ok"] and Bank.get_installment(loan) == 923 and Bank.get_remaining_months(loan) == 13
		and Bank.get_remaining_principal(loan) == 7000, "refinanciado: %s" % result["message"])
	var again: Dictionary = Bank.refinance(loan["id"], 3)
	_expect(not again["ok"] and again["message"].contains("ya se refinanció"), "no se refinancia dos veces: %s" % again["message"])
	# La última cuota cierra el total justo.
	for month: int in range(13):
		_to_next_month()
	_expect(Bank.loans.is_empty(), "refinanciado también termina")
	# Un préstamo a 24 meses ya no se puede alargar.
	Bank.request_loan(1000, 24)
	_expect(Bank.get_max_refinance_extra(Bank.loans[0]) == 0 and not Bank.refinance(Bank.loans[0]["id"], 3)["ok"], "24 meses es el tope")


func _check_late() -> void:
	_new_game()
	Bank.request_loan(10000, 10)
	Economy.charge(Economy.balance, "Prueba")
	var late: int = Bank.late_payments
	_to_next_month()
	# Sin dinero el mantenimiento deja saldo negativo y la cuota queda atrasada: dos atrasos.
	_expect(Bank.late_payments == late + 2, "la cuota sin dinero es un atraso: %d" % Bank.late_payments)
	_expect(_sum(Bank.CONCEPT_INSTALLMENT) == 0 and Bank.get_overdue() > 0, "la cuota no se cobra: queda atrasada (hito 23)")
	_expect(int(Bank.loans[0]["paid"]) == 1, "la cuota atrasada cuenta como vencida")


func _check_save() -> void:
	_new_game()
	Bank.request_loan(6000, 12)
	_to_next_month()
	Bank.refinance(Bank.loans[0]["id"], 3)
	Bank.request_loan(1000, 3)
	var before: String = JSON.stringify(Bank.export_state())
	_expect(SaveManager.save_game("slot_5"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(JSON.stringify(Bank.export_state()) == before, "los préstamos vuelven igual")
	var state: Dictionary = Bank.export_state()
	state.erase("loans")
	state.erase("next_loan_id")
	Bank.import_state(state)
	_expect(Bank.loans.is_empty(), "una partida del hito 21 carga sin préstamos")


func _check_panel() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	Bank.monthly_income = 4000
	var bank: BankPanel = game.get_node("BankPanel")
	bank.set_open(true)
	await get_tree().process_frame
	_expect(bank.get_loans_text() == "No tienes préstamos.", "sin préstamos: %s" % bank.get_loans_text())
	_expect(bank.get_request() == Vector2i(12000, 12), "propone lo disponible a 12 meses: %s" % bank.get_request())
	_expect(bank.get_amount_buttons()[1].disabled, "no se puede subir sobre el límite")
	for i: int in range(4):
		bank.get_amount_buttons()[0].pressed.emit()
	for i: int in range(2):
		bank.get_months_buttons()[0].pressed.emit()
	_expect(bank.get_request() == Vector2i(10000, 10), "monto y plazo con −: %s" % bank.get_request())
	_expect(bank.get_quote_text().begins_with("Tasa 4.5 % mensual · cuota $1,450 · total $14,500 (intereses $4,500)"), "vista previa: %s" % bank.get_quote_text())
	bank.get_request_button().pressed.emit()
	await get_tree().process_frame
	_expect(Bank.loans.size() == 1 and bank.get_loan_status().begins_with("Préstamo de $10,000"), "pedido: %s" % bank.get_loan_status())
	_expect(bank.get_loans_text().contains("$10,000 al 4.5 % mensual · cuota $1,450 · 10 cuotas · capital pendiente $10,000"), "renglón: %s" % bank.get_loans_text())
	var loan_id: int = Bank.loans[0]["id"]
	# Refinanciar: elegir los meses y confirmar.
	bank.get_refinance_button(loan_id).pressed.emit()
	await get_tree().process_frame
	_expect(bank.get_loans_text().contains("+3 meses: 13 cuotas de"), "vista del refinanciado: %s" % bank.get_loans_text())
	bank.get_extra_buttons()[1].pressed.emit()
	await get_tree().process_frame
	_expect(bank.get_loans_text().contains("+4 meses: 14 cuotas de"), "+ alarga: %s" % bank.get_loans_text())
	bank.get_confirm_button().pressed.emit()
	await get_tree().process_frame
	_expect(Bank.get_remaining_months(Bank.loans[0]) == 14 and bank.get_refinance_button(loan_id).disabled, "refinanciado desde el menú")
	# Saldar: pide confirmación.
	bank.get_prepay_button(loan_id).pressed.emit()
	await get_tree().process_frame
	_expect(Bank.loans.size() == 1 and bank.get_loans_text().contains("¿Saldar por"), "pide confirmar: %s" % bank.get_loans_text())
	bank.get_confirm_button().pressed.emit()
	await get_tree().process_frame
	_expect(Bank.loans.is_empty() and bank.get_loans_text() == "No tienes préstamos.", "saldado desde el menú")
	game.queue_free()
	await get_tree().process_frame
