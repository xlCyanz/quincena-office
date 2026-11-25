"""Puerta doble de vidrio sin marco de la Recepción (``glass_door_double_a``/``_b``, ``_tall``/``_low``,
``_x``/``_y``, en los cinco colores de pared) y sus cuadros de abrir (``…_tall_<eje>_open_1`` a ``_6``), con Moana.
Ver ../_walls_kit.py.

Ocupa dos bordes: se modela de a = 0 a 64 y se guarda en dos mitades de 72×160, ``_a`` (el borde de menor x o y)
y ``_b``, que solo empalman entre sí. Hojas de vidrio templado de 48 px sin perfil, con canto celeste más oscuro,
herrajes de metal junto a la bisagra y tirador largo junto al medio; abren hacia afuera. Cada mitad lleva los
pixeles de la puerta armada donde se ve ella (así la línea entre las hojas es la de la puerta entera). Desde el
repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/walls/glass_door_double/build.py [--out DIR] [--only TEXTO]
"""

import sys
from pathlib import Path
from typing import Iterator, Optional

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import _walls_kit as k  # noqa: E402

WALL = 8.0  # 16 px de pared a cada lado
GAP = 0.5  # medio hueco entre las dos hojas (1 px cada una)
TOP = k.DATA["glass_door_double"]["height"] * k.SCALE  # 114, casi al alto de la pared
BOTTOM = 1  # la hoja queda 1 px sobre el piso
PULL = (26, 74)
ANGLES = (15, 30, 45, 60, 75, 90)
GROW = (136, 56, 136, 104)  # lienzo de la puerta entera: los dos tramos, un vecino a cada lado y las hojas
WIDTH = k.EDGE - WALL - GAP

GLASS = k.ramp8("glass", "#2B3D4CFF", "#5D8AA6FF", "#A9D4E6FF", "#B4DCECFF", "#BCE0EFFF", "#C3E4F2FF", "#DFF1F8FF")
GLASS_X = k.colors("glass_x", "#2B3D4CFF", top="#8FB8CCFF", light="#FFFFFFFF")


def leaf_face(a: np.ndarray, b: np.ndarray, kk: np.ndarray, tone: np.ndarray) -> np.ndarray:
    width = np.floor(WIDTH * 2)
    height = TOP - BOTTOM
    out = tone.copy()
    d = np.mod(a + b * 0.5, 30.0)
    out[((d >= 10) & (d < 12) | (d >= 16) & (d < 17)) & (b > 8) & (b < height - 8)] = "glass_x.light"
    out[(a < 1) | (a >= width - 1) | (b < 1) | (b >= height - 1)] = "glass_x.top"
    return out


def leaf(f: k.Along, hinge: float, sign: float, angle: float) -> None:
    r = k.RECESS
    lf = k.Leaf(hinge, sign, WIDTH, angle, True, BOTTOM, TOP)
    height = TOP - BOTTOM
    hold = (-r - 0.5, r + 0.5)
    hardware = [(0, 6, hold[0], hold[1], 0, 6, "metal"), (0, 6, hold[0], hold[1], height - 6, height, "metal")]
    for k0, k1 in ((r, r + 0.5), (-r - 0.5, -r)):
        hardware.append((lf.px - 6, lf.px - 5, k0, k1, PULL[0], PULL[1], "metal"))
    lf.add(f, "glass", leaf_face, hardware)


def model(f: k.Along, tall: bool, half: Optional[str] = None, angle: float = 0) -> None:
    """De a = 0 a 64; ``half`` "a" o "b" dibuja solo esa mitad (con su hoja), None las dos."""
    E = k.EDGE
    height = k.WALL_TOP if tall else k.LOW
    for h in (("a", "b") if half is None else (half,)):
        stub = (0.0, WALL) if h == "a" else (2 * E - WALL, 2 * E)
        k.wall_block(f, stub[0], stub[1], 0, height)
        if not tall:
            continue
        inner = (WALL, E) if h == "a" else (E, 2 * E - WALL)
        k.wall_block(f, inner[0], inner[1], TOP, height)
        if h == "a":
            leaf(f, WALL, 1.0, angle)
        else:
            leaf(f, 2 * E - WALL, -1.0, angle)


def render(edge: str, tall: bool, color: str, half: Optional[str], angle: float) -> tuple[np.ndarray, np.ndarray]:
    height = k.WALL_TOP if tall else k.LOW
    f = k.Along(edge)
    model(f, tall, half, angle)
    solids = f.solids + k.ghosts(edge, height)
    if half is None:  # la puerta armada, con una pared vecina a cada lado
        k.wall_block(f, -k.EDGE, 0, 0, height)
        k.wall_block(f, 2 * k.EDGE, 3 * k.EDGE, 0, height)
        solids = f.solids + k.ghosts(edge, height)
    elif half == "b":
        solids = f.solids + [s for s in k.ghosts(edge, height) if s.part == "~floor"] + \
            k.ghosts_at(edge, height, k.EDGE)
    mats = [k.wall_mat(color), k.CAP, GLASS, GLASS_X, k.METAL]
    return k.draw(solids, k.wall_canvas(edge, tall, GROW), mats)


def half_image(edge: str, tall: bool, color: str, half: str, angle: float = 0) -> np.ndarray:
    whole, whole_depth = render(edge, tall, color, None, angle)
    alone, alone_depth = render(edge, tall, color, half, angle)
    mine = alone[..., 3] == 255
    same = mine & (np.abs(whole_depth - alone_depth) < 1e-6) & (whole[..., 3] == 255)
    out = np.where(same[..., None], whole, alone)
    out[~mine] = 0
    return out


def sprites() -> Iterator[k.Sprite]:
    gl, gt = GROW[0], GROW[1]
    for color, *_ in k.WALL_COLORS:
        for edge in ("x", "y"):
            step = (64, 32) if edge == "y" else (-64, 32)
            for tall in (True, False):
                h = k.CANVAS_TALL if tall else k.CANVAS_LOW
                for n, half in enumerate(("a", "b")):
                    image = half_image(edge, tall, color, half)
                    ox, oy = gl + step[0] * n, gt + step[1] * n
                    name = k.colored(f"glass_door_double_{half}_{'tall' if tall else 'low'}_{edge}", color)
                    entry = k.wall_entry(edge, tall, color, joins=False, pair=half, pair_with="b" if half == "a" else "a")
                    if tall:
                        entry["door_height"] = k.DATA["glass_door_double"]["height"]
                    yield k.Sprite(name, np.ascontiguousarray(image[oy:oy + h, ox:ox + k.CANVAS_W]), entry)
                    if not tall:
                        continue
                    frames = [half_image(edge, True, color, half, a) for a in ANGLES]
                    (x0, y0, w, hh), offset = k.crop_frames(frames, (ox, oy, k.CANVAS_W, h))
                    anchor = [k.piece_anchor(True)[0] + offset[0], k.piece_anchor(True)[1] + offset[1]]
                    for m, arr in enumerate(frames, 1):
                        fname = k.colored(f"glass_door_double_{half}_tall_{edge}_open_{m}", color)
                        yield k.Sprite(fname, np.ascontiguousarray(arr[y0:y0 + hh, x0:x0 + w]),
                                       {"anchor": anchor, "kind": "wall_frame", "base": name + ".png",
                                        "base_offset": offset, "frame": m, "frames": len(ANGLES), "animation": "open",
                                        "axis": edge, "pair": half, "wall_color": color})


if __name__ == "__main__":
    raise SystemExit(k.main("la puerta doble de vidrio", sprites, HERE))
