# Puerta de vidrio doble: la entrada la lleva siempre (partida nueva, empresa de prueba y partidas viejas),
# ocupa la puerta de entrada y un tramo del contorno de al lado, no se compra, no se vende ni se cambia,
# +10 al ambiente de la Recepción, cada borde dibuja su mitad, el camino de grava sale de sus dos tramos y
# con terreno frente a la entrada se corre entera (y el camino con ella).
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=glass_door_double
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DOUBLE: String = ConstructionCatalog.GLASS_DOOR_DOUBLE

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_fallback()
	await _check_in_game()
	_check_demo()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _changes(edge: Vector3i, kind: String) -> Array[Dictionary]:
	var changes: Array[Dictionary] = [{"edge": edge, "kind": kind}]
	return changes


# Casilla de fuera del local junto a un borde del contorno.
func _outside_of(edge: Vector3i) -> Vector2i:
	var cells: Array[Vector2i] = GridEdge.get_cells(edge)
	return cells[1] if OfficeState.lot.has_point(cells[0]) else cells[0]


func _check_catalog() -> void:
	_expect(ConstructionCatalog.get_display_name(DOUBLE) == "Puerta de vidrio doble", "nombre")
	_expect(ConstructionCatalog.get_price(DOUBLE) == 0, "no se compra")
	_expect(ConstructionCatalog.get_glass_door_ambiance(DOUBLE) == 10, "10 puntos de ambiente")
	_expect(ConstructionCatalog.is_door(DOUBLE) and ConstructionCatalog.is_glass_door(DOUBLE)
		and not ConstructionCatalog.is_glass_door(ConstructionCatalog.DOOR), "es puerta y de vidrio")
	_expect(int(ConstructionCatalog.get_edge_piece(DOUBLE).get("height", 0))
		> int(ConstructionCatalog.get_edge_piece(ConstructionCatalog.GLASS_DOOR).get("height", 0)), "más alta que la sencilla")
	var row: Array[Vector3i] = [Vector3i(2, 7, GridEdge.AXIS_Y), Vector3i(4, 7, GridEdge.AXIS_Y)]
	var column: Array[Vector3i] = [Vector3i(3, 6, GridEdge.AXIS_X), Vector3i(3, 8, GridEdge.AXIS_X)]
	_expect(GridEdge.get_line_neighbors(Vector3i(3, 7, GridEdge.AXIS_Y)) == row
		and GridEdge.get_line_neighbors(Vector3i(3, 7, GridEdge.AXIS_X)) == column, "bordes en línea a cada lado")
	var edges: Dictionary = {Vector3i(3, 7, GridEdge.AXIS_Y): DOUBLE, Vector3i(4, 7, GridEdge.AXIS_Y): DOUBLE}
	_expect(EdgePieceView.get_double_half(edges, Vector3i(3, 7, GridEdge.AXIS_Y)) == "a"
		and EdgePieceView.get_double_half(edges, Vector3i(4, 7, GridEdge.AXIS_Y)) == "b"
		and EdgePieceView.get_double_half({Vector3i.ZERO: ConstructionCatalog.WALL}, Vector3i.ZERO).is_empty(), "mitades a y b")
	_expect(EdgePieceView.get_sprite_name(DOUBLE, false, GridEdge.AXIS_Y, "b") == "glass_door_double_b_low_y"
		and SpriteLibrary.has_sprite("glass_door_double_a_tall_x") and SpriteLibrary.has_sprite("glass_door_double_b_low_y"),
		"sprites de las mitades")


# Sin tramo del contorno al lado (local de una casilla) queda la de vidrio sencilla.
func _check_fallback() -> void:
	var lot := Lot.from_rect(Rect2i(0, 0, 1, 1))
	var edges: Dictionary[Vector3i, String] = {}
	for edge: Vector3i in GridEdge.get_lot_outline(lot):
		edges[edge] = ConstructionCatalog.WALL
	var door: Vector3i = GridEdge.between(Vector2i(0, 0), Vector2i(0, 1))
	var partner: Vector3i = OfficeState.place_double_door(edges, lot, door)
	_expect(partner == OfficeState.NO_EDGE and edges[door] == ConstructionCatalog.GLASS_DOOR,
		"sin tramo al lado, la sencilla: %s" % edges[door])


