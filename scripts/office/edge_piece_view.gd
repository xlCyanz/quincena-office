# Pared, puerta o ventana sobre su borde. Se dibuja con su sprite (SpriteLibrary:
# <pieza>_<tall|low>_<x|y>) y, si no lo hay, con el arte provisional: una caja delgada. Las de atrás
# (contorno con el exterior detrás) van a su alto; las demás, bajas, para ver adentro.
# Va dentro de la capa ordenada por Y; su punto de orden es el centro del borde, así que
# un personaje queda detrás si está en la casilla de atrás y delante si está en la de
# adelante.
class_name EdgePieceView
extends Node2D

## Grosor de la pared, en casillas.
const THICKNESS: float = 0.08
## La puerta se dibuja un poco más corta que el borde, para que se note el marco.
const DOOR_INSET: float = 0.15

## Brazos de un vértice: hacia dónde sale de él cada tramo (para elegir el poste de esquina).
const ARM_PLUS_X: int = 0
const ARM_PLUS_Y: int = 1
const ARM_MINUS_X: int = 2
const ARM_MINUS_Y: int = 3

var edge := Vector3i.ZERO
var kind: String = ""
## Alta (pared de atrás) o baja.
var tall: bool = true

var _base := PackedVector2Array()
var _height: float = 0.0
var _color := Color.WHITE
# Puerta de vidrio (hito 69): bases del marco (dos postes) y de las dos hojas.
var _frame_bases: Array[PackedVector2Array] = []
var _leaf_bases: Array[PackedVector2Array] = []
var _frame_color := Color.DIM_GRAY
var _along := Vector2.RIGHT  # dirección del borde en pantalla
# Sprite del tramo ("" = arte provisional) y postes de esquina que dibuja encima: [sprite, posición].
var _sprite: String = ""
var _posts: Array[Array] = []


func setup(grid: OfficeGrid, piece_edge: Vector3i, piece_kind: String, is_tall: bool = true) -> void:
	edge = piece_edge
	kind = piece_kind
	tall = is_tall
	var piece: Dictionary = ConstructionCatalog.get_edge_piece(kind)
	_height = float(piece.get("height", 20.0)) if tall else ConstructionCatalog.get_low_wall_height()
	_color = Color(String(piece.get("color", "cccccc")))
	var ends: Array[Vector2] = GridEdge.get_endpoints(edge)
	var inset: float = DOOR_INSET if kind == ConstructionCatalog.DOOR else 0.0
	var half := THICKNESS / 2.0
	var low: Vector2
	var high: Vector2
	if edge.z == GridEdge.AXIS_X:
		low = Vector2(ends[0].x - half, ends[0].y + inset)
		high = Vector2(ends[1].x + half, ends[1].y - inset)
	else:
		low = Vector2(ends[0].x + inset, ends[0].y - half)
		high = Vector2(ends[1].x - inset, ends[1].y + half)
	position = grid.grid_to_world((ends[0] + ends[1]) / 2.0)
	_base = PackedVector2Array()
	for corner: Vector2 in IsoBox.grid_rect_corners(grid, low, high):
		_base.append(corner - position)
	_sprite = get_sprite_name(kind, tall, edge.z)
	if not SpriteLibrary.has_sprite(_sprite):
		_sprite = ""
	_posts.clear()
	_frame_bases.clear()
	_leaf_bases.clear()
	if kind == ConstructionCatalog.GLASS_DOOR:
		_frame_color = Color(String(piece.get("frame_color", "4f5862")))
		_along = (grid.grid_to_world(ends[1]) - grid.grid_to_world(ends[0])).normalized()
		# Postes en las puntas y dos hojas con una rendija en el medio.
		for span: Vector2 in [Vector2(0.0, 0.08), Vector2(0.92, 1.0)]:
			_frame_bases.append(_segment(grid, ends, span, THICKNESS * 1.4))
		for span: Vector2 in [Vector2(0.09, 0.485), Vector2(0.515, 0.91)]:
			_leaf_bases.append(_segment(grid, ends, span, THICKNESS * 0.6))
	queue_redraw()


