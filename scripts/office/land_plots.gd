# Lotes de terreno: el solar, menos el local inicial, partido en rectángulos de tamaños variados. Se
# parte igual cada vez con la misma semilla (OfficeState.land_seed). Funciones estáticas.
class_name LandPlots
extends RefCounted


## Rectángulos que cubren el solar sin el local inicial (base), sin solaparse. Cada lado mide de
## min_side a max_side, salvo donde la franja junto al borde del solar es más angosta que min_side.
static func partition(site: Rect2i, base: Rect2i, seed_value: int, min_side: int, max_side: int) -> Array[Rect2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var middle: Rect2i = base.intersection(site)
	# Cuatro franjas alrededor del local inicial: arriba y abajo a todo lo ancho, izquierda y derecha a su alto.
	var bands: Array[Rect2i] = [
		Rect2i(site.position.x, site.position.y, site.size.x, middle.position.y - site.position.y),
		Rect2i(site.position.x, middle.end.y, site.size.x, site.end.y - middle.end.y),
		Rect2i(site.position.x, middle.position.y, middle.position.x - site.position.x, middle.size.y),
		Rect2i(middle.end.x, middle.position.y, site.end.x - middle.end.x, middle.size.y),
	]
	var plots: Array[Rect2i] = []
	for band: Rect2i in bands:
		if band.size.x > 0 and band.size.y > 0:
			_split(band, rng, maxi(min_side, 1), maxi(max_side, min_side), plots)
	return plots


## Como partition, en bloques de construcción de step casillas (BuildGrid): site y base alineados a step y los
## lados en bloques; los lotes salen con lados y posición múltiplos de step.
static func partition_blocks(site: Rect2i, base: Rect2i, seed_value: int, min_blocks: int, max_blocks: int,
		step: int) -> Array[Rect2i]:
	var plots: Array[Rect2i] = []
	for plot: Rect2i in partition(_shrink(site, step), _shrink(base, step), seed_value, min_blocks, max_blocks):
		plots.append(Rect2i(plot.position * step, plot.size * step))
	return plots


# Rectángulo en unidades de step (los bordes que no caen justo se recortan hacia adentro).
static func _shrink(rect: Rect2i, step: int) -> Rect2i:
	var low := Vector2i(ceili(float(rect.position.x) / step), ceili(float(rect.position.y) / step))
	var high := Vector2i(floori(float(rect.end.x) / step), floori(float(rect.end.y) / step))
	return Rect2i(low, (high - low).max(Vector2i.ZERO))


# Corta el rectángulo en dos (a lo largo de su lado más largo) hasta que los lados quepan en max_side;
# a veces corta antes, para que salgan tamaños distintos.
static func _split(rect: Rect2i, rng: RandomNumberGenerator, min_side: int, max_side: int, out: Array[Rect2i]) -> void:
	var can_x: bool = rect.size.x >= min_side * 2
	var can_y: bool = rect.size.y >= min_side * 2
	var must: bool = (rect.size.x > max_side and can_x) or (rect.size.y > max_side and can_y)
	if not must and (not (can_x or can_y) or rng.randf() < 0.6):
		out.append(rect)
		return
	var along_x: bool
	if rect.size.x > max_side and can_x and (rect.size.x >= rect.size.y or not (rect.size.y > max_side and can_y)):
		along_x = true
	elif rect.size.y > max_side and can_y:
		along_x = false
	else:
		along_x = can_x and (not can_y or rng.randf() < 0.5)
	var length: int = rect.size.x if along_x else rect.size.y
	var cut: int = rng.randi_range(min_side, length - min_side)
	if along_x:
		_split(Rect2i(rect.position, Vector2i(cut, rect.size.y)), rng, min_side, max_side, out)
		_split(Rect2i(rect.position + Vector2i(cut, 0), Vector2i(rect.size.x - cut, rect.size.y)), rng, min_side, max_side, out)
	else:
		_split(Rect2i(rect.position, Vector2i(rect.size.x, cut)), rng, min_side, max_side, out)
		_split(Rect2i(rect.position + Vector2i(0, cut), Vector2i(rect.size.x, rect.size.y - cut)), rng, min_side, max_side, out)


## Casillas de un rectángulo, ordenadas.
static func get_cells(rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			cells.append(Vector2i(x, y))
	return cells
