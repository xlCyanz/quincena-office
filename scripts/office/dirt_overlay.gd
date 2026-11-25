# Manchas de suciedad en el piso de cada habitación: más casillas manchadas cuanto más sucia (sprites dirt_*).
class_name DirtOverlay
extends Node2D

## Opacidad de las manchas antes de que la habitación cuente como sucia (dirty_from); sucia, enteras.
const STAIN_ALPHA: float = 0.6
## Manchas por casilla con la suciedad al máximo.
const MAX_STAINS_PER_CELL: int = 1
const SALT_CELL: int = 7151
const SALT_KIND: int = 9283

var _grid: OfficeGrid
var _rooms: Array[Dictionary] = []


func setup(grid: OfficeGrid) -> void:
	_grid = grid


## Habitaciones con su suciedad (como en OfficeState).
func set_rooms(rooms: Array[Dictionary]) -> void:
	_rooms = rooms.duplicate(true)
	queue_redraw()


## Manchas dibujadas en una habitación (para pruebas).
func get_stain_count(room: Dictionary) -> int:
	var cells: Array = room["cells"]
	var ratio: float = OfficeState.get_room_dirt(room) / float(StaffCatalog.get_cleaning("max_dirt"))
	return mini(roundi(ratio * cells.size() * MAX_STAINS_PER_CELL), cells.size())


## Casillas manchadas de una habitación y la mancha de cada una: [[casilla, sprite], …]. Siempre las mismas
## casillas en el mismo orden, así al ensuciarse se suman manchas sin que se muevan las que ya estaban.
func get_stains(room: Dictionary) -> Array[Array]:
	var stains: Array[Array] = []
	var sprites: Array[String] = SpriteLibrary.get_dirt_sprites()
	var count: int = get_stain_count(room)
	if count <= 0 or sprites.is_empty():
		return stains
	var cells: Array[Vector2i] = []
	for cell: Vector2i in room["cells"]:
		cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return MapDecor.noise(a, SALT_CELL) < MapDecor.noise(b, SALT_CELL))
	for index: int in range(count):
		var cell: Vector2i = cells[index]
		var kind: int = int(MapDecor.noise(cell, SALT_KIND) * 1000.0) % sprites.size()
		stains.append([cell, sprites[kind]])
	return stains


func _draw() -> void:
	if _grid == null:
		return
	for room: Dictionary in _rooms:
		var tint := Color(1.0, 1.0, 1.0, 1.0 if OfficeState.is_room_dirty(room) else STAIN_ALPHA)
		for stain: Array in get_stains(room):
			SpriteLibrary.draw(self, String(stain[1]), _grid.grid_to_world(Vector2(stain[0])), tint)
