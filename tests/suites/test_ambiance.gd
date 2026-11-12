# Prueba del hito 45: ambiente y decoración.
# Criterio: una habitación con plantas y cuadros sube la meta de ánimo; muchos escritorios
# juntos la bajan; los objetos de pared van en bordes con pared.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=ambiance
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261145
## Área abierta del local de 6×8 (fuera de la Oficina Ejecutiva): 39 m².
const OPEN_CELL := Vector2i(3, 3)
const DESK_CELL := Vector2i(4, 4)
const CHAIR_CELL := Vector2i(4, 5)

var _failures: int = 0
var _checks: int = 0
var _notices: Array[String] = []
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	EventBus.notice.connect(func(text: String) -> void: _notices.append(text))
	_check_catalog()
	_check_wall_placement()
	_check_rug()
	_check_formula()
	_check_mood()
	_check_crowding()
	_check_aquarium()
	await _check_old_save()
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


# Área de trabajo en toda la zona abierta con un puesto y un programador sentado en él.
func _work_area_with_employee() -> Dictionary:
	_expect(_builder.mark_room(Workstations.WORK_AREA, OPEN_CELL)["ok"], "marcar el Área de trabajo")
	_builder.place("simple_desk", DESK_CELL, 2)
	_builder.install_computer("basic_computer", DESK_CELL)
	_builder.place("basic_chair", CHAIR_CELL, 0)
	var employee: Dictionary = Staff.hire_directly("programmer", "junior")
	_expect(not employee.is_empty(), "contratar un programador con puesto")
	return employee


func _work_room() -> Dictionary:
	return OfficeState.rooms[OfficeState.get_room_index_at(CHAIR_CELL)]


func _room(cells: Array[Vector2i]) -> Dictionary:
	return {"type": Workstations.WORK_AREA, "cells": cells}


