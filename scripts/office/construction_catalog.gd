# Precios y arte provisional de pisos, paredes y puertas, leídos de
# data/construction.json una sola vez. Se usa por su nombre de clase.
class_name ConstructionCatalog
extends RefCounted

const CATALOG_PATH: String = "res://data/construction.json"

## Tipo de piso de una casilla sin piso.
const BARE_FLOOR: String = "bare"
## Terreno del solar que rodea al local (no se construye sobre él).
const TERRAIN: String = "terrain"
## Tipos de pieza que pueden ir en un borde.
const WALL: String = "wall"
const DOOR: String = "door"

static var _data: Dictionary = {}


## Tipos de piso que se pueden comprar, en el orden del archivo.
static func get_floor_types() -> Array[String]:
	var types: Array[String] = []
	types.assign(_catalog().get("floors", {}).keys())
	return types


## Datos de un tipo de piso (name, price_per_m2, colors). BARE_FLOOR no tiene precio.
static func get_floor(floor_type: String) -> Dictionary:
	if floor_type == BARE_FLOOR:
		return _catalog().get("bare_floor", {})
	if floor_type == TERRAIN:
		return _catalog().get("terrain", {})
	return _catalog().get("floors", {}).get(floor_type, {})


## Datos de una pieza de borde (WALL o DOOR): name, price, height y color.
static func get_edge_piece(kind: String) -> Dictionary:
	return _catalog().get(kind, {})


## Precio de compra de un piso por casilla, de una pared o de una puerta.
static func get_price(kind: String) -> int:
	if kind == WALL or kind == DOOR:
		return int(get_edge_piece(kind).get("price", 0))
	return int(get_floor(kind).get("price_per_m2", 0))


## Lo que se recupera al vender (redondeado hacia abajo).
static func get_refund(kind: String) -> int:
	return floori(get_price(kind) * float(_catalog().get("sale_refund_ratio", 0.0)))


## Nombre visible para el jugador.
static func get_display_name(kind: String) -> String:
	if kind == WALL or kind == DOOR:
		return String(get_edge_piece(kind).get("name", kind))
	return String(get_floor(kind).get("name", kind))


## Colores (tablero de ajedrez) de un tipo de piso.
static func get_floor_colors(floor_type: String) -> Array[Color]:
	var colors: Array[Color] = []
	for hex: Variant in get_floor(floor_type).get("colors", ["888888", "777777"]):
		colors.append(Color(String(hex)))
	return colors


## Precio del terreno por m² y el piso con que llega: {"price_per_m2", "floor"}.
static func get_land() -> Dictionary:
	return _catalog().get("land", {})


## Precio del terreno por m², sin el piso.
static func get_land_price() -> int:
	return int(get_land().get("price_per_m2", 0))


## Lo que cuesta el piso con que llegan area m² de terreno: su precio por
## floor_price_ratio (la mitad), redondeado.
static func get_land_floor_cost(area: int) -> int:
	var land: Dictionary = get_land()
	var floor_type: String = String(land.get("floor", BARE_FLOOR))
	return roundi(area * get_price(floor_type) * float(land.get("floor_price_ratio", 1.0)))


static func _catalog() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("No se pudo leer %s" % CATALOG_PATH)
	return _data
