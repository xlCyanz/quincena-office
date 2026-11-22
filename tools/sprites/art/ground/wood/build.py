"""Piso de madera (4 variantes), hecho con Moana. Ver ../_ground_kit.py.

8 tablas angostas por casilla a lo largo de un eje, con dos cortes por fila escalonados. Cada tabla tiene su
tono, el canto de arriba con luz, la punta en sombra, vetas largas en dos tonos, moteado suelto y, a veces,
un nudo. La tabla que cruza el borde de la casilla es igual en las 4 variantes; las de adentro cambian de
fila y de sentido, así todas tienen los mismos pixeles por color. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/ground/wood/build.py [--out DIR] [--preview DIR]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import numpy as np  # noqa: E402

from _ground_kit import A, B, N, Group, Material, Tile, hash_cells, main  # noqa: E402

# 0 junta, 1 veta honda, 2 veta, 3 tabla oscura, 4 tabla media, 5 tabla, 6 tabla clara, 7 moteado claro,
# 8 canto con luz, 9 nudo.
WOOD = ["783a13", "86441b", "904f25", "9d6035", "a5663a", "ad6d40", "b67647", "c0814f", "c98b58", "6e320f"]
JOINT, DEEP, GRAIN, DARK, MID, BASE, LIGHT, SHINE, EDGE_LIT, KNOT = range(10)
UP = {DARK: MID, MID: BASE, BASE: LIGHT, LIGHT: SHINE}
DOWN = {DARK: GRAIN, MID: DARK, BASE: MID, LIGHT: BASE}
PLANK = 8  # celdas de ancho (8 tablas por casilla)
HALF = 32  # distancia entre los dos cortes de una fila
CUTS = (3, 19, 11, 27, 7, 23, 15, 31)  # primer corte de cada fila
MOTTLE = 0.14
SEED = 9300
# Tablas: (tono, semilla, vetas [(a, b, largo)], nudo (a, b) o None); a a lo largo (0 … 30), b a lo ancho
# (1 … 6, la 0 es el canto con luz). Las 8 primeras van adentro; las 8 siguientes cruzan el borde.
KITS = (
    (BASE, 11, [(3, 3, 14), (20, 5, 8)], None), (MID, 12, [(8, 2, 10)], (22, 4)),
    (LIGHT, 13, [(2, 4, 9), (14, 2, 12)], None), (BASE, 14, [(12, 5, 13)], None),
    (DARK, 15, [(4, 3, 18)], None), (LIGHT, 16, [(9, 5, 7), (19, 2, 9)], None),
    (MID, 17, [(1, 4, 11), (16, 3, 12)], None), (BASE, 18, [(6, 2, 9)], (21, 4)),
    (MID, 21, [(5, 3, 15)], None), (BASE, 22, [(2, 5, 10), (15, 2, 12)], None),
    (LIGHT, 23, [(10, 4, 14)], None), (MID, 24, [(3, 2, 8), (17, 5, 10)], None),
    (BASE, 25, [(7, 3, 16)], None), (LIGHT, 26, [(12, 5, 9)], (5, 3)),
    (BASE, 27, [(1, 4, 12), (18, 2, 9)], None), (MID, 28, [(9, 3, 13)], None),
)
# Por variante: (tabla de adentro, al revés) de cada fila.
LAYOUTS = (
    ((0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0), (7, 0)),
    ((5, 1), (6, 0), (0, 1), (4, 0), (2, 1), (7, 1), (1, 0), (3, 1)),
    ((3, 1), (4, 1), (6, 0), (1, 1), (7, 0), (0, 0), (2, 1), (5, 0)),
    ((6, 1), (2, 1), (7, 0), (0, 1), (1, 0), (3, 0), (5, 1), (4, 1)),
)


def plank(cells: np.ndarray, area: np.ndarray, a: np.ndarray, b: np.ndarray, kit: int, length: int) -> None:
    """Pinta una tabla de ``length`` celdas: tono, moteado, vetas, nudo, canto con luz y punta en sombra."""
    tone, seed, grains, knot = KITS[kit]
    cells[area] = tone
    chance = hash_cells(SEED + seed)
    cells[area & (chance < MOTTLE / 2)] = UP[tone]
    cells[area & (chance >= MOTTLE / 2) & (chance < MOTTLE)] = DOWN[tone]
    for a0, b0, size in grains:
        # Veta: un trazo largo que baja una celda a la mitad, con la punta más clara.
        bend = a0 + size // 2
        line = ((a >= a0) & (a < bend) & (b == b0)) | ((a >= bend) & (a < a0 + size) & (b == b0 + 1))
        cells[area & line] = GRAIN
        cells[area & line & (a >= a0 + 2) & (a < a0 + size - 3) & ((a - a0) % 5 == 1)] = DEEP
    if knot:
        ka, kb = knot
        cells[area & (np.abs(a - ka) <= 1) & (b == kb)] = GRAIN
        cells[area & (a == ka) & (b == kb)] = KNOT
        cells[area & (np.abs(a - ka) <= 2) & (np.abs(b - kb) == 1) & (np.abs(a - ka) >= 1)] = GRAIN
    cells[area & (b == 0)] = EDGE_LIT
    cells[area & (a == length - 1) & (b > 0)] = DOWN[tone]


def draw(variant: int) -> Tile:
    cells = np.full((N, N), BASE)
    row = B // PLANK
    across = B % PLANK
    body = across >= 1
    b = across - 1
    for number in range(8):
        in_row = (row == number) & body
        along = (A - CUTS[number]) % N  # 0 = el corte; 1 … 31 la tabla de adentro
        inner = in_row & (along >= 1) & (along < HALF)
        cross = in_row & (along > HALF)
        plank(cells, cross, along - HALF - 1, b, 8 + number, N - HALF - 1)
        kit, reverse = LAYOUTS[variant][number]
        a = along - 1
        if reverse:
            a = HALF - 2 - a
        plank(cells, inner, a, b, kit, HALF - 1)
        cells[in_row & ((along == 0) | (along == HALF))] = JOINT
    cells[across == 0] = JOINT
    return Tile(cells)


GROUP = Group([Material("floor_wood", WOOD, draw, ring=False)])

if __name__ == "__main__":
    raise SystemExit(main(GROUP, HERE))
