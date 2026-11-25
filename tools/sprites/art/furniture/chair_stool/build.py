"""Taburete de Quincena Office (mostaza), hecho con Moana. Ver ../_chair_kit.py y ../_chairs.py.

Base de estrella con ruedas, columna alta, aro para los pies, asiento redondo y un respaldo bajo; el de
la recepción. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/chair_stool/build.py [--out DIR] [--preview]
"""

import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _chair_kit import BACK_GROUP, SEAT_GROUP, ChairSpec, beam, cylinder, main, slab, upright  # noqa: E402
from _chairs import C, METAL, MUSTARD, STAR, SEAT_TOP, base  # noqa: E402

RING = 6.0  # radio del aro para los pies
RING_Z = 10.0


def foot_ring():
    """Aro de 8 tramos de metal con 4 rayos a la columna."""
    out = []
    pts = [(C + RING * math.cos(math.radians(22.5 + 45 * k)), C + RING * math.sin(math.radians(22.5 + 45 * k)))
           for k in range(8)]
    for k in range(8):
        a, b = pts[k], pts[(k + 1) % 8]
        out.append(beam("ring", SEAT_GROUP, "metal", (*a, RING_Z), (*b, RING_Z), 0.6, 0.7, lit=True))
    for k in (0, 2, 4, 6):
        out.append(beam("spoke", SEAT_GROUP, "metal", (C, C, RING_Z), (*pts[k], RING_Z), 0.5, 0.6))
    return out


def model():
    return [*base(column_top=17.0, star="metal", wheel="metal"), *foot_ring(),
            cylinder("pan", SEAT_GROUP, "metal", C, C, 6.0, 16.0, 18.5, sides=12),
            cylinder("seat", SEAT_GROUP, "mustard", C, C, 7.5, 18.0, SEAT_TOP, sides=14, r_top=6.8, lit=True),
            beam("bracket", BACK_GROUP, "metal", (C, 18.5, 16.0), (C, 24.6, 22.0), 1.0, 1.2),
            slab("post", BACK_GROUP, "metal", C, 24.9, 1.1, 0.8, 0.3, 20.5, 34.0, lit=True),
            upright("back", BACK_GROUP, "mustard", C, 6.0, 22.5, 25.5, 30.0, 40.0, 3.0, bevel=0.8, lit=True)]


SPEC = ChairSpec(
    name="chair_stool",
    mats={m.name: m for m in (MUSTARD, METAL)},
    model=model,
    shadow=[("disc", C, C, STAR + 0.6, 0, 6), ("disc", C, C, 7.5, 16, 24), ("bar", 11.0, 24.0, 21.0, 24.0, 2.0, 30, 40)],
)

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
