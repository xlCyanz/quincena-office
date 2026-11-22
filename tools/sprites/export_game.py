#!/usr/bin/env python3
# Pasa al juego los sprites conectados (suelo, paredes, árboles, muebles, objetos de pared y personajes).
#
#   python3 tools/sprites/export_game.py DIR
#
# DIR es la carpeta de generate.py (PNG y manifest*.json). Escribe assets/tiles/ground.png,
# assets/sprites/ y data/sprites.json (apoyos; lo lee SpriteLibrary). Los PNG de tools/sprites/art/
# (dibujados aparte, una carpeta por pieza) reemplazan a los de DIR con el mismo nombre.
# Después: Godot --headless --editor --quit
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
from pieces import character  # noqa: E402
from pieces import walls as wall_piece  # noqa: E402

# Sprites dibujados aparte: art/<categoría>/<pieza>/ con sus PNG y un manifest.json con el apoyo de
# cada uno. Reemplazan al de generate.py del mismo nombre.
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
TREES = 8

# Mueble (id de data/furniture.json) -> (sprite, si tiene rotaciones _r0.._r3). Los chicos usan _q.
FURNITURE = {
    "simple_desk": ("desk_simple", True), "executive_desk": ("executive_desk", True),
    "basic_chair": ("chair_basic", True), "ergonomic_chair": ("chair_ergonomic", True),
    "small_plant": ("plant_small_q", False), "large_plant": ("plant_large", False),
    "reception_counter": ("reception_counter", True), "waiting_sofa": ("waiting_sofa", True),
    "trash_can": ("trash_can_q", False), "water_dispenser": ("water_dispenser_q", True),
    "cleaning_closet": ("cleaning_closet", True), "server_rack": ("server_rack", True),
    "long_desk": ("desk_long", True),
    "basic_computer": ("computer_basic", True), "pro_computer": ("computer_pro", True),
    "meeting_table": ("meeting_table", False), "toilet": ("toilet", True), "sink": ("sink", True),
    "coffee_maker": ("coffee_maker", True), "fridge": ("fridge", True), "microwave": ("microwave", True),
    "printer": ("printer", True), "sofa": ("sofa", True), "ping_pong": ("ping_pong", True),
    "vending_machine": ("vending_machine", True), "dining_table": ("dining_table", True),
    "backup_battery": ("backup_battery", True), "filing_cabinet": ("filing_cabinet", True),
    "floor_lamp": ("floor_lamp_q", False), "rug": ("rug", False), "aquarium": ("aquarium", True),
}
# Objeto de pared -> dibujos posibles (uno fijo por casilla), cada uno con _x y _y.
WALL_ITEMS = {
    "air_conditioner": ("air_conditioner",), "painting": ("painting", "painting_abstract", "painting_sea"),
    "wall_clock": ("wall_clock",), "whiteboard": ("whiteboard",), "presentation_screen": ("presentation_screen",),
}
# Escritorio dibujado entero con su computadora -> sprite según las pantallas extra (0, 1, 2).
DESK_SETS = {"long_desk": {"basic_computer": ["desk_long_basic"],
                           "pro_computer": ["desk_long_pro1", "desk_long_pro2", "desk_long_pro3"]}}
# Sillas: asiento y respaldo aparte (<base>_seat_r0, <base>_back_r0); el respaldo va delante o
# detrás de quien se sienta según la rotación.
PARTS = ("chair_basic", "chair_ergonomic")

# Personajes: cuadros de cada pose, en el orden de las columnas de la hoja.
CHARACTER_CELL = (128, 128)
CHARACTER_POSES = (("stand", 1), ("sit", 1), ("idle", character.IDLE_FRAMES), ("walk", character.WALK_FRAMES),
                   ("type", character.TYPE_FRAMES))
CHARACTER_VARIANTS = ("", "_v1", "_v2")
# Poses del suape, solo del personal de limpieza: van en una hoja aparte (<aspecto>_tools.png).
TOOL_POSES = (("mop", character.MOP_FRAMES), ("mopwalk", character.MOPWALK_FRAMES))


