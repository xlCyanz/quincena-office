"""Arbustos y setos de Quincena Office, hechos con Moana. Ver ../_tree_kit.py.

    bush_0               arbusto redondo
    bush_1               arbusto chico, más alto que ancho
    bush_2               arbusto bajo y ancho
    bush_3..5            los mismos con frutos rojos, frutos azules y flores naranjas
    hedge_cube           seto recortado en cubo (1×1)
    hedge_long_r0, r1    seto recto de 2×1 (dos giros)
    hedge_corner_r0..r3  seto en esquina (L) dentro de 2×2

Lienzos de mueble según la planta, apoyados en el piso. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/nature/bushes/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _tree_kit import LEAVES, Ramp, Sprite, box, crown, dome_profile, dots, main  # noqa: E402

BERRY_RED = Ramp("berry_red", ("#D6452EFF", "#F07A5AFF"), "#5A140AFF")
BERRY_BLUE = Ramp("berry_blue", ("#3FA6D8FF", "#7CCBEEFF"), "#12405EFF")
BLOOM = Ramp("bloom", ("#F08A2AFF", "#F8B860FF"), "#6A3206FF")
RAMPS = {r.name: r for r in (LEAVES, BERRY_RED, BERRY_BLUE, BLOOM)}
C = 0.5
HEDGE_TOP = 40

BUSHES = (
    # nombre, radio (casillas), alto (px), bultos, tamaño de bulto, semilla, lienzo
    ("bush_0", 0.4, 44, 22, (0.08, 0.11), 31, (128, 160)),
    ("bush_1", 0.29, 46, 16, (0.07, 0.1), 32, (128, 160)),
    ("bush_2", 0.44, 28, 22, (0.07, 0.1), 33, (128, 128)),
)
DOTS = (("berry_red", 3), ("berry_blue", 4), ("bloom", 5))


def bush(index: int, name: str, dotted: str = "") -> Sprite:
    _, radius, top, count, size, seed, canvas = BUSHES[index]
    shapes = crown("bush", "leaves", (C, C, 0), dome_profile(radius * 0.88), 0, top, count, size, seed, low=0.3)
    if dotted:
        shapes += dots("dot", dotted, shapes, 16, seed + 50, (0.022, 0.03), min_z=6)
    return Sprite(name, canvas, (1, 1), shapes, [("disc", C, C, radius + 0.04, 0, top)], max_colors=11)


def rotate(x: float, y: float, r: int, w: int, d: int) -> tuple[float, float]:
    """Punto de la planta de w×d en rotación 0 llevado al giro r (como View.rot)."""
    return ((x, y), (d - y, x), (w - x, d - y), (y, w - x))[r]


def hedge(name: str, boxes: list, w: int, d: int, r: int, canvas: tuple, shadow: list) -> Sprite:
    """Seto recortado: cajas (x0, x1, y0, y1) de alto HEDGE_TOP con el borde rizado de hojas."""
    shapes = []
    for k, (x0, x1, y0, y1) in enumerate(boxes):
        a = rotate(x0, y0, r, w, d)
        b = rotate(x1, y1, r, w, d)
        lo = (min(a[0], b[0]), min(a[1], b[1]), -2.0)
        hi = (max(a[0], b[0]), max(a[1], b[1]), float(HEDGE_TOP))
        shapes.append(box("hedge", "leaves", lo, hi, 0.05, bump=0.012,
                          seed=60 + k))
    world = (w, d) if r % 2 == 0 else (d, w)
    rot_shadow = []
    for s in shadow:
        if s[0] == "bar":
            a, b = rotate(s[1], s[2], r, w, d), rotate(s[3], s[4], r, w, d)
            rot_shadow.append(("bar", a[0], a[1], b[0], b[1], *s[5:]))
    return Sprite(name, canvas, world, shapes, rot_shadow, max_colors=8)


LONG_SHADOW = [("bar", 0.3, 0.5, 1.7, 0.5, 0.24, 0, HEDGE_TOP)]
SPRITES = [bush(k, BUSHES[k][0]) for k in range(3)]
SPRITES += [bush(k, f"bush_{target}", ramp) for k, (ramp, target) in enumerate(DOTS)]
SPRITES.append(hedge("hedge_cube", [(0.14, 0.86, 0.14, 0.86)], 1, 1, 0, (128, 160),
                     [("bar", 0.3, 0.5, 0.7, 0.5, 0.26, 0, HEDGE_TOP)]))
SPRITES += [hedge(f"hedge_long_r{r}", [(0.12, 1.88, 0.16, 0.84)], 2, 1, r, (192, 192), LONG_SHADOW) for r in (0, 1)]
SPRITES += [hedge(f"hedge_corner_r{r}", [(0.12, 1.88, 0.16, 0.84), (0.16, 0.84, 0.5, 1.88)], 2, 2, r, (256, 224),
                  LONG_SHADOW + [("bar", 0.5, 0.5, 0.5, 1.7, 0.24, 0, HEDGE_TOP)]) for r in range(4)]

if __name__ == "__main__":
    raise SystemExit(main(SPRITES, RAMPS, HERE, "los arbustos y setos"))