func _check_in_game() -> void:
	var demo_before: bool = SaveManager.start_with_demo
	SaveManager.start_with_demo = false
	SaveManager.new_game()
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	Economy.earn(100000, "Prueba")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var builder: Builder = game.get_node("BuildController").builder
	var door: Vector3i = OfficeState.get_entrance_edge()
	var partner: Vector3i = OfficeState.get_double_door_partner()
	_expect(OfficeState.get_edge(door) == DOUBLE, "la partida nueva empieza con la puerta doble")
	_expect(partner == GridEdge.get_line_neighbors(door)[1] and OfficeState.get_edge(partner) == DOUBLE
		and GridEdge.is_exterior(partner, OfficeState.lot), "su otro tramo es el contorno de al lado (el de arriba)")

	# Fija: no se vende, no se cambia y no se compra en otro lado.
	var balance: int = Economy.balance
	for edge: Vector3i in [door, partner]:
		for kind: String in ["", ConstructionCatalog.DOOR, ConstructionCatalog.WALL, ConstructionCatalog.WINDOW]:
			var refused: Dictionary = builder.apply(_changes(edge, kind))
			_expect(not refused["ok"] and refused["message"] == Builder.ENTRANCE_FIXED_MESSAGE,
				"'%s' sobre la puerta doble no: %s" % [kind, refused["message"]])
	var far: Vector3i = Vector3i.ZERO
	for edge: Vector3i in GridEdge.get_lot_outline(OfficeState.lot):
		if edge != door and edge != partner and OfficeState.get_edge(edge) == ConstructionCatalog.WALL:
			far = edge
			break
	for kind: String in [DOUBLE, ConstructionCatalog.GLASS_DOOR]:
		_expect(not builder.quote(_changes(far, kind))["ok"], "%s en otra pared no" % kind)
	_expect(Economy.balance == balance and OfficeState.get_edge(door) == DOUBLE and OfficeState.get_edge(partner) == DOUBLE,
		"sigue igual y sin cobrar")
	var panel: BuildPanel = game.get_node("BuildPanel")
	_expect(panel.get_tool_button("glass_door") == null and panel.get_tool_button(DOUBLE) == null,
		"no hay botón de puertas de vidrio en Construir")

	var marked: Dictionary = builder.mark_room("reception", OfficeState.entrance)
	_expect(marked["ok"], "Recepción en la entrada: %s" % marked.get("message", ""))
	var reception: Dictionary = OfficeState.find_room("reception")
	_expect(not reception.is_empty() and OfficeState.get_room_door_ambiance(reception) == 10, "la Recepción suma 10 de ambiente")

	await get_tree().process_frame
	var halves: Array[String] = []
	for child: Node in game.get_node("OfficeGrid/Objects").get_children():
		if child is EdgePieceView and (child.edge == door or child.edge == partner):
			halves.append(child.get_sprite())
	halves.sort()
	_expect(halves.size() == 2 and halves[0].begins_with("glass_door_double_a_") and halves[1].begins_with("glass_door_double_b_"),
		"cada borde dibuja su mitad: %s" % [halves])
	var tiles: Dictionary = game.get_node("OfficeGrid").get_map_plan()["tiles"]
	_expect(tiles.get(OfficeState.get_outside_of_entrance(), "") == MapDecor.PATH and tiles.get(_outside_of(partner), "") == MapDecor.PATH,
		"el camino de grava sale de los dos tramos")

	OfficeState.import_state(OfficeState.export_state())
	_expect(OfficeState.get_edge(door) == DOUBLE and OfficeState.get_edge(partner) == DOUBLE, "se guarda y se carga")
	# Partida vieja: puerta normal en la entrada y pared al lado.
	var old: Dictionary = OfficeState.export_state()
	for entry: Array in old["edges"]:
		var edge: Vector3i = GridEdge.from_data(entry)
		if edge == door:
			entry[3] = ConstructionCatalog.DOOR
		elif edge == partner:
			entry[3] = ConstructionCatalog.WALL
	OfficeState.import_state(old)
	_expect(OfficeState.get_edge(door) == DOUBLE and OfficeState.get_double_door_partner() == partner,
		"una partida vieja carga con la puerta doble")

	# Terreno frente a la entrada: la puerta se corre entera y el camino con ella.
	var street: Vector2i = OfficeState.get_outside_of_entrance()
	var cells: Array[Vector2i] = [street, _outside_of(partner)]
	var land: Dictionary = builder.buy_land_cells(cells)
	_expect(land["ok"], "compra el terreno frente a la puerta: %s" % land["message"])
	if land["ok"]:
		var new_door: Vector3i = OfficeState.get_entrance_edge()
		var new_partner: Vector3i = OfficeState.get_double_door_partner()
		_expect(new_door != door and OfficeState.get_edge(new_door) == DOUBLE and new_partner == partner + (new_door - door),
			"con terreno la puerta doble se corre entera")
		var leftovers: int = 0
		for edge: Vector3i in OfficeState.edges:
			if OfficeState.edges[edge] == DOUBLE and edge != new_door and edge != new_partner:
				leftovers += 1
		_expect(leftovers == 0, "no queda un tramo suelto")
		await get_tree().process_frame
		tiles = game.get_node("OfficeGrid").get_map_plan()["tiles"]
		_expect(tiles.get(OfficeState.get_outside_of_entrance(), "") == MapDecor.PATH
			and tiles.get(_outside_of(new_partner), "") == MapDecor.PATH, "el camino de grava llega a la puerta nueva")
	game.queue_free()
	await get_tree().process_frame
	SaveManager.start_with_demo = demo_before


# La empresa de prueba también la trae.
func _check_demo() -> void:
	var demo_before: bool = SaveManager.start_with_demo
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	_expect(OfficeState.get_edge(OfficeState.get_entrance_edge()) == DOUBLE
		and OfficeState.get_double_door_partner() != OfficeState.NO_EDGE, "la empresa de prueba tiene la puerta doble")
	var reception: Dictionary = OfficeState.find_room("reception")
	_expect(not reception.is_empty() and OfficeState.get_room_door_ambiance(reception) == 10,
		"y su Recepción suma el ambiente")
	SaveManager.start_with_demo = demo_before
	SaveManager.new_game()
