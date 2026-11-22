# Árboles del mapa (MapDecor/TreeView). Copas de una pieza con contorno solo en la silueta, pintadas
# en pantalla con manchas de hojas sobre una luz general (arriba a la izquierda). pieces/bushes.py
# usa las mismas funciones.
#
#   tree_0               roble: copa ancha e irregular sobre un tronco grueso con horqueta
#   tree_1               copa ovalada en punta sobre un tronco corto
#   tree_2               abeto de faldones con flecos que cuelgan
#   tree_3               cerezo: copa redonda con flores rosadas
#   tree_4               copa de bola sobre un tronco fino
#   tree_5               ciprés: columna alta y angosta
#   tree_6               árbol joven: tronco fino con horqueta y copa redonda chica
#   tree_7               copa de pirámide ancha con horqueta
#   <cada uno>_shadow
#   tree_<n>_fall_1..16  hojas que caen (ciclo que empalma); mismo lienzo y apoyo que el árbol
#   _sheets/trees.png
#
# Lienzo 128×256, apoyo (64, 224), planta 1×1. La copa puede salir del rombo a los lados, nunca abajo.
import os

import numpy as np
from PIL import Image

import iso
import palette as pal
import sheet
from pieces import _shadow

BARK = pal.style_ramp("9a6238", outline="3a1e0c", name="tree_bark")
BARK_LINE = BARK.add("7a4a28")
GREEN = pal.style_ramp("86b934", side="5f9627", shadow="4a811f", outline="2a5214", deep="366a19", soft="73a82e",
                       light="9dcb3c", shine="b4d84a", name="tree_leaves")
FIR = pal.style_ramp("3fae52", side="2c8f42", shadow="1f7a38", outline="0f4a22", deep="17662f", soft="36a04a",
                     light="58c462", shine="7ad676", name="tree_leaves_fir")
FLOWER = pal.style_ramp("ee8fb2", light="fbd3e2", outline="6a2440", name="tree_flowers")
PETAL = FLOWER.add("f5b5cc")

WIDTH, HEIGHT = 128, 256
ORIGIN = (64.0, 192.0)
ANCHOR = (64, 224)
FRAMES = 16
SCREEN_W = 90.5  # px de ancho en pantalla por casilla de radio


def canvas():
    return iso.Canvas(WIDTH, HEIGHT, ORIGIN, size=(1, 1), kind="tree", anchor=ANCHOR)


def screen(c, x, y, z):
    """Pixel del lienzo de un punto del modelo (lienzos sin girar)."""
    return c.origin[0] + (x - y) * 64.0, c.origin[1] + (x + y) * 32.0 - z


# ---------------------------------------------------------------------------- pintura de hojas

def quantize(v):
    """Valor de luz (≈ −1.6 a 1.6) → paso de la rampa."""
    v = np.asarray(v)
    return np.select([v > 1.0, v > 0.52, v > 0.02, v > -0.36, v > -0.76, v > -1.16],
                     [pal.SHINE, pal.LIGHT, pal.BASE, pal.SOFT, pal.LEFT, pal.RIGHT], pal.DEEP).astype(np.int16)


def blotch_field(c, seed, radius=(3.6, 7.0), spacing=24.0):
    """Manchas de hojas: círculos chicos encimados, cada uno claro arriba a la izquierda."""
    rng = np.random.RandomState(seed)
    X, Y = c.X, c.Y
    hh, ww = X.shape
    field = np.zeros((hh, ww), dtype=np.float64)
    pad = c.pad
    for _ in range(int(hh * ww / spacing)):
        bx, by = rng.uniform(-pad, ww - pad), rng.uniform(-pad, hh - pad)
        br = rng.uniform(*radius)
        x0, x1 = max(0, int(bx + pad - br - 1)), min(ww, int(bx + pad + br + 2))
        y0, y1 = max(0, int(by + pad - br - 1)), min(hh, int(by + pad + br + 2))
        if x0 >= x1 or y0 >= y1:
            continue
        dx = (X[y0:y1, x0:x1] + 0.5 - bx) / br
        dy = (Y[y0:y1, x0:x1] + 0.5 - by) / br
        d = np.sqrt(dx * dx + dy * dy)
        n = -(0.6 * dx + 0.8 * dy)  # 1 = hacia la luz
        value = 0.46 * n + 0.12 - 0.32 * (d > 0.72) * (n < 0.3)
        win = field[y0:y1, x0:x1]
        field[y0:y1, x0:x1] = np.where(d < 1.0, value, win)
    return field


