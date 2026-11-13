# Prueba del hito 55: impresora, pizarra y ventanas.
# Criterio: la impresora mejora al contador; con pizarra la reunión inútil cuesta la mitad y
# los contratos grandes traen más plazo; una ventana sube el ambiente y no va en paredes interiores.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=office_extras
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261155
## Zona abierta del local inicial (fuera de la Oficina Ejecutiva).
const OPEN_CELL := Vector2i(3, 3)
const TABLE_CELL := Vector2i(3, 4)
## Casilla de la pared norte de la zona abierta; con rotación 2 la pared queda detrás.
const BOARD_CELL := Vector2i(4, 0)
## Bordes del contorno: norte de la Oficina Ejecutiva y este del local.
const NORTH_EDGE := Vector3i(0, -1, GridEdge.AXIS_Y)
const EAST_EDGE := Vector3i(5, 1, GridEdge.AXIS_X)
## Pared interior de la Oficina Ejecutiva.
const INNER_EDGE := Vector3i(2, 0, GridEdge.AXIS_X)

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_data()
	_check_printer()
	_check_whiteboard()
	_check_window_rules()
	_check_window_ambiance()
	_check_window_land()
	_check_save()
	await _check_ui()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	GameClock.stop()
	SaveManager.new_game()
	Staff.set_seed(SEED)
	Projects.set_seed(SEED)
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(100000, "Prueba")
	Projects.offers.clear()


# Área de trabajo de tres puestos al norte de la zona abierta (como en test_breaks).
func _work_area() -> void:
	var y: int = GridEdge.AXIS_Y
	var walls: Array[Dictionary] = [
		{"edge": Vector3i(3, 2, y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 2, y), "kind": ConstructionCatalog.DOOR},
		{"edge": Vector3i(5, 2, y), "kind": ConstructionCatalog.WALL},
	]
	_expect(_builder.apply(walls)["ok"], "paredes del área de trabajo")
	_expect(_builder.mark_room(Workstations.WORK_AREA, Vector2i(4, 1))["ok"], "marcar el área de trabajo")
	for x: int in [3, 4, 5]:
		_expect(_builder.place("simple_desk", Vector2i(x, 0), 2)["ok"], "escritorio en %d" % x)
		_expect(_builder.place("basic_chair", Vector2i(x, 1), 0)["ok"], "silla en %d" % x)
		_expect(_builder.install_computer("basic_computer", Vector2i(x, 0))["ok"], "computadora en %d" % x)


func _meeting_room() -> void:
	Projects.meeting_room_unlocked = true
	_expect(_builder.mark_room("meeting_room", OPEN_CELL)["ok"], "marcar la Sala de reuniones")
	_expect(_builder.place("meeting_table", TABLE_CELL, 0)["ok"], "mesa de reuniones")


func _check_data() -> void:
	_expect(FurnitureCatalog.get_price("printer") == 350 and FurnitureCatalog.get_item("printer")["name"] == "Impresora",
		"impresora a $350")
	_expect(is_equal_approx(FurnitureCatalog.get_number("printer", "accountant_boost"), 1.25), "la impresora vale ×1.25")
	_expect(FurnitureCatalog.get_price("whiteboard") == 250 and FurnitureCatalog.is_wall_mounted("whiteboard")
		and FurnitureCatalog.get_number("whiteboard", "meeting_board") > 0.0, "pizarra de pared a $250")
	_expect(is_equal_approx(float(ContractCatalog.get_meetings("board_days_factor")), 1.1), "la pizarra da 10 % más de plazo")
	_expect(ConstructionCatalog.get_price(ConstructionCatalog.WINDOW) == 200
		and ConstructionCatalog.get_display_name(ConstructionCatalog.WINDOW) == "Ventana"
		and ConstructionCatalog.get_refund(ConstructionCatalog.WINDOW) == 100, "ventana a $200, se devuelven $100")
	_expect(ConstructionCatalog.get_window_ambiance() == 4, "la ventana suma 4 puntos de ambiente")


