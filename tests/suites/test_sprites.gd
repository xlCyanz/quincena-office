# Prueba de los sprites conectados al juego (fase 8): suelo, paredes con sus postes de esquina,
# árboles, muebles de piso y personajes se dibujan con las imágenes de data/sprites.json (SpriteLibrary).
extends Node

signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_library()
	_check_furniture()
	_check_characters()
	await _check_game()
	finished.emit(_failures, _checks)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FALLO: " + message)


func _check_library() -> void:
	_expect(is_equal_approx(SpriteLibrary.get_scale(), 2.0), "2 px de sprite por px del mundo")
	var sprites: Dictionary = SpriteLibrary.get_data().get("sprites", {})
	_expect(sprites.size() >= 40, "hay sprites: %d" % sprites.size())
	for sprite: String in sprites:
		_expect(SpriteLibrary.get_texture(sprite) != null, "%s tiene su imagen importada" % sprite)
	_expect(not SpriteLibrary.has_sprite("no_existe") and SpriteLibrary.get_texture("no_existe") == null, "un nombre desconocido no da imagen")
	# El tramo alto mide 72×160 de sprite con el apoyo en (36, 142): en el mundo, la mitad.
	var rect: Rect2 = SpriteLibrary.get_rect("wall_tall_x")
	_expect(rect.is_equal_approx(Rect2(-18.0, -71.0, 36.0, 80.0)), "rectángulo de la pared alta en el mundo: %s" % rect)
	for kind: String in [ConstructionCatalog.WALL, ConstructionCatalog.DOOR, ConstructionCatalog.WINDOW, ConstructionCatalog.GLASS_DOOR]:
		for tall: bool in [true, false]:
			for axis: int in [GridEdge.AXIS_X, GridEdge.AXIS_Y]:
				var sprite: String = EdgePieceView.get_sprite_name(kind, tall, axis)
				_expect(SpriteLibrary.has_sprite(sprite), "hay sprite %s" % sprite)
	_expect(EdgePieceView.get_sprite_name("wall", true, GridEdge.AXIS_X) == "wall_tall_x", "nombre del tramo")
	# Postes: solo en las L.
	var plus_x: int = EdgePieceView.ARM_PLUS_X
	var plus_y: int = EdgePieceView.ARM_PLUS_Y
	var minus_x: int = EdgePieceView.ARM_MINUS_X
	var minus_y: int = EdgePieceView.ARM_MINUS_Y
	_expect(EdgePieceView.get_corner_sprite({plus_x: true, plus_y: true}) == "wall_tall_corner", "esquina del fondo")
	_expect(EdgePieceView.get_corner_sprite({minus_y: true, plus_x: false}) == "wall_tall_corner_left", "esquina izquierda")
	_expect(EdgePieceView.get_corner_sprite({minus_x: true, plus_y: false}) == "wall_tall_corner_right", "esquina derecha")
	_expect(EdgePieceView.get_corner_sprite({minus_x: false, minus_y: false}) == "wall_low_corner", "esquina del frente")
	_expect(EdgePieceView.get_corner_sprite({plus_x: false, plus_y: false}) == "wall_low_corner_back", "L baja de atrás")
	_expect(EdgePieceView.get_corner_sprite({plus_x: true, minus_x: true}) == "", "dos tramos en línea no llevan poste")
	_expect(EdgePieceView.get_corner_sprite({plus_x: true, plus_y: true, minus_x: true}) == "", "una T no lleva poste")
	# Familias de pasto: fijas por casilla y salen las cuatro.
	var seen: Dictionary[String, int] = {}
	for x: int in range(60):
		for y: int in range(60):
			var family: String = MapDecor.get_grass_family(Vector2i(x, y))
			seen[family] = int(seen.get(family, 0)) + 1
	_expect(seen.size() == MapDecor.GRASS_FAMILIES.size(), "salen las cuatro familias de pasto: %s" % seen)
	_expect(MapDecor.get_grass_family(Vector2i(7, 9)) == MapDecor.get_grass_family(Vector2i(7, 9)), "la familia de una casilla no cambia")