func _cells(width: int, depth: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(width):
		for y: int in range(depth):
			cells.append(Vector2i(x, y))
	return cells


func _item(id: String, cell: Vector2i) -> Dictionary:
	return {"id": id, "cell": cell, "rotation": 0, "assigned_to": "", "computer": ""}


func _check_catalog() -> void:
	var prices: Dictionary[String, int] = {"large_plant": 120, "painting": 80, "wall_clock": 50, "floor_lamp": 90, "rug": 150, "aquarium": 500}
	for id: String in prices:
		_expect(FurnitureCatalog.get_price(id) == prices[id] and FurnitureCatalog.get_ambiance_points(id) > 0.0,
			"adorno %s a %s con ambiente" % [id, MoneyFormat.format(prices[id])])
	_expect(FurnitureCatalog.get_ambiance_points("small_plant") == 2.0 and FurnitureCatalog.get_ambiance_points("aquarium") == 8.0,
		"planta pequeña 2 puntos, pecera 8")
	for id: String in ["painting", "wall_clock", "air_conditioner"]:
		_expect(FurnitureCatalog.is_wall_mounted(id) and FurnitureCatalog.get_footprint(id, Vector2i(3, 3), 0).is_empty(),
			"%s va en la pared y no ocupa casilla" % id)
	_expect(not FurnitureCatalog.blocks_passage("rug") and FurnitureCatalog.get_footprint("rug", Vector2i.ZERO, 0).size() == 4,
		"la alfombra ocupa 2×2 y se pisa")
	_expect(FurnitureCatalog.get_stress_relief("aquarium") == 5, "la pecera baja 5 el estrés")


func _check_wall_placement() -> void:
	_new_game()
	var blocked: int = OfficeState.get_blocking_cells().size()
	# (3, 0) mira al sur: la pared del contorno norte queda detrás.
	var result: Dictionary = _builder.place("painting", Vector2i(3, 0), 2)
	_expect(result["ok"], "cuadro en la pared del contorno: %s" % result["message"])
	_expect(not _builder.quote_place("wall_clock", Vector2i(3, 0), 2)["ok"], "una cara de pared lleva un solo objeto")
	_expect(_builder.place("wall_clock", Vector2i(3, 0), 1)["ok"], "en la otra pared de la casilla sí (la de la Oficina Ejecutiva)")
	result = _builder.quote_place("painting", DESK_CELL, 0)
	_expect(not result["ok"] and String(result["message"]).contains("pared"), "sin pared detrás no se cuelga: %s" % result["message"])
	result = _builder.quote_place("painting", Vector2i(1, 3), 2)
	_expect(not result["ok"], "en una puerta no se cuelga")
	_expect(not _builder.quote_place("painting", Vector2i(9, 9), 2)["ok"], "fuera del local no")
	# Un objeto de pared no ocupa la casilla ni estorba el paso.
	_expect(OfficeState.get_blocking_cells().size() == blocked and OfficeState.find_furniture_at(Vector2i(3, 0)) < 0, "no ocupa piso")
	_expect(_builder.place("small_plant", Vector2i(3, 0), 0)["ok"], "debajo cabe una planta")
	# Una pared con algo colgado no se vende ni se cambia por puerta.
	var wall: Array[Dictionary] = [{"edge": Vector3i(2, 0, GridEdge.AXIS_X), "kind": ""}]
	result = _builder.quote(wall)
	_expect(not result["ok"] and String(result["message"]).contains("colgado"), "no se vende una pared con un reloj: %s" % result["message"])
	_expect(not _builder.quote([{"edge": Vector3i(2, 0, GridEdge.AXIS_X), "kind": ConstructionCatalog.DOOR}] as Array[Dictionary])["ok"],
		"ni se cambia por puerta")
	var balance: int = Economy.balance
	result = _builder.sell_wall_item(Vector2i(3, 0), 1)
	_expect(result["ok"] and Economy.balance == balance + FurnitureCatalog.get_resale("wall_clock"), "vender el reloj devuelve la reventa")
	_expect(_builder.quote(wall)["ok"], "sin el reloj, la pared se puede vender")
	_expect(not _builder.sell_wall_item(Vector2i(3, 0), 1)["ok"], "no queda nada que vender ahí")
	# Comprar terreno no abre una pared con algo colgado.
	_builder.place("painting", Vector2i(5, 4), 3)
	result = _builder.quote_land(Builder.SIDE_EAST, 2, 2, 3)
	_expect(not result["ok"] and String(result["message"]).contains("colgado"), "el terreno no abre la pared del cuadro: %s" % result["message"])
	_builder.sell_wall_item(Vector2i(5, 4), 3)
	_expect(_builder.quote_land(Builder.SIDE_EAST, 2, 2, 3)["ok"], "sin cuadro sí")
	# El modo construcción elige la pared más cercana al ratón, del lado del ratón.
	var controller := BuildController.new()
	controller.set("_pointer", Vector2(3.1, -0.35))
	_expect(controller.call("_wall_slot") == [Vector2i(3, 0), 2], "cerca de la pared norte: %s" % [controller.call("_wall_slot")])
	controller.set("_pointer", Vector2(2.6, 1.0))
	_expect(controller.call("_wall_slot") == [Vector2i(3, 1), 1], "del lado este de la pared de la Oficina: %s" % [controller.call("_wall_slot")])
	controller.free()


func _check_rug() -> void:
	_new_game()
	var blocked: int = OfficeState.get_blocking_cells().size()
	var result: Dictionary = _builder.place("rug", Vector2i(3, 4), 0)
	_expect(result["ok"], "alfombra: %s" % result["message"])
	_expect(OfficeState.get_blocking_cells().size() == blocked and OfficeState.get_furniture_cells().size() == blocked + 4,
		"la alfombra ocupa 4 casillas pero no tapa el paso")
	_expect(not _builder.quote_place("basic_chair", Vector2i(4, 5), 0)["ok"], "nada encima de la alfombra")
	var finder := OfficePathfinder.new()
	finder.build(OfficeState.lot, OfficeState.get_blocking_cells(), OfficeState.edges)
	_expect(not finder.find_path(OfficeState.entrance, Vector2i(3, 4)).is_empty(), "se camina sobre ella")


func _check_formula() -> void:
	var room: Dictionary = _room(_cells(5, 4))  # 20 m²: caben 5 escritorios
	var furniture: Array[Dictionary] = []
	_expect(Ambiance.get_value(room, furniture) == 0, "sin adornos el ambiente es neutro")
	furniture.append_array([_item("large_plant", Vector2i(0, 0)), _item("painting", Vector2i(1, 0)), _item("painting", Vector2i(2, 0))])
	# (4 + 3 + 3) × 10 / 20 = 5.
	_expect(Ambiance.get_value(room, furniture) == 5, "plantas y cuadros: +5: %d" % Ambiance.get_value(room, furniture))
	_expect(Ambiance.get_value(_room(_cells(10, 4)), furniture) == 3, "en una sala del doble rinden la mitad (2.5 → 3)")
	furniture.append(_item("large_plant", Vector2i(9, 9)))
	_expect(Ambiance.get_value(room, furniture) == 5, "lo de otra habitación no cuenta")
	for x: int in range(5):
		furniture.append(_item("simple_desk", Vector2i(x, 2)))
	_expect(Ambiance.get_value(room, furniture) == 5, "5 escritorios en 20 m² no amontonan")
	furniture.append(_item("simple_desk", Vector2i(0, 3)))
	furniture.append(_item("simple_desk", Vector2i(1, 3)))
	var detail: Dictionary = Ambiance.get_detail(room, furniture)
	# 2 de más sobre 5 es 40 %: 40 / 50 × 15 = 12.
	_expect(int(detail["value"]) == -7 and int(detail["desks"]) == 7 and int(detail["allowed_desks"]) == 5,
		"2 de más: 5 − 12 = −7: %s" % [detail])
	_expect(Ambiance.describe(room, furniture) == "Ambiente −7 (amontonado: 7 escritorios, caben 5)", Ambiance.describe(room, furniture))
	furniture.append(_item("simple_desk", Vector2i(2, 3)))
	_expect(is_equal_approx(float(Ambiance.get_detail(room, furniture)["crowding"]), -15.0), "50 %% de más: −15")
	for x: int in range(5):
		furniture.append(_item("simple_desk", Vector2i(x, 1)))
	_expect(is_equal_approx(float(Ambiance.get_detail(room, furniture)["crowding"]), -15.0), "amontonar no pasa de −15")
	var big: Dictionary = _room(_cells(10, 14))  # 140 m²: caben 35
	var desks: Array[Dictionary] = []
	for index: int in range(37):
		desks.append(_item("simple_desk", Vector2i(index % 10, index / 10)))
	_expect(Ambiance.get_value(big, desks) == -2, "una sala grande con 2 de más apenas baja: %d" % Ambiance.get_value(big, desks))
	var crowded: Array[Dictionary] = []
	for index: int in range(60):
		crowded.append(_item("simple_desk", Vector2i(index % 10, index / 10)))
	_expect(Ambiance.get_value(big, crowded) == -15, "tope −15")
	var decorated: Array[Dictionary] = []
	for x: int in range(5):
		decorated.append(_item("aquarium", Vector2i(x, 0)))
	_expect(Ambiance.get_value(room, decorated) == 15, "tope +15")
	_expect(Ambiance.describe(room, []) == "Ambiente 0", "describe neutro")


func _check_mood() -> void:
	_new_game()
	var employee: Dictionary = _work_area_with_employee()
	var before: int = Staff.get_mood_target(employee)
	_expect(Staff.get_ambiance(Staff.employee_key(employee["id"])) == 0, "un puesto en 39 m² sin adornos: neutro")
	for cell: Vector2i in [Vector2i(3, 0), Vector2i(5, 0), Vector2i(0, 7)]:
		_expect(_builder.place("large_plant", cell, 0)["ok"], "planta grande en %s" % cell)
	_expect(_builder.place("painting", Vector2i(4, 0), 2)["ok"] and _builder.place("painting", Vector2i(5, 3), 3)["ok"], "dos cuadros")
	# (3 × 4 + 2 × 3) × 10 / 39 = 4.6 → 5.
	_expect(Ambiance.get_value(_work_room(), OfficeState.furniture) == 5, "ambiente +5: %d" % Ambiance.get_value(_work_room(), OfficeState.furniture))
	_expect(Staff.get_mood_target(employee) == before + 5, "plantas y cuadros suben la meta de ánimo: %d → %d" % [before, Staff.get_mood_target(employee)])
	_expect(_builder.room_status(_work_room())["message"].contains("Ambiente +5"), "el modo construcción lo dice: %s" % _builder.room_status(_work_room())["message"])
	var mood: int = int(employee["mood"])
	GameClock.fast_forward_hours(GameConstants.HOURS_PER_DAY * 5)
	_expect(int(employee["mood"]) > mood or int(employee["mood"]) >= Staff.get_mood_target(employee) - 3, "el ánimo sube hacia la meta")


func _check_crowding() -> void:
	_new_game()
	var employee: Dictionary = _work_area_with_employee()
	var before: int = Staff.get_mood_target(employee)
	# 39 m²: caben 9 escritorios. Se agregan 11 más (12 en total, 3 de más).
	var added: int = 0
	for cell: Vector2i in _work_room()["cells"]:
		if added == 11:
			break
		if OfficeState.find_furniture_at(cell) < 0 and cell != OfficeState.entrance and cell.y <= 2:
			OfficeState.furniture.append(_item("simple_desk", cell))
			added += 1
	for cell: Vector2i in [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4),
			Vector2i(0, 5), Vector2i(1, 5)]:
		if added < 11:
			OfficeState.furniture.append(_item("simple_desk", cell))
			added += 1
	# 3 de más sobre 9 es 33 %: 33 / 50 × 15 = 10.
	_expect(Ambiance.get_value(_work_room(), OfficeState.furniture) == -10, "12 escritorios en 39 m²: −10: %s" % [Ambiance.get_detail(_work_room(), OfficeState.furniture)])
	_expect(Staff.get_mood_target(employee) == before - 10, "muchos escritorios juntos bajan la meta de ánimo: %d → %d" % [before, Staff.get_mood_target(employee)])


