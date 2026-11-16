# Prueba del hito 25: compra de terreno.
# Criterio: comprar 4 × 3 al este cuesta $2,010, el local suma 12 m² y el mantenimiento
# sube $60 al mes; no se puede comprar fuera del solar ni sin tocar el local; los
# caminos llegan al terreno nuevo.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=land
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
	_check_lot()
	_check_east()
	_check_refused()
	_check_notch()
	_check_rooms()
	_check_save()
	await _check_panel()

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


func _sum(concept: String) -> int:
	var total: int = 0
	for movement: Dictionary in Economy.movements:
		if movement["concept"] == concept:
			total += int(movement["amount"])
	return total


func _pathfinder() -> OfficePathfinder:
	var finder := OfficePathfinder.new()
	finder.build(OfficeState.lot, OfficeState.get_furniture_cells(), OfficeState.edges)
	return finder


func _check_lot() -> void:
	var lot := Lot.from_rect(Rect2i(0, 0, 2, 2))
	_expect(lot.get_area() == 4 and lot.has_point(Vector2i(1, 1)) and not lot.has_point(Vector2i(2, 0)), "local de 2 × 2")
	_expect(lot.get_outline().size() == 8, "contorno de 8 bordes: %d" % lot.get_outline().size())
	var grown: Lot = lot.with_cells([Vector2i(2, 0)] as Array[Vector2i])
	_expect(grown.get_area() == 5 and grown.get_bounds() == Rect2i(0, 0, 3, 2) and lot.get_area() == 4, "crece sin tocar el original")
	_expect(grown.get_outline().size() == 10, "contorno en L: %d" % grown.get_outline().size())
	_expect(Lot.from_cells(grown.get_cells()).equals(grown), "desde casillas")


func _check_east() -> void:
	_new_game()
	var builder := Builder.new()
	var area: int = OfficeState.lot.get_area()
	var balance: int = Economy.balance
	var maintenance: int = Economy.get_maintenance(area)
	var quote: Dictionary = builder.quote_land(Builder.SIDE_EAST, 4, 3, 0)
	_expect(quote["ok"] and quote["cost"] == 2010 and (quote["new_cells"] as Array).size() == 12, "4 × 3 al este cuesta $2,010: %s" % quote)
	_expect(String(quote["message"]).contains("$2,010") and String(quote["message"]).contains("$1,800 + cerámica $210") and String(quote["message"]).contains("+$60"), "vista previa: %s" % quote["message"])
	var result: Dictionary = builder.buy_land(Builder.SIDE_EAST, 4, 3, 0)
	_expect(result["ok"] and Economy.balance == balance - 2010 and _sum(Builder.CONCEPT_LAND) == -2010, "comprado: %s" % result)
	_expect(OfficeState.lot.get_area() == area + 12, "el local suma 12 m²: %d" % OfficeState.lot.get_area())
	_expect(Economy.get_maintenance(OfficeState.lot.get_area()) - maintenance == 60, "el mantenimiento sube $60")
	# El terreno nuevo: al este del local (x 6 a 8, filas 0 a 3), con cerámica.
	for x: int in range(6, 9):
		for y: int in range(0, 4):
			_expect(OfficeState.lot.has_point(Vector2i(x, y)) and OfficeState.get_floor(Vector2i(x, y)) == "ceramic",
				"casilla nueva %s con cerámica" % Vector2i(x, y))
	# El contorno se corre: el borde compartido queda abierto y el nuevo tiene pared.
	var x_axis: int = GridEdge.AXIS_X
	var y_axis: int = GridEdge.AXIS_Y
	_expect(OfficeState.get_edge(Vector3i(5, 0, x_axis)).is_empty() and OfficeState.get_edge(Vector3i(5, 2, x_axis)).is_empty(),
		"el borde compartido queda abierto")
	_expect(OfficeState.get_edge(Vector3i(5, 4, x_axis)) == ConstructionCatalog.WALL, "el resto del borde este sigue con pared")
	_expect(OfficeState.get_edge(Vector3i(8, 1, x_axis)) == ConstructionCatalog.WALL
		and OfficeState.get_edge(Vector3i(7, -1, y_axis)) == ConstructionCatalog.WALL
		and OfficeState.get_edge(Vector3i(7, 3, y_axis)) == ConstructionCatalog.WALL, "pared en el contorno nuevo")
	for edge: Vector3i in OfficeState.lot.get_outline():
		_expect(not OfficeState.get_edge(edge).is_empty(), "todo el contorno cerrado: %s" % edge)
	# Los caminos llegan al terreno nuevo.
	_expect(not _pathfinder().find_path(OfficeState.entrance, Vector2i(8, 0)).is_empty(), "se llega caminando al terreno nuevo")
	# El mantenimiento del mes siguiente cobra los metros nuevos.
	var before: int = Economy.balance
	GameClock.fast_forward_hours((GameConstants.DAYS_PER_MONTH - GameClock.get_day_count()) * GameConstants.HOURS_PER_DAY - GameClock.get_hour())
	_expect(-_sum(Economy.CONCEPT_MAINTENANCE) == maintenance + 60, "mantenimiento de %d m²: %d" % [OfficeState.lot.get_area(), -_sum(Economy.CONCEPT_MAINTENANCE)])
	_expect(before - Economy.balance >= maintenance + 60, "se cobra")


