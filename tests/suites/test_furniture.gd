# Muebles: colocar, girar, mover y vender escritorio, silla, computadora y planta; no se coloca sobre
# otro objeto ni tapando el único acceso; la reventa devuelve el 50 %.
# Parte de test_all; sola: Godot --headless --path . res://tests/test_all.tscn -- --only=furniture
extends Node

## Terminó: cuántas comprobaciones fallaron y cuántas se hicieron (lo escucha test_all).
signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Esta escena es una prueba automática sin ventana; se abre el juego normal.")
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)
		return
	# Para no tocar las partidas del jugador.
	SaveManager.save_dir = "user://test_saves"
	_check_catalog()
	_check_place_and_overlap()
	_check_access()
	_check_rotate()
	_check_computer_and_sell()
	_check_move()
	_check_outline()
	await _check_in_game_with_mouse()

	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALLO: " + message)


func _index_at(cell: Vector2i) -> int:
	return OfficeState.find_furniture_at(cell)


func _check_catalog() -> void:
	var prices: Dictionary = {"simple_desk": 150, "basic_chair": 60, "basic_computer": 500,
		"small_plant": 40, "executive_desk": 900}
	for id: String in prices:
		_expect(FurnitureCatalog.get_price(id) == prices[id], "precio de %s" % id)
		_expect(FurnitureCatalog.get_resale(id) == prices[id] / 2, "la reventa de %s no es el 50%%" % id)
	_expect(FurnitureCatalog.get_footprint("basic_computer", Vector2i(2, 2), 0).is_empty(),
		"la computadora no debería ocupar casilla")
	_expect(FurnitureCatalog.get_footprint("executive_desk", Vector2i(2, 2), 1) == [Vector2i(2, 2), Vector2i(2, 3)],
		"el escritorio ejecutivo girado debería ocupar (2, 2) y (2, 3)")


func _check_place_and_overlap() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	var money: int = Economy.balance
	var count: int = OfficeState.furniture.size()

	var result: Dictionary = builder.place("simple_desk", Vector2i(4, 4), 0)
	_expect(result["ok"] and Economy.balance == money - 150 and OfficeState.furniture.size() == count + 1,
		"colocar un escritorio sencillo: %s" % [result])
	money = Economy.balance

	for id: String in ["basic_chair", "small_plant", "simple_desk"]:
		result = builder.place(id, Vector2i(4, 4), 0)
		_expect(not result["ok"] and Economy.balance == money, "%s encima del escritorio: %s" % [id, result])
	result = builder.place("executive_desk", Vector2i(3, 4), 0)  # ocuparía (3, 4) y (4, 4)
	_expect(not result["ok"] and Economy.balance == money, "un escritorio de 2 casillas pisando otro: %s" % [result])
	result = builder.place("small_plant", Vector2i(1, 0), 0)
	_expect(not result["ok"], "una planta sobre el escritorio del CEO: %s" % [result])
	result = builder.place("small_plant", OfficeState.entrance, 0)
	_expect(not result["ok"], "una planta tapando la entrada: %s" % [result])
	result = builder.place("executive_desk", Vector2i(5, 3), 0)  # (6, 3) está fuera
	_expect(not result["ok"], "un escritorio que se sale del local: %s" % [result])

	# Un mueble no puede quedar partido por una pared, ni una pared partir un mueble.
	builder.apply([{"edge": Vector3i(4, 6, GridEdge.AXIS_X), "kind": ConstructionCatalog.WALL}])
	money = Economy.balance
	result = builder.place("executive_desk", Vector2i(4, 6), 0)
	_expect(not result["ok"] and Economy.balance == money, "un escritorio atravesado por una pared: %s" % [result])
	builder.place("executive_desk", Vector2i(2, 5), 0)  # (2, 5) y (3, 5)
	result = builder.apply([{"edge": Vector3i(2, 5, GridEdge.AXIS_X), "kind": ConstructionCatalog.WALL}])
	_expect(not result["ok"], "una pared en medio de un escritorio: %s" % [result])

	builder.occupied_cells = [Vector2i(0, 5)]
	result = builder.place("small_plant", Vector2i(0, 5), 0)
	_expect(not result["ok"], "una planta encima de un personaje: %s" % [result])


