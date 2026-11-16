# Pinta las texturas del suelo (pisos del local y terreno del mapa) con más detalle que la
# casilla en pantalla: cada casilla de 64×32 px se pinta en DETAIL veces más píxeles y la
# capa del piso se dibuja a 1/DETAIL con suavizado, así el suelo no se ve pixelado de cerca.
#
# Cada estilo tiene un material (pasto, cerámica, madera, alfombra, concreto, grava, acera,
# asfalto) que pinta en coordenadas de la casilla (u, v de 0 a 1 a lo largo de los ejes de
# la cuadrícula). Los dibujos que se repiten (losas, tablones, juntas, manchas) usan esas
# coordenadas y ruido periódico, así casillas vecinas encajan sin costuras. Solo funciones
# puras: OfficeGrid arma el TileSet con la imagen.
class_name GroundPainter
extends RefCounted

## Cuántos píxeles de textura hay por píxel de la casilla en pantalla (el de los sprites:
## docs/sprites_128.md, 1 px del mundo = 2 px del sprite).
const DETAIL: int = 2

const GRASS: String = "grass"
const CERAMIC: String = "ceramic"
const WOOD: String = "wood"
const CARPET: String = "carpet"
const CONCRETE: String = "concrete"
const GRAVEL: String = "gravel"
const SLABS: String = "slabs"
const ASPHALT: String = "asphalt"

## Material de cada estilo del atlas (pisos de data/construction.json y estilos de data/map.json).
const MATERIALS: Dictionary[String, String] = {
	"bare": CONCRETE, "terrain": GRASS, "carpet": CARPET, "wood": WOOD, "ceramic": CERAMIC,
	"grass": GRASS, "outside": GRASS, "path": GRAVEL, "sidewalk": SLABS, "road": ASPHALT, "road_line": ASPHALT,
}
## Cuánto se acerca cada variante de color al color medio del estilo (0 = la variante tal cual):
## así las casillas vecinas del pasto se distinguen poco y no se ve un tablero.
const VARIANT_BLEND: float = 0.6
## Losas por lado en la cerámica, tablones por casilla en la madera y cuadros de alfombra.
const CERAMIC_TILES: int = 2
const WOOD_PLANKS: int = 4
const CARPET_TILES: int = 2
## Semilla fija de las manchas del pasto.
const GRASS_PATCH_SEED: int = 5417


## Material de un estilo del atlas (el pasto si no se conoce).
static func get_material(style: String) -> String:
	return MATERIALS.get(style, GRASS)


## Pinta una casilla en image con su esquina en offset (en píxeles de textura). colors son
## los colores del estilo y variant cuál usa esta columna del atlas. overlap es cuánto se
## pasa el rombo de su borde (en píxeles de textura) para no dejar rayas entre casillas.
static func paint(image: Image, offset: Vector2i, size: Vector2i, style: String, colors: Array, variant: int,
		overlap: float, line_color: Color = Color.TRANSPARENT, line_direction: Vector2 = Vector2.ZERO) -> void:
	var material: String = get_material(style)
	var base: Color = _variant_color(colors, variant)
	var other: Color = colors[(variant + 1) % colors.size()] if colors.size() > 1 else base.darkened(0.08)
	if material in [CERAMIC, WOOD, CARPET, CONCRETE]:
		# Los pisos del local son iguales en todas las casillas: el dibujo ya trae sus losas.
		base = colors[0]
		other = colors[1] if colors.size() > 1 else base.darkened(0.08)
	var seed: int = hash(style)
	var half: Vector2 = Vector2(size) / 2.0
	var limit: float = 1.0 + overlap / half.y
	var unit: Vector2 = line_direction.normalized()
	for y: int in range(size.y):
		for x: int in range(size.x):
			var px: float = (x + 0.5 - half.x) / half.x
			var py: float = (y + 0.5 - half.y) / half.y
			if absf(px) + absf(py) > limit:
				continue
			# Fuera del rombo (en el solape) se sigue el dibujo de la casilla de al lado.
			var u: float = fposmod((py + px) / 2.0 + 0.5, 1.0)
			var v: float = fposmod((py - px) / 2.0 + 0.5, 1.0)
			var color: Color = shade(material, base, other, u, v, x, y, seed + (variant * 101 if material == GRASS else 0))
			if line_color.a > 0.0:
				var point := Vector2(x + 0.5, y + 0.5) - half
				var normal := Vector2(-unit.y, unit.x)
				if absf(point.dot(normal)) <= 1.2 * DETAIL and absf(point.dot(unit)) <= half.x * 0.6:
					color = line_color.lerp(color, 0.12 * _hash(x / 2, y / 2, seed + 5))
			image.set_pixel(offset.x + x, offset.y + y, color)


