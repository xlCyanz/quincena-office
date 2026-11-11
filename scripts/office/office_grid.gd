# Cuadrícula isométrica de la oficina: dibuja el piso del local y resalta la casilla
# que está bajo el cursor. Es el único lugar que convierte entre píxeles y casillas;
# el resto del juego trabaja siempre con casillas (Vector2i).
class_name OfficeGrid
extends Node2D

## Colores provisionales del piso (tablero de ajedrez para distinguir cada casilla).
const FLOOR_COLOR_LIGHT := Color("c9b48a")
const FLOOR_COLOR_DARK := Color("b39c72")

## Coordenadas en el atlas de cada variante de piso.
const ATLAS_LIGHT := Vector2i(0, 0)
const ATLAS_DARK := Vector2i(1, 0)

## Casilla bajo el cursor, o NO_CELL si el cursor está fuera del local.
const NO_CELL := Vector2i(-1, -1)

var hovered_cell: Vector2i = NO_CELL

var _floor_source_id: int = -1

@onready var _floor: TileMapLayer = $Floor
@onready var _highlight: CellHighlight = $CellHighlight


func _ready() -> void:
	_floor.tile_set = _build_tile_set()
	_paint_lot()
	_highlight.visible = false


func _process(_delta: float) -> void:
	update_hover(get_global_mouse_position())


## Rectángulo de casillas del local actual.
func get_lot_rect() -> Rect2i:
	return Rect2i(Vector2i.ZERO, GameConstants.STARTING_LOT_SIZE)


## Indica si una casilla pertenece al local.
func is_in_lot(cell: Vector2i) -> bool:
	return get_lot_rect().has_point(cell)


## Casilla que contiene un punto del mundo (en píxeles).
func world_to_cell(world_position: Vector2) -> Vector2i:
	return _floor.local_to_map(_floor.to_local(world_position))


## Centro de una casilla en píxeles del mundo.
func cell_to_world(cell: Vector2i) -> Vector2:
	return _floor.to_global(_floor.map_to_local(cell))


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
		_highlight.position = _floor.position + _floor.map_to_local(cell)


func _paint_lot() -> void:
	var lot: Rect2i = get_lot_rect()
	for x: int in range(lot.position.x, lot.end.x):
		for y: int in range(lot.position.y, lot.end.y):
			var atlas: Vector2i = ATLAS_LIGHT if (x + y) % 2 == 0 else ATLAS_DARK
			_floor.set_cell(Vector2i(x, y), _floor_source_id, atlas)


# Crea el TileSet en código con rombos de colores generados (arte provisional).
func _build_tile_set() -> TileSet:
	var tile_size: Vector2i = GameConstants.TILE_SIZE
	var image := Image.create_empty(tile_size.x * 2, tile_size.y, false, Image.FORMAT_RGBA8)
	_draw_diamond(image, Vector2i(0, 0), FLOOR_COLOR_LIGHT)
	_draw_diamond(image, Vector2i(tile_size.x, 0), FLOOR_COLOR_DARK)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = tile_size
	source.create_tile(ATLAS_LIGHT)
	source.create_tile(ATLAS_DARK)

	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = tile_size
	_floor_source_id = tile_set.add_source(source)
	return tile_set


# Pinta un rombo que llena exactamente una casilla. Usa el centro de cada píxel
# para que los rombos vecinos encajen sin huecos ni solapes.
func _draw_diamond(image: Image, offset: Vector2i, color: Color) -> void:
	var half: Vector2 = Vector2(GameConstants.TILE_SIZE) / 2.0
	for y: int in range(GameConstants.TILE_SIZE.y):
		for x: int in range(GameConstants.TILE_SIZE.x):
			var dx: float = absf(x + 0.5 - half.x) / half.x
			var dy: float = absf(y + 0.5 - half.y) / half.y
			if dx + dy <= 1.0:
				image.set_pixel(offset.x + x, offset.y + y, color)
