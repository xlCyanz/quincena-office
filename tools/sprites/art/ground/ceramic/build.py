"""Cerámica blanca (4 variantes), hecha con Moana. Ver ../_ground_kit.py.

2×2 losas por casilla en damero de dos blancos, junta gris de 1 celda con las esquinas redondeadas, bisel
claro arriba y en sombra abajo, nubes muy suaves en el esmalte y un reflejo en diagonal que cambia de losa
según la variante. La junta y el bisel van en el borde, así empalma con cualquier vecina. Desde el
repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/ground/ceramic/build.py [--out DIR] [--preview DIR]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import numpy as np  # noqa: E402

from _ground_kit import A, B, IN_RING, Group, Material, Tile, main, waves  # noqa: E402

# 0 junta, 1 bisel en sombra (abajo a la derecha), 2 bisel suave (abajo a la izquierda), 3 losa del otro
# tono, 4 losa, 5 reflejo, 6 bisel claro, 7 nube de la losa, 8 nube del otro tono, 9 centro de la junta.
CERAMIC = ["a3a1a0", "bbb9b9", "d2d1d1", "e1e1e1", "e8e8e8", "f6f6f6", "ffffff", "ededed", "dcdcdc", "8f8d8c"]
SLAB = 32  # celdas por losa
SEED = 9100
# Reflejo: franjas "/" con k = 2·du − dv: (k0, k1, du mínimo, du máximo), en celdas de la losa.
GLINTS = {
    "wide": ((14, 18, 7, 23), (23, 24, 10, 25)),
    "thin": ((8, 9, 5, 17),),
    "none": (),
}
# Reflejo de cada losa (0 arriba, 1 derecha, 2 izquierda, 3 abajo) por variante: el ancho en una del tono
# base y el fino en una del otro, así todas tienen el mismo brillo.
LAYOUTS = (
    ("wide", "thin", "none", "none"),
    ("none", "none", "thin", "wide"),
    ("wide", "none", "thin", "none"),
    ("none", "thin", "none", "wide"),
)


def draw(variant: int) -> Tile:
    du, dv = A % SLAB, B % SLAB
    su, sv = A // SLAB, B // SLAB
    slab = su + 2 * sv
    base = (su + sv) % 2 == 0
    cells = np.where(base, 4, 3)
    # Nubes del esmalte: cambian con la variante, lejos del borde.
    cloud = (waves(SEED + 10 * variant, 3, 7, 16) > 0.7) & ~IN_RING
    cells[cloud & base] = 7
    cells[cloud & ~base] = 8
    field = (du >= 2) & (dv >= 2) & (du <= SLAB - 3) & (dv <= SLAB - 3)
    k = 2 * du - dv
    for number, glint in enumerate(LAYOUTS[variant]):
        area = field & (slab == number) & ~IN_RING
        for k0, k1, low, high in GLINTS[glint]:
            cells[area & (k >= k0) & (k <= k1) & (du >= low) & (du <= high)] = 5
    # Biseles: claro arriba, suave abajo a la izquierda y en sombra abajo a la derecha.
    cells[(dv == 1) & (du >= 1)] = 6
    cells[(du == 1) & (dv >= 1)] = 6
    cells[(dv == SLAB - 1) & (du >= 1)] = 2
    cells[(du == SLAB - 1) & (dv >= 1)] = 1
    cells[(du == 0) | (dv == 0)] = 0
    # Esquinas redondeadas y el cruce de juntas un poco más hondo.
    corner = ((du == 1) | (du == SLAB - 1)) & ((dv == 1) | (dv == SLAB - 1))
    cells[corner] = 0
    cells[(du == 0) & (dv == 0)] = 9
    return Tile(cells)


GROUP = Group([Material("floor_ceramic", CERAMIC, draw)])

if __name__ == "__main__":
    raise SystemExit(main(GROUP, HERE))
