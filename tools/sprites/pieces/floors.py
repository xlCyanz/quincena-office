# Pisos y terreno (docs/sprites_128.md, sección 5; estilo de tools/sprites/STYLE.md).
#
#   floor_ceramic_0..3   cerámica blanca: 2×2 losas en damero de dos blancos, junta gris de 1 px,
#                        bisel claro arriba y gris abajo, esquinas redondeadas y reflejo en diagonal
#   floor_wood_0..3      8 tablas angostas de madera naranja con cortes escalonados, moteado y vetas
#   floor_carpet_0..3    alfombra lila de pared a pared: ruido de dominós en 4 tonos, algo agrupado
#   ground_grass_0..3    pasto saturado (rampa de hojas): manchas grandes que cruzan los bordes y matas
#
# Las 4 variantes de cada material comparten el borde y tienen la MISMA cantidad de pixeles de
# cada color (se comprueba al generar): mismo color medio exacto, sin tablero de ajedrez.
# Todo se dibuja en la rejilla isométrica (grid.iu, grid.iv): cada celda es 1 px y un
# rectángulo de ella es un rombo en pantalla, así las líneas salen 2:1.
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
    """Cuánto del dibujo se repite en cada casilla: varianza del promedio de las variantes entre
    la varianza total del brillo. Es la autocorrelación que se espera en un mosaico al azar a un
    paso de casilla: 0.25 con 4 variantes que no se parecen en nada, 1.0 si son iguales."""
    mask = tiles[0][0].mask
    values = np.array([brightness(index, colors)[mask] for _grid, index in tiles])
    mean = values.mean()
    return float(((values.mean(axis=0) - mean) ** 2).mean() / ((values - mean) ** 2).mean())


# ---------------------------------------------------------------------- cerámica

# Cerámica blanca al estilo de los pisos de losas de la referencia: 2×2 losas por casilla, junta
# gris de 1 px (no negra), bisel claro en los cantos de arriba (la luz viene de arriba a la
# izquierda) y oscuro en los de abajo, esquinas redondeadas (el pixel de la esquina es junta) y
# las losas en dos tonos apenas distintos, en damero. Algunas losas llevan el reflejo en diagonal
# (dos franjas, una ancha y una fina); las variantes cambian qué losas lo tienen.
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
# Reflejo: franjas en diagonal (pantalla "/") de la losa, dadas por k = 2·du − dv: (k0, k1, largo
# mínimo y máximo en du). Lo de cada losa va en celdas de su campo (2 … 30).
CERAMIC_GLINTS = {
    "wide": ((14, 19, 6, 24), (24, 25, 10, 26)),
    "thin": ((8, 10, 4, 18),),
    "none": (),
}
# Losas de cada variante (0 arriba, 1 derecha, 2 izquierda, 3 abajo): reflejo de cada una. El
# ancho va siempre en una losa del tono base (0 o 3) y el fino en una del otro tono (1 o 2): así
# las 4 variantes tienen los mismos pixeles por color.
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
    # Biseles: claro arriba (los dos cantos), gris abajo a la izquierda, más oscuro abajo a la derecha.
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

# Tablas angostas de madera naranja (como el piso de tablas de la referencia): 8 filas por casilla
# a lo largo de u, separadas por una línea oscura de 1 px (en pantalla, la escalera 2:1 de trazos
# de 2 px); cada tabla tiene su tono plano con un moteado de dominós del tono vecino y alguna veta
# oscura corta. Cada fila tiene dos cortes a 32 celdas: la tabla que cruza el borde de la casilla
# es igual en las 4 variantes (si no, se cortaría) y la de adentro cambia de tono, moteado y veta.
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
# Tablas: (tono, semilla del moteado, veta (a, b, largo) o None). a a lo largo (0 … 30), b a lo
# ancho del cuerpo (0 … 6). Las primeras 8 son las de adentro; las 8 siguientes, las que cruzan.
WOOD_KITS = (
    (W_BASE, 11, (5, 3, 6)), (W_MID, 12, None), (W_LIGHT, 13, (16, 2, 5)), (W_BASE, 14, None),
    (W_DARK, 15, (9, 4, 4)), (W_LIGHT, 16, None), (W_MID, 17, (20, 3, 6)), (W_BASE, 18, (3, 1, 4)),
    (W_MID, 21, None), (W_BASE, 22, (12, 4, 5)), (W_LIGHT, 23, None), (W_MID, 24, (6, 2, 6)),
    (W_BASE, 25, None), (W_LIGHT, 26, (18, 5, 4)), (W_BASE, 27, None), (W_MID, 28, (10, 3, 5)),
)
# Qué tabla de adentro va en cada fila y si va al revés a lo largo, por variante. La de la última
# fila toca el borde de la casilla (su canto de abajo) y es igual en las 4.
WOOD_LAYOUTS = (
    ((0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0), (7, 0)),
    ((5, 1), (6, 0), (0, 1), (4, 0), (2, 1), (3, 1), (1, 0), (7, 0)),
    ((3, 1), (4, 1), (6, 0), (1, 0), (5, 1), (0, 0), (2, 1), (7, 0)),
    ((6, 0), (2, 1), (5, 0), (0, 1), (1, 1), (3, 0), (4, 0), (7, 0)),
)
MOTTLE_UP = {W_DARK: W_MID, W_MID: W_BASE, W_BASE: W_LIGHT, W_LIGHT: W_SHINE}
MOTTLE_DOWN = {W_DARK: W_GRAIN, W_MID: W_DARK, W_BASE: W_MID, W_LIGHT: W_BASE}


