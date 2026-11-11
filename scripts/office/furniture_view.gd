# Dibujo provisional de un mueble: una caja isométrica del color y la altura que dice
# el catálogo, sobre las casillas que ocupa. Va dentro de la capa ordenada por Y.
class_name FurnitureView
extends Node2D

## Cuánto se adelanta hacia atrás el punto de orden del mueble: así un personaje en la
## misma casilla (por ejemplo, sentado en una silla) siempre se dibuja delante.
const SORT_BIAS_PX: float = 1.0

var item_id: String = ""
var footprint: Array[Vector2i] = []

var _base := PackedVector2Array()
var _height: float = 0.0
var _color := Color.WHITE


## Coloca el mueble. corners son las cuatro esquinas de su base en píxeles del mundo
## (arriba, derecha, abajo, izquierda) y center el centro de la base.
func setup(id: String, cells: Array[Vector2i], corners: PackedVector2Array, center: Vector2) -> void:
	item_id = id
	footprint = cells
	var item: Dictionary = FurnitureCatalog.get_item(id)
	_height = item.get("height", 16.0)
	_color = item.get("color", Color.WHITE)
	position = center - Vector2(0.0, SORT_BIAS_PX)
	_base = PackedVector2Array()
	for corner: Vector2 in corners:
		_base.append(corner - position)
	queue_redraw()


func _draw() -> void:
	IsoBox.draw(self, _base, _height, _color)
