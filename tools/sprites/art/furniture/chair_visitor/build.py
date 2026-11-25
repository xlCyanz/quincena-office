"""Silla de visita (confidente) de Quincena Office (tela verde), hecha con Moana. Ver ../_chair_kit.py y
../_chairs.py.

Cuatro patas fijas de metal, sin ruedas; cojín verde con costura y respaldo acolchado sobre dos postes de
metal. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/chair_visitor/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _chair_kit import BACK_GROUP, SEAT_GROUP, ChairSpec, cylinder, main, slab  # noqa: E402
from _chairs import C, GREEN, METAL, PLASTIC, cushion, padded_back  # noqa: E402

SEAT_CY = 15.5
HALF = 7.5
LEG = 6.0  # de la pata al centro, en x e y
BACK_Y = 22.5


def legs():
    return [cylinder("leg", SEAT_GROUP, "metal", C + sx * LEG, SEAT_CY + sy * LEG, 0.9, 0.0, 15.0, sides=8, lit=True)
            for sx in (-1, 1) for sy in (-1, 1)]


def back():
    posts = [slab("back_post", BACK_GROUP, "metal", C + sx * 5.5, BACK_Y + 1.6, 0.7, 0.7, 0.3, 17.0, 44.0)
             for sx in (-1, 1)]
    return [*posts, padded_back("green", 7.0, BACK_Y, BACK_Y + 3.0, 30.0, 52.0)]


def model():
    return [*legs(), *cushion("green", SEAT_CY, HALF, 16.0, 14.0), *back()]


SPEC = ChairSpec(
    name="chair_visitor",
    mats={m.name: m for m in (GREEN, PLASTIC, METAL)},
    model=model,
    shadow=[("bar", C - LEG, SEAT_CY - LEG, C + LEG, SEAT_CY + LEG, 1.0, 0, 15), ("bar", C + LEG, SEAT_CY - LEG, C - LEG, SEAT_CY + LEG, 1.0, 0, 15),
            ("disc", C, SEAT_CY, 8.0, 16, 24), ("bar", 10.0, 24.0, 22.0, 24.0, 2.4, 30, 52)],
)

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
