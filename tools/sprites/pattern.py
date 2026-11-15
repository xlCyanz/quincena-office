# Patrones para pisos y texturas de muebles (docs/sprites_128.md, sección 5).
#
# Todo es determinista (misma semilla = mismo dibujo) y trabaja sobre arreglos de numpy.
# En pisos se usan las coordenadas de iso.TileGrid:
#   u, v    en casillas (periodo 1): lo que sale por un lado entra por el opuesto
#   U, V    en «px de eje» (u × 64): una banda de 1 de ancho es una línea 2:1 de 1 px de alto
#   iu, iv  enteros de la rejilla isométrica; cada (iu, iv) válido son 2 px seguidos (un dominó)
# En muebles se usan ctx.a / ctx.b (px dentro de la cara) y ctx.sx / ctx.sy (pixel de pantalla).
# Nada de ruido suelto de 1 px: tramas ordenadas (Bayer), bloques y trazos.
import numpy as np

BAYER2 = np.array([[0, 2], [3, 1]], dtype=np.float64) / 4.0
BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float64) / 16.0
BAYER8 = np.array([
    [0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]], dtype=np.float64) / 64.0
_BAYER = {2: BAYER2, 4: BAYER4, 8: BAYER8}


def bayer(x, y, size=4):
    """Umbral de trama ordenada (0 a <1) para cada posición entera (x, y). size 2, 4 u 8.
    Con pixeles de pantalla (ctx.sx, ctx.sy o grid.x, grid.y) empalma entre casillas porque 64
    y 32 son múltiplos de size. Con (iu, iv) la trama sigue los ejes isométricos."""
    matrix = _BAYER[size]
    return matrix[np.asarray(y).astype(np.int64) % size, np.asarray(x).astype(np.int64) % size]


def dither(value, x, y, levels=2, size=4):
    """Cuantiza value (0–1) a `levels` niveles (0 … levels−1) con trama Bayer ordenada."""
    scaled = np.clip(np.asarray(value, dtype=np.float64), 0.0, 1.0) * (levels - 1)
    low = np.floor(scaled)
    return (low + ((scaled - low) > bayer(x, y, size))).astype(np.int16)


