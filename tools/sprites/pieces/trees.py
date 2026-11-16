# Árboles del mapa (MapDecor/TreeView), con el estilo de tools/sprites/STYLE.md. Las copas son una sola pieza
# (el contorno, verde oscuro, va solo por la silueta) de borde ondulado, y se pintan en pantalla: muchas
# manchas redondas chicas y suaves, cada una con su luz arriba a la izquierda y su borde un tono más oscuro,
# sobre una luz general que va de claro (arriba a la izquierda) a oscuro (abajo a la derecha). Tronco marrón
# liso y fino, a veces con horqueta. Los arbustos y setos de pieces/bushes.py usan las mismas funciones.
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
#   tree_<n>_fall_1..16  hojas (o pétalos) que caen y quedan un momento en el piso; ciclo que empalma.
#                        Mismo lienzo y apoyo que el árbol; el manifiesto da base, frame y frames
#   _sheets/trees.png
#
# Lienzo 128×256 con el apoyo en (64, 224), planta 1×1 (sección 10 de docs/sprites_128.md). La copa puede
# pasar del rombo hacia los lados (hasta el borde del lienzo), nunca hacia abajo.
import os

import numpy as np
from PIL import Image

import iso
import palette as pal
import sheet
from pieces import chair_plant

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
    """Manchas de hojas sobre todo el lienzo: círculos chicos encimados (el último tapa); dentro de cada
    uno el valor sube hacia arriba a la izquierda y baja en el borde de abajo a la derecha."""
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
    return -(0.62 * dx + 1.0 * dy) - 0.1 - 0.55 * np.clip((dy - 0.4) / 0.5, 0, 1)  # panza a la sombra


def painted(index_map):
    """Textura que devuelve un mapa de índices ya pintado en pantalla."""
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
    """Copa de revolución: relleno a lo largo del eje y `count` bultos chicos por toda la superficie del
    perfil (profile(t) = radio en casillas a la altura t de 0 a 1), que le dan el borde ondulado. Una sola
    pieza pintada en pantalla. Devuelve (id de pieza, textura, bultos (x, y, z, r))."""
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
        if r > 0.025:
            add(cx, cy, z0 + t * span, r, False)
    placed = 0
    while placed < count:
        t = rng.uniform(0.0, 0.98)
        if rng.uniform(0, widest) > max(profile(t), widest * 0.15):
            continue
        theta = rng.uniform(0, 2 * np.pi)
        r = min(rng.uniform(*size), profile(t) * 0.8 + 0.03)
        radial = max(profile(t) - r * 0.45, 0.0)
        add(cx + radial * np.cos(theta), cy + radial * np.sin(theta), z0 + t * span, r)
        placed += 1
    return pid, tex, blobs


def dots(c, ramp, blobs, center, count, seed, size=(0.016, 0.024), name="dots"):
    """Flores o frutos: bolitas sobre los bultos que miran a la vista."""
    rng = np.random.RandomState(seed)
    cx, cy, cz = center
    front = [b for b in blobs if (b[0] - cx) + (b[1] - cy) > 0.05] or blobs
    pid = None
    for _ in range(count):
        x, y, z, r = front[rng.randint(len(front))]
        out = np.array([x - cx, y - cy, (z - cz) / iso.Z_METRIC]) + np.array([0.5, 0.5, 0.2]) * 0.4 + \
            rng.uniform(-0.2, 0.2, 3)
        out = out / max(np.linalg.norm(out), 1e-6)
        fz = z + r * 0.9 * out[2] * iso.Z_METRIC
        if fz < 3:
            continue
        got = c.sphere(x + r * 0.9 * out[0], y + r * 0.9 * out[1], fz, rng.uniform(*size), ramp, outline=False,
                       shadow=False, name=name if pid is None else None, part=pid)
        pid = got if pid is None else pid


# ---------------------------------------------------------------------------- tronco

def bark_side(ctx):
    """Corteza lisa con unas pocas vetas verticales."""
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    base = np.asarray(ctx.base).copy()
    lines = (np.mod(a * 3 + np.floor(b / 11.0) * 5, 11) == 0) & (np.mod(b, 11) > 3)
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
    trunk(c, 50, 0.1)
    branches(c, (0.5, 0.5, 44), [(0.82, 0.42, 84), (0.2, 0.62, 80), (0.5, 0.5, 86)], 4.5)
    big = ball(0.5)
    tex = crown_paint(c, GREEN, 66, 186, ball(0.6), 4)
    pid, _, _ = crown(c, GREEN, 72, 162, big, 150, (0.06, 0.09), seed=4, tex=tex)
    # Copas menores que le rompen la bola: una a cada lado y una arriba.
    crown(c, GREEN, 70, 120, ball(0.27), 60, (0.06, 0.085), seed=41, center=(0.28, 0.76), part=pid, tex=tex)
    crown(c, GREEN, 68, 118, ball(0.27), 60, (0.06, 0.085), seed=42, center=(0.77, 0.28), part=pid, tex=tex)
    crown(c, GREEN, 128, 186, ball(0.32), 70, (0.06, 0.085), seed=43, center=(0.5, 0.5), part=pid, tex=tex)
    return c


def tree_ovate():
    c = canvas()
    trunk(c, 40, 0.055)
    crown(c, GREEN, 26, 176, drop(0.42, 0.34, 1.7), 190, (0.06, 0.088), seed=5)
    return c


