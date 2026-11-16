# Nueva partida desde el menú con un clic y el estado inicial: local, Oficina Ejecutiva, dinero y reloj.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=new_game
extends Node

## Lo escucha test_all: fallos y comprobaciones.
signal finished(failures: int, checks: int)

const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const GAME_SCENE_PATH: String = "res://scenes/main.tscn"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Carpeta aparte para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	await get_tree().process_frame

	_expect(not OfficeState.has_game(), "al abrir el juego ya había una partida")
	_expect(not GameClock.is_processing(), "el reloj corre antes de empezar la partida")

	await _open_menu_and_click_new_game()
	_check_new_game_state()

	# Jugar un poco y volver al menú: la partida nueva empieza de cero.
	Economy.balance = 5
	GameClock.set_speed_index(2)
	GameClock.advance(1000.0)
	await _open_menu_and_click_new_game()
	_check_new_game_state()

	_check_state_round_trip()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


# Abre el menú como escena actual (sin que el cambio de escena borre esta prueba) y pulsa «Nueva partida».
func _open_menu_and_click_new_game() -> void:
	# Sin autoguardado: con uno, «Nueva partida» pregunta antes (test_main_menu).
	DirAccess.remove_absolute(SaveManager.save_dir.path_join(SaveManager.AUTOSAVE + ".json"))
	var previous: Node = get_tree().current_scene
	# Sin cerrar test_all, que corre esta parte.
	if previous != null and previous != self and not previous.is_ancestor_of(self):
		previous.queue_free()
	var menu: Node = load(MENU_SCENE_PATH).instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not GameClock.is_processing(), "el reloj corre en el menú")

	var button: Button = menu.get_node("%NewGameButton")
	_expect(button.text == "Nueva partida", "el botón dice «%s»" % button.text)
	var center: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = center
		click.global_position = center
		get_viewport().push_input(click, true)
		await get_tree().process_frame
	for i: int in range(3):
		await get_tree().process_frame
	var scene: Node = get_tree().current_scene
	_expect(scene != null and scene.scene_file_path == GAME_SCENE_PATH,
		"tras el clic la escena actual es %s" % (scene.scene_file_path if scene else "ninguna"))


