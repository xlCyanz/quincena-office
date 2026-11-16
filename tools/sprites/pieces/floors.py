# Pisos y terreno (docs/sprites_128.md, sección 5; estilo de tools/sprites/STYLE.md).
#
#   floor_ceramic_0..3   cerámica blanca: 2×2 losas en damero de dos blancos, junta gris de 1 px,
#                        bisel claro arriba y gris abajo, esquinas redondeadas y reflejo en diagonal
#   floor_wood_0..3      8 tablas angostas de madera naranja con cortes escalonados, moteado y vetas
#   floor_carpet_0..3    alfombra lila de pared a pared: ruido de dominós en 4 tonos, algo agrupado
#   floor_bare_0..3      concreto (sin piso): grises cálidos de poco contraste, poros y una grieta fina
#   ground_grass_<familia>_0..3    pasto del solar en 4 familias que empalman: plain, patchy, lush y sunny
#   ground_outside_<familia>_0..3  lo mismo fuera del solar, 15 % más oscuro
#   ground_path_0..3     camino de grava: muchas piedras con cara clara, lado y contorno-sombra
#   ground_sidewalk_0..3 acera: una losa por casilla con junta en el borde y bisel
#   ground_road_0..3     calle: asfalto de granos sueltos
#   ground_road_line_x_0..3 / _y_0..3  calle con la línea amarilla por el medio a lo largo de x o de y
#
# Las 4 variantes de cada material comparten el borde y tienen la MISMA cantidad de pixeles por color.
# Se dibuja en la rejilla isométrica (grid.iu, grid.iv): celda = 1 px, así las líneas salen 2:1.
import os

import numpy as np
from PIL import Image

import iso
import palette as pal
import pattern
import sheet

CONSTRUCTION = iso.load_json("data/construction.json")
MAP = iso.load_json("data/map.json")
VARIANTS = 4
CELL = 64  # px de eje por casilla
ANCHOR = [64, 96]  # punto de apoyo de una casilla de piso (centro del rombo)


def color_counts(index, mask, size):
    """Cuántos pixeles hay de cada color de la paleta dentro de mask."""
    return np.bincount(index[mask].ravel(), minlength=size)


def check_same_counts(name, counts):
    """Todas las variantes deben tener la misma cantidad de pixeles de cada color."""
    for variant, count in enumerate(counts):
        if not np.array_equal(count, counts[0]):
            raise ValueError("%s: la variante %d no tiene los mismos pixeles por color que la 0 (%s contra %s)"
                             % (name, variant, count.tolist(), counts[0].tolist()))


def brightness(index, colors):
    """Brillo (0–255) de cada pixel de un arreglo de índices de paleta."""
    table = np.array([pal.luminance(color) for color in colors])
    return table[index]


def repetition(tiles, colors):
    """Varianza del promedio de las variantes entre la varianza total del brillo: 0.25 si las 4
    no se parecen, 1.0 si son iguales."""
    mask = tiles[0][0].mask
    values = np.array([brightness(index, colors)[mask] for _grid, index in tiles])
    mean = values.mean()
    return float(((values.mean(axis=0) - mean) ** 2).mean() / ((values - mean) ** 2).mean())


# ---------------------------------------------------------------------- cerámica

# 2×2 losas por casilla en damero de dos tonos; las variantes cambian qué losas llevan reflejo.
(C_JOINT, C_SHADE, C_SOFT_SHADE, C_OTHER, C_BASE, C_GLAZE, C_LIGHT) = range(7)
CERAMIC = pal.palette([
    "9a9897",                                     # junta
    pal.CERAMIC_WHITE[pal.LEFT],                  # bisel de abajo a la derecha (bbb9b9)
    pal.CERAMIC_WHITE[pal.SOFT],                  # bisel de abajo a la izquierda (d2d1d1)
    pal.mix(pal.CERAMIC_WHITE[pal.BASE], pal.CERAMIC_WHITE[pal.SOFT], 0.3),  # losa del otro tono
    pal.CERAMIC_WHITE[pal.BASE],                  # losa (e8e8e8)
    pal.mix(pal.CERAMIC_WHITE[pal.BASE], "ffffff", 0.6),  # reflejo
    "ffffff",                                     # bisel de arriba a la izquierda
], name="ceramic")
SLAB = 32  # celdas de eje por losa (2×2 por casilla); la junta es la primera fila de cada losa
# Reflejo: franjas "/" con k = 2·du − dv: (k0, k1, du mínimo, du máximo), en celdas de la losa (2 … 30).
CERAMIC_GLINTS = {
    "wide": ((14, 19, 6, 24), (24, 25, 10, 26)),
    "thin": ((8, 10, 4, 18),),
    "none": (),
}
# Reflejo de cada losa (0 arriba, 1 derecha, 2 izquierda, 3 abajo) por variante. El ancho va en
# una losa del tono base (0 o 3) y el fino en una del otro (1 o 2): mismos pixeles por color.
CERAMIC_LAYOUTS = (
    ("wide", "thin", "none", "none"),
    ("none", "none", "thin", "wide"),
    ("wide", "none", "thin", "none"),
    ("none", "thin", "none", "wide"),
)


