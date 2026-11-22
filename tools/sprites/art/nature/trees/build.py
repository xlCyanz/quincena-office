"""Árboles del mapa de Quincena Office (MapDecor/TreeView), hechos con Moana. Ver ../_tree_kit.py.

    tree_0   roble: copa ancha de tres masas sobre un tronco grueso con horqueta
    tree_1   copa ovalada en punta sobre un tronco corto
    tree_2   abeto de faldones
    tree_3   cerezo: copa redonda con flores rosadas
    tree_4   copa de bola sobre un tronco fino
    tree_5   ciprés: columna alta y angosta
    tree_6   árbol joven: tronco fino con horqueta y copa redonda chica
    tree_7   copa de pirámide ancha con horqueta

Lienzo 128×256, apoyo (64, 224), planta 1×1; la copa puede salir del rombo a los lados, nunca abajo.
Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/nature/trees/build.py [--out DIR] [--preview]
"""

import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import numpy as np  # noqa: E402
from _tree_kit import (LEAVES, Ramp, Sprite, ball, ball_profile, capsule, cone, crown, dots, drop_profile,  # noqa: E402
                       main)

FIR = Ramp("fir", ("#17662FFF", "#1F7A38FF", "#2C8F42FF", "#36A04AFF", "#3FAE52FF", "#58C462FF", "#7AD676FF"),
           "#0F4A22FF")
BARK = Ramp("bark", ("#5C3418FF", "#7A4A28FF", "#9A6238FF", "#B47A48FF"), "#3A1E0CFF")
FLOWER = Ramp("flower", ("#EE8FB2FF", "#FBD3E2FF"), "#6A2440FF")
RAMPS = {r.name: r for r in (LEAVES, FIR, BARK, FLOWER)}
C = 0.5
SIZE = (128, 256)


def trunk(top: float, radius: float, foot: float = 1.35) -> list:
    """Tronco que se angosta, con el pie un poco más ancho."""
    return [capsule("trunk", "bark", (C, C, 0), (C, C, top), radius, radius * 0.8),
            capsule("trunk", "bark", (C, C, 0), (C, C, 10), radius * foot, radius)]


def branches(start: tuple, tips: list, radius: float) -> list:
    return [capsule(f"branch{k}", "bark", start, tip, radius, radius * 0.6) for k, tip in enumerate(tips)]


def tree(name: str, shapes: list, shadow: list, max_colors: int = 13) -> Sprite:
    return Sprite(name, SIZE, (1, 1), shapes, shadow, max_colors=max_colors)


def oak() -> list:
    s = trunk(64, 0.085)
    s += branches((C, C, 52), [(0.78, 0.42, 96), (0.24, 0.62, 92), (C, C, 100)], 0.05)
    s += crown("crown", "leaves", (C, C, 0), ball_profile(0.48), 84, 184, 34, (0.1, 0.14), 4)
    s += crown("left", "leaves", (0.3, 0.72, 0), ball_profile(0.26), 82, 138, 12, (0.09, 0.12), 41)
    s += crown("right", "leaves", (0.74, 0.3, 0), ball_profile(0.26), 80, 136, 12, (0.09, 0.12), 42)
    s += crown("top", "leaves", (C, C, 0), ball_profile(0.32), 148, 212, 14, (0.09, 0.12), 43)
    return s


def ovate() -> list:
    return trunk(46, 0.055) + crown("crown", "leaves", (C, C, 0), drop_profile(0.43, 0.34, 1.7), 34, 202, 46,
                                    (0.09, 0.13), 5)


def fir() -> list:
    s = trunk(38, 0.07)
    count = 7
    rng = np.random.RandomState(23)
    for k in range(count):
        f = k / (count - 1)
        r0 = 0.5 - 0.36 * f
        z0 = 30 + 140 * f ** 0.95
        z1 = z0 + 46 - 14 * f
        look = dict(center=(C, C, z0 + 10), radius=r0 * 1.1, seed=20 + k)
        s.append(cone(f"tier{k}", "fir", C, C, z0 + 4, z1, r0 * 0.94, r0 * 0.25, bump=0.008, **look))
        lobes = int(8 + r0 * 22)
        for j in range(lobes):  # flecos del borde, de largo desparejo
            ang = 2 * math.pi * j / lobes + k * 0.5
            s.append(ball(f"tier{k}", "fir", (C + r0 * 0.9 * math.cos(ang), C + r0 * 0.9 * math.sin(ang),
                                              z0 + 8 - rng.uniform(0, 4)), rng.uniform(0.05, 0.065),
                          stretch=rng.uniform(1.15, 1.5), bump=0.004, **look))
    s.append(cone("tip", "fir", C, C, 186, 216, 0.08, 0.0, center=(C, C, 196), radius=0.12, bump=0.0, seed=30))
    return s


def cherry() -> list:
    s = trunk(80, 0.065)
    s += branches((C, C, 72), [(0.76, 0.5, 104), (0.28, 0.64, 102), (C, C, 108)], 0.04)
    leaves = crown("crown", "leaves", (C, C, 0), ball_profile(0.56), 90, 168, 44, (0.1, 0.13), 8)
    return s + leaves + dots("flower", "flower", leaves, 34, 21, (0.018, 0.024), min_z=104)


def ball_tree() -> list:
    return trunk(72, 0.045) + crown("crown", "leaves", (C, C, 0), ball_profile(0.52), 64, 162, 40, (0.1, 0.14), 14)


def cypress() -> list:
    return trunk(32, 0.055) + crown("crown", "leaves", (C, C, 0), drop_profile(0.27, 0.2, 2.1), 24, 214, 40,
                                    (0.07, 0.1), 15)


def young() -> list:
    s = trunk(74, 0.034, 1.2)
    s += branches((C, C, 68), [(0.7, 0.5, 110), (0.32, 0.62, 108), (C, C, 114)], 0.024)
    return s + crown("crown", "leaves", (C, C, 0), ball_profile(0.42), 104, 182, 28, (0.09, 0.12), 16)


def pyramid() -> list:
    s = trunk(56, 0.072)
    s += branches((C, C, 46), [(0.74, 0.48, 82), (0.28, 0.64, 80)], 0.045)
    return s + crown("crown", "leaves", (C, C, 0), drop_profile(0.58, 0.24, 1.0), 60, 212, 56, (0.1, 0.14), 17)


SPRITES = [
    tree("tree_0", oak(), [("disc", C, C, 0.46, 70, 180)]),
    tree("tree_1", ovate(), [("disc", C, C, 0.4, 30, 176)]),
    tree("tree_2", fir(), [("disc", C, C, 0.46, 18, 170)]),
    tree("tree_3", cherry(), [("disc", C, C, 0.46, 72, 146)], max_colors=16),
    tree("tree_4", ball_tree(), [("disc", C, C, 0.46, 46, 142)]),
    tree("tree_5", cypress(), [("disc", C, C, 0.28, 12, 186)]),
    tree("tree_6", young(), [("disc", C, C, 0.4, 88, 164)]),
    tree("tree_7", pyramid(), [("disc", C, C, 0.46, 54, 184)]),
]

if __name__ == "__main__":
    raise SystemExit(main(SPRITES, RAMPS, HERE, "los árboles"))
