"""Pecera de Quincena Office (2×1, cuatro rotaciones), hecha con Moana. Ver ../_chair_kit.py.

Mueble de madera naranja con dos puertas al frente (−y en rotación 0) y encima el tanque: marco negro
arriba y abajo y en las aristas, una franja de aire bajo la tapa, agua más clara arriba que abajo, arena
con piedras, algas que se mecen, tres peces, burbujas y dos franjas de reflejo en el vidrio. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/aquarium/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _chair_kit import Mat, PieceSpec, main_piece, slab  # noqa: E402
from _chairs import PLASTIC  # noqa: E402

GROUP = "aquarium"
W, D = 64.0, 32.0  # planta en unidades (2×1 casillas)
STAND_TOP = 20.0
INSET = 1.0  # el mueble entra 1 unidad en la planta para que el contorno no toque el lienzo
TANK = (1.0, 63.0, 2.0, 30.0)  # x0, x1, y0, y1
TANK_TOP = 56.0  # más alto que el `height` del juego para que se lea como pecera
WATER_TOP = TANK_TOP - 4.0
RIM = 2.0  # marco negro arriba y abajo (px)

WOOD = Mat("wood", light="#EDA85DFF", top="#DF823DFF", upper="#C26B24FF", left="#C26B24FF", right="#894522FF",
           dark="#5B2A10FF", ink="#3C1300FF")
WATER = Mat("water", light="#C8ECF7FF", top="#9FD6EFFF", upper="#4F9FC9FF", left="#3D8BB8FF", right="#347CA7FF",
            dark="#245A7DFF", ink="#1B2F3DFF")
# Tonos sueltos del fondo y de los peces (cada nombre de tono es un color, no una cara).
AQUA = Mat("aqua", light="#E2C68CFF", top="#C4A46AFF", upper="#7CC24AFF", left="#4C9A3AFF", right="#8A8F96FF",
           dark="#2D6F99FF", ink="#1B2F3DFF")
FISH = Mat("fish", light="#F4D04AFF", top="#F08A2CFF", upper="#D8434AFF", left="#F1D39AFF", right="#1B1B1DFF",
           dark="#1B1B1DFF", ink="#1B1B1DFF")
SAND, SAND_DARK, WEED_LIGHT, WEED, STONE, DEEP = ("aqua.light", "aqua.top", "aqua.upper", "aqua.left", "aqua.right",
                                                  "aqua.dark")
# Peces: (lugar a lo largo de la cara, alto sobre el fondo del tanque, color, hacia dónde mira)
FISHES = ((0.3, 11.0, "fish.top", 1), (0.62, 19.0, "fish.light", -1), (0.82, 7.0, "fish.upper", 1))


def ends_with(tone: np.ndarray, suffix: str) -> np.ndarray:
    return np.char.endswith(tone.astype(str), suffix)


def stand_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Zócalo oscuro abajo y, al frente, dos puertas con ranura y tiradores."""
    out = tone.copy()
    side = mz < STAND_TOP - 0.5
    front = side & (my < INSET + 0.5)
    out[side & (mz < 2.0)] = "wood.dark"
    a = (mx - INSET) * 2.0  # px a lo largo del frente
    length = (W - 2 * INSET) * 2.0
    door = front & (mz >= 4.0) & (mz < STAND_TOP - 3.0) & (a >= 6) & (a < length - 6)
    groove = door & ((mz < 5.0) | (mz >= STAND_TOP - 4.0) | (a < 7) | (a >= length - 7) | (np.abs(a - length / 2) < 1.0))
    out[groove] = "wood.dark"
    knob = front & (np.abs(mz - 11.5) < 1.0) & ((np.abs(a - (length / 2 - 5)) < 1.0) | (np.abs(a - (length / 2 + 4)) < 1.0))
    out[knob] = "wood.light"
    return out