# Base de un tramo del borde, de span.x a span.y (0 a 1 a lo largo), con depth de grosor.
func _segment(grid: OfficeGrid, ends: Array[Vector2], span: Vector2, depth: float) -> PackedVector2Array:
	var a: Vector2 = ends[0].lerp(ends[1], span.x)
	var b: Vector2 = ends[0].lerp(ends[1], span.y)
	var across: Vector2 = Vector2(depth / 2.0, 0.0) if edge.z == GridEdge.AXIS_X else Vector2(0.0, depth / 2.0)
	var low: Vector2 = a.min(b) - across
	var high: Vector2 = a.max(b) + across
	var base := PackedVector2Array()
	for corner: Vector2 in IsoBox.grid_rect_corners(grid, low, high):
		base.append(corner - position)
	return base


## Nombre del sprite de una pieza: <pieza>_<tall|low>_<x|y>.
static func get_sprite_name(piece_kind: String, is_tall: bool, axis: int) -> String:
	return "%s_%s_%s" % [piece_kind, "tall" if is_tall else "low", "x" if axis == GridEdge.AXIS_X else "y"]


## Sprite del poste de un vértice según sus brazos (brazo → si ese tramo es alto), o "" si no
## lleva: solo las esquinas en L (dos tramos perpendiculares).
static func get_corner_sprite(arms: Dictionary) -> String:
	if arms.size() != 2:
		return ""
	var tall: bool = false
	for arm: int in arms:
		tall = tall or bool(arms[arm])
	var suffix: String = ""
	if arms.has(ARM_PLUS_X) and arms.has(ARM_PLUS_Y):
		suffix = "" if tall else "_back"
	elif arms.has(ARM_MINUS_Y) and arms.has(ARM_PLUS_X):
		suffix = "_left"
	elif arms.has(ARM_MINUS_X) and arms.has(ARM_PLUS_Y):
		suffix = "_right"
	elif arms.has(ARM_MINUS_X) and arms.has(ARM_MINUS_Y):
		suffix = "_front" if tall else ""
	else:
		return ""
	var sprite: String = "wall_%s_corner%s" % ["tall" if tall else "low", suffix]
	return sprite if SpriteLibrary.has_sprite(sprite) else ""


## Agrega un poste de esquina en un punto del mundo; se dibuja encima del tramo.
func add_post(sprite: String, world_position: Vector2) -> void:
	_posts.append([sprite, world_position - position])
	queue_redraw()


## Sprite con que se dibuja el tramo ("" = arte provisional) y cuántos postes lleva.
func get_sprite() -> String:
	return _sprite


func get_post_count() -> int:
	return _posts.size()


func _draw() -> void:
	if not _sprite.is_empty():
		SpriteLibrary.draw(self, _sprite)
		for post: Array in _posts:
			SpriteLibrary.draw(self, post[0], post[1])
		return
	if kind == ConstructionCatalog.GLASS_DOOR:
		_draw_glass_door()
		return
	if kind != ConstructionCatalog.WINDOW:
		IsoBox.draw(self, _base, _height, _color)
		return
	# Ventana: pared hasta un tercio, vidrio en el medio y un dintel arriba.
	var wall := Color(String(ConstructionCatalog.get_edge_piece(ConstructionCatalog.WALL).get("color", "d8d0c4")))
	IsoBox.draw(self, _base, _height * 0.35, wall)
	var glass := PackedVector2Array()
	for corner: Vector2 in _base:
		glass.append(corner + Vector2(0, -_height * 0.35))
	IsoBox.draw(self, glass, _height * 0.5, _color)
	var top := PackedVector2Array()
	for corner: Vector2 in _base:
		top.append(corner + Vector2(0, -_height * 0.85))
	IsoBox.draw(self, top, _height * 0.15, wall)


# Puerta doble de vidrio: dos hojas celestes semitransparentes entre dos postes oscuros, con
# un dintel arriba y una manija en cada hoja junto a la rendija.
func _draw_glass_door() -> void:
	var glass := Color(_color, 0.55)
	for leaf: PackedVector2Array in _leaf_bases:
		IsoBox.draw(self, leaf, _height * 0.88, glass)
	for post: PackedVector2Array in _frame_bases:
		IsoBox.draw(self, post, _height, _frame_color)
	var lintel := PackedVector2Array()
	for corner: Vector2 in _base:
		lintel.append(corner + Vector2(0, -_height * 0.88))
	IsoBox.draw(self, lintel, _height * 0.12, _frame_color)
	var middle := Vector2.ZERO
	for corner: Vector2 in _base:
		middle += corner / 4.0
	for side: float in [-1.0, 1.0]:
		draw_line(middle + _along * 3.0 * side + Vector2(0, -_height * 0.55),
			middle + _along * 3.0 * side + Vector2(0, -_height * 0.35), _frame_color, 1.5)
