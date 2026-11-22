# Pisos de adentro (docs/sprites_128.md, sección 5; estilo de tools/sprites/STYLE.md).
#
#   floor_ceramic_0..3   cerámica blanca: 2×2 losas en damero de dos blancos, junta gris de 1 px,
#                        bisel claro arriba y gris abajo, esquinas redondeadas y reflejo en diagonal
#   floor_wood_0..3      8 tablas angostas de madera naranja con cortes escalonados, moteado y vetas
#   floor_carpet_0..3    alfombra lila de pared a pared: ruido de dominós en 4 tonos, algo agrupado
#   floor_bare_0..3      concreto (sin piso): grises cálidos de poco contraste, poros y una grieta fina
#
# El terreno de afuera (pasto, camino, acera y calle) se dibuja con Moana en tools/sprites/art/ground/.
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


# ---------------------------------------------------------------------- concreto (sin piso)

# 4 grises cálidos de poco contraste, algún poro y una grieta fina en 2:1.
(B_D, B_M, B_B, B_L, B_PORE) = range(5)
BARE = pal.palette(["807e7a", "868480", "8c8a86", "92908c", "6f6d69"], name="bare")
PORE = shape_pixels(("pp",), {"p": B_PORE})
CRACK = shape_pixels(("pp....",
                      "..pp..",
                      "....pp"), {"p": B_PORE})
BARE_RECIPE = Noise((0.2, 0.3, 0.32), 0.6, ((4, 0.7), (8, 0.3)), 7000, (CRACK, PORE, PORE, PORE, PORE), 7.0, B_B)


# ---------------------------------------------------------------------- generar

MATERIALS = [
    # (nombre, función, paleta, material, colores base de data/construction.json o data/map.json)
    ("floor_ceramic", ceramic_tile, CERAMIC, "ceramic", CONSTRUCTION["floors"]["ceramic"]["colors"]),
    ("floor_wood", wood_tile, WOOD, "wood", CONSTRUCTION["floors"]["wood"]["colors"]),
    ("floor_carpet", noise_material(CARPET_RECIPE, "floor_carpet"), CARPET, "carpet",
     CONSTRUCTION["floors"]["carpet"]["colors"]),
    ("floor_bare", noise_material(BARE_RECIPE, "floor_bare"), BARE, "bare", CONSTRUCTION["bare_floor"]["colors"]),

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


def review_sheets(out_dir, images):
    """Hojas de revisión en _sheets/: mosaicos de cada material, la hoja del grupo y un solar de prueba."""
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    for name, tiles in images.items():
        short = name.split("_", 1)[1]
        sheet.tile_mosaic(tiles, 5, 5, seed=3, scale=3).save(os.path.join(folder, "floors_%s_x3.png" % short))
        sheet.tile_mosaic(tiles, 12, 12, seed=5, scale=1).save(os.path.join(folder, "floors_%s_x1.png" % short))
    # Habitación de prueba con los cuatro pisos.
    lot = sheet.Scene(8, 6, top=16, margin=8)
    lot.fill_floor(images["floor_ceramic"], seed=12, area=(0, 0, 4, 3))
    lot.fill_floor(images["floor_wood"], seed=13, area=(4, 0, 8, 3))
    lot.fill_floor(images["floor_carpet"], seed=14, area=(0, 3, 4, 6))
    lot.fill_floor(images["floor_bare"], seed=15, area=(4, 3, 8, 6))
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


def build(out_dir):
    files = []
    images = {}
    for name, tile, colors, material, base_colors in MATERIALS:
        more, images[name], tiles = build_material(out_dir, name, tile, colors, material, base_colors)
        files += more
        print("  %s: repetición %.3f" % (name, repetition(tiles, colors)))
    review_sheets(out_dir, images)
    return files