func _check_refused() -> void:
	_new_game()
	var builder := Builder.new()
	var quote: Dictionary = builder.quote_land(Builder.SIDE_EAST, 4, 40, 0)
	# Lo que se sale del solar se deja afuera; se compra el resto.
	var inside: bool = (quote["new_cells"] as Array).all(func(cell: Vector2i) -> bool: return OfficeState.site_rect.has_point(cell))
	_expect(quote["ok"] and inside and (quote["new_cells"] as Array).size() < 4 * 40, "lo de fuera del solar no se compra: %s" % quote["message"])
	quote = builder.quote_land(Builder.SIDE_EAST, 4, 3, 8)
	_expect(not quote["ok"] and String(quote["message"]).contains("tocar el local"), "no sin tocar el local: %s" % quote["message"])
	quote = builder.quote_land(Builder.SIDE_SOUTH, 3, 2, 2)
	# Frente a la puerta sí se compra: la entrada se corre derecho al borde nuevo (sin hueco de calle).
	var street: Vector2i = OfficeState.get_outside_of_entrance()
	var old_entrance: Vector2i = OfficeState.entrance
	_expect(quote["ok"] and (quote["new_cells"] as Array).has(street) and quote["entrance"] == old_entrance + Vector2i(0, 2)
		and String(quote["message"]).contains("puerta de entrada"), "se compra frente a la puerta y la entrada se corre: %s" % quote["message"])
	var moved: Dictionary = builder.buy_land(Builder.SIDE_SOUTH, 3, 2, 2)
	_expect(moved["ok"] and OfficeState.entrance == old_entrance + Vector2i(0, 2) and OfficeState.lot.has_point(street),
		"la entrada queda en el borde nuevo: %s" % OfficeState.entrance)
	_expect(ConstructionCatalog.is_door(OfficeState.get_edge(OfficeState.get_entrance_edge()))
		and OfficeState.get_outside_of_entrance() == OfficeState.entrance + Vector2i(0, 1)
		and not OfficeState.lot.has_point(OfficeState.get_outside_of_entrance()), "con su puerta hacia afuera")
	_expect(OfficeState.get_edge(GridEdge.between(old_entrance, street)).is_empty(), "donde estaba la puerta queda abierto")
	_expect(not _pathfinder().find_path(OfficeState.entrance, Vector2i(0, 0)).is_empty(), "de la entrada nueva se llega al local")
	_new_game()
	quote = builder.quote_land(Builder.SIDE_EAST, 0, 3, 0)
	_expect(not quote["ok"], "medida mínima 1 × 1")
	Economy.charge(Economy.balance - 100, "Prueba")
	quote = builder.quote_land(Builder.SIDE_EAST, 1, 1, 0)
	_expect(quote["ok"] == false and String(quote["message"]).contains("No alcanza"), "sin dinero: %s" % quote["message"])
	var area: int = OfficeState.lot.get_area()
	builder.buy_land(Builder.SIDE_EAST, 1, 1, 0)
	_expect(OfficeState.lot.get_area() == area and Economy.balance == 100, "si no se puede, no cambia nada")
	# Los otros lados: oeste y norte crecen hacia coordenadas negativas.
	_new_game()
	quote = builder.quote_land(Builder.SIDE_WEST, 2, 1, 5)
	var cells: Array[Vector2i] = quote["new_cells"]
	_expect(quote["ok"] and cells.has(Vector2i(-1, 5)) and cells.has(Vector2i(-1, 6)) and cells.size() == 2, "oeste: %s" % [cells])
	quote = builder.quote_land(Builder.SIDE_NORTH, 2, 2, 4)
	cells = quote["new_cells"]
	_expect(quote["ok"] and cells.has(Vector2i(4, -1)) and cells.has(Vector2i(5, -2)) and cells.size() == 4, "norte: %s" % [cells])


