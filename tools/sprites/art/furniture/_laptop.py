"""Laptop de Quincena Office, como una laptop isométrica de pixel art clásica: base delgada de canto oscuro,
bloque de teclas oscuras con una rejilla clara de 1 px, touchpad grande y la tapa recta (vertical, así sus
aristas quedan en escalera 2:1 limpia) con bisel fino y la pantalla azul petróleo lisa.

Planta en unidades (1/32 de casilla) en rotación 0, con la pantalla mirando a -y como las demás
computadoras. Colores tomados de la referencia que eligió el jugador.
"""

from __future__ import annotations

from _computer_kit import DESK_Z, NEG_Y, POS_Y, Box, Decal, face_rect
from _desk_kit import COLORS

COLORS_LAPTOP = {
    "ink": "#000000FF",
    "ink_in": "#1A2226FF",
    # Base: arriba gris claro, cantos oscuros.
    "case_light": "#F2F6F8FF",
    "case_top": "#C1CCD0FF",
    "case_grain": "#C1CCD0FF",
    "case_left": "#4F636BFF",
    "case_right": "#43565CFF",
    "case_dark": "#313E44FF",
    "case_deep": "#242D32FF",
    # Tapa: marco claro.
    "lid_light": "#E5EAEEFF",
    "lid_top": "#C1CCD0FF",
    "lid_grain": "#C1CCD0FF",
    "lid_left": "#B4C2CAFF",
    "lid_right": "#9DAFB9FF",
    "lid_dark": "#5B717CFF",
    "lid_deep": "#313E44FF",
    "screen": "#21455FFF",
    "key": "#242D32FF",
    "pad": "#5B717CFF",
    "led": "#6FE08AFF",
    "shadow_ink": COLORS["shadow_ink"],
}

W, D = 22, 15  # base: 44 px a lo largo de x (la bisagra) y 15 unidades de fondo
BASE_H = 3  # grosor de la base en px
LID_H = 30  # alto de la tapa en px
GRID = 2  # paso de la rejilla de teclas, en unidades


def laptop(x0: float, y0: float) -> list[Box]:
    x1, y1 = x0 + W, y0 + D
    top = DESK_Z + BASE_H
    base = Box("base", x0, x1, y0, y1, DESK_Z, top, mat="case")
    z = top

    def rect(name: str, color: str, a0: float, a1: float, b0: float, b1: float) -> Decal:
        return Decal(name, color, (0, 0, 1), [(a0, b0, z), (a1, b0, z), (a1, b1, z), (a0, b1, z)])

    # Teclado: bloque oscuro atravesado por una rejilla del gris de la base (teclas de 1,5 x 1 unidades).
    kx0, kx1, ky0, ky1 = x0 + 1.5, x1 - 1.5, y0 + 6, y1 - 2
    base.decals.append(rect("keys", "key", kx0, kx1, ky0, ky1))
    k = 0
    y = ky0 + GRID - 1
    while y < ky1 - 0.5:
        base.decals.append(Decal(f"row{k}", "case_top", (0, 0, 1), [(kx0, y, z), (kx1, y, z)]))
        y += GRID
        k += 1
    x = kx0 + GRID - 0.5
    while x < kx1 - 0.5:
        base.decals.append(rect(f"col{k}", "case_top", x, x + 0.5, ky0, ky1))
        x += GRID
        k += 1
    # Touchpad: centrado, con la mitad de adelante en sombra como en la referencia.
    mid = (x0 + x1) / 2
    base.decals += [
        rect("touchpad", "pad", mid - 4, mid + 4, y0 + 1.5, y0 + 5),
        rect("touchpad_shade", "case_dark", mid - 4, mid + 4, y0 + 1.5, y0 + 2.5),
        Decal("power", "led", NEG_Y, face_rect(NEG_Y, y0, x1 - 2, x1 - 1, DESK_Z + 1, DESK_Z + 2)),
    ]
    # Tapa recta sobre el borde de atrás: bisel de 1 unidad a los lados, 2 px arriba y 3 abajo, con una
    # línea oscura de 1 px alrededor de la pantalla.
    lid = Box("lid", x0, x1, y1 - 1, y1, top, top + LID_H, mat="lid")
    plane = y1 - 1
    lid.decals += [
        Decal("screen_edge", "ink_in", NEG_Y, face_rect(NEG_Y, plane, x0 + 0.5, x1 - 0.5, top + 2, top + LID_H - 1)),
        Decal("screen", "screen", NEG_Y, face_rect(NEG_Y, plane, x0 + 1, x1 - 1, top + 3, top + LID_H - 2)),
        Decal("logo", "@lit", POS_Y, face_rect(POS_Y, y1, mid - 1, mid + 1, top + 13, top + 17)),
    ]
    return [base, lid]