## Color de un punto de la casilla según su material. u y v van de 0 a 1 a lo largo de los
## ejes de la cuadrícula; sx y sy son el píxel de la textura (para el grano fino).
static func shade(material: String, base: Color, other: Color, u: float, v: float, sx: int, sy: int, seed: int) -> Color:
	match material:
		CERAMIC:
			return _ceramic(base, other, u, v, seed)
		WOOD:
			return _wood(base, other, u, v, seed)
		CARPET:
			return _carpet(base, other, u, v, sx, sy, seed)
		CONCRETE:
			return _concrete(base, other, u, v, sx, sy, seed)
		GRAVEL:
			return _gravel(base, other, u, v, sx, sy, seed)
		SLABS:
			return _slabs(base, other, u, v, sx, sy, seed)
		ASPHALT:
			return _asphalt(base, other, u, v, sx, sy, seed)
	return _grass(base, other, u, v, sx, sy, seed)


# Pasto: manchas suaves de dos tonos, briznas (trazos de 2 × 6 píxeles, oscuras abajo y
# claras en la punta). Las briznas cambian con la variante para que no se note la repetición.
static func _grass(base: Color, other: Color, u: float, v: float, sx: int, sy: int, seed: int) -> Color:
	# Las manchas no cambian con la variante: así encajan entre casillas vecinas.
	var patches: float = noise(u, v, 3, GRASS_PATCH_SEED) * 0.6 + noise(u, v, 7, GRASS_PATCH_SEED + 1) * 0.4
	var color: Color = base.lerp(other, patches)
	color = _tone(color, (patches - 0.5) * 0.12)
	var column: int = sx / 2
	var shift: int = int(_hash(column, 0, seed + 2) * 6.0)
	var blade_row: int = floori(float(sy + shift) / 6.0)
	var blade: float = _hash(column, blade_row, seed + 3)
	var tip: bool = (sy + shift) % 6 < 2
	if blade < 0.2:
		color = color.lightened(0.1) if tip else color.darkened(0.16)
	elif blade > 0.9:
		color = color.lerp(Color("b5cf72"), 0.3) if tip else color.lightened(0.06)
	return color


# Cerámica: losas en tablero suave con junta, bisel claro arriba y oscuro abajo y brillo leve.
static func _ceramic(base: Color, other: Color, u: float, v: float, seed: int) -> Color:
	var tu: float = u * CERAMIC_TILES
	var tv: float = v * CERAMIC_TILES
	var iu: int = floori(tu)
	var iv: int = floori(tv)
	var fu: float = tu - iu
	var fv: float = tv - iv
	var color: Color = base if (iu + iv) % 2 == 0 else base.lerp(other, 0.6)
	color = _tone(color, (_hash(iu, iv, seed) - 0.5) * 0.06)
	var grout: float = minf(minf(fu, fv), minf(1.0 - fu, 1.0 - fv))
	if grout < 0.03:
		return base.darkened(0.32).lerp(Color(0.55, 0.55, 0.55), 0.25)
	if fu < 0.07 or fv < 0.07:
		color = color.lightened(0.09)
	elif fu > 0.93 or fv > 0.93:
		color = color.darkened(0.1)
	return _tone(color, (noise(u, v, 6, seed + 4) - 0.5) * 0.05)


# Madera: tablones a lo largo de u, con las uniones escalonadas, la ranura entre tablones y veta.
static func _wood(base: Color, other: Color, u: float, v: float, seed: int) -> Color:
	var plank_v: float = v * WOOD_PLANKS
	var plank: int = floori(plank_v)
	var across: float = plank_v - plank
	var ends: Array[float] = [0.0, 0.5, 0.25, 0.75]
	var along: float = fposmod(u - ends[plank % ends.size()], 1.0)
	var color: Color = base.lerp(other, _hash(plank, 0, seed) * 0.8)
	var grain: float = sin((across * 3.0 + noise(u, v, 4, seed + plank) * 2.5 + u * 1.5) * TAU)
	color = _tone(color, grain * 0.045 + (noise(u * 2.0, v, 8, seed + 9) - 0.5) * 0.05)
	if across < 0.06:
		color = color.darkened(0.3)
	elif across > 0.94:
		color = color.lightened(0.05)
	if along < 0.012 or along > 0.988:
		color = color.darkened(0.28)
	return color


