# Prueba sin ventana del hito 7: detección de espacios cerrados con puerta, asignación
# de tipo de habitación y validación de requisitos. La Recepción exige pared exterior
# (y contener la entrada).
# Ejecutar con:
#   Godot --headless --path . res://tests/test_rooms.tscn
# Termina con código 0 si todo pasa y 1 si algo falla.
extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Las pruebas guardan en otra carpeta para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_starting_spaces()
	_check_mark_and_rules()
	_check_requirements()
	_check_walls_change_rooms()
	await _check_in_game_with_mouse()

	print("Comprobaciones: %d, fallos: %d" % [_checks, _failures])
	print("RESULTADO: %s" % ("OK" if _failures == 0 else "FALLO"))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _wall(x: int, y: int, axis: int, kind: String = ConstructionCatalog.WALL) -> Dictionary:
	return {"edge": Vector3i(x, y, axis), "kind": kind}


func _room_type_at(cell: Vector2i) -> String:
	var index: int = RoomRules.room_index_at(OfficeState.rooms, cell)
	return "" if index < 0 else String(OfficeState.rooms[index]["type"])


func _room_at(cell: Vector2i) -> Dictionary:
	return OfficeState.rooms[RoomRules.room_index_at(OfficeState.rooms, cell)]


# Habitación cerrada de 2×2 en (3..4, 3..4), en medio del local, con puerta al sur.
func _interior_room_changes() -> Array[Dictionary]:
	var x: int = GridEdge.AXIS_X
	var y: int = GridEdge.AXIS_Y
	return [_wall(2, 3, x), _wall(2, 4, x), _wall(4, 3, x), _wall(4, 4, x),
		_wall(3, 2, y), _wall(4, 2, y), _wall(3, 4, y, ConstructionCatalog.DOOR), _wall(4, 4, y)]


func _check_catalog() -> void:
	var ids: Array[String] = RoomCatalog.get_type_ids()
	_expect(ids.size() == 8, "debería haber 8 tipos de habitación: %s" % [ids])
	_expect(RoomCatalog.needs_exterior_wall("reception") and RoomCatalog.needs_entrance("reception"),
		"la Recepción exige pared exterior y entrada")
	_expect(RoomCatalog.is_locked("executive_office") and RoomCatalog.is_unique("executive_office"),
		"la Oficina Ejecutiva es única y no se puede quitar")
	_expect(RoomCatalog.get_min_area("meeting_room") == 9 and RoomCatalog.get_min_area("bathroom") == 2,
		"tamaños mínimos")


func _check_starting_spaces() -> void:
	SaveManager.new_game()
	var spaces: Array[Dictionary] = RoomRules.find_spaces(OfficeState.lot_rect, OfficeState.edges)
	_expect(spaces.size() == 2, "la oficina inicial tiene 2 espacios: %d" % spaces.size())
	var office: Dictionary = spaces[RoomRules.space_index_at(spaces, Vector2i(0, 0))]
	var main_area: Dictionary = spaces[RoomRules.space_index_at(spaces, Vector2i(5, 7))]
	_expect(office["cells"].size() == 9 and office["closed"] and office["doors"] == 1 and office["exterior"],
		"espacio de la Oficina Ejecutiva: %s" % [office])
	_expect(main_area["cells"].size() == 39 and main_area["closed"] and main_area["doors"] == 2,
		"espacio principal: %d casillas, %d puertas" % [main_area["cells"].size(), main_area["doors"]])
	_expect(OfficeState.rooms.size() == 1 and _room_at(Vector2i(1, 1))["cells"] == office["cells"],
		"la Oficina Ejecutiva inicial ocupa su espacio")
	var builder := Builder.new()
	_expect(builder.room_status(_room_at(Vector2i(0, 0)))["ok"], "la Oficina Ejecutiva inicial debería funcionar")
	_expect(RoomRules.missing_mandatory(OfficeState.rooms) == ["Baño (0 de 2)", "Recepción"],
		"obligatorias que faltan: %s" % [RoomRules.missing_mandatory(OfficeState.rooms)])


