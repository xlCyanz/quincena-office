"""Concreto sin piso (4 variantes), hecho con Moana. Ver ../_ground_kit.py.

Grises cálidos de poco contraste con manchas de llana suaves, árido suelto, poros con su labio claro y una
grieta fina en escalera 2:1 en cada variante. El anillo del borde es igual en las 4. Desde el repositorio
de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/ground/bare/build.py [--out DIR] [--preview DIR]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _ground_kit import (Group, Material, Shape, Tile, blended, dither, hash_cells, levels, main, scatter,  # noqa: E402
                         specks, waves)

# 0–3 concreto de oscuro a claro, 4 poro y grieta, 5 labio claro, 6 árido oscuro.
BARE = ["83817d", "878581", "8b8985", "8f8d89", "6f6d69", "9a9894", "7a7874"]
C = {"p": 4, "l": 5, "d": 6}
PORE = Shape(("pp", "ll"), C)
PIT = Shape(("pppp", "..ll"), C)
CRACK = Shape(("pp..........",
               "..pp........",
               "....pppp....",
               "........pp..",
               "..........pp"), C)
CRACK_B = Shape(("..........pp",
                 "......pppp..",
                 "....pp......",
                 "pppp........"), C)
SEED = 7000
SHARES = (0.2, 0.3, 0.32, 0.18)
RING_PORES = [PORE, PORE, PIT]


def draw_factory():
    ring_field = waves(SEED, 2, 5, 14)
    ring_grain = hash_cells(SEED + 1)
    ring_dark = hash_cells(SEED + 2)
    ring_pores = scatter(RING_PORES, SEED + 3, inner=False)

    def draw(variant: int) -> Tile:
        s = SEED + 100 * (variant + 1)
        shared = ring_field * 0.6 + ring_grain * 0.4
        own = waves(s, 2, 5, 14) * 0.6 + hash_cells(s + 1) * 0.4
        cells = levels(blended(shared, own), shared, SHARES)
        cells = dither(cells, ((0, 1), (1, 2), (2, 3)))
        cells = specks(cells, ring_dark, hash_cells(s + 2), 0.025, 6, (0,))
        tile = Tile(cells)
        for shape, x, y in ring_pores:
            tile.put(shape, x, y, wrap=True)
        crack = CRACK if variant % 2 == 0 else CRACK_B
        for shape, x, y in scatter([crack, PIT, PORE, PORE, PORE], s + 3, inner=True, used=tile.used.copy(), gap=3):
            tile.put(shape, x, y, wrap=False)
        return tile
    return draw


GROUP = Group([Material("floor_bare", BARE, draw_factory())])

if __name__ == "__main__":
    raise SystemExit(main(GROUP, HERE))