def general_light(c, sx, sy, rx, ry):
    """Luz general de una copa con centro (sx, sy) y radios (rx, ry) en px: clara arriba a la izquierda."""
    dx = (c.X + 0.5 - sx) / float(rx)
    dy = (c.Y + 0.5 - sy) / float(ry)
    return -(0.9 * dx + 1.0 * dy) - 0.12 - 0.6 * np.clip((dy - 0.35) / 0.5, 0, 1) - 0.35 * np.clip((dx - 0.45) / 0.5, 0, 1)  # panza a la sombra


def clean(index, passes=2):
    """Quita pixeles sueltos: sin vecino (de 8) de su tono, toma el del vecino de la izquierda."""
    index = np.asarray(index)
    for _ in range(passes):
        pad = np.pad(index, 1, mode="edge")
        h, w = index.shape
        same = np.zeros(index.shape, dtype=np.int16)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx or dy:
                    same += pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w] == index
        index = np.where(same == 0, pad[1:1 + h, 0:w], index)
    return index


def despeckle(c, passes=3):
    """Limpieza final: un pixel opaco sin vecino de su color toma el más repetido entre sus vecinos.
    No cambia la silueta."""
    arr = np.array(c.image.convert("RGBA"))
    h, w = arr.shape[:2]
    for _ in range(passes):
        opaque = arr[..., 3] == 255
        pad = np.pad(arr, ((1, 1), (1, 1), (0, 0)))
        same = np.zeros((h, w), dtype=np.int16)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx or dy:
                    q = pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
                    same += (q[..., 3] == 255) & (q[..., :3] == arr[..., :3]).all(-1)
        ys, xs = np.nonzero(opaque & (same == 0))
        if not len(ys):
            break
        for y, x in zip(ys, xs):
            around = [tuple(pad[y + 1 + dy, x + 1 + dx]) for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                      if (dx or dy) and pad[y + 1 + dy, x + 1 + dx, 3] == 255]
            if around:
                arr[y, x] = max(set(around), key=around.count)
    c.result = Image.fromarray(arr, "RGBA")
    return c.result


def painted(index_map):
    """Textura que devuelve un mapa de índices ya pintado en pantalla (sin pixeles sueltos)."""
    index_map = clean(index_map)
    return lambda ctx: index_map


def lump(c, ramp, x, y, z, r, tex, part=None, name=None, stretch=1.0):
    """Un bulto de la silueta: esfera cortada en el piso, pintada con `tex`. Devuelve el id de pieza."""
    return c.ellipsoid(x, y, z, r, r, r * iso.Z_METRIC * stretch, ramp, clip_z=(0, 9999), tex=tex, name=name,
                       part=part)


def ball(radius):
    return lambda t: radius * np.sqrt(max(0.0, 1.0 - (2.0 * t - 1.0) ** 2))


def drop(radius, peak=0.3, power=1.5):
    """Perfil en gota: lo más ancho a `peak` de la altura y de ahí se cierra hasta la punta."""
    def fn(t):
        if t < peak:
            return radius * np.sqrt(max(0.0, 1.0 - ((peak - t) / peak) ** 2))
        return radius * max(0.0, 1.0 - ((t - peak) / (1.0 - peak)) ** power)
    return fn


def dome(radius):
    return lambda t: radius * np.sqrt(max(0.0, 1.0 - t * t))


def crown_paint(c, ramp, z0, z1, profile, seed, center=(0.5, 0.5), radius=(3.2, 6.2)):
    """Textura pintada para una copa que va de z0 a z1 con ese perfil."""
    widest = max(profile(t) for t in np.linspace(0, 1, 41))
    sx, sy = screen(c, center[0], center[1], (z0 + z1) / 2.0)
    light = general_light(c, sx, sy, widest * SCREEN_W + 4, (z1 - z0) / 2.0 + 6)
    return painted(quantize(light + blotch_field(c, seed, radius)))


