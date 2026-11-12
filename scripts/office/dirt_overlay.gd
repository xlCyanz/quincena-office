# Manchas de suciedad en el piso de cada habitación (hito 37): más manchas cuanto más
# sucia está. Va entre el piso y los objetos y se ve siempre. Arte provisional.
class_name DirtOverlay
extends Node2D

const STAIN_COLOR := Color(0.35, 0.25, 0.12, 0.45)
const DIRTY_COLOR := Color(0.3, 0.2, 0.08, 0.6)
## Manchas por casilla con la suciedad al máximo.
const MAX_STAINS_PER_CELL: int = 3

var _grid: OfficeGrid
var _rooms: Array[Dictionary] = []


func setup(grid: OfficeGrid) -> void:
	_grid = grid


## Habitaciones con su suciedad, tal como las guarda OfficeState.
func set_rooms(rooms: Array[Dictionary]) -> void:
	_rooms = rooms.duplicate(true)
	queue_redraw()


## Cuántas manchas se dibujan en una habitación (para las pruebas).
func get_stain_count(room: Dictionary) -> int:
	var cells: Array = room["cells"]
	var ratio: float = OfficeState.get_room_dirt(room) / float(StaffCatalog.get_cleaning("max_dirt"))
	return roundi(ratio * cells.size() * MAX_STAINS_PER_CELL)


func _draw() -> void:
	if _grid == null:
		return
	for room: Dictionary in _rooms:
		var stains: int = get_stain_count(room)
		if stains <= 0:
			continue
		var color: Color = DIRTY_COLOR if OfficeState.is_room_dirty(room) else STAIN_COLOR
		var cells: Array = room["cells"]
		# Posiciones fijas por casilla (mismo dibujo en cada redibujado).
		for index: int in range(stains):
			var cell: Vector2i = cells[index % cells.size()]
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector3i(cell.x, cell.y, index))
			var point := Vector2(cell) + Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
			var center: Vector2 = _grid.grid_to_world(point)
			draw_set_transform(center, 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, rng.randf_range(4.0, 8.0), color)
	draw_set_transform(Vector2.ZERO)
