"""Calle (4 variantes) y calle con la línea amarilla a lo largo de x o de y, hecha con Moana.
Ver ../_ground_kit.py.

Asfalto de grano fino en cuatro grises con árido claro y puntos de brea; la línea es una franja de 4 celdas
por el centro, con partes gastadas que dejan ver el asfalto. Las casillas con línea son la calle de la misma
variante más la franja, así empalman con la calle sin línea. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/ground/road/build.py [--out DIR] [--preview DIR]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _ground_kit import A, B, N, Group, Material, Tile, blended, hash_cells, levels, main, specks, waves  # noqa: E402

# 0–3 asfalto de oscuro a claro, 4 línea, 5 línea gastada, 6 brea, 7 árido claro.
ROAD = ["3f4248", "44474d", "494c52", "55585e", "e0cf78", "c4b56a", "36383d", "62656b"]
SEED = 9000
SHARES = (0.28, 0.34, 0.30, 0.08)
LINE_WIDTH = 4


def road_cells(variant: int):
    s = SEED + 100 * (variant + 1)
    shared = waves(SEED, 3, 10, 20) * 0.35 + hash_cells(SEED + 1) * 0.65
    own = waves(s, 3, 10, 20) * 0.35 + hash_cells(s + 1) * 0.65
    cells = levels(blended(shared, own), shared, SHARES)
    cells = specks(cells, hash_cells(SEED + 2), hash_cells(s + 2), 0.025, 6, (0,))
    cells = specks(cells, hash_cells(SEED + 3), hash_cells(s + 3), 0.02, 4, (3,))
    return cells


def road(variant: int) -> Tile:
    return Tile(road_cells(variant))


def line(axis: str):
    def draw(variant: int) -> Tile:
        cells = road_cells(variant)
        across, along = (B, A) if axis == "x" else (A, B)
        band = (across >= N // 2 - LINE_WIDTH // 2) & (across < N // 2 + LINE_WIDTH // 2)
        worn = hash_cells(SEED + 50)  # igual en todas las variantes: la línea cruza el borde
        cells[band] = 4
        cells[band & (worn < 0.12)] = 5
        cells[band & (worn > 0.97)] = 2  # se ve el asfalto
        return Tile(cells)
    return draw


GROUP = Group([Material("ground_road", ROAD, road), Material("ground_road_line_x", ROAD, line("x")),
               Material("ground_road_line_y", ROAD, line("y"))])

if __name__ == "__main__":
    raise SystemExit(main(GROUP, HERE))
