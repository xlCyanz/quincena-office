"""Alfombra lila de pared a pared (4 variantes), hecha con Moana. Ver ../_ground_kit.py.

Pelo corto: cuatro lilas cercanos en manchas suaves con el borde tramado, una trama fina de bucles y fibras
sueltas más oscuras y más claras. Sin juntas ni brillo. El anillo del borde es igual en las 4. Desde el
repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/ground/carpet/build.py [--out DIR] [--preview DIR]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _ground_kit import Group, Material, Tile, blended, dither, hash_cells, levels, main, specks, waves  # noqa: E402

# 0 fibra oscura, 1–4 lila de oscuro a claro, 5 fibra clara.
CARPET = ["6f7292", "777a9a", "7d80a0", "8688a4", "8e8fa8", "9798b0"]
SEED = 5100
SHARES = (0.22, 0.28, 0.32, 0.18)


def draw_factory():
    ring_field = waves(SEED, 3, 8, 18)
    ring_grain = hash_cells(SEED + 1)
    ring_dark = hash_cells(SEED + 2)
    ring_light = hash_cells(SEED + 3)

    def draw(variant: int) -> Tile:
        s = SEED + 100 * (variant + 1)
        shared = ring_field * 0.6 + ring_grain * 0.4
        own = waves(s, 3, 8, 18) * 0.6 + hash_cells(s + 1) * 0.4
        cells = levels(blended(shared, own), shared, SHARES) + 1
        cells = dither(cells, ((1, 2), (2, 3), (3, 4)))
        cells = specks(cells, ring_dark, hash_cells(s + 2), 0.025, -1, (1,))
        cells = specks(cells, ring_light, hash_cells(s + 3), 0.02, 1, (4,))
        return Tile(cells)
    return draw


GROUP = Group([Material("floor_carpet", CARPET, draw_factory())])

if __name__ == "__main__":
    raise SystemExit(main(GROUP, HERE))