def crown(c, ramp, z0, z1, profile, count, size, seed, center=(0.5, 0.5), name="crown", part=None, tex=None):
    """Copa de revolución con `count` bultos sobre el perfil (profile(t) = radio en casillas, t de 0 a 1).
    Devuelve (id de pieza, textura, bultos (x, y, z, r))."""
    rng = np.random.RandomState(seed)
    cx, cy = center
    tex = tex or crown_paint(c, ramp, z0, z1, profile, seed, center)
    widest = max(profile(t) for t in np.linspace(0, 1, 41))
    span = float(z1 - z0)
    pid = part
    blobs = []

    def add(x, y, z, r, keep=True):
        nonlocal pid
        got = lump(c, ramp, x, y, z, r, tex, part=pid, name=name if pid is None else None)
        pid = got if pid is None else pid
        if keep:
            blobs.append((x, y, z, r))

    for t in np.linspace(0.0 if z0 <= 0 else 0.04, 0.96, 18):  # relleno, sin pasar de la altura de la copa
        low = 9.0 if z0 <= 0 else span * t / iso.Z_METRIC + 0.02  # apoyada en el piso: se corta ahí
        r = min(profile(t) * 0.95, span * (1.0 - t) / iso.Z_METRIC + 0.02, low)
        if r > 0.012:
            add(cx, cy, z0 + t * span, r, False)
    placed = 0
    while placed < count:
        t = rng.uniform(0.0, 0.96)
        if rng.uniform(0, widest) > max(profile(t), widest * 0.15):
            continue
        theta = rng.uniform(0, 2 * np.pi)
        r = min(rng.uniform(*size), profile(t) * 0.9 + 0.012)  # hacia la punta, bultos chicos
        radial = max(profile(t) - r * 0.45, 0.0)
        add(cx + radial * np.cos(theta), cy + radial * np.sin(theta), z0 + t * span, r)
        placed += 1
    return pid, tex, blobs


def dot_tex(ctx):
    """Flor o fruto de dos tonos: luz arriba a la izquierda, su tono en lo demás."""
    return np.where(np.asarray(ctx.light) > 0.25, pal.LIGHT, pal.BASE)


def dots(c, ramp, blobs, center, count, seed, size=(0.03, 0.04), name="dots"):
    """Flores o frutos de 5 a 7 px sobre los bultos que miran a la vista."""
    rng = np.random.RandomState(seed)
    cx, cy, cz = center
    front = [b for b in blobs if (b[0] - cx) + (b[1] - cy) > 0.05] or blobs
    pid = None
    for _ in range(count):
        x, y, z, r = front[rng.randint(len(front))]
        out = np.array([x - cx, y - cy, (z - cz) / iso.Z_METRIC]) + np.array([0.5, 0.5, 0.2]) * 0.4 + \
            rng.uniform(-0.2, 0.2, 3)
        out = out / max(np.linalg.norm(out), 1e-6)
        fz = z + r * 1.05 * out[2] * iso.Z_METRIC
        if fz < 3:
            continue
        got = c.sphere(x + r * 1.05 * out[0], y + r * 1.05 * out[1], fz, rng.uniform(*size), ramp, outline=False,
                       shadow=False, tex=dot_tex, name=name if pid is None else None, part=pid)
        pid = got if pid is None else pid


# ---------------------------------------------------------------------------- tronco

def bark_side(ctx):
    """Corteza lisa con unas pocas vetas verticales."""
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    base = np.asarray(ctx.base).copy()
    lines = (np.mod(a * 3 + np.floor(b / 11.0) * 5, 11) == 0) & (np.mod(b, 11) > 3)
    t = np.asarray(ctx.t)
    base = np.where(t < -0.45, pal.lighter(base), base)  # luz a la izquierda
    base = np.where(t > 0.5, pal.darker(base), base)  # sombra a la derecha
    return np.where(lines, BARK_LINE, base)


