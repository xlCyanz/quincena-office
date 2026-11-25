"""Silla de malla de Quincena Office (blanca con malla gris), hecha con Moana. Ver ../_chair_kit.py y
../_chairs.py.

Base de estrella blanca, cojín grafito con costura y respaldo medio de malla con marco blanco, sin
apoyabrazos. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/chair_mesh/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _chair_kit import BACK_GROUP, ChairSpec, beam, main, slab  # noqa: E402
from _chairs import C, GRAPHITE, PLASTIC, STAR, WHITE, base, cushion, mesh_back  # noqa: E402

SEAT_CY = 15.5
HALF = 7.5


def bracket():
    """El soporte en «J», blanco como el marco."""
    return [
        beam("bracket", BACK_GROUP, "white", (C, SEAT_CY + 3.0, 14.5), (C, 25.3, 22.0), 1.0, 1.2),
        slab("post", BACK_GROUP, "white", C, 25.6, 1.1, 0.8, 0.3, 20.5, 38.0, lit=True),
    ]


def model():
    return [*base(star="white", column="white", wheel="graphite"), *cushion("graphite", SEAT_CY, HALF, 16.0, 13.0), *bracket(),
            mesh_back(7.0, 24.0, 26.5, 28.0, 52.0, mat="white")]


SPEC = ChairSpec(
    name="chair_mesh",
    mats={m.name: m for m in (WHITE, GRAPHITE, PLASTIC)},
    model=model,
    shadow=[("disc", C, C, STAR + 0.6, 0, 6), ("disc", C, SEAT_CY, 8.0, 16, 24), ("bar", 11.0, 25.0, 21.0, 25.0, 2.4, 28, 52)],
)

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
