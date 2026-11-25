# Cuadrícula isométrica: dibuja el piso, el mapa (MapDecor) y la casilla bajo el cursor. Único lugar
# que convierte entre píxeles y casillas. La vista es siempre desde la misma esquina.
class_name OfficeGrid
extends Node2D

## Casilla bajo el cursor, o NO_CELL fuera del local.
const NO_CELL := Vector2i(-1, -1)

## Píxeles que cada rombo del piso se pasa de su borde para no dejar huecos.
const TILE_OVERLAP_PX: float = 1.0

## Casillas hacia atrás (x e y menores) de la casilla de fuera de un borde donde se busca local
## (una pared alta lo taparía).
const BEHIND_WALL_REACH: int = 3

## Paredes arriba: todas las piezas a su alto; abajo, solo las de atrás. Solo la vista: al cambiarlo, build().
var walls_up: bool = false

var hovered_cell: Vector2i = NO_CELL

var _floor_source_id: int = -1
# El TileSet del suelo se pinta una vez por ejecución (~1 s) y se comparte (depende solo de data/).
static var _shared_tile_set: TileSet = null
static var _shared_rows: Dictionary[String, int] = {}
static var _shared_columns: Dictionary[String, int] = {}
static var _shared_source_id: int = -1
# true si el TileSet salió del atlas de sprites y no de GroundPainter.
static var _shared_from_sprites: bool = false
var _lot := Lot.new()
var _site_rect := Rect2i()
# Casilla de fuera junto a la entrada (de ahí sale el camino a la calle).
var _entrance_outside := Vector2i(-1, -1)
# Fila del atlas de cada piso o estilo del mapa, y cuántas variantes tiene.
var _atlas_rows: Dictionary[String, int] = {}
var _atlas_columns: Dictionary[String, int] = {}
# Plano del mapa (MapDecor.plan) y sus datos, para no rehacerlo si no cambió.
var _map_plan: Dictionary = {}
var _map_signature: String = ""
# Lo de fuera del solar (bajo el piso) y la línea del límite.
var _surroundings := TileMapLayer.new()
var _site_border := SiteBorder.new()

@onready var _floor: TileMapLayer = $Floor
@onready var _highlight: CellHighlight = $CellHighlight
@onready var _room_overlay: RoomOverlay = $RoomOverlay
# Capa ordenada por Y: muebles y personajes (lo de más abajo en pantalla, encima).
@onready var _objects: Node2D = $Objects
# Manchas de suciedad; se crea en _ready, encima del tinte de habitaciones.
var _dirt_overlay := DirtOverlay.new()


func _ready() -> void:
	_floor.tile_set = _get_tile_set()
	_surroundings.name = "Surroundings"
	_surroundings.tile_set = _floor.tile_set
	# El suelo tiene DETAIL veces más píxeles: la capa se achica a la casilla. Sin suavizar de cerca, mipmaps de lejos.
	for layer: TileMapLayer in [_floor, _surroundings]:
		layer.scale = Vector2.ONE / GroundPainter.DETAIL
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	add_child(_surroundings)
	move_child(_surroundings, _floor.get_index())
	_site_border.name = "SiteBorder"
	add_child(_site_border)
	move_child(_site_border, _floor.get_index() + 1)
	_highlight.visible = false
	_room_overlay.setup(self)
	_dirt_overlay.name = "DirtOverlay"
	add_child(_dirt_overlay)
	move_child(_dirt_overlay, _room_overlay.get_index() + 1)
	_dirt_overlay.setup(self)


func _process(_delta: float) -> void:
	update_hover(get_global_mouse_position())


## Dibuja la oficina (piso, bordes, muebles y tinte de habitaciones) con los datos de OfficeState,
## y alrededor el terreno del solar (ver set_site).
func build(lot: Lot, floors: Dictionary[Vector2i, String], edges: Dictionary[Vector3i, String],
		furniture: Array[Dictionary], rooms: Array[Dictionary] = []) -> void:
	_lot = lot
	_update_map(edges)
	_floor.clear()
	var tiles: Dictionary = _map_plan.get("tiles", {})
	for x: int in range(_site_rect.position.x, _site_rect.end.x):
		for y: int in range(_site_rect.position.y, _site_rect.end.y):
			var cell := Vector2i(x, y)
			if not lot.has_point(cell):
				_floor.set_cell(cell, _floor_source_id, _map_tile(cell, tiles.get(cell, MapDecor.GRASS)))
	for cell: Vector2i in lot.get_cells():
		var floor_type: String = floors.get(cell, ConstructionCatalog.BARE_FLOOR)
		var row: int = _atlas_rows.get(floor_type, _atlas_rows[ConstructionCatalog.BARE_FLOOR])
		_floor.set_cell(cell, _floor_source_id, Vector2i(_floor_variant(cell, floor_type), row))
	hovered_cell = NO_CELL
	_highlight.visible = false
	_place_edge_pieces(edges)
	_place_furniture(furniture)
	_room_overlay.set_rooms(rooms)
	_dirt_overlay.set_rooms(rooms)


