"""Cuadros de pared de Quincena Office (``painting``, ``painting_abstract``, ``painting_sea``; ``_x`` y
``_y``), hechos con Moana. Ver ../_wall_kit.py.

Marco de madera naranja de cuatro listones de 3 px y, 1 px más adentro, la tela con el dibujo: paisaje con
colinas, árbol, sol y nube; bloques de color con líneas negras; o mar con velero, sol y arena. Desde el
repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/wall_items/painting/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _wall_kit import BASE, FACE, WallSpec, main_wall  # noqa: E402
from _boxes import box, colors, faces, ramp  # noqa: E402

GROUP = "painting"
X0, X1 = 8.0, 24.0  # 32 px a lo largo
TOP = BASE + 24.0  # `height` 12 × 2
BORDER = 3.0  # px del marco
DEPTH = 1.5  # 3 px de fondo
INSET = 0.5  # la tela queda 1 px detrás del marco
A0 = X0 + BORDER / 2  # borde izquierdo de la tela, en unidades
ART_W, ART_H = (X1 - X0) * 2 - 2 * BORDER, TOP - BASE - 2 * BORDER

WOOD = ramp("wood", "#DF823DFF", "#C26B24FF", "#A65A1CFF", "#3C1300FF", "#EDA85DFF", "#743B0EFF")
LAND = colors("land", "#2B2526FF", light="#B9DEF0FF", top="#8FC9E4FF", upper="#F6D36BFF", left="#9ECC42FF",
              right="#648132FF", dark="#743B0EFF")
SEA = colors("sea", "#2B2526FF", light="#F4F1E8FF", top="#3D90C0FF", upper="#6DACCEFF", left="#E8CF98FF",
             right="#C03D43FF", dark="#4C6029FF")
BLOCKS = colors("blocks", "#2B2526FF", light="#EFE6D2FF", top="#C03D43FF", upper="#EEC04AFF", left="#3D6FB0FF",
                right="#2B2526FF", dark="#2B2526FF")
SKY, SKY_LIGHT, SUN, HILL, HILL_DARK, TRUNK = (f"land.{k}" for k in ("top", "light", "upper", "left", "right", "dark"))
WHITE, WATER, WATER_LIGHT, SAND, RED, PINE = (f"sea.{k}" for k in ("light", "top", "upper", "left", "right", "dark"))
CREAM, BLOCK_RED, BLOCK_YELLOW, BLOCK_BLUE, INK, CREAM_SHADE = (f"blocks.{k}" for k in
                                                               ("light", "top", "upper", "left", "right", "dark"))


def landscape(a: np.ndarray, b: np.ndarray, out: np.ndarray) -> np.ndarray:
    w, h = ART_W, ART_H
    out[:] = SKY
    out[b >= h * 0.72] = SKY_LIGHT
    out[(a - w * 0.74) ** 2 + (b - h * 0.74) ** 2 <= 8.5] = SUN
    cloud = ((a - 7.5) ** 2 / 9.0 + (b - 14.5) ** 2 <= 1.0) | ((a - 10.5) ** 2 / 6.0 + (b - 15.2) ** 2 / 1.5 <= 1.0)
    out[cloud] = WHITE
    out[b < h * 0.48 + 2.5 * np.sin(a / 4.0 + 1.0)] = HILL_DARK
    out[b < h * 0.30 + 2.0 * np.sin(a / 6.0 + 3.5)] = HILL
    path = (b < h * 0.30) & (np.abs(a - (w * 0.55 + b * 0.9)) < 1.0 + (5 - b) * 0.25)
    out[path] = SAND
    out[(a >= 5) & (a < 7) & (b >= 3) & (b < 8)] = TRUNK
    out[(a - 6) ** 2 / 9.0 + (b - 9.5) ** 2 / 7.0 <= 1.0] = PINE
    return out


def sea(a: np.ndarray, b: np.ndarray, out: np.ndarray) -> np.ndarray:
    w, h = ART_W, ART_H
    out[:] = SKY
    out[b >= h * 0.72] = SKY_LIGHT
    out[(a - w * 0.22) ** 2 + (b - h * 0.78) ** 2 <= 6.0] = SUN
    water = b < h * 0.45
    out[water] = WATER
    out[water & (np.mod(a + 3 * b, 9) < 2)] = WATER_LIGHT
    out[b < 3 + (a > w * 0.6)] = SAND
    hull = (b >= 5) & (b < 7) & (a >= 12 + (6 - b)) & (a < 22 - (6 - b))
    sail = (b >= 7) & (b < 15) & (a >= 17) & (a < 17 + (15 - b) * 0.7)
    jib = (b >= 7) & (b < 13) & (a < 16) & (a >= 16 - (13 - b) * 0.5)
    out[sail | jib] = WHITE
    out[hull] = RED
    out[(a == 16) & (b >= 7) & (b < 16)] = TRUNK
    return out


def abstract(a: np.ndarray, b: np.ndarray, out: np.ndarray) -> np.ndarray:
    out[:] = CREAM
    out[(a < 8) & (b >= 7)] = BLOCK_RED
    out[(a >= 19) & (b < 5)] = BLOCK_BLUE
    out[(a >= 21) & (b >= 11)] = BLOCK_YELLOW
    lines = (a == 8) | (a == 9) | (a == 19) | (b == 5) | (b == 6) | ((b == 10) & (a >= 9))
    out[lines] = INK
    return out


def canvas_texture(art):
    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        f = faces(mx, my, mz, A0, X1 - BORDER / 2, FACE, FACE + DEPTH - INSET, BASE + BORDER, TOP - BORDER)
        out = tone.copy()
        a, b = np.floor(f.a), np.floor(f.b)
        drawn = art(a, b, tone.copy())
        out[f.back] = drawn[f.back]
        out[~f.back] = "wood.dark"  # cantos de la tela, que asoman por el hueco del marco
        return out

    return texture


def frame_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Veta: una línea más oscura a lo largo de cada listón."""
    f = faces(mx, my, mz, X0, X1, FACE, FACE + DEPTH, BASE, TOP)
    out = tone.copy()
    across = f.back & ((np.floor(f.b) == 1) | (np.floor(f.b) == TOP - BASE - 2)) & (f.a >= 3) & (f.a < f.width - 3)
    along = f.back & ((np.floor(f.a) == 1) | (np.floor(f.a) == f.width - 2)) & (f.b >= 3) & (f.b < TOP - BASE - 3)
    out[across | along] = "wood.upper"
    return out


def model_for(art):
    def model() -> list:
        y1 = FACE + DEPTH
        bar = BORDER / 2
        kw = {"lit": True, "texture": frame_texture}
        return [
            box("canvas", GROUP, "land", X0 + 0.5, X1 - 0.5, FACE, y1 - INSET, BASE + 1, TOP - 1,
                texture=canvas_texture(art)),
            box("frame_top", GROUP, "wood", X0, X1, FACE, y1, TOP - BORDER, TOP, **kw),
            box("frame_bottom", GROUP, "wood", X0, X1, FACE, y1, BASE, BASE + BORDER, **kw),
            box("frame_left", GROUP, "wood", X0, X0 + bar, FACE, y1, BASE + BORDER, TOP - BORDER, **kw),
            box("frame_right", GROUP, "wood", X1 - bar, X1, FACE, y1, BASE + BORDER, TOP - BORDER, **kw),
        ]

    return model


MATS = {m.name: m for m in (WOOD, LAND, SEA, BLOCKS)}
SPECS = [WallSpec(name, MATS, model_for(art)) for name, art in
         (("painting", landscape), ("painting_abstract", abstract), ("painting_sea", sea))]

if __name__ == "__main__":
    raise SystemExit(main_wall(SPECS, HERE))
