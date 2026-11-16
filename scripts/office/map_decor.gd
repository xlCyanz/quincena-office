# Arte del mapa alrededor del local (data/map.json, funciones puras): pasto del solar, camino a la
# calle y, afuera, acera y calle del lado de la entrada y pasto oscuro con árboles. Azar fijo por casilla.
class_name MapDecor
extends RefCounted

const DATA_PATH: String = "res://data/map.json"

## Estilos de casilla (ver data/map.json).
const GRASS: String = "grass"
const PATH: String = "path"
const OUTSIDE: String = "outside"
const SIDEWALK: String = "sidewalk"
const ROAD: String = "road"
## Calle con su línea; la columna depende de hacia dónde corre.
const ROAD_LINE: String = "road_line"

## Sal del azar fijo de cada uso.
const SALT_STYLE: int = 1
const SALT_TREE: int = 2
const SALT_TREE_SIZE: int = 3
const SALT_TREE_COLOR: int = 4
const SALT_GRASS: int = 5
## Tamaño de las zonas de pasto, en casillas, y cuánto del mapa toma cada familia.
const GRASS_ZONE: int = 4
const GRASS_FAMILIES: Array[Array] = [["plain", 0.40], ["lush", 0.23], ["patchy", 0.22], ["sunny", 0.15]]

const DIRECTIONS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

static var _data: Dictionary = {}


## Datos de data/map.json (se leen una vez).
static func get_data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(DATA_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


## Colores de cada estilo de casilla: nombre → lista de colores.
static func get_styles() -> Dictionary[String, Array]:
	var styles: Dictionary[String, Array] = {}
	var raw: Dictionary = get_data().get("styles", {})
	for style: String in raw:
		var colors: Array[Color] = []
		for hex: String in raw[style]:
			colors.append(Color(hex))
		styles[style] = colors
	return styles


## Número entre 0 y 1 fijo por casilla y uso (salt).
static func noise(cell: Vector2i, salt: int) -> float:
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = (h ^ (h >> 16)) & 0x7fffffff
	return float(h % 100000) / 100000.0


## Familia de pasto de una casilla: por zonas de GRASS_ZONE con ruido suave, sin repetición visible.
static func get_grass_family(cell: Vector2i) -> String:
	var at: Vector2 = Vector2(cell) / float(GRASS_ZONE)
	var corner := Vector2i(floori(at.x), floori(at.y))
	var t: Vector2 = at - Vector2(corner)
	t = t * t * (Vector2(3.0, 3.0) - 2.0 * t)
	var top: float = lerpf(noise(corner, SALT_GRASS), noise(corner + Vector2i(1, 0), SALT_GRASS), t.x)
	var bottom: float = lerpf(noise(corner + Vector2i(0, 1), SALT_GRASS), noise(corner + Vector2i(1, 1), SALT_GRASS), t.x)
	# El ruido suavizado se junta al medio: se estira para que salgan las cuatro familias.
	var value: float = clampf(0.5 + (lerpf(top, bottom, t.y) - 0.5) * 1.8, 0.0, 0.9999)
	var limit: float = 0.0
	for family: Array in GRASS_FAMILIES:
		limit += float(family[1])
		if value < limit:
			return String(family[0])
	return String(GRASS_FAMILIES[0][0])


## Dirección de salida por la entrada (de adentro a afuera); sin entrada, +y.
static func get_exit_direction(lot: Lot, entrance_outside: Vector2i) -> Vector2i:
	for direction: Vector2i in DIRECTIONS:
		if lot.has_point(entrance_outside - direction):
			return direction
	return Vector2i(0, 1)


## Eje a lo largo del que corre la calle (GridEdge.AXIS_X o AXIS_Y).
static func get_road_axis(exit_direction: Vector2i) -> int:
	return GridEdge.AXIS_X if exit_direction.x == 0 else GridEdge.AXIS_Y


## Plano: {"tiles": casilla → estilo (solar y surround_width alrededor, sin el local),
## "trees": casillas con árbol, "road_axis"}.
static func plan(site: Rect2i, lot: Lot, entrance_outside: Vector2i) -> Dictionary:
	var data: Dictionary = get_data()
	var surround: int = int(data.get("surround_width", 0))
	var exit: Vector2i = get_exit_direction(lot, entrance_outside)
	var tiles: Dictionary[Vector2i, String] = {}
	var trees: Array[Vector2i] = []
	if site.size == Vector2i.ZERO:
		return {"tiles": tiles, "trees": trees, "road_axis": get_road_axis(exit)}
	# Camino de la puerta hasta el borde del solar.
	var path: Dictionary[Vector2i, bool] = {}
	var step: Vector2i = entrance_outside
	while site.has_point(step) and not lot.has_point(step):
		path[step] = true
		step += exit
	var near_lot: Dictionary[Vector2i, bool] = _near_cells(lot, int(data.get("trees", {}).get("lot_margin", 0)))
	var tree_data: Dictionary = data.get("trees", {})
	var outer: Rect2i = site.grow(surround)
	for x: int in range(outer.position.x, outer.end.x):
		for y: int in range(outer.position.y, outer.end.y):
			var cell := Vector2i(x, y)
			if lot.has_point(cell):
				continue
			var style: String
			if site.has_point(cell):
				style = PATH if path.has(cell) else GRASS
				if style == GRASS and not near_lot.has(cell) \
						and noise(cell, SALT_TREE) < float(tree_data.get("site_chance", 0.0)):
					trees.append(cell)
			else:
				style = _outside_style(cell, site, exit, data)
				if style == OUTSIDE and noise(cell, SALT_TREE) < float(tree_data.get("outside_chance", 0.0)):
					trees.append(cell)
			tiles[cell] = style
	return {"tiles": tiles, "trees": trees, "road_axis": get_road_axis(exit)}


# Fuera del solar: acera y calle del lado de la salida, pasto oscuro en el resto.
static func _outside_style(cell: Vector2i, site: Rect2i, exit: Vector2i, data: Dictionary) -> String:
	var distance: int = 0 # casillas más allá del borde, del lado de la salida
	var along: int = 0  # posición a lo largo de la calle
	match exit:
		Vector2i(0, 1):
			distance = cell.y - site.end.y + 1
			along = cell.x
		Vector2i(0, -1):
			distance = site.position.y - cell.y
			along = cell.x
		Vector2i(1, 0):
			distance = cell.x - site.end.x + 1
			along = cell.y
		_:
			distance = site.position.x - cell.x
			along = cell.y
	var sidewalk: int = int(data.get("sidewalk_width", 0))
	var road: int = int(data.get("road_width", 0))
	if distance < 1:
		return OUTSIDE
	if distance <= sidewalk:
		return SIDEWALK
	if distance <= sidewalk + road:
		var row: int = distance - sidewalk - 1
		var gap: int = maxi(int(data.get("road_line_gap", 1)), 1)
		if row == int(data.get("road_line_row", -1)) and posmod(along, gap) != 0:
			return ROAD_LINE
		return ROAD
	return OUTSIDE


# Casillas del local y las que están a menos de margin (con diagonales).
static func _near_cells(lot: Lot, margin: int) -> Dictionary[Vector2i, bool]:
	var near: Dictionary[Vector2i, bool] = {}
	var reach: int = maxi(margin - 1, 0)
	for cell: Vector2i in lot.get_cells():
		for dx: int in range(-reach, reach + 1):
			for dy: int in range(-reach, reach + 1):
				near[cell + Vector2i(dx, dy)] = true
	return near
