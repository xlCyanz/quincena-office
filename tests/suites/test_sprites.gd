# Sprites conectados: suelo, paredes con postes, árboles, muebles de piso y personajes se dibujan
# con las imágenes de data/sprites.json (SpriteLibrary).
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
	await _check_palette_drawing()
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
	# Tramo alto de 72×160 con apoyo en (36, 142): en el mundo, la mitad.
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
	# Poste: wall_post_<−x><−y><+x><+y> con n (nada), l (bajo) o t (alto).
	_expect(EdgePieceView.get_corner_sprite({plus_x: true, plus_y: true}) == "wall_post_nntt", "esquina del fondo")
	_expect(EdgePieceView.get_corner_sprite({minus_y: true, plus_x: false}) == "wall_post_ntln", "esquina izquierda: alta que termina sobre baja")
	_expect(EdgePieceView.get_corner_sprite({minus_x: true, plus_y: false}) == "wall_post_tnnl", "esquina derecha")
	_expect(EdgePieceView.get_corner_sprite({minus_x: false, minus_y: false}) == "wall_post_llnn", "esquina del frente")
	_expect(EdgePieceView.get_corner_sprite({minus_y: true, plus_x: true}) == "wall_post_nttn", "con paredes arriba, la izquierda con las dos altas")
	_expect(EdgePieceView.get_corner_sprite({plus_x: true, minus_x: true}) == "" and EdgePieceView.get_corner_sprite({plus_y: false, minus_y: false}) == "",
		"dos tramos del mismo alto en línea no llevan poste")
	_expect(EdgePieceView.get_corner_sprite({plus_x: true, minus_x: false}) == "wall_post_lntn", "en línea con otro alto sí")
	_expect(EdgePieceView.get_corner_sprite({plus_x: true, plus_y: true, minus_x: true}) == "wall_post_tntt", "una T lleva su poste")
	_expect(EdgePieceView.get_corner_sprite({plus_x: false, plus_y: false, minus_x: false, minus_y: false}) == "wall_post_llll", "un cruce también")
	_expect(EdgePieceView.get_corner_sprite({plus_x: true}) == "", "la punta de una pared suelta no lleva poste")
	_expect(EdgePieceView.get_arm_code(ConstructionCatalog.DOOR, false) == "d" and EdgePieceView.get_arm_code(ConstructionCatalog.DOOR, true) == "h"
		and EdgePieceView.get_arm_code(ConstructionCatalog.WALL, true) == "t" and EdgePieceView.get_arm_code(ConstructionCatalog.GLASS_DOOR, false) == "l",
		"códigos de brazo: puertas d/h, lo demás como pared")
	_expect(EdgePieceView.get_corner_sprite({minus_x: "d", plus_x: "d"}) == "wall_post_dndn", "dos puertas bajas en línea: jamba compartida")
	_expect(EdgePieceView.get_corner_sprite({minus_y: "h", plus_y: "h"}) == "wall_post_nhnh", "dos puertas altas en línea: jamba compartida")
	_expect(EdgePieceView.get_corner_sprite({minus_x: "l", plus_x: "d"}) == "" and EdgePieceView.get_corner_sprite({minus_x: "d", plus_x: "l"}) == "",
		"pared y puerta del mismo alto en línea: sin poste")
	_expect(EdgePieceView.get_corner_sprite({minus_x: "t", plus_x: "t", plus_y: "d"}) == "wall_post_tntd", "puerta baja contra una pared alta: el poste la dibuja como puerta")
	_expect(EdgePieceView.get_corner_sprite({minus_y: "d", plus_x: "l"}) == "wall_post_nlln", "una puerta atrás del poste cuenta como pared")
	# Familias de pasto: fijas por casilla y salen las cuatro.
	var seen: Dictionary[String, int] = {}
	for x: int in range(60):
		for y: int in range(60):
			var family: String = MapDecor.get_grass_family(Vector2i(x, y))
			seen[family] = int(seen.get(family, 0)) + 1
	_expect(seen.size() == MapDecor.GRASS_FAMILIES.size(), "salen las cuatro familias de pasto: %s" % seen)
	_expect(MapDecor.get_grass_family(Vector2i(7, 9)) == MapDecor.get_grass_family(Vector2i(7, 9)), "la familia de una casilla no cambia")


