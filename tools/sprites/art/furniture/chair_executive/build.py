"""Sillón ejecutivo de Quincena Office (cuero café), hecho con Moana. Ver ../_chair_kit.py y ../_chairs.py.

Un sillón, no una silla: asiento ancho y grueso, brazos macizos de cuero pegados al asiento y respaldo ancho y
alto, capitoné (botones en rombo) con cabecera marcada, sobre una base de estrella negra. Desde el
repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/chair_executive/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _chair_kit import BACK_GROUP, SEAT_GROUP, ChairSpec, beam, main, slab, upright  # noqa: E402
from _chairs import BROWN, C, METAL, PLASTIC, SEAT_TOP, STAR, base, darker, rounded_sdf  # noqa: E402

SEAT_CY = 15.5
HALF = 9.5  # medio ancho del asiento
DEPTH = 7.5  # medio fondo: el frente queda donde el de las otras sillas, delante de las rodillas
ARM_X = HALF + 0.6  # centro de cada brazo
ARM_TOP = 33.0
BACK = (22.0, 28.0)  # y del frente y del fondo del respaldo
BACK_Z = (23.0, 70.0)
HEAD_Z = 58.0  # costura de la cabecera


def seat():
    def seam(x: np.ndarray, y: np.ndarray, z: np.ndarray, tone: np.ndarray) -> np.ndarray:
        d = rounded_sdf(x, y, C, SEAT_CY, HALF - 2.0, DEPTH, 3.0)
        return darker(tone, (z > SEAT_TOP - 0.5) & (d > -3.4) & (d < -2.6))

    return [slab("pan", SEAT_GROUP, "plastic", C, SEAT_CY, HALF - 2.0, DEPTH - 1.5, 2.5, 13.0, 15.0),
            slab("seat", SEAT_GROUP, "brown", C, SEAT_CY, HALF - 1.0, DEPTH, 3.0, 14.0, SEAT_TOP, bevel=1.5, bevel_z=3.0,
                 lit=True, texture=seam)]


def arms():
    """Brazos macizos: un bloque de cuero de la base del asiento hasta el codo, a todo lo largo."""
    return [slab("arm", SEAT_GROUP, "brown", C + side * ARM_X, SEAT_CY + 1.0, 1.9, DEPTH + 1.0, 1.6, 15.0, ARM_TOP,
                 bevel=0.9, bevel_z=1.5, lit=True) for side in (-1, 1)]


def back():
    y0, y1 = BACK
    z0, z1 = BACK_Z

    def tufted(x: np.ndarray, y: np.ndarray, z: np.ndarray, tone: np.ndarray) -> np.ndarray:
        front = y < y0 + 0.8
        head = front & (np.abs(z - HEAD_Z) < 0.7)  # costura de la cabecera
        # Botones en rombo: filas cada 6 px, columnas cada 4 unidades, una sí y una no corridas.
        row = np.round((z - 30.0) / 6.0)
        shift = np.where(row % 2 == 0, 0.0, 2.0)
        col = np.round((x - C - shift) / 4.0) * 4.0 + C + shift
        button = front & (z > 27.0) & (z < HEAD_Z - 3.0) & (np.abs(z - (30.0 + row * 6.0)) < 0.8) \
            & (np.abs(x - col) < 0.6) & (np.abs(x - C) < HALF - 2.5)
        return darker(darker(tone, head | button), button)

    return [beam("bracket", BACK_GROUP, "plastic", (C, SEAT_CY + 4.0, 14.0), (C, y1 - 1.0, 22.0), 1.0, 1.2),
            upright("back", BACK_GROUP, "brown", C, HALF + 0.5, y0, y1, z0, z1, 4.5, bevel=1.6, lit=True,
                    texture=tufted)]


def model():
    return [*base(), *seat(), *arms(), *back()]


SPEC = ChairSpec(
    name="chair_executive",
    mats={m.name: m for m in (BROWN, PLASTIC, METAL)},
    model=model,
    shadow=[("disc", C, C, STAR + 0.6, 0, 6), ("disc", C, SEAT_CY, 10.5, 14, 33),
            ("bar", C - HALF + 1.0, 25.0, C + HALF - 1.0, 25.0, 3.0, 23, 70)],
)

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