# Cada mueble de piso tiene su sprite en las 4 rotaciones; las sillas van en asiento y respaldo.
func _check_furniture() -> void:
	for id: String in FurnitureCatalog.get_ids():
		for rotation: int in range(4):
			var sprite: String = SpriteLibrary.get_furniture_sprite(id, rotation)
			if FurnitureCatalog.is_monitor(id):
				# La pantalla extra no tiene sprite propio: va dibujada en el del escritorio largo.
				_expect(sprite.is_empty(), "%s no tiene sprite propio" % id)
				continue
			if FurnitureCatalog.is_wall_mounted(id):
				_expect(sprite.is_empty(), "%s (de pared) no está entre los muebles de piso" % id)
				for axis: int in [GridEdge.AXIS_X, GridEdge.AXIS_Y]:
					var hung: String = SpriteLibrary.get_wall_item_sprite(id, axis, rotation)
					_expect(SpriteLibrary.get_texture(hung) != null and hung.ends_with("_x" if axis == GridEdge.AXIS_X else "_y"),
						"%s tiene sprite para el eje %d: «%s»" % [id, axis, hung])
				_expect(SpriteLibrary.get_wall_item_base(id) > 0.0, "%s empieza sobre el piso" % id)
				continue
			_expect(SpriteLibrary.get_texture(sprite) != null, "%s r%d tiene sprite: «%s»" % [id, rotation, sprite])
			if FurnitureView.has_backrest(id):
				_expect(sprite.contains("_seat") and SpriteLibrary.get_furniture_sprite(id, rotation, "back").contains("_back"),
					"%s r%d va en asiento y respaldo" % [id, rotation])
			if id != "rug":
				_expect(not SpriteLibrary.get_furniture_sprite(id, rotation, "shadow").is_empty(), "%s r%d tiene sombra" % [id, rotation])
	_expect(SpriteLibrary.get_furniture_sprite("basic_chair", 5) == SpriteLibrary.get_furniture_sprite("basic_chair", 1),
		"la rotación da la vuelta")
	_expect(SpriteLibrary.get_furniture_sprite("small_plant", 0).ends_with("_q"), "el mueble chico usa su versión de cuarto de casilla")
	_expect(SpriteLibrary.get_furniture_sprite("no_existe", 0).is_empty(), "un mueble desconocido no da sprite")
	# El escritorio largo se dibuja entero con lo que lleva: un sprite por computadora y pantallas extra.
	for rotation: int in range(4):
		for entry: Array in [["basic_computer", 0, "desk_long_basic"], ["pro_computer", 0, "desk_long_pro1"],
				["pro_computer", 1, "desk_long_pro2"], ["pro_computer", 2, "desk_long_pro3"]]:
			var whole: String = SpriteLibrary.get_desk_set_sprite("long_desk", entry[0], entry[1], rotation)
			_expect(whole == "%s_r%d" % [entry[2], rotation] and SpriteLibrary.get_texture(whole) != null
				and SpriteLibrary.get_texture(whole + "_shadow") != null, "largo con %s y %d pantallas extra: «%s»" % [entry[0], entry[1], whole])
	_expect(SpriteLibrary.get_desk_set_sprite("simple_desk", "pro_computer", 0, 0).is_empty()
		and SpriteLibrary.get_desk_set_sprite("long_desk", "", 0, 0).is_empty(), "el sencillo y el largo vacío van con su sprite de siempre")
	_expect(SpriteLibrary.get_seat_x("desk_long_pro1") > 0.5 and is_equal_approx(SpriteLibrary.get_seat_x("computer_basic"), 0.5)
		and SpriteLibrary.get_seat_x("no_existe") < 0.0, "dónde queda el teclado de cada sprite")