# Cada mueble de piso con sprite en las 4 rotaciones; las sillas en asiento y respaldo.
func _check_furniture() -> void:
	for id: String in FurnitureCatalog.get_ids():
		for rotation: int in range(4):
			var sprite: String = SpriteLibrary.get_furniture_sprite(id, rotation)
			if FurnitureCatalog.is_monitor(id):
				# La pantalla extra va dibujada en el escritorio largo.
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
	# El escritorio largo se dibuja entero: un sprite por computadora y pantallas extra.
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


# Las paletas _v1 y _v2 son la hoja base con un shader que cambia colores exactos.
func _check_palettes() -> void:
	var characters: Dictionary = SpriteLibrary.get_data()["characters"]
	_expect(characters["looks"]["office_f1_v2"] == characters["looks"]["office_f1"]
		and characters["tool_looks"]["cleaning_v1"] == characters["tool_looks"]["cleaning"], "las paletas usan la hoja base")
	_expect(SpriteLibrary.get_character_material("office") == null and SpriteLibrary.get_character_material("no_existe") == null,
		"la paleta base va sin shader")
	var material: ShaderMaterial = SpriteLibrary.get_character_material("woman_executive_f2_v2")
	var palette: Dictionary = characters["palettes"]["woman_executive_f2_v2"]
	_expect(material != null and material == SpriteLibrary.get_character_material("woman_executive_f2_v2")
		and int(material.get_shader_parameter("color_count")) == palette["from"].size() and palette["from"].size() > 0
		and palette["from"].size() <= 48, "la otra paleta trae su shader con la tabla de colores")
	var from_colors: PackedVector3Array = material.get_shader_parameter("from_colors")
	var first := Color(String(palette["from"][0]))
	_expect(from_colors[0].is_equal_approx(Vector3(first.r, first.g, first.b)), "los colores de la tabla llegan al shader")


# Al dibujar, el lienzo toma la paleta del aspecto (y la suelta con la base).
func _check_palette_drawing() -> void:
	var canvas := Node2D.new()
	var drawn: Array[String] = ["office_v1"]
	canvas.draw.connect(func() -> void: SpriteLibrary.draw_character(canvas, drawn[0], "stand", 0, 0))
	add_child(canvas)
	await get_tree().process_frame
	var first_material: Material = canvas.material
	drawn[0] = "office"
	canvas.queue_redraw()
	await get_tree().process_frame
	_expect(first_material != null and first_material == SpriteLibrary.get_character_material("office_v1")
		and canvas.material == null, "al dibujar, el lienzo toma la paleta del aspecto")
	canvas.queue_free()