def ceramic_tile(variant):
    """Índices de paleta de una casilla de cerámica blanca."""
    grid = iso.tile_grid()
    du = np.mod(grid.iu, SLAB)
    dv = np.mod(grid.iv, SLAB)
    su, sv = grid.iu // SLAB, grid.iv // SLAB
    slab = su + 2 * sv
    index = np.where((su + sv) % 2 == 0, C_BASE, C_OTHER).astype(np.int16)
    field = (du >= 2) & (dv >= 2) & (du <= SLAB - 3) & (dv <= SLAB - 3)
    k = 2 * du - dv
    for number, glint in enumerate(CERAMIC_LAYOUTS[variant]):
        area = grid.mask & field & (slab == number)
        for k0, k1, low, high in CERAMIC_GLINTS[glint]:
            index[area & (k >= k0) & (k <= k1) & (du >= low) & (du <= high)] = C_GLAZE
    # Biseles: claro arriba, gris abajo a la izquierda, más oscuro abajo a la derecha.
    index[(dv == 1) & (du >= 1)] = C_LIGHT
    index[(du == 1) & (dv >= 1)] = C_LIGHT
    index[(dv == SLAB - 1) & (du >= 1)] = C_SOFT_SHADE
    index[(du == SLAB - 1) & (dv >= 1)] = C_SHADE
    index[(du == 0) | (dv == 0)] = C_JOINT
    # Esquinas redondeadas: el pixel de cada esquina de la losa es junta.
    edge_u = (du == 1) | (du == SLAB - 1)
    edge_v = (dv == 1) | (dv == SLAB - 1)
    index[edge_u & edge_v] = C_JOINT
    return grid, index


# ---------------------------------------------------------------------- madera

# 8 filas de tablas a lo largo de u con dos cortes a 32 celdas: la tabla que cruza el borde de la
# casilla es igual en las 4 variantes y la de adentro cambia.
W = pal.WOOD_FLOOR
(W_SEAM, W_GRAIN, W_DARK, W_MID, W_BASE, W_LIGHT, W_SHINE) = range(7)
WOOD = pal.palette([
    W[pal.RIGHT],             # junta y cortes (783a13)
    "904f25",                 # veta oscura
    W[pal.LEFT],              # tabla oscura (9d6035)
    W[W.index("base2")],      # tabla (a5663a)
    W[pal.BASE],              # tabla (ad6d40)
    W[pal.LIGHT],             # tabla clara (b67647)
    "c0814f",                 # moteado claro
], name="wood")
PLANK = 8           # celdas de eje de ancho (8 por casilla)
INNER_LENGTH = 32   # distancia entre los dos cortes de una fila
WOOD_CUTS = (3, 19, 11, 27, 7, 23, 15, 31)  # primer corte de cada fila; escalonados
WOOD_MOTTLE = 0.16  # parte de los dominós de una tabla con el tono vecino
# Tablas: (tono, semilla, veta (a, b, largo) o None); a a lo largo (0 … 30), b a lo ancho (0 … 6).
# Las primeras 8 son las de adentro; las 8 siguientes, las que cruzan.
WOOD_KITS = (
    (W_BASE, 11, (5, 3, 6)), (W_MID, 12, None), (W_LIGHT, 13, (16, 2, 5)), (W_BASE, 14, None),
    (W_DARK, 15, (9, 4, 4)), (W_LIGHT, 16, None), (W_MID, 17, (20, 3, 6)), (W_BASE, 18, (3, 1, 4)),
    (W_MID, 21, None), (W_BASE, 22, (12, 4, 5)), (W_LIGHT, 23, None), (W_MID, 24, (6, 2, 6)),
    (W_BASE, 25, None), (W_LIGHT, 26, (18, 5, 4)), (W_BASE, 27, None), (W_MID, 28, (10, 3, 5)),
)
# Por variante: (tabla de adentro, al revés) de cada fila. La última toca el borde y es igual en las 4.
WOOD_LAYOUTS = (
    ((0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0), (7, 0)),
    ((5, 1), (6, 0), (0, 1), (4, 0), (2, 1), (3, 1), (1, 0), (7, 0)),
    ((3, 1), (4, 1), (6, 0), (1, 0), (5, 1), (0, 0), (2, 1), (7, 0)),
    ((6, 0), (2, 1), (5, 0), (0, 1), (1, 1), (3, 0), (4, 0), (7, 0)),
)
MOTTLE_UP = {W_DARK: W_MID, W_MID: W_BASE, W_BASE: W_LIGHT, W_LIGHT: W_SHINE}
MOTTLE_DOWN = {W_DARK: W_GRAIN, W_MID: W_DARK, W_BASE: W_MID, W_LIGHT: W_BASE}