# Con el local en L, una franja larga rellena el hueco: solo se cobra lo nuevo.
func _check_notch() -> void:
	_new_game()
	var builder := Builder.new()
	builder.buy_land(Builder.SIDE_EAST, 3, 2, 0)
	var quote: Dictionary = builder.quote_land(Builder.SIDE_EAST, 8, 2, 0)
	var cells: Array[Vector2i] = quote["new_cells"]
	_expect(quote["ok"] and cells.size() == 10 and quote["cost"] == 1675 and cells.has(Vector2i(6, 3)) and cells.has(Vector2i(7, 7)),
		"rellena el hueco y cobra 10 m²: %s" % quote)
	builder.buy_land(Builder.SIDE_EAST, 8, 2, 0)
	_expect(OfficeState.lot.get_area() == 48 + 6 + 10 and OfficeState.lot.get_bounds() == Rect2i(0, 0, 8, 8), "local de 8 × 8")
	for edge: Vector3i in OfficeState.lot.get_outline():
		_expect(not OfficeState.get_edge(edge).is_empty(), "contorno cerrado: %s" % edge)
	_expect(OfficeState.get_edge(Vector3i(5, 4, GridEdge.AXIS_X)).is_empty(), "el viejo borde este queda abierto")


func _check_rooms() -> void:
	_new_game()
	var builder := Builder.new()
	# Una franja al norte de todo el local juntaría la Oficina Ejecutiva con el resto.
	var quote: Dictionary = builder.quote_land(Builder.SIDE_NORTH, 6, 1, 0)
	# Ahora se puede: el borde se abre al espacio común y la oficina conserva su pared.
	var office_before: int = 0
	for room: Dictionary in OfficeState.rooms:
		if room["type"] == "executive_office":
			office_before = (room["cells"] as Array).size()
	var office_after: int = -1
	for room: Dictionary in quote.get("rooms", []):
		if room["type"] == "executive_office":
			office_after = (room["cells"] as Array).size()
	_expect(quote["ok"] and office_after == office_before, "la Oficina Ejecutiva no se junta con el resto: %s (%d → %d)" % [
		quote["message"], office_before, office_after])
	# Solo encima de ella, la oficina crece con el terreno.
	var result: Dictionary = builder.buy_land(Builder.SIDE_NORTH, 3, 1, 0)
	var room: Dictionary = OfficeState.find_room("executive_office")
	_expect(result["ok"] and (room["cells"] as Array).size() == 12 and (room["cells"] as Array).has(Vector2i(1, -1)),
		"la Oficina Ejecutiva crece: %s / %s" % [result["message"], room])
	_expect(builder.room_status(room)["ok"], "y sigue funcionando")


func _check_save() -> void:
	_new_game()
	var builder := Builder.new()
	builder.buy_land(Builder.SIDE_EAST, 4, 3, 0)
	var before: String = JSON.stringify(OfficeState.export_state())
	_expect(SaveManager.save_game("slot_5"), "guardar")
	SaveManager.new_game()
	_expect(OfficeState.lot.get_area() == 48, "partida nueva con el local inicial")
	_expect(SaveManager.load_game("slot_5"), "cargar")
	_expect(JSON.stringify(OfficeState.export_state()) == before and OfficeState.lot.get_area() == 60, "el local vuelve igual")
	# Una partida de antes del hito 25 solo tiene el rectángulo.
	var state: Dictionary = OfficeState.export_state()
	state.erase("lot_cells")
	state["lot"] = [0, 0, 6, 8]
	OfficeState.import_state(state)
	_expect(OfficeState.lot.get_area() == 48 and OfficeState.lot_rect == Rect2i(0, 0, 6, 8), "partida vieja: rectángulo")


