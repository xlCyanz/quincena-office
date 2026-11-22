"""Rack de servidores de Quincena Office (1×1, cuatro rotaciones), hecho con Moana. Ver ../_boxes.py.

Gabinete negro de esquinas redondeadas sobre cuatro ruedas, con rejillas en la tapa y en los costados (panel
hundido). Al frente, la puerta de malla en relieve con su manija cromada y, detrás, servidores de 1 y 2
unidades con luces verdes, celestes y ámbar, bahías de discos y un panel de cables de colores. El frente
mira a −y en rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/server_rack/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _bath import CHROME  # noqa: E402
from _boxes import box, colors, faces, frame, ramp, rect  # noqa: E402
from _chair_kit import PieceSpec, cylinder, main_piece, slab  # noqa: E402

GROUP = "rack"
X0, X1, Y0, Y1 = 7.0, 25.0, 6.4, 26.2
FY0 = 5.2
FOOT, TOP = 3.0, 88.0

RACK = ramp("rack", "#33383FFF", "#2A2E34FF", "#22262BFF", "#07090BFF", "#4A525BFF", "#15191DFF")
UNIT = colors("unit", "#07090BFF", light="#5B646EFF", top="#4A525BFF", upper="#0D1014FF", left="#3A4149FF",
              right="#2B3138FF", dark="#1B1F24FF")
LED = colors("led", "#07090BFF", light="#3FD0F0FF", top="#6FE08AFF", upper="#F0B030FF", left="#4F9BD0FF",
             right="#F0C030FF", dark="#E2453CFF")
HEIGHTS = (4, 7, 4, 4, 7, 4, 7, 4, 4, 7, 4, 4, 7, 4)


def door_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Marco de la puerta y, tras la malla, los servidores con sus luces, discos y cables."""
    f = faces(mx, my, mz, X0 + 0.4, X1 - 0.4, FY0, Y0 + 0.5, FOOT + 1.0, TOP - 1.5)
    out = tone.copy()
    bay = f.front & rect(f, 3, -3, 3, f.height - 3)
    out[bay] = "unit.upper"
    b0 = 4.0
    for k, uh in enumerate(HEIGHTS):
        unit = bay & rect(f, 4, -4, b0, b0 + uh - 1)
        out[unit] = "unit.top" if uh == 4 else "unit.left"
        row = (f.b >= b0 + uh - 3) & (f.b < b0 + uh - 2)
        out[unit & row & rect(f, 6, 8, 0, 999)] = "led.top"
        out[unit & row & rect(f, 9, 11, 0, 999)] = "led.light" if k % 3 else "led.upper"
        if uh == 7:  # bahías de discos
            out[unit & (f.b >= b0 + 1) & (f.b < b0 + 3) & rect(f, 13, -6, 0, 999) & (np.mod(f.a, 3) < 2)] = \
                "unit.dark"
        else:
            out[unit & row & rect(f, -12, -6, 0, 999) & (np.mod(f.a, 2) < 1)] = "unit.dark"
        if k == 6:  # panel de cables de colores
            cables = unit & (f.b >= b0) & (f.b < b0 + 3) & rect(f, 6, -6, 0, 999)
            pick = np.mod(np.floor(f.a / 2.0), 4)
            for j, tone_name in enumerate(("led.left", "led.right", "led.top", "led.dark")):
                out[cables & (pick == j) & (np.mod(f.a, 2) < 1)] = tone_name
        b0 += uh
    mesh = bay & (np.mod(f.a + f.b, 4) < 1)
    out[mesh & ~np.char.startswith(out.astype(str), "led")] = "unit.dark"
    return out


def body_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Panel hundido en los costados y atrás, con rejilla arriba; rejilla en la tapa."""
    f = faces(mx, my, mz, X0, X1, Y0, Y1, FOOT, TOP)
    out = tone.copy()
    panel = (f.left | f.right | f.back) & ~f.top
    out[panel & frame(f, 3, -3, 4, f.height - 5)] = "rack.dark"
    out[panel & rect(f, 6, -6, f.height - 16, f.height - 8) & (np.mod(f.b, 2) < 1)] = "rack.dark"
    out[f.top & rect(f, 6, -6, 6, -6) & (np.mod(f.b, 2) < 1)] = "rack.dark"
    return out


def model() -> list:
    s = [cylinder(f"wheel{k}", GROUP, "rack", x, y, 1.4, 0.0, FOOT, sides=8) for k, (x, y) in
         enumerate(((9.0, 8.4), (23.0, 8.4), (9.0, 24.2), (23.0, 24.2)))]
    s += [
        slab("body", GROUP, "rack", (X0 + X1) / 2, (Y0 + Y1) / 2, (X1 - X0) / 2, (Y1 - Y0) / 2, 1.2, FOOT, TOP,
             bevel=0.5, bevel_z=1.5, lit=True, texture=body_texture),
        slab("door", GROUP, "rack", (X0 + X1) / 2, (FY0 + Y0 + 0.5) / 2, (X1 - X0) / 2 - 0.4,
             (Y0 + 0.5 - FY0) / 2, 0.5, FOOT + 1.0, TOP - 1.5, bevel=0.3, bevel_z=1.0, lit=True,
             texture=door_texture),
        box("handle", GROUP, "chrome", 8.2, 9.0, FY0 - 0.9, FY0, 40.0, 56.0, lit=True),
    ]
    return s


SPEC = PieceSpec(
    name="server_rack",
    mats={m.name: m for m in (RACK, UNIT, LED, CHROME)},
    model=model,
    shadow=[("bar", 16.0, 9.0, 16.0, 23.0, 9.6, 0, 30)],
    max_colors=30,
    canvas=(128, 160),
    rotations=(0, 1, 2, 3),
    painter=True,
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
