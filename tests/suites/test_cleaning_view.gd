# Cómo se ve la limpieza: el personal de limpieza en su turno camina con el suape, trapea con el cubo
# al lado y cambia de casilla cada mop_minutes; sin nada sucio recorre varias habitaciones.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=cleaning_view
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
	_check_library()
	var demo_before: bool = SaveManager.start_with_demo
	SaveManager.start_with_demo = true
	SaveManager.new_game()
	await _check_cleaners()
	SaveManager.start_with_demo = demo_before
	SaveManager.new_game()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _check_library() -> void:
	_expect(SpriteLibrary.get_character_frames("mop") == 4 and SpriteLibrary.get_character_frames("mopwalk") == 8,
		"poses del suape: trapear 4 cuadros y caminar 8")
	for woman: bool in [false, true]:
		for number: int in range(9):
			var look: String = OfficeCharacter.make_look(woman, "cleaning", number)
			_expect(SpriteLibrary.has_tool_look(look), "hoja del suape para %s" % look)
	_expect(not SpriteLibrary.has_tool_look("casual") and not SpriteLibrary.has_tool_look("office_v1"),
		"los demás aspectos no tienen suape")
	var bucket: String = SpriteLibrary.get_bucket_sprite()
	_expect(SpriteLibrary.has_sprite(bucket) and SpriteLibrary.has_sprite(bucket + "_shadow"), "el cubo tiene sprite y sombra")


func _check_cleaners() -> void:
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	GameClock.set_paused(false)
	GameClock.fast_forward_hours(2)  # 10:00 del lunes: la limpieza está en su turno.
	await get_tree().process_frame
	var cleaners: Array[Employee] = []
	var others: int = 0
	for character: OfficeCharacter in game.get_characters():
		if character is Employee:
			var employee: Dictionary = Staff.get_employee_by_key(character.person_key)
			if employee["role"] == String(StaffCatalog.get_cleaning("role")):
				cleaners.append(character)
			elif character.cleaning:
				others += 1
	_expect(cleaners.size() >= 1, "la empresa de prueba tiene personal de limpieza: %d" % cleaners.size())
	_expect(others == 0, "solo la limpieza lleva el suape")
	if cleaners.is_empty():
		game.queue_free()
		return
	var cleaner: Employee = cleaners[0]
	var employee: Dictionary = Staff.get_employee_by_key(cleaner.person_key)
	_expect(game.is_cleaning_now(employee) and cleaner.cleaning, "en su turno lleva el suape")
	# Cambia de casilla cada mop_minutes; sin nada sucio, de habitación cada mop_spots_per_room.
	for room: Dictionary in OfficeState.rooms:
		room["dirt"] = 0.0
	var minutes: int = int(StaffCatalog.get_cleaning("mop_minutes"))
	var now: int = Staff.get_absolute_hour() * 60
	var cells: Dictionary[Vector2i, bool] = {}
	var rooms: Dictionary[int, bool] = {}
	var room_map: Dictionary[Vector2i, int] = {}
	for index: int in range(OfficeState.rooms.size()):
		for cell: Vector2i in OfficeState.rooms[index]["cells"]:
			room_map[cell] = index
	for turn: int in range(12):
		var spot: Vector2i = game._cleaning_spot(employee, now + turn * minutes)
		cells[spot] = true
		rooms[room_map.get(spot, -1)] = true
	_expect(cells.size() >= 6 and not cells.has(game.NO_SPOT), "trapea en varias casillas: %d" % cells.size())
	_expect(rooms.size() >= 3 and not rooms.has(-1), "sin nada sucio recorre varias habitaciones: %d" % rooms.size())
	# Con una habitación sucia trapea ahí, en varias partes de ella.
	var dirty: int = 0
	OfficeState.rooms[dirty]["dirt"] = 80.0
	var inside: Dictionary[Vector2i, bool] = {}
	var all_inside: bool = true
	for turn: int in range(6):
		var spot: Vector2i = game._cleaning_spot(employee, now + turn * minutes)
		inside[spot] = true
		all_inside = all_inside and Array(OfficeState.rooms[dirty]["cells"]).has(spot)
	_expect(all_inside and inside.size() >= 3, "la habitación sucia, por partes: %d casillas" % inside.size())
	OfficeState.rooms[dirty]["dirt"] = 0.0
	# Parado en su lugar trapea con el cubo al lado; caminando lleva el suape.
	cleaner.grid_position = Vector2(cleaner.get_seat_cell())
	cleaner.call("_set_activity", OfficeCharacter.Activity.SEATED)
	cleaner.visible = true
	_expect(cleaner.is_mopping() and cleaner.get("_pose") == "mop", "en su lugar trapea: %s" % cleaner.get("_pose"))
	var bucket: Node2D = cleaner.get_node("Bucket")
	_expect(bucket.visible and bucket.position.length() > 4.0, "el cubo se ve a su lado")
	cleaner.call("_animate", 0.016, Vector2(0.1, 0.0))
	_expect(cleaner.get("_pose") == "mopwalk", "caminando lleva el suape: %s" % cleaner.get("_pose"))
	cleaner.cleaning = false
	cleaner.call("_animate", 0.016, Vector2.ZERO)
	_expect(not cleaner.is_mopping() and not bucket.visible and cleaner.get("_pose") != "mop", "fuera de turno sin suape ni cubo")
	game.queue_free()
	await get_tree().process_frame
