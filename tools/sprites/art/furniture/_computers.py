"""Piezas de las computadoras (básica y pro) y sus paletas, para dibujarlas solas o sobre el escritorio largo.

Planta en unidades (1/32 de casilla) en rotación 0, con la pantalla mirando a -y. Las medidas salen de
tools/sprites/pieces/desk.py, así el teclado queda donde el juego sienta a la persona (``seats``).
Quien se sienta mira hacia +y, así que su derecha es -x: el ratón va del lado -x del teclado.
``ink`` es el prefijo de los colores de contorno: "" sola, "pc_" sobre un escritorio de madera.
"""

from __future__ import annotations

import math
from typing import Optional

from _computer_kit import DESK_Z, glass, keyboard, mouse, vents_top
from _desk_kit import COLORS, NEG_X, NEG_Y, POS_X, POS_Y, Box, Decal, face_rect, material

SCREEN_Y = 13  # cara de las pantallas de la pro

COLORS_BASIC = {
    "ink": "#4A3F2CFF",
    "ink_in": "#8A7A58FF",
    **material("case", (0xE4, 0xD6, 0xB4), "#F6EED8FF"),
    **material("glass", (0x6B, 0x8A, 0x92), "#9DB8BEFF"),
    "key": "#C9B88FFF",
    "led": "#6FE08AFF",
    "shadow_ink": COLORS["shadow_ink"],
}

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


def with_ink(boxes: list[Box], ink: str) -> list[Box]:
    for b in boxes:
        b.ink = ink
    return boxes


# ---------------------------------------------------------------------------- básica

CRT_W, CRT_Y = 12, (10, 20)  # caja del tubo; la culata (3 más) no se sale del tablero, que acaba en y = 22
CRT_H = 34
BEZEL_SIDE, BEZEL_TOP, CHIN = 1, 4, 14  # bisel en unidades a los lados, px arriba y mentón en px


def basic_set(x0: float, ink: str = "") -> list[Box]:
    """Todo en uno crema de tubo desde x0, con su teclado delante y el ratón a la derecha (-x)."""
    x1 = x0 + CRT_W
    y0, y1 = CRT_Y
    z1 = DESK_Z + CRT_H
    crt = Box("crt", x0, x1, y0, y1, DESK_Z, z1, mat="case")
    crt.decals += glass("screen", y0, x0 + BEZEL_SIDE, x1 - BEZEL_SIDE, DESK_Z + CHIN, z1 - BEZEL_TOP)
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
            y = y - 3  # medidas de cuando la caja empezaba en y = 13
            crt.decals.append(Decal(f"vent_{plane}_{k}", "@deep", normal,
                                    face_rect(normal, plane, y, y + 0.5, DESK_Z + 4, z1 - 4)))
    # Rejilla arriba, hacia atrás, y la culata del tubo con sus ranuras.
    vents_top(crt, "top_vent", y1 - 4, y1 - 1.5)
    tube = Box("tube", x0 + 2, x1 - 2, y1, y1 + 3, DESK_Z + 6, z1 - 6, mat="case")
    vents_top(tube, "tube_vent", y1 + 1, y1 + 2, inset=1)
    for k, z in enumerate(range(DESK_Z + 10, z1 - 9, 3)):
        tube.decals.append(Decal(f"rear{k}", "@deep", POS_Y, [(x0 + 3.5, y1 + 3, z), (x1 - 3.5, y1 + 3, z)]))
    # Logo del fabricante: una rayita bajo el vidrio, a la izquierda.
    crt.decals.append(Decal("badge", "@dark", NEG_Y, [(x0 + 1.5, y0, DESK_Z + CHIN - 3), (x0 + 3.5, y0, DESK_Z + CHIN - 3)]))
    parts = [crt, tube, keyboard(x0, x1, 3, 8, mat="case", key="key"), *mouse(x0 - 3, 6, mat="case")]
    return with_ink(parts, ink)


# ---------------------------------------------------------------------------- pro