func _check_mark_and_rules() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	var money: int = Economy.balance

	# Recepción en el espacio principal: toca la pared exterior y contiene la entrada.
	var result: Dictionary = builder.mark_room("reception", Vector2i(4, 6))
	_expect(result["ok"] and _room_type_at(OfficeState.entrance) == "reception" and Economy.balance == money,
		"marcar la Recepción: %s" % [result])
	_expect(String(result["message"]).contains("falta mostrador de recepción"),
		"el aviso debería decir que falta el mostrador: %s" % result["message"])
	_expect(_room_at(Vector2i(4, 6))["cells"].size() == 39, "la Recepción ocupa todo el espacio")
	result = builder.mark_room("reception", Vector2i(0, 7))
	_expect(not result["ok"], "volver a marcar lo mismo no hace nada: %s" % [result])

	# Un espacio abierto (sin pared en el borde del local) no es habitación.
	var open_space: Dictionary = {"cells": [Vector2i(0, 0)] as Array[Vector2i], "doors": 1, "closed": false, "exterior": false}
	_expect(RoomRules.mark_problem("bathroom", open_space, [], Vector2i.ZERO).contains("no está cerrado"),
		"un espacio sin cerrar no se puede marcar")

	# Esquina cerrada sin puerta: no se puede marcar; con puerta, sí.
	var x: int = GridEdge.AXIS_X
	var y: int = GridEdge.AXIS_Y
	result = builder.apply([_wall(1, 6, x), _wall(1, 7, x), _wall(0, 5, y), _wall(1, 5, y)])
	_expect(result["ok"], "cerrar la esquina: %s" % [result])
	_expect(_room_at(OfficeState.entrance)["cells"].size() == 35, "la Recepción pierde las 4 casillas de la esquina")
	result = builder.mark_room("bathroom", Vector2i(0, 7))
	_expect(not result["ok"] and String(result["message"]).contains("puerta"), "sin puerta no hay habitación: %s" % [result])
	_expect(builder.apply([_wall(1, 7, x, ConstructionCatalog.DOOR)])["ok"], "poner la puerta del baño")
	result = builder.mark_room("bathroom", Vector2i(0, 7))
	_expect(result["ok"] and _room_type_at(Vector2i(1, 6)) == "bathroom", "marcar el baño: %s" % [result])
	_expect(RoomRules.missing_mandatory(OfficeState.rooms) == ["Baño (1 de 2)"],
		"obligatorias que faltan: %s" % [RoomRules.missing_mandatory(OfficeState.rooms)])

	# La Recepción exige pared exterior y contener la entrada.
	_expect(builder.apply(_interior_room_changes())["ok"], "construir la habitación interior")
	builder.unmark_room(OfficeState.entrance)
	result = builder.quote_mark_room("reception", Vector2i(3, 3))
	_expect(not result["ok"] and String(result["message"]).contains("pared exterior"),
		"Recepción sin pared exterior: %s" % [result])
	result = builder.quote_mark_room("reception", Vector2i(0, 7))
	_expect(not result["ok"] and String(result["message"]).contains("entrada"), "Recepción sin la entrada: %s" % [result])
	_expect(builder.quote_mark_room("bathroom", Vector2i(3, 3))["ok"], "un baño sí puede ir en medio")

	# Únicas: solo una Sala de descanso.
	_expect(builder.mark_room("break_room", Vector2i(3, 3))["ok"], "marcar la sala de descanso")
	result = builder.mark_room("break_room", Vector2i(5, 7))
	_expect(not result["ok"] and String(result["message"]).contains("Solo puede haber una"), "dos salas de descanso: %s" % [result])
	# Cambiar el tipo de una habitación.
	result = builder.mark_room("meeting_room", Vector2i(3, 3))
	_expect(result["ok"] and _room_type_at(Vector2i(4, 4)) == "meeting_room"
		and RoomRules.room_index_at(OfficeState.rooms, Vector2i(3, 3)) == OfficeState.rooms.size() - 1
		and OfficeState.rooms.size() == 3, "cambiar de tipo: %s" % [OfficeState.rooms])

	# Quitar: la Oficina Ejecutiva no se puede quitar ni cambiar de tipo.
	_expect(not builder.unmark_room(Vector2i(0, 0))["ok"], "se quitó la Oficina Ejecutiva")
	_expect(not builder.mark_room("single_office", Vector2i(0, 0))["ok"], "se cambió el tipo de la Oficina Ejecutiva")
	result = builder.unmark_room(Vector2i(3, 3))
	_expect(result["ok"] and _room_type_at(Vector2i(3, 3)) == "", "quitar la sala de reuniones: %s" % [result])
	_expect(not builder.unmark_room(Vector2i(5, 0))["ok"], "quitar donde no hay habitación")
	_expect(Economy.balance == money - 50 * 4 - 200 + 25 - 50 * 7 - 200, "las habitaciones no cuestan dinero")