## Redibuja la suciedad de las habitaciones.
func set_dirt(rooms: Array[Dictionary]) -> void:
	_dirt_overlay.set_rooms(rooms)


## Capa de suciedad (para pruebas).
func get_dirt_overlay() -> DirtOverlay:
	return _dirt_overlay


## Muestra u oculta el tinte de las habitaciones.
func set_rooms_visible(rooms_visible: bool) -> void:
	_room_overlay.visible = rooms_visible


## Píxeles del mundo a posición de cuadrícula con decimales (inversa de grid_to_world).
func world_to_grid(world_position: Vector2) -> Vector2:
	var origin: Vector2 = cell_to_world(Vector2i.ZERO)
	var basis := Transform2D(cell_to_world(Vector2i(1, 0)) - origin, cell_to_world(Vector2i(0, 1)) - origin, origin)
	return basis.affine_inverse() * world_position


func _place_edge_pieces(edges: Dictionary[Vector3i, String]) -> void:
	for child: Node in _objects.get_children():
		if child is EdgePieceView:
			_objects.remove_child(child)
			child.queue_free()
	var views: Dictionary[Vector3i, EdgePieceView] = {}
	for edge: Vector3i in edges:
		var view := EdgePieceView.new()
		view.name = "%s_%d_%d_%d" % [edges[edge], edge.x, edge.y, edge.z]
		_objects.add_child(view)
		view.setup(self, edge, edges[edge], is_tall_edge(edge), EdgePieceView.get_double_half(edges, edge))
		views[edge] = view
	_place_corner_posts(views)


# Postes de esquina: cada tramo dibuja después de sí los postes de sus puntas, así quedan encima
# y se ordenan con él.
func _place_corner_posts(views: Dictionary[Vector3i, EdgePieceView]) -> void:
	# Vértice (x, y) = punto (x + 0.5, y + 0.5); brazo = hacia dónde sale el tramo.
	var corners: Dictionary[Vector2i, Dictionary] = {}
	for edge: Vector3i in views:
		for end: Array in _edge_vertices(edge):
			var arms: Dictionary = corners.get_or_add(end[0], {})
			arms[end[1]] = EdgePieceView.get_arm_code(views[edge].kind, views[edge].tall)
	for edge: Vector3i in views:
		for end: Array in _edge_vertices(edge):
			var sprite: String = EdgePieceView.get_corner_sprite(corners[end[0]])
			if not sprite.is_empty():
				views[edge].add_post(sprite, grid_to_world(Vector2(end[0]) + Vector2(0.5, 0.5)))


# Los dos vértices de un borde con el brazo que es para cada uno.
func _edge_vertices(edge: Vector3i) -> Array[Array]:
	if edge.z == GridEdge.AXIS_X:
		return [[Vector2i(edge.x, edge.y - 1), EdgePieceView.ARM_PLUS_Y], [Vector2i(edge.x, edge.y), EdgePieceView.ARM_MINUS_Y]]
	return [[Vector2i(edge.x - 1, edge.y), EdgePieceView.ARM_PLUS_X], [Vector2i(edge.x, edge.y), EdgePieceView.ARM_MINUS_X]]


## Indica si la pieza de un borde va a su alto: todas con walls_up; si no, solo las de atrás.
func is_tall_edge(edge: Vector3i) -> bool:
	return walls_up or is_back_edge(edge)


## Indica si un borde es del contorno de atrás (la casilla de fuera queda más arriba en pantalla).
func is_back_edge(edge: Vector3i) -> bool:
	var cells: Array[Vector2i] = GridEdge.get_cells(edge)
	# La segunda casilla de un borde siempre queda más abajo en pantalla que la primera.
	if _lot.has_point(cells[0]) or not _lot.has_point(cells[1]):
		return false
	# Con el local en L un tramo así puede tener local detrás: alto lo taparía, así que va bajo.
	for back_x: int in range(BEHIND_WALL_REACH + 1):
		for back_y: int in range(BEHIND_WALL_REACH + 1):
			if _lot.has_point(cells[0] - Vector2i(back_x, back_y)):
				return false
	return true


