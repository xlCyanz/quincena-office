"""Planta grande de Quincena Office, hecha con Moana. Ver ../_chair_kit.py y ../_plants.py.

Arbolito de hojas ovaladas en espiral alrededor de un tallo, en maceta blanca con franja roja sobre su
plato. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/plant_large/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _chair_kit import PieceSpec, cylinder, main_piece  # noqa: E402
from _plants import CERAMIC, GROUP, LEAF, RED, SOIL, C, leaf, pot  # noqa: E402

COUNT = 13
TWEAKS = {9: {"bend": 24, "elevation": -12, "twist": -20}, 6: {"bend": 16, "elevation": 6},
          12: {"elevation": -8, "bend": 8}}


def model():
    solids = [cylinder("saucer", GROUP, "ceramic", C, C, 6.0, 0.0, 3.0, sides=14, r_top=7.0)]
    solids += pot("ceramic", 4.0, 6.0, 28.0, 6.0, z0=2.0, band=(9.0, 15.0, "red"))
    solids.append(cylinder("stem", GROUP, "soil", C, C, 0.8, 26.0, 50.0, sides=6))
    for k in range(COUNT):
        f = k / (COUNT - 1)
        p = {"elevation": 32 + 48 * f, "bend": 0.6 * (80 - 44 * f), "twist": 22 if k % 2 else -22}
        for key, change in TWEAKS.get(k, {}).items():
            p[key] += change
        solids.append(leaf(f"leaf{k}", (C, C, 38 + 24 * f), 200 + 137.5 * k, p["elevation"], p["bend"],
                           13.5 - 2.5 * f, 8.0 - 1.5 * f, p["twist"], "oval", level=0 if f < 0.3 else (1 if f < 0.7 else 2)))
    return solids


SPEC = PieceSpec(
    name="plant_large",
    mats={m.name: m for m in (LEAF, CERAMIC, RED, SOIL)},
    model=model,
    shadow=[("disc", C, C, 7.0, 0, 0), ("disc", C, C, 8.3, 50, 70)],
    max_colors=20,  # maceta de dos colores, tierra y hojas (la de antes tenía 21)
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
