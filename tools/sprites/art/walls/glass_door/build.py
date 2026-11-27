"""Puerta de vidrio de una hoja (``glass_door_tall``/``_low``, ``_x``/``_y``, en los cinco colores de pared) y sus
cuadros de abrir (``glass_door_tall_<eje>_open_1`` a ``_6``), con Moana. Ver ../_walls_kit.py.

Una hoja de la puerta doble de la Recepción (``../glass_door_double``) en un borde de 1 m: vidrio templado sin
perfil de punta a punta del borde (de junta a junta del piso), canto celeste más oscuro, herrajes de metal junto a
la bisagra arriba y abajo y tirador largo junto al canto libre, de los dos lados; pared encima y abre hacia afuera.
La baja deja solo un umbral de metal. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/walls/glass_door/build.py [--out DIR] [--only TEXTO]
"""

import sys
from pathlib import Path
from typing import Iterator

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import _walls_kit as k  # noqa: E402

GAP = 0.5  # 1 px libre en cada punta
TOP = k.DATA["glass_door"]["height"] * k.SCALE  # 114, como la doble
BOTTOM = 1  # la hoja queda 1 px sobre el piso
SILL = 2  # umbral de la baja
PULL = (26, 74)
ANGLES = (15, 30, 45, 60, 75, 90)
GROW = (72, 48, 72, 72)  # cuánto sale la hoja abierta del lienzo (izquierda, arriba, derecha, abajo)
WIDTH = k.EDGE - 2 * GAP

GLASS = k.ramp8("glass", "#2B3D4CFF", "#5D8AA6FF", "#A9D4E6FF", "#B4DCECFF", "#BCE0EFFF", "#C3E4F2FF", "#DFF1F8FF")
GLASS_X = k.colors("glass_x", "#2B3D4CFF", top="#8FB8CCFF", light="#FFFFFFFF")


def leaf_face(a: np.ndarray, b: np.ndarray, kk: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Reflejos en diagonal y canto más oscuro, como cada hoja de la doble."""
    width = np.floor(WIDTH * 2)
    height = TOP - BOTTOM
    out = tone.copy()
    d = np.mod(a + b * 0.5, 30.0)
    out[((d >= 10) & (d < 12) | (d >= 16) & (d < 17)) & (b > 8) & (b < height - 8)] = "glass_x.light"
    out[(a < 1) | (a >= width - 1) | (b < 1) | (b >= height - 1)] = "glass_x.top"
    return out


def model(f: k.Along, tall: bool, angle: float = 0) -> None:
    E = k.EDGE
    if not tall:
        f.box("sill", "metal", 0, E, -k.HALF, k.HALF, 0, SILL)
        return
    k.wall_block(f, 0, E, TOP, k.WALL_TOP)
    r = k.RECESS
    leaf = k.Leaf(GAP, 1.0, WIDTH, angle, True, BOTTOM, TOP)
    height = TOP - BOTTOM
    hold = (-r - 0.5, r + 0.5)
    hardware = [(0, 6, hold[0], hold[1], 0, 6, "metal"), (0, 6, hold[0], hold[1], height - 6, height, "metal")]
    for k0, k1 in ((r, r + 0.5), (-r - 0.5, -r)):
        hardware.append((leaf.px - 6, leaf.px - 5, k0, k1, PULL[0], PULL[1], "metal"))
    leaf.add(f, "glass", leaf_face, hardware)


def render(edge: str, tall: bool, color: str, angle: float = 0, grow=(0, 0, 0, 0)) -> np.ndarray:
    f = k.Along(edge)
    model(f, tall, angle)
    height = k.WALL_TOP if tall else k.LOW
    v = k.wall_canvas(edge, tall, grow)
    side = k.ink_side(edge) if grow == (0, 0, 0, 0) else None
    mats = [k.wall_mat(color), k.CAP, GLASS, GLASS_X, k.METAL]
    return k.draw(f.solids + k.ghosts(edge, height), v, mats, side)[0]


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