## Añade un objeto (p. ej. un personaje) a la capa ordenada por Y.
func add_object(node: Node2D) -> void:
	_objects.add_child(node)


## Posición de cuadrícula con decimales a píxeles del mundo (las casillas enteras caen en su centro).
func grid_to_world(grid_position: Vector2) -> Vector2:
	var origin: Vector2 = cell_to_world(Vector2i.ZERO)
	var axis_x: Vector2 = cell_to_world(Vector2i(1, 0)) - origin
	var axis_y: Vector2 = cell_to_world(Vector2i(0, 1)) - origin
	return origin + axis_x * grid_position.x + axis_y * grid_position.y


func _place_furniture(furniture: Array[Dictionary]) -> void:
	for child: Node in _objects.get_children():
		if child is FurnitureView:
			_objects.remove_child(child)
			child.queue_free()
	for item: Dictionary in furniture:
		var view := FurnitureView.new()
		view.name = "%s_%d_%d" % [item["id"], item["cell"].x, item["cell"].y]
		_objects.add_child(view)
		view.setup(self, item)
		for slice: int in range(1, FurnitureView.get_slice_count(item)):
			var strip := FurnitureView.new()
			strip.name = "%s_tira_%d" % [view.name, slice]
			_objects.add_child(strip)
			strip.setup(self, item, FurnitureView.PART_SLICE, slice)
		if FurnitureView.has_backrest(item["id"]):
			var backrest := FurnitureView.new()
			backrest.name = view.name + "_respaldo"
			_objects.add_child(backrest)
			backrest.setup(self, item, FurnitureView.PART_BACKREST)


## Fija el solar y la casilla de fuera de la entrada. Se dibuja en build().
func set_site(site_rect: Rect2i, entrance_outside: Vector2i = Vector2i(-1, -1)) -> void:
	_site_rect = site_rect
	_entrance_outside = entrance_outside


## Plano del mapa dibujado (para pruebas).
func get_map_plan() -> Dictionary:
	return _map_plan


## Árboles de adorno dibujados.
func get_trees() -> Array[TreeView]:
	var trees: Array[TreeView] = []
	for child: Node in _objects.get_children():
		if child is TreeView and not child.is_queued_for_deletion():
			trees.append(child)
	return trees


## Línea del límite del solar.
func get_site_border() -> SiteBorder:
	return _site_border


# Rehace mapa, lo de fuera, árboles y borde si cambió el local, el solar o la entrada.
func _update_map(edges: Dictionary[Vector3i, String]) -> void:
	var starts: Array[Vector2i] = MapDecor.get_path_starts(_lot, _entrance_outside, edges)
	var signature: String = "%s|%s|%d|%s" % [_site_rect, starts, _lot.get_cells().size(), _lot.get_bounds()]
	if signature == _map_signature:
		return
	_map_signature = signature
	_map_plan = MapDecor.plan(_site_rect, _lot, _entrance_outside, edges)
	_surroundings.clear()
	var tiles: Dictionary = _map_plan["tiles"]
	for cell: Vector2i in tiles:
		if not _site_rect.has_point(cell):
			_surroundings.set_cell(cell, _floor_source_id, _map_tile(cell, tiles[cell]))
	for child: Node in _objects.get_children():
		if child is TreeView:
			_objects.remove_child(child)
			child.queue_free()
	for cell: Vector2i in _map_plan["trees"]:
		var tree := TreeView.new()
		tree.name = "Tree_%d_%d" % [cell.x, cell.y]
		_objects.add_child(tree)
		tree.setup(self, cell)
	_site_border.setup(self, _site_rect)


# Variante del piso de una casilla: con sprites al azar fijo; con arte pintado, en tablero.
func _floor_variant(cell: Vector2i, floor_type: String) -> int:
	if not _shared_from_sprites:
		return posmod(cell.x + cell.y, 2)
	var count: int = _atlas_columns.get(floor_type, 1)
	return mini(floori(MapDecor.noise(cell, MapDecor.SALT_STYLE) * count), count - 1)