func _check_access() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	var money: int = Economy.balance
	# Frente a la puerta de la Oficina Ejecutiva, por dentro o por fuera: el CEO no llegaría.
	for cell: Vector2i in [Vector2i(1, 2), Vector2i(1, 3)]:
		var blocked: Dictionary = builder.place("small_plant", cell, 0)
		_expect(not blocked["ok"] and Economy.balance == money and _index_at(cell) < 0,
			"una planta en %s bloquea la puerta de la Oficina Ejecutiva: %s" % [cell, blocked])
	# Un rincón al que solo se llega por (5, 1)–(5, 2): taparlo lo dejaría sin acceso.
	builder.apply([
		{"edge": Vector3i(3, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL},
		{"edge": Vector3i(4, 1, GridEdge.AXIS_Y), "kind": ConstructionCatalog.WALL},
	])
	money = Economy.balance
	var result: Dictionary = builder.place("small_plant", Vector2i(5, 2), 0)
	_expect(not result["ok"] and Economy.balance == money, "una planta que encierra el rincón: %s" % [result])
	result = builder.place("small_plant", Vector2i(4, 4), 0)
	_expect(result["ok"], "una planta en medio del local no bloquea nada: %s" % [result])


func _check_rotate() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	var money: int = Economy.balance
	# El escritorio del CEO girado pisaría su silla.
	var result: Dictionary = builder.rotate(Vector2i(1, 0))
	_expect(not result["ok"] and OfficeState.furniture[_index_at(Vector2i(1, 0))]["rotation"] == 2,
		"el escritorio del CEO giró sobre su silla: %s" % [result])
	builder.place("executive_desk", Vector2i(4, 4), 0)  # (4, 4) y (5, 4)
	money = Economy.balance
	result = builder.rotate(Vector2i(5, 4))
	var index: int = _index_at(Vector2i(4, 5))
	_expect(result["ok"] and Economy.balance == money and index >= 0 and OfficeState.furniture[index]["rotation"] == 1,
		"girar es gratis y el escritorio pasa a ocupar (4, 4) y (4, 5): %s" % [result])
	_expect(_index_at(Vector2i(5, 4)) < 0, "tras girar, (5, 4) debería quedar libre")
	for i: int in range(3):
		builder.rotate(Vector2i(4, 4))
	_expect(OfficeState.furniture[_index_at(Vector2i(4, 4))]["rotation"] == 0, "cuatro giros vuelven al inicio")
	result = builder.rotate(Vector2i(3, 3))
	_expect(not result["ok"], "girar donde no hay mueble: %s" % [result])


# Mover: gratis, con lo que lleva; no encima de otro, no lo de un puesto ajeno; la silla del CEO solo
# dentro de su oficina; lo colgado, a otra pared.
func _check_move() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	builder.place("simple_desk", Vector2i(4, 4), 0)
	builder.install_computer("basic_computer", Vector2i(4, 4))
	var money: int = Economy.balance
	var count: int = OfficeState.furniture.size()
	var index: int = _index_at(Vector2i(4, 4))
	_expect(bool(builder.quote_pick_up(index)["ok"]), "el escritorio se puede tomar")
	var result: Dictionary = builder.move(index, Vector2i(3, 6), 1)
	var moved: int = _index_at(Vector2i(3, 6))
	_expect(result["ok"] and Economy.balance == money and OfficeState.furniture.size() == count and _index_at(Vector2i(4, 4)) < 0
		and moved >= 0 and OfficeState.furniture[moved]["rotation"] == 1 and OfficeState.furniture[moved]["computer"] == "basic_computer",
		"mover es gratis, deja libre el lugar y se lleva la computadora: %s" % [result])
	builder.place("small_plant", Vector2i(4, 4), 0, 0)
	result = builder.move(moved, Vector2i(4, 4), 0)
	_expect(not result["ok"] and _index_at(Vector2i(3, 6)) == moved, "no se mueve encima de otro: %s" % [result])
	_expect(not bool(builder.quote_move(moved, Vector2i(3, 6), 1)["ok"]), "soltarlo donde está no es mover")
	# Planta chica: a otro cuarto de la misma casilla.
	var plant: int = OfficeState.find_furniture_at(Vector2i(4, 4), 0)
	result = builder.move(plant, Vector2i(4, 4), 0, 3)
	_expect(result["ok"] and FurnitureCatalog.get_quarter(OfficeState.furniture[plant]) == 3,
		"una planta chica pasa a otro cuarto: %s" % [result])
	# Silla del CEO: dentro de su oficina sí, fuera no.
	var ceo: Dictionary = OfficeState.find_furniture_assigned_to("ceo")
	var ceo_index: int = OfficeState.furniture.find(ceo)
	var office: int = RoomRules.room_index_at(OfficeState.rooms, ceo["cell"])
	result = builder.move(ceo_index, Vector2i(4, 6), 0)
	_expect(not result["ok"] and String(result["message"]).contains("CEO"), "la silla del CEO no sale de su oficina: %s" % [result])
	var inside: Vector2i = Vector2i(-1, -1)
	for cell: Vector2i in OfficeState.rooms[office]["cells"]:
		if OfficeState.find_furniture_at(cell) < 0 and bool(builder.quote_move(ceo_index, cell, ceo["rotation"])["ok"]):
			inside = cell
			break
	_expect(inside.x >= 0, "la silla del CEO se mueve dentro de su oficina")
	# Lo colgado se mueve a otra pared libre.
	var spots: Array[Array] = []
	for cell: Vector2i in OfficeState.lot.get_cells():
		for rotation: int in range(4):
			if bool(builder.quote_place("painting", cell, rotation)["ok"]):
				spots.append([cell, rotation])
	var hung: int = -1
	if spots.size() >= 2 and bool(builder.place("painting", spots[0][0], spots[0][1])["ok"]):
		hung = OfficeState.find_wall_item(spots[0][0], spots[0][1])
	if hung >= 0:
		result = builder.move(hung, spots[1][0], spots[1][1])
		_expect(result["ok"] and OfficeState.find_wall_item(spots[1][0], spots[1][1]) == hung
			and OfficeState.find_wall_item(spots[0][0], spots[0][1]) < 0, "el cuadro pasa a otra pared: %s" % [result])
		result = builder.move(hung, Vector2i(3, 3), 0)
		_expect(not result["ok"], "en medio del piso no se cuelga: %s" % [result])
	else:
		_expect(false, "se cuelga un cuadro para moverlo")


func _check_computer_and_sell() -> void:
	SaveManager.new_game()
	var builder := Builder.new()
	builder.place("simple_desk", Vector2i(4, 4), 0)
	builder.place("small_plant", Vector2i(4, 6), 0)
	var money: int = Economy.balance

	var result: Dictionary = builder.install_computer("basic_computer", Vector2i(4, 4))
	_expect(result["ok"] and Economy.balance == money - 500
		and OfficeState.furniture[_index_at(Vector2i(4, 4))]["computer"] == "basic_computer",
		"instalar una computadora: %s" % [result])
	money = Economy.balance
	result = builder.install_computer("basic_computer", Vector2i(4, 4))
	_expect(not result["ok"] and Economy.balance == money, "dos computadoras en un escritorio: %s" % [result])
	result = builder.install_computer("basic_computer", Vector2i(4, 6))
	_expect(not result["ok"], "una computadora sobre una planta: %s" % [result])
	result = builder.install_computer("basic_computer", Vector2i(3, 3))
	_expect(not result["ok"], "una computadora en el piso: %s" % [result])
	result = builder.place("basic_computer", Vector2i(3, 3), 0)
	_expect(not result["ok"], "colocar una computadora como mueble: %s" % [result])

	result = builder.sell_furniture_at(Vector2i(4, 4))
	_expect(result["ok"] and Economy.balance == money + 250 and _index_at(Vector2i(4, 4)) >= 0
		and OfficeState.furniture[_index_at(Vector2i(4, 4))]["computer"].is_empty(), "vender la computadora: %s" % [result])
	money = Economy.balance
	result = builder.sell_furniture_at(Vector2i(4, 4))
	_expect(result["ok"] and Economy.balance == money + 75 and _index_at(Vector2i(4, 4)) < 0,
		"vender el escritorio: %s" % [result])
	money = Economy.balance
	result = builder.sell_furniture_at(Vector2i(4, 6))
	_expect(result["ok"] and Economy.balance == money + 20, "vender la planta: %s" % [result])
	money = Economy.balance
	result = builder.sell_furniture_at(Vector2i(1, 1))
	_expect(not result["ok"] and Economy.balance == money and _index_at(Vector2i(1, 1)) >= 0,
		"la silla del CEO no se vende: %s" % [result])
	# El escritorio del CEO trae computadora: se vende primero ella (+250) y luego él (+450).
	result = builder.sell_furniture_at(Vector2i(2, 0))
	_expect(result["ok"] and Economy.balance == money + 250, "vender la computadora del CEO: %s" % [result])
	result = builder.sell_furniture_at(Vector2i(2, 0))
	_expect(result["ok"] and Economy.balance == money + 250 + 450 and _index_at(Vector2i(1, 0)) < 0,
		"vender el escritorio ejecutivo: %s" % [result])
	result = builder.sell_furniture_at(Vector2i(3, 3))
	_expect(not result["ok"], "vender donde no hay mueble: %s" % [result])


# Contorno de selección: sigue la silueta (una L), se separa de ella y va punteado.
func _check_outline() -> void:
	var mask := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		mask.set_pixelv(cell + Vector2i.ONE, Color.WHITE)
	var length: Callable = func(segments: PackedVector2Array) -> float:
		var total: float = 0.0
		for i: int in range(0, segments.size(), 2):
			total += segments[i].distance_to(segments[i + 1])
		return total
	var solid: PackedVector2Array = SelectionOutline.trace(mask, Vector2(10.0, 20.0), 2.0, 0, 0.0)
	_expect(is_equal_approx(length.call(solid), 4.0), "el contorno de la L mide su perímetro (%s)" % solid)
	var area := Rect2(Vector2(10.0, 20.0), Vector2(1.0, 1.0))
	var inside: bool = true
	for point: Vector2 in solid:
		inside = inside and area.grow(0.001).has_point(point)
	_expect(inside, "el contorno queda sobre la silueta (%s)" % solid)
	var apart: PackedVector2Array = SelectionOutline.trace(mask, Vector2.ZERO, 1.0, 0, 1.0)
	_expect(apart.has(Vector2(-1.0, 0.0)) and apart.has(Vector2(0.0, -1.0)), "el contorno se separa hacia afuera (%s)" % apart)
	var dashed: PackedVector2Array = SelectionOutline.trace(mask, Vector2.ZERO, 1.0, 1, 0.0)
	_expect(length.call(dashed) > 0.0 and length.call(dashed) < length.call(SelectionOutline.trace(mask, Vector2.ZERO, 1.0, 0, 0.0)),
		"el contorno va punteado")
	var ring := Image.create_empty(5, 5, false, Image.FORMAT_RGBA8)
	for x: int in range(1, 4):
		for y: int in range(1, 4):
			if Vector2i(x, y) != Vector2i(2, 2):
				ring.set_pixel(x, y, Color.WHITE)
	_expect(is_equal_approx(length.call(SelectionOutline.trace(ring, Vector2.ZERO, 1.0, 0, 0.0)), 12.0),
		"un hueco adentro no lleva contorno")
	var box: Image = SelectionOutline.build_mask([{"polygon": PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 2), Vector2(0, 2)])}],
		Rect2(0, 0, 4, 2), 1.0)
	_expect(box.get_pixel(1, 1).a > 0.5 and box.get_pixel(4, 2).a > 0.5 and box.get_pixel(0, 0).a < 0.5,
		"la caja provisional se pinta en la máscara")


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame


