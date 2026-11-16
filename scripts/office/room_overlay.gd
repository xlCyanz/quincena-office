# Tiñe el piso de cada habitación con el color de su tipo, bajo paredes y muebles. Solo en construcción.
class_name RoomOverlay
extends Node2D

const FILL_ALPHA: float = 0.45

var _grid: OfficeGrid
var _rooms: Array[Dictionary] = []


func setup(grid: OfficeGrid) -> void:
	_grid = grid


## Habitaciones a teñir (como en OfficeState).
func set_rooms(rooms: Array[Dictionary]) -> void:
	_rooms = rooms.duplicate()
	queue_redraw()


func _draw() -> void:
	if _grid == null:
		return
	for room: Dictionary in _rooms:
		var color: Color = RoomCatalog.get_color(room["type"])
		color.a = FILL_ALPHA
		for cell: Vector2i in room["cells"]:
			var center := Vector2(cell)
			draw_colored_polygon(IsoBox.grid_rect_corners(_grid, center - Vector2(0.5, 0.5),
				center + Vector2(0.5, 0.5)), color)