SCREEN_W, SCREEN_DEPTH = 17, 2
SCREEN_Z = (DESK_Z + 8, DESK_Z + 33)
BEZEL, PRO_CHIN = 0.5, 3  # bisel en unidades a los lados y arriba (1 px), mentón en px
TOWER_H = 26


def monitor(x0: float, prefix: str = "") -> list[Box]:
    """Pantalla plana negra sobre su pie, con bulto y rejillas atrás."""
    x1 = x0 + SCREEN_W
    y0, y1 = SCREEN_Y, SCREEN_Y + SCREEN_DEPTH
    z0, z1 = SCREEN_Z
    mid = (x0 + x1) / 2
    foot = Box(f"{prefix}foot", mid - 4, mid + 4, y0 - 1, y0 + 5, DESK_Z, DESK_Z + 2, mat="plastic")
    neck = Box(f"{prefix}neck", mid - 2, mid + 2, y1 + 1, y1 + 2, DESK_Z + 2, z0 + 6, mat="plastic")
    screen = Box(f"{prefix}screen", x0, x1, y0, y1, z0, z1, mat="plastic")
    screen.decals += glass("display", y0, x0 + BEZEL, x1 - BEZEL, z0 + PRO_CHIN, z1 - 1)
    screen.decals += [
        Decal("power", "led", NEG_Y, face_rect(NEG_Y, y0, x1 - 2.5, x1 - 1.5, z0 + 1, z0 + 2)),
        Decal("logo", "@lit", NEG_Y, [(mid - 1, y0, z0 + 2), (mid + 1, y0, z0 + 2)]),
    ]
    bulge = Box(f"{prefix}bulge", x0 + 4, x1 - 4, y1, y1 + 1, z0 + 3, z1 - 4, mat="plastic")
    for k, z in enumerate((z1 - 7, z1 - 10)):
        bulge.decals += [
            Decal(f"vent{k}", "@deep", POS_Y, [(x0 + 5.5, y1 + 1, z), (x1 - 5.5, y1 + 1, z)]),
            Decal(f"vent{k}_lit", "@lit", POS_Y, [(x0 + 5.5, y1 + 1, z - 1), (x1 - 5.5, y1 + 1, z - 1)]),
        ]
    return [foot, neck, bulge, screen]


def tower(x0: float, x1: float, y0: float, y1: float, base: float = DESK_Z) -> Box:
    """Torre negra: tira de luz y LED al frente, ventana con luces y ventilador a los costados, rejillas."""
    z1 = base + TOWER_H if base == DESK_Z else base + 28
    box = Box("tower", x0, x1, y0, y1, base, z1, mat="plastic")
    box.decals += [
        Decal("strip", "cyan", NEG_Y, face_rect(NEG_Y, y0, x0 + 1, x0 + 2, base + 4, z1 - 4)),
        Decal("power", "led", NEG_Y, face_rect(NEG_Y, y0, x0 + 3, x0 + 4, z1 - 6, z1 - 4)),
    ]
    for normal, plane in ((POS_X, x1), (NEG_X, x0)):
        t = "px" if normal == POS_X else "nx"
        box.decals += [
            Decal(f"window_{t}", "@deep", normal, face_rect(normal, plane, y0 + 1.5, y1 - 1.5, base + 4, z1 - 4)),
            Decal(f"bar_hi_{t}", "cyan", normal, face_rect(normal, plane, y0 + 2.5, y1 - 2.5, z1 - 9, z1 - 7)),
            Decal(f"bar_lo_{t}", "cyan", normal, face_rect(normal, plane, y0 + 2.5, y1 - 2.5, base + 7, base + 9)),
            Decal(f"fan_{t}", "cyan_dark", normal, face_rect(normal, plane, (y0 + y1) / 2 - 1.5, (y0 + y1) / 2 + 1.5,
                                                           base + 11, z1 - 11)),
        ]
    for k, z in enumerate(range(int(base) + 6, int(z1) - 5, 3)):
        box.decals.append(Decal(f"grille{k}", "@deep", POS_Y, [(x0 + 1, y1, z), (x1 - 1, y1, z)]))
    vents_top(box, "top_vent", y0 + 3, y1 - 3, step=2, inset=1)
    box.decals += [
        Decal("button", "@lit", NEG_Y, face_rect(NEG_Y, y0, x1 - 2, x1 - 1, z1 - 4, z1 - 2)),
        Decal("usb0", "@deep", NEG_Y, face_rect(NEG_Y, y0, x0 + 3, x0 + 4, z1 - 10, z1 - 9)),
        Decal("usb1", "@deep", NEG_Y, face_rect(NEG_Y, y0, x0 + 3, x0 + 4, z1 - 13, z1 - 12)),
    ]
    return box


