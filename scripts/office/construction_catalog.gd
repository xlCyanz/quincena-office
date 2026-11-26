# Precios y arte provisional de pisos, paredes y puertas (data/construction.json), leídos una vez.
class_name ConstructionCatalog
extends RefCounted

const CATALOG_PATH: String = "res://data/construction.json"

## Tipo de piso de una casilla sin piso.
const BARE_FLOOR: String = "bare"
## Terreno del solar alrededor del local (no se construye sobre él).
const TERRAIN: String = "terrain"
## Tipos de pieza que pueden ir en un borde.
const WALL: String = "wall"
const DOOR: String = "door"
## Ventana: solo en el contorno, en lugar de un tramo de pared.
const WINDOW: String = "window"
## Puerta doble de vidrio: solo en lugar de la puerta de entrada.
const GLASS_DOOR: String = "glass_door"
## Puerta de vidrio doble ancha: ocupa la puerta de entrada y el tramo de pared de al lado.
const GLASS_DOOR_DOUBLE: String = "glass_door_double"

static var _data: Dictionary = {}


## Tipos de piso que se pueden comprar, en el orden del archivo.
static func get_floor_types() -> Array[String]:
	var types: Array[String] = []
	types.assign(_catalog().get("floors", {}).keys())
	return types


## Datos de un piso (name, price_per_m2, colors). BARE_FLOOR no tiene precio.
static func get_floor(floor_type: String) -> Dictionary:
	if floor_type == BARE_FLOOR:
		return _catalog().get("bare_floor", {})
	if floor_type == TERRAIN:
		return _catalog().get("terrain", {})
	return _catalog().get("floors", {}).get(floor_type, {})


## Datos de una pieza de borde: name, price, height y color.
static func get_edge_piece(kind: String) -> Dictionary:
	return _catalog().get(kind, {})


## Indica si una pieza es puerta (deja pasar y abre habitaciones).
static func is_door(kind: String) -> bool:
	return kind == DOOR or kind == GLASS_DOOR or kind == GLASS_DOOR_DOUBLE


## Indica si una pieza es de vidrio (va solo en la entrada y suma ambiente).
static func is_glass_door(kind: String) -> bool:
	return kind == GLASS_DOOR or kind == GLASS_DOOR_DOUBLE


## Indica si kind es una pieza de borde.
static func is_edge_piece(kind: String) -> bool:
	return kind == WALL or kind == DOOR or kind == WINDOW or kind == GLASS_DOOR or kind == GLASS_DOOR_DOUBLE


## Precio de un piso por casilla o de una pieza de borde.
static func get_price(kind: String) -> int:
	if is_edge_piece(kind):
		return int(get_edge_piece(kind).get("price", 0))
	return int(get_floor(kind).get("price_per_m2", 0))


## Lo que se recupera al vender (hacia abajo).
static func get_refund(kind: String) -> int:
	return floori(get_price(kind) * float(_catalog().get("sale_refund_ratio", 0.0)))


## Nombre visible para el jugador.
static func get_display_name(kind: String) -> String:
	if is_edge_piece(kind):
		return String(get_edge_piece(kind).get("name", kind))
	return String(get_floor(kind).get("name", kind))


## Puntos de ambiente de una ventana para su habitación.
static func get_window_ambiance() -> int:
	return int(get_edge_piece(WINDOW).get("ambiance", 0))


## Puntos de ambiente de la puerta de vidrio (o de la doble con kind) para su habitación.
static func get_glass_door_ambiance(kind: String = GLASS_DOOR) -> int:
	return int(get_edge_piece(kind).get("ambiance", 0))


## Alto en píxeles de las piezas bajas (todas menos las de atrás).
static func get_low_wall_height() -> float:
	return float(_catalog().get("low_wall_height", 10))


## Colores (tablero de ajedrez) de un tipo de piso.
static func get_floor_colors(floor_type: String) -> Array[Color]:
	var colors: Array[Color] = []
	for hex: Variant in get_floor(floor_type).get("colors", ["888888", "777777"]):
		colors.append(Color(String(hex)))
	return colors


## Terreno: {"price_per_m2", "floor"}.
static func get_land() -> Dictionary:
	return _catalog().get("land", {})


## Lado mínimo y máximo (x, y) de los lotes en que se parte el solar.
static func get_land_plot_sides() -> Vector2i:
	var sides: Array = get_land().get("plot_sides", [3, 6])
	var low: int = maxi(int(sides[0]), 1)
	return Vector2i(low, maxi(int(sides[1]), low))


## Precio del terreno por m², sin el piso.
static func get_land_price() -> int:
	return int(get_land().get("price_per_m2", 0))


## Costo del piso con que llegan area m² de terreno: su precio × floor_price_ratio, redondeado.
static func get_land_floor_cost(area: int) -> int:
	var land: Dictionary = get_land()
	var floor_type: String = String(land.get("floor", BARE_FLOOR))
	return roundi(area * get_price(floor_type) * float(land.get("floor_price_ratio", 1.0)))


## Lo que devuelve vender area m² de terreno: sale_refund_ratio del terreno y su piso.
static func get_land_refund(area: int) -> int:
	var price: int = area * get_land_price() + get_land_floor_cost(area)
	return floori(price * float(_catalog().get("sale_refund_ratio", 0.0)))


static func _catalog() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("No se pudo leer %s" % CATALOG_PATH)
	return _data
