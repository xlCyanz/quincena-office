# Prueba del hito 69: la puerta doble de vidrio de la Recepción. Solo reemplaza la puerta de
# entrada; cuesta $900 y al venderla devuelve la mitad y queda la puerta normal; deja pasar
# y cuenta como puerta para las habitaciones; suma 6 puntos al ambiente de la habitación de
# la entrada; se dibuja con marco y dos hojas; se guarda y se carga.
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


func _check_in_game() -> void:
	SaveManager.new_game()
	# Sin recompensas de objetivos en medio: la prueba mide el saldo exacto.
	for objective: Dictionary in Company.get_objectives():
		Company.objectives_done.append(String(objective["id"]))
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var builder: Builder = game.get_node("BuildController").builder
	var entrance_edge: Vector3i = OfficeState.get_entrance_edge()
	var outside: Vector2i = OfficeState.get_outside_of_entrance()
	_expect(OfficeState.get_edge(entrance_edge) == ConstructionCatalog.DOOR, "la entrada empieza con puerta normal")

	# Solo en la entrada: no en otra pared exterior ni en un borde de adentro.
	var other_exterior: Vector3i = Vector3i.ZERO
	for edge: Vector3i in GridEdge.get_lot_outline(OfficeState.lot):
		if edge != entrance_edge:
			other_exterior = edge
			break
	var refused: Dictionary = builder.quote(_changes(other_exterior, ConstructionCatalog.GLASS_DOOR))
	_expect(not refused["ok"] and String(refused["message"]).contains("puerta de entrada"),
		"en otra pared exterior no: %s" % refused["message"])
	var inner: Vector3i = GridEdge.between(OfficeState.entrance, OfficeState.entrance + Vector2i(1, 0))
	if not OfficeState.lot.has_point(OfficeState.entrance + Vector2i(1, 0)):
		inner = GridEdge.between(OfficeState.entrance, OfficeState.entrance - Vector2i(1, 0))
	_expect(not builder.quote(_changes(inner, ConstructionCatalog.GLASS_DOOR))["ok"], "adentro no")
	# La puerta normal de la entrada sigue sin venderse.
	_expect(not builder.quote(_changes(entrance_edge, ""))["ok"], "la puerta de entrada normal no se vende")

	# Ponerla: cobra $900.
	var balance: int = Economy.balance
	var marked: Dictionary = builder.mark_room("reception", OfficeState.entrance)
	_expect(marked["ok"], "Recepción en la entrada: %s" % marked.get("message", ""))
	var reception: Dictionary = OfficeState.find_room("reception")
	var area: int = Array(reception["cells"]).size()
	var before: Dictionary = Ambiance.get_detail(reception, OfficeState.furniture, OfficeState.count_room_windows(reception),
		OfficeState.get_room_door_ambiance(reception))
	balance = Economy.balance
	var placed: Dictionary = builder.apply(_changes(entrance_edge, ConstructionCatalog.GLASS_DOOR))
	_expect(placed["ok"] and int(placed["cost"]) == 900 and Economy.balance == balance - 900,
		"poner la puerta cobra $900: %s" % [placed])
	_expect(OfficeState.get_edge(entrance_edge) == ConstructionCatalog.GLASS_DOOR, "la entrada tiene la puerta de vidrio")
	_expect(OfficeState.get_outside_of_entrance() == outside and OfficeState.get_entrance_edge() == entrance_edge,
		"la entrada sigue en el mismo lugar")
	reception = OfficeState.find_room("reception")
	_expect(not reception.is_empty(), "la Recepción sigue siendo habitación con la puerta de vidrio")
	_expect(OfficeState.get_room_door_ambiance(reception) == 6, "6 puntos para la Recepción")
	var after: Dictionary = Ambiance.get_detail(reception, OfficeState.furniture, OfficeState.count_room_windows(reception),
		OfficeState.get_room_door_ambiance(reception))
	_expect(is_equal_approx(float(after["points"]) - float(before["points"]), 6.0), "suma 6 puntos al ambiente")
	_expect(is_equal_approx(float(after["decor"]) - float(before["decor"]), 60.0 / area),
		"como un adorno: 6 × 10 / %d m²" % area)
	for room: Dictionary in OfficeState.rooms:
		if room["type"] != "reception":
			_expect(OfficeState.get_room_door_ambiance(room) == 0, "a %s no le suma" % room["type"])
	_expect(builder.quote_mark_room("reception", OfficeState.entrance)["message"].contains("Ambiente"),
		"el cartel de la Recepción dice el ambiente")
	# Se dibuja con marco y dos hojas.
	await get_tree().process_frame
	var view: EdgePieceView = null
	for child: Node in game.get_node("OfficeGrid/Objects").get_children():
		if child is EdgePieceView and child.edge == entrance_edge:
			view = child
	_expect(view != null and view.kind == ConstructionCatalog.GLASS_DOOR, "se dibuja la puerta de vidrio")
	if view != null:
		_expect((view.get("_leaf_bases") as Array).size() == 2 and (view.get("_frame_bases") as Array).size() == 2,
			"dos hojas y dos postes")
	# Herramienta de Construir.
	var panel: BuildPanel = game.get_node("BuildPanel")
	var tool_button: Button = panel.get_tool_button(BuildController.TOOL_GLASS_DOOR)
	_expect(tool_button != null and tool_button.text == "Puerta de vidrio", "botón Puerta de vidrio en Construir")

	# Se guarda y se carga.
	var saved: Dictionary = OfficeState.export_state()
	OfficeState.import_state(saved)
	_expect(OfficeState.get_edge(entrance_edge) == ConstructionCatalog.GLASS_DOOR, "se guarda y se carga")

	# Venderla devuelve $450 y deja la puerta normal; pasarle Puerta, igual.
	balance = Economy.balance
	var sold: Dictionary = builder.apply(_changes(entrance_edge, ""))
	_expect(sold["ok"] and int(sold["cost"]) == -450 and Economy.balance == balance + 450,
		"venderla devuelve $450: %s" % [sold])
	_expect(OfficeState.get_edge(entrance_edge) == ConstructionCatalog.DOOR, "queda la puerta normal")
	_expect(builder.apply(_changes(entrance_edge, ConstructionCatalog.GLASS_DOOR))["ok"], "ponerla otra vez")
	balance = Economy.balance
	var swapped: Dictionary = builder.apply(_changes(entrance_edge, ConstructionCatalog.DOOR))
	_expect(swapped["ok"] and Economy.balance == balance + 450 and OfficeState.get_edge(entrance_edge) == ConstructionCatalog.DOOR,
		"Puerta encima la vuelve normal y devuelve $450")
	_expect(not builder.quote(_changes(entrance_edge, ConstructionCatalog.WALL))["ok"], "la entrada no se tapa con pared")
	game.queue_free()
	await get_tree().process_frame


# La empresa de prueba la trae puesta como ejemplo.
func _check_demo() -> void:
	var demo_before: bool = SaveManager.start_with_demo
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	_expect(OfficeState.get_edge(OfficeState.get_entrance_edge()) == ConstructionCatalog.GLASS_DOOR,
		"la empresa de prueba tiene la puerta de vidrio en la entrada")
	var reception: Dictionary = OfficeState.find_room("reception")
	_expect(not reception.is_empty() and OfficeState.get_room_door_ambiance(reception) == 6,
		"y su Recepción suma el ambiente")
	SaveManager.start_with_demo = demo_before
	SaveManager.new_game()
