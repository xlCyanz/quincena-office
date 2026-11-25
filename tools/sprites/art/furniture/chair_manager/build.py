"""Silla gerencial de Quincena Office (cuero gris grafito), hecha con Moana. Ver ../_chair_kit.py y
../_chairs.py.

Base de estrella de plástico, cojín de cuero, apoyabrazos y respaldo medio-alto acolchado. Desde el
repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/chair_manager/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _chair_kit import SEAT_GROUP, ChairSpec, main, slab  # noqa: E402
from _chairs import C, GRAPHITE, METAL, PLASTIC, STAR, base, bracket, cushion, padded_back  # noqa: E402

SEAT_CY = 15.5
HALF = 7.5
ARM_X = HALF + 1.4


def arms():
    out = []
    for side in (-1, 1):
        x = C + side * ARM_X
        out += [
            slab("arm_post", SEAT_GROUP, "plastic", x, SEAT_CY + 1.5, 0.7, 0.8, 0.3, 15.0, 31.0),
            slab("arm_pad", SEAT_GROUP, "plastic", x, SEAT_CY, 1.0, 5.0, 0.9, 30.5, 33.0, lit=True),
        ]
    return out


def model():
    return [*base(), *cushion("graphite", SEAT_CY, HALF, 16.0, 13.0), *arms(), *bracket(SEAT_CY, 42.0),
            padded_back("graphite", 7.5, 23.0, 27.0, 28.0, 58.0)]


SPEC = ChairSpec(
    name="chair_manager",
    mats={m.name: m for m in (GRAPHITE, PLASTIC, METAL)},
    model=model,
    shadow=[("disc", C, C, STAR + 0.6, 0, 6), ("disc", C, SEAT_CY, 8.0, 16, 24), ("bar", 10.5, 25.0, 21.5, 25.0, 2.6, 28, 58)],
)

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
