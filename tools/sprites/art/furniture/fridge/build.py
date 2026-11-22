"""Nevera de Quincena Office (1×1, cuatro rotaciones), hecha con Moana. Ver ../_boxes.py.

Cuerpo blanco de esquinas redondeadas y tapa curva, dos puertas abultadas que sobresalen del cuerpo (el
congelador arriba, con pantalla de temperatura y placa de la marca) de canto gris, tiradores en relieve con
soportes, reflejo en los costados, zócalo hundido con rejilla y, en la puerta de abajo, una nota amarilla con
su imán y un imán azul. El frente mira a −y en rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/fridge/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, colors, faces, ramp, rect  # noqa: E402
from _chair_kit import PieceSpec, main_piece, slab  # noqa: E402

GROUP = "fridge"
X0, X1, Y0, Y1 = 5.8, 26.2, 7.6, 25.6  # cuerpo (el frente de las puertas sale hasta DOOR_Y)
DOOR_Y = 6.0
PLINTH, SPLIT, TOP = 4.0, 54.0, 80.0
HANDLE_X = (9.2, 10.6)  # a la derecha mirando el frente

WHITE = ramp("white", "#F4F6F6FF", "#DDE2E2FF", "#C4CBCCFF", "#26252DFF", "#FFFFFFFF", "#8F989CFF")
GREY = ramp("grey", "#A9AFB2FF", "#7E868AFF", "#5F676BFF", "#1F2326FF", "#D3D8D9FF", "#4A5155FF")
DETAIL = colors("detail", "#3D3B44FF", light="#8FD3F0FF", top="#2F3437FF", upper="#F2D25CFF", left="#D8434AFF",
                right="#C9A94AFF", dark="#4F9BD0FF")
DIGITS, SCREEN, NOTE, MAGNET, NOTE_LINE, BLUE = ("detail.light", "detail.top", "detail.upper", "detail.left",
                                                 "detail.right", "detail.dark")


def rounded(part: str, mat: str, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, r: float,
            bevel: float, **kw: object):
    return slab(part, GROUP, mat, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, r, z0, z1,
                bevel=bevel, bevel_z=2.0, lit=True, **kw)


def plinth_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Rejilla de ventilación al frente del zócalo."""
    f = faces(mx, my, mz, X0 + 0.8, X1 - 0.8, Y0 - 0.6, Y1 - 0.8, 0, PLINTH)
    out = tone.copy()
    out[f.front & rect(f, 3, -3, 1, 3) & (np.mod(f.a, 2) < 1)] = "grey.ink"
    return out


def body_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Reflejo vertical en los costados, cerca del frente."""
    out = tone.copy()
    side = ((mx < X0 + 0.3) | (mx > X1 - 0.3)) & (mz < TOP - 2.5) & (mz > PLINTH + 2)
    out[side & (((my > Y0 + 2.5) & (my < Y0 + 3.5)) | ((my > Y0 + 5.0) & (my < Y0 + 5.5)))] = "white.top"
    return out


def door_texture(z0: float, z1: float, low: bool):
    """Canto de la puerta en gris (el burlete); arriba la pantalla de temperatura y la placa de la marca,
    abajo la nota amarilla con su imán y un imán azul."""

    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        f = faces(mx, my, mz, X0 + 0.3, X1 - 0.3, DOOR_Y, Y0 + 0.5, z0, z1)
        out = tone.copy()
        out[f.sides & ~f.front & (my > Y0 - 0.3) & (mz < z1 - 1.5)] = "white.dark"
        if low:
            note = f.front & rect(f, 6, 12, 32, 40)
            out[note] = NOTE
            out[note & ((np.abs(f.b - 34.5) < 0.5) | (np.abs(f.b - 36.5) < 0.5)) & rect(f, 7, 11, 0, 99)] = NOTE_LINE
            out[f.front & rect(f, 8, 10, 39, 41)] = MAGNET
            out[f.front & rect(f, 15, 18, 25, 28)] = BLUE
        else:
            out[f.front & rect(f, 5, 13, 12, 18)] = SCREEN
            out[f.front & rect(f, 6, 12, 14, 16) & (np.mod(f.a, 3) < 2)] = DIGITS
            out[f.front & rect(f, 5, 11, 4, 5)] = "grey.right"  # placa de la marca
        return out

    return texture


def handle_texture(z0: float, z1: float):
    """Soportes oscuros en las puntas del tirador."""

    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        out = tone.copy()
        out[((mz < z0 + 1.5) | (mz > z1 - 1.5)) & (mz < z1 - 0.3)] = "grey.dark"
        return out

    return texture


def model() -> list:
    s = [
        box("plinth", GROUP, "grey", X0 + 0.8, X1 - 0.8, Y0 - 0.6, Y1 - 0.8, 0, PLINTH, texture=plinth_texture),
        rounded("body", "white", X0, X1, Y0, Y1, PLINTH, TOP, 2.5, 1.0, texture=body_texture),
        rounded("door_low", "white", X0 + 0.3, X1 - 0.3, DOOR_Y, Y0 + 0.5, PLINTH + 0.5, SPLIT - 0.5, 1.2, 0.4,
                texture=door_texture(PLINTH + 0.5, SPLIT - 0.5, True)),
        rounded("door_top", "white", X0 + 0.3, X1 - 0.3, DOOR_Y, Y0 + 0.5, SPLIT + 0.5, TOP - 2.0, 1.2, 0.4,
                texture=door_texture(SPLIT + 0.5, TOP - 2.0, False)),
    ]
    for k, (z0, z1) in enumerate(((SPLIT - 22, SPLIT - 4), (SPLIT + 4, SPLIT + 15))):
        s.append(box(f"handle{k}", GROUP, "grey", *HANDLE_X, DOOR_Y - 1.0, DOOR_Y, z0, z1, lit=True,
                     texture=handle_texture(z0, z1)))
    return s


SPEC = PieceSpec(
    name="fridge",
    mats={m.name: m for m in (WHITE, GREY, DETAIL)},
    model=model,
    shadow=[("bar", 16.0, 9.6, 16.0, 22.4, 10.56, 0, TOP)],
    max_colors=24,
    canvas=(128, 160),
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