def paint_plank(index, area, a, b, kit):
    """Pinta una tabla: tono, moteado (mitad un tono arriba, mitad uno abajo) y veta."""
    tone, seed, grain = WOOD_KITS[kit]
    index[area] = tone
    chance = pattern.hash2(a, b, seed)
    index[area & (chance < WOOD_MOTTLE / 2)] = MOTTLE_UP[tone]
    index[area & (chance >= WOOD_MOTTLE / 2) & (chance < WOOD_MOTTLE)] = MOTTLE_DOWN[tone]
    if grain:
        a0, b0, length = grain
        index[area & (a >= a0) & (a < a0 + length) & (b == b0)] = W_GRAIN


def wood_tile(variant):
    """Índices de paleta de una casilla de tablas."""
    grid = iso.tile_grid()
    row = grid.iv // PLANK
    across = np.mod(grid.iv, PLANK)
    index = np.full(grid.mask.shape, W_BASE, dtype=np.int16)
    body = across >= 1
    b = across - 1
    for number in range(8):
        cut = WOOD_CUTS[number]
        in_row = grid.mask & (row == number) & body
        along = np.mod(grid.iu - cut, 64)       # 0 = el corte; 1 … 31 la tabla de adentro
        inner = in_row & (along >= 1) & (along < INNER_LENGTH)
        cross = in_row & (along > INNER_LENGTH)
        paint_plank(index, cross, along - INNER_LENGTH - 1, b, 8 + number)
        kit, reverse = WOOD_LAYOUTS[variant][number]
        a = along - 1
        if reverse:
            a = INNER_LENGTH - 2 - a
        paint_plank(index, inner, a, b, kit)
        index[in_row & ((along == 0) | (along == INNER_LENGTH))] = W_SEAM
    index[grid.mask & (across == 0)] = W_SEAM
    return grid, index


# ---------------------------------------------------------------------- ruido de dominós

# Alfombra, pasto, concreto, grava, acera y calle: cada dominó (2 px) toma un tono por azar más manchas
# suaves, con cantidad EXACTA de cada tono. El anillo del borde es común a las 4 variantes. Encima van
# formas chicas (matas, piedritas), las mismas en las 4 pero en otro lugar.

BLEND = 10  # celdas de eje desde el borde en que el dibujo propio de la variante entra de a poco
SHAPE_MARGIN = 4  # celdas de eje que las formas dejan libres junto al borde


class Noise(object):
    """Receta de un piso de ruido.

    shares   parte de cada tono de ruido (índices 0 … n−1 de la paleta), menos el último, que es el resto
    clump    peso de las manchas suaves frente al azar de cada dominó (0 = granos sueltos)
    periods  nudos por casilla de cada capa de manchas y su peso: ((periodo, peso), …)
    seed     semilla base (la variante suma la suya)
    shapes   formas chicas por casilla (de shape_pixels), en el orden en que se colocan
    spacing  separación mínima entre formas (px de alto; a lo ancho cuenta la mitad)
    cover    tono de ruido al que se le descuentan los pixeles que tapan las formas
    fixed    función grid -> arreglo de índices de paleta (−1 = libre): lo que es igual en las 4
             variantes y no es ruido (juntas, la línea de la calle)
    ring     otra receta de la que salen el anillo del borde y el campo común: así varias familias
             (pasto liso, manchado, tupido…) empalman entre sí y se pueden mezclar casilla a casilla
    blend    celdas desde el borde en que se pasa del campo común al de la variante (BLEND si no
             se da); angosto = menos franja igual en todas las casillas, que se ve como retícula
    """

    def __init__(self, shares, clump, periods, seed, shapes=(), spacing=8.0, cover=None, fixed=None, ring=None,
                 blend=None):
        self.shares = shares
        self.clump = clump
        self.periods = periods
        self.seed = seed
        self.shapes = shapes
        self.spacing = spacing
        self.cover = len(shares) - 1 if cover is None else cover
        self.fixed = fixed
        self.ring = ring
        self.blend = BLEND if blend is None else blend

    def value(self, grid, seed):
        soft = sum(pattern.value_noise(grid.u, grid.v, period=period, seed=seed + period) * weight
                   for period, weight in self.periods)
        return pattern.hash2(grid.iu, grid.iv, seed) * (1.0 - self.clump) + soft * self.clump