func _check_requirements() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	builder.apply(_interior_room_changes())
	builder.mark_room("work_area", Vector2i(3, 3))
	var status: String = builder.room_status(_room_at(Vector2i(3, 3)))["message"]
	_expect(status.contains("muy pequeña (4 de 6 m²)") and status.contains("falta escritorio")
		and status.contains("falta silla"), "estado del área de trabajo vacía: %s" % status)
	builder.mark_room("single_office", Vector2i(3, 3))
	_expect(not builder.room_status(_room_at(Vector2i(3, 3)))["ok"], "oficina única sin muebles")
	_expect(builder.place("simple_desk", Vector2i(4, 3), 2)["ok"], "poner el escritorio")
	status = builder.room_status(_room_at(Vector2i(3, 3)))["message"]
	_expect(not status.contains("escritorio") and status.contains("falta silla"), "solo falta la silla: %s" % status)
	_expect(builder.place("basic_chair", Vector2i(4, 4), 0)["ok"], "poner la silla")
	_expect(builder.room_status(_room_at(Vector2i(3, 3)))["ok"], "la oficina única amueblada debería funcionar")
	# Sin el escritorio ejecutivo, la Oficina Ejecutiva deja de funcionar.
	var chair: int = OfficeState.find_furniture_at(Vector2i(1, 1))
	var desk: int = OfficeState.find_furniture_at(Vector2i(1, 0))
	OfficeState.furniture.remove_at(desk)
	status = builder.room_status(_room_at(Vector2i(0, 0)))["message"]
	_expect(chair >= 0 and status.contains("falta escritorio ejecutivo"), "Oficina Ejecutiva sin escritorio: %s" % status)


