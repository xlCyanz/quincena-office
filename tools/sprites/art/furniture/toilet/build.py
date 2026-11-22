"""Inodoro de Quincena Office (1×1, cuatro rotaciones), hecho con Moana. Ver ../_bath.py.

Cerámica blanca: pie ovalado, taza redondeada con el asiento y la tapa cerrada (aro y bisagras), y atrás el
tanque con su tapa y el botón cromado. El frente mira a −y en rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/toilet/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _bath import CERAMIC, CHROME  # noqa: E402
from _boxes import box  # noqa: E402
from _chair_kit import PieceSpec, cylinder, main_piece, slab  # noqa: E402

GROUP = "toilet"
CX, CY = 16.0, 13.4  # centro de la taza
BOWL, SEAT, LID = 15.0, 16.5, 18.0
TANK = (10.4, 21.6, 21.4, 26.6, 8.0, 27.0)


def lid_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Aro de la tapa un tono más oscuro cerca del borde."""
    out = tone.copy()
    top = mz > LID - 0.3
    u, v = (mx - CX) / 5.4, (my - CY) / 6.6
    r = u * u + v * v
    out[top & (r > 0.62) & (r < 0.78)] = "ceramic.upper"
    return out


def tank_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Junta bajo la tapa del tanque."""
    out = tone.copy()
    out[(mz > TANK[5] - 1.2) & (mz < TANK[5] - 0.3)] = "ceramic.dark"
    return out


def oval(part: str, hx: float, hy: float, z0: float, z1: float, cy: float = CY, **kw: object):
    return slab(part, GROUP, "ceramic", CX, cy, hx, hy, min(hx, hy) - 0.2, z0, z1, lit=True, **kw)


def model() -> list:
    x0, x1, y0, y1, z0, z1 = TANK
    return [
        oval("foot", 3.8, 5.0, 0.0, 8.0, cy=CY + 1.2, bevel=0.0),
        oval("bowl", 6.4, 7.6, 8.0, BOWL, bevel=1.0, bevel_z=2.0),
        box("neck", GROUP, "ceramic", 12.6, 19.4, 18.0, 22.0, 6.0, BOWL),
        oval("seat", 6.2, 7.4, BOWL, SEAT, bevel=0.0),
        oval("lid", 6.0, 7.2, SEAT, LID, bevel=0.6, bevel_z=1.0, texture=lid_texture),
        box("hinges", GROUP, "chrome", 13.0, 19.0, 19.8, 21.2, BOWL, SEAT + 0.6),
        slab("tank", GROUP, "ceramic", (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, 1.4, z0, z1,
             lit=True, texture=tank_texture),
        slab("tank_lid", GROUP, "ceramic", (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2 + 0.6, (y1 - y0) / 2 + 0.6,
             1.6, z1, z1 + 2.5, bevel=0.6, bevel_z=1.0, lit=True),
        cylinder("button", GROUP, "chrome", (x0 + x1) / 2, (y0 + y1) / 2, 1.3, z1 + 2.5, z1 + 3.3, sides=10,
                 lit=True),
    ]


SPEC = PieceSpec(
    name="toilet",
    mats={m.name: m for m in (CERAMIC, CHROME)},
    model=model,
    shadow=[("disc", CX, CY, 6.7, 0, BOWL), ("bar", 11.8, 24.0, 20.2, 24.0, 2.6, 0, 12)],
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
