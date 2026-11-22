"""Archivero de Quincena Office (1×1, cuatro rotaciones), hecho con Moana. Ver ../_boxes.py.

Mueble de metal gris de cuatro cajones al frente (−y en rotación 0), cada uno con su tirador y una
etiqueta crema; costados con un panel hundido y una tapa que sobresale un poco. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/filing_cabinet/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, colors, faces, frame, ramp, rect  # noqa: E402
from _chair_kit import PieceSpec, main_piece  # noqa: E402

GROUP = "filing"
TOP = 52.0
BODY = (8.3, 23.7, 6.4, 25.6, 0.0, TOP - 2)
LID = (8.0, 24.0, 6.1, 25.9, TOP - 2, TOP)
DRAWERS = 4

METAL = ramp("metal", "#AEB5B9FF", "#83888BFF", "#686D6FFF", "#2F3437FF", "#C6CBCEFF", "#494E50FF")
DETAIL = colors("detail", "#2F3437FF", light="#E8ECEEFF", top="#F2EAD2FF", upper="#5F676BFF", left="#9AA1A5FF")
HANDLE, LABEL, LINE, GLINT = "detail.light", "detail.top", "detail.upper", "detail.left"


def body_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    f = faces(mx, my, mz, *BODY)
    out = tone.copy()
    foot = 2.0
    step = (f.height - foot - 1) / DRAWERS
    for k in range(DRAWERS):
        b0 = foot + k * step
        b1 = b0 + step
        drawer = f.front & frame(f, 1, -1, b0 + 0.5, b1)
        out[drawer] = LINE
        mid_b = b0 + step * 0.45
        out[f.front & (np.abs(f.a - f.width / 2) < f.width * 0.17) & (np.abs(f.b - mid_b) < 0.8)] = HANDLE
        out[f.front & (np.abs(f.a - f.width / 2) < 3) & (f.b >= mid_b + 2.5) & (f.b < mid_b + 5)] = LABEL
    out[f.front & (f.b < foot)] = LINE
    panel = (f.left | f.right | f.back) & frame(f, 3, -3, 4, f.height - 3)
    out[panel] = LINE
    out[(f.left | f.right | f.back) & rect(f, 4, -4, f.height - 4, f.height - 3)] = GLINT  # luz bajo el canto
    return out


def model() -> list:
    return [
        box("body", GROUP, "metal", *BODY, texture=body_texture),
        box("lid", GROUP, "metal", *LID, lit=True),
    ]


SPEC = PieceSpec(
    name="filing_cabinet",
    mats={m.name: m for m in (METAL, DETAIL)},
    model=model,
    shadow=[("bar", 16.0, 8.0, 16.0, 24.0, 8.32, 0, TOP)],
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