func _check_new_game_state() -> void:
	var lot := Rect2i(Vector2i.ZERO, GameConstants.STARTING_LOT_SIZE)
	_expect(OfficeState.lot_rect == lot, "local %s, se esperaba %s" % [OfficeState.lot_rect, lot])
	var office: Dictionary = OfficeState.find_room("executive_office")
	_expect(not office.is_empty(), "no hay Oficina Ejecutiva")
	var office_cells: Array[Vector2i] = []
	if not office.is_empty():
		office_cells = office["cells"]
	_expect(office_cells.size() == 9, "la Oficina Ejecutiva tiene %d casillas" % office_cells.size())
	var count: int = 0
	for room: Dictionary in OfficeState.rooms:
		if room["type"] == "executive_office":
			count += 1
	_expect(count == 1, "hay %d Oficinas Ejecutivas" % count)
	for cell: Vector2i in office_cells:
		_expect(lot.has_point(cell), "casilla %s de la oficina fuera del local" % cell)
	var ids: Array[String] = []
	for item: Dictionary in OfficeState.furniture:
		ids.append(item["id"])
		_expect(office_cells.has(item["cell"]), "%s fuera de la Oficina Ejecutiva" % item["id"])
	_expect(ids.has("executive_desk") and ids.has("basic_chair"), "muebles iniciales: %s" % [ids])

	_expect(Economy.balance == GameConstants.STARTING_CAPITAL, "saldo $%d" % Economy.balance)
	_expect(GameClock.get_day() == 1 and GameClock.get_month() == 1 and GameClock.get_hour() == GameConstants.START_HOUR
		and GameClock.get_minute() == 0, "fecha inicial: día %d, mes %d, %d:%02d" % [
			GameClock.get_day(), GameClock.get_month(), GameClock.get_hour(), GameClock.get_minute()])
	_expect(GameClock.get_speed() == 1.0 and not GameClock.is_paused, "el reloj no empieza a 1x")
	_expect(GameClock.is_processing(), "el reloj no corre en la partida")

	var scene: Node = get_tree().current_scene
	if scene == null or scene.scene_file_path != GAME_SCENE_PATH:
		return
	var grid: OfficeGrid = scene.get_node("OfficeGrid")
	var floor_layer: TileMapLayer = grid.get_node("Floor")
	_expect(grid.get_lot_rect() == lot, "la cuadrícula dibuja el local %s" % grid.get_lot_rect())
	_expect(floor_layer.get_used_cells().size() == OfficeState.site_rect.get_area(),
		"casillas pintadas: %d" % floor_layer.get_used_cells().size())
	# Oficina Ejecutiva de madera, resto de cerámica y terreno fuera; cada casilla con la fila del atlas de su tipo.
	var rows: Dictionary = grid.get("_atlas_rows")
	for cell: Vector2i in floor_layer.get_used_cells():
		if not lot.has_point(cell):
			var terrain_row: int = floor_layer.get_cell_atlas_coords(cell).y
			_expect(grid.is_style_row(terrain_row, MapDecor.GRASS) or grid.is_style_row(terrain_row, MapDecor.PATH), "casilla %s sin terreno" % cell)
			continue
		var expected_type: String = "wood" if office_cells.has(cell) else "ceramic"
		_expect(OfficeState.get_floor(cell) == expected_type, "casilla %s con piso %s" % [cell, OfficeState.get_floor(cell)])
		var row: int = floor_layer.get_cell_atlas_coords(cell).y
		_expect(row == rows[expected_type], "casilla %s dibujada con la fila %d" % [cell, row])
	for edge: Vector3i in GridEdge.get_lot_outline(Lot.from_rect(lot)):
		var expected_kind: String = ConstructionCatalog.WALL
		if edge == GridEdge.between(OfficeState.entrance, OfficeState.get_outside_of_entrance()):
			expected_kind = ConstructionCatalog.DOOR
		_expect(OfficeState.get_edge(edge) == expected_kind, "borde exterior %s: «%s»" % [edge, OfficeState.get_edge(edge)])
	var office_doors: int = 0
	for cell: Vector2i in office_cells:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var neighbour: Vector2i = cell + direction
			if office_cells.has(neighbour) or not lot.has_point(neighbour):
				continue
			var kind: String = OfficeState.get_edge(GridEdge.between(cell, neighbour))
			_expect(not kind.is_empty(), "la Oficina Ejecutiva está abierta entre %s y %s" % [cell, neighbour])
			if kind == ConstructionCatalog.DOOR:
				office_doors += 1
	_expect(office_doors == 1, "la Oficina Ejecutiva tiene %d puertas" % office_doors)
	var camera: OfficeCamera = scene.get_node("OfficeCamera")
	_expect(camera.is_current(), "la cámara de la oficina no es la actual")
	_expect(OfficeState.site_rect == OfficeState.site_around(OfficeState.lot_rect), "el solar no rodea al local")
	_expect(camera.position.distance_to(grid.get_lot_world_rect().get_center()) < 0.01,
		"la cámara no empieza centrada en el local")


func _check_state_round_trip() -> void:
	var office_before: Dictionary = OfficeState.export_state()
	var economy_before: Dictionary = Economy.export_state()
	var office_json: Dictionary = JSON.parse_string(JSON.stringify(office_before))
	var economy_json: Dictionary = JSON.parse_string(JSON.stringify(economy_before))
	OfficeState.import_state({})
	Economy.import_state({})
	_expect(not OfficeState.has_game(), "import_state vacío no limpia la oficina")
	OfficeState.import_state(office_json)
	Economy.import_state(economy_json)
	_expect(JSON.stringify(OfficeState.export_state()) == JSON.stringify(office_before),
		"la oficina no se restauró igual")
	_expect(Economy.export_state() == economy_before, "el saldo no se restauró igual")
	_expect(OfficeState.rooms[0]["cells"] is Array[Vector2i], "las casillas restauradas no son Vector2i")
