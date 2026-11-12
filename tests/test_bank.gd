# Prueba sin ventana del hito 20: menú Banco.
# Criterio: tras comprar un mueble y cobrar un contrato, ambos movimientos aparecen con
# su fecha y los totales del mes cuadran con Economy.
# Ejecutar con:
#   Godot --headless --path . res://tests/test_bank.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

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
	_check_totals()
	_check_months()
	_check_trimmed_history()
	_check_save()
	await _check_panel()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)


# Compra una planta (un mueble) y devuelve su precio.
func _buy_plant() -> int:
	var price: int = int(FurnitureCatalog.get_item("small_plant")["price"])
	var result: Dictionary = Builder.new().place("small_plant", Vector2i(1, 4), 0)
	_expect(result["ok"], "comprar una planta: %s" % result.get("message", ""))
	return price


# Acepta un contrato, lo termina y lo entrega. Devuelve lo cobrado en la entrega.
func _deliver_contract() -> Dictionary:
	if Projects.offers.is_empty():
		Projects.offers.append(Projects._make_offer(GameClock.get_day_count(), "small"))
	Projects.accept(Projects.offers[0]["id"])
	var contract: Dictionary = Projects.contracts[-1]
	for phase: String in ContractCatalog.PHASES:
		contract["progress"][phase] = float(contract["points"][phase])
	contract["bugs_hidden"] = 0
	var result: Dictionary = Projects.deliver(contract["id"])
	_expect(result["ok"], "entregar el contrato: %s" % result.get("message", ""))
	return contract


func _sum_month(month: int) -> int:
	var total: int = 0
	for movement: Dictionary in Economy.movements:
		if int(movement["month"]) == month:
			total += int(movement["amount"])
	return total


func _sum_totals(month: int) -> int:
	var total: int = 0
	var totals: Dictionary[String, int] = Economy.get_month_totals(month)
	for concept: String in totals:
		total += totals[concept]
	return total


func _check_totals() -> void:
	_new_game()
	var start: int = Economy.balance
	var price: int = _buy_plant()
	var contract: Dictionary = _deliver_contract()
	var totals: Dictionary[String, int] = Economy.get_month_totals(1)
	_expect(totals.get(Builder.CONCEPT_FURNITURE, 0) == -price, "muebles del mes: %s" % [totals])
	var paid: int = 0
	for movement: Dictionary in Economy.movements:
		if movement["concept"] == Projects.CONCEPT_DELIVERY:
			paid += int(movement["amount"])
	_expect(paid > 0 and totals.get(Projects.CONCEPT_DELIVERY, 0) == paid, "cobro del contrato: %d, %s" % [paid, totals])
	_expect(_sum_totals(1) == Economy.balance - start and _sum_totals(1) == _sum_month(1), "los totales cuadran con el saldo")
	var last: Dictionary = Economy.movements[-1]
	_expect(int(last["day"]) == GameClock.get_day() and int(last["month"]) == GameClock.get_month(), "el movimiento lleva la fecha de hoy")
	_expect(Economy.get_month_totals(5).is_empty(), "un mes sin datos da vacío")
	_expect(contract["id"] > 0, "contrato con id")


