"""Mesa de reuniones redonda de Quincena Office (2×2, simétrica: una sola imagen), hecha con Moana.
Ver ../_boxes.py.

Tapa de madera naranja con vetas suaves y un aro más oscuro cerca del canto, sobre una columna y un pie
gris oscuro. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/meeting_table/build.py [--out DIR] [--preview]
"""

import math
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import ramp  # noqa: E402
from _chair_kit import CELL, PieceSpec, cylinder, main_piece  # noqa: E402

GROUP = "table"
C = 32.0  # centro de la planta de 64 × 64 unidades
TOP, SLAB = 40.0, 5.0
RADIUS = 25.6
EDGE = round((C - math.sqrt(RADIUS ** 2 - (CELL / 2) ** 2)) / CELL, 4)

WOOD = ramp("wood", "#DF823DFF", "#C26B24FF", "#894522FF", "#3C1300FF", "#EDA85DFF", "#743B0EFF")
COLUMN = ramp("column", "#4A4F55FF", "#383B40FF", "#2C2F33FF", "#141619FF", "#6B7177FF", "#1F2125FF")


def top_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Aro oscuro cerca del canto y vetas onduladas a lo largo de x."""
    out = tone.copy()
    cap = mz > TOP - 0.3
    r = np.hypot(mx - C, my - C) / RADIUS
    grain = cap & (r < 0.84) & (np.mod(my + 1.6 * np.sin(mx / 6.0) + 0.8 * np.sin(mx / 2.3 + my), 7.0) < 0.55)
    out[grain] = "wood.upper"
    out[cap & (r > 0.86) & (r < 0.9)] = "wood.dark"
    return out


def model() -> list:
    return [
        cylinder("foot", GROUP, "column", C, C, 11.5, 0.0, 3.0, sides=24, r_top=9.6, lit=True),
        cylinder("column", GROUP, "column", C, C, 2.9, 3.0, TOP - SLAB, sides=10),
        cylinder("top", GROUP, "wood", C, C, RADIUS, TOP - SLAB, TOP, sides=40, texture=top_texture, lit=True),
    ]


SPEC = PieceSpec(
    name="meeting_table",
    mats={m.name: m for m in (WOOD, COLUMN)},
    model=model,
    shadow=[("disc", C, C, 22.4, 0, TOP)],
    size=(2, 2),
    # Canto de la tapa redonda frente al centro de cada casilla vecina (a media casilla del eje).
    edges=(EDGE,) * 4,
    canvas=(256, 192),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
