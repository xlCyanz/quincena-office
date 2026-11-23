"""Ventanas (``window_tall``/``_low``, ``_x``/``_y``, en los cinco colores de pared) y los cuadros de la persiana de
la alta (``window_tall_<eje>_blind_1`` a ``_6``, que baja hasta cerrar), con Moana. Ver ../_walls_kit.py.

Marco de aluminio oscuro con parante en el medio y, en la alta, travesaño que deja una banda fija arriba; vidrio
celeste hundido con dos reflejos en diagonal por hoja, alféizar que sale 1 px y persiana veneciana blanca de
tablillas de 3 px del lado de adentro. La baja es una franja de ventana en la pared de 20 px. Desde el repositorio
de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/walls/window/build.py [--out DIR] [--only TEXTO]
"""

import sys
from pathlib import Path
from typing import Iterator

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import _walls_kit as k  # noqa: E402

WALL = 4.0
JAMB = 6.0
MULLION = (15.0, 17.0)
KINDS = {
    True: {"sill": (28, 32), "head": (104, 108), "transom": (84, 86)},
    False: {"sill": (4, 6), "head": (16, 18), "transom": None},
}
BLIND_LEVELS = (70, 64, 58, 51, 45, 38, 32)  # borde de abajo de la persiana por cuadro (0 = la pieza)

GLASS = k.ramp8("glass", "#2B3D4CFF", "#5D8AA6FF", "#9FC7DCFF", "#AED6EAFF", "#BADEEFFF", "#C6E6F4FF", "#E4F5FBFF")
SHINE = k.colors("shine", "#2B3D4CFF", top="#FFFFFFFF")
BLIND = k.ramp8("blind", "#5D6468FF", "#A4ABAFFF", "#D3D7D9FF", "#DFE2E3FF", "#E6E8E9FF", "#ECEEEEFF", "#F7F8F8FF")


def glass_face(a: np.ndarray, c: np.ndarray, z: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """En cada hoja dos reflejos cortos en diagonal (uno de 2 px y otro de 1 px)."""
    ax = np.floor(a * 2)
    zz = np.floor(z)
    pane = np.mod(ax - JAMB * 2, 22.0)
    d = pane + np.mod(zz, 64.0) * 0.5
    shine = ((d >= 9) & (d < 11) | (d >= 14) & (d < 15)) & (pane >= 2) & (pane < 18) & (np.mod(zz, 64.0) > 0)
    out = tone.copy()
    out[shine & (c > 0) & (tone != "glass.top")] = "shine.top"
    return out


def blind_face(a: np.ndarray, c: np.ndarray, z: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Tablillas de 3 px: rendija gris abajo y filo claro arriba."""
    row = np.mod(np.floor(z), 3.0)
    out = tone.copy()
    side = tone != "blind.top"
    out[side & (row == 0)] = "blind.dark"
    out[side & (row == 2)] = "blind.upper"
    return out


def model(f: k.Along, tall: bool, blind: int = 0) -> None:
    E = k.EDGE
    height = k.WALL_TOP if tall else k.LOW
    spec = KINDS[tall]
    sill0, sill1 = spec["sill"]
    head0, head1 = spec["head"]
    k.wall_block(f, 0, WALL, 0, height)
    k.wall_block(f, E - WALL, E, 0, height)
    k.wall_block(f, WALL, E - WALL, 0, sill0, top=False)
    k.wall_block(f, WALL, E - WALL, head1, height)
    f.box("frame", "alu", WALL, E - WALL, -k.HALF, k.HALF + 0.5, sill0, sill1)
    f.box("frame", "alu", WALL, E - WALL, -k.HALF, k.HALF, head0, head1)
    f.box("frame", "alu", WALL, JAMB, -k.HALF, k.HALF, sill1, head0, tex=k.jamb_light(JAMB - 0.25, "alu"))
    f.box("frame", "alu", E - JAMB, E - WALL, -k.HALF, k.HALF, sill1, head0)
    f.box("mullion", "alu", MULLION[0], MULLION[1], -k.RECESS - 0.25, k.RECESS + 0.25, sill1, head0)
    if spec["transom"]:
        t0, t1 = spec["transom"]
        f.box("mullion", "alu", JAMB, E - JAMB, -k.RECESS - 0.25, k.RECESS + 0.25, t0, t1)
    f.box("glass", "glass", JAMB, E - JAMB, -k.RECESS, k.RECESS, sill1, head0, tex=glass_face)
    if tall:
        level = BLIND_LEVELS[blind]
        f.box("blind", "blind", JAMB, E - JAMB, k.RECESS, k.RECESS + 0.5, level + 2, head0, tex=blind_face)
        f.box("blind_bar", "alu", JAMB, E - JAMB, k.RECESS, k.RECESS + 1.0, level, level + 2)


def render(edge: str, tall: bool, color: str, blind: int = 0) -> np.ndarray:
    f = k.Along(edge)
    model(f, tall, blind)
    height = k.WALL_TOP if tall else k.LOW
    return k.draw(f.solids + k.ghosts(edge, height), k.wall_canvas(edge, tall),
                  [k.wall_mat(color), k.CAP, k.ALU, GLASS, SHINE, BLIND], k.ink_side(edge))[0]


def sprites() -> Iterator[k.Sprite]:
    for color, *_ in k.WALL_COLORS:
        for tall in (True, False):
            for edge in ("x", "y"):
                base = k.colored(f"window_{'tall' if tall else 'low'}_{edge}", color)
                entry = k.wall_entry(edge, tall, color, joins=True)
                if tall:
                    entry["height"] = k.DATA["window"]["height"]
                yield k.Sprite(base, render(edge, tall, color), entry)
                if tall:
                    images = [render(edge, True, color, step) for step in range(1, len(BLIND_LEVELS))]
                    names = [k.colored(f"window_tall_{edge}_blind_{n}", color) for n in range(1, len(BLIND_LEVELS))]
                    yield from k.frame_sprites(names, images, (0, 0, 0, 0), True, lambda step, base=base, edge=edge, color=color: {
                        "base": base + ".png", "animation": "blind", "axis": edge, "wall_color": color})


if __name__ == "__main__":
    raise SystemExit(k.main("las ventanas", sprites, HERE))
