"""Impresora multifunción de Quincena Office (1×1, cuatro rotaciones), hecha con Moana. Ver ../_boxes.py.

Mueble bajo gris oscuro con una puerta, cuerpo gris claro con la bandeja de papel, la ranura de salida con
una hoja y el panel de control (pantalla celeste y botón verde) adelante, y la tapa del escáner con su
alimentador de hojas. El frente mira a −y en rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/printer/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, colors, faces, frame, ramp, rect  # noqa: E402
from _chair_kit import PieceSpec, main_piece  # noqa: E402

GROUP = "printer"
STAND = (6.4, 25.6, 7.0, 25.0, 0.0, 18.0)
BODY = (7.0, 25.0, 8.0, 24.0, 18.0, 30.0)
LID = (8.0, 24.0, 13.4, 23.4, 30.0, 34.0)

CASE = ramp("case", "#6B7177FF", "#505559FF", "#404447FF", "#1F2326FF", "#8A9095FF", "#2F3437FF")
BODY_MAT = ramp("body", "#E8E9EAFF", "#CFD2D4FF", "#B3B8BBFF", "#3D3B44FF", "#FFFFFFFF", "#979CA0FF")
LID_MAT = ramp("lid", "#9AA1A6FF", "#74797DFF", "#5C6164FF", "#2F3437FF", "#B8BDC1FF", "#43484BFF")
DETAIL = colors("detail", "#1F2326FF", light="#FFFFFFFF", top="#6DACCEFF", upper="#6FE08AFF", left="#4A4F55FF",
                right="#AAB1B6FF", dark="#26292CFF")
PAPER, SCREEN, GREEN, SLOT, HANDLE, LINE = ("detail.light", "detail.top", "detail.upper", "detail.left",
                                            "detail.right", "detail.dark")


def stand_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Puerta hundida con tirador al frente y zócalo oscuro."""
    f = faces(mx, my, mz, *STAND)
    out = tone.copy()
    out[f.front & frame(f, 3, -3, 3, f.height - 2)] = LINE
    out[f.front & rect(f, -8, -6, 7, 12)] = HANDLE
    out[f.sides & (f.b < 1.5)] = LINE
    return out


def body_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Bandeja con su tirador, ranura de salida con la hoja y panel de control en la franja de adelante."""
    f = faces(mx, my, mz, *BODY)
    out = tone.copy()
    mid = f.width / 2
    out[f.front & rect(f, 3, -3, 2.5, 3.5)] = SLOT  # junta de la bandeja
    out[f.front & (np.abs(f.a - mid) < 5) & (f.b >= 4.5) & (f.b < 5.5)] = SLOT  # tirador de la bandeja
    out[f.front & rect(f, 4, -4, f.height - 5, f.height - 3)] = SLOT  # ranura de salida
    out[f.front & rect(f, 7, -7, f.height - 4, f.height - 3)] = PAPER  # la hoja que sale
    out[f.top & rect(f, 4, 14, 0, 3)] = SCREEN
    out[f.top & rect(f, 17, 19, 0.5, 2.5)] = GREEN
    out[f.top & rect(f, 21, 23, 0.5, 2.5)] = HANDLE  # botón gris
    return out


def lid_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Alimentador de hojas: ranura oscura atrás con una hoja asomando."""
    f = faces(mx, my, mz, *LID)
    out = tone.copy()
    out[f.top & rect(f, 4, -4, 13, 15)] = SLOT
    out[f.top & rect(f, 7, -7, 14, 15)] = PAPER
    return out


def model() -> list:
    return [
        box("stand", GROUP, "case", *STAND, texture=stand_texture),
        box("body", GROUP, "body", *BODY, texture=body_texture, lit=True),
        box("lid", GROUP, "lid", *LID, texture=lid_texture, lit=True),
    ]


SPEC = PieceSpec(
    name="printer",
    mats={m.name: m for m in (CASE, BODY_MAT, LID_MAT, DETAIL)},
    model=model,
    shadow=[("bar", 10.24, 16.0, 21.76, 16.0, 8.32, 0, 34)],
    max_colors=24,
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