def blended(grid, shared, own, width=BLEND):
    """Campo común en el borde que pasa al de la variante hacia adentro."""
    distance = np.minimum(np.minimum(grid.iu, CELL - 1 - grid.iu), np.minimum(grid.iv, CELL - 1 - grid.iv))
    weight = np.clip(distance / float(width), 0.0, 1.0)
    weight = weight * weight * (3.0 - 2.0 * weight)
    return shared * (1.0 - weight) + own * weight


def shape_pixels(rows, colors):
    """Dibujo en filas de letras -> [(dx, dy, color)]. dy = 0 la fila de abajo, negativo hacia arriba;
    '.' = vacío. Las filas van de a pares desde la columna 0 (dominós enteros)."""
    pixels = []
    for row, line in enumerate(rows):
        for column, letter in enumerate(line):
            if letter != ".":
                pixels.append((column, row - (len(rows) - 1), colors[letter]))
    return tuple(pixels)


def place_shapes(grid, free, shapes, spacing, seed, name):
    """Pone cada forma al azar fijo dentro de `free`, a spacing de las otras y alineada a dominós.
    Devuelve [(x, y, color)]."""
    order = pattern.hash2(grid.x, grid.y, seed)
    pair = np.zeros(grid.mask.shape, dtype=bool)  # el pixel y el de su derecha son un dominó
    pair[:, :-1] = grid.domino[:, :-1] == grid.domino[:, 1:]

    def fits(x, y, shape):
        for dx, dy, _color in shape:
            qx, qy = x + dx, y + dy
            if not (0 <= qy < grid.height and 0 <= qx < grid.width - 1 and free[qy, qx]):
                return False
            if dx % 2 == 0 and not pair[qy, qx]:
                return False
        return True

    placed, chosen, left = [], [], list(shapes)
    ys, xs = np.nonzero(free)
    for position in np.argsort(order[ys, xs], kind="stable"):
        if not left:
            break
        x, y = int(xs[position]), int(ys[position])
        if any(((x - cx) / 2.0) ** 2 + (y - cy) ** 2 < spacing ** 2 for cx, cy in chosen):
            continue
        if fits(x, y, left[0]):
            chosen.append((x, y))
            placed += [(x + dx, y + dy, color) for dx, dy, color in left.pop(0)]
    if left:
        raise ValueError("%s: no hubo lugar para %d formas" % (name, len(left)))
    return placed


