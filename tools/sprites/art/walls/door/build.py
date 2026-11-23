"""Puertas de una hoja (``door``, ``door_wood``, ``door_office``; ``_tall``/``_low``, ``_x``/``_y``, en los cinco
colores de pared) y sus cuadros de abrir (``<puerta>_tall_<eje>_open_1`` a ``_6``), con Moana. Ver ../_walls_kit.py.

Pared a los lados y encima, marco, umbral y hoja hundida 2 px con manija de metal del lado de adentro; la baja va
sin hoja. ``door`` beige de dos tableros con marco crema; ``door_wood`` madera naranja de seis tableros con marco
de madera; ``door_office`` lisa gris clara con mirilla de vidrio y marco de aluminio. La hoja abre hacia adentro.
Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/walls/door/build.py [--out DIR] [--only TEXTO]
"""

import sys
from pathlib import Path
from typing import Iterator, Optional

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import _walls_kit as k  # noqa: E402

SILL = 2  # umbral
LINTEL = 4  # alto del cabezal del marco
OPENING = k.DOOR_TOP - LINTEL  # 88: arriba de la hoja
HANDLE_Z = 44
SWING_ANGLES = (15, 30, 45, 60, 75, 90)
GROW = (48, 0, 48, 32)  # cuánto sale la hoja abierta del lienzo (izquierda, arriba, derecha, abajo)

LEAF = k.ramp8("leaf", "#2A211BFF", "#5E3E29FF", "#AFA08DFF", "#B8A991FF", "#C1B29AFF", "#C9BAA2FF", "#EFDFBDFF")
LEAF_X = k.colors("leaf_x", "#2A211BFF", dark="#8D6E4FFF", light="#E3D4B4FF")  # ranura y filo de los tableros
FRAME = k.ramp8("frame", "#2A211BFF", "#8D6E4FFF", "#E8D6B0FF", "#F1E3C3FF", "#F6EACFFF", "#FBF1DAFF", "#FFFBF0FF")
WOOD = k.ramp8("wood", "#3C1300FF", "#783A13FF", "#9D6035FF", "#AD6D40FF", "#B77748FF", "#C0814FFF", "#D39463FF")
WOOD_X = k.colors("wood_x", "#3C1300FF", dark="#783A13FF", light="#D39463FF")
WOOD_FRAME = k.ramp8("wood_frame", "#3C1300FF", "#5B2A10FF", "#834E28FF", "#94592FFF", "#9E6236FF", "#A86A3CFF",
                     "#C07D4CFF")
OFFICE = k.ramp8("office", "#2E3236FF", "#6B7378FF", "#BCC2C4FF", "#C9CECFFF", "#D2D6D7FF", "#DADEDFFF", "#EEF0F0FF")
OFFICE_X = k.colors("office_x", "#2E3236FF", dark="#8F989DFF", top="#9FC7DCFF", light="#E4F5FBFF")

# layout: (pared, fin de la jamba, hoja desde, hoja hasta) en unidades; panels: tableros (a0, a1, b0, b1) en px.
NARROW = (2, 5, 5, 27)  # hoja de 44 px
WIDE = (4, 6, 6, 26)  # hoja de 40 px
TYPES = {
    "door": {"leaf": LEAF, "extra": LEAF_X, "frame": FRAME, "layout": NARROW,
             "panels": ((6, 38, 8, 36), (6, 38, 44, 78)), "slot": None},
    "door_wood": {"leaf": WOOD, "extra": WOOD_X, "frame": WOOD_FRAME, "layout": WIDE,
                  "panels": ((4, 18, 6, 26), (22, 36, 6, 26), (4, 18, 32, 52), (22, 36, 32, 52),
                             (4, 18, 58, 80), (22, 36, 58, 80)), "slot": None},
    "door_office": {"leaf": OFFICE, "extra": OFFICE_X, "frame": k.ALU, "layout": WIDE, "panels": (),
                    "slot": (7, 14, 40, 78)},
}


