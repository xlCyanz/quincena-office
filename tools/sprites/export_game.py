#!/usr/bin/env python3
# Pasa al juego los sprites que ya están conectados (por ahora: suelo, paredes y árboles).
#
#   python3 tools/sprites/export_game.py DIR
#
# DIR es la carpeta donde generate.py escribió los PNG y sus manifest*.json. Escribe:
#   assets/tiles/ground.png      atlas del suelo: una fila por estilo, una columna por variante;
#                                cada casilla mide 128×64 (el rombo del sprite, sin la mitad vacía
#                                de arriba) y lleva 1 px de más alrededor del rombo (el color del
#                                borde repetido) para que dos casillas vecinas no dejen rendija
#                                cuando el zoom no es entero
#   assets/sprites/walls/*.png   tramos de pared, puerta, ventana y puerta de vidrio, y los postes
#   assets/sprites/trees/*.png   los árboles y sus sombras
#   data/sprites.json            dónde está cada cosa y su punto de apoyo (lo lee SpriteLibrary)
#
# Después hay que dejar que Godot importe lo nuevo: Godot --headless --editor --quit
import json
import os
import shutil
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import sheet  # noqa: E402

TILE = (128, 64)
VARIANTS = 4
GRASS_FAMILIES = ("plain", "patchy", "lush", "sunny")
# Estilo del juego -> prefijo del sprite (las variantes son _0 … _3).
GROUND = [("bare", "floor_bare"), ("carpet", "floor_carpet"), ("wood", "floor_wood"), ("ceramic", "floor_ceramic")]
GROUND += [("grass_" + f, "ground_grass_" + f) for f in GRASS_FAMILIES]
GROUND += [("outside_" + f, "ground_outside_" + f) for f in GRASS_FAMILIES]
GROUND += [("path", "ground_path"), ("sidewalk", "ground_sidewalk"), ("road", "ground_road"),
           ("road_line_x", "ground_road_line_x"), ("road_line_y", "ground_road_line_y")]

EDGE_KINDS = ("wall", "door", "window", "glass_door")
CORNERS = ("wall_tall_corner", "wall_tall_corner_left", "wall_tall_corner_right", "wall_tall_corner_front",
           "wall_low_corner", "wall_low_corner_back", "wall_low_corner_left", "wall_low_corner_right")
TREES = 8


def bleed(tile):
    """Repite 1 px hacia afuera el color del borde del rombo (4 vecinos)."""
    arr = np.array(tile)
    alpha = arr[..., 3] > 0
    out = arr.copy()
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        moved = np.roll(arr, (dy, dx), axis=(0, 1))
        ok = np.roll(alpha, (dy, dx), axis=(0, 1))
        if dy == 1:
            ok[0, :] = False
        if dy == -1:
            ok[-1, :] = False
        if dx == 1:
            ok[:, 0] = False
        if dx == -1:
            ok[:, -1] = False
        take = ok & ~(out[..., 3] > 0)
        out[take] = moved[take]
    return Image.fromarray(out)


def main(directory):
    manifest = sheet.manifest(directory)

    def load(name):
        path = os.path.join(directory, name + ".png")
        if not os.path.isfile(path):
            raise SystemExit("Falta %s: corre antes generate.py --out %s" % (path, directory))
        return Image.open(path).convert("RGBA")

    # ---- suelo
    atlas = Image.new("RGBA", (TILE[0] * VARIANTS, TILE[1] * len(GROUND)), (0, 0, 0, 0))
    styles = {}
    for row, (style, prefix) in enumerate(GROUND):
        for column in range(VARIANTS):
            tile = load("%s_%d" % (prefix, column)).crop((0, 64, 128, 128))
            atlas.paste(bleed(tile), (column * TILE[0], row * TILE[1]))
        styles[style] = {"row": row, "count": VARIANTS}
    tiles_dir = os.path.join(ROOT, "assets", "tiles")
    os.makedirs(tiles_dir, exist_ok=True)
    atlas.save(os.path.join(tiles_dir, "ground.png"))

    # ---- piezas sueltas
    sprites = {}

    def copy(name, folder):
        target = os.path.join(ROOT, "assets", "sprites", folder)
        os.makedirs(target, exist_ok=True)
        image = load(name)
        shutil.copyfile(os.path.join(directory, name + ".png"), os.path.join(target, name + ".png"))
        entry = manifest.get(name + ".png", {})
        if "anchor" not in entry:
            raise SystemExit("%s no tiene anchor en el manifiesto" % name)
        sprites[name] = {"file": "%s/%s.png" % (folder, name), "anchor": [float(v) for v in entry["anchor"]],
                         "size": list(image.size)}

    for kind in EDGE_KINDS:
        for height in ("tall", "low"):
            for axis in ("x", "y"):
                copy("%s_%s_%s" % (kind, height, axis), "walls")
    for name in CORNERS:
        copy(name, "walls")
    for index in range(TREES):
        copy("tree_%d" % index, "trees")
        copy("tree_%d_shadow" % index, "trees")

    data = {
        "_comentario": "Sprites conectados al juego (lo escribe tools/sprites/export_game.py; no editar a mano). scale = "
                       "px de sprite por px del mundo. ground: atlas del suelo, una fila por estilo (row) con count "
                       "variantes de tile px cada una. sprites: archivo dentro de assets/sprites, punto de apoyo "
                       "(anchor, en px del sprite) y tamaño.",
        "scale": 2,
        "ground": {"file": "res://assets/tiles/ground.png", "tile": list(TILE), "styles": styles},
        "sprites": sprites,
    }
    with open(os.path.join(ROOT, "data", "sprites.json"), "w") as handle:
        json.dump(data, handle, indent="\t", sort_keys=True, ensure_ascii=False)
        handle.write("\n")
    print("suelo: %d estilos · piezas: %d" % (len(styles), len(sprites)))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__ or "uso: export_game.py DIR")
    main(sys.argv[1])