def fir_tex(c, r0, z0, z1, k):
    """Faldón del abeto: flecos que cuelgan (tiras verticales de tonos alternados con una rendija oscura
    entre ellas), más claro a la izquierda y con la parte de arriba a la sombra del piso de encima."""
    sx0, _ = screen(c, 0.5, 0.5, 0)
    X = c.X
    col = np.floor_divide(X + k * 2, 5)
    hashed = np.mod(col * 7 + k * 3, 5)
    stripe = np.select([hashed == 0, hashed == 3], [0.28, -0.22], 0.0)
    gap = np.mod(X + k * 2, 5) == 0
    side = -(X + 0.5 - sx0) / (r0 * SCREEN_W)

    def tex(ctx):
        f = (np.asarray(ctx.z) - z0) / float(z1 - z0)
        v = 0.95 * side + 0.1 + stripe - 0.3 * gap - 1.1 * np.clip((f - 0.42) / 0.4, 0, 1) + 0.25 * (f < 0.12)
        return quantize(v)
    return tex


def tree_fir():
    c = canvas()
    trunk(c, 26, 0.075)
    count = 7
    rng = np.random.RandomState(23)
    for k in range(count):
        f = k / float(count - 1)
        r0 = 0.5 - 0.37 * f
        z0 = 16 + 136 * f ** 0.95
        z1 = z0 + 40 - 12 * f
        tex = fir_tex(c, r0, z0 - 6, z1, k)
        tier = c.cylinder(0.5, 0.5, r0 * 0.96, z0 + 6, z1, FIR, radius_top=r0 * 0.3, tex=tex, name="tier_%d" % k)
        lobes = int(12 + r0 * 34)
        for j in range(lobes):  # flecos del borde, de largo desparejo
            ang = 2 * np.pi * j / lobes + k * 0.5
            r = rng.uniform(0.034, 0.05)
            lump(c, FIR, 0.5 + r0 * 0.92 * np.cos(ang), 0.5 + r0 * 0.92 * np.sin(ang), z0 + 7 - rng.uniform(0, 5), r, tex,
                 part=tier, stretch=rng.uniform(1.6, 2.6))
    tip = fir_tex(c, 0.08, 150, 196, 0)
    c.cylinder(0.5, 0.5, 0.06, 168, 189, FIR, radius_top=0.008, tex=tip, name="tip")
    return c


def tree_cherry():
    c = canvas()
    trunk(c, 62, 0.07)
    branches(c, (0.5, 0.5, 56), [(0.78, 0.5, 86), (0.26, 0.66, 84), (0.5, 0.5, 90)], 3.0)
    _, _, blobs = crown(c, GREEN, 70, 164, ball(0.52), 200, (0.06, 0.088), seed=8)
    dots(c, FLOWER, blobs, (0.5, 0.5, 117), 110, 21, name="flowers")
    return c


def tree_ball():
    c = canvas()
    trunk(c, 56, 0.045)
    crown(c, GREEN, 46, 142, ball(0.53), 200, (0.06, 0.088), seed=14)
    return c


def tree_cypress():
    c = canvas()
    trunk(c, 18, 0.06)
    crown(c, GREEN, 10, 186, drop(0.27, 0.2, 2.1), 170, (0.05, 0.07), seed=15)
    return c


def tree_young():
    c = canvas()
    trunk(c, 60, 0.035)
    branches(c, (0.5, 0.5, 56), [(0.72, 0.5, 96), (0.3, 0.62, 94), (0.5, 0.5, 100)], 1.8)
    crown(c, GREEN, 88, 164, ball(0.42), 150, (0.055, 0.08), seed=16)
    return c


def tree_pyramid():
    c = canvas()
    trunk(c, 46, 0.075)
    branches(c, (0.5, 0.5, 40), [(0.76, 0.48, 72), (0.26, 0.64, 70)], 3.4)
    crown(c, GREEN, 54, 186, drop(0.56, 0.28, 1.25), 240, (0.06, 0.09), seed=17)
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
    "tree_0": ([LEAF_GREEN, LEAF_YELLOW, ("86b934", "366a19")], (18, 110, 90, 130), 6),
    "tree_1": ([LEAF_GREEN, LEAF_YELLOW], (32, 96, 110, 160), 5),
    "tree_2": ([("9a6a2e", "4a3010"), ("58c462", "1f7a38")], (24, 104, 150, 176), 3),
    "tree_3": ([("f5b5cc", "b0587c"), ("fbd3e2", "c06a90"), ("ee8fb2", "8a2f55")], (22, 106, 100, 124), 7),
    "tree_4": ([LEAF_GREEN, LEAF_YELLOW], (24, 104, 100, 140), 5),
    "tree_5": ([LEAF_GREEN, LEAF_YELLOW], (44, 84, 130, 176), 3),
    "tree_6": ([LEAF_GREEN, LEAF_YELLOW], (32, 96, 90, 110), 4),
    "tree_7": ([LEAF_GREEN, LEAF_YELLOW, ("86b934", "366a19")], (20, 108, 110, 140), 6),
}


def ground_point(rng):
    """Un punto del piso dentro de la planta, en pixeles del lienzo (lejos del borde del rombo)."""
    u, v = rng.uniform(0.18, 0.82), rng.uniform(0.18, 0.82)
    return ORIGIN[0] + (u - v) * 64.0, ORIGIN[1] + (u + v) * 32.0


def fall_frames(base, name, seed):
    """Cuadros de la caída: cada hoja tiene su fase en el ciclo (así empalma): cae el 80 % del ciclo
    meciéndose de lado y queda el resto en el piso."""
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
    ("tree_3", tree_cherry, [("disc", 0.5, 0.5, 0.46, 70, 164)]),
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
        files.append(iso.save(c, out_dir, name))
        files.append(chair_plant.save_shadow(c, out_dir, name + "_shadow", shapes))
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
