"""Camino de grava (4 variantes), hecho con Moana. Ver ../_ground_kit.py.

Grava de grises cálidos en cuatro tonos con granos oscuros sueltos, y piedras de 2 a 8 px con cara clara
arriba, lado en sombra a la derecha y su sombra en el piso abajo. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/ground/path/build.py [--out DIR] [--preview DIR]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _ground_kit import Group, Material, Shape, Tile, blended, hash_cells, levels, main, scatter, specks, waves  # noqa: E402

# 0–3 grava de oscura a clara, 4 contorno y sombra, 5 lado de la piedra, 6 piedra, 7 cara iluminada.
PATH = ["988c76", "a59a84", "afa38c", "bcb19b", "6e6453", "a89d87", "c8bea8", "e0d8c4"]
C = {"t": 7, "s": 6, "m": 5, "o": 4}
LARGE = Shape(("..tttt..", "ttttssmm", "ssssssmm", "ssssmmmm", "..oooooo"), C)
ROUND = Shape(("..ttt...", ".ttsssm.", "tsssssmm", ".ssssmm.", "..ooooo."), C)
MID = Shape(("tttt..", "ttssmm", "ssmmmm", "oooooo"), C)
FLAT = Shape(("ttssss", "ssssmm", "..oooo"), C)
SMALL = Shape(("tsmm", "oooo"), C)
TINY = Shape(("ts", "oo"), C)
RING_STONES = [LARGE, MID, FLAT, SMALL, SMALL, TINY, TINY, TINY]
STONES = [LARGE, LARGE, ROUND, ROUND, MID, MID, MID, FLAT, FLAT, FLAT, SMALL, SMALL, SMALL, SMALL,
          TINY, TINY, TINY, TINY, TINY]
SEED = 7500
SHARES = (0.2, 0.3, 0.3, 0.2)


def draw_factory():
    ring_field = waves(SEED, 4, 12, 24)
    ring_grain = hash_cells(SEED + 1)
    ring_grit = hash_cells(SEED + 2)
    ring_stones = scatter(RING_STONES, SEED + 3, inner=False)

    def draw(variant: int) -> Tile:
        s = SEED + 100 * (variant + 1)
        # Grava: ondas cortas mezcladas con grano por celda, en cuatro tonos con las mismas partes.
        shared = ring_field * 0.55 + ring_grain * 0.45
        own = waves(s, 4, 12, 24) * 0.55 + hash_cells(s + 1) * 0.45
        cells = levels(blended(shared, own), shared, SHARES)
        # Granos oscuros sueltos (el contorno de las piedras, en un 3 % de las celdas).
        cells = specks(cells, ring_grit, hash_cells(s + 2), 0.03, 4, (0,))
        cells = specks(cells, ring_grit, hash_cells(s + 2), 0.03, 3, (1,))
        tile = Tile(cells)
        for shape, x, y in ring_stones:
            tile.put(shape, x, y, wrap=True)
        for shape, x, y in scatter(STONES, s + 3, inner=True, used=tile.used.copy()):
            tile.put(shape, x, y, wrap=False)
        return tile
    return draw


GROUP = Group([Material("ground_path", PATH, draw_factory())])

if __name__ == "__main__":
    raise SystemExit(main(GROUP, HERE))
