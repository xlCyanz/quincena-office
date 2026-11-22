# Decoración: lámpara de pie, alfombra y pecera (estilo de tools/sprites/STYLE.md).
#
#   floor_lamp            128×160, apoyo (64, 96); a tamaño de casilla (el juego la achica al 60 %)
#   floor_lamp_q          la misma ya al 60 %
#   floor_lamp(_q)_shadow sombra en el piso, aparte
#   rug                   256×128, solo el rombo de 2×2 (se pisa, como un piso)
#   aquarium_r0..r3       192×160: mueble de madera con el tanque encima
#   aquarium_r0..r3_shadow
#   _sheets/decor.png     hoja de contacto
#
# El frente de la pecera (las puertas) mira a −y con rotación 0.
import os

import numpy as np

import iso
import palette as pal
import sheet
from pieces import _shadow

ITEMS = iso.load_json("data/furniture.json")["items"]
LAMP_ITEM = ITEMS["floor_lamp"]
RUG_ITEM = ITEMS["rug"]
AQUARIUM_ITEM = ITEMS["aquarium"]

# ---------------------------------------------------------------------------- rampas

METAL = pal.METAL_LIGHT
PLASTIC = pal.PLASTIC_BLACK
# Pantalla de tela crema encendida: brilla bajo el borde.
SHADE = pal.style_ramp("f6e3a1", side="ecd28a", shadow="dcbd72", outline="4e3510", deep="a07a35",
                       light="fff6d6", name="lamp_shade")
SHADE_GLOW = SHADE.add("fff1b8")
SHADE_SEAM = SHADE.add("d9b866")

RUG = pal.style_ramp("9c4f5e", outline="3b1520", name="rug")
RUG_DARK = RUG.add("7a3846")
RUG_CREAM = RUG.add("e8d6b0")
RUG_CREAM_DARK = RUG.add("c9b48c")
RUG_GOLD = RUG.add("d4a046")
RUG_NAVY = RUG.add("34456b")

WOOD = pal.style("wood_orange", name="aquarium_stand")
WOOD_LINE = WOOD.add("5b2a10")
KNOB = WOOD.add("f1d39a")
WATER = pal.style_ramp("4f9fc9", side="3d8bb8", shadow="347ca7", outline="1b2f3d", deep="245a7d",
                       light="9fd6ef", name="aquarium_water")
WATER_DEEP = WATER.add("2d6f99")
WATER_SHINE = WATER.add("c8ecf7")
SAND = WATER.add("e2c68c")
SAND_DARK = WATER.add("c4a46a")
WEED = WATER.add("4c9a3a")
WEED_LIGHT = WATER.add("7cc24a")
STONE = WATER.add("8a8f96")
FISH_ORANGE = WATER.add("f08a2c")
FISH_YELLOW = WATER.add("f4d04a")
FISH_RED = WATER.add("d8434a")
FISH_EYE = WATER.add("1b1b1d")
RIM = pal.style("plastic_black", name="aquarium_rim")


# ---------------------------------------------------------------------------- lámpara de pie

def lamp(c, scale=1.0):
    """Lámpara centrada en la casilla: base de 3 px, poste y pantalla en cono truncado."""
    height = iso.world_px(LAMP_ITEM["height"]) * scale  # 68 px de sprite a escala 1
    shade_h = round(24 * scale)
    pole_top = height - shade_h + round(4 * scale)
    c.cylinder(0.5, 0.5, 0.17 * scale, 0, max(2, round(3 * scale)), PLASTIC, name="base")
    c.cylinder(0.5, 0.5, 0.06 * scale, max(2, round(3 * scale)), max(3, round(5 * scale)), PLASTIC, name="foot")
    c.cylinder(0.5, 0.5, 0.022 if scale < 1 else 0.026, max(3, round(5 * scale)), pole_top, METAL, name="pole")

    def shade_tex(ctx):
        index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(np.shape(ctx.b), ctx.base)
        b = np.floor(ctx.b)
        # Costura vertical y filo claro arriba y abajo.
        index = np.where(np.abs(ctx.t) < 0.06, SHADE_SEAM, index)
        index = np.where((b == 0) & (ctx.t < 0.4), SHADE_GLOW, index)
        return np.where(b >= shade_h - 1, pal.LIGHT, index)

    c.cylinder(0.5, 0.5, 0.20 * scale, height - shade_h, height, SHADE, radius_top=0.13 * scale,
               tex={"side": shade_tex}, name="shade")
    return c


def lamp_shadow_shapes(scale=1.0):
    return [("disc", 0.5, 0.5, 0.17 * scale, 0, 0), ("disc", 0.5, 0.5, 0.20 * scale, 40 * scale, 68 * scale)]


