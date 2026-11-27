# Construcción en bloques de 2×2 (BuildGrid): paredes, puertas y ventanas solo en líneas de bloque, pisos por
# bloques enteros, lotes de terreno y solar alineados, la puerta doble en un solo tramo, la oficina inicial y la
# empresa de prueba alineadas; muebles y personajes siguen en casillas y una partida vieja con paredes en 1 m
# carga y se puede vender.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=build_blocks
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const X: int = GridEdge.AXIS_X
const Y: int = GridEdge.AXIS_Y

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_grid()
	_new_game()
	_check_new_office()
	_check_rules()
	_check_land()
	_check_old_save()
	await _check_tools()
	_check_demo()
	SaveManager.start_with_demo = false
	SaveManager.new_game()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _new_game() -> void:
	GameClock.stop()
	SaveManager.start_with_demo = false
	SaveManager.new_game()
	Economy.earn(200000, "Prueba")


func _wall(edge: Vector3i, kind: String = ConstructionCatalog.WALL) -> Array[Dictionary]:
	var changes: Array[Dictionary] = [{"edge": edge, "kind": kind}]
	return changes


func _floor(cells: Array[Vector2i], kind: String) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	for cell: Vector2i in cells:
		changes.append({"cell": cell, "kind": kind})
	return changes


# Bordes con pieza que no son del contorno y no están en una línea de bloque.
func _off_block_pieces() -> Array[Vector3i]:
	var off: Array[Vector3i] = []
	for edge: Vector3i in OfficeState.edges:
		if not GridEdge.is_exterior(edge, OfficeState.lot) and not BuildGrid.is_block_edge(edge):
			off.append(edge)
	return off


func _check_grid() -> void:
	_expect(GameConstants.BUILD_BLOCK == 2, "bloques de 2×2")
	_expect(BuildGrid.block_of(Vector2i(3, -1)) == Vector2i(1, -1) and BuildGrid.block_of(Vector2i(-2, 0)) == Vector2i(-1, 0),
		"bloque de una casilla (también con coordenadas negativas)")
	_expect(BuildGrid.block_cells(Vector2i(1, 0)) == ([Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i]),
		"casillas de un bloque")
	_expect(BuildGrid.is_block_edge(Vector3i(1, 0, X)) and not BuildGrid.is_block_edge(Vector3i(2, 0, X))
		and BuildGrid.is_block_edge(Vector3i(0, -1, Y)) and not BuildGrid.is_block_edge(Vector3i(0, 2, Y)),
		"bordes en línea de bloque")
	_expect(BuildGrid.block_segment(Vector3i(3, 5, X)) == ([Vector3i(3, 4, X), Vector3i(3, 5, X)] as Array[Vector3i]),
		"un tramo de bloque son dos bordes")
	_expect(BuildGrid.nearest_block_edge(Vector2(1.4, 2.2)) == Vector3i(1, 2, X)
		and BuildGrid.nearest_block_edge(Vector2(2.1, 3.3)) == Vector3i(2, 3, Y), "el borde de bloque más cercano")
	_expect(BuildGrid.snap_rect_to_blocks(Rect2i(3, 1, 1, 2)) == Rect2i(2, 0, 2, 4), "un rectángulo se agranda a bloques")


func _check_new_office() -> void:
	_expect(_off_block_pieces().is_empty(), "la oficina inicial está en bloques: %s" % [_off_block_pieces()])
	var room: Dictionary = OfficeState.find_room(OfficeState.EXECUTIVE_OFFICE)
	_expect(not room.is_empty() and (room["cells"] as Array).size() == 16, "la oficina del CEO es de 4×4")
	_expect(not OfficeState.get_working_room(OfficeState.EXECUTIVE_OFFICE).is_empty(), "y funciona")
	var door: Vector3i = OfficeState.get_entrance_edge()
	var partner: Vector3i = OfficeState.get_double_door_partner()
	_expect(BuildGrid.block_segment(door).has(partner), "la puerta doble queda en un solo tramo: %s %s" % [door, partner])
	_expect(posmod(OfficeState.site_rect.position.x, 2) == 0 and posmod(OfficeState.site_rect.position.y, 2) == 0,
		"el solar está alineado: %s" % OfficeState.site_rect)


