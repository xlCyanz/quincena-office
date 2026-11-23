"""Dispensador de agua de la Recepción de Quincena Office (mueble chico, ya a su tamaño: el 60 % de una
casilla; cuatro rotaciones), hecho con Moana. Ver ../_boxes.py.

Gabinete blanco de esquinas redondeadas: luces de frío y calor arriba, hueco oscuro para el vaso con las
llaves roja y azul y la bandeja de goteo de rejilla, rejilla de ventilación abajo y, a un costado, el tubo
de vasos de papel. Encima, el aro donde se apoya el bidón celeste casi transparente: hombro y cuello abajo,
agua más azul en el fondo con burbujas, tres aros, etiqueta con una gota, aire arriba, brillo del lado de la
luz y filo claro del otro lado. El frente mira a −y en rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/water_dispenser_q/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, colors, faces, ramp, rect  # noqa: E402
from _chair_kit import PieceSpec, cylinder, main_piece, slab  # noqa: E402

GROUP = "water"
C = 16.0
CAB = (12.4, 19.6, 12.4, 19.6, 0.0, 20.0)
COLLAR = 20.8
SHOULDER, TOP = 23.5, 40.0
R = 3.84
CUPS = (11.5, 16.6)

WHITE = ramp("white", "#F4F6F6FF", "#DDE2E2FF", "#C4CBCCFF", "#3D3B44FF", "#FFFFFFFF", "#A9B1B4FF")
METAL = ramp("metal", "#A9B1B4FF", "#8C96A0FF", "#6F787FFF", "#2F3437FF", "#D3D8D9FF", "#4F575CFF")
BOTTLE = ramp("bottle", "#BFE6F5FF", "#A3D8EFFF", "#8CC8E6FF", "#1B3A52FF", "#FFFFFFFF", "#4F9BD0FF")
PARTS = colors("parts", "#0E0F10FF", top="#3A3D44FF", upper="#2A2C31FF", left="#3D90C0FF", right="#2F6FA8FF",
               dark="#7DBDE3FF", light="#DDF3FBFF")
LABEL = colors("label", "#1B3A52FF", light="#EEF6F9FF", top="#4F9BD0FF", upper="#E2453CFF", left="#6FE08AFF",
               right="#F4F6F6FF", dark="#C4CBCCFF")
TAP_RED = colors("tap_red", "#5A1919FF", **{k: "#D8434AFF" for k in ("light", "top", "upper", "left", "right", "dark")})
TAP_BLUE = colors("tap_blue", "#1B3A52FF", **{k: "#3D90C0FF" for k in ("light", "top", "upper", "left", "right", "dark")})

# Dirección de «izquierda en pantalla» en el modelo para cada rotación (el brillo va del lado de la luz).
SCREEN_X = {0: (1, -1), 1: (-1, -1), 2: (-1, 1), 3: (1, 1)}
_view = {"r": 0}


def cabinet_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Luces de calor y frío, hueco del vaso, rejilla abajo y ranuras atrás en los costados."""
    f = faces(mx, my, mz, *CAB)
    out = tone.copy()
    out[f.front & rect(f, 3, 5, 16.5, 18)] = "label.upper"  # calor
    out[f.front & rect(f, 6, 8, 16.5, 18)] = "parts.left"  # frío
    out[f.front & rect(f, -5, -2, 16.5, 17.5)] = "white.dark"  # marca
    alcove = f.front & rect(f, 2, -2, 7, 15)
    out[alcove] = "parts.upper"
    out[alcove & (f.b >= 14)] = "parts.top"  # techo del hueco
    out[f.front & rect(f, 2, -2, 15, 15.6)] = "white.dark"
    out[f.front & rect(f, 3, -3, 2, 5) & (np.mod(f.b, 2) < 1)] = "white.dark"
    out[(f.left | f.right | f.back) & rect(f, 2, 6, 11, 18) & (np.mod(f.a, 2) < 1)] = "white.dark"
    out[f.sides & (f.b < 1)] = "white.dark"
    out[f.top & rect(f, 1, -1, 1, -1)] = "white.upper"  # tapa: un tono más bajo que el filo
    return out


def tray_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    out = tone.copy()
    out[(mz > 7.2) & (np.mod(np.floor(mx * 2), 2) < 1)] = "metal.dark"
    return out