func _check_printer() -> void:
	_new_game()
	_work_area()
	_expect(is_equal_approx(Staff.get_printer_factor(), 1.0), "sin contador ni impresora: ×1")
	Company.stage = 1
	var accountant: Dictionary = Staff.hire_directly("accountant", "junior")
	_expect(not accountant.is_empty(), "contador contratado")
	var base_maintenance: float = Staff.get_maintenance_discount()
	var base_rate: float = Staff.get_loan_rate_discount()
	_expect(base_maintenance > 0.0 and base_rate > 0.0, "el contador ya descuenta sin impresora")
	# En otra habitación (la zona abierta, que no es un Área de trabajo) no cuenta.
	_expect(_builder.place("printer", Vector2i(4, 5), 0)["ok"], "impresora en la zona abierta")
	_expect(is_equal_approx(Staff.get_printer_factor(), 1.0), "fuera del Área de trabajo no ayuda")
	_expect(_builder.sell_furniture_at(Vector2i(4, 5))["ok"], "vender esa impresora")
	var placed: Dictionary = _builder.place("printer", Vector2i(5, 2), 0)
	_expect(placed["ok"], "impresora en el Área de trabajo: %s" % placed["message"])
	_expect(is_equal_approx(Staff.get_printer_factor(), 1.25), "con impresora: ×1.25")
	_expect(is_equal_approx(Staff.get_maintenance_discount(), base_maintenance * 1.25),
		"mantenimiento: %.4f" % Staff.get_maintenance_discount())
	_expect(is_equal_approx(Staff.get_loan_rate_discount(), base_rate * 1.25), "tasa: %.4f" % Staff.get_loan_rate_discount())
	# El cobro del pago atrasado: 3 días → 2 con impresora.
	var effect: Dictionary = {"type": "withhold", "days": 3, "by_accountant": true}
	_expect(int(Events._resolve(effect, {"amount": 900})["days"]) == 2, "con impresora el contador cobra en 2 días")
	_expect(int(Events._resolve({"type": "withhold", "days": 15}, {"amount": 900})["days"]) == 15,
		"sin el contador el pago sigue en 15 días")
	var option_effect: Dictionary = _late_payment_accountant_effect()
	_expect(bool(option_effect.get("by_accountant", false)) and int(option_effect["days"]) == 3,
		"la opción del contador en data/events.json usa la impresora")
	# Sin contador la impresora no hace nada.
	Staff.employees.clear()
	_expect(is_equal_approx(Staff.get_printer_factor(), 1.0) and is_zero_approx(Staff.get_maintenance_discount()),
		"sin contador, nada")
	_expect(int(Events._resolve(effect, {"amount": 900})["days"]) == 3, "sin contador vuelven a ser 3 días")


func _late_payment_accountant_effect() -> Dictionary:
	for event: Dictionary in Events._events_data()["events"]:
		if event["id"] == "late_payment":
			for option: Dictionary in event["options"]:
				for effect: Dictionary in option["effects"]:
					if effect["type"] == "withhold" and int(effect["days"]) < 15:
						return effect
	return {}


func _meeting_effect() -> Dictionary:
	for event: Dictionary in Events._events_data()["events"]:
		if event["id"] == "useless_meeting":
			return event["options"][0]["effects"][0]
	return {}


func _check_whiteboard() -> void:
	_new_game()
	var effect: Dictionary = _meeting_effect()
	_expect(effect.has("halved_by") and int(effect["hours"]) == 2, "la reunión inútil se acorta con la pizarra")
	_expect(int(Events._resolve(effect, {})["hours"]) == 2, "sin pizarra se pierden 2 horas")
	Projects.set_seed(SEED)
	var plain_large: Dictionary = Projects._make_offer(GameClock.get_day_count(), "large")
	Projects.set_seed(SEED)
	var plain_small: Dictionary = Projects._make_offer(GameClock.get_day_count(), "small")
	_meeting_room()
	var placed: Dictionary = _builder.place("whiteboard", BOARD_CELL, 2)
	_expect(placed["ok"], "pizarra en la pared de la sala: %s" % placed["message"])
	_expect(Projects.has_room_item("meeting_room", "meeting_board"), "la sala tiene pizarra")
	_expect(int(Events._resolve(effect, {})["hours"]) == 1, "con pizarra se pierde 1 hora")
	Projects.set_seed(SEED)
	var board_large: Dictionary = Projects._make_offer(GameClock.get_day_count(), "large")
	_expect(int(board_large["days"]) == ceili(int(plain_large["days"]) * 1.1) and int(board_large["days"]) > int(plain_large["days"]),
		"el grande trae más plazo: %d → %d" % [plain_large["days"], board_large["days"]])
	_expect(int(board_large["total_points"]) == int(plain_large["total_points"]) and int(board_large["pay"]) == int(plain_large["pay"]),
		"lo demás de la oferta no cambia")
	Projects.set_seed(SEED)
	var board_elite: Dictionary = Projects._make_offer(GameClock.get_day_count(), "elite")
	Projects.set_seed(SEED)
	_expect(Projects._offer_days("elite", 20) == 22 and Projects._offer_days("medium", 20) == 20,
		"el de élite también, el mediano no (élite %d días)" % board_elite["days"])
	Projects.set_seed(SEED)
	var board_small: Dictionary = Projects._make_offer(GameClock.get_day_count(), "small")
	_expect(int(board_small["days"]) == int(plain_small["days"]), "el pequeño sigue igual")
	# Sin mesa la sala no funciona y la pizarra no cuenta.
	OfficeState.furniture.remove_at(OfficeState.find_furniture_at(TABLE_CELL))
	_expect(not Projects.has_room_item("meeting_room", "meeting_board"), "en una sala que no funciona no cuenta")
	_expect(int(Events._resolve(effect, {})["hours"]) == 2, "otra vez 2 horas")
	_expect(Projects._offer_days("large", 20) == 20, "ni da plazo")