def trunk(c, top, radius=0.06):
    pid = c.cylinder(0.5, 0.5, radius + 0.02, 0, 8, BARK, radius_top=radius, tex={"side": bark_side}, name="trunk")
    c.cylinder(0.5, 0.5, radius, 8, top, BARK, radius_top=radius * 0.82, tex={"side": bark_side}, part=pid)


def branches(c, start, tips, radius=2.2):
    """Horqueta: ramas del tronco hacia la copa."""
    pid = None
    for tip in tips:
        got = c.capsule(start, tip, radius, BARK, name="branches" if pid is None else None, part=pid)
        pid = got if pid is None else pid


# ---------------------------------------------------------------------------- árboles

def tree_oak():
    c = canvas()
    trunk(c, 58, 0.1)
    branches(c, (0.5, 0.5, 50), [(0.82, 0.42, 96), (0.2, 0.62, 92), (0.5, 0.5, 98)], 4.5)
    tex = crown_paint(c, GREEN, 76, 210, ball(0.6), 4)
    pid, _, _ = crown(c, GREEN, 82, 182, ball(0.5), 160, (0.06, 0.09), seed=4, tex=tex)
    # Copas menores a los lados y arriba.
    crown(c, GREEN, 80, 134, ball(0.27), 60, (0.06, 0.085), seed=41, center=(0.28, 0.76), part=pid, tex=tex)
    crown(c, GREEN, 78, 132, ball(0.27), 60, (0.06, 0.085), seed=42, center=(0.77, 0.28), part=pid, tex=tex)
    crown(c, GREEN, 146, 210, ball(0.33), 80, (0.06, 0.085), seed=43, center=(0.5, 0.5), part=pid, tex=tex)
    return c


def tree_ovate():
    c = canvas()
    trunk(c, 46, 0.055)
    crown(c, GREEN, 32, 200, drop(0.44, 0.34, 1.7), 210, (0.06, 0.088), seed=5)
    return c


def fir_tex(c, r0, z0, z1, k):
    """Faldón del abeto: filas de puntas redondeadas separadas por arcos oscuros; la parte de arriba
    queda a la sombra del faldón de encima."""
    sx0, _ = screen(c, 0.5, 0.5, 0)
    X, Y = c.X, c.Y
    w, h = 10, 8
    row = np.floor_divide(Y, h)
    lx = np.mod(X + np.mod(row, 2) * 5 + k * 3, w) - (w - 1) / 2.0
    ly = np.mod(Y, h)
    curve = (h - 1) - 3.5 * (lx / (w / 2.0)) ** 2
    line = np.abs(ly - curve) < 0.75  # borde de abajo de cada punta
    lit = (ly < curve - 3.0) & (lx < 1.0)
    side = -(X + 0.5 - sx0) / (r0 * SCREEN_W)

    def tex(ctx):
        f = (np.asarray(ctx.z) - z0) / float(z1 - z0)
        v = 1.0 * side + 0.1 + 0.2 * lit - 0.55 * line - 1.1 * np.clip((f - 0.45) / 0.4, 0, 1)
        return clean(quantize(v), 4)
    return tex


def tree_fir():
    c = canvas()
    trunk(c, 38, 0.075)
    count = 8
    rng = np.random.RandomState(23)
    for k in range(count):
        f = k / float(count - 1)
        r0 = 0.52 - 0.39 * f
        z0 = 28 + 146 * f ** 0.95
        z1 = z0 + 42 - 13 * f
        tex = fir_tex(c, r0, z0 - 6, z1, k)
        tier = c.cylinder(0.5, 0.5, r0 * 0.96, z0 + 6, z1, FIR, radius_top=r0 * 0.3, tex=tex, name="tier_%d" % k)
        lobes = int(12 + r0 * 34)
        for j in range(lobes):  # flecos del borde, de largo desparejo
            ang = 2 * np.pi * j / lobes + k * 0.5
            r = rng.uniform(0.034, 0.05)
            lump(c, FIR, 0.5 + r0 * 0.92 * np.cos(ang), 0.5 + r0 * 0.92 * np.sin(ang), z0 + 7 - rng.uniform(0, 5), r, tex,
                 part=tier, stretch=rng.uniform(1.6, 2.6))
    tip = fir_tex(c, 0.08, 170, 220, 0)
    c.cylinder(0.5, 0.5, 0.06, 190, 212, FIR, radius_top=0.008, tex=tip, name="tip")
    return c


