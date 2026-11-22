"""Escritorio largo con una computadora encima, en un solo sprite (el juego lo usa en lugar del
escritorio vacío; ver ``sets`` en data/sprites.json). Lo usan los build.py de desk_long_<conjunto>/.

Mismo lienzo y apoyo que desk_long. Las piezas salen de _computers.py con las posiciones del
generador viejo (tools/sprites/pieces/desk.py, LONG_SETS), así el teclado sigue donde el juego sienta
a la persona. La sombra de piso es la del escritorio (y la de la torre si va en el piso).
"""

from __future__ import annotations

from typing import Callable, Optional

from _computers import COLORS_BASIC, COLORS_PRO, basic_set, pro_set, tower, with_ink
from _desk_kit import COLORS, BASE, Box, DeskSpec, shade, standard_model

TOP_X = (9, 55)  # tablero del escritorio largo
CANVAS = (192, 192)
DESK_CONTACT = ("pedestal", "leg0", "leg1")


def merged(pc: dict[str, str]) -> dict[str, str]:
    """Paleta del escritorio más la de la computadora, con su contorno como ``pc_ink`` y ``pc_ink_in``."""
    colors = {**COLORS, "wood_shade": shade(BASE, 0.80)}  # sombra de contacto sobre el tablero
    for key, value in pc.items():
        colors[f"pc_{key}" if key in ("ink", "ink_in") else key] = value
    return colors


def desk_set(name: str, pc: dict[str, str], on_top: Callable[[], list[Box]], contact: tuple[str, ...],
             floor: Optional[Callable[[], list[Box]]] = None) -> DeskSpec:
    def model(spec: DeskSpec) -> tuple[list[Box], Box]:
        under, top = standard_model(spec)
        return under + (floor() if floor else []), top

    return DeskSpec(name=name, size=(2, 1), canvas=CANVAS, top_x=TOP_X, model=model, colors=merged(pc),
                    on_top=lambda _s: on_top(), contact=DESK_CONTACT + contact, max_colors=32)


PC = "pc_"
SETS = {
    "desk_long_basic": desk_set("desk_long_basic", COLORS_BASIC, lambda: basic_set(25, PC), ("crt", "keyboard", "mouse")),
    # pantalla al medio · torre sobre la cajonera
    "desk_long_pro1": desk_set("desk_long_pro1", COLORS_PRO, lambda: pro_set(23, 25, 21.5, tower(46, 51, 9, 21), PC),
                               ("foot", "keyboard", "mouse", "tower")),
    # segunda girada hacia la punta de las patas · principal · torre sobre la cajonera
    "desk_long_pro2": desk_set("desk_long_pro2", COLORS_PRO,
                               lambda: pro_set(25, 26, 22.5, tower(46, 51, 9, 21), PC, wings=((24.5, -1),)),
                               ("foot", "keyboard", "mouse", "tower", "wing0_foot")),
    # tres pantallas en ala y la torre en el piso, debajo de la mesa
    "desk_long_pro3": desk_set("desk_long_pro3", COLORS_PRO,
                               lambda: pro_set(23, 24, 20.5, None, PC, wings=((22.5, -1), (40.5, 1))),
                               ("foot", "keyboard", "mouse", "tower", "wing0_foot", "wing1_foot"),
                               floor=lambda: with_ink([tower(13, 18, 7, 19, base=0)], PC)),
}
