"""Lavamanos de pedestal de Quincena Office (1×1, cuatro rotaciones), hecho con Moana. Ver ../_bath.py.

Cerámica blanca: pedestal que se ensancha abajo y lavabo de esquinas redondeadas con su cuenco hundido
(sombra adentro, desagüe y un reflejo). Atrás, la llave cromada con caño y dos manijas (roja la caliente,
azul la fría) y un jabón líquido. El frente mira a −y en rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/sink/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _bath import CERAMIC, CHROME  # noqa: E402
from _boxes import box, colors, ramp  # noqa: E402
from _chair_kit import PieceSpec, beam, cylinder, main_piece, slab  # noqa: E402

GROUP = "sink"
CX = 16.0
BASIN = (7.4, 24.6, 9.6, 26.6, 27.0, 35.0)
BOWL_C = (16.0, 16.6)  # centro del cuenco
TAP_Y = 24.2

HOT = colors("hot", "#5A1919FF", **{k: "#E2453CFF" for k in ("light", "top", "upper", "left", "right", "dark")})
COLD = colors("cold", "#1B3A52FF", **{k: "#4F9BD0FF" for k in ("light", "top", "upper", "left", "right", "dark")})
SOAP = ramp("soap", "#8FD18AFF", "#6DB56AFF", "#55964FFF", "#1F3A1EFF", "#C2EDBDFF", "#3F7A3BFF")


def basin_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Cuenco hundido: borde oscuro, sombra en la mitad de atrás, desagüe y un reflejo."""
    out = tone.copy()
    top = mz > BASIN[5] - 0.3
    u, v = (mx - BOWL_C[0]) / 6.4, (my - BOWL_C[1]) / 5.0
    r = u * u + v * v
    bowl = top & (r < 1.0)
    out[top & (r >= 1.0) & (r < 1.18)] = "ceramic.upper"
    out[bowl] = "ceramic.left"
    out[bowl & (v > -0.1)] = "ceramic.right"  # el lado de atrás queda en sombra
    out[bowl & (r < 0.05)] = "chrome.dark"  # desagüe
    out[bowl & (np.abs(u + 0.45) < 0.08) & (v < -0.2) & (v > -0.7)] = "ceramic.light"
    return out


def model() -> list:
    x0, x1, y0, y1, z0, z1 = BASIN
    return [
        cylinder("foot", GROUP, "ceramic", CX, 19.0, 4.6, 0.0, 2.5, sides=14, r_top=3.4, lit=True),
        cylinder("column", GROUP, "ceramic", CX, 19.0, 2.8, 2.5, z0, sides=12, r_top=3.6),
        slab("basin", GROUP, "ceramic", (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, 3.5, z0, z1,
             bevel=0.6, bevel_z=1.5, lit=True, texture=basin_texture),
        cylinder("faucet", GROUP, "chrome", CX, TAP_Y, 1.1, z1, z1 + 7.0, sides=8, lit=True),
        beam("spout", GROUP, "chrome", (CX, TAP_Y, z1 + 6.0), (CX, TAP_Y - 4.5, z1 + 5.0), 0.7, 0.8, lit=True),
        cylinder("tap_hot", GROUP, "chrome", CX + 3.6, TAP_Y, 1.0, z1, z1 + 2.5, sides=8, lit=True),
        cylinder("tap_cold", GROUP, "chrome", CX - 3.6, TAP_Y, 1.0, z1, z1 + 2.5, sides=8, lit=True),
        cylinder("hot", GROUP, "hot", CX + 3.6, TAP_Y, 0.5, z1 + 2.5, z1 + 3.0, sides=6),
        cylinder("cold", GROUP, "cold", CX - 3.6, TAP_Y, 0.5, z1 + 2.5, z1 + 3.0, sides=6),
        cylinder("soap", GROUP, "soap", 21.8, 23.6, 1.2, z1, z1 + 4.5, sides=8, lit=True),
        box("pump", GROUP, "chrome", 21.4, 22.2, 22.4, 24.0, z1 + 4.5, z1 + 5.5),
    ]


SPEC = PieceSpec(
    name="sink",
    mats={m.name: m for m in (CERAMIC, CHROME, HOT, COLD, SOAP)},
    model=model,
    shadow=[("disc", CX, 19.0, 4.6, 0, 4), ("bar", 11.0, 18.0, 21.0, 18.0, 5.0, 10, 24)],
    max_colors=24,
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
