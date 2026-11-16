# Rombo semitransparente sobre la casilla bajo el cursor (lo coloca OfficeGrid).
class_name CellHighlight
extends Node2D

const FILL_COLOR := Color(1.0, 1.0, 1.0, 0.25)
const OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 0.9)


func _draw() -> void:
	var half: Vector2 = Vector2(GameConstants.TILE_SIZE) / 2.0
	var points := PackedVector2Array([
		Vector2(0.0, -half.y),
		Vector2(half.x, 0.0),
		Vector2(0.0, half.y),
		Vector2(-half.x, 0.0),
	])
	draw_colored_polygon(points, FILL_COLOR)
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, OUTLINE_COLOR, 1.0)
