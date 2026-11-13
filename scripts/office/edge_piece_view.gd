# Dibujo provisional de una pared o una puerta: una caja baja y delgada sobre su borde.
# Va dentro de la capa ordenada por Y; su punto de orden es el centro del borde, así que
# un personaje queda detrás si está en la casilla de atrás y delante si está en la de
# adelante.
class_name EdgePieceView
extends Node2D

## Grosor de la pared, en casillas.
const THICKNESS: float = 0.08
## La puerta se dibuja un poco más corta que el borde, para que se note el marco.
const DOOR_INSET: float = 0.15

var edge := Vector3i.ZERO
var kind: String = ""

var _base := PackedVector2Array()
var _height: float = 0.0
var _color := Color.WHITE


func setup(grid: OfficeGrid, piece_edge: Vector3i, piece_kind: String) -> void:
	edge = piece_edge
	kind = piece_kind
	var piece: Dictionary = ConstructionCatalog.get_edge_piece(kind)
	_height = float(piece.get("height", 20.0))
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
	queue_redraw()


func _draw() -> void:
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
