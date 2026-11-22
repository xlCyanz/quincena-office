"""Planta chica de Quincena Office, hecha con Moana. Ver ../_chair_kit.py y ../_plants.py.

Mata de hojas anchas en tres pisos sobre una maceta de barro. Es un mueble chico: va en un cuarto de la
casilla y se dibuja ya a su tamaño final (el diseño de la planta al 60 %). Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/plant_small_q/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _chair_kit import PieceSpec, main_piece, slab  # noqa: E402
from _plants import CLAY, GROUP, LEAF, SOIL, C, leaf, pot  # noqa: E402

S = 0.6
TOP = 22 * S
# Pisos de hojas: (hojas, elevación, caída, largo, ancho, nivel, giro, torsión); largo y ancho en unidades.
RINGS = ((5, 14, 50, 9.0, 6.4, 0, 20, 12), (4, 48, 48, 8.4, 6.0, 1, 56, -12), (2, 82, 46, 7.2, 5.6, 2, 10, 10))


def model():
    solids = pot("clay", 10 * S / 2, 14 * S / 2, TOP, 3.0, soil=False)
    # Corazón de la mata: tapa la boca de la maceta con verde en sombra.
    solids.append(slab("heart", GROUP, "leaf", C, C, 4.9, 4.9, 2.5, TOP - 1, TOP + 3, bevel=1.0, bevel_z=1.5))
    crown = (C, C, TOP + 1)
    n = 0
    for count, elevation, bend, length, width, level, turn, twist in RINGS:
        for k in range(count):
            solids.append(leaf(f"leaf{n}", crown, turn + 360.0 * k / count, elevation, bend, length, width,
                               twist if k % 2 else -twist, "round", level=level))
            n += 1
    return solids


SPEC = PieceSpec(
    name="plant_small_q",
    mats={m.name: m for m in (LEAF, CLAY, SOIL)},
    model=model,
    shadow=[("disc", C, C, 3.8, 0, 0), ("disc", C, C, 5.1, 18, 24)],
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
