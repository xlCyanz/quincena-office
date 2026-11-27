# Puerta de vidrio de una hoja: se compra en cualquier borde de adentro (en líneas de bloque) como una puerta,
# $900 y se vende a la mitad, +6 de ambiente a las habitaciones de sus dos lados, abre con sus cuadros y tiene
# botón en Construir; la doble sigue fija en la entrada y no se compra.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=glass_door_single
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GLASS: String = ConstructionCatalog.GLASS_DOOR
## Puerta de la oficina del CEO en la oficina inicial (data/starting_office.json).
const CEO_DOOR := Vector3i(1, 3, GridEdge.AXIS_Y)

var _failures: int = 0
var _checks: int = 0
var _builder := Builder.new()


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	GameClock.stop()
	SaveManager.start_with_demo = false
	SaveManager.new_game()
	Economy.earn(100000, "Prueba")
	_check_sprites()
	_check_buy_and_sell()
	await _check_tool()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _changes(edge: Vector3i, kind: String) -> Array[Dictionary]:
	var changes: Array[Dictionary] = [{"edge": edge, "kind": kind}]
	return changes


func _check_sprites() -> void:
	_expect(int(ConstructionCatalog.get_edge_piece(GLASS).get("height", 0))
		== int(ConstructionCatalog.get_edge_piece(ConstructionCatalog.GLASS_DOOR_DOUBLE).get("height", 0)),
		"del alto de la doble")
	_expect(SpriteLibrary.has_sprite("glass_door_tall_y") and SpriteLibrary.has_sprite("glass_door_low_x"), "tiene sprites")
	_expect(SpriteLibrary.get_door_frames(GLASS) == 6 and SpriteLibrary.has_sprite("glass_door_tall_x_open_6"),
		"abre en 6 cuadros")


func _check_buy_and_sell() -> void:
	var room: Dictionary = OfficeState.find_room(OfficeState.EXECUTIVE_OFFICE)
	var before: int = OfficeState.get_room_door_ambiance(room)
	var balance: int = Economy.balance
	var bought: Dictionary = _builder.apply(_changes(CEO_DOOR, GLASS))
	var door_refund: int = ConstructionCatalog.get_refund(ConstructionCatalog.DOOR)
	_expect(bought["ok"] and OfficeState.get_edge(CEO_DOOR) == GLASS, "cambia la puerta del CEO por una de vidrio: %s" % bought["message"])
	_expect(balance - Economy.balance == 900 - door_refund, "cobra $900 menos la puerta de antes: %d" % (balance - Economy.balance))
	room = OfficeState.find_room(OfficeState.EXECUTIVE_OFFICE)
	_expect(not room.is_empty() and OfficeState.get_room_door_ambiance(room) == before + 6,
		"+6 de ambiente a la oficina del CEO: %d" % OfficeState.get_room_door_ambiance(room))
	_expect(not OfficeState.get_working_room(OfficeState.EXECUTIVE_OFFICE).is_empty(), "la oficina sigue funcionando")
	var finder := OfficePathfinder.new()
	finder.build(OfficeState.lot, OfficeState.get_blocking_cells(), OfficeState.edges)
	_expect(finder.can_cross(Vector2i(1, 3), Vector2i(1, 4)), "se pasa por ella")
	var off_block := Vector3i(0, 3, GridEdge.AXIS_X)
	_expect(not _builder.quote(_changes(Vector3i(2, 4, GridEdge.AXIS_Y), GLASS))["ok"], "fuera de línea de bloque no")
	_expect(not _builder.quote(_changes(off_block, GLASS))["ok"], "en un borde sin pared ni bloque no")
	var outline: Vector3i = Vector3i.ZERO
	for edge: Vector3i in GridEdge.get_lot_outline(OfficeState.lot):
		if OfficeState.get_edge(edge) == ConstructionCatalog.WALL and BuildGrid.is_block_edge(edge):
			outline = edge
			break
	_expect(not _builder.quote(_changes(outline, GLASS))["ok"], "en el contorno no")
	_expect(not _builder.quote(_changes(CEO_DOOR, ConstructionCatalog.GLASS_DOOR_DOUBLE))["ok"], "la doble no se compra")
	balance = Economy.balance
	var back: Dictionary = _builder.apply(_changes(CEO_DOOR, ConstructionCatalog.DOOR))
	_expect(back["ok"] and Economy.balance - balance == 450 - ConstructionCatalog.get_price(ConstructionCatalog.DOOR),
		"vuelve a puerta normal y devuelve $450: %s" % back["message"])


func _check_tool() -> void:
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var panel: BuildPanel = game.get_node("BuildPanel")
	_expect(panel.get_tool_button(BuildController.TOOL_GLASS_DOOR) != null, "botón Puerta de vidrio en Construir")
	var controller: BuildController = game.get_node("BuildController")
	controller.set_tool(BuildController.TOOL_GLASS_DOOR)
	var changes: Array[Dictionary] = controller.call("_structure_changes", Vector2(1.2, 3.6), Vector2(1.2, 3.6))
	_expect(changes.size() == 1 and changes[0]["kind"] == GLASS and changes[0]["edge"] == CEO_DOOR,
		"la herramienta pone la puerta de vidrio en el borde de bloque: %s" % [changes])
	game.queue_free()
	await get_tree().process_frame