func _click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	await _push(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
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
	var at_cell: Callable = func(cell: Vector2i) -> Vector2:
		return grid.get_canvas_transform() * grid.cell_to_world(cell)
	# Elige la herramienta con clics siguiendo get_button_toward. Un mueble que no está en el inventario se
	# compra antes: Salir, Tienda, su tarjeta, Comprar y Volver al mapa (el precio se cobra ahí; colocarlo es
	# gratis); después Construir, Inventario y su tarjeta.
	var press: Callable = func(tool: String) -> void:
		var shop: ShopScreen = panel.get_shop()
		for i: int in range(10):
			if panel.is_build_mode() and panel.get_selected_tool() == tool:
				break
			if shop.is_open() and OfficeState.get_stock(tool) > 0:
				await _click(shop.get_back_button().get_global_rect().get_center())
			elif shop.is_open() and shop.get_selected() == tool:
				await _click(shop.get_buy_button().get_global_rect().get_center())
			else:
				await _click(panel.get_button_toward(tool).get_global_rect().get_center())

	await _click(panel.get_open_button().get_global_rect().get_center())
	_expect(panel.is_build_mode() and GameClock.is_paused, "no se abrió el modo construcción en pausa")

	var money: int = Economy.balance
	await press.call("simple_desk")
	_expect(panel.get_selected_tool() == "simple_desk" and OfficeState.get_stock("simple_desk") == 1 and not panel.is_shop_open(),
		"comprar el escritorio en la Tienda lo deja en el inventario, elegido")
	await _click(at_cell.call(Vector2i(4, 5)), MOUSE_BUTTON_RIGHT)
	await _click(at_cell.call(Vector2i(4, 5)))
	var index: int = _index_at(Vector2i(4, 5))
	_expect(index >= 0 and OfficeState.furniture[index]["id"] == "simple_desk" and OfficeState.furniture[index]["rotation"] == 1
		and Economy.balance == money - 150 and OfficeState.get_stock("simple_desk") == 0, "colocar el escritorio girado con el ratón")
	_expect(panel.get_selected_tool() == BuildController.TOOL_NONE, "sin escritorios en el inventario queda sin herramienta")
	var views: int = _count_views(grid)
	money = Economy.balance
	await _click(at_cell.call(Vector2i(4, 5)))
	_expect(Economy.balance == money and _count_views(grid) == views, "se colocó otro escritorio encima")

	await press.call("basic_computer")
	await _click(at_cell.call(Vector2i(4, 5)))
	_expect(OfficeState.furniture[_index_at(Vector2i(4, 5))]["computer"] == "basic_computer"
		and Economy.balance == money - 500, "instalar la computadora con el ratón")

	await press.call(BuildController.TOOL_ROTATE)
	await _click(at_cell.call(Vector2i(4, 5)))
	_expect(OfficeState.furniture[_index_at(Vector2i(4, 5))]["rotation"] == 2, "girar con el ratón")
	# Elegir un mueble puesto lo marca con un marco punteado que lo rodea; poner uno nuevo, no.
	var controller: BuildController = game.get_node("BuildController")
	var selection: Rect2 = controller.get_selection_bounds()
	var desk_floor: Vector2 = grid.cell_to_world(Vector2i(4, 5))
	_expect(selection.has_area() and selection.grow(1.0).has_point(desk_floor) and selection.position.y < desk_floor.y - 8.0,
		"girar marca el escritorio con el marco (%s, piso %s)" % [selection, desk_floor])
	_expect(selection.size.x <= GameConstants.TILE_SIZE.x * 2.0 + 1.0, "el marco no es más ancho que el escritorio (%s)" % selection)
	var outline: PackedVector2Array = controller.get_selection_outline()
	var around: bool = outline.size() >= 8
	for point: Vector2 in outline:
		around = around and selection.grow(2.0).has_point(point)
	_expect(around, "el contorno rodea el escritorio (%d puntos)" % outline.size())

	# Silla y planta; la planta frente a la puerta de la oficina se rechaza.
	money = Economy.balance
	await press.call("basic_chair")
	await _click(at_cell.call(Vector2i(4, 6)))
	_expect(_index_at(Vector2i(4, 6)) >= 0 and Economy.balance == money - 60, "colocar la silla con el ratón")
	await press.call("small_plant")
	money = Economy.balance + 40
	await _click(at_cell.call(Vector2i(1, 3)))
	_expect(_index_at(Vector2i(1, 3)) < 0 and OfficeState.get_stock("small_plant") == 1, "la planta bloqueó la puerta de la oficina")
	await _click(at_cell.call(Vector2i(0, 7)))
	_expect(_index_at(Vector2i(0, 7)) >= 0 and Economy.balance == money - 40, "colocar la planta con el ratón")

	# El mueble que se va a poner también lleva su contorno, en la casilla del ratón.
	OfficeState.add_stock("small_plant", 1)
	await press.call("small_plant")
	var spot: Vector2 = grid.cell_to_world(Vector2i(0, 7))
	var new_outline: PackedVector2Array = controller.get_selection_outline()
	var near: bool = not new_outline.is_empty() and not controller.get_selection_bounds().has_area()
	for point: Vector2 in new_outline:
		near = near and point.distance_to(spot) < GameConstants.TILE_SIZE.x
	_expect(near, "poner un mueble nuevo muestra su contorno donde va (%d puntos)" % new_outline.size())
	# Mover con el ratón: un clic toma la silla, otro la suelta; Esc suelta lo tomado sin salir de Construir.
	await press.call(BuildController.TOOL_MOVE)
	money = Economy.balance
	await _click(at_cell.call(Vector2i(4, 6)))
	_expect(controller.is_moving() and controller.get_move_index() == _index_at(Vector2i(4, 6)), "un clic toma la silla")
	await _click(at_cell.call(Vector2i(3, 6)))
	_expect(not controller.is_moving() and _index_at(Vector2i(3, 6)) >= 0 and _index_at(Vector2i(4, 6)) < 0
		and Economy.balance == money, "otro clic la suelta en su nuevo lugar, gratis")
	await _click(at_cell.call(Vector2i(0, 7)))
	_expect(controller.is_moving() and not controller.get_selection_outline().is_empty(), "tomar la planta muestra su contorno")
	_expect(game.handle_escape() == "move" and not controller.is_moving() and panel.is_build_mode()
		and _index_at(Vector2i(0, 7)) >= 0, "Esc la deja donde estaba sin salir de Construir")
	await press.call(BuildController.TOOL_SELL)
	var hover := InputEventMouseMotion.new()
	hover.position = at_cell.call(Vector2i(3, 6))
	await _push(hover)
	_expect(controller.get_selection_bounds().grow(1.0).has_point(grid.cell_to_world(Vector2i(3, 6))),
		"vender marca la silla bajo el ratón (%s)" % controller.get_selection_bounds())
	money = Economy.balance
	await _click(at_cell.call(Vector2i(4, 5)))
	await _click(at_cell.call(Vector2i(4, 5)))
	_expect(_index_at(Vector2i(4, 5)) < 0 and Economy.balance == money + 250 + 75, "vender computadora y escritorio")

	var path: Array[Vector2i] = game.ceo.get_path_cells()
	for cell: Vector2i in path:
		_expect(cell == OfficeState.find_furniture_assigned_to("ceo")["cell"] or _index_at(cell) < 0,
			"el camino del CEO pasa por el mueble de %s" % cell)
	_expect(_count_views(grid) == OfficeState.furniture.size(), "los muebles dibujados no coinciden con los guardados")

	var saved: Dictionary = JSON.parse_string(JSON.stringify(OfficeState.export_state()))
	var before: String = JSON.stringify(OfficeState.export_state())
	OfficeState.import_state(saved)
	_expect(JSON.stringify(OfficeState.export_state()) == before, "los muebles no se restauraron igual")
	game.queue_free()
	await get_tree().process_frame


func _count_views(grid: OfficeGrid) -> int:
	var count: int = 0
	for child: Node in grid.get_node("Objects").get_children():
		if child is FurnitureView and child.part == FurnitureView.PART_MAIN and not child.is_queued_for_deletion():
			count += 1
	return count
