"""Zafacón de la Recepción de Quincena Office (mueble chico, ya a su tamaño: el 60 % de una casilla;
simétrico, una sola imagen), hecho con Moana. Ver ../_boxes.py.

Cubo de metal gris que se angosta abajo, con banda oscura al pie, aro claro arriba y la bolsa negra doblada
sobre el borde; adentro, una bola de papel. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/trash_can_q/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import ramp  # noqa: E402
from _chair_kit import PieceSpec, cylinder, main_piece  # noqa: E402

GROUP = "bin"
C = 16.0
TOP = 15.6

METAL = ramp("metal", "#969CA0FF", "#80868AFF", "#6C7276FF", "#1C1F22FF", "#C3C8CAFF", "#585E62FF")
BAG = ramp("bag", "#2E3134FF", "#25282BFF", "#1D1F22FF", "#0E0F10FF", "#4A4E52FF", "#141618FF")
PAPER = ramp("paper", "#F4F6F6FF", "#DDE2E2FF", "#C4CBCCFF", "#4A4F55FF", "#FFFFFFFF", "#A9B0B3FF")


def bin_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Banda oscura al pie y aro claro bajo la bolsa."""
    out = tone.copy()
    out[(mz >= 1.0) & (mz < 2.5)] = "metal.dark"
    out[(mz >= TOP - 2.0) & (mz < TOP - 1.0)] = "metal.light"
    return out


def bag_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Adentro de la bolsa, más oscuro."""
    out = tone.copy()
    out[(mz > TOP + 0.8 - 0.3) & (np.hypot(mx - C, my - C) < 2.3)] = "bag.dark"
    return out


def model() -> list:
    return [
        cylinder("bin", GROUP, "metal", C, C, 2.2, 0.0, TOP, sides=14, r_top=2.9, lit=True, texture=bin_texture),
        cylinder("bag", GROUP, "bag", C, C, 3.1, TOP - 0.6, TOP + 0.8, sides=14, lit=True, texture=bag_texture),
        cylinder("paper", GROUP, "paper", 15.4, 16.6, 0.9, TOP + 0.8, TOP + 2.0, sides=6, lit=True),
    ]


SPEC = PieceSpec(
    name="trash_can_q",
    mats={m.name: m for m in (METAL, BAG, PAPER)},
    model=model,
    shadow=[("disc", C, C, 3.0, 0, TOP)],
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