def recolor(image, base, variant):
    """Cambia la paleta de un cuadro: cada tono de cada capa de `base` por el mismo tono de `variant`."""
    mapping = {}
    for layer in character.LAYER_ORDER:
        for old, new in zip(base.ramp(layer).colors, variant.ramp(layer).colors):
            old, new = tuple(old), tuple(new)
            if mapping.get(old, new) != new:
                raise SystemExit("personajes: el color %s está en dos capas con destinos distintos" % (old,))
            mapping[old] = new
    arr = np.array(image)
    out = arr.copy()
    done = arr[..., 3] == 0
    for old, new in mapping.items():
        take = (arr[..., 0] == old[0]) & (arr[..., 1] == old[1]) & (arr[..., 2] == old[2]) & (arr[..., 3] > 0)
        out[take, :3] = new
        done |= take
    if not done.all():
        raise SystemExit("personajes: hay colores fuera de las rampas del aspecto")
    return Image.fromarray(out)

# Sillas con las que se arma «sentado en su silla»: mueble del juego -> base del sprite.
SEATED_CHAIRS = {"basic_chair": "chair_basic", "ergonomic_chair": "chair_ergonomic"}


def check_chair_colors(directory):
    """Ningún tono de una silla puede ser también de la ropa, la piel o el pelo de un personaje."""
    used = {}
    for style in character.STYLES:
        for variant, look in character.LOOKS[style.name].items():
            for layer in character.LAYER_ORDER:
                for color in look.ramp(layer).colors:
                    used[tuple(color)] = "%s%s (%s)" % (style.name, variant, layer)
    for base in SEATED_CHAIRS.values():
        for rotation in range(4):
            arr = np.array(Image.open(os.path.join(directory, "%s_r%d.png" % (base, rotation))).convert("RGBA"))
            for color in np.unique(arr[arr[..., 3] > 0][:, :3], axis=0):
                key = tuple(int(v) for v in color)
                if key in used:
                    raise SystemExit("%s usa el color %s, que también es de %s" % (base, key, used[key]))


