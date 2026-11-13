# Cuadrícula isométrica de la oficina: dibuja el piso del local, el mapa de alrededor
# (MapDecor) y resalta la casilla que está bajo el cursor. Es el único lugar que convierte
# entre píxeles y casillas; el resto del juego trabaja siempre con casillas (Vector2i).
#
# La vista se puede girar de a un cuarto de vuelta (view_rotation): las casillas de la
# lógica no cambian, solo dónde se dibujan. Todo lo que pasa por cell_to_world,
# grid_to_world y world_to_cell gira solo.
class_name OfficeGrid
extends Node2D

## Casilla bajo el cursor, o NO_CELL si el cursor está fuera del local.
const NO_CELL := Vector2i(-1, -1)

## Píxeles que cada rombo del piso se pasa de su borde para no dejar huecos con zoom.
const TILE_OVERLAP_PX: float = 1.0

var hovered_cell: Vector2i = NO_CELL

## Cuartos de vuelta de la vista, de 0 a 3, en el sentido de las agujas del reloj.
var view_rotation: int = 0

var _floor_source_id: int = -1
var _lot := Lot.new()
var _site_rect := Rect2i()
# Casilla de fuera del local junto a la entrada (de ahí sale el camino a la calle).
var _entrance_outside := Vector2i(-1, -1)
# Fila del atlas de cada tipo de piso o estilo del mapa, y cuántas variantes tiene.
var _atlas_rows: Dictionary[String, int] = {}
var _atlas_columns: Dictionary[String, int] = {}
# Plano del mapa (MapDecor.plan) y con qué datos se hizo, para no rehacerlo si no cambió.
var _map_plan: Dictionary = {}
var _map_signature: String = ""
# Lo que se dibuja fuera del solar, debajo del piso, y la línea del límite del solar.
var _surroundings := TileMapLayer.new()
var _site_border := SiteBorder.new()

@onready var _floor: TileMapLayer = $Floor
@onready var _highlight: CellHighlight = $CellHighlight
@onready var _room_overlay: RoomOverlay = $RoomOverlay
# Capa ordenada por Y: muebles y personajes. Lo que está más abajo en pantalla
# (más cerca de quien mira) se dibuja encima.
@onready var _objects: Node2D = $Objects
# Manchas de suciedad (hito 37); se crea en _ready, justo encima del tinte de habitaciones.
var _dirt_overlay := DirtOverlay.new()


func _ready() -> void:
	_floor.tile_set = _build_tile_set()
	_surroundings.name = "Surroundings"
	_surroundings.tile_set = _floor.tile_set
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


## Dibuja la oficina: el piso de cada casilla, las paredes y puertas de los bordes,
## los muebles y el tinte de las habitaciones. Recibe los datos tal como los guarda
## OfficeState. Alrededor del local dibuja el terreno del solar (ver set_site).
func build(lot: Lot, floors: Dictionary[Vector2i, String], edges: Dictionary[Vector3i, String],
		furniture: Array[Dictionary], rooms: Array[Dictionary] = []) -> void:
	_lot = lot
	_update_map()
	_floor.clear()
	var tiles: Dictionary = _map_plan.get("tiles", {})
	for x: int in range(_site_rect.position.x, _site_rect.end.x):
		for y: int in range(_site_rect.position.y, _site_rect.end.y):
			var cell := Vector2i(x, y)
			if not lot.has_point(cell):
				_floor.set_cell(_to_view(cell), _floor_source_id, _map_tile(cell, tiles.get(cell, MapDecor.GRASS)))
	for cell: Vector2i in lot.get_cells():
		var floor_type: String = floors.get(cell, ConstructionCatalog.BARE_FLOOR)
		var row: int = _atlas_rows.get(floor_type, _atlas_rows[ConstructionCatalog.BARE_FLOOR])
		_floor.set_cell(_to_view(cell), _floor_source_id, Vector2i(posmod(cell.x + cell.y, 2), row))
	hovered_cell = NO_CELL
	_highlight.visible = false
	_place_edge_pieces(edges)
	_place_furniture(furniture)
	_room_overlay.set_rooms(rooms)
	_dirt_overlay.set_rooms(rooms)