def paint_plank(index, area, a, b, kit):
    """Pinta una tabla: tono, moteado (la mitad un tono arriba y la mitad uno abajo, siempre la
    misma cantidad: la elección va por el azar de la tabla en sus coordenadas a, b) y veta."""
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


# ---------------------------------------------------------------------- alfombra

# Alfombra de pared a pared como el piso lila de la referencia: un ruido de dominós en cuatro
# tonos fríos cercanos, algo agrupado (un ruido suave suma al azar de cada dominó) para que se
# vean mechones y no un gris parejo. Sin juntas ni brillo.
(K_DARK, K_MID, K_BASE, K_LIGHT) = range(4)
CARPET = pal.palette(["777a9a", "7d80a0", "8688a4", "8e8fa8"], name="carpet")
CARPET_SHARES = (0.24, 0.26, 0.38)  # oscuro, medio, base; el resto claro
CARPET_CLUMP = 0.55  # peso del ruido suave frente al azar de cada dominó


BLEND = 10  # celdas de eje desde el borde en que el dibujo propio de la variante entra de a poco


def blended(grid, shared, own):
    """Campo que en el borde es el común (igual en las 4 variantes) y hacia adentro pasa al de la
    variante: así no se nota dónde termina cada casilla."""
    distance = np.minimum(np.minimum(grid.iu, CELL - 1 - grid.iu), np.minimum(grid.iv, CELL - 1 - grid.iv))
    weight = np.clip(distance / float(BLEND), 0.0, 1.0)
    weight = weight * weight * (3.0 - 2.0 * weight)
    return shared * (1.0 - weight) + own * weight


def domino_counts(grid, shares):
    """Cuántos dominós (2 px) de cada tono: shares para los primeros, el resto para el último."""
    total = int(grid.mask.sum()) // 2
    counts = [int(round(total * share)) for share in shares]
    return counts + [total - sum(counts)]


def carpet_value(grid, seed):
    """Azar de cada dominó más un ruido suave periódico (mechones)."""
    return pattern.hash2(grid.iu, grid.iv, seed) * (1.0 - CARPET_CLUMP) + \
        pattern.value_noise(grid.u, grid.v, period=8, seed=seed) * CARPET_CLUMP


def carpet_tile(variant):
    """Índices de paleta de una casilla de alfombra. El anillo del borde sale de un azar común a
    las 4 variantes (si no, se cortaría); adentro, del de la variante, con lo que falta de cada tono."""
    grid = iso.tile_grid()
    counts = domino_counts(grid, CARPET_SHARES)
    shared = pattern.exact_levels(carpet_value(grid, 5100), grid.mask, counts[:-1], group=grid.domino)
    ring = grid.mask & ((grid.iu == 0) | (grid.iv == 0) | (grid.iu == CELL - 1) | (grid.iv == CELL - 1))
    inside = grid.mask & ~ring
    index = np.where(ring, shared, 0).astype(np.int16)
    left = [count - int((shared[ring] == level).sum()) // 2 for level, count in enumerate(counts)]
    value = blended(grid, carpet_value(grid, 5100), carpet_value(grid, 5200 + 37 * variant))
    split = pattern.exact_levels(value, inside, left[:-1], group=grid.domino)
    index[inside] = split[inside]
    return grid, index


# ---------------------------------------------------------------------- pasto

GRASS_BASE, GRASS_SECOND = CONSTRUCTION["terrain"]["colors"]  # 5f8a4c, 567e44 (dibujo provisional)
# Pasto con el mismo método que la alfombra (ruido de dominós en tonos cercanos, agrupado en
# manchas suaves) con los verdes de la rampa de hojas de STYLE.md, y unas pocas matas encima.
L = pal.LEAVES
(G_DARK, G_MID, G_BASE, G_LIGHT, G_DEEP, G_BLADE, G_TIP) = range(7)
GRASS = pal.palette([
    pal.mix(L[pal.LEFT], L[pal.SOFT], 0.35),   # mancha oscura
    pal.mix(L[pal.LEFT], L[pal.SOFT], 0.7),    # pasto oscuro
    L[pal.SOFT],                               # pasto (81a73a)
    pal.mix(L[pal.SOFT], L[pal.BASE], 0.3),    # pasto claro
    L[pal.RIGHT],                              # pie de las matas (4c6029)
    L[pal.BASE],                               # brizna (9ecc42)
    L[pal.LIGHT],                              # punta de la brizna (cbf166)
], name="grass")
GRASS_SHARES = (0.20, 0.30, 0.36)  # oscuro, pasto oscuro, pasto; el resto claro
GRASS_CLUMP = 0.7   # peso de las manchas suaves frente al azar de cada dominó
GRASS_PERIODS = (3, 6)  # nudos por casilla de las dos capas de manchas


def shape_pixels(rows, colors):
    """Convierte un dibujo en filas de letras en una lista (dx, dy, color). El pie es la fila de
    abajo (dy = 0); dy negativo = hacia arriba. '.' = vacío."""
    pixels = []
    for row, line in enumerate(rows):
        for column, letter in enumerate(line):
            if letter != ".":
                pixels.append((column, row - (len(rows) - 1), colors[letter]))
    return tuple(pixels)


BLADE_COLORS = {"t": G_TIP, "b": G_BLADE, "d": G_DEEP}
# Matas: briznas juntas, más claras arriba, con el pie oscuro (pares de 2 px, sin sueltos).
TUFT_BIG = shape_pixels(("tt..",
                         "bbtt",
                         "bbbb",
                         "dddd"), BLADE_COLORS)
TUFT_SMALL = shape_pixels(("tt",
                           "bb",
                           "dd"), BLADE_COLORS)
GRASS_TUFTS = (TUFT_BIG, TUFT_SMALL, TUFT_SMALL)  # matas por casilla (las mismas en las 4 variantes)
TUFT_SPACING = 14.0   # separación mínima entre matas (px de alto; a lo ancho, el doble)
TUFT_MARGIN = 4       # celdas de eje que las matas dejan libres junto al borde


def grass_value(grid, seed):
    """Azar de cada dominó más dos capas de manchas suaves periódicas."""
    soft = sum(pattern.value_noise(grid.u, grid.v, period=period, seed=seed + period) * weight
               for period, weight in zip(GRASS_PERIODS, (0.65, 0.35)))
    return pattern.hash2(grid.iu, grid.iv, seed) * (1.0 - GRASS_CLUMP) + soft * GRASS_CLUMP


def grass_tile(variant):
    """Índices de paleta de una casilla de pasto. El anillo del borde es igual en las 4 variantes;
    adentro van las manchas y las matas de la variante."""
    grid = iso.tile_grid()
    name = "ground_grass_%d" % variant
    seed = 6100 + 53 * variant
    ring = grid.mask & ((grid.iu == 0) | (grid.iv == 0) | (grid.iu == CELL - 1) | (grid.iv == CELL - 1))
    # Matas: el pie en un pixel par (empieza un dominó) bien adentro de la casilla.
    margin = grid.mask & (grid.iu >= TUFT_MARGIN) & (grid.iv >= TUFT_MARGIN) & \
        (grid.iu < CELL - TUFT_MARGIN) & (grid.iv < CELL - TUFT_MARGIN)
    order = pattern.hash2(grid.x, grid.y, seed)
    pair = np.zeros(grid.mask.shape, dtype=bool)  # el pixel y el de su derecha son un dominó
    pair[:, :-1] = grid.domino[:, :-1] == grid.domino[:, 1:]

    def fits(x, y, shape):
        # Cada fila de la mata cae en dominós enteros (si no, quedarían medios dominós sueltos).
        pixels = [(x + dx, y + dy) for dx, dy, _color in shape]
        return all(0 <= qy < grid.height and 0 <= qx + 1 < grid.width and margin[qy, qx]
                   and (dx % 2 == 1 or pair[qy, qx]) for (qx, qy), (dx, _dy, _c) in zip(pixels, shape))

    blades = []
    blocked = np.zeros(grid.mask.shape, dtype=bool)
    chosen = []
    ys, xs = np.nonzero(margin)
    tufts = list(GRASS_TUFTS)
    for position in np.argsort(order[ys, xs], kind="stable"):
        if not tufts:
            break
        x, y = int(xs[position]), int(ys[position])
        if any(((x - cx) / 2.0) ** 2 + (y - cy) ** 2 < TUFT_SPACING ** 2 for cx, cy in chosen):
            continue
        if not fits(x, y, tufts[0]):
            continue
        chosen.append((x, y))
        blades += [(x + dx, y + dy, color) for dx, dy, color in tufts.pop(0)]
    if tufts:
        raise ValueError("%s: no hubo lugar para todas las matas" % name)
    for x, y, _color in blades:
        blocked[y, x] = True
    counts = domino_counts(grid, GRASS_SHARES)
    shared = pattern.exact_levels(grass_value(grid, 6000), grid.mask, counts[:-1], group=grid.domino)
    index = np.where(ring, shared, 0).astype(np.int16)
    # Las matas tapan siempre la misma cantidad de pasto: se le resta al tono base.
    left = [count - int((shared[ring] == level).sum()) // 2 for level, count in enumerate(counts)]
    left[G_BASE] -= len(blades) // 2
    inside = grid.mask & ~ring & ~blocked
    value = blended(grid, grass_value(grid, 6000), grass_value(grid, seed))
    split = pattern.exact_levels(value, inside, left[:-1], group=grid.domino)
    index[inside] = split[inside]
    for x, y, color in blades:
        index[y, x] = color
    return grid, index


# ---------------------------------------------------------------------- generar

MATERIALS = (
    # (nombre, función, paleta, material, colores base de data/construction.json)
    ("floor_ceramic", ceramic_tile, CERAMIC, "ceramic", CONSTRUCTION["floors"]["ceramic"]["colors"]),
    ("floor_wood", wood_tile, WOOD, "wood", CONSTRUCTION["floors"]["wood"]["colors"]),
    ("floor_carpet", carpet_tile, CARPET, "carpet", CONSTRUCTION["floors"]["carpet"]["colors"]),
    ("ground_grass", grass_tile, GRASS, "grass", [GRASS_BASE, GRASS_SECOND]),
)


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
    """Vistas para mirar (no son arte del juego), todas en _sheets/: mosaicos de variantes al
    azar a ×3 y a ×1 de cada material, y la hoja del grupo (todas las casillas, un mosaico de
    cada material y un local con los tres pisos rodeado de pasto, todo a ×3)."""
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    mosaics = []
    for name, tiles in images.items():
        short = name.split("_", 1)[1]
        sheet.tile_mosaic(tiles, 5, 5, seed=3, scale=3).save(os.path.join(folder, "floors_%s_x3.png" % short))
        sheet.tile_mosaic(tiles, 12, 12, seed=5, scale=1).save(os.path.join(folder, "floors_%s_x1.png" % short))
        mosaics.append(sheet.tile_mosaic(tiles, 4, 4, seed=8, scale=3))
    lot = sheet.Scene(9, 9, top=16, margin=8)
    lot.fill_floor(images["ground_grass"], seed=11)
    lot.fill_floor(images["floor_ceramic"], seed=12, area=(2, 2, 7, 4))
    lot.fill_floor(images["floor_wood"], seed=13, area=(2, 4, 5, 7))
    lot.fill_floor(images["floor_carpet"], seed=14, area=(5, 4, 7, 7))
    items = []
    for name, tiles in images.items():
        items += [("%s_%d" % (name, i), image.crop((0, 64, 128, 128))) for i, image in enumerate(tiles)]
    parts = [sheet.contact_sheet(items, columns=4, scale=3)] + mosaics + [lot.render(2)]
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
