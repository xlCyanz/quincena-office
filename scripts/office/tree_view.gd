# Árbol de adorno del mapa (arte provisional): tronco y copa redonda sobre una casilla
# fuera del local. Va en la capa ordenada por Y para que un personaje pase por delante o
# por detrás. Su tamaño y su verde salen de la posición (MapDecor.noise).
class_name TreeView
extends Node2D

const TRUNK_SIZE: float = 0.14
const TRUNK_HEIGHT_PX: float = 18.0
const CANOPY_RADIUS_PX: float = 15.0

var cell := Vector2i.ZERO

var _grid: OfficeGrid
var _scale: float = 1.0
var _trunk_color := Color.SADDLE_BROWN
var _leaf_color := Color.FOREST_GREEN


func setup(grid: OfficeGrid, tree_cell: Vector2i) -> void:
	_grid = grid
	cell = tree_cell
	var data: Dictionary = MapDecor.get_data().get("trees", {})
	_trunk_color = Color(String(data.get("trunk_color", "6b4a32")))
	var leaves: Array = data.get("leaf_colors", ["3f7a3a"])
	var pick: int = floori(MapDecor.noise(cell, MapDecor.SALT_TREE_COLOR) * leaves.size())
	_leaf_color = Color(String(leaves[clampi(pick, 0, leaves.size() - 1)]))
	_scale = 0.8 + 0.5 * MapDecor.noise(cell, MapDecor.SALT_TREE_SIZE)
	position = grid.grid_to_world(Vector2(cell))
	queue_redraw()


func _draw() -> void:
	var half := Vector2(TRUNK_SIZE, TRUNK_SIZE) / 2.0
	var center := Vector2(cell)
	var base := PackedVector2Array()
	for corner: Vector2 in IsoBox.grid_rect_corners(_grid, center - half, center + half):
		base.append(corner - position)
	var trunk_height: float = TRUNK_HEIGHT_PX * _scale
	# Sombra en el piso.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, CANOPY_RADIUS_PX * _scale * 0.9, Color(0.0, 0.0, 0.0, 0.18))
	draw_set_transform(Vector2.ZERO)
	IsoBox.draw(self, base, trunk_height, _trunk_color)
	var radius: float = CANOPY_RADIUS_PX * _scale
	var top := Vector2(0.0, -trunk_height - radius * 0.6)
	draw_circle(top + Vector2(0.0, radius * 0.25), radius, _leaf_color.darkened(0.2))
	draw_circle(top + Vector2(-radius * 0.35, 0.0), radius * 0.7, _leaf_color)
	draw_circle(top + Vector2(radius * 0.35, -radius * 0.1), radius * 0.65, _leaf_color.lightened(0.1))
	draw_circle(top + Vector2(0.0, -radius * 0.45), radius * 0.55, _leaf_color.lightened(0.18))
