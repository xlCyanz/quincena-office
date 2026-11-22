"""Mesa de ping pong de Quincena Office (2×2, cuatro rotaciones), hecha con Moana. Ver ../_boxes.py.

Tablero verde con líneas blancas en el borde y a lo largo, red blanca con sus dos postes, patas de metal
oscuro, dos paletas rojas de mango de madera y una pelota. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/ping_pong/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, faces, ramp  # noqa: E402
from _chair_kit import PieceSpec, cylinder, main_piece  # noqa: E402

GROUP = "pong"
TOP = 24.0
TABLE = (3.2, 60.8, 14.4, 49.6, TOP - 2, TOP)

GREEN = ramp("green", "#2F8A52FF", "#23683EFF", "#1C5331FF", "#0E2A18FF", "#6DAD86FF", "#143C23FF")
WHITE = ramp("white", "#F2F6F2FF", "#D3D8D9FF", "#B3B5B6FF", "#2F3437FF", "#FFFFFFFF", "#808488FF")
METAL = ramp("metal", "#4A4F55FF", "#383B40FF", "#2C2F33FF", "#141619FF", "#6B7177FF", "#1F2125FF")
RED = ramp("red", "#D8434AFF", "#B0343AFF", "#8E2A2FFF", "#3A0C0AFF", "#F07A7FFF", "#5A1919FF")
WOOD = ramp("wood", "#DF823DFF", "#C26B24FF", "#894522FF", "#3C1300FF", "#EDA85DFF", "#743B0EFF")


def table_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Líneas blancas: borde de la tapa y la línea del medio a lo largo."""
    x0, x1, y0, y1 = TABLE[:4]
    f = faces(mx, my, mz, *TABLE)
    out = tone.copy()
    edge = (mx < x0 + 1.0) | (mx > x1 - 1.0) | (my < y0 + 1.0) | (my > y1 - 1.0)
    mid = np.abs(my - (y0 + y1) / 2) < 0.5
    out[f.top & (edge | mid)] = "white.top"
    return out


def paddle(k: int, cx: float, cy: float, hx: float, hy: float) -> list:
    return [cylinder(f"paddle{k}", GROUP, "red", cx, cy, 3.0, TOP, TOP + 1, sides=10, lit=True),
            box(f"handle{k}", GROUP, "wood", cx + hx - 0.8, cx + hx + 0.8, cy + hy - 0.8, cy + hy + 0.8, TOP, TOP + 1)]


def model() -> list:
    s = [box("legs", GROUP, "metal", x, x + 2.6, y, y + 2.6, 0, TOP - 2) for x in (8.0, 53.0) for y in (17.6, 43.2)]
    s.append(box("table", GROUP, "green", *TABLE, texture=table_texture, lit=True))
    s.append(box("net", GROUP, "white", 31.5, 32.5, TABLE[2] - 1, TABLE[3] + 1, TOP, TOP + 6, lit=True))
    for k, y in enumerate((TABLE[2] - 1.5, TABLE[3] + 0.5)):
        s.append(box(f"post{k}", GROUP, "metal", 31.2, 32.8, y, y + 1, TOP - 2, TOP + 7))
    s += paddle(0, 17.6, 25.6, -3.0, -2.0)
    s += paddle(1, 46.0, 40.0, 3.0, 2.0)
    s.append(cylinder("ball", GROUP, "white", 40.0, 24.0, 0.8, TOP, TOP + 1.5, sides=6))
    return s


SPEC = PieceSpec(
    name="ping_pong",
    mats={m.name: m for m in (GREEN, WHITE, METAL, RED, WOOD)},
    model=model,
    shadow=[("bar", 12.8, 32.0, 51.2, 32.0, 16.0, 0, TOP)],
    max_colors=26,
    size=(2, 2),
    canvas=(256, 192),
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
