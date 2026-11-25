# Pared, puerta o ventana sobre su borde: sprite <pieza>_<tall|low>_<x|y> o caja provisional. La puerta de vidrio
# doble ocupa dos bordes: cada uno dibuja su mitad, <pieza>_<a|b>_<tall|low>_<x|y> (a = el de menor x o y).
# Las de atrás van altas; las demás bajas. Se ordena por el centro del borde.
class_name EdgePieceView
extends Node2D

## Grosor de la pared, en casillas.
const THICKNESS: float = 0.08
## La puerta es algo más corta que el borde, para que se note el marco.
const DOOR_INSET: float = 0.15

## Brazos de un vértice (para elegir el poste). Nombre: wall_post_<−x><−y><+x><+y>, cada uno
## n (nada), l (bajo), t (alto), d (puerta baja) o h (puerta alta); igual que tools/sprites/art/walls/posts/build.py (post_name).
const POST_ARM_ORDER: Array[int] = [2, 3, 0, 1]
const ARM_PLUS_X: int = 0
const ARM_PLUS_Y: int = 1
const ARM_MINUS_X: int = 2
const ARM_MINUS_Y: int = 3
const DOOR_CODES: Array[String] = ["d", "h"]

var edge := Vector3i.ZERO
var kind: String = ""
## Alta (pared de atrás) o baja.
var tall: bool = true

var _base := PackedVector2Array()
var _height: float = 0.0
var _color := Color.WHITE
# Puerta de vidrio: bases de los dos postes y de las dos hojas.
var _frame_bases: Array[PackedVector2Array] = []
var _leaf_bases: Array[PackedVector2Array] = []
var _frame_color := Color.DIM_GRAY
var _along := Vector2.RIGHT  # dirección del borde en pantalla
# Sprite del tramo ("" = provisional) y postes que dibuja encima: [sprite, posición].
var _sprite: String = ""
var _posts: Array[Array] = []


func setup(grid: OfficeGrid, piece_edge: Vector3i, piece_kind: String, is_tall: bool = true, double_half: String = "") -> void:
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
	_sprite = get_sprite_name(kind, tall, edge.z, double_half)
	if not SpriteLibrary.has_sprite(_sprite):
		_sprite = ""
	_posts.clear()
	_frame_bases.clear()
	_leaf_bases.clear()
	if ConstructionCatalog.is_glass_door(kind):
		_frame_color = Color(String(piece.get("frame_color", "4f5862")))
		_along = (grid.grid_to_world(ends[1]) - grid.grid_to_world(ends[0])).normalized()
		# Postes en las puntas y dos hojas con una rendija en el medio.
		for span: Vector2 in [Vector2(0.0, 0.08), Vector2(0.92, 1.0)]:
			_frame_bases.append(_segment(grid, ends, span, THICKNESS * 1.4))
		for span: Vector2 in [Vector2(0.09, 0.485), Vector2(0.515, 0.91)]:
			_leaf_bases.append(_segment(grid, ends, span, THICKNESS * 0.6))
	queue_redraw()


# Base de un tramo de span.x a span.y (0 a 1 a lo largo), con depth de grosor.
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


## Nombre del sprite de una pieza: <pieza>_<tall|low>_<x|y>, o <pieza>_<half>_… para una mitad.
static func get_sprite_name(piece_kind: String, is_tall: bool, axis: int, half: String = "") -> String:
	var piece: String = piece_kind if half.is_empty() else "%s_%s" % [piece_kind, half]
	return "%s_%s_%s" % [piece, "tall" if is_tall else "low", "x" if axis == GridEdge.AXIS_X else "y"]


## Mitad de la puerta de vidrio doble que va en un borde: "a" si su pareja está del lado de mayor x o y,
## "b" si está del otro; "" para las demás piezas.
static func get_double_half(edges: Dictionary, piece_edge: Vector3i) -> String:
	if String(edges.get(piece_edge, "")) != ConstructionCatalog.GLASS_DOOR_DOUBLE:
		return ""
	var sides: Array[Vector3i] = GridEdge.get_line_neighbors(piece_edge)
	return "b" if String(edges.get(sides[0], "")) == ConstructionCatalog.GLASS_DOOR_DOUBLE else "a"


## Código de un tramo para el poste: t pared alta, l baja, h puerta alta, d puerta baja.
## Ventana y puerta de vidrio cuentan como pared.
static func get_arm_code(piece_kind: String, is_tall: bool) -> String:
	if piece_kind == ConstructionCatalog.DOOR:
		return "h" if is_tall else "d"
	return "t" if is_tall else "l"


## Poste de un vértice según sus brazos, o "" si no lleva: toda unión de dos o más tramos salvo
## dos del mismo alto en línea (dos puertas así comparten jamba). Atrás (−x, −y) la puerta se nombra pared.
static func get_corner_sprite(arms: Dictionary) -> String:
	if arms.size() < 2:
		return ""
	var codes: Dictionary[int, String] = {}
	for arm: int in arms:
		var value: Variant = arms[arm]
		codes[arm] = value if value is String else ("t" if bool(value) else "l")
	var mullion: bool = false
	if arms.size() == 2:
		for pair: Array in [[ARM_MINUS_X, ARM_PLUS_X], [ARM_MINUS_Y, ARM_PLUS_Y]]:
			if not (codes.has(pair[0]) and codes.has(pair[1])):
				continue
			var a: String = codes[pair[0]]
			var b: String = codes[pair[1]]
			if a == b and a in DOOR_CODES:
				mullion = true
			elif _is_tall_code(a) == _is_tall_code(b):
				# Dos tramos del mismo alto en línea: la pared sigue de largo, sin poste.
				return ""
	var sprite: String = "wall_post_"
	for arm: int in POST_ARM_ORDER:
		var code: String = codes.get(arm, "n")
		if not mullion and (arm == ARM_MINUS_X or arm == ARM_MINUS_Y) and code in DOOR_CODES:
			code = "t" if _is_tall_code(code) else "l"
		sprite += code
	return sprite if SpriteLibrary.has_sprite(sprite) else ""


static func _is_tall_code(code: String) -> bool:
	return code == "t" or code == "h"


## Agrega un poste de esquina en un punto del mundo, encima del tramo.
func add_post(sprite: String, world_position: Vector2) -> void:
	_posts.append([sprite, world_position - position])
	queue_redraw()


## Sprite del tramo ("" = provisional) y cuántos postes lleva.
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
	if ConstructionCatalog.is_glass_door(kind):
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


# Puerta de vidrio: dos hojas celestes entre postes oscuros, dintel y una manija por hoja.
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