func _check_panel() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var panel: BuildPanel = game.get_node("BuildPanel")
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var status: Array[String] = []
	game.get_node("BuildController").status_changed.connect(func(text: String) -> void: status.append(text))
	panel.set_build_mode(true)
	_expect(not panel.is_land_row_visible(), "la fila del terreno empieza oculta")
	panel.select_tool(BuildController.TOOL_LAND)
	_expect(panel.is_land_row_visible(), "la herramienta Terreno muestra su fila")
	var controller: BuildController = game.get_node("BuildController")
	var rect: Rect2i = OfficeState.lot_rect
	var corner: Vector2i = Vector2i(rect.end.x, rect.position.y)
	# Arrastrar ya no elige terreno suelto: solo se compran los lotes marcados.
	var free_area: int = OfficeState.lot.get_area()
	controller.set("_pointer", Vector2(corner + Vector2i(9, 0)))
	controller.call("_land_input", _mouse_button(true))
	controller.set("_pointer", Vector2(corner + Vector2i(12, 3)))
	controller.call("_land_input", _mouse_button(false))
	_expect(OfficeState.lot.get_area() == free_area, "arrastrar lejos del local no compra nada")
	_expect(not bool(controller.buy_land_plot_at(corner + Vector2i(9, 0))["ok"]), "un lote que no toca el local no se compra")
	# Lotes marcados (fase 8): el solar se parte en lotes de 4×4 y los que tocan el local se compran con un clic.
	var plots: Array[Dictionary] = controller.get_land_plots()
	_expect(plots.size() >= 4, "hay lotes marcados alrededor del local: %d" % plots.size())
	var all_touch: bool = true
	for plot: Dictionary in plots:
		all_touch = all_touch and not (plot["new_cells"] as Array).is_empty() and int(plot["cost"]) > 0
	_expect(all_touch, "cada lote tiene casillas que comprar y su precio")
	_expect(Builder.get_plot_cells(Vector2i(5, 6)).size() == 16 and Builder.get_plot_cells(Vector2i(5, 6))[0] == Vector2i(4, 4)
		and Builder.get_plot_cells(Vector2i(-1, -1))[0] == Vector2i(-4, -4), "los lotes van alineados con la casilla (0, 0)")
	var plot_cell: Vector2i = (plots[0]["new_cells"] as Array)[0]
	var area: int = OfficeState.lot.get_area()
	var price: int = int(plots[0]["cost"])
	var balance: int = Economy.balance
	# Un clic (apretar y soltar en la misma casilla) sobre un lote lo compra.
	controller.set("_pointer", Vector2(plot_cell))
	controller.call("_land_input", _mouse_button(true))
	controller.call("_land_input", _mouse_button(false))
	_expect(OfficeState.lot.get_area() == area + (plots[0]["new_cells"] as Array).size() and grid.is_in_lot(plot_cell)
		and Economy.balance == balance - price, "un clic en un lote lo compra: %s" % status[-1])
	_expect(status[-1].contains("Compraste"), "y avisa: %s" % status[-1])
	var still: bool = false
	for plot: Dictionary in controller.get_land_plots():
		still = still or (plot["new_cells"] as Array).has(plot_cell)
	_expect(not still and not controller.get_land_plots().is_empty(), "los lotes se vuelven a calcular")
	# Cada lote marcado toca el local: uno de más afuera solo aparece al comprar el anterior.
	var touching: bool = true
	for plot: Dictionary in controller.get_land_plots():
		var touches: bool = false
		for cell: Vector2i in plot["new_cells"]:
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				touches = touches or grid.is_in_lot(cell + step)
		touching = touching and touches
	_expect(touching, "todos los lotes marcados tocan el local")
	# Sin dinero el lote se marca pero no se compra.
	Economy.charge(Economy.balance - 100, "Prueba")
	controller.refresh_land_plots()
	var poor: Dictionary = controller.get_land_plots()[0]
	area = OfficeState.lot.get_area()
	var refused: Dictionary = controller.buy_land_plot_at((poor["new_cells"] as Array)[0])
	_expect(not bool(poor["ok"]) and not bool(refused["ok"]) and String(refused["message"]).contains("No alcanza")
		and OfficeState.lot.get_area() == area, "sin dinero no se compra: %s" % refused["message"])
	_expect(not bool(controller.buy_land_plot_at(Vector2i(1, 1))["ok"]), "un clic dentro del local no compra nada")
	panel.select_tool(BuildController.TOOL_WALL)
	_expect(controller.get_land_plots().is_empty(), "con otra herramienta no hay lotes marcados")
	_expect(not panel.is_land_row_visible(), "otra herramienta oculta la fila")
	panel.set_build_mode(false)
	game.queue_free()
	await get_tree().process_frame


func _mouse_button(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event
