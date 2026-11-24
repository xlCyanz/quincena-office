"""Mostrador de la Recepción de Quincena Office (2×1, cuatro rotaciones), hecho con Moana. Ver ../_boxes.py.

Del lado de la recepcionista (el frente, −y en rotación 0): mesa de trabajo de tablero naranja sobre dos
cajoneras de metal gris de tres cajones, con papeles y un portalápices. Del lado del cliente: panel alto de
madera con dos ranuras y una placa con el logo, postes de aluminio en las esquinas y el mesón crema con un
timbre dorado y folletos. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/reception_counter/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, colors, faces, ramp, rect  # noqa: E402
from _chair_kit import CELL, PieceSpec, cylinder, main_piece, slab  # noqa: E402

GROUP = "counter"
DESK_TOP, SLAB = 34.0, 4.0
C, DESK_Y, DESK_HALF = 32.0, 9.6, (31.0, 8.0)  # tablero de quien atiende: centro x e y y medio ancho y fondo
PANEL = (1.2, 62.8, 18.0, 30.8, 0.0, 45.0)
LEDGE = (0.6, 63.4, 15.6, 31.4, 45.0, 48.0)
PEDESTALS = ((2.5, 13.5), (50.5, 61.5))
PED_Y = (2.8, 17.8)

WOOD = ramp("wood", "#DF823DFF", "#C26B24FF", "#894522FF", "#3C1300FF", "#EDA85DFF", "#5B2A10FF")
CREAM = ramp("cream", "#ECE5D6FF", "#D6CDB9FF", "#BCB29CFF", "#4A3F30FF", "#FFFFFFFF", "#9C917CFF")
METAL = ramp("metal", "#C3C8CAFF", "#A9AFB2FF", "#8F969AFF", "#2F3437FF", "#E6EAEBFF", "#6F777BFF")
BELL = ramp("bell", "#E0B84AFF", "#C49A34FF", "#9E7A22FF", "#4E3510FF", "#F7E08AFF", "#7A5A14FF")
DARK = ramp("dark", "#3B3F45FF", "#2C2F34FF", "#232629FF", "#0E0F10FF", "#5C5F66FF", "#17191BFF")
PAPER = ramp("paper", "#F4F6F6FF", "#DDE2E2FF", "#C4CBCCFF", "#4A4F55FF", "#FFFFFFFF", "#A9B0B3FF")
PEN_RED = colors("pen_red", "#5A1919FF", **{k: "#E2453CFF" for k in ("light", "top", "upper", "left", "right", "dark")})
PEN_BLUE = colors("pen_blue", "#1B3A52FF", **{k: "#4F9BD0FF" for k in ("light", "top", "upper", "left", "right", "dark")})


def pedestal_texture(x0: float, x1: float):
    """Tres cajones con su tirador y zócalo oscuro."""

    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        f = faces(mx, my, mz, x0, x1, *PED_Y, 0.0, DESK_TOP - SLAB)
        out = tone.copy()
        step = (f.height - 2) / 3.0
        for k in range(3):
            b0 = 2 + k * step
            out[f.front & rect(f, 1, -1, b0, b0 + 1)] = "metal.dark"
            out[f.front & (np.abs(f.a - f.width / 2) < 3) & (f.b >= b0 + step - 4) & (f.b < b0 + step - 3)] = \
                "metal.light"
        out[f.front & ((f.a < 1) | (f.a >= f.width - 1)) & (f.b >= 2)] = "metal.dark"
        out[f.sides & (f.b < 2)] = "dark.top"
        return out

    return texture


def panel_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Lado del cliente: dos ranuras a lo largo, placa con el logo en el medio y zócalo oscuro."""
    f = faces(mx, my, mz, *PANEL)
    out = tone.copy()
    for b in (13.0, f.height - 6):
        out[(f.back | f.left | f.right) & (f.b >= b) & (f.b < b + 1)] = "wood.dark"
    mid = f.width / 2
    plate = f.back & (np.abs(f.a - mid) < 11) & (f.b >= 20) & (f.b < 33)
    out[plate] = "metal.top"
    out[plate & ((np.abs(f.a - mid) >= 10) | (f.b < 21) | (f.b >= 32))] = "metal.dark"
    logo = plate & (np.hypot((f.a - mid) / 1.6, f.b - 26.5) < 3.4)
    out[logo] = "wood.top"
    out[logo & (np.hypot((f.a - mid) / 1.6, f.b - 26.5) < 1.6)] = "metal.top"
    out[f.sides & (f.b < 3)] = "wood.dark"
    return out


