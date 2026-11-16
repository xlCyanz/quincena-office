# Muebles de la Sala de descanso (estilo de tools/sprites/STYLE.md):
#
#   sofa_r0..r3              2×1: sofá lila de dos cojines, brazos rectos y patas de madera (frente a −y)
#   fridge_r0..r3            nevera blanca de dos puertas (congelador arriba) con tiradores
#   microwave_r0..r3         microondas negro con ventana oscura y panel, sobre un mueble bajo de cocina
#   coffee_maker_r0..r3      cafetera negra con jarra de vidrio, sobre el mismo mueble bajo
#   vending_machine_r0..r3   máquina expendedora roja con vitrina de golosinas, panel y bandeja
#   ping_pong_r0..r3         2×2: mesa verde con líneas blancas, red al medio y dos paletas
#   dining_table_r0..r3      2×1: mesa de comedor de madera con un banco a cada lado (4 asientos)
#   <cada uno>_shadow        sombra en el piso, aparte
#   _sheets/break_room.png   hoja de contacto
import numpy as np

import iso
import palette as pal
from pieces._kit import Saver, g, grid, inside, plain, sunken

ITEMS = iso.load_json("data/furniture.json")["items"]
SOFA_ITEM = ITEMS["sofa"]
FRIDGE_ITEM = ITEMS["fridge"]
MICRO_ITEM = ITEMS["microwave"]
COFFEE_ITEM = ITEMS["coffee_maker"]
VENDING_ITEM = ITEMS["vending_machine"]
PONG_ITEM = ITEMS["ping_pong"]
DINING_ITEM = ITEMS["dining_table"]

PLASTIC = pal.PLASTIC_BLACK
SOFA = pal.style_ramp("8f6cbf", outline="2a1640", name="lounge_sofa")
SOFA_FRAME = pal.style_ramp("75539f", outline="2a1640", name="lounge_sofa_frame")
LEG_WOOD = pal.style("wood_orange", name="lounge_legs")
WHITE = pal.style_ramp("f4f6f6", side="dde2e2", shadow="c4cbcc", outline="3d3b44", name="fridge_white")
WHITE_LINE = WHITE.add("8f989c")
WHITE_HANDLE = WHITE.add("5f676b")
CABINET = pal.style("wood_orange", name="kitchen_cabinet")
CABINET_LINE = CABINET.add("5b2a10")
CABINET_HANDLE = CABINET.add("eef1f2")
WORKTOP = pal.style_ramp("d9d4ca", outline="3d3b44", name="kitchen_worktop")
APPLIANCE = pal.style_ramp("3b3f45", outline="0e0f10", name="appliance_black")
GLASS_DARK = APPLIANCE.add("1b2026")
GLASS_SHINE = APPLIANCE.add("5a6874")
KEYPAD = APPLIANCE.add("8c96a0")
DIGITS = APPLIANCE.add("6fe08a")
STEEL = APPLIANCE.add("c6cdd2")
CARAFE = pal.style_ramp("a9d4e6", outline="1b3a52", name="coffee_carafe")
COFFEE = CARAFE.add("4a2410")
VENDING = pal.style_ramp("d23f3a", outline="3a0c0a", name="vending_red")
VENDING_GLASS = VENDING.add("27313a")
VENDING_SHELF = VENDING.add("8c96a0")
VENDING_PANEL = VENDING.add("e8e9ea")
VENDING_SLOT = VENDING.add("15191d")
V_SHINE = VENDING.add("5a6874")
V_DIGITS = VENDING.add("6fe08a")
V_KEYS = VENDING.add("8c96a0")
SNACKS = [VENDING.add(h) for h in ("f0b030", "6fe08a", "4f9bd0", "f2f2f2", "e05ae0")]
TABLE_GREEN = pal.style_ramp("2f8a52", outline="0e2a18", name="pong_green")
TABLE_LINE = TABLE_GREEN.add("f2f6f2")
NET = pal.style_ramp("eef1f2", outline="2f3437", name="pong_net")
PADDLE = pal.style_ramp("d8434a", outline="3a0c0a", name="pong_paddle")
METAL_DARK = pal.style_ramp("4a4f55", outline="141619", name="pong_legs")
DINING = pal.style("wood_orange", name="dining_wood")


# ---------------------------------------------------------------------------- sofá

S_LEG = 3
S_BASE = 10
S_SEAT = 17
S_ARM = 24
S_BACK = 32
S_ARM_W = 12 / 64.0