# Hojas de personajes: los 6 conjuntos en sus 3 paletas, con todas las poses.
func _check_characters() -> void:
	for woman: bool in [false, true]:
		for outfit: String in ["casual", "office", "executive"]:
			for number: int in range(3):
				var look: String = OfficeCharacter.make_look(woman, outfit, number)
				_expect(SpriteLibrary.has_character_look(look), "hay hoja para %s" % look)
	_expect(OfficeCharacter.make_look(true, "casual", 0) == "woman" and OfficeCharacter.make_look(false, "office", 4) == "office_v1",
		"nombres de los aspectos")
	_expect(not SpriteLibrary.has_character_look("no_existe"), "un aspecto desconocido no tiene hoja")
	_expect(SpriteLibrary.get_character_frames("walk") == 8 and SpriteLibrary.get_character_frames("idle") == 4
		and SpriteLibrary.get_character_frames("type") == 4 and SpriteLibrary.get_character_frames("sit") == 1
		and SpriteLibrary.get_character_frames("no_existe") == 0, "cuadros de cada pose")
	_expect(OfficeCharacter.is_woman_name("Ana García") and not OfficeCharacter.is_woman_name("Carlos García"), "el nombre dice si es mujer")


func _check_game() -> void:
	SaveManager.new_game()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	GameClock.stop()
	var grid: OfficeGrid = game.get_node("OfficeGrid")
	var floor_layer: TileMapLayer = grid.get_node("Floor")
	var source: TileSetAtlasSource = floor_layer.tile_set.get_source(floor_layer.tile_set.get_source_id(0))
	_expect(source.texture.resource_path == String(SpriteLibrary.get_ground()["file"]), "el suelo usa el atlas de sprites")
	var rows: Dictionary = grid.get("_atlas_rows")
	for style: String in ["bare", "carpet", "wood", "ceramic", MapDecor.GRASS, MapDecor.OUTSIDE, MapDecor.PATH,
			MapDecor.SIDEWALK, MapDecor.ROAD, ConstructionCatalog.TERRAIN]:
		_expect(rows.has(style), "el atlas tiene %s" % style)
	# Dentro del local, cada casilla usa una variante de su piso; afuera, pasto o camino.
	var variants: Dictionary[int, bool] = {}
	for cell: Vector2i in floor_layer.get_used_cells():
		var coords: Vector2i = floor_layer.get_cell_atlas_coords(cell)
		_expect(source.has_tile(coords), "casilla %s con una losa que existe" % cell)
		if grid.is_in_lot(cell):
			variants[coords.x] = true
	_expect(variants.size() > 2, "el piso usa más de dos variantes: %d" % variants.size())
	# Paredes: cada tramo con su sprite; las cuatro esquinas del local llevan poste.
	var with_post: int = 0
	var pieces: int = 0
	for child: Node in grid.get_node("Objects").get_children():
		if child is EdgePieceView and not child.is_queued_for_deletion():
			var view: EdgePieceView = child
			pieces += 1
			_expect(view.get_sprite() == EdgePieceView.get_sprite_name(view.kind, view.tall, view.edge.z),
				"el tramo %s usa %s" % [view.name, view.get_sprite()])
			if view.get_post_count() > 0:
				with_post += 1
	_expect(pieces > 0 and with_post >= 8, "tramos con poste de esquina: %d de %d" % [with_post, pieces])
	var trees: Array[TreeView] = grid.get_trees()
	var kinds: Dictionary[String, bool] = {}
	for tree: TreeView in trees:
		_expect(SpriteLibrary.has_sprite(tree.get_sprite()) and SpriteLibrary.has_sprite(tree.get_sprite() + "_shadow"),
			"árbol con sprite y sombra: %s" % tree.get_sprite())
		kinds[tree.get_sprite()] = true
	_expect(trees.size() > 0 and kinds.size() > 3, "árboles de varias clases: %d" % kinds.size())
	# Muebles: cada pieza de piso se dibuja con su sprite.
	var furniture_views: int = 0
	for child: Node in grid.get_node("Objects").get_children():
		if child is FurnitureView and not child.is_queued_for_deletion():
			var piece: FurnitureView = child
			if FurnitureCatalog.is_wall_mounted(piece.item_id):
				continue
			furniture_views += 1
			_expect(SpriteLibrary.has_sprite(piece.get_sprite()), "%s usa un sprite: «%s»" % [piece.name, piece.get_sprite()])
	_expect(furniture_views >= 2, "hay muebles dibujados: %d" % furniture_views)
	# Objetos de pared: con sprite en las caras que se ven de frente (miran a +x o +y); de espaldas, el dibujo provisional.
	OfficeState.furniture.append({"id": "painting", "cell": Vector2i(0, 4), "rotation": 1})
	OfficeState.furniture.append({"id": "wall_clock", "cell": Vector2i(4, 0), "rotation": 2})
	OfficeState.furniture.append({"id": "painting", "cell": Vector2i(2, 1), "rotation": 3})
	EventBus.office_changed.emit()
	await get_tree().process_frame
	var hung_sprites: Dictionary[String, String] = {}
	for child: Node in grid.get_node("Objects").get_children():
		if child is FurnitureView and not child.is_queued_for_deletion() and FurnitureCatalog.is_wall_mounted((child as FurnitureView).item_id):
			hung_sprites["%s_%d" % [(child as FurnitureView).item_id, (child as FurnitureView).rotation_index]] = (child as FurnitureView).get_sprite()
	_expect(String(hung_sprites.get("painting_1", "")).begins_with("painting") and String(hung_sprites.get("painting_1", "")).ends_with("_x"),
		"cuadro en pared del eje x: %s" % hung_sprites.get("painting_1", ""))
	_expect(hung_sprites.get("wall_clock_2", "") == "wall_clock_y", "reloj en pared del eje y: %s" % hung_sprites.get("wall_clock_2", ""))
	_expect(hung_sprites.get("painting_3", "?") == "", "de espaldas no hay sprite")
	# El CEO: camina mirando hacia donde va y, sentado frente a su computadora, teclea mirándola.
	var ceo: Ceo = game.get("ceo")
	_expect(SpriteLibrary.has_character_look(ceo.look), "el CEO tiene aspecto: %s" % ceo.look)
	ceo.update_routine(true)
	GameClock.start()
	var walked: Dictionary[String, bool] = {}
	var guard: int = 0
	var facing_ok: bool = true
	while ceo.activity != OfficeCharacter.Activity.SEATED and guard < 4000:
		var before: Vector2 = ceo.grid_position
		await get_tree().process_frame
		guard += 1
		var walking: Dictionary = ceo.get_sprite_state()
		walked[String(walking["pose"])] = true
		# En un tramo recto (no en el cuadro en que dobla) mira hacia donde avanzó.
		var moved: Vector2 = ceo.grid_position - before
		if String(walking["pose"]) == "walk" and (moved.x == 0.0) != (moved.y == 0.0):
			facing_ok = facing_ok and FurnitureCatalog.get_front(int(walking["facing"])) == Vector2i(moved.sign())
	_expect(facing_ok, "camina mirando hacia donde va")
	GameClock.stop()
	_expect(walked.has("walk"), "caminando usa la animación de caminar")
	var seated: Dictionary = ceo.get_sprite_state()
	_expect(String(seated["pose"]) == "type", "sentado frente a su computadora teclea: %s" % seated["pose"])
	var desk_cell: Vector2i = ceo.get_seat_cell() + FurnitureCatalog.get_front(int(seated["facing"]))
	var desk: int = OfficeState.find_furniture_at(desk_cell)
	_expect(desk >= 0 and not String(OfficeState.furniture[desk].get("computer", "")).is_empty(), "mira hacia su computadora")
	ceo.standing = true
	_expect(String(ceo.get_sprite_state()["pose"]) == "idle", "de pie en su lugar no teclea")
	ceo.standing = false
	game.queue_free()
	await get_tree().process_frame
