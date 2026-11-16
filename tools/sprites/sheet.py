# Vistas de revisión (no son arte): ampliar, fondos, hojas de contacto y escenas por casilla
# con el orden de dibujo del juego (por Y de pantalla).
import os

import numpy as np
from PIL import Image, ImageDraw

BACKGROUND = (70, 76, 90)
HALF_W = 64
HALF_H = 32


def manifest(directory):
    """Entradas de los manifest*.json de una carpeta: archivo -> {canvas, anchor, footprint, …}."""
    import glob
    import json
    entries = {}
    for path in sorted(glob.glob(os.path.join(directory, "manifest*.json"))):
        with open(path, "r") as handle:
            for entry in json.load(handle).get("sprites", []):
                entries[entry["file"]] = entry
    return entries


def load(path):
    """Abre un PNG como RGBA."""
    return Image.open(path).convert("RGBA")


def upscale(image, factor=4):
    """Amplía ×factor con vecino más cercano (sin suavizar)."""
    return image.resize((image.size[0] * factor, image.size[1] * factor), Image.NEAREST)


def on_background(image, color=BACKGROUND, scale=4, margin=4):
    """El sprite sobre un fondo liso, ampliado ×scale. margin en px del sprite."""
    base = Image.new("RGBA", (image.size[0] + 2 * margin, image.size[1] + 2 * margin), tuple(color) + (255,))
    base.alpha_composite(image.convert("RGBA"), (margin, margin))
    return upscale(base, scale)


def plain_tile(base="c9b48a", joint=True):
    """Casilla de piso lisa 128×128 para mirar muebles; con joint, junta de 2 px un tono más oscura."""
    from palette import darken, hex_to_rgb
    ys, xs = np.mgrid[0:128, 0:128]
    u = ((ys - 64 + 0.5) / HALF_H + (xs + 0.5 - 64) / HALF_W) / 2.0
    v = ((ys - 64 + 0.5) / HALF_H - (xs + 0.5 - 64) / HALF_W) / 2.0
    mask = (u >= 0) & (u < 1) & (v >= 0) & (v < 1)
    rgba = np.zeros((128, 128, 4), dtype=np.uint8)
    rgba[mask, :3] = hex_to_rgb(base)
    if joint:
        edge = mask & ((u * 64 < 1) | (u * 64 >= 63) | (v * 64 < 1) | (v * 64 >= 63))
        rgba[edge, :3] = darken(base, 0.18)
    rgba[mask, 3] = 255
    return Image.fromarray(rgba, "RGBA")