func _check_rules() -> void:
	var off := Vector3i(4, 5, X)
	var on := Vector3i(3, 5, X)
	var refused: Dictionary = _builder.quote(_wall(off))
	_expect(not refused["ok"] and refused["message"] == Builder.OFF_BLOCK_MESSAGE, "pared fuera de bloque no: %s" % refused["message"])
	_expect(not _builder.quote(_wall(off, ConstructionCatalog.DOOR))["ok"], "puerta fuera de bloque tampoco")
	_expect(_builder.quote(_wall(on))["ok"], "en una línea de bloque sí")
	var one: Array[Vector2i] = [Vector2i(4, 5)]
	_expect(_builder.quote(_floor(one, "wood"))["message"] == Builder.OFF_BLOCK_MESSAGE, "el piso de una casilla suelta no")
	var block: Array[Vector2i] = BuildGrid.block_cells(Vector2i(2, 2))
	_expect(_builder.quote(_floor(block, "wood"))["ok"], "el piso de un bloque entero sí")
	# Una pared vieja fuera de bloque se vende.
	OfficeState.edges[off] = ConstructionCatalog.WALL
	EventBus.office_changed.emit()
	_expect(_builder.quote(_wall(off, ""))["ok"], "una pared vieja fuera de bloque se puede vender")
	OfficeState.edges.erase(off)
	EventBus.office_changed.emit()
	# Los muebles siguen en casillas.
	_expect(_builder.place("small_plant", Vector2i(4, 5), 0)["ok"], "un mueble va en cualquier casilla")
	var plant: int = OfficeState.find_furniture_at(Vector2i(4, 5))
	_expect(plant >= 0 and _builder.move(plant, Vector2i(5, 5), 0)["ok"], "y se mueve de a una casilla")
	_builder.sell_furniture_at(Vector2i(5, 5))


func _check_land() -> void:
	var plots: Array[Rect2i] = OfficeState.get_land_plots()
	_expect(not plots.is_empty(), "hay lotes")
	var aligned: bool = true
	var sized: bool = true
	for plot: Rect2i in plots:
		aligned = aligned and posmod(plot.position.x, 2) == 0 and posmod(plot.position.y, 2) == 0 \
			and plot.size.x % 2 == 0 and plot.size.y % 2 == 0
		sized = sized and mini(plot.size.x, plot.size.y) >= 2
	_expect(aligned, "los lotes empiezan y miden en bloques: %s" % [plots])
	_expect(sized, "ningún lote mide menos de un bloque")
	var plot: Rect2i = OfficeState.get_land_plot_at(OfficeState.get_outside_of_entrance())
	var bought: Dictionary = _builder.buy_land_cells(LandPlots.get_cells(plot))
	_expect(bought["ok"], "compra el lote frente a la entrada: %s" % bought["message"])
	if bought["ok"]:
		var door: Vector3i = OfficeState.get_entrance_edge()
		_expect(BuildGrid.is_block_edge(door) and BuildGrid.block_segment(door).has(OfficeState.get_double_door_partner()),
			"la entrada corrida sigue en un tramo de bloque")
		_expect(_off_block_pieces().is_empty(), "el contorno nuevo está en bloques: %s" % [_off_block_pieces()])


func _check_old_save() -> void:
	var off := Vector3i(4, 1, X)
	var state: Dictionary = OfficeState.export_state()
	(state["edges"] as Array).append(GridEdge.to_data(off) + [ConstructionCatalog.WALL])
	OfficeState.import_state(state)
	_expect(OfficeState.get_edge(off) == ConstructionCatalog.WALL, "una partida vieja con pared en 1 m carga")
	_expect(_builder.apply(_wall(off, ""))["ok"] and OfficeState.get_edge(off).is_empty(), "y la pared se vende")


func _check_tools() -> void:
	_new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var controller: Node = game.get_node("BuildController")
	controller.set("tool", "wall")
	var changes: Array[Dictionary] = controller.call("_structure_changes", Vector2(3.4, 4.2), Vector2(3.4, 6.9))
	var edges: Array[Vector3i] = []
	for change: Dictionary in changes:
		edges.append(change["edge"])
	var on_blocks: bool = not edges.is_empty() and edges.size() % 2 == 0
	for edge: Vector3i in edges:
		on_blocks = on_blocks and BuildGrid.is_block_edge(edge)
	_expect(on_blocks,
		"arrastrar pared pone tramos de 2 m en línea de bloque: %s" % [edges])
	controller.set("tool", "door")
	changes = controller.call("_structure_changes", Vector2(4.4, 4.6), Vector2(4.4, 4.6))
	_expect(changes.size() == 1 and BuildGrid.is_block_edge(changes[0]["edge"]), "la puerta va en una línea de bloque: %s" % [changes])
	controller.set("tool", "wood")
	changes = controller.call("_structure_changes", Vector2(4.2, 4.8), Vector2(4.2, 4.8))
	var cells: Array[Vector2i] = []
	for change: Dictionary in changes:
		cells.append(change["cell"])
	_expect(cells.size() == 4 and BuildGrid.covers_whole_blocks(cells), "el piso se pinta por bloques: %s" % [cells])
	game.queue_free()
	await get_tree().process_frame


func _check_demo() -> void:
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	_expect(_off_block_pieces().is_empty(), "la empresa de prueba está en bloques: %s" % [_off_block_pieces()])
	for room_type: String in [OfficeState.EXECUTIVE_OFFICE, "single_office", "cleaning_room", "reception", Workstations.WORK_AREA]:
		_expect(not OfficeState.find_room(room_type).is_empty(), "la empresa de prueba tiene %s" % room_type)
	_expect(Staff.employees.size() >= 40, "y su personal: %d" % Staff.employees.size())
	var door: Vector3i = OfficeState.get_entrance_edge()
	_expect(BuildGrid.block_segment(door).has(OfficeState.get_double_door_partner()), "con la puerta doble en un tramo")
