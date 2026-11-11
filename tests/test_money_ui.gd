# Prueba sin ventana del hito 8: cuenta empresarial, cobro del mantenimiento el día 1
# y la interfaz superpuesta mínima (dinero, reloj, velocidades y botón Construir).
# Criterio: el saldo cambia con cada compra y el día 1 se descuenta $5 por m².
# Ejecutar con:
#   Godot --headless --path . res://tests/test_money_ui.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	_check_format()
	_check_maintenance()
	_check_account()
	await _check_hud()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Avanza el reloj hasta la hora 00:00 del día indicado del mes actual o siguiente.
func _skip_to_midnight_of_next_day() -> void:
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY - GameClock.get_hour())


func _check_format() -> void:
	var cases: Dictionary = {20000: "$20,000", -240: "−$240", 999: "$999", 1234567: "$1,234,567", 0: "$0",
		1000: "$1,000"}
	for amount: int in cases:
		_expect(MoneyFormat.format(amount) == cases[amount], "formato de %d: %s" % [amount, MoneyFormat.format(amount)])
	var payroll: Dictionary = {1: 14, 14: 1, 15: 0, 16: 14, 29: 1, 30: 0}
	for day: int in payroll:
		_expect(Hud.days_until_payroll(day) == payroll[day], "días hasta la nómina desde el día %d" % day)


func _check_maintenance() -> void:
	SaveManager.new_game()
	_expect(Economy.balance == 20000 and Economy.movements.is_empty(), "la partida empieza con $20,000 y sin movimientos")
	_expect(Economy.get_maintenance(48) == 240, "el mantenimiento de 48 m² es $240")
	# Del día 1 al día 30 no se cobra nada (el primer cobro es el día 1 del mes 2).
	while GameClock.get_day() < 30:
		_skip_to_midnight_of_next_day()
	GameClock.fast_forward_hours(23)
	_expect(GameClock.get_month() == 1 and GameClock.get_hour() == 23 and Economy.balance == 20000,
		"antes del día 1 del mes 2 no se cobra: %d" % Economy.balance)
	GameClock.fast_forward_hours(1)
	_expect(GameClock.get_day() == 1 and GameClock.get_month() == 2 and Economy.balance == 20000 - 240,
		"el día 1 del mes 2 se cobran $240: %d" % Economy.balance)
	var movement: Dictionary = Economy.movements.back()
	_expect(movement == {"day": 1, "month": 2, "concept": Economy.CONCEPT_MAINTENANCE, "amount": -240},
		"movimiento del mantenimiento: %s" % [movement])
	# Un mes entero de golpe (como el salto del CEO) cobra una sola vez.
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY * GameConstants.DAYS_PER_MONTH)
	_expect(GameClock.get_month() == 3 and Economy.balance == 20000 - 480, "un mes más, un cobro más: %d" % Economy.balance)
	# El cobro es proporcional al local: $5 por m².
	OfficeState.lot_rect = Rect2i(0, 0, 10, 12)
	var before: int = Economy.balance
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY * GameConstants.DAYS_PER_MONTH)
	_expect(Economy.balance == before - 600, "un local de 120 m² paga $600: %d" % (before - Economy.balance))


