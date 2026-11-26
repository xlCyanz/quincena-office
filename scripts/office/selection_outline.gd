# Contorno punteado del mueble elegido en Construir: sigue la silueta de sus piezas (sprites o la
# caja provisional). Las piezas se pintan en una máscara y se toman los bordes entre lleno y vacío.
# Funciones estáticas; OfficeGrid guarda el resultado de cada mueble.
class_name SelectionOutline
extends RefCounted

## Alfa mínimo (0–255) de un píxel que cuenta como parte del mueble.
const ALPHA_MIN: int = 128


## Máscara (RGBA8, el alfa es lo lleno) de la unión de las piezas, con 1 píxel libre en cada lado.
## Cada pieza es {image: Image, rect: Rect2} o {polygon: PackedVector2Array}, en px del mundo.
## La máscara empieza en bounds.position y tiene resolution píxeles por px del mundo.
static func build_mask(pieces: Array[Dictionary], bounds: Rect2, resolution: float) -> Image:
	var size: Vector2i = Vector2i((bounds.size * resolution).ceil()) + Vector2i(2, 2)
	var mask := Image.create_empty(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	for piece: Dictionary in pieces:
		if piece.has("image"):
			_paint_image(mask, piece["image"], piece["rect"], bounds.position, resolution)
		elif piece.has("polygon"):
			_paint_polygon(mask, piece["polygon"], bounds.position, resolution)
	return mask


static func _paint_image(mask: Image, source: Image, rect: Rect2, origin: Vector2, resolution: float) -> void:
	var image: Image = source.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var target: Vector2i = Vector2i((rect.size * resolution).round())
	if target.x < 1 or target.y < 1:
		return
	if target != image.get_size():
		image.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
	var at: Vector2i = Vector2i(((rect.position - origin) * resolution).round()) + Vector2i.ONE
	mask.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)


static func _paint_polygon(mask: Image, polygon: PackedVector2Array, origin: Vector2, resolution: float) -> void:
	if polygon.size() < 3:
		return
	var local := PackedVector2Array()
	for point: Vector2 in polygon:
		local.append((point - origin) * resolution + Vector2.ONE)
	var area := Rect2(local[0], Vector2.ZERO)
	for point: Vector2 in local:
		area = area.expand(point)
	var first: Vector2i = Vector2i(area.position.floor()).max(Vector2i.ZERO)
	var last: Vector2i = Vector2i(area.end.ceil()).min(mask.get_size())
	for y: int in range(first.y, last.y):
		for x: int in range(first.x, last.x):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), local):
				mask.set_pixel(x, y, Color.WHITE)


## Segmentos (pares de puntos, px del mundo) del borde exterior de la máscara (sin huecos), punteados: tramos de dash píxeles de
## la máscara, uno sí y uno no. gap: cuánto se separa la línea de la silueta hacia afuera (px de la máscara).
static func trace(mask: Image, origin: Vector2, resolution: float, dash: int, gap: float) -> PackedVector2Array:
	var width: int = mask.get_width()
	var height: int = mask.get_height()
	var data: PackedByteArray = mask.get_data()
	var filled := PackedByteArray()
	filled.resize(width * height)
	for i: int in range(width * height):
		filled[i] = 1 if data[i * 4 + 3] >= ALPHA_MIN else 0
	_fill_holes(filled, width, height)
	var segments := PackedVector2Array()
	# Bordes de arriba y abajo de cada fila, y de izquierda y derecha de cada columna.
	for side: int in [-1, 1]:
		for y: int in range(height):
			var run_start: int = -1
			for x: int in range(width + 1):
				var on: bool = x < width and _is_edge(filled, width, height, x, y, 0, side) and _dash_on(x + y, dash)
				if on and run_start < 0:
					run_start = x
				elif not on and run_start >= 0:
					var line_y: float = (y + (1.0 if side > 0 else 0.0)) + side * gap
					segments.append(Vector2(run_start, line_y))
					segments.append(Vector2(x, line_y))
					run_start = -1
		for x: int in range(width):
			var run_start: int = -1
			for y: int in range(height + 1):
				var on: bool = y < height and _is_edge(filled, width, height, x, y, side, 0) and _dash_on(x + y, dash)
				if on and run_start < 0:
					run_start = y
				elif not on and run_start >= 0:
					var line_x: float = (x + (1.0 if side > 0 else 0.0)) + side * gap
					segments.append(Vector2(line_x, run_start))
					segments.append(Vector2(line_x, y))
					run_start = -1
	# A px del mundo (la máscara tiene 1 píxel de margen).
	for i: int in range(segments.size()):
		segments[i] = origin + (segments[i] - Vector2.ONE) / resolution
	return segments


# Llena los huecos de adentro (bajo un escritorio, entre las patas): solo queda vacío lo que toca el borde.
static func _fill_holes(filled: PackedByteArray, width: int, height: int) -> void:
	var outside := PackedByteArray()
	outside.resize(width * height)
	var stack := PackedInt32Array()
	for x: int in range(width):
		stack.append(x)
		stack.append((height - 1) * width + x)
	for y: int in range(height):
		stack.append(y * width)
		stack.append(y * width + width - 1)
	while not stack.is_empty():
		var index: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if outside[index] == 1 or filled[index] == 1:
			continue
		outside[index] = 1
		var x: int = index % width
		if x > 0:
			stack.append(index - 1)
		if x < width - 1:
			stack.append(index + 1)
		if index >= width:
			stack.append(index - width)
		if index < (height - 1) * width:
			stack.append(index + width)
	for i: int in range(width * height):
		if outside[i] == 0:
			filled[i] = 1


# Píxel lleno con su vecino (dx, dy) vacío.
static func _is_edge(filled: PackedByteArray, width: int, height: int, x: int, y: int, dx: int, dy: int) -> bool:
	if filled[y * width + x] == 0:
		return false
	var nx: int = x + dx
	var ny: int = y + dy
	return nx < 0 or ny < 0 or nx >= width or ny >= height or filled[ny * width + nx] == 0


static func _dash_on(step: int, dash: int) -> bool:
	return dash <= 0 or (step / dash) % 2 == 0
