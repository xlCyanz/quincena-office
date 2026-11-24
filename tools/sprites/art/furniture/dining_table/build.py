"""Mesa de comedor de Quincena Office (2×1, cuatro rotaciones), hecha con Moana. Ver ../_boxes.py.

Mesa de madera naranja de tres tablones sobre cuatro patas, con un banco a cada lado (cuatro asientos).
El frente mira a −y en rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/dining_table/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, faces, ramp  # noqa: E402
from _chair_kit import CELL, PieceSpec, main_piece  # noqa: E402

GROUP = "dining"
TOP, BENCH = 28.0, 16.0
TABLE = (3.2, 60.8, 9.6, 22.4, TOP - 4, TOP)

WOOD = ramp("wood", "#DF823DFF", "#C26B24FF", "#894522FF", "#3C1300FF", "#EDA85DFF", "#743B0EFF")


def planks(spec: tuple, count: int):
    """Juntas entre ``count`` tablones a lo largo de x en la tapa."""
    x0, x1, y0, y1 = spec[:4]

    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        f = faces(mx, my, mz, *spec)
        out = tone.copy()
        step = (y1 - y0) / count
        seam = np.zeros(mx.shape, dtype=bool)
        for k in range(1, count):
            seam |= np.abs(my - (y0 + k * step)) < 0.3
        out[f.top & seam & (mx > x0 + 0.5) & (mx < x1 - 0.5)] = "wood.dark"
        return out

    return texture


def bench(k: int, y0: float, y1: float) -> list:
    seat = (6.4, 57.6, y0, y1, BENCH - 3, BENCH)
    s = [box(f"bench_legs{k}", GROUP, "wood", x, x + 2, y0 + 1, y1 - 1, 0, BENCH - 3) for x in (8.3, 53.8)]
    return s + [box(f"bench{k}", GROUP, "wood", *seat, texture=planks(seat, 2), lit=True)]


def model() -> list:
    s = [box("legs", GROUP, "wood", x, x + 2.6, y, y + 2.6, 0, TOP - 4) for x in (5.8, 55.7) for y in (11.5, 17.9)]
    s.append(box("top", GROUP, "wood", *TABLE, texture=planks(TABLE, 3), lit=True))
    return s + bench(0, 1.3, 6.4) + bench(1, 25.6, 30.7)


SPEC = PieceSpec(
    name="dining_table",
    mats={m.name: m for m in (WOOD,)},
    model=model,
    shadow=[("bar", 9.6, 16.0, 54.4, 16.0, 14.4, 0, TOP)],
    size=(2, 1),
    edges=(TABLE[2] / CELL, 2 - TABLE[1] / CELL, 1 - TABLE[3] / CELL, TABLE[0] / CELL),
    canvas=(192, 128),
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