# Alfombra: cuadros de alfombra con la fibra en direcciones alternas y grano fino.
static func _carpet(base: Color, other: Color, u: float, v: float, sx: int, sy: int, seed: int) -> Color:
	var tu: float = u * CARPET_TILES
	var tv: float = v * CARPET_TILES
	var iu: int = floori(tu)
	var iv: int = floori(tv)
	var fu: float = tu - iu
	var fv: float = tv - iv
	var color: Color = base.lerp(other, 0.35 if (iu + iv) % 2 == 0 else 0.0)
	var stripe: float = fu if (iu + iv) % 2 == 0 else fv
	color = _tone(color, sin(stripe * 40.0 * PI) * 0.025)
	color = _tone(color, (_hash(sx, sy, seed) - 0.5) * 0.1)
	if minf(minf(fu, fv), minf(1.0 - fu, 1.0 - fv)) < 0.012:
		color = color.darkened(0.12)
	return color


# Concreto (sin piso): manchas suaves y puntitos.
static func _concrete(base: Color, other: Color, u: float, v: float, sx: int, sy: int, seed: int) -> Color:
	var color: Color = base.lerp(other, noise(u, v, 4, seed) * 0.8)
	color = _tone(color, (noise(u, v, 10, seed + 1) - 0.5) * 0.06)
	var dot: float = _hash(sx / 2, sy / 2, seed + 2)
	if dot < 0.05:
		color = color.darkened(0.12)
	elif dot > 0.96:
		color = color.lightened(0.1)
	return color


# Grava del camino: tierra con piedritas claras y oscuras de 2×2 píxeles.
static func _gravel(base: Color, other: Color, u: float, v: float, sx: int, sy: int, seed: int) -> Color:
	var color: Color = base.lerp(other, noise(u, v, 5, seed))
	var stone: float = _hash(sx / 2, sy / 2, seed + 1)
	if stone < 0.12:
		color = color.darkened(0.16)
	elif stone > 0.9:
		color = color.lightened(0.14)
	return color


# Acera: una baldosa grande por casilla con junta en el borde y grano fino.
static func _slabs(base: Color, other: Color, u: float, v: float, sx: int, sy: int, seed: int) -> Color:
	var color: Color = base.lerp(other, noise(u, v, 3, seed) * 0.7)
	color = _tone(color, (_hash(sx, sy, seed + 1) - 0.5) * 0.06)
	var edge: float = minf(minf(u, v), minf(1.0 - u, 1.0 - v))
	if edge < 0.015:
		color = color.darkened(0.2)
	elif u < 0.05 or v < 0.05:
		color = color.lightened(0.05)
	return color


# Asfalto: grano fino de piedritas y manchas.
static func _asphalt(base: Color, other: Color, u: float, v: float, sx: int, sy: int, seed: int) -> Color:
	var color: Color = base.lerp(other, noise(u, v, 4, seed) * 0.8)
	var grain: float = _hash(sx, sy, seed + 1)
	if grain < 0.15:
		color = color.darkened(0.12)
	elif grain > 0.94:
		color = color.lightened(0.14)
	return color


# Color de una variante, acercado al color medio del estilo.
static func _variant_color(colors: Array, variant: int) -> Color:
	var mean := Color(0.0, 0.0, 0.0)
	for color: Color in colors:
		mean += color
	mean /= float(colors.size())
	mean.a = 1.0
	var own: Color = colors[variant % colors.size()]
	return own.lerp(mean, VARIANT_BLEND)


# Aclara (amount > 0) u oscurece (amount < 0) un color.
static func _tone(color: Color, amount: float) -> Color:
	return color.lightened(amount) if amount >= 0.0 else color.darkened(-amount)


## Ruido suave entre 0 y 1 que se repite cada casilla (period celdas por lado), así casillas
## vecinas encajan sin costura.
static func noise(u: float, v: float, period: int, seed: int) -> float:
	var x: float = fposmod(u, 1.0) * period
	var y: float = fposmod(v, 1.0) * period
	var ix: int = floori(x)
	var iy: int = floori(y)
	var fx: float = x - ix
	var fy: float = y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a: float = _hash(ix % period, iy % period, seed)
	var b: float = _hash((ix + 1) % period, iy % period, seed)
	var c: float = _hash(ix % period, (iy + 1) % period, seed)
	var d: float = _hash((ix + 1) % period, (iy + 1) % period, seed)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


# Número fijo entre 0 y 1 para unos enteros (azar que no cambia entre partidas).
static func _hash(x: int, y: int, seed: int) -> float:
	var h: int = (x * 374761393 + y * 668265263 + seed * 1274126177) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0