def wing(inner_x: float, side: int, prefix: str, width: float = SCREEN_W, turn: float = 0.5) -> list[Box]:
    """Pantalla extra girada hacia quien se sienta: sale de inner_x hacia ``side`` (±1) y viene al frente
    ``turn`` unidades por unidad de ancho. Pie y cuello en su punto medio."""
    z0, z1 = SCREEN_Z
    length = math.hypot(1.0, turn)
    dx, dy = side * width / length, -width * turn / length
    nx, ny = -dy / width, dx / width  # normal de la cara, hacia el frente (-y)
    if ny > 0:
        nx, ny = -nx, -ny
    t = 1.6  # grosor
    a = (inner_x, SCREEN_Y)
    b = (inner_x + dx, SCREEN_Y + dy)
    quad = [a, b, (b[0] - nx * t, b[1] - ny * t), (a[0] - nx * t, a[1] - ny * t)]
    panel = Box.prism(f"{prefix}panel", quad, z0, z1, mat="plastic")
    # Vidrio sobre la cara de adelante (normal hacia -y girada), con su bisel de 1 px.
    normal = (nx, ny, 0)
    ex, ey = dx / width, dy / width

    def at(u: float, z: float) -> tuple[float, float, float]:
        return (a[0] + ex * u, a[1] + ey * u, z)

    g0, g1 = 1.0, width - 1.0
    gz0, gz1 = z0 + PRO_CHIN, z1 - 1
    corners = [at(g0, gz1), at(g1, gz1), at(g1, gz0), at(g0, gz0)]
    panel.decals += [
        Decal("glass", "glass_top", normal, corners),
        Decal("glass_shade", "glass_dark", normal, [at(g0, gz1), at(g1, gz1)]),
        Decal("glass_glare", "glass_light", normal, [at(width * 0.6, gz1 - 1), at(width * 0.6 + 2.5, gz1 - 1),
                                                     at(width * 0.6 - 4, gz0 + 4), at(width * 0.6 - 6.5, gz0 + 4)]),
        Decal("power", "led", normal, [at(width - 2.5, z0 + 2), at(width - 1.5, z0 + 2), at(width - 1.5, z0 + 1), at(width - 2.5, z0 + 1)]),
    ]
    mx, my = round((inner_x + dx / 2) * 2) / 2, round((SCREEN_Y + dy / 2) * 2) / 2
    foot = Box(f"{prefix}foot", mx - 3, mx + 3, my - 1, my + 4, DESK_Z, DESK_Z + 2, mat="plastic")
    neck = Box(f"{prefix}neck", mx - 1, mx + 1, my + 1.5, my + 2.5, DESK_Z + 2, z0 + 5, mat="plastic")
    return [foot, neck, panel]


def pro_set(screen_x: float, keyboard_x: float, mouse_x: float, tower_box: Optional[Box], ink: str = "",
            wings: tuple[tuple[float, int], ...] = ()) -> list[Box]:
    """Pantalla principal, teclado (14 de largo) y ratón negros, la torre (si va encima) y las pantallas extra."""
    parts = [*([tower_box] if tower_box else []), *monitor(screen_x), keyboard(keyboard_x, keyboard_x + 14, 2, 7, mat="plastic", key="key"),
             *mouse(mouse_x, 4, mat="plastic")]
    for i, (inner_x, side) in enumerate(wings):
        parts += wing(inner_x, side, f"wing{i}_")
    return with_ink(parts, ink)
