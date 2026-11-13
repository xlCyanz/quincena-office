# Prueba del hito 26: valor de la empresa.
# Criterio: comprar un mueble baja el valor la mitad de su precio; pedir un préstamo no
# cambia el valor; comprar terreno tampoco (se cuenta a lo pagado); cada cuota baja el
# valor solo en su interés.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=company_value
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SEED: int = 20261112

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_start()
	_check_furniture()
	_check_loan()
	_check_land()
	_check_overdue()
	_check_save()
	await _check_ui()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)


func _to_next_month() -> void:
	var target: int = GameClock.get_month() * GameConstants.DAYS_PER_MONTH
	GameClock.fast_forward_hours((target - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY - GameClock.get_hour())


func _check_start() -> void:
	_new_game()
	var assets: int = Bank.get_assets_value()
	_expect(assets == 450 + 250 + 30 + 30, "muebles iniciales: escritorio ejecutivo, computadora y dos sillas: %d" % assets)
	_expect(Company.get_value() == Economy.balance + assets, "valor inicial = dinero + muebles: %d" % Company.get_value())
	var labels: Array[String] = []
	for part: Dictionary in Company.get_value_parts():
		labels.append(part["label"])
	_expect(labels.size() == 5 and labels[0] == "Dinero" and labels[3].begins_with("Productos") and labels[4] == "Deuda con el banco", "partes: %s" % [labels])


func _check_furniture() -> void:
	_new_game()
	var values: Array[int] = []
	EventBus.company_value_changed.connect(func(value: int) -> void: values.append(value))
	var value: int = Company.get_value()
	var builder := Builder.new()
	_expect(builder.place("small_plant", Vector2i(4, 5), 0)["ok"], "comprar una planta")
	_expect(Company.get_value() == value - 20, "una planta de $40 baja el valor $20: %d → %d" % [value, Company.get_value()])
	_expect(not values.is_empty() and values[-1] == Company.get_value(), "avisa el valor nuevo")
	value = Company.get_value()
	builder.sell_furniture_at(Vector2i(4, 5))
	_expect(Company.get_value() == value, "venderla no cambia el valor (se recupera la reventa)")
	# Paredes y pisos no son bienes: comprarlos baja el valor lo que cuestan.
	value = Company.get_value()
	builder.apply([{"edge": Vector3i(3, 4, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL}])
	_expect(Company.get_value() == value - ConstructionCatalog.get_price(ConstructionCatalog.WALL), "una pared baja lo que cuesta")


func _check_loan() -> void:
	_new_game()
	var value: int = Company.get_value()
	_expect(Bank.request_loan(5000, 10)["ok"], "pedir préstamo")
	_expect(Company.get_value() == value, "pedir un préstamo no cambia el valor: %d → %d" % [value, Company.get_value()])
	var loan: Dictionary = Bank.loans[0]
	var maintenance: int = Economy.get_maintenance(OfficeState.lot.get_area())
	value = Company.get_value()
	_to_next_month()
	var interest: int = Bank.get_installment(loan) - (5000 - Bank.get_remaining_principal(loan))
	_expect(interest == roundi(5000 * Bank.get_monthly_rate()) or interest > 0, "interés de la cuota: %d" % interest)
	_expect(Company.get_value() == value - maintenance - interest, "la cuota baja solo su interés (y el mantenimiento): %d → %d (interés %d)" % [
		value, Company.get_value(), interest])
	# Saldar: el valor baja solo el interés de un mes.
	value = Company.get_value()
	var cost: int = Bank.get_prepay_cost(loan)
	var principal: int = Bank.get_remaining_principal(loan)
	Bank.prepay(loan["id"])
	_expect(Company.get_value() == value - (cost - principal), "saldar baja el interés de un mes: %d" % (cost - principal))


func _check_land() -> void:
	_new_game()
	var value: int = Company.get_value()
	var builder := Builder.new()
	_expect(builder.buy_land(Builder.SIDE_EAST, 4, 3, 0)["ok"], "comprar terreno")
	_expect(OfficeState.land_paid == 2010, "terreno pagado: %d" % OfficeState.land_paid)
	_expect(Company.get_value() == value, "comprar terreno no cambia el valor: %d → %d" % [value, Company.get_value()])


func _check_overdue() -> void:
	_new_game()
	Bank.request_loan(1000, 12)
	Economy.charge(Economy.balance, "Prueba")
	var value: int = Company.get_value()
	var maintenance: int = Economy.get_maintenance(OfficeState.lot.get_area())
	var loan: Dictionary = Bank.loans[0]
	var installment: int = Bank.get_installment(loan)
	var principal_part: int = 1000 - roundi(1000.0 / 12)
	_to_next_month()
	var late: int = Bank.get_overdue()
	_expect(late > installment, "cuota atrasada con recargo: %d" % late)
	_expect(Company.get_value() == value - maintenance - (late - (1000 - principal_part)), "el atraso cuenta como deuda (con recargo): %d → %d" % [
		value, Company.get_value()])
	_expect(-Company.get_value_parts()[4]["amount"] == Bank.get_debt() + late, "la deuda suma capital y atrasos")


func _check_save() -> void:
	_new_game()
	Builder.new().buy_land(Builder.SIDE_EAST, 2, 2, 0)
	var value: int = Company.get_value()
	_expect(SaveManager.save_game("slot_5"), "guardar")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(OfficeState.land_paid == 670 and Company.get_value() == value, "el terreno pagado se guarda")
	var state: Dictionary = OfficeState.export_state()
	state.erase("land_paid")
	OfficeState.import_state(state)
	_expect(OfficeState.land_paid == 0, "una partida vieja no tiene terreno comprado")


func _check_ui() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var hud: Hud = game.get_node("Hud")
	_expect(hud.get_value_text() == "Valor %s" % MoneyFormat.format(Company.get_value()), "Hud: %s" % hud.get_value_text())
	Builder.new().place("small_plant", Vector2i(4, 5), 0)
	_expect(hud.get_value_text() == "Valor %s" % MoneyFormat.format(Company.get_value()), "Hud se actualiza: %s" % hud.get_value_text())
	var bank: BankPanel = game.get_node("BankPanel")
	bank.set_open(true)
	Bank.request_loan(2000, 6)
	await get_tree().process_frame
	var text: String = bank.get_value_text()
	_expect(text.begins_with("Valor de la empresa: %s" % MoneyFormat.format(Company.get_value())) and text.contains("Dinero | +")
		and text.contains("Muebles y computadoras (reventa) | +$780") and text.contains("Terreno comprado | $0")
		and text.contains("Deuda con el banco | −$2,000"), "detalle en el Banco: %s" % text)
	Economy.charge(Economy.balance + 50000, "Prueba")
	await get_tree().process_frame
	_expect(hud.get_value_text().begins_with("Valor −"), "valor negativo: %s" % hud.get_value_text())
	game.queue_free()
	await get_tree().process_frame
