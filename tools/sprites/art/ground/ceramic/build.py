"""Cerámica blanca, hecha con Moana. Ver ../_ground_kit.py.

Losas de 50 cm, 4 por casilla, para que no se vean grandes junto a los muebles. Juntas y biseles de 2 celdas (con zoom
1 quedan de 1 px entero), esquinas redondeadas, bisel claro arriba y en sombra abajo, nubes muy suaves y un reflejo en
diagonal en cada losa, corrido según la variante. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/ground/ceramic/build.py [--out DIR] [--preview DIR]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import numpy as np  # noqa: E402

from _ground_kit import A, B, IN_RING, Group, Material, Tile, main, waves  # noqa: E402

# 0 junta, 1 bisel en sombra (abajo a la derecha), 2 bisel suave (abajo a la izquierda), 3 losa del otro
# tono, 4 losa, 5 reflejo, 6 bisel claro, 7 nube de la losa, 8 nube del otro tono, 9 cruce de juntas.
CERAMIC = ["a3a1a0", "bbb9b9", "d2d1d1", "e1e1e1", "e8e8e8", "f6f6f6", "ffffff", "ededed", "dcdcdc", "8f8d8c"]
SLAB = 32  # celdas por losa: media casilla (losas de 50 cm, 4 por casilla)
# Ancho de juntas y biseles, en celdas: 2 para que con zoom 1 (la mitad de píxeles) no se corten.
LINE = 2
SEED = 9100
# Reflejo: franjas "/" con k = 2·du − dv: (k0, k1, du mínimo, du máximo), en celdas de la losa.
GLINTS = {
    "wide": ((14, 17, 7, 23), (23, 25, 10, 25)),
    "thin": ((8, 9, 5, 17),),
    "low": ((30, 31, 17, 28),),
    "none": (),
}
# Reflejos de las losas de una casilla.
LAYOUTS = ("wide", "none", "thin", "low")


def draw(variant: int) -> Tile:
    du, dv = A % SLAB, B % SLAB
    cells = np.full(A.shape, 4)
    # Nubes del esmalte: cambian con la pieza, lejos del borde.
    cloud = (waves(SEED + 10 * variant, 3, 7, 16) > 0.7) & ~IN_RING
    cells[cloud] = 7
    field = (du >= 3 * LINE) & (dv >= 3 * LINE) & (du <= SLAB - 2 * LINE - 1) & (dv <= SLAB - 2 * LINE - 1)
    k = 2 * du - dv
    # Cada losa de la casilla con su reflejo, corrido según la pieza.
    slab = (A // SLAB + 2 * (B // SLAB) + variant) % len(LAYOUTS)
    for index, layout in enumerate(LAYOUTS):
        for k0, k1, low, high in GLINTS[layout]:
            cells[(slab == index) & field & (k >= k0) & (k <= k1) & (du >= low) & (du <= high)] = 5
    # Biseles: claro arriba, suave abajo a la izquierda y en sombra abajo a la derecha.
    band_u = (du >= LINE) & (du < 2 * LINE)
    band_v = (dv >= LINE) & (dv < 2 * LINE)
    cells[(band_v & (du >= LINE)) | (band_u & (dv >= LINE))] = 6
    cells[(dv >= SLAB - LINE) & (du >= LINE)] = 2
    cells[(du >= SLAB - LINE) & (dv >= LINE)] = 1
    cells[(du < LINE) | (dv < LINE)] = 0
    # Esquinas redondeadas y el cruce de juntas un poco más hondo.
    cells[(band_u | (du >= SLAB - LINE)) & (band_v | (dv >= SLAB - LINE))] = 0
    cells[(du < LINE) & (dv < LINE)] = 9
    return Tile(cells)


GROUP = Group([Material("floor_ceramic", CERAMIC, draw)])

if __name__ == "__main__":
    raise SystemExit(main(GROUP, HERE))