## Vuelve a dibujar la suciedad de las habitaciones (hito 37).
func set_dirt(rooms: Array[Dictionary]) -> void:
	_dirt_overlay.set_rooms(rooms)


## Capa de suciedad (para las pruebas).
func get_dirt_overlay() -> DirtOverlay:
	return _dirt_overlay


## Muestra u oculta el tinte de las habitaciones (se ve en modo construcción).
func set_rooms_visible(rooms_visible: bool) -> void:
	_room_overlay.visible = rooms_visible


## Convierte píxeles del mundo a una posición de cuadrícula con decimales (la inversa
## de grid_to_world). Sirve para saber qué borde está más cerca del ratón.
func world_to_grid(world_position: Vector2) -> Vector2:
	var origin: Vector2 = cell_to_world(Vector2i.ZERO)
	var basis := Transform2D(cell_to_world(Vector2i(1, 0)) - origin, cell_to_world(Vector2i(0, 1)) - origin, origin)
	return basis.affine_inverse() * world_position


func _place_edge_pieces(edges: Dictionary[Vector3i, String]) -> void:
	for child: Node in _objects.get_children():
		if child is EdgePieceView:
			_objects.remove_child(child)
			child.queue_free()
	for edge: Vector3i in edges:
		var view := EdgePieceView.new()
		view.name = "%s_%d_%d_%d" % [edges[edge], edge.x, edge.y, edge.z]
		_objects.add_child(view)
		view.setup(self, edge, edges[edge])


## Añade un objeto (por ejemplo, un personaje) a la capa ordenada por Y.
func add_object(node: Node2D) -> void:
	_objects.add_child(node)


## Convierte una posición de cuadrícula con decimales (por ejemplo, un personaje a
## medio camino entre dos casillas) a píxeles del mundo. Las casillas enteras caen
## en su centro, igual que cell_to_world.
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
		if FurnitureView.has_backrest(item["id"]):
			var backrest := FurnitureView.new()
			backrest.name = view.name + "_respaldo"
			_objects.add_child(backrest)
			backrest.setup(self, item, FurnitureView.PART_BACKREST)


## Fija el solar: el mapa fijo de terreno que rodea al local, y la casilla de fuera de la
## entrada (de ahí sale el camino a la calle). Se dibuja en build().
func set_site(site_rect: Rect2i, entrance_outside: Vector2i = Vector2i(-1, -1)) -> void:
	_site_rect = site_rect
	_entrance_outside = entrance_outside


## Gira la vista a quarter_turns cuartos de vuelta (se dibuja en el próximo build()).
func set_view_rotation(quarter_turns: int) -> void:
	view_rotation = posmod(quarter_turns, 4)


## Plano del mapa con que se dibujó (MapDecor.plan; para las pruebas).
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


## Casilla donde se dibuja una casilla de la lógica con la vista girada.
func _to_view(cell: Vector2i) -> Vector2i:
	if view_rotation == 0:
		return cell
	var origin: Vector2i = _site_rect.position
	var last: int = maxi(_site_rect.size.x, _site_rect.size.y) - 1
	var local: Vector2i = cell - origin
	match view_rotation:
		1:
			local = Vector2i(last - local.y, local.x)
		2:
			local = Vector2i(last - local.x, last - local.y)
		_:
			local = Vector2i(local.y, last - local.x)
	return origin + local


## La inversa de _to_view.
func _from_view(cell: Vector2i) -> Vector2i:
	if view_rotation == 0:
		return cell
	var origin: Vector2i = _site_rect.position
	var last: int = maxi(_site_rect.size.x, _site_rect.size.y) - 1
	var local: Vector2i = cell - origin
	match view_rotation:
		1:
			local = Vector2i(local.y, last - local.x)
		2:
			local = Vector2i(last - local.x, last - local.y)
		_:
			local = Vector2i(last - local.y, local.x)
	return origin + local