func _check_window_rules() -> void:
	_new_game()
	var window: String = ConstructionCatalog.WINDOW
	var result: Dictionary = _builder.quote([{"edge": INNER_EDGE, "kind": window}])
	_expect(not result["ok"] and String(result["message"]).contains("exteriores"), "no va en una pared interior: %s" % result["message"])
	result = _builder.quote([{"edge": Vector3i(3, 3, GridEdge.AXIS_X), "kind": window}])
	_expect(not result["ok"] and String(result["message"]).contains("exteriores"), "ni en un borde libre de dentro")
	var entrance_edge: Vector3i = GridEdge.between(OfficeState.entrance, OfficeState.get_outside_of_entrance())
	_expect(not _builder.quote([{"edge": entrance_edge, "kind": window}])["ok"], "ni en la puerta de entrada")
	_expect(not _builder.quote([{"edge": NORTH_EDGE, "kind": ConstructionCatalog.DOOR}])["ok"], "el contorno sigue sin puertas nuevas")
	var rooms_before: String = _rooms_text()
	var balance: int = Economy.balance
	result = _builder.apply([{"edge": NORTH_EDGE, "kind": window}])
	_expect(result["ok"] and int(result["cost"]) == 200 and Economy.balance == balance - 200,
		"ventana en el contorno por $200 (la pared no se devuelve): %s" % result["message"])
	_expect(OfficeState.get_edge(NORTH_EDGE) == window and OfficeState.blocks_passage(NORTH_EDGE), "la ventana cierra el paso")
	_expect(_rooms_text() == rooms_before, "las habitaciones no cambian: %s" % _rooms_text())
	_expect(not _builder.quote([{"edge": NORTH_EDGE, "kind": window}])["ok"], "poner otra igual no cambia nada")
	# Nada se cuelga en una ventana, ni se cambia por ventana una pared con algo colgado.
	_expect(FurnitureCatalog.get_wall_edge(Vector2i(0, 0), 2) == NORTH_EDGE, "el cuadro de (0, 0) mira a esa pared")
	_expect(not _builder.quote_place("painting", Vector2i(0, 0), 2)["ok"], "no se cuelga un cuadro en la ventana")
	_expect(_builder.place("painting", Vector2i(1, 0), 2)["ok"], "cuadro en la pared de al lado")
	result = _builder.quote([{"edge": Vector3i(1, -1, GridEdge.AXIS_Y), "kind": window}])
	_expect(not result["ok"] and String(result["message"]).contains("colgado"), "ni ventana donde hay un cuadro")
	# Quitarla deja pared y devuelve la mitad.
	balance = Economy.balance
	result = _builder.apply([{"edge": NORTH_EDGE, "kind": ""}])
	_expect(result["ok"] and int(result["cost"]) == -100 and Economy.balance == balance + 100, "vender la ventana devuelve $100")
	_expect(OfficeState.get_edge(NORTH_EDGE) == ConstructionCatalog.WALL, "queda la pared")
	_expect(not _builder.quote([{"edge": NORTH_EDGE, "kind": ""}])["ok"], "la pared del contorno sigue sin venderse")
	# La herramienta Pared sobre una ventana también la vuelve pared.
	_builder.apply([{"edge": NORTH_EDGE, "kind": window}])
	result = _builder.apply([{"edge": NORTH_EDGE, "kind": ConstructionCatalog.WALL}])
	_expect(result["ok"] and int(result["cost"]) == -100 and OfficeState.get_edge(NORTH_EDGE) == ConstructionCatalog.WALL,
		"pared sobre la ventana: %s" % result["message"])
	# Las ventanas no cuentan como bienes (como paredes y pisos).
	var assets: int = Bank.get_assets_value()
	_builder.apply([{"edge": NORTH_EDGE, "kind": window}])
	_expect(Bank.get_assets_value() == assets, "la ventana no suma al valor")


func _rooms_text() -> String:
	var parts: Array[String] = []
	for room: Dictionary in OfficeState.rooms:
		parts.append("%s %s" % [room["type"], room["cells"]])
	return "; ".join(parts)