def noise_tile(recipe, variant, name):
    """Índices de paleta de una casilla de ruido según la receta."""
    grid = iso.tile_grid()
    fixed = recipe.fixed(grid) if recipe.fixed else np.full(grid.mask.shape, -1, dtype=np.int16)
    free = grid.mask & (fixed < 0)
    ring = free & ((grid.iu == 0) | (grid.iv == 0) | (grid.iu == CELL - 1) | (grid.iv == CELL - 1))
    seed = recipe.seed + 53 * (variant + 1)
    margin = free & (grid.iu >= SHAPE_MARGIN) & (grid.iv >= SHAPE_MARGIN) & \
        (grid.iu < CELL - SHAPE_MARGIN) & (grid.iv < CELL - SHAPE_MARGIN)
    shapes = place_shapes(grid, margin, recipe.shapes, recipe.spacing, seed, name) if recipe.shapes else []
    blocked = np.zeros(grid.mask.shape, dtype=bool)
    for x, y, _color in shapes:
        blocked[y, x] = True
    # Cantidades en dominós.
    total = int(free.sum()) // 2
    counts = [int(round(total * share)) for share in recipe.shares]
    counts.append(total - sum(counts))
    common = recipe.ring or recipe
    ring_counts = [int(round(total * share)) for share in common.shares]
    common_field = common.value(grid, common.seed)
    shared = pattern.exact_levels(common_field, free, ring_counts, group=grid.domino)
    index = np.where(fixed >= 0, fixed, np.where(ring, shared, 0)).astype(np.int16)
    left = [count - int((shared[ring] == level).sum()) // 2 for level, count in enumerate(counts)]
    left[recipe.cover] -= len(shapes) // 2
    if min(left) < 0:
        raise ValueError("%s: el anillo común usa más de un tono que la receta (%s)" % (name, left))
    inside = free & ~ring & ~blocked
    value = blended(grid, common_field, recipe.value(grid, seed), recipe.blend)
    split = pattern.exact_levels(value, inside, left[:-1], group=grid.domino)
    index[inside] = split[inside]
    for x, y, color in shapes:
        index[y, x] = color
    return grid, index


def noise_material(recipe, prefix):
    """Función variante -> (grid, índices) para MATERIALS."""
    return lambda variant: noise_tile(recipe, variant, "%s_%d" % (prefix, variant))


# ---------------------------------------------------------------------- alfombra

# 4 lilas cercanos algo agrupados, sin juntas ni brillo.
CARPET = pal.palette(["777a9a", "7d80a0", "8688a4", "8e8fa8"], name="carpet")
CARPET_RECIPE = Noise((0.24, 0.26, 0.38), 0.55, ((8, 1.0),), 5100)


# ---------------------------------------------------------------------- pasto

GRASS_BASE, GRASS_SECOND = CONSTRUCTION["terrain"]["colors"]  # 5f8a4c, 567e44 (dibujo provisional)
L = pal.LEAVES


def grass_palette(factor, name):
    """Verdes de la rampa de hojas × factor de brillo (1 el solar, 0.85 afuera)."""
    colors = [
        pal.mix(L[pal.RIGHT], L[pal.LEFT], 0.75),  # mancha oscura
        pal.mix(L[pal.LEFT], L[pal.SOFT], 0.45),   # borde de la mancha
        L[pal.SOFT],                               # pasto (81a73a)
        pal.mix(L[pal.SOFT], L[pal.BASE], 0.4),    # mancha clara
        L[pal.RIGHT],                              # pie de las matas y trazos (4c6029)
        L[pal.BASE],                               # brizna (9ecc42)
        L[pal.LIGHT],                              # punta de la brizna (cbf166)
    ]
    if factor != 1.0:
        colors = [pal.mix("000000", color, factor) for color in colors]
    return pal.palette(colors, name=name)


(G_DARK, G_MID, G_BASE, G_LIGHT, G_DEEP, G_BLADE, G_TIP) = range(7)
GRASS = grass_palette(1.0, "grass")
OUTSIDE = grass_palette(0.85, "outside")  # pasto fuera del solar: 15 % más oscuro
BLADE_COLORS = {"t": G_TIP, "b": G_BLADE, "d": G_DEEP}
# Matas: briznas juntas, más claras arriba, con el pie oscuro.
TUFT_TALL = shape_pixels(("..tt....",
                          "..bb..tt",
                          "ttbb..bb",
                          "bbbbttbb",
                          "bbbbbbbb",
                          "dddddddd"), BLADE_COLORS)
TUFT_FAN = shape_pixels(("tt....tt",
                         "bb..ttbb",
                         "bbttbbbb",
                         "bbbbbb..",
                         "dddddd.."), BLADE_COLORS)
TUFT_BIG = shape_pixels(("tt..",
                         "bbtt",
                         "bbbb",
                         "dddd"), BLADE_COLORS)
TUFT_SMALL = shape_pixels(("tt",
                           "bb",
                           "dd"), BLADE_COLORS)
# Matitas oscuras de pasto tupido (briznas en ^ y en zigzag), sin punta clara.
STROKE_A = shape_pixels(("..dd..",
                         "dd..dd"), BLADE_COLORS)
STROKE_B = shape_pixels(("dd..dd..",
                         "..dd..dd"), BLADE_COLORS)
# Manchas más chicas que la casilla (5 y 9 nudos) para que no se vea la retícula.
GRASS_PERIODS = ((5, 0.6), (9, 0.4))
GRASS_CLUMP = 1.0  # solo las manchas: bordes nítidos, sin grano suelto
# Familias de pasto: comparten el anillo del borde (GRASS_RING), así cualquier casilla empalma.
# (nombre, partes de mancha oscura, su borde y pasto (el resto claro), formas, separación, semilla)
GRASS_BLEND = 6  # franja en que la mancha de cada casilla se funde con el borde común
GRASS_RING = Noise((0.06, 0.06, 0.70), GRASS_CLUMP, GRASS_PERIODS, 6000)
GRASS_FAMILIES = (
    ("plain", (0.03, 0.05, 0.80), (TUFT_BIG, TUFT_SMALL, TUFT_SMALL, STROKE_A, STROKE_B), 12.0, 6100),
    ("patchy", (0.17, 0.09, 0.60), (TUFT_TALL, TUFT_BIG, TUFT_SMALL, STROKE_B, STROKE_A, STROKE_A), 9.0, 6200),
    ("lush", (0.10, 0.10, 0.62), (TUFT_TALL, TUFT_TALL, TUFT_FAN, TUFT_FAN, TUFT_BIG, TUFT_BIG, TUFT_BIG,
                                  TUFT_SMALL, TUFT_SMALL, TUFT_SMALL, STROKE_A, STROKE_B, STROKE_A, STROKE_B), 6.5, 6300),
    ("sunny", (0.02, 0.06, 0.52), (TUFT_SMALL, TUFT_SMALL, STROKE_A), 14.0, 6400),
)
# Parte del mapa de cada familia en la vista de prueba.
GRASS_FAMILY_SHARES = {"plain": 0.40, "patchy": 0.22, "lush": 0.23, "sunny": 0.15}


def grass_recipes(seed_offset):
    return [(name, Noise(shares, GRASS_CLUMP, GRASS_PERIODS, seed + seed_offset, shapes, spacing, G_BASE,
                         ring=GRASS_RING, blend=GRASS_BLEND))
            for name, shares, shapes, spacing, seed in GRASS_FAMILIES]


GRASS_RECIPES = grass_recipes(0)
OUTSIDE_RECIPES = grass_recipes(500)


# ---------------------------------------------------------------------- concreto (sin piso)

# 4 grises cálidos de poco contraste, algún poro y una grieta fina en 2:1.
(B_D, B_M, B_B, B_L, B_PORE) = range(5)
BARE = pal.palette(["807e7a", "868480", "8c8a86", "92908c", "6f6d69"], name="bare")
PORE = shape_pixels(("pp",), {"p": B_PORE})
CRACK = shape_pixels(("pp....",
                      "..pp..",
                      "....pp"), {"p": B_PORE})
BARE_RECIPE = Noise((0.2, 0.3, 0.32), 0.6, ((4, 0.7), (8, 0.3)), 7000, (CRACK, PORE, PORE, PORE, PORE), 7.0, B_B)


# ---------------------------------------------------------------------- grava (camino)

# Grava de grises cálidos con piedras de 2 a 6 px: cara clara, lado oscuro y contorno-sombra abajo.
(P_D, P_M, P_B, P_L, P_OUTLINE, P_SIDE, P_STONE, P_TOP) = range(8)
PATH = pal.palette(["988c76", "a59a84", "afa38c", "bcb19b", "6e6453", "a89d87", "c8bea8", "e0d8c4"],
                   name="path")
STONE_COLORS = {"t": P_TOP, "s": P_STONE, "m": P_SIDE, "o": P_OUTLINE}
STONE_LARGE = shape_pixels(("..tttt..",
                            "ttttssmm",
                            "ssssssmm",
                            "ssssmmmm",
                            "..oooooo"), STONE_COLORS)
STONE_MID = shape_pixels(("tttt..",
                          "ttssmm",
                          "ssmmmm",
                          "oooooo"), STONE_COLORS)
STONE_FLAT = shape_pixels(("ttssss",
                           "ssssmm",
                           "..oooo"), STONE_COLORS)
STONE_SMALL = shape_pixels(("tsmm",
                            "oooo"), STONE_COLORS)
STONE_TINY = shape_pixels(("ts",
                           "oo"), STONE_COLORS)
PATH_SHAPES = (STONE_LARGE, STONE_LARGE, STONE_LARGE, STONE_MID, STONE_MID, STONE_MID, STONE_MID, STONE_FLAT,
               STONE_FLAT, STONE_FLAT, STONE_FLAT, STONE_SMALL, STONE_SMALL, STONE_SMALL, STONE_SMALL, STONE_TINY,
               STONE_TINY, STONE_TINY, STONE_TINY, STONE_TINY)
PATH_RECIPE = Noise((0.2, 0.3, 0.3), 0.3, ((6, 1.0),), 7500, PATH_SHAPES, 5.0, P_B)


# ---------------------------------------------------------------------- acera

# Una losa por casilla: junta de 1 celda por lado (2 px entre casillas), bisel y gris claro moteado.
(S_D, S_M, S_B, S_L, S_JOINT, S_SHADE, S_LIGHT) = range(7)
SIDEWALK = pal.palette(["9e9d97", "a3a29c", "a8a7a1", "adaca6", "7d7c77", "93928c", "bfbeb8"], name="sidewalk")


def sidewalk_fixed(grid):
    fixed = np.full(grid.mask.shape, -1, dtype=np.int16)
    fixed[(grid.iv == 1) | (grid.iu == 1)] = S_LIGHT
    fixed[(grid.iv == CELL - 2) | (grid.iu == CELL - 2)] = S_SHADE
    fixed[(grid.iu == 0) | (grid.iv == 0) | (grid.iu == CELL - 1) | (grid.iv == CELL - 1)] = S_JOINT
    return np.where(grid.mask, fixed, -1)


SIDEWALK_RECIPE = Noise((0.2, 0.3, 0.32), 0.5, ((4, 1.0),), 8000, (), fixed=sidewalk_fixed)


# ---------------------------------------------------------------------- calle

# Asfalto de granos sueltos en 3 tonos; la línea es una franja amarilla de 4 celdas a lo largo de
# un eje (x = u, y = v).
(R_D, R_M, R_B, R_L, R_LINE, R_WORN) = range(6)
ROAD = pal.palette(["3f4248", "44474d", "494c52", "55585e", MAP["road_line_color"], "c4b56a"], name="road")
ROAD_RECIPE = Noise((0.28, 0.34, 0.30), 0.25, ((8, 1.0),), 9000)
LINE_WIDTH = 4


def road_line_fixed(axis):
    def fixed(grid):
        across = grid.iv if axis == "x" else grid.iu
        along = grid.iu if axis == "x" else grid.iv
        band = (across >= CELL // 2 - LINE_WIDTH // 2) & (across < CELL // 2 + LINE_WIDTH // 2)
        worn = pattern.hash2(along, across, 9500) < 0.12
        out = np.where(band, np.where(worn, R_WORN, R_LINE), -1).astype(np.int16)
        return np.where(grid.mask, out, -1)
    return fixed


ROAD_LINE_X_RECIPE = Noise((0.28, 0.34, 0.30), 0.25, ((8, 1.0),), 9000, fixed=road_line_fixed("x"))
ROAD_LINE_Y_RECIPE = Noise((0.28, 0.34, 0.30), 0.25, ((8, 1.0),), 9000, fixed=road_line_fixed("y"))


# ---------------------------------------------------------------------- generar

MATERIALS = [
    # (nombre, función, paleta, material, colores base de data/construction.json o data/map.json)
    ("floor_ceramic", ceramic_tile, CERAMIC, "ceramic", CONSTRUCTION["floors"]["ceramic"]["colors"]),
    ("floor_wood", wood_tile, WOOD, "wood", CONSTRUCTION["floors"]["wood"]["colors"]),
    ("floor_carpet", noise_material(CARPET_RECIPE, "floor_carpet"), CARPET, "carpet",
     CONSTRUCTION["floors"]["carpet"]["colors"]),
    ("floor_bare", noise_material(BARE_RECIPE, "floor_bare"), BARE, "bare", CONSTRUCTION["bare_floor"]["colors"]),
] + [
    ("ground_grass_%s" % family, noise_material(recipe, "ground_grass_%s" % family), GRASS, "grass",
     [GRASS_BASE, GRASS_SECOND]) for family, recipe in GRASS_RECIPES
] + [
    ("ground_outside_%s" % family, noise_material(recipe, "ground_outside_%s" % family), OUTSIDE, "outside",
     MAP["styles"]["outside"]) for family, recipe in OUTSIDE_RECIPES
] + [
    ("ground_path", noise_material(PATH_RECIPE, "ground_path"), PATH, "path", MAP["styles"]["path"]),
    ("ground_sidewalk", noise_material(SIDEWALK_RECIPE, "ground_sidewalk"), SIDEWALK, "sidewalk",
     MAP["styles"]["sidewalk"]),
    ("ground_road", noise_material(ROAD_RECIPE, "ground_road"), ROAD, "road", MAP["styles"]["road"]),
    ("ground_road_line_x", noise_material(ROAD_LINE_X_RECIPE, "ground_road_line_x"), ROAD, "road_line",
     MAP["styles"]["road"]),
    ("ground_road_line_y", noise_material(ROAD_LINE_Y_RECIPE, "ground_road_line_y"), ROAD, "road_line",
     MAP["styles"]["road"]),
]


def build_material(out_dir, name, tile, colors, material, base_colors):
    """Dibuja las 4 variantes, comprueba que tengan los mismos pixeles por color y las guarda."""
    tiles = [tile(variant) for variant in range(VARIANTS)]
    check_same_counts(name, [color_counts(index, grid.mask, len(colors)) for grid, index in tiles])
    files = []
    images = []
    for variant, (grid, index) in enumerate(tiles):
        image = grid.image(index, colors)
        images.append(image)
        files.append(iso.save(image, out_dir, "%s_%d" % (name, variant), kind="floor", material=material,
                              variant=variant, base_colors=list(base_colors), anchor=list(ANCHOR)))
    return files, images, tiles


def fill_families(scene, images, prefix, seed, area=None):
    """Llena casillas con familias de pasto por zonas (ruido suave, GRASS_FAMILY_SHARES) y variante
    al azar fijo por casilla."""
    families = [name for name, _shares, _shapes, _spacing, _seed in GRASS_FAMILIES]
    x0, y0, x1, y1 = area if area is not None else (0, 0, scene.cols, scene.rows)
    cells = [(x, y) for y in range(y0, y1) for x in range(x0, x1)]
    xs = np.array([x for x, _y in cells], dtype=float)
    ys = np.array([y for _x, y in cells], dtype=float)
    # Ruido suave sobre todo el mapa (periodo grande, para que no se repita en la vista).
    zone = pattern.value_noise(xs / 32.0, ys / 32.0, period=8, seed=seed) * 0.8 + \
        pattern.hash2(xs.astype(int), ys.astype(int), seed) * 0.2
    limits = np.cumsum([GRASS_FAMILY_SHARES[name] for name in families])
    ranks = np.argsort(np.argsort(zone)) / float(len(cells))
    rng = np.random.RandomState(seed)
    for (x, y), rank in zip(cells, ranks):
        family = families[min(int(np.searchsorted(limits, rank, side="right")), len(families) - 1)]
        tiles = images["%s_%s" % (prefix, family)]
        scene.floor(tiles[rng.randint(len(tiles))], x, y)


def review_sheets(out_dir, images):
    """Hojas de revisión en _sheets/: mosaicos de cada material, la hoja del grupo y un solar de prueba."""
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    for name, tiles in images.items():
        short = name.split("_", 1)[1]
        sheet.tile_mosaic(tiles, 5, 5, seed=3, scale=3).save(os.path.join(folder, "floors_%s_x3.png" % short))
        sheet.tile_mosaic(tiles, 12, 12, seed=5, scale=1).save(os.path.join(folder, "floors_%s_x1.png" % short))
    # Solar de prueba con todos los suelos.
    lot = sheet.Scene(14, 14, top=16, margin=8)
    fill_families(lot, images, "ground_outside", 10)
    fill_families(lot, images, "ground_grass", 11, area=(1, 1, 13, 9))
    lot.fill_floor(images["floor_ceramic"], seed=12, area=(3, 2, 9, 4))
    lot.fill_floor(images["floor_wood"], seed=13, area=(3, 4, 6, 7))
    lot.fill_floor(images["floor_carpet"], seed=14, area=(6, 4, 9, 7))
    lot.fill_floor(images["floor_bare"], seed=15, area=(9, 2, 11, 7))
    lot.fill_floor(images["ground_path"], seed=16, area=(6, 7, 8, 9))
    lot.fill_floor(images["ground_sidewalk"], seed=17, area=(0, 9, 14, 10))
    lot.fill_floor(images["ground_road"], seed=18, area=(0, 10, 14, 14))
    for x in range(0, 14, 3):
        lot.fill_floor(images["ground_road_line_x"], seed=19 + x, area=(x, 12, min(x + 2, 14), 13))
    items = []
    for name, tiles in images.items():
        items += [("%s_%d" % (name, i), image.crop((0, 64, 128, 128))) for i, image in enumerate(tiles)]
    parts = [sheet.contact_sheet(items, columns=4, scale=2), lot.render(2)]
    page = Image.new("RGBA", (max(part.size[0] for part in parts), sum(part.size[1] for part in parts)),
                     tuple(sheet.BACKGROUND) + (255,))
    top = 0
    for part in parts:
        page.paste(part.convert("RGBA"), ((page.size[0] - part.size[0]) // 2, top))
        top += part.size[1]
    page.save(os.path.join(folder, "floors.png"))
    # Pasto solo: una familia contra las cuatro mezcladas, 16×16 casillas a ×1.
    for label, prefix in (("one", "ground_grass_patchy"), ("mixed", None)):
        field = sheet.Scene(16, 16, top=8, margin=8)
        if prefix:
            field.fill_floor(images[prefix], seed=21)
        else:
            fill_families(field, images, "ground_grass", 21)
        field.render(1).save(os.path.join(folder, "grass_%s_x1.png" % label))


def check_shared_ring(images, prefix):
    """Todas las familias de pasto deben tener el mismo anillo del borde (si no, no empalman)."""
    grid = iso.tile_grid()
    ring = grid.mask & ((grid.iu == 0) | (grid.iv == 0) | (grid.iu == CELL - 1) | (grid.iv == CELL - 1))
    rings = [np.array(image)[ring] for name, tiles in images.items() if name.startswith(prefix) for image in tiles]
    if not all(np.array_equal(rings[0], other) for other in rings[1:]):
        raise ValueError("%s: las familias no comparten el anillo del borde" % prefix)


def build(out_dir):
    files = []
    images = {}
    for name, tile, colors, material, base_colors in MATERIALS:
        more, images[name], tiles = build_material(out_dir, name, tile, colors, material, base_colors)
        files += more
        print("  %s: repetición %.3f" % (name, repetition(tiles, colors)))
    check_shared_ring(images, "ground_grass_")
    check_shared_ring(images, "ground_outside_")
    review_sheets(out_dir, images)
    return files
