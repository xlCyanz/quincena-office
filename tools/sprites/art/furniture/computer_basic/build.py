"""Computadora básica de Quincena Office (todo en uno crema de tubo, teclado y ratón), hecha con Moana.

Va encima de un escritorio; ver ../_computer_kit.py. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/computer_basic/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _computer_kit import (DESK_Z, NEG_X, NEG_Y, POS_X, POS_Y, Box, Decal, DeskSpec, face_rect, glass,  # noqa: E402
                           keyboard, main, mouse, vents_top)
from _desk_kit import COLORS, material  # noqa: E402

# Planta en unidades (1/32 de casilla), como en tools/sprites/pieces/desk.py: el teclado entre x 10 y 22
# deja a quien se sienta en el medio de la casilla.
CRT = (10, 22, 10, 20)  # caja del tubo: x0, x1, y0, y1 (la culata no se sale del tablero, que acaba en y = 22)
CRT_Z1 = DESK_Z + 34
BEZEL_SIDE, BEZEL_TOP, CHIN = 1, 4, 14  # bisel en unidades a los lados, px arriba y mentón en px
KEYBOARD = (10, 22, 3, 8)
MOUSE = (25, 6)

COLORS_BASIC = {
    "ink": "#4A3F2CFF",
    "ink_in": "#8A7A58FF",
    **material("case", (0xE4, 0xD6, 0xB4), "#F6EED8FF"),
    **material("glass", (0x6B, 0x8A, 0x92), "#9DB8BEFF"),
    "key": "#C9B88FFF",
    "led": "#6FE08AFF",
    "shadow_ink": COLORS["shadow_ink"],
}


def model(_spec: DeskSpec) -> tuple[list[Box], None]:
    x0, x1, y0, y1 = CRT
    crt = Box("crt", x0, x1, y0, y1, DESK_Z, CRT_Z1, mat="case")
    crt.decals += glass("screen", y0, x0 + BEZEL_SIDE, x1 - BEZEL_SIDE, DESK_Z + CHIN, CRT_Z1 - BEZEL_TOP)
    slot_z = DESK_Z + CHIN // 2 + 1
    crt.decals += [
        # Ranura del disquete con su canto claro abajo, luz de encendido y zócalo marcado.
        Decal("floppy", "@deep", NEG_Y, [((x0 + x1) / 2, y0, slot_z), (x1 - 1.5, y0, slot_z)]),
        Decal("floppy_lit", "@lit", NEG_Y, [((x0 + x1) / 2, y0, slot_z - 1), (x1 - 1.5, y0, slot_z - 1)]),
        Decal("power", "led", NEG_Y, face_rect(NEG_Y, y0, x0 + 1, x0 + 2, slot_z - 2, slot_z)),
        Decal("plinth", "@dark", NEG_Y, [(x0, y0, DESK_Z + 3), (x1, y0, DESK_Z + 3)]),
    ]
    # Ranuras de ventilación verticales en los costados.
    for normal, plane in ((POS_X, x1), (NEG_X, x0)):
        for k, y in enumerate((16, 17.5, 19, 20.5)):
            crt.decals.append(Decal(f"vent_{plane}_{k}", "@deep", normal,
                                    face_rect(normal, plane, y, y + 0.5, DESK_Z + 4, CRT_Z1 - 4)))
    # Rejilla arriba, hacia atrás, y la culata del tubo con sus ranuras.
    vents_top(crt, "top_vent", y1 - 4, y1 - 1.5)
    tube = Box("tube", x0 + 2, x1 - 2, y1, y1 + 3, DESK_Z + 6, CRT_Z1 - 6, mat="case")
    vents_top(tube, "tube_vent", y1 + 1, y1 + 2, inset=1)
    for k, z in enumerate(range(DESK_Z + 10, CRT_Z1 - 9, 3)):
        tube.decals.append(Decal(f"rear{k}", "@deep", POS_Y, [(x0 + 3.5, y1 + 3, z), (x1 - 3.5, y1 + 3, z)]))
    # Logo del fabricante: una rayita bajo el vidrio, a la izquierda.
    crt.decals.append(Decal("badge", "@dark", NEG_Y, [(x0 + 1.5, y0, DESK_Z + CHIN - 3), (x0 + 3.5, y0, DESK_Z + CHIN - 3)]))
    parts = [crt, tube, keyboard(*KEYBOARD, mat="case", key="key"), *mouse(*MOUSE, mat="case")]
    return parts, None


SPEC = DeskSpec(name="computer_basic", size=(1, 1), canvas=(128, 160), model=model, colors=COLORS_BASIC,
                contact=("crt", "keyboard", "mouse"))

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
