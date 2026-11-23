"""Aire acondicionado split de Quincena Office (``air_conditioner_x`` y ``_y``), hecho con Moana. Ver
../_wall_kit.py.

Largo y bajo, de 10 px de fondo: frente blanco verdoso con el canto de arriba redondeado, tapa gris con
rejilla de entrada y un panel claro al final, logo, pantallita con la temperatura y luces roja y verde;
abajo, la rejilla de salida negra 3 px más adentro, y tapas de los extremos con un rectángulo
hundido. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/wall_items/air_conditioner/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _wall_kit import BASE, FACE, WallSpec, current_axis, main_wall  # noqa: E402
from _boxes import box, colors, faces, ramp  # noqa: E402
from _chair_kit import slab  # noqa: E402

GROUP = "air"
SPANS = {"y": (8.0, 30.0), "x": (2.0, 24.0)}  # 44 px a lo largo, corrido contra el lado al que lo empuja el fondo
DEPTH = 5.0  # 10 px de fondo
GRILLE_H = 6.0
Z_BODY, TOP = BASE + GRILLE_H, BASE + 24.0  # `height` 12 × 2

BODY = ramp("body", "#C9CFD2FF", "#EEF4F2FF", "#DCE6E3FF", "#2A2A30FF", "#FFFFFFFF", "#9BA3A8FF")
GRILLE = colors("grille", "#1E1E24FF", light="#4A4A52FF", top="#2A2A30FF", upper="#4A4A52FF", left="#1E1E24FF",
                right="#1E1E24FF", dark="#111114FF")
TRIM = colors("trim", "#2A2A30FF", light="#C03D43FF", top="#9AA4ACFF", upper="#6FE08AFF", left="#2A2E36FF",
              right="#AAB4B6FF", dark="#7DBDE3FF")


def body_texture_for(X0: float, X1: float):
    """Textura del cuerpo para el tramo X0–X1 de la pared que se dibuja."""
    def body_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        f = faces(mx, my, mz, X0, X1, FACE, FACE + DEPTH, Z_BODY, TOP)
        a, b = np.floor(f.a), np.floor(f.b)
        h = TOP - Z_BODY
        w = (X1 - X0) * 2
        out = tone.copy()
        front = f.back & (b < h - 3)  # el canto redondeado de arriba queda con su tono
        out[front & (b == 0)] = "body.dark"  # junta con la rejilla
        out[front & (b >= h - 7) & (b < h - 5) & (a >= 4) & (a < 10) & (np.mod(a, 3) != 2)] = "trim.top"  # logo
        display = front & (b >= 3) & (b < 6) & (a >= w - 15) & (a < w - 9)
        out[display] = "trim.left"
        out[display & (b == 4) & (a >= w - 14) & (a < w - 10) & (np.mod(a, 2) == 0)] = "trim.dark"  # 24°
        out[front & (b == 4) & (a == w - 7)] = "trim.upper"
        out[front & (b == 4) & (a == w - 5)] = "trim.light"
        top = f.top
        across = np.floor((my - FACE) * 2)
        along = np.floor((mx - X0) * 2)
        out[top & (across >= 1) & (across < 7) & (along >= 3) & (along < w - 14) & (np.mod(along, 2) == 0)] = "body.dark"
        panel = top & (across >= 1) & (across < 7) & (along >= w - 12) & (along < w - 3)
        out[panel] = "body.light"
        out[panel & ((along == w - 12) | (across == 6))] = "body.dark"
        ends = f.left | f.right
        ring = ends & (np.floor(f.a) >= 2) & (np.floor(f.a) < 8) & (b >= 2) & (b < h - 4)
        inner = ends & (np.floor(f.a) >= 3) & (np.floor(f.a) < 7) & (b >= 3) & (b < h - 5)
        out[ring & ~inner] = "trim.right"
        return out

    return body_texture


def grille_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    out = tone.copy()
    out[np.mod(np.floor(mz - BASE), 2) == 1] = "grille.light"  # tablillas
    return out


def model() -> list:
    X0, X1 = SPANS[current_axis()]
    cx, cy = (X0 + X1) / 2, FACE + DEPTH / 2
    return [
        box("grille", GROUP, "grille", X0 + 1.5, X1 - 2.5, FACE, FACE + 3.5, BASE, Z_BODY + 0.5,
            texture=grille_texture),
        slab("body", GROUP, "body", cx, cy, (X1 - X0) / 2, DEPTH / 2, 0.8, Z_BODY, TOP, bevel=0.9, bevel_z=3.0,
             lit=True, texture=body_texture_for(X0, X1)),
    ]


SPECS = [WallSpec("air_conditioner", {m.name: m for m in (BODY, GRILLE, TRIM)}, model, max_colors=24)]

if __name__ == "__main__":
    raise SystemExit(main_wall(SPECS, HERE))
