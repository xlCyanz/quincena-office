"""Máquina expendedora de Quincena Office (1×1, cuatro rotaciones), hecha con Moana. Ver ../_boxes.py.

Gabinete rojo de esquinas redondeadas y tapa curva sobre un zócalo oscuro, con una franja crema en
diagonal en los costados. Al frente, piezas en relieve: el
letrero iluminado arriba, la puerta de vidrio con cuatro estantes de golosinas (latas, bolsas y barras con su
precio) y reflejos, el panel de control (pantalla verde, teclado, ranura de monedas y lector de tarjetas) y
abajo la bandeja de retiro con su tapa. El frente mira a −y en rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/vending_machine/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, colors, faces, frame, ramp, rect  # noqa: E402
from _chair_kit import PieceSpec, main_piece, slab  # noqa: E402

GROUP = "vending"
X0, X1, Y0, Y1 = 5.1, 26.9, 8.0, 25.6
FY0, FY1 = 6.6, 8.5  # piezas del frente
PLINTH, LOW, SIGN, TOP = 3.0, 22.0, 73.0, 80.0
PANEL_X = (5.7, 11.0)  # el panel queda a la derecha mirando el frente
GLASS_X = (11.4, 26.3)

RED = ramp("red", "#D23F3AFF", "#B23531FF", "#8E2A27FF", "#3A0C0AFF", "#E87B76FF", "#5A1919FF")
DARK = ramp("dark", "#3B3F45FF", "#2C2F34FF", "#232629FF", "#0E0F10FF", "#5C5F66FF", "#15191DFF")
PANEL = ramp("panel", "#E8E9EAFF", "#D3D5D7FF", "#B8BCBFFF", "#2F3437FF", "#FFFFFFFF", "#8C96A0FF")
PARTS = colors("parts", "#15191DFF", light="#7F98A8FF", top="#27313AFF", upper="#3E4A55FF", left="#6FE08AFF",
               right="#F2E6C8FF", dark="#1B2229FF")
SNACK = colors("snack", "#15191DFF", light="#F2F2F2FF", top="#F0B030FF", upper="#6FE08AFF", left="#4F9BD0FF",
               right="#E05AE0FF", dark="#F08A2CFF")
SHINE, GLASS, SHELF, DIGITS, CREAM, DEEP = ("parts.light", "parts.top", "parts.upper", "parts.left", "parts.right",
                                            "parts.dark")
SNACKS = np.array(["snack.top", "snack.upper", "snack.left", "snack.light", "snack.right", "snack.dark"])


def rounded(part: str, mat: str, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, r: float,
            bevel: float, **kw: object):
    return slab(part, GROUP, mat, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, r, z0, z1,
                bevel=bevel, bevel_z=1.5, lit=True, **kw)


def glass_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Vitrina: marco rojo, cuatro estantes con golosinas de alturas distintas y su precio, y dos reflejos."""
    f = faces(mx, my, mz, *GLASS_X, FY0, FY1, LOW + 0.5, SIGN - 0.5)
    out = tone.copy()
    g0, g1 = 2.0, f.height - 2.0
    glass = f.front & rect(f, 2, -2, g0, g1)
    out[glass] = GLASS
    step = (g1 - g0) / 4.0
    col = np.floor((f.a - 3) / 4.0).astype(int)
    for k in range(4):
        s0 = g0 + k * step
        out[glass & (f.b >= s0) & (f.b < s0 + 1)] = SHELF
        out[glass & (f.b >= s0 + 1) & (f.b < s0 + 2) & (np.mod(f.a - 3, 4) < 1)] = CREAM  # precio
        tall = 4.0 + np.mod(col * 3 + k * 5, 4)  # alto de cada golosina
        snack = glass & (f.b >= s0 + 2) & (f.b < s0 + 2 + np.minimum(tall, step - 3)) & (np.mod(f.a - 3, 4) < 3)
        snack &= (f.a >= 3) & (f.a < f.width - 3)
        kind = np.mod(col + 2 * k, len(SNACKS))
        out[snack] = SNACKS[kind[snack]]
        top = snack & (f.b >= s0 + 1 + np.minimum(tall, step - 3))  # tapa más oscura de cada golosina
        out[top] = DEEP
    shine = glass & (np.abs(np.mod(f.a - f.b * 0.6, 26) - 4) < 0.5) & (f.b > g1 * 0.35)
    out[shine] = SHINE
    return out