def cups_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Tubo de vasos: los bordes de los vasos asoman cada 2 px."""
    out = tone.copy()
    out[(mz < 15.7) & (np.mod(mz, 2.0) < 1.0)] = "label.right"
    out[mz < 6.0] = "label.light"
    return out


def bottle_texture(rotation: int):
    """Textura del bidón para la rotación que se dibuja."""

    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        out = tone.copy()
        sx, sy = SCREEN_X[rotation]
        t = ((mx - C) * sx + (my - C) * sy) / (R * 1.414)  # -1 a la izquierda en pantalla, 1 a la derecha
        side = mz < TOP - 0.3
        b = mz - SHOULDER
        h = TOP - SHOULDER
        out[side & (b < h * 0.35)] = "parts.dark"
        out[side & (np.abs(t) < 0.25) & (b < h * 0.35)] = "parts.left"  # el fondo, más hondo en el medio
        out[side & (b >= h - 2.0)] = "bottle.top"  # aire
        out[side & (b >= h - 2.5) & (b < h - 2.0)] = "parts.light"  # nivel del agua
        for f in (0.22, 0.5, 0.78):
            r0 = np.floor(h * f)
            out[side & (b >= r0) & (b < r0 + 1)] = "parts.right"
            out[side & (b >= r0 + 1) & (b < r0 + 2)] = "bottle.right"
        label = side & (b >= np.floor(h * 0.5) + 2) & (b < np.floor(h * 0.78)) & (t > -0.5)
        out[label] = "label.light"
        mid = (np.floor(h * 0.5) + 2 + np.floor(h * 0.78)) / 2
        out[label & (np.hypot(t * 4.0, (b - mid) * 0.8) < 1.0)] = "label.top"  # gota
        shine = side & (t > -0.68) & (t < -0.58) & (b > -2) & (b < h - 1) & (np.mod(np.floor(b), 7) != 3)
        out[shine] = "bottle.light"
        out[side & ~label & (t > -0.82) & (t < -0.7) & (b > 1) & (b < h - 3)] = "parts.light"
        out[side & ~label & (t > 0.86) & (b > 0) & (b < h - 1)] = "parts.light"  # filo del otro lado
        bubbles = side & (np.mod(np.floor(mx * 3) * 7 + np.floor(b) * 5, 23) == 0) & (t > -0.2) & (b < h * 0.35)
        out[bubbles] = "bottle.light"
        cap = mz > TOP - 0.3
        r = np.hypot(mx - C, my - C)
        out[cap & (r < 0.9)] = "parts.right"
        out[cap & (r >= 1.5) & (r < 2.2)] = "parts.left"
        out[cap & (r >= 2.8) & (r < 3.3) & (t < -0.2)] = "bottle.light"
        return out

    return texture


def model() -> list:
    """``main_piece`` pide el modelo una vez por rotación, en orden; así el brillo sabe cuál dibuja."""
    x0, x1, y0, y1, z0, z1 = CAB
    r = _view["r"]
    solids = [
        slab("cabinet", GROUP, "white", C, C, (x1 - x0) / 2, (y1 - y0) / 2, 0.8, z0, z1, bevel=0.3, bevel_z=1.0,
             lit=True, texture=cabinet_texture),
        box("tray", GROUP, "metal", 13.6, 18.4, 11.0, 12.6, 6.0, 7.5, lit=True, texture=tray_texture),
        box("tap_red", GROUP, "tap_red", 17.4, 18.4, 11.7, 12.4, 12.0, 14.5),
        box("tap_blue", GROUP, "tap_blue", 14.8, 15.8, 11.7, 12.4, 12.0, 14.5),
        cylinder("cups", GROUP, "metal", *CUPS, 0.9, 5.0, 16.0, sides=8, texture=cups_texture),
        cylinder("collar", GROUP, "metal", C, C, 2.8, z1, COLLAR, sides=14, lit=True),
        cylinder("neck", GROUP, "bottle", C, C, 1.6, COLLAR, COLLAR + 1.0, sides=10),
        cylinder("shoulder", GROUP, "bottle", C, C, 2.0, COLLAR + 1.0, SHOULDER, sides=16, r_top=R),
        cylinder("bottle", GROUP, "bottle", C, C, R, SHOULDER, TOP, sides=16, lit=True, texture=bottle_texture(r)),
    ]
    _view["r"] = (_view["r"] + 1) % 4
    return solids


SPEC = PieceSpec(
    name="water_dispenser_q",
    mats={m.name: m for m in (WHITE, METAL, BOTTLE, PARTS, LABEL, TAP_RED, TAP_BLUE)},
    model=model,
    shadow=[("disc", C, C, 4.0, 0, TOP)],
    max_colors=36,
    canvas=(128, 160),
    rotations=(0, 1, 2, 3),
    painter=True,
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
