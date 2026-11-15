# Dibuja cajas isométricas del arte provisional (muebles, paredes, puertas).
# Se usa por su nombre de clase desde el _draw() de un nodo.
class_name IsoBox
extends RefCounted

## Oscurecimiento de las caras laterales respecto a la tapa, para dar volumen.
const LEFT_FACE_DARKEN: float = 0.25
const RIGHT_FACE_DARKEN: float = 0.4


## base son las cuatro esquinas de la base, en orden alrededor del rectángulo, en las
## coordenadas locales del nodo; height, la altura en píxeles. La esquina de arriba se
## busca (no hace falta que sea la primera).
static func draw(canvas: CanvasItem, base: PackedVector2Array, height: float, color: Color) -> void:
	if base.size() != 4:
		return
	var lift := Vector2(0.0, -height)
	var top_index: int = 0
	for i: int in range(1, 4):
		if base[i].y < base[top_index].y or (base[i].y == base[top_index].y and base[i].x < base[top_index].x):
			top_index = i
	var top_corner: Vector2 = base[top_index]
	var bottom: Vector2 = base[(top_index + 2) % 4]
	var right: Vector2 = base[(top_index + 1) % 4]
	var left: Vector2 = base[(top_index + 3) % 4]
	if right.x < left.x:
		var swap: Vector2 = right
		right = left
		left = swap
	canvas.draw_colored_polygon(PackedVector2Array([left, bottom, bottom + lift, left + lift]),
		color.darkened(LEFT_FACE_DARKEN))
	canvas.draw_colored_polygon(PackedVector2Array([bottom, right, right + lift, bottom + lift]),
		color.darkened(RIGHT_FACE_DARKEN))
	canvas.draw_colored_polygon(PackedVector2Array([top_corner + lift, right + lift, bottom + lift, left + lift]), color)


## Las cuatro esquinas (arriba, derecha, abajo, izquierda) de un rectángulo de la
## cuadrícula con decimales, de low a high, convertidas con grid_to_world.
static func grid_rect_corners(grid: OfficeGrid, low: Vector2, high: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		grid.grid_to_world(Vector2(low.x, low.y)),
		grid.grid_to_world(Vector2(high.x, low.y)),
		grid.grid_to_world(Vector2(high.x, high.y)),
		grid.grid_to_world(Vector2(low.x, high.y)),
	])