# ---------------------------------------------------------------------------- alfombra

RUG_SIZE = 128  # px de la textura por lado (2 casillas de 64)


def rug_tex(ctx):
    """Textura de la alfombra; a, b de 0 a 128 a lo largo de x e y."""
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    edge = np.minimum(np.minimum(a, RUG_SIZE - 1 - a), np.minimum(b, RUG_SIZE - 1 - b))
    index = np.full(a.shape, pal.BASE)
    # Borde oscuro de 2 px, banda crema con grecas y filete dorado.
    index = np.where(edge < 2, RUG_DARK, index)
    band = (edge >= 3) & (edge < 13)
    index = np.where(band, RUG_CREAM, index)
    along = np.where(np.minimum(a, RUG_SIZE - 1 - a) == edge, b, a)
    greca = band & (edge >= 6) & (edge < 10) & (np.mod(along, 8) < 4) & (np.mod(along + edge, 8) < 6)
    index = np.where(greca, RUG_DARK, index)
    index = np.where((edge == 13) | (edge == 2), RUG_GOLD, index)
    # Medallón: rombo dorado con centro azul y rombo vino.
    da = np.abs(a + 0.5 - RUG_SIZE / 2.0)
    db = np.abs(b + 0.5 - RUG_SIZE / 2.0)
    diamond = np.maximum(da, db) * 1.4  # cuadrado en el modelo = rombo en pantalla
    index = np.where((diamond < 34) & (edge >= 14), RUG_DARK, index)
    index = np.where((diamond < 30) & (edge >= 14), RUG_GOLD, index)
    index = np.where(diamond < 26, RUG_NAVY, index)
    index = np.where(diamond < 16, pal.BASE, index)
    index = np.where(diamond < 8, RUG_CREAM, index)
    # Cuatro rombitos en las esquinas del campo.
    for ca, cb in ((32, 32), (96, 32), (32, 96), (96, 96)):
        corner = np.maximum(np.abs(a + 0.5 - ca), np.abs(b + 0.5 - cb)) * 1.4
        index = np.where((corner < 8) & (edge >= 14), RUG_GOLD, index)
        index = np.where((corner < 4) & (edge >= 14), RUG_NAVY, index)
    # Trama del tejido: un punto más oscuro cada 4 px.
    weave = (index == pal.BASE) & (np.mod(a + 2 * b, 4) == 0) & (np.mod(b, 2) == 0)
    return np.where(weave, pal.SOFT, index)


def rug():
    c = iso.Canvas.furniture(RUG_ITEM["size"], RUG_ITEM["height"], flat=True)
    c.slab(0.0, 2.0, 0.0, 2.0, 0, RUG, tex=rug_tex, name="rug")
    return c


# ---------------------------------------------------------------------------- pecera

STAND_TOP = 20  # alto del mueble (px de sprite)
# El tanque llega a 56, más que el `height` del juego (20 → 40), para que se lea como pecera.
TANK_TOP = 56
TANK_INSET = 2 / 64.0


def stand_front(ctx):
    """Frente del mueble: dos puertas con tirador y zócalo."""
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    w = np.floor(ctx.w)
    index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(a.shape, ctx.base)
    door = (b >= 3) & (b < STAND_TOP - 3) & (a >= 4) & (a < w - 4)
    groove = door & ((b == 3) | (b == STAND_TOP - 4) | (a == 4) | (a == w - 5) | (np.abs(a - w / 2.0) < 1))
    index = np.where(groove, WOOD_LINE, index)
    knobs = (b >= 9) & (b < 11) & ((np.abs(a - (w / 2.0 - 4)) < 1) | (np.abs(a - (w / 2.0 + 3)) < 1))
    index = np.where(knobs, KNOB, index)
    return np.where(b < 2, WOOD_LINE, index)


def stand_side(ctx):
    b = np.floor(ctx.b)
    index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(b.shape, ctx.base)
    return np.where(b < 2, WOOD_LINE, index)


FISH = ((0.30, 9, FISH_ORANGE, 1), (0.62, 13, FISH_YELLOW, -1), (0.80, 6, FISH_RED, 1))


