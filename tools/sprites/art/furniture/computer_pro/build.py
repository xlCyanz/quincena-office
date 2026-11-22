"""Computadora pro de Quincena Office (pantalla plana negra, torre, teclado y ratón), hecha con Moana.

Va encima de un escritorio; ver ../_computer_kit.py. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/computer_pro/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _computer_kit import (DESK_Z, NEG_X, NEG_Y, POS_X, POS_Y, Box, Decal, DeskSpec, face_rect, glass,  # noqa: E402
                           keyboard, main, mouse, vents_top)
from _desk_kit import COLORS, material  # noqa: E402

# Planta en unidades, como en tools/sprites/pieces/desk.py (el teclado entre x 12 y 26).
SCREEN = (11, 28, 13, 15)  # pantalla plana de 2 unidades de fondo
SCREEN_Z = (DESK_Z + 8, DESK_Z + 33)
BEZEL, CHIN = 0.5, 3  # bisel en unidades a los lados y arriba (1 px), mentón en px
KEYBOARD = (12, 26, 2, 7)
MOUSE = (8, 4)
TOWER = (3, 8, 9, 21, DESK_Z + 26)  # x0, x1, y0, y1, alto

COLORS_PRO = {
    "ink": "#08080AFF",
    "ink_in": "#101012FF",
    **material("plastic", (0x4A, 0x4A, 0x52), "#7C7C88FF"),
    **material("glass", (0x2A, 0x2B, 0x36), "#6A6E80FF"),
    "key": "#7A7A84FF",
    "cyan": "#3FE0E8FF",
    "cyan_dark": "#1F8A90FF",
    "led": "#6FE08AFF",
    "shadow_ink": COLORS["shadow_ink"],
}


def monitor() -> list[Box]:
    x0, x1, y0, y1 = SCREEN
    z0, z1 = SCREEN_Z
    mid = (x0 + x1) / 2
    foot = Box("foot", mid - 4, mid + 4, y0 - 1, y0 + 5, DESK_Z, DESK_Z + 2, mat="plastic")
    neck = Box("neck", mid - 2, mid + 2, y1 + 1, y1 + 2, DESK_Z + 2, z0 + 6, mat="plastic")
    screen = Box("screen", x0, x1, y0, y1, z0, z1, mat="plastic")
    screen.decals += glass("display", y0, x0 + BEZEL, x1 - BEZEL, z0 + CHIN, z1 - 1)
    screen.decals += [
        Decal("power", "led", NEG_Y, face_rect(NEG_Y, y0, x1 - 2.5, x1 - 1.5, z0 + 1, z0 + 2)),
        Decal("logo", "@lit", NEG_Y, [(mid - 1, y0, z0 + 2), (mid + 1, y0, z0 + 2)]),
    ]
    # Espalda: bulto con dos ranuras de ventilación.
    bulge = Box("bulge", x0 + 4, x1 - 4, y1, y1 + 1, z0 + 3, z1 - 4, mat="plastic")
    for k, z in enumerate((z1 - 7, z1 - 10)):
        bulge.decals += [
            Decal(f"vent{k}", "@deep", POS_Y, [(x0 + 5.5, y1 + 1, z), (x1 - 5.5, y1 + 1, z)]),
            Decal(f"vent{k}_lit", "@lit", POS_Y, [(x0 + 5.5, y1 + 1, z - 1), (x1 - 5.5, y1 + 1, z - 1)]),
        ]
    return [foot, neck, bulge, screen]


def tower() -> Box:
    """Torre negra: tira de luz y LED al frente, ventana con luces y ventilador a los costados, rejilla atrás."""
    x0, x1, y0, y1, z1 = TOWER
    box = Box("tower", x0, x1, y0, y1, DESK_Z, z1, mat="plastic")
    box.decals += [
        Decal("strip", "cyan", NEG_Y, face_rect(NEG_Y, y0, x0 + 1, x0 + 2, DESK_Z + 4, z1 - 4)),
        Decal("power", "led", NEG_Y, face_rect(NEG_Y, y0, x0 + 3, x0 + 4, z1 - 6, z1 - 4)),
    ]
    for normal, plane in ((POS_X, x1), (NEG_X, x0)):
        t = "px" if normal == POS_X else "nx"
        box.decals += [
            Decal(f"window_{t}", "@deep", normal, face_rect(normal, plane, y0 + 1.5, y1 - 1.5, DESK_Z + 4, z1 - 4)),
            Decal(f"bar_hi_{t}", "cyan", normal, face_rect(normal, plane, y0 + 2.5, y1 - 2.5, z1 - 9, z1 - 7)),
            Decal(f"bar_lo_{t}", "cyan", normal, face_rect(normal, plane, y0 + 2.5, y1 - 2.5, DESK_Z + 7, DESK_Z + 9)),
            Decal(f"fan_{t}", "cyan_dark", normal, face_rect(normal, plane, (y0 + y1) / 2 - 1.5, (y0 + y1) / 2 + 1.5,
                                                           DESK_Z + 11, z1 - 11)),
        ]
    for k, z in enumerate(range(DESK_Z + 6, z1 - 5, 3)):
        box.decals.append(Decal(f"grille{k}", "@deep", POS_Y, [(x0 + 1, y1, z), (x1 - 1, y1, z)]))
    vents_top(box, "top_vent", y0 + 3, y1 - 3, step=2, inset=1)
    # Botón de encendido arriba del frente y puertos USB debajo.
    box.decals += [
        Decal("button", "@lit", NEG_Y, face_rect(NEG_Y, y0, x1 - 2, x1 - 1, z1 - 4, z1 - 2)),
        Decal("usb0", "@deep", NEG_Y, face_rect(NEG_Y, y0, x0 + 3, x0 + 4, z1 - 10, z1 - 9)),
        Decal("usb1", "@deep", NEG_Y, face_rect(NEG_Y, y0, x0 + 3, x0 + 4, z1 - 13, z1 - 12)),
    ]
    return box


def model(_spec: DeskSpec) -> tuple[list[Box], None]:
    return [tower(), *monitor(), keyboard(*KEYBOARD, mat="plastic", key="key"), *mouse(*MOUSE, mat="plastic")], None


SPEC = DeskSpec(name="computer_pro", size=(1, 1), canvas=(128, 160), model=model, colors=COLORS_PRO,
                contact=("foot", "keyboard", "mouse", "tower"))

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