func _check_aquarium() -> void:
	_new_game()
	var employee: Dictionary = _work_area_with_employee()
	var before: int = Staff.get_stress_target(employee)
	_expect(_builder.place("aquarium", Vector2i(3, 6), 0)["ok"], "pecera")
	_expect(Staff.get_stress_target(employee) == maxi(0, before - 5), "la pecera baja 5 la meta de estrés: %d → %d" % [before, Staff.get_stress_target(employee)])
	_builder.place("aquarium", Vector2i(0, 7), 0)
	_expect(Staff.get_stress_target(employee) == maxi(0, before - 5), "dos peceras no suman")


# Antes del hito 45 el aire acondicionado ocupaba una casilla de piso.
func _check_old_save() -> void:
	_new_game()
	_builder.mark_room(Workstations.WORK_AREA, OPEN_CELL)
	var state: Dictionary = OfficeState.export_state()
	state["furniture"].append({"id": "air_conditioner", "cell": [4, 4], "rotation": 0, "assigned_to": "", "computer": ""})
	state["furniture"].append({"id": "air_conditioner", "cell": [3, 0], "rotation": 2, "assigned_to": "", "computer": ""})
	OfficeState.import_state(state)
	var hung: Array[Dictionary] = OfficeState.furniture.filter(func(item: Dictionary) -> bool: return item["id"] == "air_conditioner")
	_expect(hung.size() == 2, "los dos siguen")
	_expect(hung[1]["cell"] == Vector2i(3, 0) and int(hung[1]["rotation"]) == 2, "el que ya estaba junto a una pared no se mueve")
	var edge: Vector3i = FurnitureCatalog.get_wall_edge(hung[0]["cell"], hung[0]["rotation"])
	_expect(OfficeState.get_edge(edge) == ConstructionCatalog.WALL and _work_room()["cells"].has(hung[0]["cell"]),
		"el del medio se cuelga en una pared de su habitación: %s" % [hung[0]])
	_expect(hung[0]["cell"] != hung[1]["cell"] or hung[0]["rotation"] != hung[1]["rotation"], "cada uno en su cara")
	# Sin habitación ni pared en su casilla: se quita y se devuelve lo pagado.
	_new_game()
	state = OfficeState.export_state()
	state["furniture"].append({"id": "air_conditioner", "cell": [4, 4], "rotation": 0, "assigned_to": "", "computer": ""})
	var balance: int = Economy.balance
	_notices.clear()
	OfficeState.import_state(state)
	await get_tree().process_frame
	_expect(not OfficeState.has_furniture("air_conditioner") and Economy.balance == balance + 800, "sin pared: se quita y devuelve $800")
	_expect(_notices.any(func(text: String) -> bool: return text.begins_with("Aire acondicionado quitado")), "y avisa: %s" % [_notices])
	# Una partida guardada con objetos de pared los conserva.
	_new_game()
	_builder.place("painting", Vector2i(4, 0), 2)
	SaveManager.save_game("slot_5")
	SaveManager.new_game()
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(OfficeState.find_wall_item(Vector2i(4, 0), 2) >= 0, "el cuadro sigue en su pared")


func _check_ui() -> void:
	_new_game()
	var employee: Dictionary = _work_area_with_employee()
	_builder.place("large_plant", Vector2i(3, 0), 0)
	_builder.place("painting", Vector2i(4, 0), 2)
	_builder.place("rug", Vector2i(0, 5), 0)
	_builder.place("floor_lamp", Vector2i(5, 6), 0)
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var card: EmployeeCard = game.get_node("EmployeeCard")
	card.open_employee(employee["id"])
	await get_tree().process_frame
	var expected: String = "Trabaja en: Área de trabajo · %s" % Ambiance.describe(_work_room(), OfficeState.furniture)
	_expect(card.get_text().contains(expected), "la ficha dice el ambiente: %s" % card.get_text())
	card.close()
	var drawn: Array[String] = []
	for view: Node in game.get_node("OfficeGrid").find_children("*", "", true, false):
		if view is FurnitureView:
			drawn.append((view as FurnitureView).item_id)
	_expect(drawn.has("painting") and drawn.has("rug") and drawn.has("floor_lamp"), "los adornos se dibujan: %s" % [drawn])
	game.queue_free()
	await get_tree().process_frame