def bleed(tile):
    """Repite 1 px hacia afuera el color del borde del rombo (evita rendijas con zoom no entero)."""
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

    art = sheet.art_sprites()

    def copy(name, folder):
        target = os.path.join(ROOT, "assets", "sprites", folder)
        os.makedirs(target, exist_ok=True)
        if name + ".png" in art:
            source, entry = art[name + ".png"]
            image = Image.open(source).convert("RGBA")
        else:
            source = os.path.join(directory, name + ".png")
            image = load(name)
            entry = manifest.get(name + ".png", {})
        shutil.copyfile(source, os.path.join(target, name + ".png"))
        if "anchor" not in entry:
            raise SystemExit("%s no tiene anchor en el manifiesto" % name)
        sprites[name] = {"file": "%s/%s.png" % (folder, name), "anchor": [float(v) for v in entry["anchor"]],
                         "size": list(image.size)}

    for kind in EDGE_KINDS:
        for height in ("tall", "low"):
            for axis in ("x", "y"):
                copy("%s_%s_%s" % (kind, height, axis), "walls")
    for neighbors in wall_piece.post_combos():
        copy(wall_piece.post_name(neighbors), "walls")
    for index in range(TREES):
        copy("tree_%d" % index, "trees")
        copy("tree_%d_shadow" % index, "trees")

    furniture = {}
    for item, (base, rotated) in FURNITURE.items():
        parts = base in PARTS
        for suffix in (["_r%d" % r for r in range(4)] if rotated else [""]):
            if parts:
                copy(base + "_seat" + suffix, "furniture")
                copy(base + "_back" + suffix, "furniture")
            else:
                copy(base + suffix, "furniture")
            shadow = base + suffix + "_shadow"
            if shadow + ".png" in art or os.path.isfile(os.path.join(directory, shadow + ".png")):
                copy(base + suffix + "_shadow", "furniture")
        furniture[item] = {"base": base, "rotated": rotated, "parts": parts}
    for item, by_computer in DESK_SETS.items():
        for names in by_computer.values():
            for base in names:
                for rotation in range(4):
                    copy("%s_r%d" % (base, rotation), "furniture")
                    copy("%s_r%d_shadow" % (base, rotation), "furniture")
        furniture[item]["sets"] = by_computer
    seats = dict((name, round(value, 4)) for name, value in sheet.art_seats().items())

    wall_items = {}
    for item, bases in WALL_ITEMS.items():
        for base in bases:
            for axis in ("x", "y"):
                copy("%s_%s" % (base, axis), "wall_items")
        wall_items[item] = {"sprites": list(bases), "base_z": manifest[bases[0] + "_x.png"]["base_z"]}

    # ---- personajes
    # Cada hoja lleva además «sentado en su silla» por silla: silla entera + persona con su paleta +
    # la parte de la silla que la tapa.
    chair_poses = [(pose, count) for pose, count in CHARACTER_POSES if pose in ("sit", "type")]
    all_poses = list(CHARACTER_POSES)
    for item, base in SEATED_CHAIRS.items():
        all_poses += [("%s_%s" % (pose, item), count) for pose, count in chair_poses]
    columns = sum(count for _pose, count in all_poses)
    poses = {}
    column = 0
    for pose, count in all_poses:
        poses[pose] = {"column": column, "frames": count}
        column += count
    characters_dir = os.path.join(ROOT, "assets", "sprites", "characters")
    os.makedirs(characters_dir, exist_ok=True)
    check_chair_colors(directory)
    chairs = {}
    for item, base in SEATED_CHAIRS.items():
        for rotation in range(4):
            whole = Image.new("RGBA", CHARACTER_CELL, (0, 0, 0, 0))
            source = load("%s_r%d" % (base, rotation))
            whole.paste(source.crop((0, 0, CHARACTER_CELL[0], CHARACTER_CELL[1] - character.CHAIR_SHIFT)),
                        (0, character.CHAIR_SHIFT))
            chairs[(item, rotation)] = whole
    looks = {}
    for style in character.STYLES:
        frames = []  # (columna, fila, persona, silla entera o None, parte de la silla que tapa o None)
        for rotation in range(4):
            column = 0
            for pose, count in all_poses:
                plain = pose.split("_")[0]
                item = pose[len(plain) + 1:]
                for frame in range(count):
                    name = "character_%s%s_r%d" % (style.prefix, plain, rotation)
                    if plain not in ("stand", "sit"):
                        name += "_%d" % (frame + 1)
                    image = load(name)
                    if image.size != CHARACTER_CELL or manifest[name + ".png"]["anchor"] != [64.0, 112.0]:
                        raise SystemExit("%s: lienzo o apoyo distinto del esperado" % name)
                    chair = over = None
                    if item:
                        chair = chairs[(item, rotation)]
                        over = Image.open(os.path.join(directory, character.CHAIR_DIR,
                                                       "%s_%s.png" % (name, SEATED_CHAIRS[item]))).convert("RGBA")
                    frames.append((column, rotation, image, chair, over))
                    column += 1
        for suffix in CHARACTER_VARIANTS:
            page = Image.new("RGBA", (CHARACTER_CELL[0] * columns, CHARACTER_CELL[1] * 4), (0, 0, 0, 0))
            for column, row, image, chair, over in frames:
                if suffix:
                    image = recolor(image, character.LOOKS[style.name][""], character.LOOKS[style.name][suffix])
                if chair is not None:
                    joined = chair.copy()
                    joined.alpha_composite(image)
                    joined.alpha_composite(over)
                    image = joined
                page.paste(image, (column * CHARACTER_CELL[0], row * CHARACTER_CELL[1]))
            page.save(os.path.join(characters_dir, style.name + suffix + ".png"))
            looks[style.name + suffix] = "characters/%s%s.png" % (style.name, suffix)
    tool_poses = {}
    column = 0
    for pose, count in TOOL_POSES:
        tool_poses[pose] = {"column": column, "frames": count}
        column += count
    tool_looks = {}
    for style in character.STYLES:
        if style.name not in character.CLEANING_STYLES:
            continue
        for suffix in CHARACTER_VARIANTS:
            page = Image.new("RGBA", (CHARACTER_CELL[0] * column, CHARACTER_CELL[1] * 4), (0, 0, 0, 0))
            for rotation in range(4):
                for pose, count in TOOL_POSES:
                    for frame in range(count):
                        name = "character_%s%s_r%d_%d" % (style.prefix, pose, rotation, frame + 1)
                        image = load(name)
                        if image.size != CHARACTER_CELL or manifest[name + ".png"]["anchor"] != [64.0, 112.0]:
                            raise SystemExit("%s: lienzo o apoyo distinto del esperado" % name)
                        if suffix:
                            image = recolor(image, character.LOOKS[style.name][""], character.LOOKS[style.name][suffix])
                        page.paste(image, ((tool_poses[pose]["column"] + frame) * CHARACTER_CELL[0],
                                           rotation * CHARACTER_CELL[1]))
            page.save(os.path.join(characters_dir, style.name + suffix + "_tools.png"))
            tool_looks[style.name + suffix] = "characters/%s%s_tools.png" % (style.name, suffix)
    copy("character_stand_shadow", "characters")
    copy("mop_bucket", "characters")
    copy("mop_bucket_shadow", "characters")

    data = {
        "_comentario": "Sprites conectados al juego (lo escribe tools/sprites/export_game.py; no editar a mano). scale = "
                       "px de sprite por px del mundo. ground: atlas del suelo, una fila por estilo (row) con count "
                       "variantes de tile px cada una. sprites: archivo dentro de assets/sprites, punto de apoyo "
                       "(anchor, en px del sprite) y tamaño. furniture: mueble del juego -> base del nombre de su sprite, "
                       "si tiene rotaciones (_r0.._r3) y si va en partes (_seat y _back antes de la rotación); "
                       "la sombra es el nombre sin parte más _shadow; sets = el mueble se dibuja entero con lo que "
                       "lleva encima: computadora -> base del sprite según las pantallas extra (0, 1, 2). seats: "
                       "base de un sprite de escritorio o de computadora -> a qué altura del modelo queda el teclado, "
                       "en casillas a lo largo del mueble desde su punta −x (ahí se dibuja quien se sienta). wall_items: objeto de pared -> dibujos "
                       "(sprites, cada uno con _x y _y según el eje del borde) y a cuántos px de sprite del piso "
                       "empieza (base_z). characters: hojas de personajes (looks: "
                       "aspecto -> archivo; una fila por dirección r0..r3; poses: columna del primer cuadro y "
                       "cuántos tiene; sit_<silla> y type_<silla> = sentado en esa silla, con la silla dibujada; "
                       "tool_poses y tool_looks: poses del suape (mop, mopwalk) en una hoja aparte, solo del personal "
                       "de limpieza; bucket: el cubo que se dibuja junto a quien trapea; "
                       "cell y anchor en px del sprite).",
        "scale": 2,
        "ground": {"file": "res://assets/tiles/ground.png", "tile": list(TILE), "styles": styles},
        "characters": {"cell": list(CHARACTER_CELL), "anchor": [64, 112], "poses": poses, "looks": looks,
                       "tool_poses": tool_poses, "tool_looks": tool_looks, "bucket": "mop_bucket",
                       "shadow": "character_stand_shadow"},
        "furniture": furniture,
        "seats": seats,
        "sprites": sprites,
        "wall_items": wall_items,
    }
    with open(os.path.join(ROOT, "data", "sprites.json"), "w") as handle:
        json.dump(data, handle, indent="\t", sort_keys=True, ensure_ascii=False)
        handle.write("\n")
    print("suelo: %d estilos · muebles: %d · aspectos: %d · piezas: %d" % (len(styles), len(furniture), len(looks), len(sprites)))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__ or "uso: export_game.py DIR")
    main(sys.argv[1])