# Los 8 conjuntos de personajes en sus 3 formas y 3 paletas, con todas las poses.
func _check_characters() -> void:
	for woman: bool in [false, true]:
		for outfit: String in ["casual", "office", "executive", "cleaning"]:
			for number: int in range(9):
				var look: String = OfficeCharacter.make_look(woman, outfit, number)
				_expect(SpriteLibrary.has_character_look(look), "hay hoja para %s" % look)
	_expect(OfficeCharacter.make_look(true, "casual", 0) == "woman" and OfficeCharacter.make_look(false, "office", 1) == "office_v1"
		and OfficeCharacter.make_look(false, "office", 4) == "office_f1_v1"
		and OfficeCharacter.make_look(true, "executive", 8) == "woman_executive_f2_v2", "nombres de los aspectos")
	_expect(not SpriteLibrary.has_character_look("no_existe"), "un aspecto desconocido no tiene hoja")
	_check_palettes()
	_expect(SpriteLibrary.get_character_frames("walk") == 8 and SpriteLibrary.get_character_frames("idle") == 4
		and SpriteLibrary.get_character_frames("type") == 4 and SpriteLibrary.get_character_frames("sit") == 1
		and SpriteLibrary.get_character_frames("no_existe") == 0, "cuadros de cada pose")
	for chair: String in ["basic_chair", "ergonomic_chair", "mesh_chair", "manager_chair", "executive_chair",
			"visitor_chair", "stool"]:
		_expect(not SpriteLibrary.get_furniture_sprite(chair, 0).is_empty(), "%s tiene dibujo" % chair)
		_expect(SpriteLibrary.has_character_pose("sit_" + chair) and SpriteLibrary.get_character_frames("type_" + chair) == 4,
			"hay cuadros de sentado y tecleando en %s" % chair)
	_expect(not SpriteLibrary.has_character_pose("sit_waiting_sofa"), "en un asiento que no es silla, la pose suelta")
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
	# Dentro del local, una variante de su piso por casilla; afuera, pasto o camino.
	var variants: Dictionary[int, bool] = {}
	for cell: Vector2i in floor_layer.get_used_cells():
		var coords: Vector2i = floor_layer.get_cell_atlas_coords(cell)
		_expect(source.has_tile(coords), "casilla %s con una losa que existe" % cell)
		if grid.is_in_lot(cell):
			variants[coords.x] = true
	_expect(variants.size() > 2, "el piso usa más de dos variantes: %d" % variants.size())
	# Cada tramo con su sprite; las cuatro esquinas del local llevan poste.
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
	var furniture_views: int = 0
	for child: Node in grid.get_node("Objects").get_children():
		if child is FurnitureView and not child.is_queued_for_deletion():
			var piece: FurnitureView = child
			if FurnitureCatalog.is_wall_mounted(piece.item_id):
				continue
			furniture_views += 1
			_expect(SpriteLibrary.has_sprite(piece.get_sprite()), "%s usa un sprite: «%s»" % [piece.name, piece.get_sprite()])
	_expect(furniture_views >= 2, "hay muebles dibujados: %d" % furniture_views)
	# Objetos de pared: sprite en las caras que se ven de frente (+x o +y); de espaldas, el dibujo provisional.
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
	# Con ↕ todas las paredes van altas y lo colgado en una pared baja se ve a su tamaño.
	var front_edge: Vector3i = OfficeState.get_entrance_edge()
	_expect(not grid.is_tall_edge(front_edge) and not game.are_walls_up(), "al empezar las paredes de adelante van bajas")
	game.set_walls_up(true)
	await get_tree().process_frame
	var all_tall: bool = true
	for child: Node in grid.get_node("Objects").get_children():
		if child is EdgePieceView and not child.is_queued_for_deletion():
			all_tall = all_tall and (child as EdgePieceView).tall
	_expect(game.are_walls_up() and grid.is_tall_edge(front_edge) and all_tall, "paredes arriba: todas a su alto")
	_expect(game.menu_bar_button("WallsButton") != null and game.menu_bar_button("WallsButton").button_pressed
		and not game.menu_bar_button("WallsButton").tooltip_text.is_empty(), "el botón ↕ queda marcado y tiene descripción")
	game.set_walls_up(false)
	await get_tree().process_frame
	_expect(not game.are_walls_up() and not grid.is_tall_edge(front_edge), "paredes abajo otra vez")
	# Al elegir un objeto de pared en Construir suben solas y al salir vuelven.
	var build_panel: BuildPanel = game.get_node("BuildPanel")
	build_panel.set_build_mode(true)
	build_panel.select_tool("painting")
	await get_tree().process_frame
	_expect(game.are_walls_up() and not game.menu_bar_button("WallsButton").button_pressed, "colgando algo las paredes suben solas")
	build_panel.select_tool(BuildController.TOOL_WALL)
	await get_tree().process_frame
	_expect(not game.are_walls_up(), "con otra herramienta bajan")
	build_panel.set_build_mode(false)
	await get_tree().process_frame
	# El CEO camina mirando hacia donde va y, sentado frente a su computadora, teclea mirándola.
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
	# Sentado se dibuja con su silla en un solo cuadro: la silla no se dibuja aparte.
	_expect(OfficeCharacter.draws_chair_at(ceo.get_seat_cell()), "la silla del CEO se dibuja con él")
	ceo.standing = true
	_expect(String(ceo.get_sprite_state()["pose"]) == "idle", "de pie en su lugar no teclea")
	_expect(not OfficeCharacter.draws_chair_at(ceo.get_seat_cell()), "de pie, la silla vuelve a dibujarse sola")
	ceo.standing = false
	_expect(OfficeCharacter.draws_chair_at(ceo.get_seat_cell()), "y al sentarse otra vez, con él")
	game.queue_free()
	await get_tree().process_frame