func _check_window_ambiance() -> void:
	_new_game()
	var office: Dictionary = OfficeState.find_room("executive_office")
	_expect(OfficeState.count_room_windows(office) == 0, "la Oficina Ejecutiva empieza sin ventanas")
	var before: int = Ambiance.get_value(office, OfficeState.furniture)
	var ceo_before: int = Staff.get_ambiance("ceo")
	_expect(_builder.apply([{"edge": NORTH_EDGE, "kind": ConstructionCatalog.WINDOW}])["ok"], "ventana al norte")
	office = OfficeState.find_room("executive_office")
	_expect(OfficeState.count_room_windows(office) == 1, "una ventana da a la oficina")
	var detail: Dictionary = Ambiance.get_detail(office, OfficeState.furniture, 1)
	_expect(is_equal_approx(float(detail["points"]), 4.0), "la ventana suma 4 puntos")
	_expect(Ambiance.get_value(office, OfficeState.furniture, 1) == before + 4, "ambiente %d → %d (40 / 9 m²)" % [
		before, Ambiance.get_value(office, OfficeState.furniture, 1)])
	_expect(Staff.get_ambiance("ceo") == ceo_before + 4, "el CEO trabaja con más ambiente: %d" % Staff.get_ambiance("ceo"))
	var open_room: Dictionary = {"cells": [Vector2i(3, 3)]}
	_expect(OfficeState.count_room_windows(open_room) == 0, "no da a otra habitación")
	_expect(_builder.apply([{"edge": Vector3i(-1, 0, GridEdge.AXIS_X), "kind": ConstructionCatalog.WINDOW}])["ok"],
		"otra ventana al oeste")
	_expect(OfficeState.count_room_windows(OfficeState.find_room("executive_office")) == 2, "dos ventanas")
	_expect(Ambiance.describe(OfficeState.find_room("executive_office"), OfficeState.furniture, 2).begins_with("Ambiente +"),
		"el texto del ambiente")


func _check_window_land() -> void:
	_new_game()
	_expect(_builder.apply([{"edge": EAST_EDGE, "kind": ConstructionCatalog.WINDOW}])["ok"], "ventana al este")
	_expect(_builder.apply([{"edge": NORTH_EDGE, "kind": ConstructionCatalog.WINDOW}])["ok"], "ventana al norte")
	var quote: Dictionary = _builder.quote_land(Builder.SIDE_EAST, 4, 3, 0)
	_expect(quote["ok"] and int(quote["window_refund"]) == 100 and String(quote["message"]).contains("1 ventana"),
		"el terreno avisa que devuelve la ventana: %s" % quote["message"])
	var balance: int = Economy.balance
	var bought: Dictionary = _builder.buy_land(Builder.SIDE_EAST, 4, 3, 0)
	_expect(bought["ok"], "comprar terreno al este")
	_expect(Economy.balance == balance - int(bought["cost"]) + 100, "se devuelven $100 de la ventana")
	_expect(OfficeState.get_edge(EAST_EDGE).is_empty(), "el borde abierto queda libre")
	_expect(OfficeState.get_edge(NORTH_EDGE) == ConstructionCatalog.WINDOW, "la del norte sigue")
	_expect(String(bought["message"]).contains("ventanas"), "el mensaje lo dice: %s" % bought["message"])
	_expect(not _builder.quote_land(Builder.SIDE_EAST, 4, 3, 0).has("window_refund")
		or int(_builder.quote_land(Builder.SIDE_EAST, 4, 3, 0).get("window_refund", 0)) == 0, "otro terreno ya no devuelve")


func _check_save() -> void:
	_new_game()
	_builder.apply([{"edge": NORTH_EDGE, "kind": ConstructionCatalog.WINDOW}])
	var state: Dictionary = OfficeState.export_state()
	_new_game()
	_expect(OfficeState.get_edge(NORTH_EDGE) == ConstructionCatalog.WALL, "partida nueva sin ventana")
	OfficeState.import_state(state)
	_expect(OfficeState.get_edge(NORTH_EDGE) == ConstructionCatalog.WINDOW, "la ventana se guarda")


func _check_ui() -> void:
	_new_game()
	_builder.apply([{"edge": NORTH_EDGE, "kind": ConstructionCatalog.WINDOW}])
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	var panel: BuildPanel = game.get_node("BuildPanel")
	_expect(panel.get_tool_button(BuildController.TOOL_WINDOW).text.contains("Ventana"),
		"botón Ventana en el modo construcción: %s" % panel.get_tool_button(BuildController.TOOL_WINDOW).text)
	var views: Array[Node] = game.find_children("*", "EdgePieceView", true, false)
	var found: bool = false
	for view: Node in views:
		if (view as EdgePieceView).edge == NORTH_EDGE and (view as EdgePieceView).kind == ConstructionCatalog.WINDOW:
			found = true
	_expect(found, "la ventana se dibuja")
	game.queue_free()
	await get_tree().process_frame
