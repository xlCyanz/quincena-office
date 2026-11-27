# Puerta de vidrio sencilla: catálogo y paso (se compra en cualquier borde desde test_glass_door_single; la
# entrada lleva la doble, ver test_glass_door_double). Pasa y cuenta como puerta.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=glass_door
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_packed.call_deferred(GAME_SCENE)
		return
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_pathfinding()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _changes(edge: Vector3i, kind: String) -> Array[Dictionary]:
	var changes: Array[Dictionary] = [{"edge": edge, "kind": kind}]
	return changes


func _check_catalog() -> void:
	var glass: String = ConstructionCatalog.GLASS_DOOR
	_expect(ConstructionCatalog.get_display_name(glass) == "Puerta de vidrio", "nombre")
	_expect(ConstructionCatalog.get_price(glass) == 900 and ConstructionCatalog.get_refund(glass) == 450,
		"$900, se vende a $450")
	_expect(ConstructionCatalog.get_glass_door_ambiance() == 6, "6 puntos de ambiente")
	_expect(ConstructionCatalog.is_door(glass) and ConstructionCatalog.is_door(ConstructionCatalog.DOOR)
		and not ConstructionCatalog.is_door(ConstructionCatalog.WINDOW), "es una puerta")


# Deja pasar como una puerta y abre habitaciones (con un borde interior a mano).
func _check_pathfinding() -> void:
	var lot := Lot.from_rect(Rect2i(0, 0, 4, 2))
	var edges: Dictionary[Vector3i, String] = {}
	for y: int in range(2):
		edges[GridEdge.between(Vector2i(1, y), Vector2i(2, y))] = ConstructionCatalog.WALL
	var middle: Vector3i = GridEdge.between(Vector2i(1, 0), Vector2i(2, 0))
	edges[middle] = ConstructionCatalog.GLASS_DOOR
	var finder := OfficePathfinder.new()
	finder.build(lot, [], edges)
	_expect(finder.can_cross(Vector2i(1, 0), Vector2i(2, 0)), "se cruza la puerta de vidrio")
	_expect(not finder.can_cross(Vector2i(1, 1), Vector2i(2, 1)), "la pared de al lado no")
	var spaces: Array[Dictionary] = RoomRules.find_spaces(lot, edges)
	var doors: int = 0
	for space: Dictionary in spaces:
		doors += int(space["doors"])
	_expect(spaces.size() == 2 and doors == 2, "cada lado cuenta la puerta de vidrio: %d espacios, %d puertas" % [spaces.size(), doors])
