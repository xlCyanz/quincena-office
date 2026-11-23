"""Tramos de pared lisos (``wall_tall_x`` … ``wall_<color>_low_y``) y la sombra de la pared alta
(``wall_tall_x_shadow``, ``_y``), con Moana. Ver ../_walls_kit.py.

Cara lisa del color de la pared y tapa ciruela arriba. Desde el
repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/walls/wall/build.py [--out DIR] [--only TEXTO]
"""

import sys
from pathlib import Path
from typing import Iterator

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import _walls_kit as k  # noqa: E402

# Sombra de contacto de la pared alta: franja en la casilla de adentro, pegada al borde.
SHADOW_DEPTH = {"x": 3 / 16.0, "y": 5 / 32.0}  # casillas desde el borde: 8 y 6 px fuera de la pared
SHADOW_COLOR = (26, 28, 38)


def model(f: k.Along, height: float) -> None:
    k.wall_block(f, 0.0, k.EDGE, 0, height)


def wall_sprite(edge: str, tall: bool, color: str) -> k.Sprite:
    height = k.WALL_TOP if tall else k.LOW
    f = k.Along(edge)
    model(f, height)
    rgba, _depth = k.draw(f.solids + k.ghosts(edge, height), k.wall_canvas(edge, tall), [k.wall_mat(color), k.CAP],
                         k.ink_side(edge))
    name = k.colored(f"wall_{'tall' if tall else 'low'}_{edge}", color)
    return k.Sprite(name, rgba, k.wall_entry(edge, tall, color, joins=True))


def shadow(edge: str) -> k.Sprite:
    ys, xs = np.mgrid[0:128, 0:128]
    rx, ry = xs + 0.5 - 64, ys + 0.5 - 64
    u = (ry / 32 + rx / 64) / 2
    v = (ry / 32 - rx / 64) / 2
    across = u if edge == "x" else v
    mask = (u >= 0) & (u < 1) & (v >= 0) & (v < 1) & (across < SHADOW_DEPTH[edge])
    rgba = np.zeros((128, 128, 4), dtype=np.uint8)
    rgba[mask] = SHADOW_COLOR + (255,)
    return k.Sprite(f"wall_tall_{edge}_shadow", rgba,
                    {"anchor": [64.0, 96.0], "kind": "shadow", "footprint": [1, 1],
                     "placed_on": "casilla de adentro, delante de la pared alta del borde"})


def sprites() -> Iterator[k.Sprite]:
    for color, *_ in k.WALL_COLORS:
        for tall in (True, False):
            for edge in ("x", "y"):
                yield wall_sprite(edge, tall, color)
    for edge in ("x", "y"):
        yield shadow(edge)


if __name__ == "__main__":
    raise SystemExit(k.main("los tramos de pared", sprites, HERE))