func _check_walls_change_rooms() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	var x: int = GridEdge.AXIS_X
	var y: int = GridEdge.AXIS_Y
	builder.mark_room("reception", OfficeState.entrance)
	builder.apply([_wall(1, 6, x), _wall(1, 7, x, ConstructionCatalog.DOOR), _wall(0, 5, y), _wall(1, 5, y)])
	builder.mark_room("bathroom", Vector2i(0, 7))
	_expect(OfficeState.rooms.size() == 3, "tres habitaciones antes de tumbar paredes")

	# Quitar una pared del baño lo une a la Recepción: el baño se deshace con aviso.
	var result: Dictionary = builder.quote([_wall(1, 6, x, "")])
	_expect(result["ok"] and String(result["message"]).contains("Se deshace: Baño"), "aviso al deshacer: %s" % [result])
	builder.apply([_wall(1, 6, x, "")])
	_expect(_room_type_at(Vector2i(0, 7)) == "reception" and OfficeState.rooms.size() == 2
		and _room_at(OfficeState.entrance)["cells"].size() == 39, "el baño se unió a la Recepción: %s" % [OfficeState.rooms])

	# Vender una pared exterior abre la Recepción a la calle: se deshace.
	result = builder.apply([_wall(5, 0, x, "")])
	_expect(result["ok"] and _room_type_at(OfficeState.entrance) == "", "la Recepción abierta se deshizo: %s" % [result])
	builder.apply([_wall(5, 0, x)])

	# Lo que desharía la Oficina Ejecutiva (abrirla a la calle) no se permite.
	var money: int = Economy.balance
	result = builder.apply([_wall(-1, 0, x, "")])
	_expect(not result["ok"] and String(result["message"]).contains("Oficina Ejecutiva") and Economy.balance == money
		and OfficeState.get_edge(Vector3i(-1, 0, x)) == ConstructionCatalog.WALL, "abrir la Oficina Ejecutiva: %s" % [result])
	# Agrandarla sí: al quitar una pared interior, absorbe el espacio vecino.
	builder.mark_room("reception", OfficeState.entrance)
	result = builder.apply([_wall(2, 0, x, "")])
	_expect(result["ok"] and _room_at(Vector2i(5, 7))["type"] == "executive_office"
		and String(result["message"]).contains("Se deshace: Recepción"), "agrandar la Oficina Ejecutiva: %s" % [result])
	builder.apply([_wall(2, 0, x)])
	_expect(_room_at(Vector2i(0, 0))["cells"].size() == 9 and _room_type_at(Vector2i(5, 7)) == "",
		"al volver a poner la pared, la Oficina Ejecutiva vuelve a su espacio")


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame


func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	await _push(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _push(event)


func _check_in_game_with_mouse() -> void:
	SaveManager.new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameClock.stop()
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var panel: BuildPanel = game.get_node("BuildPanel")
	var overlay: RoomOverlay = grid.get_node("RoomOverlay")
	var at_cell: Callable = func(cell: Vector2i) -> Vector2:
		return grid.get_canvas_transform() * grid.cell_to_world(cell)
	var press: Callable = func(tool: String) -> void:
		await _click(panel.get_tool_button(tool).get_global_rect().get_center())

	_expect(not overlay.visible, "el tinte de habitaciones no debería verse fuera del modo construcción")
	await _click(panel.get_open_button().get_global_rect().get_center())
	_expect(overlay.visible, "el tinte de habitaciones debería verse en modo construcción")

	await press.call("reception")
	await _click(at_cell.call(Vector2i(4, 6)))
	_expect(_room_type_at(Vector2i(4, 6)) == "reception", "marcar la Recepción con el ratón")
	await press.call("bathroom")
	await _click(at_cell.call(Vector2i(4, 6)))
	_expect(_room_type_at(Vector2i(4, 6)) == "bathroom", "cambiar a baño con el ratón")
	await press.call(BuildController.TOOL_UNMARK_ROOM)
	await _click(at_cell.call(Vector2i(4, 6)))
	_expect(_room_type_at(Vector2i(4, 6)) == "", "quitar la habitación con el ratón")
	await _click(at_cell.call(Vector2i(1, 1)))
	_expect(_room_type_at(Vector2i(1, 1)) == "executive_office", "la Oficina Ejecutiva se quitó con el ratón")
	await press.call("reception")
	await _click(at_cell.call(Vector2i(4, 6)))

	# Guardar y restaurar las habitaciones.
	var before: String = JSON.stringify(OfficeState.export_state())
	OfficeState.import_state(JSON.parse_string(before))
	_expect(JSON.stringify(OfficeState.export_state()) == before, "las habitaciones no se restauraron igual")
	_expect(OfficeState.rooms.size() == 2, "deberían quedar 2 habitaciones guardadas")

	await _click(panel.get_exit_button().get_global_rect().get_center())
	_expect(not overlay.visible, "el tinte debería ocultarse al salir del modo construcción")
	game.queue_free()
	await get_tree().process_frame
