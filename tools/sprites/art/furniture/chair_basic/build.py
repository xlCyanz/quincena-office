"""Silla básica de Quincena Office (roja), hecha con Moana. Ver ../_chair_kit.py y ../_chairs.py.

Base de estrella con ruedas, columna de metal, cojín rojo abultado con costura y respaldo acolchado con un
panel marcado, sobre un soporte en «J». Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/chair_basic/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _chair_kit import ChairSpec, main  # noqa: E402
from _chairs import C, METAL, PLASTIC, RED, STAR, base, bracket, cushion, padded_back  # noqa: E402

SEAT_CY = 15.5
HALF = 7.5


def model():
    return [*base(), *cushion("red", SEAT_CY, HALF, 16.0, 13.0), *bracket(SEAT_CY, 40.0),
            padded_back("red", 7.0, 23.0, 27.0, 28.0, 52.0)]


SPEC = ChairSpec(
    name="chair_basic",
    mats={m.name: m for m in (RED, PLASTIC, METAL)},
    model=model,
    shadow=[("disc", C, C, STAR + 0.6, 0, 6), ("disc", C, SEAT_CY, 8.0, 16, 24), ("bar", 11.0, 25.0, 21.0, 25.0, 2.6, 28, 52)],
)

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
