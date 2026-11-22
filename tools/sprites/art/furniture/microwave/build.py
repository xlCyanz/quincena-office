"""Microondas de Quincena Office (1×1, cuatro rotaciones) sobre el mueble bajo de cocina, hecho con Moana.
Ver ../_kitchen.py y ../_boxes.py.

Cuerpo negro de esquinas redondeadas sobre cuatro patitas, con rejillas en los costados. Al frente, en
relieve, la puerta de vidrio con marco del color del cuerpo (se ve el horno con su luz, el plato giratorio y dos
reflejos) con su manija de
metal, y el panel con la hora en verde, el teclado y el botón de abrir. El frente mira a −y en rotación 0.
Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/microwave/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, colors, faces, ramp, rect  # noqa: E402
from _chair_kit import PieceSpec, main_piece, slab  # noqa: E402
from _kitchen import MATS, SHADOW, WORK_TOP, counter  # noqa: E402

GROUP = "microwave"
T = WORK_TOP
X0, X1, Y0, Y1 = 5.4, 26.6, 9.0, 24.6
FY0 = 7.6  # frente de la puerta y el panel
Z0, Z1 = T + 1.0, T + 25.0
PANEL_X = (5.9, 11.4)  # a la derecha mirando el frente
DOOR_X = (11.8, 26.1)

CASE = ramp("case", "#3B3F45FF", "#2C2F34FF", "#232629FF", "#0E0F10FF", "#5C5F66FF", "#17191BFF")
STEEL = ramp("steel", "#C6CDD2FF", "#A3ABB1FF", "#7E878EFF", "#1F2326FF", "#EEF2F4FF", "#5C646AFF")
DETAIL = colors("detail", "#0E0F10FF", light="#E9D9A6FF", top="#2A3640FF", upper="#7D93A3FF", left="#8C96A0FF",
                right="#6FE08AFF", dark="#3C4B57FF")
PLATE, GLASS, SHINE, KEYS, DIGITS, MESH = ("detail.light", "detail.top", "detail.upper", "detail.left",
                                           "detail.right", "detail.dark")


def rounded(part: str, mat: str, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, r: float,
            bevel: float, **kw: object):
    return slab(part, GROUP, mat, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, r, z0, z1,
                bevel=bevel, bevel_z=1.0, lit=True, **kw)


def body_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Rejillas de ranuras en los costados, hacia atrás."""
    out = tone.copy()
    side = (mx < X0 + 0.3) | (mx > X1 - 0.3)
    slots = side & (my > Y1 - 9.0) & (my < Y1 - 2.0) & (mz > Z1 - 7.0) & (mz < Z1 - 3.0)
    out[slots & (np.mod(my * 2.0, 2.0) < 1.0)] = "case.dark"
    return out


def door_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Puerta de vidrio con marco del color del cuerpo: adentro se ve el horno (más claro arriba, donde está
    la luz), el plato giratorio y dos reflejos en el vidrio."""
    f = faces(mx, my, mz, *DOOR_X, FY0, Y0 + 0.5, Z0 + 0.5, Z1 - 0.5)
    out = tone.copy()
    win = f.front & rect(f, 4, -3, 3, f.height - 3)
    out[f.front & rect(f, 3, -2, 2, f.height - 2) & ~win] = "case.dark"  # junta del vidrio
    out[win] = GLASS
    out[win & (f.b >= f.height - 7)] = MESH  # techo del horno, con luz
    mid = 4 + (f.width - 7) / 2
    plate = win & (((f.a - mid) / 7.0) ** 2 + ((f.b - 5.0) / 2.0) ** 2 < 1.0)
    out[plate] = PLATE
    out[plate & (f.b < 4.0)] = KEYS  # canto del plato
    for off, half in ((0.0, 0.8), (4.0, 0.5)):
        out[win & (np.abs(f.a + f.b * 0.8 - f.height * 0.9 - off) < half)] = SHINE
    return out


def panel_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Hora en verde, teclado de 3 × 3, botón verde de empezar y botón de abrir abajo."""
    f = faces(mx, my, mz, *PANEL_X, FY0, Y0 + 0.5, Z0 + 0.5, Z1 - 0.5)
    out = tone.copy()
    h = f.height
    out[f.front & rect(f, 1, -1, h - 4, h - 1)] = GLASS
    out[f.front & rect(f, 2, -2, h - 3, h - 2) & (np.mod(f.a, 2) < 1)] = DIGITS
    keys = f.front & rect(f, 1, -1, 4, h - 5) & (np.mod(f.a - 1, 3) < 2) & (np.mod(f.b - 4, 2) < 1)
    out[keys] = KEYS
    out[f.front & rect(f, -4, -1, 4, 5)] = DIGITS  # empezar
    out[f.front & rect(f, 1, -1, 1, 3)] = "case.light"  # botón de abrir
    return out


def model() -> list:
    s = counter()
    s += [box(f"foot{k}", GROUP, "case", x, x + 1.5, y, y + 1.5, T, Z0) for k, (x, y) in
          enumerate(((6.5, 10.0), (24.0, 10.0), (6.5, 22.0), (24.0, 22.0)))]
    s += [
        rounded("body", "case", X0, X1, Y0, Y1, Z0, Z1, 1.5, 0.6, texture=body_texture),
        rounded("door", "case", *DOOR_X, FY0, Y0 + 0.5, Z0 + 0.5, Z1 - 0.5, 0.6, 0.3, texture=door_texture),
        rounded("panel", "case", *PANEL_X, FY0, Y0 + 0.5, Z0 + 0.5, Z1 - 0.5, 0.6, 0.3, texture=panel_texture),
        box("handle", GROUP, "steel", 12.3, 13.4, FY0 - 1.2, FY0, Z0 + 4.0, Z1 - 4.0, lit=True),
    ]
    return s


SPEC = PieceSpec(
    name="microwave",
    mats={m.name: m for m in (*MATS, CASE, STEEL, DETAIL)},
    model=model,
    shadow=[SHADOW],
    max_colors=30,
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
