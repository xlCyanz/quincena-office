#!/usr/bin/env python3
# Vista previa: arma una oficina con los PNG de tools/sprites/art/ y una hoja de contacto de paredes y personajes.
#
#   python3 tools/sprites/preview.py --out CARPETA [--seed N]
#
# Escribe en --out _preview_x1.png, _preview_x2.png y _contact_x3.png.
# Ordena como el juego: pisos, sombras en una sola capa y lo demás por la Y de su punto de orden.
import argparse
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

import sheet  # noqa: E402

# Medidas del local y del terreno, en casillas.
OFFICE_COLS = 6
OFFICE_ROWS = 5
GRASS = 3
SHADOW_OPACITY = 0.3
BACKGROUND = (46, 52, 64)

# Copiadas de scripts/office/furniture_view.gd (en casillas o px del mundo).
SORT_BIAS_WORLD_PX = 1.0
SEAT_INSET = 0.15
BACKREST_DEPTH = 0.18
FRONTS = {0: (0, -1), 1: (1, 0), 2: (0, 1), 3: (-1, 0)}

# Rango de desempate (menor = antes) para cosas con la misma Y de orden.
RANK_WALL = 0
RANK_FURNITURE = 1
RANK_PC_SHADOW = 2
RANK_PC = 3
RANK_BACK = 4
RANK_PERSON = 5

# Grupos de la hoja de contacto, en orden.
GROUPS = ("walls", "characters")


class PreviewScene(sheet.Scene):
    """Scene con punto de orden y desempate explícitos, y sombras en una sola capa."""

    def __init__(self, cols, rows, color, top, margin):
        sheet.Scene.__init__(self, cols, rows, color=color, top=top, margin=margin)
        self._shadow_items = []

    def sort_y(self, gx, gy):
        """Y de pantalla (px de sprite) del punto (gx, gy) de la cuadrícula."""
        return self.cell_point(gx, gy)[1]

    def put(self, image, at, anchor, sort_at, rank, bias=0.0):
        """image con su apoyo en at = (gx, gy); ordena por la Y de sort_at + bias (px de sprite), luego rank."""
        px, py = self.cell_point(at[0], at[1])
        key = (self.sort_y(sort_at[0], sort_at[1]) + bias, rank, len(self._items))
        self._items.append((key, len(self._items), image, int(round(px - anchor[0])), int(round(py - anchor[1]))))

    def put_shadow(self, image, at, anchor):
        px, py = self.cell_point(at[0], at[1])
        self._shadow_items.append((image, int(round(px - anchor[0])), int(round(py - anchor[1]))))

    def render(self, scale=1, crop=None):
        out = Image.new("RGBA", (self.width, self.height), self.color + (255,))
        layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
        for image, px, py in self._floor:
            sheet._paste(layer, image, px, py)
        out = Image.alpha_composite(out, layer)
        # Sombras: unión de todas (mismo tono) y una sola transparencia.
        shadow = Image.new("RGBA", out.size, (0, 0, 0, 0))
        for image, px, py in self._shadow_items:
            sheet._paste(shadow, image, px, py)
        arr = np.array(shadow)
        arr[..., 3] = (arr[..., 3].astype(np.float64) * SHADOW_OPACITY).astype(np.uint8)
        out = Image.alpha_composite(out, Image.fromarray(arr))
        for _key, _order, image, px, py in sorted(self._items, key=lambda item: item[0]):
            layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
            sheet._paste(layer, image, px, py)
            out = Image.alpha_composite(out, layer)
        if crop is not None:
            out = out.crop(crop)
        return sheet.upscale(out, scale) if scale != 1 else out


def with_opacity(image, opacity):
    arr = np.array(image.convert("RGBA"))
    arr[..., 3] = (arr[..., 3].astype(np.float64) * opacity).astype(np.uint8)
    return Image.fromarray(arr)