func _check_account() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	builder.apply([{"edge": Vector3i(3, 3, GridEdge.AXIS_X), "kind": ConstructionCatalog.WALL}])
	_expect(Economy.balance == 19950 and Economy.movements.back()["concept"] == Builder.CONCEPT_CONSTRUCTION
		and Economy.movements.back()["amount"] == -50, "comprar una pared: %s" % [Economy.movements])
	builder.place("small_plant", Vector2i(5, 5), 0)
	_expect(Economy.balance == 19910 and Economy.movements.back()["concept"] == Builder.CONCEPT_FURNITURE,
		"comprar una planta: %d" % Economy.balance)
	builder.sell_furniture_at(Vector2i(5, 5))
	_expect(Economy.balance == 19930 and Economy.movements.back()["amount"] == 20, "vender la planta: %d" % Economy.balance)
	_expect(not Economy.spend(30000) and Economy.balance == 19930, "una compra sin dinero no se cobra")
	# Un gasto obligatorio sí puede dejar el saldo en negativo; luego no se puede comprar.
	Economy.spend(19900)
	Economy.charge(240, Economy.CONCEPT_MAINTENANCE)
	_expect(Economy.balance == -210 and not Economy.can_afford(1), "el mantenimiento deja el saldo en %d" % Economy.balance)
	var result: Dictionary = builder.place("small_plant", Vector2i(5, 5), 0)
	_expect(not result["ok"] and Economy.balance == -210, "con saldo negativo no se compra")
	# Guardar y restaurar la cuenta.
	var before: String = JSON.stringify(Economy.export_state())
	Economy.import_state(JSON.parse_string(before))
	_expect(JSON.stringify(Economy.export_state()) == before, "la cuenta no se restauró igual")


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
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


func _check_hud() -> void:
	SaveManager.new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameClock.stop()
	var hud: Hud = game.get_node("Hud")
	var panel: BuildPanel = game.get_node("BuildPanel")

	_expect(hud.get_balance_text() == "$20,000", "dinero en pantalla: %s" % hud.get_balance_text())
	var clock: String = hud.get_clock_text()
	_expect(clock.contains("Lun 1 · Mes 1") and clock.contains(" 08:0") and clock.contains("Nómina en 14 días"),
		"reloj en pantalla: %s" % clock)

	# Velocidades y pausa con el ratón.
	await _click(hud.get_speed_button(1))
	_expect(GameClock.speed_index == 1 and not GameClock.is_paused and hud.get_speed_button(1).button_pressed,
		"elegir 2x con el ratón")
	await _click(hud.get_pause_button())
	_expect(GameClock.is_paused and hud.get_pause_button().button_pressed
		and not hud.get_speed_button(1).button_pressed, "pausar con el ratón")
	await _click(hud.get_pause_button())
	_expect(not GameClock.is_paused and GameClock.speed_index == 1, "quitar la pausa recupera 2x")
	await _click(hud.get_speed_button(2))
	_expect(GameClock.speed_index == 2 and GameClock.get_time_scale() == 4.0, "elegir 4x con el ratón")
	await _click(hud.get_speed_button(0))
	_expect(GameClock.get_time_scale() == 1.0, "volver a 1x con el ratón")

	# En modo construcción el tiempo queda en pausa y los botones no lo cambian.
	await _click(panel.get_open_button())
	await get_tree().process_frame
	_expect(GameClock.is_paused and hud.get_speed_button(2).disabled, "en modo construcción los botones se desactivan")
	await _click(hud.get_speed_button(2))
	_expect(GameClock.is_paused and GameClock.speed_index == 0, "un botón de velocidad cambió el tiempo en modo construcción")

	# El dinero en pantalla cambia con cada compra.
	await _click(panel.get_tool_button("small_plant"))
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var at := InputEventMouseMotion.new()
	var cell_position: Vector2 = grid.get_canvas_transform() * grid.cell_to_world(Vector2i(5, 5))
	at.position = cell_position
	await _push(at)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = cell_position
		event.global_position = cell_position
		await _push(event)
	_expect(hud.get_balance_text() == "$19,960", "dinero tras comprar una planta: %s" % hud.get_balance_text())
	await _click(panel.get_exit_button())
	await get_tree().process_frame
	_expect(not GameClock.is_paused and not hud.get_speed_button(0).disabled, "al salir se recupera el tiempo")

	# El día 1 del mes siguiente se descuenta el mantenimiento y se ve en pantalla.
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY * GameConstants.DAYS_PER_MONTH)
	await get_tree().process_frame
	_expect(hud.get_balance_text() == "$19,720", "dinero tras el mantenimiento: %s" % hud.get_balance_text())
	game.queue_free()
	await get_tree().process_frame