# Rehace el plano del mapa, lo de fuera del solar, los árboles y el borde si cambió el
# local, el solar, la entrada o la orientación (comprar terreno o girar la vista).
func _update_map() -> void:
	var signature: String = "%s|%s|%d|%s|%d" % [_site_rect, _entrance_outside, _lot.get_cells().size(),
		_lot.get_bounds(), view_rotation]
	if signature == _map_signature:
		return
	_map_signature = signature
	_map_plan = MapDecor.plan(_site_rect, _lot, _entrance_outside)
	_surroundings.clear()
	var tiles: Dictionary = _map_plan["tiles"]
	for cell: Vector2i in tiles:
		if not _site_rect.has_point(cell):
			_surroundings.set_cell(_to_view(cell), _floor_source_id, _map_tile(cell, tiles[cell]))
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


# Casilla del atlas de un estilo del mapa: una variante al azar fijo; la línea de la
# calle va en la columna de su dirección en pantalla.
func _map_tile(cell: Vector2i, style: String) -> Vector2i:
	var row: int = _atlas_rows.get(style, _atlas_rows[MapDecor.GRASS])
	if style == MapDecor.ROAD_LINE:
		var axis: int = int(_map_plan.get("road_axis", GridEdge.AXIS_X))
		return Vector2i(axis if view_rotation % 2 == 0 else 1 - axis, row)
	var count: int = _atlas_columns.get(style, 1)
	return Vector2i(mini(floori(MapDecor.noise(cell, MapDecor.SALT_STYLE) * count), count - 1), row)


## Rombo del solar en píxeles del mundo, como Transform2D: origin es la esquina de
## arriba, x recorre el lado a lo largo del eje x de la cuadrícula e y el del eje y.
## Un punto está dentro si affine_inverse() * punto queda entre 0 y 1 en ambos ejes.
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
	return _from_view(_floor.local_to_map(_floor.to_local(world_position)))


## Centro de una casilla en píxeles del mundo.
func cell_to_world(cell: Vector2i) -> Vector2:
	return _floor.to_global(_floor.map_to_local(_to_view(cell)))