def panel_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Pantalla verde, teclado de 2 × 4, ranura de monedas y lector de tarjetas."""
    f = faces(mx, my, mz, *PANEL_X, FY0, FY1, LOW + 0.5, SIGN - 0.5)
    out = tone.copy()
    h = f.height
    out[f.front & rect(f, 2, -2, h - 8, h - 3)] = DEEP
    out[f.front & rect(f, 3, -3, h - 7, h - 4) & (np.mod(f.a, 2) < 1)] = DIGITS
    keys = f.front & rect(f, 2, -2, h - 22, h - 11) & (np.mod(f.a - 2, 4) < 2.5) & (np.mod(f.b - (h - 22), 3) < 2)
    out[keys] = "panel.dark"
    out[f.front & rect(f, 4, -4, h - 27, h - 25)] = DEEP  # monedas
    out[f.front & rect(f, 2, -2, h - 34, h - 30)] = "dark.top"  # lector de tarjetas
    out[f.front & rect(f, 3, 5, h - 33, h - 32)] = DIGITS
    return out


def sign_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Letrero claro con letras rojas."""
    f = faces(mx, my, mz, X0 + 0.5, X1 - 0.5, FY0, FY1, SIGN, TOP - 1.0)
    out = tone.copy()
    out[f.front & rect(f, 2, -2, 1, f.height - 1)] = CREAM
    letters = f.front & rect(f, 6, -6, 2, f.height - 2) & (np.mod(f.a - 6, 5) < 3)
    letters &= ~((np.mod(f.a - 6, 5) == 1) & (np.abs(f.b - f.height / 2) < 0.6))
    out[letters] = "red.top"
    return out


def bottom_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Bandeja de retiro con su tapa basculante."""
    f = faces(mx, my, mz, X0 + 0.5, X1 - 0.5, FY0, FY1, PLINTH + 0.5, LOW)
    out = tone.copy()
    out[f.front & rect(f, 12, -4, 4, 14)] = DEEP
    out[f.front & rect(f, 13, -5, 8, 13)] = "dark.top"  # tapa
    out[f.front & rect(f, 13, -5, 12, 13)] = "dark.light"
    out[f.front & rect(f, 4, 8, 6, 9)] = DEEP  # devolución de monedas
    return out


def body_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Franja crema en diagonal en los costados (la marca) y una línea de luz cerca del frente."""
    out = tone.copy()
    side = ((mx < X0 + 0.3) | (mx > X1 - 0.3)) & (mz > PLINTH + 1.5) & (mz < TOP - 2.0)
    d = (mz - PLINTH) - (my - Y0) * 2.0 * 1.2  # sube hacia atrás
    out[side & (np.abs(d - 10.0) < 2.0)] = CREAM
    out[side & (np.abs(d - 15.0) < 0.7)] = CREAM
    out[side & (my > Y0 + 1.5) & (my < Y0 + 2.2)] = "red.top"
    return out


def model() -> list:
    return [
        box("plinth", GROUP, "dark", X0 + 1.0, X1 - 1.0, Y0 - 1.0, Y1 - 1.0, 0, PLINTH),
        rounded("body", "red", X0, X1, Y0, Y1, PLINTH, TOP, 2.0, 1.0, texture=body_texture),
        rounded("sign", "red", X0 + 0.5, X1 - 0.5, FY0, FY1, SIGN, TOP - 1.0, 0.8, 0.3, texture=sign_texture),
        rounded("glass", "red", *GLASS_X, FY0, FY1, LOW + 0.5, SIGN - 0.5, 0.8, 0.3, texture=glass_texture),
        rounded("panel", "panel", *PANEL_X, FY0, FY1, LOW + 0.5, SIGN - 0.5, 0.8, 0.3, texture=panel_texture),
        rounded("bottom", "red", X0 + 0.5, X1 - 0.5, FY0, FY1, PLINTH + 0.5, LOW, 0.8, 0.3, texture=bottom_texture),
    ]


SPEC = PieceSpec(
    name="vending_machine",
    mats={m.name: m for m in (RED, DARK, PANEL, PARTS, SNACK)},
    model=model,
    shadow=[("bar", 16.0, 9.6, 16.0, 23.0, 11.2, 0, TOP)],
    max_colors=34,
    canvas=(128, 160),
    rotations=(0, 1, 2, 3),
    painter=True,
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