# Casilla del atlas de un estilo del mapa: variante al azar fijo; la calle en la columna de su
# dirección. Con sprites el pasto elige familia por zonas y la línea tiene una fila por eje.
func _map_tile(cell: Vector2i, style: String) -> Vector2i:
	if _shared_from_sprites:
		var axis: int = int(_map_plan.get("road_axis", GridEdge.AXIS_X))
		if style == MapDecor.ROAD_LINE:
			style = "road_line_x" if axis == GridEdge.AXIS_X else "road_line_y"
		elif style == MapDecor.GRASS or style == MapDecor.OUTSIDE:
			style = "%s_%s" % [style, MapDecor.get_grass_family(cell)]
	var row: int = _atlas_rows.get(style, _atlas_rows[MapDecor.GRASS])
	if style == MapDecor.ROAD_LINE:
		var axis: int = int(_map_plan.get("road_axis", GridEdge.AXIS_X))
		return Vector2i(axis, row)
	var count: int = _atlas_columns.get(style, 1)
	return Vector2i(mini(floori(MapDecor.noise(cell, MapDecor.SALT_STYLE) * count), count - 1), row)


## Indica si una fila del atlas dibuja un estilo (la suya o, con sprites, una de sus familias).
func is_style_row(row: int, style: String) -> bool:
	for name: String in _atlas_rows:
		if _atlas_rows[name] == row and (name == style or name.begins_with(style + "_")):
			return true
	return false


## Rombo del solar en px del mundo como Transform2D (origin arriba, x e y a lo largo de los ejes).
## Un punto está dentro si affine_inverse() * punto queda entre 0 y 1.
func get_site_world_area() -> Transform2D:
	var origin: Vector2 = grid_to_world(Vector2(_site_rect.position) - Vector2(0.5, 0.5))
	var side_x: Vector2 = grid_to_world(Vector2(_site_rect.end.x, _site_rect.position.y) - Vector2(0.5, 0.5)) - origin
	var side_y: Vector2 = grid_to_world(Vector2(_site_rect.position.x, _site_rect.end.y) - Vector2(0.5, 0.5)) - origin
	return Transform2D(side_x, side_y, origin)


## Rectángulo que encierra el local actual.
func get_lot_rect() -> Rect2i:
	return _lot.get_bounds()


## Indica si una casilla pertenece al local.
func is_in_lot(cell: Vector2i) -> bool:
	return _lot.has_point(cell)


## Casilla que contiene un punto del mundo (en píxeles).
func world_to_cell(world_position: Vector2) -> Vector2i:
	return _floor.local_to_map(_floor.to_local(world_position))


## Centro de una casilla en píxeles del mundo.
func cell_to_world(cell: Vector2i) -> Vector2:
	return _floor.to_global(_floor.map_to_local(cell))


