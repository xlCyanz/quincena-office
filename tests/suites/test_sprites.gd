# Prueba de los sprites conectados al juego (fase 8): suelo, paredes con sus postes de esquina
# y árboles se dibujan con las imágenes de data/sprites.json (SpriteLibrary).
extends Node

signal finished(failures: int, checks: int)

const GAME_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	_check_library()
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
	game.queue_free()
	await get_tree().process_frame