def sofa(rotation):
    w, d = SOFA_ITEM["size"]
    c = iso.Canvas.furniture((w, d), SOFA_ITEM["height"], rotation)
    legs = None
    for x in (6 / 64.0, w - 10 / 64.0):
        for y in (10 / 64.0, 52 / 64.0):
            pid = c.box(x, x + 4 / 64.0, y, y + 4 / 64.0, 0, S_LEG, LEG_WOOD, name="legs" if legs is None else None,
                        part=legs)
            legs = pid if legs is None else legs
    c.soft_box(4 / 64.0, w - 4 / 64.0, 8 / 64.0, 60 / 64.0, S_LEG, S_BASE, 2, SOFA_FRAME, name="base")
    inner = (4 / 64.0 + S_ARM_W, w - 4 / 64.0 - S_ARM_W)
    c.soft_box(inner[0], inner[1], 46 / 64.0, 60 / 64.0, S_BASE - 2, S_BACK, 4, SOFA, name="back_frame")
    half = (inner[1] - inner[0]) / 2.0
    for k in range(2):
        x0 = g(inner[0] + k * half)
        x1 = g(inner[0] + (k + 1) * half) - 1 / 64.0
        c.soft_box(x0, x1, 9 / 64.0, 47 / 64.0, S_BASE - 1, S_SEAT, 4, SOFA, name="seat_%d" % k)
    for k, x in enumerate((4 / 64.0, w - 4 / 64.0 - S_ARM_W)):
        c.soft_box(x, x + S_ARM_W, 8 / 64.0, 60 / 64.0, S_BASE - 2, S_ARM, 3, SOFA_FRAME, name="arm_%d" % k)
    return c


def sofa_shadow_shapes():
    return [("bar", 0.3, 0.52, 1.7, 0.52, 0.42, 0, S_BACK)]


# ---------------------------------------------------------------------------- nevera

FRIDGE_TOP = 80


def fridge_front(ctx):
    """Dos puertas (el congelador arriba), tiradores verticales a la derecha y rejilla abajo."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    split = np.floor(h * 0.66)
    index = np.where((b == split) | (b == split + 1), WHITE_LINE, index)
    index = np.where(inside(a, b, w - 6, w - 4, split + 5, split + 16), WHITE_HANDLE, index)
    index = np.where(inside(a, b, w - 6, w - 4, split - 22, split - 4), WHITE_HANDLE, index)
    index = np.where(inside(a, b, w - 4, w - 3, split + 5, split + 16) |
                     inside(a, b, w - 4, w - 3, split - 22, split - 4), pal.LIGHT, index)
    grille = inside(a, b, 3, w - 3, 2, 6) & (np.mod(a, 2) == 0)
    index = np.where(grille, WHITE_LINE, index)
    return np.where(b < 2, pal.DEEP, index)


def fridge(rotation):
    c = iso.Canvas.furniture(FRIDGE_ITEM["size"], FRIDGE_ITEM["height"], rotation)
    c.box(g(0.18), g(0.82), g(0.2), g(0.8), 0, FRIDGE_TOP, WHITE, tex={iso.FRONT: fridge_front}, name="body",
          flat=False)
    return c


def fridge_shadow_shapes():
    return [("bar", 0.5, 0.3, 0.5, 0.7, 0.33, 0, FRIDGE_TOP)]


# ---------------------------------------------------------------------------- mueble bajo de cocina

CAB_TOP = 22
WORK_TOP = 25


def cabinet_front(ctx):
    """Dos puertas con su tirador junto al medio."""
    a, b, w, h = grid(ctx)
    mid = np.floor(w / 2.0)
    index = sunken(plain(ctx), a, b, 2, mid - 1, 3, h - 2, CABINET_LINE, pal.LIGHT)
    index = sunken(index, a, b, mid + 1, w - 2, 3, h - 2, CABINET_LINE, pal.LIGHT)
    for a0 in (mid - 4, mid + 3):
        index = np.where(inside(a, b, a0, a0 + 1, h - 9, h - 5), CABINET_HANDLE, index)
    return np.where(b < 2, CABINET_LINE, index)


def kitchen_cabinet(c):
    c.box(g(0.14), g(0.86), g(0.18), g(0.82), 0, CAB_TOP, CABINET, tex={iso.FRONT: cabinet_front}, name="cabinet",
          flat=False)
    c.box(g(0.12), g(0.88), g(0.16), g(0.84), CAB_TOP, WORK_TOP, WORKTOP, name="worktop")


# ---------------------------------------------------------------------------- microondas

MICRO_TOP = WORK_TOP + 14


def micro_front(ctx):
    """Ventana oscura con reflejo a la izquierda y panel de botones a la derecha."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    pw = np.floor(w * 0.3)
    win = inside(a, b, 2, w - pw - 2, 2, h - 2)
    index = np.where(win, GLASS_DARK, index)
    index = np.where(win & (np.mod(a + b, 7) == 0) & (a < w * 0.4), GLASS_SHINE, index)
    index = np.where(inside(a, b, w - pw, w - 2, h - 5, h - 3), DIGITS, index)
    keys = inside(a, b, w - pw, w - 2, 3, h - 7) & (np.mod(a, 3) != 2) & (np.mod(b, 2) == 0)
    index = np.where(keys, KEYPAD, index)
    return np.where(inside(a, b, w - pw - 2, w - pw - 1, 2, h - 2), STEEL, index)