def tank_side(ctx):
    """Una cara del tanque; a = px de izquierda a derecha, b = alto desde la base del tanque."""
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    w = np.floor(ctx.w)
    h = np.floor(ctx.h)
    index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(a.shape, ctx.base)
    index = np.where(b < h * 0.45, WATER_DEEP, index)
    # Arena con lomas y piedras.
    sand_top = 3 + np.round(1.2 * np.sin(a / 7.0))
    index = np.where(b < sand_top, np.where(np.mod(a + b, 5) == 0, SAND_DARK, SAND), index)
    stone = ((a - w * 0.7) ** 2 / 9.0 + (b - 3) ** 2 / 4.0) <= 1.0
    index = np.where(stone, STONE, index)
    # Plantas: tallos ondulados de 2 px.
    for x0, top in ((w * 0.14, h * 0.75), (w * 0.22, h * 0.55), (w * 0.88, h * 0.65)):
        sway = np.round(1.5 * np.sin(b / 3.0 + x0))
        stem = (np.abs(a - x0 - sway) < 1.0) & (b >= 2) & (b < top)
        index = np.where(stem, np.where(np.mod(b, 4) < 2, WEED_LIGHT, WEED), index)
    # Peces de 5×3 con cola y ojo.
    for fx, fb, color, facing in FISH:
        cx = np.floor(w * fx)
        body = (np.abs(a - cx) <= 2) & (np.abs(b - fb) <= 1) & ~((np.abs(a - cx) == 2) & (np.abs(b - fb) == 1))
        tail = (a == cx - 3 * facing) & (np.abs(b - fb) <= 1)
        eye = (a == cx + facing) & (b == fb)
        index = np.where(body | tail, color, index)
        index = np.where(eye, FISH_EYE, index)
    # Burbujas y reflejo en diagonal.
    bubbles = (np.abs(a - w * 0.5) < 1) & (np.mod(b, 5) == 0) & (b > h * 0.4)
    index = np.where(bubbles, WATER_SHINE, index)
    shine = (np.mod(a - b, 23) == 0) & (b > 4)
    index = np.where(shine, WATER_SHINE, index)
    # Filo negro de 1 px arriba y abajo.
    return np.where((b >= h - 2) | (b < 1), pal.OUTLINE, index)


def tank_top(ctx):
    """Tapa: superficie del agua con brillos y borde negro."""
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    w = np.floor(ctx.w)
    h = np.floor(ctx.h)
    index = np.full(a.shape, pal.LIGHT)
    index = np.where(np.mod(a + 3 * b, 11) < 2, WATER_SHINE, index)
    frame = (a < 2) | (a >= w - 2) | (b < 2) | (b >= h - 2)
    return np.where(frame, pal.OUTLINE, index)


def aquarium(rotation):
    w, d = AQUARIUM_ITEM["size"]
    c = iso.Canvas.furniture((w, d), AQUARIUM_ITEM["height"], rotation)
    top = TANK_TOP
    c.box(0, w, 0, d, 0, STAND_TOP, WOOD, tex={iso.FRONT: stand_front, "sides": stand_side}, name="stand",
          flat=False)
    c.box(TANK_INSET, w - TANK_INSET, TANK_INSET * 2, d - TANK_INSET * 2, STAND_TOP, top, WATER,
          tex={"sides": tank_side, "top": tank_top}, name="tank", flat=False)
    return c


def aquarium_shadow_shapes():
    return [("bar", 0.25, 0.5, 1.75, 0.5, 0.42, 0, TANK_TOP)]


# ---------------------------------------------------------------------------- principal

def contact(out_dir, items):
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    sheet.contact_sheet(items, columns=4, scale=3).save(os.path.join(folder, "decor.png"))


def build(out_dir):
    files = []
    items = []
    for name, scale in (("floor_lamp", 1.0), ("floor_lamp_q", 0.6)):
        c = iso.Canvas.furniture((1, 1), LAMP_ITEM["height"])
        lamp(c, scale)
        c.finish()
        files.append(iso.save(c, out_dir, name, height=LAMP_ITEM["height"], small=True,
                              final_size=scale < 1.0, curved=True))
        files.append(_shadow.save_shadow(c, out_dir, name + "_shadow", lamp_shadow_shapes(scale)))
        items.append((name, sheet.on_background(c.image, scale=1)))
    c = rug()
    c.finish()
    files.append(iso.save(c, out_dir, "rug", height=RUG_ITEM["height"], walkable=True))
    items.append(("rug", sheet.on_background(c.image, scale=1)))
    for rotation in range(4):
        c = aquarium(rotation)
        c.finish()
        name = "aquarium_r%d" % rotation
        files.append(iso.save(c, out_dir, name, height=AQUARIUM_ITEM["height"]))
        files.append(_shadow.save_shadow(c, out_dir, name + "_shadow", aquarium_shadow_shapes()))
        items.append((name, sheet.on_background(c.image, scale=1)))
    contact(out_dir, items)
    return files
