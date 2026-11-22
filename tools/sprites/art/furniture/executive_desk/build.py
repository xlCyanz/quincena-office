"""Escritorio ejecutivo (2 x 1) de Quincena Office, hecho con Moana. Usa ../_desk_kit.py.

Nogal oscuro: dos cajoneras enteras sobre zócalo, panel de la visita (atrás, +y) con tres tableros
rehundidos y tablero grueso con filo dorado a media altura del canto.

Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/executive_desk/build.py [--out DIR] [--preview]

Sin --out reescribe esta carpeta. El apoyo de cada PNG va en manifest.json.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _desk_kit import (COLORS, NEG_X, POS_X, POS_Y, TOP_Z, Box, DeskSpec, drawer_pedestal,  # noqa: E402
                       grain, main, shade, side_bands, sunken_panel)

SLAB = 7  # tablero más grueso que el de los otros escritorios
UNDER_Z = TOP_Z - SLAB
TOP = (1, 63, 2, 30)
PEDESTALS = ((2, 15), (49, 62))
PED_Y = (4, 28)
PED_Z0 = 3
DRAWERS = ((6, 15), (16, 25), (26, 35))
MODESTY_Y = (24, 27)  # panel de la visita, 1 unidad hundido respecto de las cajoneras
MODESTY_Z0 = 4
MODESTY_PANELS = 3
GOLD_Z = TOP_Z - 3  # filo dorado a media altura del canto

WALNUT = (0xA0, 0x60, 0x3A)
COLORS_WALNUT = {
    **COLORS,
    "ink": "#2A1206FF",
    "ink_in": "#4A2410FF",
    "wood_light": "#BD7A4CFF",
    "wood_top": shade(WALNUT, 1.0),
    "wood_grain": shade(WALNUT, 0.88),
    "wood_left": shade(WALNUT, 0.75),
    "wood_right": shade(WALNUT, 0.60),
    "wood_dark": shade(WALNUT, 0.42),
    "wood_deep": shade(WALNUT, 0.30),
    "brass": "#E0B84AFF",
}


def model(_spec: DeskSpec) -> tuple[list[Box], Box]:
    py0, py1 = PED_Y
    under: list[Box] = []
    for tag, (x0, x1) in zip("ab", PEDESTALS):
        under.append(Box(f"plinth_{tag}", x0 + 1, x1 - 1, py0 + 1, py1 - 1, 0, PED_Z0, tone=-1))
        under.append(drawer_pedestal(f"pedestal_{tag}", x0, x1, py0, py1, PED_Z0, UNDER_Z, DRAWERS, (POS_Y, POS_X, NEG_X)))

    mx0, mx1 = PEDESTALS[0][1], PEDESTALS[1][0]
    my0, my1 = MODESTY_Y
    modesty = Box("modesty", mx0, mx1, my0, my1, MODESTY_Z0, UNDER_Z)
    step = (mx1 - mx0 - 2) / MODESTY_PANELS
    for k in range(MODESTY_PANELS):
        a0 = mx0 + 1 + round(k * step) + 1
        a1 = mx0 + 1 + round((k + 1) * step) - 1
        modesty.decals += sunken_panel(f"board{k}", POS_Y, my1, a0, a1, MODESTY_Z0 + 4, UNDER_Z - 4)
    modesty.decals += side_bands(modesty, "base", "@dark", MODESTY_Z0 + 2, rows=2)
    under.append(modesty)

    tx0, tx1, ty0, ty1 = TOP
    top = Box("top", tx0, tx1, ty0, ty1, UNDER_Z, TOP_Z)
    top.decals += side_bands(top, "gold", "brass", GOLD_Z)
    grain(top, TOP_Z)
    return under, top


SPEC = DeskSpec(name="executive_desk", size=(2, 1), canvas=(192, 160), model=model, colors=COLORS_WALNUT,
                contact=("pedestal_a", "pedestal_b", "modesty"))

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