func _check_months() -> void:
	_new_game()
	_buy_plant()
	# Al día 1 del mes 2: el mantenimiento cuenta en el mes nuevo y el anterior se guarda.
	GameClock.fast_forward_hours((GameConstants.DAYS_PER_MONTH - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY - GameClock.get_hour())
	_expect(GameClock.get_month() == 2 and Economy.get_current_month() == 2, "llegar al mes 2")
	var maintenance: int = Economy.get_maintenance(OfficeState.lot_rect.get_area())
	_expect(Economy.get_month_totals(2).get(Economy.CONCEPT_MAINTENANCE, 0) == -maintenance, "mantenimiento en el mes 2: %s" % [Economy.get_month_totals(2)])
	_expect(Economy.get_month_totals(1).has(Builder.CONCEPT_FURNITURE), "el mes anterior se conserva")
	GameClock.fast_forward_hours(GameConstants.DAYS_PER_MONTH * GameConstants.HOURS_PER_DAY)
	_expect(Economy.get_current_month() == 3 and Economy.get_month_totals(1).is_empty() and not Economy.get_month_totals(2).is_empty(),
		"en el mes 3 solo quedan el 3 y el 2: %s" % [Economy.month_totals.keys()])


func _check_trimmed_history() -> void:
	_new_game()
	for i: int in range(Economy.MAX_MOVEMENTS + 50):
		Economy.charge(1, "Prueba")
	_expect(Economy.movements.size() == Economy.MAX_MOVEMENTS, "el historial guarda %d" % Economy.MAX_MOVEMENTS)
	_expect(Economy.get_month_totals(1)["Prueba"] == -(Economy.MAX_MOVEMENTS + 50), "el total del mes no se recorta")


func _check_save() -> void:
	_new_game()
	_buy_plant()
	Economy.earn(500, "Prueba")
	var before: String = JSON.stringify(Economy.export_state())
	_expect(SaveManager.save_game("slot_5"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(JSON.stringify(Economy.export_state()) == before, "la cuenta vuelve igual")
	# Una partida de antes del hito 20 rearma los totales con el historial.
	var old: Dictionary = Economy.export_state()
	old.erase("month_totals")
	var expected: Dictionary[String, int] = Economy.get_month_totals(1)
	Economy.import_state(old)
	_expect(Economy.get_month_totals(1) == expected, "partida vieja: %s" % [Economy.get_month_totals(1)])


func _check_panel() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var bank: BankPanel = game.get_node("BankPanel")
	var projects: ProjectsPanel = game.get_node("ProjectsPanel")
	# Todos los botones de la barra entran en la pantalla.
	await get_tree().process_frame
	var view: Rect2 = get_viewport().get_visible_rect()
	for button: Node in bank.get_open_button().get_parent().get_children():
		var rect: Rect2 = (button as Control).get_global_rect()
		_expect(view.encloses(rect), "%s entra en la barra: %s" % [(button as Button).text, rect])
	projects.set_open(true)
	await _click(bank.get_open_button())
	_expect(bank.is_open() and not projects.is_open(), "abrir Banco cierra Proyectos")
	_expect(not GameClock.is_paused, "el Banco no pausa")
	_expect(bank.get_balance_text() == "Saldo: %s" % MoneyFormat.format(Economy.balance), "saldo: %s" % bank.get_balance_text())
	_expect(bank.get_month_text().contains("Sin movimientos"), "mes vacío: %s" % bank.get_month_text())
	var price: int = _buy_plant()
	_deliver_contract()
	await get_tree().process_frame
	var text: String = bank.get_month_text()
	var totals: Dictionary[String, int] = Economy.get_month_totals(1)
	var delivery: int = totals[Projects.CONCEPT_DELIVERY]
	_expect(text.contains("Mes 1 (este mes)"), "título del mes: %s" % text)
	_expect(text.contains("Muebles | −%s" % MoneyFormat.format(price)), "gasto en muebles: %s" % text)
	_expect(text.contains("%s | +%s" % [Projects.CONCEPT_DELIVERY, MoneyFormat.format(delivery)]), "cobro del contrato: %s" % text)
	_expect(text.contains("Resultado | +%s" % MoneyFormat.format(_sum_totals(1))), "resultado del mes: %s" % text)
	var rows: Array[String] = bank.get_movement_texts()
	_expect(rows.size() == Economy.movements.size(), "un renglón por movimiento")
	_expect(rows[0].begins_with("Día 1 · Mes 1 | %s" % Economy.movements[-1]["concept"]), "el más nuevo arriba: %s" % rows[0])
	_expect(rows.any(func(row: String) -> bool: return row.contains("Muebles | −%s" % MoneyFormat.format(price))), "la compra está en el historial")
	# El selector solo va del mes anterior al actual.
	_expect(bank.get_previous_button().disabled and bank.get_next_button().disabled, "en el mes 1 no hay otro mes")
	GameClock.fast_forward_hours((GameConstants.DAYS_PER_MONTH - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY - GameClock.get_hour())
	await get_tree().process_frame
	_expect(bank.get_shown_month() == 2 and not bank.get_previous_button().disabled, "en el mes 2 se puede ver el anterior")
	await _click(bank.get_previous_button())
	_expect(bank.get_shown_month() == 1 and bank.get_month_text().contains("Mes 1 (mes anterior)") and bank.get_month_text().contains("Muebles"),
		"mes anterior: %s" % bank.get_month_text())
	_expect(bank.get_previous_button().disabled and not bank.get_next_button().disabled, "del anterior solo se vuelve")
	await _click(bank.get_next_button())
	_expect(bank.get_shown_month() == 2 and bank.get_month_text().contains(Economy.CONCEPT_MAINTENANCE), "vuelve al mes 2: %s" % bank.get_month_text())
	game.queue_free()
	await get_tree().process_frame


func _click(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	await _push(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _push(event)


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame
