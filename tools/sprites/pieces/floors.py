# Pisos y terreno (docs/sprites_128.md, sección 5; estilo de tools/sprites/STYLE.md).
#
#   floor_ceramic_0..3   cerámica blanca: 2×2 losas lisas, junta oscura de 1 px en el borde y en el
#                        medio, canto blanco arriba a la izquierda y gris abajo; un reflejo o una nube
#   floor_wood_0..3      4 tablones de madera oscura a lo largo de u con cortes escalonados y vetas
#   floor_carpet_0..3    alfombra en 2×2 placas frías con surcos a cuarto de vuelta, sin brillo
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


def normalized(value, mask):
    """El mismo campo con media 0 y desviación 1 dentro de mask."""
    return (value - value[mask].mean()) / value[mask].std()


def smoothstep(value):
    value = np.clip(value, 0.0, 1.0)
    return value * value * (3.0 - 2.0 * value)


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


NEIGHBORS = ((1, 0), (-1, 0), (0, 1), (0, -1))


def neighbor_table(grid):
    """Para cada pixel de la casilla, dónde están sus 4 vecinos dando la vuelta por el borde (la
    casilla de al lado es la misma casilla): arreglo (4, alto, ancho, 2) con (y, x); −1 fuera."""
    table = np.full((4, grid.height, grid.width, 2), -1, dtype=np.int32)
    for y, x in zip(*np.nonzero(grid.mask)):
        for number, (dy, dx) in enumerate(NEIGHBORS):
            qx, qy = x + dx, y + dy
            if not (0 <= qy < grid.height and 0 <= qx < grid.width and grid.mask[qy, qx]):
                qx, qy = grid.wrap(qx, qy)
            table[number, y, x] = (qy, qx)
    return table


def same_neighbors(index, mask, table):
    """Cuántos de los 4 vecinos (con la vuelta por el borde) tienen el color del pixel."""
    total = np.zeros(index.shape, dtype=np.int16)
    for number in range(4):
        ny, nx = table[number, ..., 0], table[number, ..., 1]
        total += mask & (index[np.clip(ny, 0, None), np.clip(nx, 0, None)] == index)
    return total


def despeckle(grid, index, fixed, radius=8, rounds=6):
    """Quita los pixeles sueltos (ningún vecino de su color a los lados ni arriba o abajo, también
    del otro lado del borde) sin cambiar cuántos hay de cada color: el suelto toma el color de la
    mayoría de sus vecinos y un pixel de ese color cercano, pegado a una mancha del color del
    suelto, toma el suyo. Los pixeles de `fixed` (el anillo compartido, las briznas) no se tocan.
    Cambia `index`; devuelve cuántos sueltos quedan fuera de `fixed`."""
    mask = grid.mask
    free = mask & ~fixed
    table = neighbor_table(grid)
    height, width = index.shape

    def around(y, x):
        return [tuple(table[number, y, x]) for number in range(4)]

    def count(y, x, color):
        return sum(1 for qy, qx in around(y, x) if index[qy, qx] == color)

    for _round in range(rounds):
        specks = free & (same_neighbors(index, mask, table) == 0)
        if not specks.any():
            break
        for y, x in zip(*np.nonzero(specks)):
            own = index[y, x]
            if count(y, x, own):
                continue  # ya lo arregló otro cambio
            colors = [index[qy, qx] for qy, qx in around(y, x) if free[qy, qx]] or \
                     [index[qy, qx] for qy, qx in around(y, x)]
            other = max(set(colors), key=colors.count)
            found = None
            # Primero uno que quede bien metido en una mancha; si no hay, uno que al menos toque una.
            for need, step in [(2, step) for step in range(1, radius + 1)] + \
                              [(1, step) for step in range(1, 2 * radius + 1)]:
                for qy in range(max(y - step, 0), min(y + step + 1, height)):
                    for qx in range(max(x - 2 * step, 0), min(x + 2 * step + 1, width)):
                        if found or not free[qy, qx] or index[qy, qx] != other or (qy, qx) == (y, x):
                            continue
                        if count(qy, qx, own) < need or (qy, qx) in around(y, x):
                            continue
                        # Que no deje suelto a ningún vecino de su color.
                        if all(index[ny, nx] != other or count(ny, nx, other) >= 2 for ny, nx in around(qy, qx)):
                            found = (qy, qx)
                if found:
                    break
            if found:
                index[y, x] = other
                index[found] = own
    return int((free & (same_neighbors(index, mask, table) == 0)).sum())


def repetition(tiles, colors):
    """Cuánto del dibujo se repite en cada casilla: varianza del promedio de las variantes entre
    la varianza total del brillo. Es la autocorrelación que se espera en un mosaico al azar a un
    paso de casilla: 0.25 con 4 variantes que no se parecen en nada, 1.0 si son iguales."""
    mask = tiles[0][0].mask
    values = np.array([brightness(index, colors)[mask] for _grid, index in tiles])
    mean = values.mean()
    return float(((values.mean(axis=0) - mean) ** 2).mean() / ((values - mean) ** 2).mean())


# ---------------------------------------------------------------------- cerámica

# Cerámica blanca de STYLE.md: losas lisas casi blancas, junta oscura de 1 px (el ciruela de la
# tapa de pared, como en la referencia), brillo blanco en el canto de arriba a la izquierda y un
# gris en el de abajo a la derecha. Poco ruido: cada losa lleva a lo sumo un reflejo y una nube.
(C_JOINT, C_SHADE, C_SOFT_SHADE, C_CLOUD, C_OTHER, C_BASE, C_GLAZE, C_LIGHT) = range(8)
CERAMIC = pal.palette([
    pal.CERAMIC_WHITE[pal.OUTLINE],               # junta (3e2e33)
    pal.CERAMIC_WHITE[pal.LEFT],                  # canto de abajo a la derecha (bbb9b9)
    pal.CERAMIC_WHITE[pal.SOFT],                  # canto de abajo a la izquierda (d2d1d1)
    pal.mix(pal.CERAMIC_WHITE[pal.BASE], pal.CERAMIC_WHITE[pal.SOFT], 0.32),  # nube del esmalte
    pal.mix(pal.CERAMIC_WHITE[pal.BASE], pal.CERAMIC_WHITE[pal.SOFT], 0.25),  # losa de otra hornada
    pal.CERAMIC_WHITE[pal.BASE],                  # losa (e8e8e8)
    pal.mix(pal.CERAMIC_WHITE[pal.BASE], "ffffff", 0.55),  # reflejo
    "ffffff",                                     # brillo del canto de arriba a la izquierda
], name="ceramic")
SLAB = 32  # px de eje por losa (2×2 por casilla); la junta es la primera fila de cada losa
CERAMIC_TONES = (
    {"cloud": C_CLOUD, "sheen": C_GLAZE, "mark": C_CLOUD},
    {"cloud": C_CLOUD, "sheen": C_BASE, "mark": C_SOFT_SHADE},
)
# Dibujo de cada losa: rectángulos (parte, a, b, ancho, alto) en celdas de la rejilla isométrica
# dentro del campo de la losa (sin junta ni cantos: 0 … 28). Un rectángulo de esa rejilla es un
# rombo en pantalla (bordes 2:1); con medidas pares no deja pixeles sueltos.
CERAMIC_KITS = {
    "glint": (("sheen", 5, 4, 2, 14), ("sheen", 9, 4, 2, 6), ("cloud", 18, 18, 8, 6)),
    "cloud": (("cloud", 3, 4, 14, 6), ("cloud", 5, 10, 12, 4), ("cloud", 9, 14, 6, 2)),
    "band": (("sheen", 20, 6, 2, 12), ("cloud", 3, 18, 10, 6), ("cloud", 3, 14, 4, 4)),
    "other": (("sheen", 4, 6, 2, 8), ("mark", 14, 20, 8, 2)),
}
CERAMIC_LAYOUTS = (
    (("other", 0, 0), ("glint", 0, 1), ("cloud", 1, 0), ("band", 1, 1)),
    (("band", 0, 1), ("cloud", 0, 0), ("glint", 1, 1), ("other", 1, 0)),
    (("cloud", 1, 1), ("other", 0, 1), ("band", 0, 0), ("glint", 1, 0)),
    (("glint", 0, 0), ("band", 1, 0), ("other", 1, 1), ("cloud", 0, 1)),
)


def ceramic_tile(variant):
    """Índices de paleta de una casilla de cerámica blanca."""
    grid = iso.tile_grid()
    du = np.mod(grid.iu, SLAB)
    dv = np.mod(grid.iv, SLAB)
    index = np.full(grid.mask.shape, C_BASE, dtype=np.int16)
    slab = (grid.iu // SLAB) + 2 * (grid.iv // SLAB)
    field = (du >= 2) & (dv >= 2) & (du <= SLAB - 2) & (dv <= SLAB - 2)
    for number, (kit, flip_a, flip_b) in enumerate(CERAMIC_LAYOUTS[variant]):
        area = grid.mask & field & (slab == number)
        tones = CERAMIC_TONES[1 if kit == "other" else 0]
        if kit == "other":
            index[area] = C_OTHER
        a = (SLAB - 2) - du if flip_a else du - 2
        b = (SLAB - 2) - dv if flip_b else dv - 2
        for part, a0, b0, width, height in CERAMIC_KITS[kit]:
            index[area & pattern.rect(a, b, a0, a0 + width, b0, b0 + height)] = tones[part]
    # Cantos: la luz viene de arriba a la izquierda.
    index[dv == SLAB - 1] = C_SOFT_SHADE  # abajo a la izquierda
    index[du == SLAB - 1] = C_SHADE       # abajo a la derecha
    index[(du == 1) & (dv >= 1)] = C_LIGHT  # arriba a la izquierda
    index[(du == 0) | (dv == 0)] = C_JOINT
    return grid, index


# ---------------------------------------------------------------------- madera

# Tablones de madera oscura (WOOD_FLOOR, como el piso de la referencia): 4 por casilla a lo largo
# de u, separados por una línea oscura de 1 px; cada tablón tiene su tono plano, un canto claro
# arriba, uno oscuro abajo y alguna veta larga. Cada fila tiene dos cortes escalonados: la tabla
# que cruza el borde de la casilla es igual en las 4 variantes (si no, se cortaría) y la de
# adentro (36 px de largo en todas las filas) cambia de tono y de veta entre variantes.
W = pal.WOOD_FLOOR
(W_SEAM, W_EDGE_DARK, W_GRAIN_DARK, W_SOFT, W_BASE2, W_BASE, W_LIGHT, W_GRAIN_LIGHT) = range(8)
WOOD = pal.palette([
    W[pal.RIGHT],             # junta y cortes (783a13)
    W[pal.LEFT],              # canto de abajo de cada tablón (9d6035)
    pal.mix(W[pal.LEFT], W[pal.SOFT], 0.35),  # veta oscura
    W[pal.SOFT],              # tablón (a5673b)
    W[W.index("base2")],      # tablón (a5663a)
    W[pal.BASE],              # tablón (ad6d40)
    W[pal.LIGHT],             # tablón claro y canto de arriba (b67647)
    pal.mix(W[pal.LIGHT], W[pal.SHINE], 0.18),  # veta clara
], name="wood")
PLANK = 16          # px de eje de ancho (4 por casilla)
INNER_LENGTH = 36   # largo de la tabla de adentro
WOOD_CUTS = (6, 22, 14, 26)  # primer corte de cada fila (el segundo, 36 más allá); escalonados
WOOD_CROSS_TONES = (W_BASE, W_LIGHT, W_BASE2, W_BASE)  # tabla que cruza el borde, por fila
# Tablas de adentro: (tono, vetas (a, b, largo, tono)) en coordenadas de la tabla: a a lo largo
# (0 … 35), b a lo ancho del cuerpo (0 … 12).
WOOD_KITS = (
    (W_BASE, ((4, 3, 18, W_GRAIN_DARK), (14, 8, 14, W_GRAIN_DARK))),
    (W_SOFT, ((8, 5, 20, W_GRAIN_DARK),)),
    (W_LIGHT, ((2, 4, 12, W_GRAIN_LIGHT), (18, 9, 14, W_GRAIN_DARK))),
    (W_BASE2, ((10, 2, 16, W_GRAIN_LIGHT), (6, 9, 10, W_GRAIN_DARK))),
)
WOOD_CROSS_GRAIN = ((10, 6, 14, W_GRAIN_DARK), (4, 3, 10, W_GRAIN_LIGHT), (12, 9, 12, W_GRAIN_DARK),
                    (6, 5, 16, W_GRAIN_DARK))
# Qué tabla de adentro va en cada fila y si va volteada (a lo largo, a lo ancho).
WOOD_LAYOUTS = (
    ((0, 0, 0), (1, 0, 0), (2, 0, 0), (3, 0, 0)),
    ((2, 1, 0), (3, 0, 1), (0, 1, 1), (1, 1, 0)),
    ((3, 0, 1), (0, 1, 0), (1, 0, 1), (2, 1, 1)),
    ((1, 1, 1), (2, 0, 1), (3, 1, 0), (0, 0, 1)),
)


def wood_tile(variant):
    """Índices de paleta de una casilla de tablones."""
    grid = iso.tile_grid()
    row = grid.iv // PLANK
    across = np.mod(grid.iv, PLANK)
    index = np.full(grid.mask.shape, W_BASE, dtype=np.int16)
    body = (across >= 2) & (across <= PLANK - 2)
    for number in range(4):
        cut = WOOD_CUTS[number]
        in_row = grid.mask & (row == number)
        inner = in_row & (grid.iu > cut) & (grid.iu < cut + INNER_LENGTH)
        cross = in_row & ~inner
        # Tabla que cruza el borde: igual en todas las variantes (periódica a lo largo).
        index[cross] = WOOD_CROSS_TONES[number]
        along = np.mod(grid.iu - (cut + INNER_LENGTH + 1), 64)
        a0, b0, length, tone = WOOD_CROSS_GRAIN[number]
        index[cross & body & (along >= a0) & (along < a0 + length) & (across - 2 == b0)] = tone
        # Tabla de adentro: la de la variante.
        kit, flip_a, flip_b = WOOD_LAYOUTS[variant][number]
        tone, grains = WOOD_KITS[kit]
        index[inner] = tone
        a = grid.iu - (cut + 1)
        if flip_a:
            a = INNER_LENGTH - 2 - a
        b = across - 2
        if flip_b:
            b = PLANK - 4 - b
        for a0, b0, length, grain in grains:
            index[inner & body & (a >= a0) & (a < a0 + length) & (b == b0)] = grain
        # Cortes de punta.
        index[in_row & ((grid.iu == cut) | (grid.iu == cut + INNER_LENGTH))] = W_SEAM
    index[across == 1] = np.where(index[across == 1] == W_SEAM, W_SEAM, W_LIGHT)
    index[across == PLANK - 1] = W_EDGE_DARK
    index[across == 0] = W_SEAM
    return grid, index


# ---------------------------------------------------------------------- alfombra

# Alfombra de oficina en placas (color frío, como el piso lila de la referencia): 2×2 placas por
# casilla con el borde apenas marcado y una trama ordenada de surcos que en cada placa va en el
# otro sentido (a cuarto de vuelta, como se colocan). Sin brillo. Cada variante tiene una zona
# del pelo aplastado (un tono más clara) en otra placa y con otra forma.
(K_LINE, K_DARK, K_MID, K_BASE, K_LIGHT) = range(5)
CARPET = pal.palette(["646787", "717496", "7b7e9f", "8688a4", "8e90ab"], name="carpet")
CARPET_SQUARE = 32
# Zonas de pelo aplastado: rectángulos (a, b, ancho, alto) con lados múltiplos de 8 (el periodo
# de la trama) dentro de la placa, así tapan la misma cantidad de cada tono en cualquier sentido.
CARPET_KITS = (
    ((4, 8, 16, 16), (8, 0, 8, 8)),
    ((8, 12, 16, 8), (16, 20, 8, 8)),
    ((4, 12, 16, 16),),
    ((4, 4, 24, 8), (12, 12, 8, 8)),
)
CARPET_LAYOUTS = (
    ((0, 0), (1, 1), (2, 2), (3, 3)),
    ((1, 2), (3, 0), (0, 3), (2, 1)),
    ((2, 1), (0, 3), (3, 0), (1, 2)),
    ((3, 3), (2, 2), (1, 1), (0, 0)),
)


def carpet_texture(along, across):
    """Surcos de la alfombra: cada 4 filas, dos del tono base, una media y una oscura con
    puntadas de 4 px (todo de a dominó, sin pixeles sueltos)."""
    phase = np.mod(across, 4)
    stitch = np.mod(along // 4 + across // 4, 2) == 0
    out = np.full(np.shape(along), K_BASE, dtype=np.int16)
    out = np.where(phase == 2, np.where(stitch, K_MID, K_BASE), out)
    out = np.where(phase == 3, np.where(stitch, K_DARK, K_MID), out)
    return out


def carpet_tile(variant):
    """Índices de paleta de una casilla de alfombra."""
    grid = iso.tile_grid()
    du = np.mod(grid.iu, CARPET_SQUARE)
    dv = np.mod(grid.iv, CARPET_SQUARE)
    square = (grid.iu // CARPET_SQUARE) + 2 * (grid.iv // CARPET_SQUARE)
    # Placas 0 y 3 con surcos a lo largo de u; 1 y 2 a lo largo de v.
    along_u = (square == 0) | (square == 3)
    index = np.where(along_u, carpet_texture(du, dv), carpet_texture(dv, du)).astype(np.int16)
    for number, (kit, turn) in enumerate(CARPET_LAYOUTS[variant]):
        a = du if turn % 2 == 0 else CARPET_SQUARE - 1 - du
        b = dv if turn < 2 else CARPET_SQUARE - 1 - dv
        a = a - 1
        b = b - 1
        area = grid.mask & (square == number) & (du >= 1) & (dv >= 1)
        for a0, b0, width, height in CARPET_KITS[kit]:
            zone = area & pattern.rect(a, b, a0, a0 + width, b0, b0 + height)
            lifted = np.minimum(index + 1, K_LIGHT)
            index[zone] = lifted[zone]
    index[(du == 0) | (dv == 0)] = K_LINE
    return grid, index


# ---------------------------------------------------------------------- pasto

GRASS_BASE, GRASS_SECOND = CONSTRUCTION["terrain"]["colors"]  # 5f8a4c, 567e44 (dibujo provisional)
G_DEEP, G_SHADE, G_DARK, G_MID, G_BASE, G_LIGHT, G_BLADE, G_TIP = range(8)
# Pasto saturado con la rampa de hojas de STYLE.md (LEAVES): pocos verdes bien separados.
L = pal.LEAVES
GRASS = pal.palette([
    L[pal.RIGHT],                          # pie de las matas (4c6029)
    pal.mix(L[pal.RIGHT], L[pal.LEFT], 0.45),  # mechones dentro de las manchas oscuras
    L[pal.LEFT],                           # mancha oscura (648132)
    pal.mix(L[pal.LEFT], L[pal.SOFT], 0.5),    # borde de la mancha oscura
    L[pal.SOFT],                           # pasto (81a73a)
    pal.mix(L[pal.SOFT], L[pal.BASE], 0.35),   # mancha clara
    L[pal.BASE],                           # brizna (9ecc42)
    L[pal.LIGHT],                          # punta de la brizna (cbf166)
], name="grass")
GRASS_DARK = 0.15    # fracción de la casilla en verde oscuro
GRASS_MID = 0.09     # en el verde intermedio (borde de las manchas oscuras)
GRASS_LIGHT = 0.10   # en verde claro
GRASS_BLEND = 5      # px de eje desde el borde en los que entra la mancha propia de cada variante
# Corrección por distancia al borde (px de eje → suma al campo de las manchas; positivo = menos
# oscuro ahí). Igual en las 4 variantes: aplana el brillo medio de las 4 por bandas, para que no
# quede una retícula (borde más oscuro o más claro que el centro). Se interpola entre los puntos.
GRASS_BAND_BIAS = ((1, 0.51), (3, 0.20), (5, 0.38), (7, 0.22), (10, -0.13), (14, -0.53), (20, -0.45), (28, 0.38))
GRASS_FRINGE = (0.06, 0.24)  # parte de las columnas con fleco de 2 px, y de 2 o 1 px
GRASS_FRINGE_SEED = 7
# Lo que cruza el borde es igual en las 4 variantes (si no, se cortaría): unas manchitas cortas
# a caballo de cada lado. (eje del lado, posición a lo largo, signo: −1 oscura / +1 clara, medio
# ancho). El lado "u" es el que se recorre a lo largo de u (entre esta casilla y la de v − 1).
# Lejos de los vértices, sin tramos largos y en la proporción del resto de la casilla, para que
# el borde no se vea ni como marco ni como fila de manchas.
GRASS_NUBS = (
    ("u", 21.0, -1, 4.2), ("u", 50.0, -1, 2.4), ("u", 36.0, +1, 3.0),
    ("v", 43.0, -1, 4.2), ("v", 12.0, -1, 2.4), ("v", 27.0, +1, 3.0),
)
GRASS_NUB_HEIGHT = 2.0  # fuerza en el centro (en desviaciones de la mancha propia)
GRASS_NUB_DEPTH = 3.0   # cuánto entra en la casilla (px de eje)
# Manchas de verde claro (mismo formato que GRASS_OWN, otras semillas): más chicas y parecidas
# entre variantes. GRASS_LIGHT_BIAS: cuánto de GRASS_BAND_BIAS se les aplica (al revés).
GRASS_LIGHT_OWN = (
    (4001, 2.2, 0.8, 1.5, 3.5),
    (4013, 2.2, 0.8, 1.5, 3.5),
    (4027, 2.6, 0.8, 1.5, 4.0),
    (4049, 2.0, 0.8, 1.5, 3.5),
)
GRASS_LIGHT_BIAS = 0.0
GRASS_RING_CUTS = (-1.2, -0.7, 0.9)  # cortes del borde: oscuro, intermedio, claro
# Mancha propia de cada variante: (semilla, ciclos por casilla con más fuerza, ancho de la banda,
# ciclos mínimo y máximo). Cada una tiene otro carácter con los mismos pixeles por color: una
# mancha grande, dos medianas, mechones repartidos y una mezcla.
GRASS_OWN = (
    (3001, 1.0, 0.8, 1.0, 2.5),
    (3027, 1.6, 0.8, 1.0, 3.0),
    (3061, 2.2, 0.8, 1.4, 3.2),
    (3037, 1.4, 1.0, 1.0, 3.0),
)


def shape_pixels(rows, colors):
    """Convierte un dibujo en filas de letras en una lista (dx, dy, color). El pie es la fila de
    abajo (dy = 0); dy negativo = hacia arriba. '.' = vacío."""
    pixels = []
    for row, line in enumerate(rows):
        for column, letter in enumerate(line):
            if letter != ".":
                pixels.append((column, row - (len(rows) - 1), colors[letter]))
    return tuple(pixels)


BLADE_COLORS = {"t": G_TIP, "b": G_BLADE, "d": G_DEEP, "s": G_SHADE}
# Matas: briznas de 1×2 a 1×3 juntas, más claras arriba, con el pie oscuro. La grande junta dos
# puntas para que se siga viendo al achicar.
TUFT_BIG = shape_pixels(("..t..",
                         "..tt.",
                         "t.bb.",
                         "bdbbd"), BLADE_COLORS)
TUFT_PAIR = shape_pixels(("t..",
                          "b.b",
                          "bdb"), BLADE_COLORS)
BLADE_SHORT = shape_pixels(("t",
                            "b"), BLADE_COLORS)
# Mechón dentro de una mancha oscura: trazo 2:1 de 4 px.
STROKE_U = shape_pixels(("ss..",
                         "..ss"), BLADE_COLORS)
STROKE_V = shape_pixels(("..ss",
                         "ss.."), BLADE_COLORS)
# Grupos de matas por casilla: cada grupo es una lista (forma, dx, dy) alrededor de su centro.
# Entre los grupos queda pasto limpio.
TUFT_GROUPS = (
    ((TUFT_BIG, 0, 0), (TUFT_PAIR, -7, -1), (TUFT_PAIR, 8, 2), (BLADE_SHORT, -3, 3), (BLADE_SHORT, 13, 0)),
    ((TUFT_BIG, 0, 0), (TUFT_PAIR, 7, -2), (BLADE_SHORT, -4, 2), (BLADE_SHORT, 4, 3)),
    ((TUFT_PAIR, 0, 0), (TUFT_PAIR, -6, 2), (BLADE_SHORT, 5, 1)),
    ((TUFT_BIG, 0, 0), (TUFT_PAIR, -8, 1), (BLADE_SHORT, 6, -2)),
)
TUFT_SPACING = 13.0   # separación mínima entre centros de grupo (px de alto; a lo ancho, el doble)
TUFT_MARGIN = 3       # px de eje que las matas dejan libres junto al borde
TUFT_OFFSET = (0, -3)  # un grupo va donde el pixel corrido esto (dx, dy) es de una mancha oscura
STROKE_COUNT = 6      # mechones oscuros por casilla
STROKE_SPACING = 5.0


def wrapped(delta):
    """Distancia con signo dando la vuelta por el borde de la casilla."""
    return np.mod(delta + CELL / 2.0, CELL) - CELL / 2.0


def grass_fringe(grid):
    """Flecos: cada columna de pixeles muestra la mancha de 0, 1 o 2 px más abajo (briznas en el
    borde de las manchas). Se repite cada 64 columnas, como la casilla."""
    chance = pattern.hash2(grid.x % CELL, 5, GRASS_FRINGE_SEED)
    return np.where(chance < GRASS_FRINGE[0], 2.0, np.where(chance < GRASS_FRINGE[1], 1.0, 0.0))


def grass_shared_field(grid, lift):
    """Manchitas del borde, iguales en las 4 variantes y periódicas."""
    total = np.zeros(grid.mask.shape)
    for axis, position, sign, half in GRASS_NUBS:
        along, across = (grid.U, grid.V) if axis == "u" else (grid.V, grid.U)
        total += sign * GRASS_NUB_HEIGHT * np.exp(-(wrapped(along + lift - position) / half) ** 2
                                                   - (wrapped(across + lift) / GRASS_NUB_DEPTH) ** 2)
    return total


def grass_own_field(grid, variant, lift, table=None):
    """Manchas propias de una variante: suma de ondas (ciclos por casilla en u, en v) con fase
    y fuerza al azar; media 0 y desviación 1. table = GRASS_OWN (oscuras) o GRASS_LIGHT_OWN."""
    seed, peak, width, low, high = (table or GRASS_OWN)[variant]
    u = (grid.U + lift) / CELL
    v = (grid.V + lift) / CELL
    total = np.zeros(grid.mask.shape)
    number = 0
    for ku in range(0, 7):
        for kv in range(-6, 7):
            cycles = (ku * ku + kv * kv) ** 0.5
            if (ku == 0 and kv <= 0) or not low <= cycles <= high:
                continue
            strength = np.exp(-((cycles - peak) / width) ** 2) * (0.5 + pattern.hash2(number, 2, seed))
            phase = pattern.hash2(number, 1, seed) * 2.0 * np.pi
            total += strength * np.cos(2.0 * np.pi * (ku * u + kv * v) + phase)
            number += 1
    return normalized(total, grid.mask)


def grass_levels(grid, variant, blocked=None):
    """Verde de cada pixel (G_DARK, G_MID, G_BASE o G_LIGHT) con cantidades exactas. Los pixeles
    de `blocked` (las briznas) no cuentan.

    En el anillo del borde solo hay manchitas compartidas; hacia adentro entra la mancha propia
    de la variante."""
    distance = np.minimum(np.minimum(grid.iu, CELL - 1 - grid.iu), np.minimum(grid.iv, CELL - 1 - grid.iv))
    lift = grass_fringe(grid)
    shared = grass_shared_field(grid, lift)
    value = shared + grass_own_field(grid, variant, lift) * smoothstep(distance / float(GRASS_BLEND))
    stops = np.array(GRASS_BAND_BIAS, dtype=float)
    value = value + np.interp(distance, stops[:, 0], stops[:, 1])
    ring = grid.mask & (distance == 0)
    level = np.full(grid.mask.shape, G_BASE, dtype=np.int16)
    # En el anillo se decide de a dominó (2 px seguidos), con la media del campo compartido: así
    # no queda ningún pixel suelto en el borde, que no se puede retocar después.
    ids, inverse = np.unique(grid.domino[ring], return_inverse=True)
    pair = np.zeros(grid.mask.shape)
    pair[ring] = (np.bincount(inverse, weights=shared[ring]) / np.bincount(inverse))[inverse]
    level[ring & (pair < GRASS_RING_CUTS[1])] = G_MID
    level[ring & (pair < GRASS_RING_CUTS[0])] = G_DARK
    level[ring & (pair > GRASS_RING_CUTS[2])] = G_LIGHT
    inside = grid.mask & ~ring
    if blocked is not None:
        inside &= ~blocked
    total = int(grid.mask.sum())
    wanted = {G_DARK: int(round(total * GRASS_DARK)), G_MID: int(round(total * GRASS_MID)),
              G_LIGHT: int(round(total * GRASS_LIGHT))}
    for green in wanted:
        wanted[green] -= int((level[ring] == green).sum())
    counts = [wanted[G_DARK], wanted[G_MID]]
    split = pattern.exact_levels(value, inside, counts)
    level[inside & (split == 0)] = G_DARK
    level[inside & (split == 1)] = G_MID
    # El verde claro sale de otro campo, de manchas más chicas: si fuera la otra punta del mismo
    # campo, cada variante tendría una sola mancha clara grande enfrente de la oscura, y esa
    # mancha se reconoce al repetirse.
    rest = inside & (split == 2)
    light = grass_own_field(grid, variant, lift, GRASS_LIGHT_OWN) * smoothstep(distance / float(GRASS_BLEND))
    light = light - np.interp(distance, stops[:, 0], stops[:, 1]) * GRASS_LIGHT_BIAS
    picked = pattern.exact_levels(-light, rest, [wanted[G_LIGHT]])
    level[rest & (picked == 0)] = G_LIGHT
    return level, distance


def place_shapes(grid, distance, wanted, taken):
    """Coloca formas chicas (briznas, matas, mechones). wanted = lista de (forma, x, y, permitido):
    el pie va en (x, y) o lo más cerca posible, con todos sus pixeles dentro de `permitido` y sin
    tocar lo ya puesto. Devuelve la lista de pixeles (x, y, color)."""
    placed = []
    for shape, x, y, allowed in wanted:
        found = None
        for radius in range(0, 12):
            for dy in range(-radius, radius + 1):
                for dx in range(-2 * radius, 2 * radius + 1):
                    if max(abs(dx) / 2.0, abs(dy)) < radius - 0.5 and radius:
                        continue  # ya se probó con un radio menor
                    pixels = [(x + dx + px, y + dy + py, color) for px, py, color in shape]
                    if all(0 <= qx < grid.width and 0 <= qy < grid.height and allowed[qy, qx] and not taken[qy, qx]
                           for qx, qy, _color in pixels):
                        found = pixels
                        break
                if found:
                    break
            if found:
                break
        if found is None:
            raise ValueError("no hubo lugar para una forma cerca de (%d, %d)" % (x, y))
        for qx, qy, _color in found:
            taken[max(qy - 1, 0):qy + 2, max(qx - 1, 0):qx + 2] = True
        placed.extend(found)
    return placed


def spaced_points(candidates, order, count, spacing, name):
    """Elige `count` pixeles, en el orden de `order` (azar fijo) y a no menos de `spacing` entre
    sí (px de alto; a lo ancho cuenta la mitad, como el suelo en pantalla). candidates es una
    lista de máscaras por orden de preferencia: de la segunda solo se toma lo que faltó."""
    chosen = []
    for mask in candidates:
        ys, xs = np.nonzero(mask)
        for position in np.argsort(order[ys, xs], kind="stable"):
            x, y = int(xs[position]), int(ys[position])
            if all(((x - cx) / 2.0) ** 2 + (y - cy) ** 2 >= spacing ** 2 for cx, cy in chosen):
                chosen.append((x, y))
                if len(chosen) == count:
                    return chosen
    raise ValueError("%s: solo hubo lugar para %d de %d" % (name, len(chosen), count))


def grass_tile(variant):
    """Índices de paleta de una casilla de pasto."""
    grid = iso.tile_grid()
    name = "ground_grass_%d" % variant
    level, distance = grass_levels(grid, variant)
    seed = GRASS_OWN[variant][0]
    order = pattern.hash2(grid.x, grid.y, seed)
    room = grid.mask & (distance >= TUFT_MARGIN)
    taken = np.zeros(grid.mask.shape, dtype=bool)
    # Grupos de matas pegados a las manchas oscuras (la mancha queda como lo tupido de atrás).
    dark = level == G_DARK
    behind = np.roll(np.roll(dark, -TUFT_OFFSET[1], axis=0), -TUFT_OFFSET[0], axis=1)
    open_ground = room & (distance >= TUFT_MARGIN + 6) & ~dark
    centers = spaced_points([open_ground & behind, open_ground], order, len(TUFT_GROUPS), TUFT_SPACING,
                            name + ", grupos de matas")
    wanted = []
    for (cx, cy), group in zip(centers, TUFT_GROUPS):
        for shape, dx, dy in group:
            wanted.append((shape, cx + dx, cy + dy, room))
    blades = place_shapes(grid, distance, wanted, taken)
    # Mechones: trazos 2:1 bien adentro de las manchas oscuras.
    deep = dark & room
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (0, 2), (0, -2)):
        deep &= np.roll(np.roll(dark, dy, axis=0), dx, axis=1)
    points = spaced_points([deep & ~taken], order, STROKE_COUNT, STROKE_SPACING, name + ", mechones")
    wanted = [((STROKE_U, STROKE_V)[number % 2], x, y, dark & room) for number, (x, y) in enumerate(points)]
    blades += place_shapes(grid, distance, wanted, taken)
    # Los verdes se reparten de nuevo sin contar los pixeles de las briznas: así cada color
    # tiene la misma cantidad en las 4 variantes caigan donde caigan.
    blocked = np.zeros(grid.mask.shape, dtype=bool)
    for x, y, _color in blades:
        blocked[y, x] = True
    index, _distance = grass_levels(grid, variant, blocked)
    for x, y, color in blades:
        index[y, x] = color
    # Sin pixeles sueltos de verde (los flecos dejan alguno); el anillo del borde no se toca.
    left = despeckle(grid, index, blocked | (distance == 0))
    if left:
        raise ValueError("%s: quedaron %d pixeles sueltos de verde" % (name, left))
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