def leaf_face(spec: dict):
    """Tableros hundidos (ranura arriba y a la izquierda, filo claro abajo y a la derecha) o la mirilla."""
    x = spec["extra"].name

    def face(a: np.ndarray, b: np.ndarray, kk: np.ndarray, tone: np.ndarray) -> np.ndarray:
        out = tone.copy()
        for a0, a1, b0, b1 in spec["panels"]:
            inside = (a >= a0) & (a < a1) & (b >= b0) & (b < b1)
            dark = inside & ((b == b1 - 1) | (a == a0))
            light = inside & ((b == b0) | (a == a1 - 1)) & ~dark
            out[dark] = f"{x}.dark"
            out[light] = f"{x}.light"
        if spec["slot"]:
            a0, a1, b0, b1 = spec["slot"]
            inside = (a >= a0) & (a < a1) & (b >= b0) & (b < b1)
            edge = inside & ((a == a0) | (a == a1 - 1) | (b == b0) | (b == b1 - 1))
            shine = inside & ~edge & (np.mod(a - a0 + (b - b0) // 2, 9) == 3)
            out[inside] = f"{x}.top"
            out[shine] = f"{x}.light"
            out[edge] = f"{x}.dark"
        return out

    return face


def handle(px: float) -> tuple:
    """Manija del lado de adentro: placa de 4 px y palanca de 12 px, a 6 px del canto libre."""
    r = k.RECESS
    return ((px - 10, px - 6, r, r + 0.5, HANDLE_Z - 6 - SILL, HANDLE_Z + 6 - SILL, "metal"),
            (px - 18, px - 6, r + 0.5, r + 1.0, HANDLE_Z - SILL, HANDLE_Z + 3 - SILL, "metal"))


def model(f: k.Along, kind: str, tall: bool, angle: float = 0, skip: Optional[str] = None, leaf: bool = True) -> None:
    """Pared a los lados y encima, marco, umbral, hoja y manija; ``skip`` ("start"/"end") quita la pared de esa
    punta y ``leaf=False`` la hoja (los dos, para los postes)."""
    spec = TYPES[kind]
    frame = spec["frame"].name
    wall, jamb, leaf0, leaf1 = spec["layout"]
    height = k.WALL_TOP if tall else k.LOW
    stub_top = k.DOOR_TOP if tall else height
    E = k.EDGE
    if skip != "start":
        k.wall_block(f, 0, wall, 0, stub_top, top=not tall)
    if skip != "end":
        k.wall_block(f, E - wall, E, 0, stub_top, top=not tall)
    if tall:
        k.wall_block(f, 0, E, k.DOOR_TOP, height)
    jamb_top = OPENING if tall else height
    f.box("frame", frame, wall, jamb, -k.HALF, k.HALF, 0, jamb_top, tex=k.jamb_light(jamb - 0.25, frame))
    f.box("frame", frame, E - jamb, E - wall, -k.HALF, k.HALF, 0, jamb_top)
    if tall:
        f.box("frame", frame, wall, E - wall, -k.HALF, k.HALF, OPENING, k.DOOR_TOP)
    f.box("sill", spec["leaf"].name, leaf0, leaf1, -k.HALF, k.HALF, 0, SILL)
    if tall and leaf:
        hinge = k.Leaf(leaf0, 1.0, leaf1 - leaf0, angle, False, SILL, OPENING)
        hinge.add(f, spec["leaf"].name, leaf_face(spec), handle(hinge.px))


def mats(kind: str, color: str) -> list:
    spec = TYPES[kind]
    return [k.wall_mat(color), k.CAP, spec["leaf"], spec["extra"], spec["frame"], k.METAL]


def render(kind: str, edge: str, tall: bool, color: str, angle: float = 0, grow=(0, 0, 0, 0)) -> np.ndarray:
    f = k.Along(edge)
    model(f, kind, tall, angle)
    height = k.WALL_TOP if tall else k.LOW
    v = k.wall_canvas(edge, tall, grow)
    side = k.ink_side(edge) if grow == (0, 0, 0, 0) else None
    return k.draw(f.solids + k.ghosts(edge, height), v, mats(kind, color), side)[0]


def sprites() -> Iterator[k.Sprite]:
    for color, *_ in k.WALL_COLORS:
        for kind in TYPES:
            for tall in (True, False):
                for edge in ("x", "y"):
                    base = k.colored(f"{kind}_{'tall' if tall else 'low'}_{edge}", color)
                    entry = k.wall_entry(edge, tall, color, joins=False)
                    if tall:
                        entry["door_height"] = k.DATA["door"]["height"]
                    yield k.Sprite(base, render(kind, edge, tall, color), entry)
                    if not tall:
                        continue
                    images = [render(kind, edge, True, color, a, GROW) for a in SWING_ANGLES]
                    names = [k.colored(f"{kind}_tall_{edge}_open_{n}", color) for n in range(1, 7)]
                    yield from k.frame_sprites(names, images, GROW, True, lambda step, base=base, edge=edge, color=color: {
                        "base": base + ".png", "animation": "open", "axis": edge, "wall_color": color})


if __name__ == "__main__":
    raise SystemExit(k.main("las puertas de una hoja", sprites, HERE))