## Punto de la pantalla a píxeles del mundo, con la posición y zoom de la cámara.
func screen_to_world(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position


## Casilla bajo un punto de la pantalla.
func screen_to_cell(screen_position: Vector2) -> Vector2i:
	return world_to_cell(screen_to_world(screen_position))


## Rectángulo en px del mundo que cubre todo el local (para la cámara).
func get_lot_world_rect() -> Rect2:
	var half_tile: Vector2 = Vector2(GameConstants.TILE_SIZE) / 2.0
	var lot: Rect2i = get_lot_rect()
	var bounds := Rect2(cell_to_world(lot.position) - half_tile, Vector2(GameConstants.TILE_SIZE))
	for x: int in range(lot.position.x, lot.end.x):
		for y: int in range(lot.position.y, lot.end.y):
			var center: Vector2 = cell_to_world(Vector2i(x, y))
			bounds = bounds.merge(Rect2(center - half_tile, Vector2(GameConstants.TILE_SIZE)))
	return bounds


## Actualiza el resaltado según un punto del mundo (el ratón).
func update_hover(world_position: Vector2) -> void:
	var cell: Vector2i = world_to_cell(world_position)
	if not is_in_lot(cell):
		cell = NO_CELL
	if cell == hovered_cell:
		return
	hovered_cell = cell
	_highlight.visible = cell != NO_CELL
	if _highlight.visible:
		_highlight.position = to_local(cell_to_world(cell))


## Pinta el TileSet del suelo si falta (~1 s); el menú y las pruebas lo llaman antes para no trabar la partida.
static func prepare_tile_set() -> void:
	if _shared_tile_set == null:
		_shared_tile_set = _build_sprite_tile_set()
		_shared_from_sprites = _shared_tile_set != null
	if _shared_tile_set == null:
		_shared_tile_set = _build_tile_set()


# TileSet desde el atlas de sprites; null si no hay. Terreno sin comprar y pasto sin familia usan el liso.
static func _build_sprite_tile_set() -> TileSet:
	var ground: Dictionary = SpriteLibrary.get_ground()
	var path: String = String(ground.get("file", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		return null
	var tile_size := Vector2i(int(ground["tile"][0]), int(ground["tile"][1]))
	if tile_size != GameConstants.TILE_SIZE * GroundPainter.DETAIL:
		return null
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = tile_size
	_shared_rows = {}
	_shared_columns = {}
	var styles: Dictionary = ground.get("styles", {})
	for style: String in styles:
		var row: int = int(styles[style]["row"])
		var count: int = int(styles[style]["count"])
		_shared_rows[style] = row
		_shared_columns[style] = count
		for column: int in range(count):
			source.create_tile(Vector2i(column, row))
	var aliases: Dictionary[String, String] = {
		ConstructionCatalog.TERRAIN: "grass_plain", MapDecor.GRASS: "grass_plain", MapDecor.OUTSIDE: "outside_plain",
	}
	for alias: String in aliases:
		if not _shared_rows.has(alias) and _shared_rows.has(aliases[alias]):
			_shared_rows[alias] = _shared_rows[aliases[alias]]
			_shared_columns[alias] = _shared_columns[aliases[alias]]
	for needed: String in [ConstructionCatalog.BARE_FLOOR, MapDecor.GRASS]:
		if not _shared_rows.has(needed):
			return null
	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = tile_size
	_shared_source_id = tile_set.add_source(source)
	return tile_set


# TileSet del suelo, pintado la primera vez y compartido.
func _get_tile_set() -> TileSet:
	prepare_tile_set()
	_atlas_rows = _shared_rows
	_atlas_columns = _shared_columns
	_floor_source_id = _shared_source_id
	return _shared_tile_set


# TileSet provisional con GroundPainter: fila = estilo, columna = variante (pisos en tablero, la
# calle una por dirección).
static func _build_tile_set() -> TileSet:
	var floor_types: Array[String] = [ConstructionCatalog.BARE_FLOOR, ConstructionCatalog.TERRAIN]
	floor_types.append_array(ConstructionCatalog.get_floor_types())
	var styles: Array[Array] = []
	_shared_rows = {}
	_shared_columns = {}
	for floor_type: String in floor_types:
		_shared_rows[floor_type] = styles.size()
		styles.append(ConstructionCatalog.get_floor_colors(floor_type))
	var map_styles: Dictionary[String, Array] = MapDecor.get_styles()
	for style: String in map_styles:
		_shared_rows[style] = styles.size()
		styles.append(map_styles[style])
	var road: Array = map_styles.get(MapDecor.ROAD, [Color.DIM_GRAY])
	_shared_rows[MapDecor.ROAD_LINE] = styles.size()
	styles.append([road[0], road[0]])
	var columns: int = 2
	for row_colors: Array in styles:
		columns = maxi(columns, row_colors.size())
	for style: String in _shared_rows:
		_shared_columns[style] = styles[_shared_rows[style]].size()

	var tile_size: Vector2i = GameConstants.TILE_SIZE * GroundPainter.DETAIL
	var overlap: float = TILE_OVERLAP_PX * GroundPainter.DETAIL
	var image := Image.create_empty(tile_size.x * columns, tile_size.y * styles.size(), false, Image.FORMAT_RGBA8)
	var row_styles: Dictionary[int, String] = {}
	for style: String in _shared_rows:
		row_styles[_shared_rows[style]] = style
	var line_color := Color(String(MapDecor.get_data().get("road_line_color", "e0cf78")))
	for row: int in range(styles.size()):
		var style: String = row_styles[row]
		for column: int in range(styles[row].size()):
			var offset: Vector2i = Vector2i(column, row) * tile_size
			if style == MapDecor.ROAD_LINE:
				# Una columna por dirección de la calle: (2, 1) eje x de la pantalla, (-2, 1) eje y.
				GroundPainter.paint(image, offset, tile_size, style, road, 0, overlap, line_color,
					Vector2(2.0, 1.0) if column == 0 else Vector2(-2.0, 1.0))
			else:
				GroundPainter.paint(image, offset, tile_size, style, styles[row], column, overlap)
	image.generate_mipmaps()

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = tile_size
	for row: int in range(styles.size()):
		for column: int in range(styles[row].size()):
			source.create_tile(Vector2i(column, row))

	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = tile_size
	_shared_source_id = tile_set.add_source(source)
	return tile_set