## Convierte un punto de la pantalla (por ejemplo, el ratón) a píxeles del mundo,
## teniendo en cuenta la posición y el zoom de la cámara.
func screen_to_world(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position


## Casilla bajo un punto de la pantalla.
func screen_to_cell(screen_position: Vector2) -> Vector2i:
	return world_to_cell(screen_to_world(screen_position))


## Rectángulo en píxeles del mundo que cubre todo el local (lo usa la cámara).
func get_lot_world_rect() -> Rect2:
	var half_tile: Vector2 = Vector2(GameConstants.TILE_SIZE) / 2.0
	var lot: Rect2i = get_lot_rect()
	var bounds := Rect2(cell_to_world(lot.position) - half_tile, Vector2(GameConstants.TILE_SIZE))
	for x: int in range(lot.position.x, lot.end.x):
		for y: int in range(lot.position.y, lot.end.y):
			var center: Vector2 = cell_to_world(Vector2i(x, y))
			bounds = bounds.merge(Rect2(center - half_tile, Vector2(GameConstants.TILE_SIZE)))
	return bounds


## Actualiza el resaltado según un punto del mundo (normalmente, el ratón).
func update_hover(world_position: Vector2) -> void:
	var cell: Vector2i = world_to_cell(world_position)
	if not is_in_lot(cell):
		cell = NO_CELL
	if cell == hovered_cell:
		return
	hovered_cell = cell
	_highlight.visible = cell != NO_CELL
	if _highlight.visible:
		_highlight.position = _floor.position + _floor.map_to_local(_to_view(cell))


# Crea el TileSet en código con rombos de colores generados (arte provisional).
# Cada fila del atlas es un estilo de piso o del mapa; cada columna, una variante (los
# pisos usan dos, en tablero). La calle con línea tiene una columna por dirección.
func _build_tile_set() -> TileSet:
	var floor_types: Array[String] = [ConstructionCatalog.BARE_FLOOR, ConstructionCatalog.TERRAIN]
	floor_types.append_array(ConstructionCatalog.get_floor_types())
	var styles: Array[Array] = []
	_atlas_rows = {}
	_atlas_columns = {}
	for floor_type: String in floor_types:
		_atlas_rows[floor_type] = styles.size()
		styles.append(ConstructionCatalog.get_floor_colors(floor_type))
	var map_styles: Dictionary[String, Array] = MapDecor.get_styles()
	for style: String in map_styles:
		_atlas_rows[style] = styles.size()
		styles.append(map_styles[style])
	var road: Array = map_styles.get(MapDecor.ROAD, [Color.DIM_GRAY])
	_atlas_rows[MapDecor.ROAD_LINE] = styles.size()
	styles.append([road[0], road[0]])
	var columns: int = 2
	for row_colors: Array in styles:
		columns = maxi(columns, row_colors.size())
	for style: String in _atlas_rows:
		_atlas_columns[style] = styles[_atlas_rows[style]].size()

	var tile_size: Vector2i = GameConstants.TILE_SIZE
	var image := Image.create_empty(tile_size.x * columns, tile_size.y * styles.size(), false, Image.FORMAT_RGBA8)
	for row: int in range(styles.size()):
		for column: int in range(styles[row].size()):
			_draw_diamond(image, Vector2i(column, row) * tile_size, styles[row][column])
	var line_color := Color(String(MapDecor.get_data().get("road_line_color", "e0cf78")))
	var line_row: int = _atlas_rows[MapDecor.ROAD_LINE]
	_draw_road_line(image, Vector2i(0, line_row) * tile_size, Vector2(2.0, 1.0), line_color)
	_draw_road_line(image, Vector2i(1, line_row) * tile_size, Vector2(-2.0, 1.0), line_color)

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
	_floor_source_id = tile_set.add_source(source)
	return tile_set


# Pinta la línea de la calle por el centro de una casilla, en la dirección direction
# (en píxeles: (2, 1) es el eje x de la pantalla isométrica, (-2, 1) el eje y).
func _draw_road_line(image: Image, offset: Vector2i, direction: Vector2, color: Color) -> void:
	var half: Vector2 = Vector2(GameConstants.TILE_SIZE) / 2.0
	var unit: Vector2 = direction.normalized()
	var normal := Vector2(-unit.y, unit.x)
	for y: int in range(GameConstants.TILE_SIZE.y):
		for x: int in range(GameConstants.TILE_SIZE.x):
			var point := Vector2(x + 0.5, y + 0.5) - half
			if absf(point.dot(normal)) <= 1.2 and absf(point.dot(unit)) <= half.x * 0.6:
				image.set_pixel(offset.x + x, offset.y + y, color)


# Pinta un rombo que llena una casilla. Usa el centro de cada píxel y se pasa
# TILE_OVERLAP_PX del borde: con zoom no entero (0.5 o 1.5) los rombos que encajan
# justo dejan rayas de huecos entre casillas; con el solape, el vecino las tapa.
func _draw_diamond(image: Image, offset: Vector2i, color: Color) -> void:
	var half: Vector2 = Vector2(GameConstants.TILE_SIZE) / 2.0
	var limit: float = 1.0 + TILE_OVERLAP_PX / half.y
	for y: int in range(GameConstants.TILE_SIZE.y):
		for x: int in range(GameConstants.TILE_SIZE.x):
			var dx: float = absf(x + 0.5 - half.x) / half.x
			var dy: float = absf(y + 0.5 - half.y) / half.y
			if dx + dy <= limit:
				image.set_pixel(offset.x + x, offset.y + y, color)