def microwave(rotation):
    c = iso.Canvas.furniture(MICRO_ITEM["size"], MICRO_ITEM["height"], rotation)
    kitchen_cabinet(c)
    c.box(g(0.2), g(0.8), g(0.26), g(0.7), WORK_TOP, MICRO_TOP, APPLIANCE, tex={iso.FRONT: micro_front},
          name="microwave", flat=False)
    return c


# ---------------------------------------------------------------------------- cafetera

def coffee_maker(rotation):
    """Cuerpo negro en C (base, columna y cabezal) con la jarra en el hueco."""
    c = iso.Canvas.furniture(COFFEE_ITEM["size"], COFFEE_ITEM["height"], rotation)
    kitchen_cabinet(c)
    x0, x1 = g(0.36), g(0.64)
    c.box(x0, x1, g(0.3), g(0.62), WORK_TOP, WORK_TOP + 3, APPLIANCE, name="plate")
    c.box(x0, x1, g(0.5), g(0.66), WORK_TOP + 3, WORK_TOP + 24, APPLIANCE, name="column")
    c.box(x0, x1, g(0.3), g(0.5), WORK_TOP + 18, WORK_TOP + 24, APPLIANCE, name="head")
    c.cylinder(0.5, 0.4, 0.085, WORK_TOP + 3, WORK_TOP + 15, CARAFE, radius_top=0.07,
               tex={"side": lambda ctx: np.where(ctx.b < 6, COFFEE, plain(ctx))}, name="carafe")
    c.box(g(0.47), g(0.53), g(0.3), g(0.32), WORK_TOP + 13, WORK_TOP + 15, APPLIANCE, name="lid")
    return c


def counter_shadow_shapes():
    return [("bar", 0.5, 0.3, 0.5, 0.7, 0.37, 0, WORK_TOP)]


# ---------------------------------------------------------------------------- máquina expendedora

VEND_TOP = 80


def vending_front(ctx):
    """Vitrina con cuatro estantes de golosinas, panel claro a la derecha y bandeja abajo."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    pw = np.floor(w * 0.26)
    g0, g1 = np.floor(h * 0.28), h - 5
    glass = inside(a, b, 3, w - pw - 2, g0, g1)
    index = np.where(glass, VENDING_GLASS, index)
    rows = 4
    step = (g1 - g0) / float(rows)
    for k in range(rows):
        s0 = np.floor(g0 + k * step)
        index = np.where(glass & (b == s0 + 1), VENDING_SHELF, index)
        snack = glass & (b >= s0 + 2) & (b < s0 + step - 1) & (np.mod(a - 4, 5) < 3)
        color = SNACKS[0]
        for j, col in enumerate(SNACKS):
            color = np.where(np.mod(np.floor((a - 4) / 5.0) + k, len(SNACKS)) == j, col, color)
        index = np.where(snack, color, index)
    shine = glass & (np.mod(a - b, 13) == 0)
    index = np.where(shine, V_SHINE, index)
    panel = inside(a, b, w - pw, w - 3, g0, g1)
    index = np.where(panel, VENDING_PANEL, index)
    index = np.where(inside(a, b, w - pw + 2, w - 5, g1 - 6, g1 - 2), V_DIGITS, index)
    index = np.where(panel & inside(a, b, w - pw + 2, w - 5, g0 + 8, g1 - 9) & (np.mod(b, 3) == 0) &
                     (np.mod(a, 3) != 0), V_KEYS, index)
    index = np.where(inside(a, b, w - pw + 3, w - 6, g0 + 3, g0 + 5), VENDING_SLOT, index)  # monedas
    index = np.where(inside(a, b, 5, w - pw - 4, 5, g0 - 5), VENDING_SLOT, index)  # bandeja
    return np.where(b < 2, pal.DEEP, index)


def vending_machine(rotation):
    c = iso.Canvas.furniture(VENDING_ITEM["size"], VENDING_ITEM["height"], rotation)
    c.box(g(0.16), g(0.84), g(0.22), g(0.8), 0, VEND_TOP, VENDING, tex={iso.FRONT: vending_front}, name="body",
          flat=False)
    return c


def vending_shadow_shapes():
    return [("bar", 0.5, 0.3, 0.5, 0.72, 0.35, 0, VEND_TOP)]


# ---------------------------------------------------------------------------- ping pong

PONG_TOP = 24
PONG_X = (0.1, 1.9)
PONG_Y = (0.45, 1.55)


def pong_top(ctx):
    """Líneas blancas del borde y del medio."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    edge = (a < 2) | (a >= w - 2) | (b < 1) | (b >= h - 1)
    mid = (b == np.floor(h / 2.0))
    return np.where(edge | mid, TABLE_LINE, index)