class Office(object):
    """Arma la escena; el local se corre GRASS casillas para dejar lugar al pasto."""

    def __init__(self, seed):
        self.seed = seed
        self.art = sheet.art_sprites()  # todo lo dibuja Moana
        self.manifest = dict((name, entry) for name, (_path, entry) in self.art.items())
        cols = OFFICE_COLS + 2 * GRASS
        rows = OFFICE_ROWS + 2 * GRASS
        self.scene = PreviewScene(cols, rows, BACKGROUND, top=24, margin=24)
        self._cache = {}

    def img(self, name):
        if name not in self._cache:
            if name + ".png" not in self.art:
                raise SystemExit("Falta %s.png en tools/sprites/art/: corre su build.py" % name)
            self._cache[name] = sheet.load(self.art[name + ".png"][0])
        return self._cache[name]

    def anchor(self, name, default=(64, 96)):
        entry = self.manifest.get(name + ".png", {})
        return tuple(entry.get("anchor", default))

    def g(self, x, y):
        """Punto de la cuadrícula de la escena para el punto (x, y) del local."""
        return (x + GRASS, y + GRASS)

    def center(self, x, y):
        return self.g(x + 0.5, y + 0.5)

    # ------------------------------------------------------------------ pisos

    def floors(self):
        rng = np.random.RandomState(self.seed)
        ceramic = [self.img("floor_ceramic_%d" % i) for i in range(4)]
        grass = [self.img("ground_grass_plain_%d" % i) for i in range(4)]
        for sy in range(self.scene.rows):
            for sx in range(self.scene.cols):
                x, y = sx - GRASS, sy - GRASS
                inside = 0 <= x < OFFICE_COLS and 0 <= y < OFFICE_ROWS
                tiles = ceramic if inside else grass
                self.scene.floor(tiles[rng.randint(len(tiles))], sx, sy)

    # ------------------------------------------------------------------ paredes

    def wall(self, name, x, y, axis):
        """Tramo en el borde (x, y, axis): _x de (x, y) a (x + 1, y), _y de (x, y) a (x, y + 1)."""
        image = self.img(name)
        entry = self.manifest.get(name + ".png", {})
        anchor = tuple(entry.get("anchor", (36, image.size[1] - 18)))
        bias = float(entry.get("sort_bias", 0.5 if axis == "x" else 0.0))
        mid = self.g(x + 1.0, y + 0.5) if axis == "x" else self.g(x + 0.5, y + 1.0)
        self.scene.put(image, mid, anchor, mid, RANK_WALL, bias)
        if name == "wall_tall_" + axis or name == "door_tall_" + axis:
            # Sombra de la pared alta en la casilla de adentro (la puerta no la lleva: se pasa).
            if name.startswith("wall_"):
                inner = self.center(x + 1, y) if axis == "x" else self.center(x, y + 1)
                shadow = "wall_tall_%s_shadow" % axis
                self.scene.put_shadow(self.img(shadow), inner, self.anchor(shadow))

    def walls(self, tall_door, low_door):
        """Altas al fondo (lados de arriba), bajas al frente; una puerta en cada una."""
        for i in range(OFFICE_COLS):
            kind = "door_tall_y" if (i, "y") == tall_door else "wall_tall_y"
            self.wall(kind, i, -1, "y")
            kind = "door_low_y" if (i, "y") == low_door else "wall_low_y"
            self.wall(kind, i, OFFICE_ROWS - 1, "y")
        for j in range(OFFICE_ROWS):
            kind = "door_tall_x" if (j, "x") == tall_door else "wall_tall_x"
            self.wall(kind, -1, j, "x")
            kind = "door_low_x" if (j, "x") == low_door else "wall_low_x"
            self.wall(kind, OFFICE_COLS - 1, j, "x")

    # ------------------------------------------------------------------ muebles

    def furniture(self, name, x, y, shadow=True):
        c = self.center(x, y)
        self.scene.put(self.img(name), c, self.anchor(name), c, RANK_FURNITURE, -2 * SORT_BIAS_WORLD_PX)
        if shadow:
            self.scene.put_shadow(self.img(name + "_shadow"), c, self.anchor(name + "_shadow"))

    def desk(self, x, y, rotation):
        """Escritorio con computadora y la silla en la casilla de su frente, mirándolo."""
        c = self.center(x, y)
        self.furniture("desk_simple_r%d" % rotation, x, y)
        pc = "computer_basic_r%d" % rotation
        bias = -2 * SORT_BIAS_WORLD_PX
        self.scene.put(with_opacity(self.img(pc + "_shadow"), SHADOW_OPACITY), c, self.anchor(pc + "_shadow"), c,
                       RANK_PC_SHADOW, bias)
        self.scene.put(self.img(pc), c, self.anchor(pc), c, RANK_PC, bias)
        fx, fy = FRONTS[rotation]
        self.chair(x + fx, y + fy, (rotation + 2) % 4)

    def chair(self, x, y, rotation):
        """Asiento y respaldo como piezas aparte, cada uno con su punto de orden (FurnitureView)."""
        c = self.center(x, y)
        bias = -2 * SORT_BIAS_WORLD_PX
        seat = "chair_basic_seat_r%d" % rotation
        back = "chair_basic_back_r%d" % rotation
        self.scene.put(self.img(seat), c, self.anchor(seat), c, RANK_FURNITURE, bias)
        fx, fy = FRONTS[rotation]
        # Centro de la franja de atrás: el asiento va de SEAT_INSET a 1 − SEAT_INSET.
        reach = 0.5 - SEAT_INSET - BACKREST_DEPTH / 2.0
        strip = self.g(x + 0.5 - fx * reach, y + 0.5 - fy * reach)
        self.scene.put(self.img(back), c, self.anchor(back), strip, RANK_BACK, bias)
        self.scene.put_shadow(self.img("chair_basic_r%d_shadow" % rotation), c,
                              self.anchor("chair_basic_r%d_shadow" % rotation))

    def small(self, name, x, y, quarter):
        """Mueble chico (sprite _q, ya a su tamaño final) en un cuarto de la casilla
        (FurnitureCatalog.get_quarter_offset)."""
        ox = ((quarter % 2) - 0.5) * 0.5
        oy = ((quarter // 2) - 0.5) * 0.5
        at = self.g(x + 0.5 + ox, y + 0.5 + oy)
        self.scene.put(self.img(name), at, self.anchor(name), at, RANK_FURNITURE, -2 * SORT_BIAS_WORLD_PX)
        self.scene.put_shadow(self.img(name + "_shadow"), at, self.anchor(name + "_shadow"))

    # ------------------------------------------------------------------ personas

    def person(self, name, x, y):
        c = self.center(x, y)
        self.scene.put(self.img(name), c, self.anchor(name, (64, 112)), c, RANK_PERSON)
        self.scene.put_shadow(self.img("character_stand_shadow"), c, self.anchor("character_stand_shadow", (64, 112)))

    # ------------------------------------------------------------------ armado

    def build(self):
        self.floors()
        # Puerta alta al fondo y baja al frente.
        self.walls(tall_door=(2, "y"), low_door=(3, "x"))
        # Cuatro puestos, uno por rotación (la silla en la casilla del frente del escritorio).
        self.desk(1, 1, 1)
        self.desk(4, 1, 3)
        self.desk(1, 3, 2)
        self.desk(4, 3, 0)
        # Plantas: la grande en la esquina del fondo, dos chicas en una casilla y otra suelta.
        self.furniture("plant_large", 0, 0)
        self.small("plant_small_q", 5, 0, 0)
        self.small("plant_small_q", 5, 0, 3)
        self.small("plant_small_q", 0, 4, 1)
        # Personas: las 4 direcciones y las variantes de paleta; una afuera, frente a la puerta baja.
        self.person("character_stand_r1", 2, 0)
        self.person("character_stand_r2", 3, 4)
        self.person("character_stand_r0", 3, 3)
        self.person("character_stand_r3", 6, 3)
        self.person("character_office_stand_r1", 0, 2)
        self.person("character_woman_stand_r1", 5, 1)
        return self.scene


# ---------------------------------------------------------------------------- hoja de contacto

def _font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow viejo: solo la fuente de mapa de bits
        return ImageFont.load_default()


def contact(scale=3, columns=8, gap=12):
    """Las piezas de GROUPS (carpetas de art/; de los personajes, solo de pie), ×scale sobre un fondo, con su nombre."""
    by_group = {}
    for folder, manifest in sheet.art_manifests():
        group = os.path.relpath(folder, sheet.ART_DIR).split(os.sep)[0]
        if group not in GROUPS:
            continue
        for name in sorted(manifest["sprites"]):
            if group == "characters" and "_stand_r" not in name:
                continue
            by_group.setdefault(group, []).append(os.path.join(folder, name))
    order = [g for g in GROUPS if g in by_group] + sorted(g for g in by_group if g not in GROUPS)
    label_font = _font(18)
    title_font = _font(28)
    label_h = 26
    title_h = 44
    blocks = []
    for group in order:
        names = by_group[group]
        images = [(os.path.basename(n)[:-4], sheet.load(n)) for n in names]
        cw = max(i.size[0] for _, i in images) * scale
        ch = max(i.size[1] for _, i in images) * scale
        cw = max(cw, 128 * scale)
        rows = (len(images) + columns - 1) // columns
        block = Image.new("RGBA", (columns * (cw + gap) + gap, title_h + rows * (ch + label_h + gap) + gap),
                          BACKGROUND + (255,))
        draw = ImageDraw.Draw(block)
        draw.text((gap, 8), "%s (%d)" % (group, len(images)), fill=(235, 235, 235, 255), font=title_font)
        for index, (label, image) in enumerate(images):
            col, row = index % columns, index // columns
            x = gap + col * (cw + gap)
            y = title_h + row * (ch + label_h + gap)
            draw.rectangle((x, y + label_h, x + cw - 1, y + label_h + ch - 1), fill=(70, 76, 90, 255))
            big = sheet.upscale(image, scale)
            block.alpha_composite(big, (x + (cw - big.size[0]) // 2, y + label_h + ch - big.size[1]))
            draw.text((x + 2, y + 2), label, fill=(220, 220, 220, 255), font=label_font)
        blocks.append(block)
    width = max(b.size[0] for b in blocks)
    height = sum(b.size[1] for b in blocks)
    out = Image.new("RGBA", (width, height), BACKGROUND + (255,))
    y = 0
    for block in blocks:
        out.alpha_composite(block, (0, y))
        y += block.size[1]
    return out


def main():
    parser = argparse.ArgumentParser(description="Vista previa de la oficina y hoja de contacto del piloto.")
    parser.add_argument("--out", required=True, help="carpeta de salida")
    parser.add_argument("--seed", type=int, default=7, help="azar fijo de las variantes de piso")
    args = parser.parse_args()
    out_dir = os.path.abspath(args.out)
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    scene = Office(args.seed).build()
    image = scene.render(scale=1)
    written = []
    for name, picture in (("_preview_x1.png", image), ("_preview_x2.png", sheet.upscale(image, 2)),
                          ("_contact_x3.png", contact())):
        path = os.path.join(out_dir, name)
        picture.convert("RGB").save(path)
        written.append(path)
        print("%s  %dx%d" % (path, picture.size[0], picture.size[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