def tree_cherry():
    c = canvas()
    trunk(c, 78, 0.07)
    branches(c, (0.5, 0.5, 70), [(0.78, 0.5, 102), (0.26, 0.66, 100), (0.5, 0.5, 106)], 3.0)
    _, _, blobs = crown(c, GREEN, 88, 166, ball(0.58), 210, (0.06, 0.088), seed=8)
    dots(c, FLOWER, [b for b in blobs if b[2] > 108], (0.5, 0.5, 127), 30, 21, name="flowers")
    return c


def tree_ball():
    c = canvas()
    trunk(c, 72, 0.045)
    crown(c, GREEN, 62, 160, ball(0.54), 210, (0.06, 0.088), seed=14)
    return c


def tree_cypress():
    c = canvas()
    trunk(c, 32, 0.06)
    crown(c, GREEN, 24, 212, drop(0.28, 0.2, 2.1), 190, (0.05, 0.07), seed=15)
    return c


def tree_young():
    c = canvas()
    trunk(c, 72, 0.035)
    branches(c, (0.5, 0.5, 68), [(0.72, 0.5, 110), (0.3, 0.62, 108), (0.5, 0.5, 114)], 1.8)
    crown(c, GREEN, 102, 180, ball(0.43), 160, (0.055, 0.08), seed=16)
    return c


def tree_pyramid():
    c = canvas()
    trunk(c, 54, 0.075)
    branches(c, (0.5, 0.5, 46), [(0.76, 0.48, 82), (0.26, 0.64, 80)], 3.4)
    crown(c, GREEN, 58, 210, drop(0.6, 0.24, 1.0), 260, (0.06, 0.09), seed=17)
    return c


# ---------------------------------------------------------------------------- hojas que caen

def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# Forma de la hoja según el giro (aletea al caer): pixeles (dx, dy) con 0 = color, 1 = borde oscuro.
LEAF_SHAPES = (
    ((0, 0, 0), (1, 0, 0), (2, 0, 1), (1, 1, 1)),  # de lado
    ((0, 0, 0), (1, 1, 0), (2, 1, 1)),  # inclinada
    ((0, 0, 0), (0, 1, 1)),  # de canto
    ((0, 1, 0), (1, 0, 0), (2, 0, 1), (1, 1, 1)),  # al revés
)

LEAF_GREEN = ("9dcb3c", "4a811f")
LEAF_YELLOW = ("e0c040", "7a6418")
FALLING = {
    # árbol: (colores (cara, borde), zona de salida (x0, x1, y0, y1) en el lienzo, cuántas)
    "tree_0": ([LEAF_GREEN, LEAF_YELLOW, ("86b934", "366a19")], (18, 110, 70, 110), 6),
    "tree_1": ([LEAF_GREEN, LEAF_YELLOW], (32, 96, 90, 150), 5),
    "tree_2": ([("9a6a2e", "4a3010"), ("58c462", "1f7a38")], (24, 104, 140, 170), 3),
    "tree_3": ([("f5b5cc", "b0587c"), ("fbd3e2", "c06a90"), ("ee8fb2", "8a2f55")], (22, 106, 84, 110), 7),
    "tree_4": ([LEAF_GREEN, LEAF_YELLOW], (24, 104, 86, 126), 5),
    "tree_5": ([LEAF_GREEN, LEAF_YELLOW], (44, 84, 110, 170), 3),
    "tree_6": ([LEAF_GREEN, LEAF_YELLOW], (32, 96, 70, 96), 4),
    "tree_7": ([LEAF_GREEN, LEAF_YELLOW, ("86b934", "366a19")], (20, 108, 90, 130), 6),
}


