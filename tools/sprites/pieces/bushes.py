# Arbustos y setos del mapa, con los bultos de hojas de pieces/trees.py.
#
#   bush_0               arbusto redondo
#   bush_1               arbusto chico, más alto que ancho
#   bush_2               arbusto bajo y ancho
#   bush_3..5            los mismos con frutos rojos, frutos azules y flores naranjas
#   hedge_cube           seto recortado en cubo (1×1)
#   hedge_long_r0, r1    seto recto de 2×1 (dos giros)
#   hedge_corner_r0..r3  seto en esquina (L) dentro de 2×2
#   <cada uno>_shadow
#   _sheets/bushes.png
#
# Lienzos de mueble (128×128, 192×128 y 256×192) con kind "bush" (sin caras lisas).
import numpy as np

import iso
import palette as pal
from pieces._kit import Saver, g
import sheet
from pieces import _shadow
from pieces.trees import GREEN, blotch_field, crown, despeckle, dome, dots, lump, painted, quantize

BERRY_RED = pal.style_ramp("d6452e", outline="5a140a", name="bush_berries_red")
BERRY_BLUE = pal.style_ramp("3fa6d8", outline="12405e", name="bush_berries_blue")
BLOOM = pal.style_ramp("f08a2a", outline="6a3206", name="bush_flowers_orange")
KIND = "bush"
HEDGE_TOP = 40


# ---------------------------------------------------------------------------- arbustos

BUSHES = (
    # nombre, radio, alto, bultos, tamaño de bulto, semilla
    ("bush_0", 0.4, 44, 110, (0.055, 0.08), 31),
    ("bush_1", 0.29, 46, 80, (0.05, 0.075), 32),
    ("bush_2", 0.44, 28, 110, (0.05, 0.075), 33),
)
DOTS = ((BERRY_RED, 3), (BERRY_BLUE, 4), (BLOOM, 5))


def bush(index, dotted=None):
    name, radius, top, count, size, seed = BUSHES[index]
    c = iso.Canvas.furniture((1, 1), top, 0, kind=KIND)
    _, _, blobs = crown(c, GREEN, 0, top, dome(radius), count, size, seed, name="bush")
    if dotted is not None:
        dots(c, dotted, blobs, (0.5, 0.5, top * 0.3), 16, seed + 50, size=(0.028, 0.036))
    return c


# ---------------------------------------------------------------------------- setos

def hedge(c, boxes, seed):
    """Seto recortado: cajas (x0, x1, y0, y1) de alto HEDGE_TOP con bultos en caras y tapa.
    Tonos: tapa clara, cara a la luz (+y en pantalla) media, la otra oscura."""
    rng = np.random.RandomState(seed)
    field = blotch_field(c, seed, radius=(3.0, 5.5), spacing=18.0)
    tones = {"top": painted(quantize(0.62 + field)), "left": painted(quantize(-0.3 + field)),
             "right": painted(quantize(-0.95 + field))}
    step = 0.115
    pid = None
    for x0, x1, y0, y1 in boxes:
        got = c.box(g(x0 + 0.05), g(x1 - 0.05), g(y0 + 0.05), g(y1 - 0.05), 0, HEDGE_TOP - 4, GREEN,
                    tex=tones["left"], name="hedge" if pid is None else None, part=pid, flat=False)
        pid = got if pid is None else pid

    def buried(x, y):
        return any(bx0 + 0.04 < x < bx1 - 0.04 and by0 + 0.04 < y < by1 - 0.04 for bx0, bx1, by0, by1 in boxes)

    def put(x, y, z, nx, ny, top):
        r = rng.uniform(0.06, 0.08)
        px, py = x - nx * r * 0.6, y - ny * r * 0.6
        pz = z - (r * 0.6 * iso.Z_METRIC if top else 0)
        w0 = c.to_world(px, py)
        w1 = c.to_world(px + nx, py + ny)
        face = "top" if top else ("right" if w1[0] - w0[0] > 0.5 else "left")
        lump(c, GREEN, px + rng.uniform(-0.015, 0.015), py + rng.uniform(-0.015, 0.015), pz + rng.uniform(-1.5, 1.5),
             r, tones[face], part=pid)

    for x0, x1, y0, y1 in boxes:
        nx = max(2, int(round((x1 - x0) / step)))
        ny = max(2, int(round((y1 - y0) / step)))
        xs = np.linspace(x0, x1, nx + 1)
        ys = np.linspace(y0, y1, ny + 1)
        for z in np.arange(4, HEDGE_TOP - 3, 7):  # caras
            for x in xs:
                for y, n in ((y0, -1), (y1, 1)):
                    if not buried(x, y + n * 0.02):
                        put(x, y, z, 0, n, False)
            for y in ys[1:-1]:
                for x, n in ((x0, -1), (x1, 1)):
                    if not buried(x + n * 0.02, y):
                        put(x, y, z, n, 0, False)
        for x in xs:  # tapa
            for y in ys:
                put(min(max(x, x0 + 0.04), x1 - 0.04), min(max(y, y0 + 0.04), y1 - 0.04), HEDGE_TOP, 0, 0, True)


def hedge_cube():
    c = iso.Canvas.furniture((1, 1), HEDGE_TOP, 0, kind=KIND)
    hedge(c, [(0.14, 0.86, 0.14, 0.86)], 61)
    return c


def hedge_long(rotation):
    c = iso.Canvas.furniture((2, 1), HEDGE_TOP, rotation, kind=KIND)
    hedge(c, [(0.12, 1.88, 0.16, 0.84)], 62)
    return c


def hedge_corner(rotation):
    c = iso.Canvas.furniture((2, 2), HEDGE_TOP, rotation, kind=KIND)
    hedge(c, [(0.12, 1.88, 0.16, 0.84), (0.16, 0.84, 0.84, 1.88)], 63)
    return c


# ---------------------------------------------------------------------------- principal

class CleanSaver(Saver):
    """Saver con la limpieza final de pixeles sueltos de los árboles."""

    def keep(self, c, name, shapes, **meta):
        c.finish()
        despeckle(c)
        self.files.append(iso.save(c, self.out_dir, name, **meta))
        self.files.append(_shadow.save_shadow(c, self.out_dir, name + "_shadow", shapes))
        self.items.append((name, sheet.on_background(c.image, scale=1)))


def build(out_dir):
    s = CleanSaver(out_dir)
    for k, (name, radius, top, _count, _size, _seed) in enumerate(BUSHES):
        s.keep(bush(k), name, [("disc", 0.5, 0.5, radius + 0.04, 0, top)])
    for k, (ramp, target) in enumerate(DOTS):
        _n, radius, top = BUSHES[k][:3]
        s.keep(bush(k, ramp), "bush_%d" % target, [("disc", 0.5, 0.5, radius + 0.04, 0, top)])
    s.keep(hedge_cube(), "hedge_cube", [("bar", 0.3, 0.5, 0.7, 0.5, 0.26, 0, HEDGE_TOP)])
    for rotation in (0, 1):
        s.keep(hedge_long(rotation), "hedge_long_r%d" % rotation, [("bar", 0.3, 0.5, 1.7, 0.5, 0.24, 0, HEDGE_TOP)])
    for rotation in range(4):
        s.keep(hedge_corner(rotation), "hedge_corner_r%d" % rotation,
               [("bar", 0.3, 0.5, 1.7, 0.5, 0.24, 0, HEDGE_TOP), ("bar", 0.5, 0.5, 0.5, 1.7, 0.24, 0, HEDGE_TOP)])
    return s.sheet("bushes")
