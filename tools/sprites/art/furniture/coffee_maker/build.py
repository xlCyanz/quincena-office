"""Cafetera de Quincena Office (1×1, cuatro rotaciones) sobre el mueble bajo de cocina, hecha con Moana.
Ver ../_kitchen.py y ../_boxes.py.

Cuerpo negro de esquinas redondeadas en C: base con la placa caliente y los botones (luz roja de encendido),
columna con el visor de agua azul a un costado y cabezal con el portafiltro abajo. En el hueco, la jarra de
vidrio con café, tapa y asa negras; al lado, una taza blanca con café y su asa. El frente mira a −y en
rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/coffee_maker/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, colors, faces, ramp, rect  # noqa: E402
from _chair_kit import Mat, PieceSpec, cylinder, main_piece, slab  # noqa: E402
from _kitchen import MATS, SHADOW, WORK_TOP, counter  # noqa: E402

GROUP = "coffee"
T = WORK_TOP
X0, X1 = 8.5, 22.5
BASE = (X0, X1, 7.6, 21.5, T, T + 3.5)
COLUMN = (X0, X1, 15.5, 22.5, T + 3.5, T + 32.0)
HEAD = (X0, X1, 7.8, 15.5, T + 25.0, T + 32.0)
CX, CY = (X0 + X1) / 2, 11.6  # centro de la jarra
CARAFE_Z = (T + 3.5, T + 19.0)
COFFEE_Z = T + 11.0
MUG = (26.0, 9.2)

CASE = ramp("case", "#3B3F45FF", "#2C2F34FF", "#232629FF", "#0E0F10FF", "#5C5F66FF", "#17191BFF")
GLASS = Mat("glass", light="#E6F4FAFF", top="#A9D4E6FF", upper="#94C4D9FF", left="#7FB3CAFF", right="#6B9FB8FF",
            dark="#4A2410FF", ink="#1B3A52FF")
CUP = ramp("cup", "#F4F6F6FF", "#DDE2E2FF", "#C4CBCCFF", "#3D3B44FF", "#FFFFFFFF", "#6B3A1EFF")
DETAIL = colors("detail", "#0E0F10FF", light="#8FD3F0FF", top="#4F9BD0FF", upper="#E2453CFF", left="#6FE08AFF",
                right="#8C96A0FF", dark="#2A1A12FF")
WATER, WATER_DARK, RED_LED, GREEN_LED, BUTTON, BREW = ("detail.light", "detail.top", "detail.upper", "detail.left",
                                                      "detail.right", "detail.dark")


def rounded(part: str, mat: str, spec: tuple, r: float, **kw: object):
    x0, x1, y0, y1, z0, z1 = spec
    return slab(part, GROUP, mat, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, r, z0, z1,
                bevel=0.5, bevel_z=1.0, lit=True, **kw)


def base_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Placa caliente (aro claro bajo la jarra) y, al frente, dos botones y la luz roja."""
    f = faces(mx, my, mz, *BASE)
    out = tone.copy()
    r = np.hypot(mx - CX, my - CY)
    out[f.top & (r > 3.6) & (r < 4.3)] = "case.light"
    out[f.front & rect(f, -10, -8, 1, 2.5)] = BUTTON
    out[f.front & rect(f, -6, -4, 1, 2.5)] = BUTTON
    out[f.front & rect(f, 4, 6, 1, 2.5)] = RED_LED
    return out


def column_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Visor del depósito de agua en los costados, con marcas, y una ranura de vapor arriba."""
    f = faces(mx, my, mz, *COLUMN)
    out = tone.copy()
    side = (f.left | f.right) & (my > 16.5) & (my < 20.5)
    gauge = side & (mz > T + 8.0) & (mz < T + 22.0)
    out[gauge] = WATER_DARK
    out[gauge & (mz > T + 15.0)] = "case.dark"  # aire sobre el agua
    out[gauge & (mz <= T + 15.0) & (np.abs(my - 17.2) < 0.5)] = WATER
    out[gauge & (np.mod(mz - T, 3.0) < 0.6) & (my > 19.5)] = BUTTON  # marcas de tazas
    out[f.top & (my > 18.0) & (my < 20.0) & (mx > X0 + 3) & (mx < X1 - 3)] = "case.dark"  # tapa del depósito
    return out


def head_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Luz verde de listo y una franja de metal al frente del cabezal."""
    f = faces(mx, my, mz, *HEAD)
    out = tone.copy()
    out[f.front & rect(f, 2, -2, 2, 3)] = BUTTON
    out[f.front & rect(f, -5, -3, 4, 6)] = GREEN_LED
    return out


def carafe_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Café en la mitad de abajo de la jarra y marcas de nivel."""
    out = tone.copy()
    out[mz < COFFEE_Z] = BREW
    out[(mz >= COFFEE_Z) & (np.mod(mz - T, 3.0) < 0.6) & (mz < CARAFE_Z[1] - 2) & (my < CY - 2.0)] = "glass.light"
    return out


def mug_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    out = tone.copy()
    out[mz > T + 4.7] = "cup.dark"  # café visto desde arriba
    out[(mz > T + 3.0) & (mz < T + 3.8)] = "cup.right"  # franja de color de la taza
    return out


def model() -> list:
    return counter() + [
        rounded("base", "case", BASE, 1.5, texture=base_texture),
        rounded("column", "case", COLUMN, 1.5, texture=column_texture),
        rounded("head", "case", HEAD, 1.2, texture=head_texture),
        cylinder("filter", GROUP, "case", CX, CY, 3.0, T + 21.5, T + 25.0, sides=12, r_top=3.6),
        cylinder("carafe", GROUP, "glass", CX, CY, 3.6, *CARAFE_Z, sides=14, r_top=2.6, texture=carafe_texture,
                 lit=True),
        cylinder("lid", GROUP, "case", CX, CY, 2.8, CARAFE_Z[1], CARAFE_Z[1] + 1.5, sides=12, lit=True),
        box("carafe_handle", GROUP, "case", CX - 4.8, CX - 3.4, CY - 0.6, CY + 0.6, T + 7.0, T + 17.0),
        cylinder("mug", GROUP, "cup", *MUG, 1.7, T, T + 5.0, sides=10, texture=mug_texture),
        box("mug_handle", GROUP, "cup", MUG[0] + 1.5, MUG[0] + 2.4, MUG[1] - 0.4, MUG[1] + 0.4, T + 1.0, T + 4.0),
    ]


SPEC = PieceSpec(
    name="coffee_maker",
    mats={m.name: m for m in (*MATS, CASE, GLASS, CUP, DETAIL)},
    model=model,
    shadow=[SHADOW],
    max_colors=34,
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
