"""Pasto del solar y de afuera (4 familias x 4 variantes cada uno), hecho con Moana. Ver ../_ground_kit.py.

Las 4 familias (plain liso, patchy manchones, lush tupido, sunny claro) comparten el anillo del borde, así
cualquier casilla empalma con cualquier otra; el juego elige la familia por zonas y la variante al azar.
Afuera del solar es lo mismo un 15 % más oscuro, con otras semillas. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/ground/grass/build.py [--out DIR] [--preview DIR]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _ground_kit import (Group, Material, Shape, Tile, blended, dither, hash_cells,  # noqa: E402
                         levels, main, scatter, specks, waves)

# Tonos: 0 pie de las matas, 1 mancha oscura, 2 borde de la mancha y sombra, 3 pasto, 4 mancha clara,
# 5 brizna, 6 punta de la brizna.
GRASS = ["4c6029", "5e7930", "719236", "81a73a", "8db63d", "9ecc42", "cbf166"]


def darker(palette: list[str], factor: float) -> list[str]:
    return ["%02x%02x%02x" % tuple(round(int(c[i:i + 2], 16) * factor) for i in (0, 2, 4)) for c in palette]


OUTSIDE = darker(GRASS, 0.85)

C = {"d": 0, "k": 1, "m": 2, "b": 5, "t": 6}
# Matas: briznas de a 2 px (en la rejilla), más claras arriba, con el pie oscuro y la sombra corrida
# abajo a la derecha, como la luz del juego.
TALL = Shape(("..tt....", "..bb..tt", "ttbb..bb", "bbbbttbb", "bbbbbbbb", "dddddddd", "..mmmmmm"), C)
WIDE = Shape(("tt......tt", "bb..tt..bb", "bbttbbttbb", "bbbbbbbbbb", "dddddddddd", "..mmmmmmmm"), C)
FAN = Shape(("tt....tt", "bb..ttbb", "bbttbbbb", "bbbbbb..", "dddddd..", "..mmmm.."), C)
BIG = Shape(("tt..", "bbtt", "bbbb", "dddd", "..mm"), C)
SMALL = Shape(("tt", "bb", "dd", ".m"), C)
SPRIG = Shape(("..tt", "ttbb", "bbdd", "dd.."), C)
# Matitas oscuras (pasto más bajo), sin punta clara.
STROKE_A = Shape(("..dd..", "dd..dd"), C)
STROKE_B = Shape(("dd..dd..", "..dd..dd"), C)

RING_SEED = 6000
RING_SHARES = (0.06, 0.06, 0.18)  # mancha oscura, su borde, mancha clara
RING_SHAPES = [SMALL, STROKE_A, SPRIG, STROKE_B]
# (familia, partes de mancha oscura, borde y clara, matas de cada variante, semilla)
FAMILIES = (
    ("plain", (0.03, 0.05, 0.12), [BIG, SMALL, SMALL, SPRIG, STROKE_A, STROKE_B], 6100),
    ("patchy", (0.17, 0.09, 0.14), [TALL, BIG, SMALL, SPRIG, STROKE_B, STROKE_A, STROKE_A], 6200),
    ("lush", (0.10, 0.10, 0.20), [TALL, TALL, WIDE, FAN, FAN, BIG, BIG, SMALL, SMALL, SPRIG, SPRIG,
                                  STROKE_A, STROKE_B, STROKE_A, STROKE_B], 6300),
    ("sunny", (0.02, 0.06, 0.40), [SMALL, SMALL, SPRIG, STROKE_A], 6400),
)
DARK_WAVES = (2, 4)  # ciclos por casilla: manchas más chicas que la casilla
LIGHT_WAVES = (1, 3)


def grass(shares: tuple[float, float, float], shapes: list, seed: int, ring_seed: int):
    dark, mid, light = shares
    rd, rm, rl = RING_SHARES
    ring_dark = waves(ring_seed, *DARK_WAVES)
    ring_light = waves(ring_seed + 1, *LIGHT_WAVES)
    ring_speck = [hash_cells(ring_seed + 2), hash_cells(ring_seed + 3)]
    ring_shapes = scatter(RING_SHAPES, ring_seed + 7, inner=False)

    def draw(variant: int) -> Tile:
        s = seed + 31 * variant
        fd = blended(ring_dark, waves(s, *DARK_WAVES))
        fl = blended(ring_light, waves(s + 1, *LIGHT_WAVES))
        # Manchas: en el anillo con las partes comunes y adentro con las de la familia.
        dk = levels(fd, ring_dark, (dark, mid, 1 - dark - mid), (rd, rm, 1 - rd - rm))
        lt = levels(fl, ring_light, (1 - light, light), (1 - rl, rl))
        cells = 3 + lt
        cells[dk == 1] = 2
        cells[dk == 0] = 1
        cells = dither(cells, ((1, 2), (2, 3), (3, 4)))
        # Briznas sueltas: un tono más oscuro sobre el pasto y uno más claro sobre las manchas.
        cells = specks(cells, ring_speck[0], hash_cells(s + 2), 0.035, -1, (3, 4))
        cells = specks(cells, ring_speck[1], hash_cells(s + 3), 0.025, +1, (1, 2, 3))
        tile = Tile(cells)
        for shape, x, y in ring_shapes:
            tile.put(shape, x, y, wrap=True)
        used = tile.used.copy()
        for shape, x, y in scatter(shapes, s + 9, inner=True, used=used):
            tile.put(shape, x, y, wrap=False)
        return tile
    return draw


MATERIALS = []
for prefix, palette, offset in (("ground_grass", GRASS, 0), ("ground_outside", OUTSIDE, 500)):
    for name, shares, shapes, seed in FAMILIES:
        MATERIALS.append(Material(f"{prefix}_{name}", palette, grass(shares, shapes, seed + offset, RING_SEED + offset)))

GROUP = Group(MATERIALS, ring_groups=[[f"ground_grass_{f[0]}" for f in FAMILIES],
                                      [f"ground_outside_{f[0]}" for f in FAMILIES]])

if __name__ == "__main__":
    raise SystemExit(main(GROUP, HERE))
