"""Baterías de respaldo de Quincena Office (1×1, cuatro rotaciones), hechas con Moana. Ver ../_boxes.py.

Gabinete gris oscuro: arriba al frente (−y en rotación 0) un panel con la pantalla verde y dos luces; debajo
cuatro módulos con su asa y su luz de carga; rejillas de ventilación en los costados y en la tapa.
Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/backup_battery/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, colors, faces, ramp, rect  # noqa: E402
from _chair_kit import PieceSpec, main_piece  # noqa: E402

GROUP = "battery"
TOP = 44.0
BODY = (7.7, 24.3, 8.3, 23.7, 0.0, TOP)
MODULES = 4

CASE = ramp("case", "#4F5A66FF", "#3B444DFF", "#2F363DFF", "#12161BFF", "#6A7682FF", "#2A3038FF")
DETAIL = colors("detail", "#12161BFF", light="#7FE0B0FF", top="#6FE08AFF", upper="#F0B030FF", left="#8C96A0FF",
                right="#20252BFF")
LCD, LED, AMBER, HANDLE, LINE = "detail.light", "detail.top", "detail.upper", "detail.left", "detail.right"


def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    f = faces(mx, my, mz, *BODY)
    out = tone.copy()
    h = f.height
    panel0 = h - 11
    out[f.front & rect(f, 3, -3, panel0, h - 3)] = LINE
    out[f.front & rect(f, 5, 15, panel0 + 2, h - 5)] = LCD
    out[f.front & rect(f, -9, -7, panel0 + 3, panel0 + 5)] = LED
    out[f.front & rect(f, -6, -4, panel0 + 3, panel0 + 5)] = AMBER
    step = (panel0 - 3) / MODULES
    for k in range(MODULES):
        b0 = 2 + k * step
        b1 = b0 + step
        out[f.front & rect(f, 2, -2, b1 - 1, b1)] = LINE
        mid = (b0 + b1) / 2
        out[f.front & (np.abs(f.a - f.width / 2) < 5) & (f.b >= mid) & (f.b < mid + 2)] = HANDLE
        out[f.front & rect(f, 3, 5, b0 + 1, b1 - 2)] = LED if k else AMBER  # el de abajo, cargando
    vents = (f.left | f.right | f.back) & rect(f, 4, -4, h - 16, h - 4) & (np.mod(np.floor(f.b), 3) == 0)
    out[vents] = LINE
    out[f.top & rect(f, 6, -6, 10, 22) & (np.mod(np.floor(f.b), 3) == 0)] = LINE
    out[f.sides & (f.b < 2)] = LINE
    return out


def model() -> list:
    return [box("body", GROUP, "case", *BODY, texture=texture, lit=True)]


SPEC = PieceSpec(
    name="backup_battery",
    mats={m.name: m for m in (CASE, DETAIL)},
    model=model,
    shadow=[("bar", 16.0, 10.24, 16.0, 21.76, 8.64, 0, TOP)],
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