def checker(x, y, size=1):
    """Damero de bloques de size px: True en las casillas «negras». La trama 2×2 de una alfombra."""
    return ((np.asarray(x).astype(np.int64) // size + np.asarray(y).astype(np.int64) // size) % 2) == 0


def hash2(i, j, seed=0):
    """Azar fijo (0 a <1) por par de enteros (i, j) y semilla. Acepta arreglos o números."""
    a = np.atleast_1d(np.asarray(i)).astype(np.int64).astype(np.uint64)
    b = np.atleast_1d(np.asarray(j)).astype(np.int64).astype(np.uint64)
    salt = np.array([(int(seed) * 0x165667B19E3779F9 + 0x27D4EB2F165667C5) % (1 << 64)], dtype=np.uint64)
    with np.errstate(over="ignore"):
        h = a * np.uint64(0x9E3779B97F4A7C15) + b * np.uint64(0xC2B2AE3D27D4EB4F) + salt
        h = h ^ (h >> np.uint64(29))
        h = h * np.uint64(0xBF58476D1CE4E5B9)
        h = h ^ (h >> np.uint64(32))
        h = h * np.uint64(0x94D049BB133111EB)
        h = h ^ (h >> np.uint64(29))
    out = (h >> np.uint64(11)).astype(np.float64) / float(1 << 53)
    if np.ndim(i) == 0 and np.ndim(j) == 0:
        return float(out[0])
    return out


def value_noise(u, v, period=4, seed=0):
    """Ruido suave (0–1) periódico: `period` nudos por casilla en cada eje; se repite cada 1 en
    u y v, así cruza los bordes de la casilla sin costura. Para manchas grandes usar period 2–4."""
    period = int(period)
    x = np.asarray(u, dtype=np.float64) * period
    y = np.asarray(v, dtype=np.float64) * period
    x0 = np.floor(x)
    y0 = np.floor(y)
    fx = x - x0
    fy = y - y0
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    x0 = x0.astype(np.int64) % period
    y0 = y0.astype(np.int64) % period
    x1 = (x0 + 1) % period
    y1 = (y0 + 1) % period
    g00, g10 = hash2(x0, y0, seed), hash2(x1, y0, seed)
    g01, g11 = hash2(x0, y1, seed), hash2(x1, y1, seed)
    return (g00 * (1 - fx) + g10 * fx) * (1 - fy) + (g01 * (1 - fx) + g11 * fx) * fy


def blobs(u, v, seed=0, periods=(2, 4), weights=(0.65, 0.35)):
    """Manchas periódicas (0–1): suma de ruidos suaves de varios tamaños. Sirve de `value` para
    exact_levels() en pasto, concreto o veteado."""
    total = np.zeros(np.asarray(u).shape, dtype=np.float64)
    for index, (period, weight) in enumerate(zip(periods, weights)):
        total += value_noise(u, v, period, seed * 31 + index) * weight
    return total / float(sum(weights))


def joints(U, V, period=64, width=2, axis="both"):
    """Máscara de juntas de una cuadrícula de losas: líneas de `width` px centradas en cada
    múltiplo de `period` (px de eje). Con width 2 queda 1 px a cada lado del borde de la casilla,
    así dos casillas vecinas forman juntas la junta completa. axis 'u', 'v' o 'both'.
    period 64 = 1 losa por casilla; 32 = 2×2 losas."""
    half = width / 2.0
    du = np.mod(np.asarray(U) + half, period)
    dv = np.mod(np.asarray(V) + half, period)
    on_u = du < width
    on_v = dv < width
    if axis == "u":
        return on_u
    if axis == "v":
        return on_v
    return on_u | on_v


def bevel(U, V, period=64, joint=2, width=1):
    """Bisel de las losas de joints(): devuelve (claro, oscuro). Claro = `width` px pegado a la
    junta del lado de arriba-izquierda de cada losa (U y V chicos); oscuro = del lado de
    abajo-derecha. No incluye la junta."""
    half = joint / 2.0
    du = np.mod(np.asarray(U) - half, period)
    dv = np.mod(np.asarray(V) - half, period)
    inner = period - joint
    inside = (du < inner) & (dv < inner)
    light = inside & ((du < width) | (dv < width))
    dark = inside & ~light & ((du >= inner - width) | (dv >= inner - width))
    return light, dark


def planks(U, V, count=4, axis="u", joint=1, length=64, seed=0, period=64):
    """Tablones paralelos a un eje. axis 'u' = corren a lo largo de u (se ven «\\»); 'v' = «/».
    count tablones por casilla, separados por una línea de `joint` px; cada tablón se corta cada
    `length` px con el corte corrido al azar (escalonado), periódico cada `period`.
    Devuelve un dict: index (número de tablón 0…count−1), piece (número único de tabla, cambia en
    cada corte), seam (línea entre tablones), cut (corte de punta), along (px a lo largo dentro de
    la tabla), across (px a lo ancho dentro del tablón), width (ancho del tablón en px)."""
    U = np.asarray(U, dtype=np.float64)
    V = np.asarray(V, dtype=np.float64)
    along_all, across_all = (U, V) if axis == "u" else (V, U)
    width = period / float(count)
    index = np.floor(np.mod(across_all, period) / width).astype(np.int64)
    across = np.mod(across_all, width)
    seam = across < joint
    offset = np.floor(hash2(index, 0, seed) * (length / 4.0)) * 4.0
    shifted = np.mod(along_all + offset, period)
    piece_n = np.floor(shifted / length).astype(np.int64)
    along = np.mod(shifted, length)
    cut = (along < 1.0) & ~seam
    piece = index * 64 + piece_n
    return {"index": index, "piece": piece, "seam": seam, "cut": cut, "along": along, "across": across,
            "width": width}


def _grain_fields(along, across, seed, length, row, period, row_period, thickness):
    along = np.asarray(along, dtype=np.float64)
    across = np.asarray(across, dtype=np.float64)
    r = np.floor(across / row).astype(np.int64)
    in_row = np.mod(np.floor(across), row) < thickness
    r_key = r if row_period is None else np.mod(r, int(row_period))
    phase = np.floor(hash2(r_key, 7, seed) * length)
    s = along + phase
    if period is not None:
        s = np.mod(s, period)
    cell = np.floor(s / length).astype(np.int64)
    pos = s - cell * length
    chance = hash2(r_key, cell, seed + 1)
    start = np.floor(hash2(r_key, cell, seed + 2) * (length / 3.0))
    size = np.floor(length / 3.0 + hash2(r_key, cell, seed + 3) * (length * 2.0 / 3.0 - 1.0))
    inside = in_row & (pos >= start) & (pos < start + size)
    return inside, chance, pos


def grain(along, across, seed=0, density=0.45, length=16, row=3, period=None, row_period=None, thickness=1):
    """Vetas: trazos largos de `thickness` px de grosor a lo largo de `along`. Las filas van cada
    `row` px de `across`; en cada fila se sortea por tramos de `length` px si hay trazo (density)
    y dónde empieza y termina. period (en px de `along`, múltiplo de length) y row_period (en
    filas) lo hacen periódico para pisos: ahí `row` tiene que dividir a 64 (2, 4, 8 o 16) y
    row_period ser 64 / row (o un divisor); con row=3 no se repite. Devuelve una máscara
    booleana. Sin pixeles sueltos: el trazo mínimo mide length / 3."""
    inside, chance, _pos = _grain_fields(along, across, seed, length, row, period, row_period, thickness)
    return inside & (chance < density)


def grain_value(along, across, seed=0, length=16, row=3, period=None, row_period=None, thickness=1):
    """Como grain() pero devuelve una PRIORIDAD por pixel en vez de una máscara: de 0 a <1 en los
    pixeles de cada trazo posible (todo el trazo comparte casi el mismo valor y crece a lo largo)
    y 2.0 fuera. Con pick_exact(grain_value(…), mask, n) se eligen exactamente n pixeles de veta
    (trazos enteros, el último cortado), para que todas las variantes de un piso tengan la misma
    cantidad y por lo tanto el mismo brillo medio."""
    inside, chance, pos = _grain_fields(along, across, seed, length, row, period, row_period, thickness)
    return np.where(inside, chance * 0.999 + pos * 1.0e-6, 2.0)


def scatter(count, seed=0, period=64, min_distance=4, margin=0, tries=40):
    """Reparte `count` puntos enteros (U, V) en una casilla de period × period px de eje, a no
    menos de min_distance entre sí (contando la vuelta por los bordes). margin deja libre una
    franja junto al borde de la casilla (para no tocar el anillo que comparten las variantes).
    Devuelve una lista de (U, V) con U + V par (los que tienen pixeles en la rejilla isométrica)."""
    points = []
    k = 0
    span = period - 2 * margin
    for n in range(int(count)):
        for _attempt in range(tries):
            pu = margin + int(hash2(k, 11, seed) * span)
            pv = margin + int(hash2(k, 23, seed) * span)
            k += 1
            if (pu + pv) % 2:  # solo los (iu, iv) de suma par tienen pixeles
                pv = pv + 1 if pv + 1 < period - margin else pv - 1
            good = True
            for qu, qv in points:
                du = min(abs(pu - qu), period - abs(pu - qu))
                dv = min(abs(pv - qv), period - abs(pv - qv))
                if max(du, dv) < min_distance:
                    good = False
                    break
            if good:
                points.append((pu, pv))
                break
    return points


def stamp_points(iu, iv, points, shape=((0, 0),), period=64):
    """Máscara de una forma chica repetida en cada punto de scatter(). shape = lista de
    desplazamientos (du, dv) en la rejilla isométrica; (0, 0) solo es un dominó de 2 px.
    Da la vuelta por los bordes (periódico)."""
    iu = np.mod(np.asarray(iu), period)
    iv = np.mod(np.asarray(iv), period)
    mask = np.zeros(iu.shape, dtype=bool)
    for pu, pv in points:
        for du, dv in shape:
            mask |= (iu == (pu + du) % period) & (iv == (pv + dv) % period)
    return mask


def stamp_pixels(grid, points, shape=((0, 0),)):
    """Como stamp_points pero en pixeles de pantalla, para formas que no siguen los ejes
    (briznas verticales de 1×2 o 1×3, piedritas de 2×1 a 3×2…). grid = iso.TileGrid; points =
    lista de pixeles (x, y) del lienzo (p. ej. de pixel_points()); shape = desplazamientos
    (dx, dy) en px. Lo que sale del rombo por un lado entra por el opuesto (grid.wrap), así
    empalma con las casillas vecinas. Devuelve una máscara."""
    mask = np.zeros(grid.mask.shape, dtype=bool)
    for px, py in points:
        for dx, dy in shape:
            wx, wy = grid.wrap(px + dx, py + dy)
            mask[wy, wx] = True
    return mask


def pixel_points(grid, count, seed=0, min_distance=4, margin=0):
    """Puntos de scatter() convertidos a pixeles (x, y) del lienzo de grid (el pixel izquierdo
    de cada dominó)."""
    points = []
    for pu, pv in scatter(count, seed, 64, min_distance, margin):
        if (pu + pv) % 2:
            pu = (pu + 1) % 64 if pu + 1 < 64 - margin else pu - 1
        points.append(grid.pixel_of(pu, pv))
    return points


def exact_levels(value, mask, counts, group=None, tie=None):
    """Reparte niveles (tonos) por orden de `value` dejando una cantidad EXACTA en cada uno: así
    todas las variantes de un piso tienen el mismo brillo medio.

    value   arreglo con el valor de cada pixel (ruido, manchas…)
    mask    pixeles a repartir
    counts  lista de cantidades por nivel, de los valores más bajos a los más altos. Lo que
            sobra queda en el último nivel + 1… o sea: niveles 0 … len(counts) (el último es «el
            resto»). Un valor entre 0 y 1 se toma como fracción del total
    group   arreglo de enteros: los pixeles con el mismo número reciben el mismo nivel y cuentan
            juntos (pasar grid.domino para repartir de a 2 px, sin pixeles sueltos). Las
            cantidades se cuentan entonces en grupos
    tie     arreglo para desempatar (p. ej. pattern.bayer(…)); por defecto el orden de lectura
    Devuelve un arreglo int16 con el nivel de cada pixel (−1 fuera de mask).
    """
    value = np.asarray(value, dtype=np.float64)
    out = np.full(value.shape, -1, dtype=np.int16)
    flat_mask = mask.ravel()
    if group is None:
        keys = np.nonzero(flat_mask)[0]
        vals = value.ravel()[keys]
        ties = tie.ravel()[keys] if tie is not None else np.zeros(len(keys))
        order = np.lexsort((np.arange(len(keys)), ties, vals))
        total = len(keys)
        levels = _split_levels(total, counts)
        ranked = np.empty(total, dtype=np.int16)
        ranked[order] = levels
        out.ravel()[keys] = ranked
        return out
    groups = np.asarray(group).ravel()[flat_mask]
    pixels = np.nonzero(flat_mask)[0]
    unique, inverse = np.unique(groups, return_inverse=True)
    sums = np.bincount(inverse, weights=value.ravel()[pixels])
    sizes = np.bincount(inverse)
    means = sums / sizes
    if tie is not None:
        ties = np.bincount(inverse, weights=tie.ravel()[pixels]) / sizes
    else:
        ties = np.zeros(len(unique))
    order = np.lexsort((np.arange(len(unique)), ties, means))
    levels = _split_levels(len(unique), counts)
    ranked = np.empty(len(unique), dtype=np.int16)
    ranked[order] = levels
    out.ravel()[pixels] = ranked[inverse]
    return out


def pick_exact(value, mask, count, group=None, tie=None):
    """Máscara con exactamente `count` pixeles de mask (o grupos, si se pasa group): los de menor
    `value`. Atajo de exact_levels(value, mask, [count]) == 0."""
    return exact_levels(value, mask, [int(count)], group=group, tie=tie) == 0


def _split_levels(total, counts):
    levels = np.full(total, len(counts), dtype=np.int16)
    start = 0
    for level, count in enumerate(counts):
        n = int(round(count * total)) if 0 < count < 1 else int(count)
        n = max(0, min(n, total - start))
        levels[start:start + n] = level
        start += n
    return levels


def frame(a, b, a0, a1, b0, b1, width=1):
    """Marco de `width` px del rectángulo [a0, a1) × [b0, b1) en coordenadas de cara (ctx.a, ctx.b)."""
    inside = (a >= a0) & (a < a1) & (b >= b0) & (b < b1)
    core = (a >= a0 + width) & (a < a1 - width) & (b >= b0 + width) & (b < b1 - width)
    return inside & ~core


def rect(a, b, a0, a1, b0, b1):
    """Rectángulo lleno [a0, a1) × [b0, b1) en coordenadas de cara."""
    return (a >= a0) & (a < a1) & (b >= b0) & (b < b1)


def stripes(value, period, width, offset=0.0):
    """Bandas de `width` cada `period` a lo largo de value (px)."""
    return np.mod(np.asarray(value) - offset, period) < width


def isolated_pixels(levels, mask):
    """Cuántos pixeles de mask no tienen NINGÚN vecino (4 direcciones) de su mismo nivel: mide
    el «ruido suelto de 1 px» que la guía prohíbe. Los bordes de la imagen dan la vuelta."""
    count = 0
    same = np.zeros(levels.shape, dtype=bool)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        same |= np.roll(np.roll(levels, dy, axis=0), dx, axis=1) == levels
    count = int((mask & ~same).sum())
    return count