def ground_point(rng):
    """Un punto del piso dentro de la planta, en pixeles del lienzo (lejos del borde del rombo)."""
    u, v = rng.uniform(0.18, 0.82), rng.uniform(0.18, 0.82)
    return ORIGIN[0] + (u - v) * 64.0, ORIGIN[1] + (u + v) * 32.0


def fall_frames(base, name, seed):
    """Cuadros de la caída: cada hoja cae el 80 % del ciclo y queda el resto en el piso."""
    colors, (x0, x1, y0, y1), count = FALLING[name]
    rng = np.random.RandomState(seed)
    leaves = []
    for k in range(count):
        gx, gy = ground_point(rng)
        sx = float(np.clip(gx + rng.uniform(-14, 14), x0, x1))
        leaves.append({"phase": (k + rng.uniform(0, 0.6)) / count, "start": (sx, rng.uniform(y0, y1)),
                       "land": (gx, gy), "sway": rng.uniform(3, 6), "turns": rng.randint(1, 3),
                       "color": colors[k % len(colors)], "spin": rng.randint(4)})
    frames = []
    for f in range(FRAMES):
        img = base.copy()
        px = img.load()
        for leaf in leaves:
            s = (f / float(FRAMES) + leaf["phase"]) % 1.0
            fall = 0.8
            if s < fall:
                p = s / fall
                x = leaf["start"][0] + (leaf["land"][0] - leaf["start"][0]) * p + \
                    leaf["sway"] * np.sin(p * np.pi * 2 * leaf["turns"])
                y = leaf["start"][1] + (leaf["land"][1] - leaf["start"][1]) * (p ** 1.2)
                shape = LEAF_SHAPES[(f + leaf["spin"]) % len(LEAF_SHAPES)]
            else:
                x, y = leaf["land"]
                shape = LEAF_SHAPES[0]
            face, edge = hex_rgb(leaf["color"][0]), hex_rgb(leaf["color"][1])
            xi, yi = int(round(x)), int(round(y))
            for dx, dy, dark in shape:
                qx, qy = xi + dx - 1, yi + dy
                if 0 <= qx < WIDTH and 0 <= qy < HEIGHT:
                    px[qx, qy] = (edge if dark else face) + (255,)
        frames.append(img)
    return frames


# ---------------------------------------------------------------------------- principal

TREES = (
    ("tree_0", tree_oak, [("disc", 0.5, 0.5, 0.46, 70, 180)]),
    ("tree_1", tree_ovate, [("disc", 0.5, 0.5, 0.4, 30, 176)]),
    ("tree_2", tree_fir, [("disc", 0.5, 0.5, 0.46, 18, 170)]),
    ("tree_3", tree_cherry, [("disc", 0.5, 0.5, 0.46, 72, 146)]),
    ("tree_4", tree_ball, [("disc", 0.5, 0.5, 0.46, 46, 142)]),
    ("tree_5", tree_cypress, [("disc", 0.5, 0.5, 0.28, 12, 186)]),
    ("tree_6", tree_young, [("disc", 0.5, 0.5, 0.4, 88, 164)]),
    ("tree_7", tree_pyramid, [("disc", 0.5, 0.5, 0.46, 54, 184)]),
)


def build(out_dir):
    files = []
    items = []
    for k, (name, fn, shapes) in enumerate(TREES):
        c = fn()
        c.finish()
        despeckle(c)
        files.append(iso.save(c, out_dir, name))
        files.append(_shadow.save_shadow(c, out_dir, name + "_shadow", shapes))
        items.append((name, sheet.on_background(c.image, scale=1)))
        base = c.image.convert("RGBA")
        for f, frame in enumerate(fall_frames(base, name, 100 + k), start=1):
            files.append(iso.save(frame, out_dir, "%s_fall_%d" % (name, f), kind="tree_frame",
                                  base=name + ".png", frame=f, frames=FRAMES, animation="fall",
                                  anchor=list(ANCHOR)))
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    sheet.contact_sheet(items, columns=4, scale=3).save(os.path.join(folder, "trees.png"))
    return files
