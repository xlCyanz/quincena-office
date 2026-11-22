"""Lámpara de pie de Quincena Office (mueble chico, ya al 60 %), hecha con Moana. Ver ../_chair_kit.py.

Base redonda negra, poste cromado y pantalla de tela crema encendida: clara abajo, donde sale la luz, con
la costura atrás y el filo de arriba en sombra. Lienzo 128×160, apoyo (64, 128). Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/floor_lamp_q/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _chair_kit import Mat, PieceSpec, cylinder, main_piece  # noqa: E402
from _chairs import METAL, PLASTIC  # noqa: E402

C = 16.0
GROUP = "lamp"
SCALE = 0.6  # el juego dibuja los muebles chicos a este tamaño
TOP = 41.0  # alto (68 px a tamaño de casilla)
SHADE_Z = TOP - 14.0
SHADE = Mat("shade", light="#FFF6D6FF", top="#FFF1B8FF", upper="#F6E3A1FF", left="#ECD28AFF", right="#DCBD72FF",
            dark="#A07A35FF", ink="#4E3510FF")


def shade_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Luz que sale por abajo (filo claro) y borde de arriba un tono más oscuro."""
    out = tone.copy()
    side = np.char.endswith(tone.astype(str), ".left") | np.char.endswith(tone.astype(str), ".right") | \
        np.char.endswith(tone.astype(str), ".upper")
    out[side & (mz < SHADE_Z + 1.5)] = "shade.light"
    out[side & (mz > TOP - 1.2)] = "shade.right"
    return out


def model() -> list:
    return [
        cylinder("base", GROUP, "plastic", C, C, 0.17 * 32 * SCALE, 0.0, 2.0, sides=14, lit=True),
        cylinder("foot", GROUP, "plastic", C, C, 1.3, 2.0, 3.5, sides=8),
        cylinder("pole", GROUP, "metal", C, C, 0.5, 3.5, SHADE_Z + 2.0, sides=6, lit=True),
        cylinder("shade", GROUP, "shade", C, C, 0.2 * 32 * SCALE, SHADE_Z, TOP, sides=14,
                 r_top=0.13 * 32 * SCALE, texture=shade_texture),
    ]


SPEC = PieceSpec(
    name="floor_lamp_q",
    mats={m.name: m for m in (PLASTIC, METAL, SHADE)},
    model=model,
    shadow=[("disc", C, C, 0.17 * 32 * SCALE, 0, 0), ("disc", C, C, 0.2 * 32 * SCALE, 40 * SCALE, 68 * SCALE)],
    canvas=(128, 160),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