def tank_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    x0, x1, y0, y1 = TANK
    out = tone.copy()
    top = mz > TANK_TOP - 0.3
    # Tapa: marco negro y superficie del agua con ondas.
    frame = top & ((mx < x0 + 1.2) | (mx > x1 - 1.2) | (my < y0 + 1.2) | (my > y1 - 1.2))
    surface = top & ~frame
    out[surface] = "water.top"
    ripple = surface & (np.mod(np.floor(mx * 2) + 5 * np.floor(my), 17) < 3) & (np.mod(np.floor(my), 3) == 0)
    out[ripple] = "water.light"
    out[frame] = "plastic.top"
    # Caras: largo a lo largo (px) y alto sobre el fondo del tanque.
    side = ~top
    on_x = np.abs(my - y0) < 0.3
    on_x |= np.abs(my - y1) < 0.3
    a = np.where(on_x, (mx - x0) * 2.0, (my - y0) * 2.0)
    length = np.where(on_x, (x1 - x0) * 2.0, (y1 - y0) * 2.0)
    b = mz - STAND_TOP
    h = TANK_TOP - STAND_TOP
    right = ends_with(tone, ".right")
    water = side & (b >= RIM) & (mz < WATER_TOP)
    out[water] = np.where(right[water], "water.left", "water.upper")
    low = water & (b < h * 0.5)
    out[low] = np.where(right[low], "water.right", "water.left")
    out[water & (b < h * 0.22)] = DEEP
    # Aire bajo la tapa.
    out[side & (mz >= WATER_TOP) & (mz < TANK_TOP - RIM)] = "water.top"
    out[side & (np.abs(mz - WATER_TOP) < 0.5)] = "water.light"
    # Arena con lomas y piedras.
    sand_top = RIM + 3.0 + np.round(1.2 * np.sin(a / 7.0))
    sand = water & (b < sand_top)
    out[sand] = np.where(np.mod(np.floor(a) + np.floor(b), 5) == 0, SAND_DARK, SAND)[sand]
    stone = water & (((a - length * 0.7) ** 2 / 9.0 + (b - RIM - 3.0) ** 2 / 4.0) <= 1.0)
    out[stone] = STONE
    # Algas: tallos ondulados de 2 px.
    for fx, top_f in ((0.12, 0.72), (0.2, 0.52), (0.88, 0.62)):
        sway = np.round(1.5 * np.sin(b / 3.0 + fx * 10))
        stem = water & (np.abs(a - length * fx - sway) < 1.0) & (b >= RIM + 1) & (b < h * top_f)
        out[stem] = np.where(np.mod(np.floor(b), 4) < 2, WEED_LIGHT, WEED)[stem]
    # Peces de 5×3 con cola y ojo.
    for fx, fb, color, facing in FISHES:
        cx = np.floor(length * fx)
        da, db = np.floor(a) - cx, np.floor(b) - fb
        body = (np.abs(da) <= 2) & (np.abs(db) <= 1) & ~((np.abs(da) == 2) & (np.abs(db) == 1))
        tail = (da == -3 * facing) & (np.abs(db) <= 1)
        out[water & (body | tail)] = color
        out[water & (da == facing) & (db == 0)] = "fish.right"
    # Burbujas y reflejo en diagonal.
    bubbles = water & (np.abs(a - length * 0.5) < 1.0) & (np.mod(np.floor(b), 5) == 0) & (b > h * 0.35)
    out[bubbles] = "water.light"
    slant = np.floor(a) - np.floor(b * 0.6) - length * 0.55  # dos franjas cortas de reflejo en el vidrio
    glare = water & (b > RIM + 6) & (b < h - 8) & (((slant >= 0) & (slant < 2)) | ((slant >= 5) & (slant < 6)))
    out[glare] = "water.light"
    # Marco negro: arriba, abajo y en las aristas.
    edge = side & ((b < RIM) | (mz >= TANK_TOP - RIM) | (a < 1.0) | (a > length - 1.0))
    out[edge] = np.where(right[edge], "plastic.right", "plastic.left")
    return out


def model() -> list:
    x0, x1, y0, y1 = TANK
    return [
        slab("stand", GROUP, "wood", W / 2, D / 2, W / 2 - INSET, D / 2 - INSET, 0.01, 0.0, STAND_TOP, texture=stand_texture),
        slab("tank", GROUP, "water", (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, 0.01, STAND_TOP,
             TANK_TOP, texture=tank_texture),
    ]


SPEC = PieceSpec(
    name="aquarium",
    mats={m.name: m for m in (WOOD, WATER, AQUA, FISH, PLASTIC)},
    model=model,
    shadow=[("bar", 8.0, 16.0, 56.0, 16.0, 13.4, 0, TANK_TOP)],
    max_colors=30,
    size=(2, 1),
    canvas=(192, 160),
    rotations=(0, 1, 2, 3),
    painter=True,
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