def ledge_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Filo claro del canto de adentro del mesón."""
    out = tone.copy()
    out[(mz > LEDGE[5] - 0.3) & (my < LEDGE[2] + 0.8)] = "cream.light"
    return out


def model() -> list:
    s = []
    for k, (x0, x1) in enumerate(PEDESTALS):
        s.append(box(f"pedestal{k}", GROUP, "metal", x0, x1, *PED_Y, 0.0, DESK_TOP - SLAB, lit=True,
                     texture=pedestal_texture(x0, x1)))
    s.append(slab("desk", GROUP, "wood", C, DESK_Y, *DESK_HALF, 0.8, DESK_TOP - SLAB, DESK_TOP, lit=True))
    s.append(box("panel", GROUP, "wood", *PANEL, texture=panel_texture))
    s += [box(f"trim{k}", GROUP, "metal", x, x + 1.5, y, y + 1.5, 0.0, LEDGE[4], lit=True)
          for k, (x, y) in enumerate(((0.8, 17.4), (61.7, 17.4), (0.8, 29.7), (61.7, 29.7)))]
    s.append(slab("ledge", GROUP, "cream", 32.0, (LEDGE[2] + LEDGE[3]) / 2, 31.4, (LEDGE[3] - LEDGE[2]) / 2, 1.0,
                  LEDGE[4], LEDGE[5], lit=True, texture=ledge_texture))
    top = LEDGE[5]
    s += [
        cylinder("bell_base", GROUP, "dark", 51.8, 26.9, 1.7, top, top + 1.0, sides=10, lit=True),
        cylinder("bell", GROUP, "bell", 51.8, 26.9, 1.4, top + 1.0, top + 3.5, sides=10, r_top=0.6, lit=True),
        cylinder("bell_knob", GROUP, "bell", 51.8, 26.9, 0.4, top + 3.5, top + 4.5, sides=6, lit=True),
        box("flyers", GROUP, "paper", 10.0, 15.0, 23.0, 28.0, top, top + 1.5, lit=True),
        box("flyer_top", GROUP, "paper", 10.6, 14.4, 23.6, 27.4, top + 1.5, top + 2.0),
        box("papers", GROUP, "paper", 36.0, 42.0, 5.0, 10.0, DESK_TOP, DESK_TOP + 1.5, lit=True),
        cylinder("pens", GROUP, "dark", 22.0, 8.0, 1.3, DESK_TOP, DESK_TOP + 4.0, sides=8, lit=True),
        box("pen_a", GROUP, "pen_red", 21.4, 22.0, 7.6, 8.2, DESK_TOP + 4.0, DESK_TOP + 6.5),
        box("pen_b", GROUP, "pen_blue", 22.2, 22.8, 8.0, 8.6, DESK_TOP + 4.0, DESK_TOP + 6.0),
    ]
    return s


SPEC = PieceSpec(
    name="reception_counter",
    mats={m.name: m for m in (WOOD, CREAM, METAL, BELL, DARK, PAPER, PEN_RED, PEN_BLUE)},
    model=model,
    shadow=[("bar", 8.0, 16.0, 56.0, 16.0, 14.4, 0, 48)],
    max_colors=40,
    size=(2, 1),
    edges=((DESK_Y - DESK_HALF[1]) / CELL, (C - DESK_HALF[0]) / CELL, 1 - LEDGE[3] / CELL, (C - DESK_HALF[0]) / CELL),
    canvas=(192, 160),
    rotations=(0, 1, 2, 3),
    painter=True,
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