def ping_pong(rotation):
    c = iso.Canvas.furniture(PONG_ITEM["size"], PONG_ITEM["height"], rotation)
    legs = None
    for x in (0.25, 1.65):
        for y in (0.55, 1.35):
            pid = c.box(g(x), g(x + 0.08), g(y), g(y + 0.08), 0, PONG_TOP - 2, METAL_DARK,
                        name="legs" if legs is None else None, part=legs)
            legs = pid if legs is None else legs
    c.box(g(PONG_X[0]), g(PONG_X[1]), g(PONG_Y[0]), g(PONG_Y[1]), PONG_TOP - 2, PONG_TOP, TABLE_GREEN,
          tex={"top": pong_top}, name="table", flat=False)
    # Red al medio a lo largo de x.
    c.box(1.0 - 1 / 64.0, 1.0 + 1 / 64.0, g(PONG_Y[0] - 0.03), g(PONG_Y[1] + 0.03), PONG_TOP, PONG_TOP + 6, NET,
          name="net")
    # Una paleta en cada mitad.
    c.cylinder(0.55, 0.8, 0.07, PONG_TOP, PONG_TOP + 1, PADDLE, name="paddle_a")
    c.cylinder(1.5, 1.25, 0.07, PONG_TOP, PONG_TOP + 1, PADDLE, name="paddle_b")
    return c


def pong_shadow_shapes():
    return [("bar", 0.4, 1.0, 1.6, 1.0, 0.5, 0, PONG_TOP)]


# ---------------------------------------------------------------------------- comedor

DINE_TOP = 28
BENCH_TOP = 16


def dining_table(rotation):
    w, d = DINING_ITEM["size"]
    c = iso.Canvas.furniture((w, d), DINING_ITEM["height"], rotation)
    legs = None
    for x in (0.18, w - 0.26):
        for y in (0.36, 0.56):
            pid = c.box(g(x), g(x + 0.08), g(y), g(y + 0.08), 0, DINE_TOP - 4, DINING,
                        name="legs" if legs is None else None, part=legs)
            legs = pid if legs is None else legs
    c.box(g(0.1), g(w - 0.1), g(0.3), g(0.7), DINE_TOP - 4, DINE_TOP, DINING, name="top")
    for k, (y0, y1) in enumerate(((0.04, 0.2), (0.8, 0.96))):
        bl = None
        for x in (0.26, w - 0.32):
            pid = c.box(g(x), g(x + 0.06), g(y0 + 0.03), g(y1 - 0.03), 0, BENCH_TOP - 3, DINING,
                        name="bench_legs_%d" % k if bl is None else None, part=bl)
            bl = pid if bl is None else bl
        c.box(g(0.2), g(w - 0.2), g(y0), g(y1), BENCH_TOP - 3, BENCH_TOP, DINING, name="bench_%d" % k)
    return c


def dining_shadow_shapes():
    return [("bar", 0.3, 0.5, 1.7, 0.5, 0.45, 0, DINE_TOP)]


# ---------------------------------------------------------------------------- principal

def build(out_dir):
    s = Saver(out_dir)
    s.rotations(sofa, "sofa", sofa_shadow_shapes(), height=SOFA_ITEM["height"])
    s.rotations(fridge, "fridge", fridge_shadow_shapes(), height=FRIDGE_ITEM["height"])
    s.rotations(microwave, "microwave", counter_shadow_shapes(), height=MICRO_ITEM["height"])
    s.rotations(coffee_maker, "coffee_maker", counter_shadow_shapes(), height=COFFEE_ITEM["height"], curved=True)
    s.rotations(vending_machine, "vending_machine", vending_shadow_shapes(), height=VENDING_ITEM["height"])
    s.rotations(ping_pong, "ping_pong", pong_shadow_shapes(), height=PONG_ITEM["height"], curved=True)
    s.rotations(dining_table, "dining_table", dining_shadow_shapes(), height=DINING_ITEM["height"])
    return s.sheet("break_room")
