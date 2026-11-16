# Patrones deterministas (numpy) para pisos y texturas de muebles (docs/sprites_128.md, sección 5).
# Pisos: u, v en casillas (periodo 1), U, V = u × 64 («px de eje»), iu, iv la rejilla isométrica
# (cada par válido = un dominó de 2 px). Muebles: ctx.a / ctx.b (px de cara), ctx.sx / ctx.sy (pantalla).
# Nada de ruido suelto de 1 px: tramas ordenadas, bloques y trazos.
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
    """Umbral Bayer (0 a <1) por posición entera; size 2, 4 u 8. En px de pantalla empalma entre casillas."""
    matrix = _BAYER[size]
    return matrix[np.asarray(y).astype(np.int64) % size, np.asarray(x).astype(np.int64) % size]


def dither(value, x, y, levels=2, size=4):
    """Cuantiza value (0–1) a `levels` niveles (0 … levels−1) con trama Bayer ordenada."""
    scaled = np.clip(np.asarray(value, dtype=np.float64), 0.0, 1.0) * (levels - 1)
    low = np.floor(scaled)
    return (low + ((scaled - low) > bayer(x, y, size))).astype(np.int16)


def checker(x, y, size=1):
    """Damero de bloques de size px: True en las casillas «negras»."""
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
    """Ruido suave (0–1) con `period` nudos por casilla, periódico en u y v (sin costuras)."""
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
    """Manchas periódicas (0–1): suma de ruidos suaves de varios tamaños."""
    total = np.zeros(np.asarray(u).shape, dtype=np.float64)
    for index, (period, weight) in enumerate(zip(periods, weights)):
        total += value_noise(u, v, period, seed * 31 + index) * weight
    return total / float(sum(weights))


def joints(U, V, period=64, width=2, axis="both"):
    """Máscara de juntas de losas: líneas de `width` px centradas en cada múltiplo de `period`
    (64 = 1 losa por casilla, 32 = 2×2). axis 'u', 'v' o 'both'."""
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
    """Bisel de las losas de joints(): (claro arriba-izquierda, oscuro abajo-derecha), sin la junta."""
    half = joint / 2.0
    du = np.mod(np.asarray(U) - half, period)
    dv = np.mod(np.asarray(V) - half, period)
    inner = period - joint
    inside = (du < inner) & (dv < inner)
    light = inside & ((du < width) | (dv < width))
    dark = inside & ~light & ((du >= inner - width) | (dv >= inner - width))
    return light, dark


def planks(U, V, count=4, axis="u", joint=1, length=64, seed=0, period=64):
    """Tablones a lo largo de axis ('u' «\\», 'v' «/»): count por casilla, cortes escalonados cada `length`.
    Devuelve un dict con index, piece, seam, cut, along, across y width (px)."""
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
    """Máscara de vetas: trazos a lo largo de `along`, una fila cada `row` px de `across`. Para pisos,
    period y row_period lo hacen periódico (row debe dividir a 64)."""
    inside, chance, _pos = _grain_fields(along, across, seed, length, row, period, row_period, thickness)
    return inside & (chance < density)


def grain_value(along, across, seed=0, length=16, row=3, period=None, row_period=None, thickness=1):
    """Como grain() pero da una prioridad por pixel (0 a <1 en trazos, 2.0 fuera) para pick_exact():
    así todas las variantes llevan la misma cantidad de veta."""
    inside, chance, pos = _grain_fields(along, across, seed, length, row, period, row_period, thickness)
    return np.where(inside, chance * 0.999 + pos * 1.0e-6, 2.0)


def scatter(count, seed=0, period=64, min_distance=4, margin=0, tries=40):
    """`count` puntos enteros (U, V) con U + V par en una casilla periódica, a min_distance o más;
    margin deja libre el borde."""
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
    """Máscara de una forma (desplazamientos (du, dv) en la rejilla) en cada punto de scatter(), periódica."""
    iu = np.mod(np.asarray(iu), period)
    iv = np.mod(np.asarray(iv), period)
    mask = np.zeros(iu.shape, dtype=bool)
    for pu, pv in points:
        for du, dv in shape:
            mask |= (iu == (pu + du) % period) & (iv == (pv + dv) % period)
    return mask


def stamp_pixels(grid, points, shape=((0, 0),)):
    """Como stamp_points en px de pantalla (shape = (dx, dy)); lo que sale da la vuelta con grid.wrap."""
    mask = np.zeros(grid.mask.shape, dtype=bool)
    for px, py in points:
        for dx, dy in shape:
            wx, wy = grid.wrap(px + dx, py + dy)
            mask[wy, wx] = True
    return mask


def pixel_points(grid, count, seed=0, min_distance=4, margin=0):
    """Puntos de scatter() como pixeles (x, y) del lienzo (el izquierdo de cada dominó)."""
    points = []
    for pu, pv in scatter(count, seed, 64, min_distance, margin):
        if (pu + pv) % 2:
            pu = (pu + 1) % 64 if pu + 1 < 64 - margin else pu - 1
        points.append(grid.pixel_of(pu, pv))
    return points


def exact_levels(value, mask, counts, group=None, tie=None):
    """Reparte niveles por orden de `value` con una cantidad EXACTA por nivel (mismo brillo en cada variante).

    counts  cantidades por nivel de menor a mayor valor (entre 0 y 1, fracción); el resto va al nivel len(counts)
    group   pixeles con el mismo número cuentan juntos (grid.domino: de a 2 px)
    tie     desempate (p. ej. pattern.bayer); por defecto el orden de lectura
    Devuelve int16 con el nivel de cada pixel (−1 fuera de mask).
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
    """Máscara de los `count` pixeles (o grupos) de mask con menor `value`."""
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
    """Cuántos pixeles de mask no tienen vecino (4 direcciones) de su nivel: el ruido suelto prohibido."""
    count = 0
    same = np.zeros(levels.shape, dtype=bool)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        same |= np.roll(np.roll(levels, dy, axis=0), dx, axis=1) == levels
    count = int((mask & ~same).sum())
    return count
