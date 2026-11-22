"""Acera (4 variantes), hecha con Moana. Ver ../_ground_kit.py.

Una losa por casilla: junta oscura en el borde (2 px entre dos losas), bisel claro arriba a la izquierda y
en sombra abajo a la derecha, cemento gris claro moteado con árido suelto (granos claros y oscuros).
Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/ground/sidewalk/build.py [--out DIR] [--preview DIR]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _ground_kit import A, B, N, Group, Material, Tile, blended, hash_cells, levels, main, specks, waves  # noqa: E402

# 0–3 cemento de oscuro a claro, 4 junta, 5 bisel en sombra, 6 bisel claro, 7 árido oscuro.
SIDEWALK = ["9e9d97", "a3a29c", "a8a7a1", "adaca6", "7d7c77", "93928c", "bfbeb8", "8a8983"]
SEED = 8000
SHARES = (0.2, 0.3, 0.32, 0.18)


def draw_factory():
    ring_field = waves(SEED, 2, 6, 16)
    ring_dark = hash_cells(SEED + 1)
    ring_light = hash_cells(SEED + 2)

    def draw(variant: int) -> Tile:
        s = SEED + 100 * (variant + 1)
        shared = ring_field * 0.7 + hash_cells(SEED + 3) * 0.3
        own = waves(s, 2, 6, 16) * 0.7 + hash_cells(s + 3) * 0.3
        cells = levels(blended(shared, own), shared, SHARES)
        # Árido: granos oscuros sobre el cemento y algún punto claro.
        cells = specks(cells, ring_dark, hash_cells(s + 1), 0.03, 7, (0,))
        cells = specks(cells, ring_dark, hash_cells(s + 1), 0.03, 6, (1,))
        cells = specks(cells, ring_light, hash_cells(s + 2), 0.02, 3, (3,))
        # Losa: bisel claro en los bordes de arriba (a = 1 o b = 1), en sombra en los de abajo, y la junta.
        cells[(A == 1) | (B == 1)] = 6
        cells[(A == N - 2) | (B == N - 2)] = 5
        cells[(A == 0) | (B == 0) | (A == N - 1) | (B == N - 1)] = 4
        return Tile(cells)
    return draw


GROUP = Group([Material("ground_sidewalk", SIDEWALK, draw_factory())])

if __name__ == "__main__":
    raise SystemExit(main(GROUP, HERE))
