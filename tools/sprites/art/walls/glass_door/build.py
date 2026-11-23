"""Puerta de vidrio de la Recepción (``glass_door_tall``/``_low``, ``_x``/``_y``, en los cinco colores de pared) y sus
cuadros de abrir (``glass_door_tall_<eje>_open_1`` a ``_6``), con Moana. Ver ../_walls_kit.py.

Marco de aluminio oscuro hasta 100 px con pared encima; dos hojas de vidrio con perfil de aluminio, reflejos en
diagonal y tirador vertical de los dos lados, cada una con la bisagra en su jamba, que abren hacia afuera (la
calle). La baja deja solo el marco y el umbral. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/walls/glass_door/build.py [--out DIR] [--only TEXTO]
"""

import sys
from pathlib import Path
from typing import Iterator

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import _walls_kit as k  # noqa: E402

SILL = 2
HEAD = k.GLASS_TOP - 4  # 96: arriba del vidrio
WALL = 4.0
IN0, IN1 = 6.0, 26.0  # hueco entre las jambas
PANE = (IN1 - IN0) / 2  # 10 unidades: cada hoja
ANGLES = (15, 30, 45, 60, 75, 90)
PULL = (30, 62)  # tirador vertical: de z 30 a 62
GROW = (32, 24, 32, 8)  # la hoja abre hacia atrás

GLASS = k.ramp8("glass", "#2B3D4CFF", "#5D8AA6FF", "#A9D4E6FF", "#B4DCECFF", "#BCE0EFFF", "#C3E4F2FF", "#DFF1F8FF")
GLASS_X = k.colors("glass_x", "#2B3D4CFF", top="#5A646DFF", dark="#4F5862FF", light="#FFFFFFFF")


def leaf_face(a: np.ndarray, b: np.ndarray, kk: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Vidrio: perfil de aluminio de 2 px (zócalo de 4), canto oscuro y dos reflejos en diagonal."""
    width = np.floor(PANE * 2)
    height = HEAD - SILL
    out = tone.copy()
    d = np.mod(a + b * 0.5, 24.0)
    out[((d >= 8) & (d < 10) | (d >= 13) & (d < 14)) & (b > 6)] = "glass_x.light"
    frame = (a < 2) | (a >= width - 2) | (b < 4) | (b >= height - 2)
    out[frame] = "glass_x.top"
    out[frame & ((a == 0) | (a == width - 1) | (b == 0))] = "glass_x.dark"
    return out


def pull(px: float) -> list:
    r = k.RECESS
    return [(px - 5, px - 4, k0, k1, PULL[0] - SILL, PULL[1] - SILL, "metal") for k0, k1 in ((r, r + 0.5), (-r - 0.5, -r))]


def model(f: k.Along, tall: bool, angle: float = 0) -> None:
    E = k.EDGE
    height = k.WALL_TOP if tall else k.LOW
    if tall:
        k.wall_block(f, 0, WALL, 0, k.GLASS_TOP, top=False)
        k.wall_block(f, E - WALL, E, 0, k.GLASS_TOP, top=False)
        k.wall_block(f, 0, E, k.GLASS_TOP, height)
    else:
        k.wall_block(f, 0, WALL, 0, height)
        k.wall_block(f, E - WALL, E, 0, height)
    top = HEAD if tall else height
    f.box("frame", "alu", WALL, IN0, -k.HALF, k.HALF, 0, top, tex=k.jamb_light(IN0 - 0.25, "alu"))
    f.box("frame", "alu", IN1, E - WALL, -k.HALF, k.HALF, 0, top)
    if tall:
        f.box("frame", "alu", WALL, E - WALL, -k.HALF, k.HALF, HEAD, k.GLASS_TOP)
    f.box("sill", "alu", IN0, IN1, -k.HALF, k.HALF, 0, SILL)
    if tall:
        for hinge, sign in ((IN0, 1.0), (IN1, -1.0)):
            leaf = k.Leaf(hinge, sign, PANE, angle, True, SILL, HEAD)
            leaf.add(f, "glass", leaf_face, pull(leaf.px))


def render(edge: str, tall: bool, color: str, angle: float = 0, grow=(0, 0, 0, 0)) -> np.ndarray:
    f = k.Along(edge)
    model(f, tall, angle)
    v = k.wall_canvas(edge, tall, grow)
    side = k.ink_side(edge) if grow == (0, 0, 0, 0) else None
    height = k.WALL_TOP if tall else k.LOW
    return k.draw(f.solids + k.ghosts(edge, height), v, [k.wall_mat(color), k.CAP, k.ALU, GLASS, GLASS_X, k.METAL],
                  side)[0]


def sprites() -> Iterator[k.Sprite]:
    for color, *_ in k.WALL_COLORS:
        for tall in (True, False):
            for edge in ("x", "y"):
                base = k.colored(f"glass_door_{'tall' if tall else 'low'}_{edge}", color)
                entry = k.wall_entry(edge, tall, color, joins=False)
                if tall:
                    entry["door_height"] = k.DATA["glass_door"]["height"]
                yield k.Sprite(base, render(edge, tall, color), entry)
                if tall:
                    images = [render(edge, True, color, a, GROW) for a in ANGLES]
                    names = [k.colored(f"glass_door_tall_{edge}_open_{n}", color) for n in range(1, 7)]
                    yield from k.frame_sprites(names, images, GROW, True, lambda step, base=base, edge=edge, color=color: {
                        "base": base + ".png", "animation": "open", "axis": edge, "wall_color": color})


if __name__ == "__main__":
    raise SystemExit(k.main("la puerta de vidrio", sprites, HERE))