def on_floor(image, floor=None, anchor=None, scale=4, color=BACKGROUND, cells=1):
    """Sprite sobre un parche de (2·cells+1)² casillas de piso (floor: imagen o variantes; por defecto
    plain_tile()). anchor por defecto: centro abajo − 32."""
    scene = Scene(2 * cells + 1, 2 * cells + 1, color=color, top=max(32, image.size[1] - 64 - cells * 64), margin=8)
    if floor is None:
        floor = plain_tile()
    tiles = floor if isinstance(floor, (list, tuple)) else [floor]
    scene.fill_floor(tiles, seed=1)
    if anchor is None:
        anchor = (image.size[0] // 2, image.size[1] - 32)
    scene.add(image, cells, cells, anchor=anchor)
    return scene.render(scale)


def contact_sheet(items, columns=4, scale=3, color=BACKGROUND, cell=None, labels=True, gap=6):
    """Hoja de contacto de imágenes, rutas o pares (etiqueta, imagen); cell = celda en px de sprite."""
    entries = []
    for item in items:
        label = ""
        if isinstance(item, (tuple, list)):
            label, item = item
        if isinstance(item, str):
            if not label:
                label = os.path.splitext(os.path.basename(item))[0]
            item = load(item)
        entries.append((label, item.convert("RGBA")))
    if not entries:
        return Image.new("RGBA", (16, 16), tuple(color) + (255,))
    if cell is None:
        cell = (max(e[1].size[0] for e in entries), max(e[1].size[1] for e in entries))
    label_h = 12 if labels else 0
    rows = (len(entries) + columns - 1) // columns
    cw = cell[0] * scale + gap
    ch = cell[1] * scale + gap + label_h
    sheet = Image.new("RGBA", (columns * cw + gap, rows * ch + gap), tuple(color) + (255,))
    draw = ImageDraw.Draw(sheet)
    for index, (label, image) in enumerate(entries):
        col, row = index % columns, index // columns
        x = gap + col * cw
        y = gap + row * ch
        big = upscale(image, scale)
        sheet.alpha_composite(big, (x + (cell[0] * scale - big.size[0]) // 2, y + label_h + cell[1] * scale - big.size[1]))
        if labels and label:
            draw.text((x + 1, y), label, fill=(220, 220, 220, 255))
    return sheet


class Scene(object):
    """Escena de prueba de cols × rows casillas con la convención del juego: (1, 0) queda abajo a
    la derecha de (0, 0) y (0, 1) abajo a la izquierda."""

    def __init__(self, cols=5, rows=5, color=BACKGROUND, top=160, margin=24):
        self.cols = cols
        self.rows = rows
        self.color = tuple(color)
        self.top = top
        self.margin = margin
        self.width = (cols + rows) * HALF_W + 2 * margin
        self.height = (cols + rows) * HALF_H + top + margin
        self.origin = (margin + rows * HALF_W, top)
        self._floor = []
        self._shadows = []
        self._items = []

    def cell_point(self, x, y):
        """Pixel de la escena del punto (x, y) de la cuadrícula; (x + 0.5, y + 0.5) es el centro de la casilla."""
        return (self.origin[0] + (x - y) * HALF_W, self.origin[1] + (x + y) * HALF_H)

    def floor(self, image, x, y):
        """Pone una casilla de piso (128×128 con el rombo abajo, o 128×64) en (x, y)."""
        px, py = self.cell_point(x + 0.5, y + 0.5)
        self._floor.append((image, int(px - 64), int(py - 32 - (image.size[1] - 64))))

    def fill_floor(self, tiles, seed=0, area=None):
        """Llena las casillas (o area = (x0, y0, x1, y1), sin x1, y1) con una variante al azar fijo por casilla."""
        rng = np.random.RandomState(seed)
        x0, y0, x1, y1 = area if area is not None else (0, 0, self.cols, self.rows)
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.floor(tiles[rng.randint(len(tiles))], x, y)

    def add(self, image, x, y, anchor=None, size=(1, 1), sort=None, bias=0.0):
        """Pone un sprite con su apoyo (por defecto (64, alto − 32)) en el centro de la casilla (x, y).
        size = planta ya girada, para ordenar; sort fuerza la Y de orden y bias la corre en px."""
        if anchor is None:
            anchor = (64, image.size[1] - 32)
        px, py = self.cell_point(x + 0.5, y + 0.5)
        if sort is None:
            sort = self.cell_point(x + size[0] / 2.0, y + size[1] / 2.0)[1]
        self._items.append((sort + bias, len(self._items), image, int(round(px - anchor[0])), int(round(py - anchor[1]))))

    def add_wall(self, image, x, y, axis, anchor=None, bias=0.0):
        """Pone una pared en un borde: axis 'x' entre (x, y) y (x+1, y) («/»), 'y' entre (x, y) y
        (x, y+1) («\\»). El apoyo (por defecto (36, alto − 18)) cae en el punto medio del borde."""
        if anchor is None:
            anchor = (36, image.size[1] - 18)
        if axis == "x":
            px, py = self.cell_point(x + 1.0, y + 0.5)
        else:
            px, py = self.cell_point(x + 0.5, y + 1.0)
        self._items.append((py + bias, len(self._items), image, int(round(px - anchor[0])), int(round(py - anchor[1]))))

    def add_wall_item(self, image, x, y, axis, anchor=(32, 112), thickness=0.125, bias=1.0):
        """Cuelga un objeto de pared (apoyo (32, 112)) en la cara visible del borde de add_wall,
        medio grosor por delante y dibujado después de la pared."""
        if axis == "x":
            px, py = self.cell_point(x + 1.0 + thickness / 2.0, y + 0.5)
            sort = self.cell_point(x + 1.0, y + 0.5)[1]
        else:
            px, py = self.cell_point(x + 0.5, y + 1.0 + thickness / 2.0)
            sort = self.cell_point(x + 0.5, y + 1.0)[1]
        self._items.append((sort + bias, len(self._items), image, int(round(px - anchor[0])), int(round(py - anchor[1]))))

    def add_shadow(self, image, x, y, anchor=None, opacity=0.3):
        """Pone una sombra con opacidad sobre el piso, debajo de todo lo demás."""
        if anchor is None:
            anchor = (64, image.size[1] - 32)
        px, py = self.cell_point(x + 0.5, y + 0.5)
        arr = np.array(image.convert("RGBA"))
        arr[..., 3] = (arr[..., 3].astype(np.float64) * opacity).astype(np.uint8)
        self._shadows.append((Image.fromarray(arr, "RGBA"), int(round(px - anchor[0])), int(round(py - anchor[1]))))

    def render(self, scale=3, crop=None):
        """Compone la escena ampliada ×scale; crop = (x0, y0, x1, y1) en px sin ampliar."""
        out = Image.new("RGBA", (self.width, self.height), self.color + (255,))
        layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
        for image, px, py in self._floor:
            _paste(layer, image, px, py)
        out = Image.alpha_composite(out, layer)
        for image, px, py in self._shadows:
            layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
            _paste(layer, image, px, py)
            out = Image.alpha_composite(out, layer)
        for _sort, _order, image, px, py in sorted(self._items, key=lambda item: (item[0], item[1])):
            layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
            _paste(layer, image, px, py)
            out = Image.alpha_composite(out, layer)
        if crop is not None:
            out = out.crop(crop)
        return upscale(out, scale) if scale != 1 else out


def _paste(layer, image, px, py):
    image = image.convert("RGBA")
    x0, y0 = max(px, 0), max(py, 0)
    x1, y1 = min(px + image.size[0], layer.size[0]), min(py + image.size[1], layer.size[1])
    if x0 >= x1 or y0 >= y1:
        return
    part = image.crop((x0 - px, y0 - py, x1 - px, y1 - py))
    layer.alpha_composite(part, (x0, y0))


def tile_mosaic(tiles, cols=4, rows=4, seed=0, scale=3, color=BACKGROUND):
    """Mosaico de piso de cols × rows casillas con variantes al azar fijo, para ver costuras."""
    scene = Scene(cols, rows, color=color, top=16, margin=8)
    scene.fill_floor(tiles, seed)
    return scene.render(scale)
