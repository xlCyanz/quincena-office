# Muebles de la Recepción (estilo de tools/sprites/STYLE.md):
#
#   reception_counter_r0..r3      2×1: mostrador; mesa de trabajo del lado de la recepcionista (frente, −y
#                                 con rotación 0) y panel alto con mesón crema y timbre del lado del cliente
#   waiting_sofa_r0..r3           2×1: sofá de espera rojo mullido (se sienta mirando a −y con rotación 0)
#   water_dispenser_r0..r3        mueble chico: gabinete blanco y bidón celeste (a tamaño de casilla;
#                                 el juego lo achica al 60 %)
#   water_dispenser_q_r0..r3      el mismo ya al 60 %
#   trash_can, trash_can_q        zafacón gris con bolsa negra (simétrico; _q al 60 %)
#   <cada uno>_shadow             sombra en el piso, aparte
#   _sheets/reception.png         hoja de contacto
#
# En data/furniture.json: reception_counter (height 24), waiting_sofa (12), water_dispenser (34), trash_can (10).
import os

import numpy as np

import iso
import palette as pal
import sheet
from pieces import chair_plant

ITEMS = iso.load_json("data/furniture.json")["items"]
COUNTER_ITEM = ITEMS["reception_counter"]
SOFA_ITEM = ITEMS["waiting_sofa"]
WATER_ITEM = ITEMS["water_dispenser"]
TRASH_ITEM = ITEMS["trash_can"]

# ---------------------------------------------------------------------------- rampas

WOOD = pal.style("wood_orange", name="reception_counter")
WOOD_LINE = WOOD.add("5b2a10")  # ranuras entre listones
COUNTER_TOP = pal.style_ramp("ece5d6", outline="4a3f30", name="counter_top")  # mesón crema
BELL = pal.style_ramp("e0b84a", outline="4e3510", name="bell")  # timbre dorado
PLASTIC = pal.PLASTIC_BLACK
SOFA = pal.style("upholstery_red", name="waiting_sofa")
SOFA_FRAME = pal.style_ramp("a8323a", outline="450e22", name="waiting_sofa_frame")  # base, brazos y marco
SOFA_BUTTON = SOFA.add("6d120a")
CABINET = pal.style_ramp("f4f6f6", side="dde2e2", shadow="c4cbcc", outline="3d3b44", name="water_cabinet")  # gabinete blanco puro
TAP_RED = CABINET.add("d8434a")
TAP_BLUE = CABINET.add("3d90c0")
PANEL = CABINET.add("3a3d44")  # panel oscuro de la llave
SLIT = CABINET.add("a9b1b4")  # rejillas
BOTTLE = pal.style_ramp("bfe6f5", side="a3d8ef", shadow="8cc8e6", outline="1b3a52", name="water_bottle")
BOTTLE_SHINE = BOTTLE.add("ffffff")
BOTTLE_RING = BOTTLE.add("4f9bd0")  # aros del bidón
BOTTLE_RING_DARK = BOTTLE.add("2f6fa8")
BOTTLE_DEEP = BOTTLE.add("7dbde3")  # el agua de abajo, más azul
BIN = pal.style_ramp("969ca0", outline="1c1f22", name="trash_can")  # gris de metal
BIN_RIM = BIN.add("a9aeb1")  # aro claro de arriba
BIN_BAND = BIN.add("6c7276")
BAG = pal.style_ramp("2e3134", outline="0e0f10", name="trash_bag")  # bolsa negra
PEDESTAL = pal.style_ramp("c3c8ca", side="a9afb2", shadow="8f969a", outline="2f3437", name="counter_pedestal")
PEDESTAL_LINE = PEDESTAL.add("6f777b")
PEDESTAL_HANDLE = PEDESTAL.add("eef1f2")
TRIM = pal.style_ramp("b9bfc2", outline="2f3437", name="counter_trim")  # perfiles de aluminio


def g(v):
    """Redondea a la rejilla de 1/64 de casilla (aristas 2:1)."""
    return round(v * 64.0) / 64.0


def plain(ctx):
    return np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(np.shape(ctx.a), ctx.base)


# ---------------------------------------------------------------------------- mostrador

DESK_Y = (0.0, 35 / 64.0)  # mesa de trabajo, del lado de la recepcionista (frente, −y)
DESK_TOP = 34  # alto de la mesa de trabajo (px de sprite)
PANEL_Y = (35 / 64.0, 1.0)  # panel alto, del lado del cliente
PANEL_TOP = 45
LEDGE = (31 / 64.0, 1.0)  # mesón que sobresale hacia adentro, de PANEL_TOP a COUNTER_H
COUNTER_H = 48  # el `height` del juego (24) × 2


def panel_back(ctx):
    """Panel del cliente: madera lisa, ranura bajo el mesón y zócalo oscuro."""
    b = np.floor(ctx.b)
    h = np.floor(ctx.h)
    index = plain(ctx)
    index = np.where(b == h - 4, WOOD_LINE, index)
    return np.where(b < 3, WOOD_LINE, index)


def panel_side(ctx):
    b = np.floor(ctx.b)
    index = plain(ctx)
    return np.where(b < 3, WOOD_LINE, index)


def ledge_top(ctx):
    """Mesón con un filo claro en el canto de adentro."""
    b = np.floor(ctx.b)
    index = plain(ctx)
    return np.where(b < 1, pal.LIGHT, index)


PED_W = 22 / 64.0  # cajoneras de metal a cada lado del hueco
DESK_SLAB = 4  # tablero de madera de la mesa de trabajo
TRIM_W = 3 / 64.0  # postes de aluminio en las esquinas del panel


def pedestal_front(ctx):
    """Cajonera de metal gris de tres cajones."""
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    w = np.floor(ctx.w)
    h = np.floor(ctx.h)
    index = plain(ctx)
    step = np.floor((h - 3) / 3.0)
    lines = (np.mod(b - 2, step) == 0) & (b >= 2) | (a == 1) | (a == w - 2)
    index = np.where(lines & (b >= 2), PEDESTAL_LINE, index)
    handle = (np.mod(b - 2, step) == step - 3) & (np.abs(a + 0.5 - w / 2.0) < 3)
    index = np.where(handle, PEDESTAL_HANDLE, index)
    return np.where(b < 2, pal.DEEP, index)


def reception_counter(rotation):
    w, d = COUNTER_ITEM["size"]
    c = iso.Canvas.furniture((w, d), COUNTER_ITEM["height"], rotation)
    y0, y1 = 3 / 64.0, DESK_Y[1]
    # Mesa de trabajo: dos cajoneras y tablero de madera.
    ped = None
    for x0 in (4 / 64.0, w - 4 / 64.0 - PED_W):
        pid = c.box(x0, x0 + PED_W, y0 + 2 / 64.0, y1, 0, DESK_TOP - DESK_SLAB, PEDESTAL,
                    tex={iso.FRONT: pedestal_front}, name="pedestals" if ped is None else None, part=ped, flat=False)
        ped = pid if ped is None else ped
    c.box(2 / 64.0, w - 2 / 64.0, y0, y1, DESK_TOP - DESK_SLAB, DESK_TOP, WOOD, name="desk_top")
    # Panel alto del lado del cliente.
    c.box(1 / 64.0, w - 1 / 64.0, PANEL_Y[0] + 1 / 64.0, PANEL_Y[1] - 1 / 64.0, 0, PANEL_TOP, WOOD,
          tex={iso.BACK: panel_back, "sides": panel_side}, name="panel", flat=False)
    # Postes de aluminio en las esquinas, 1 px afuera de la madera.
    trims = None
    for x0 in (0.0, w - TRIM_W):
        for yy in (PANEL_Y[0], PANEL_Y[1] - TRIM_W):
            pid = c.box(x0, x0 + TRIM_W, yy, yy + TRIM_W, 0, PANEL_TOP, TRIM,
                        name="trims" if trims is None else None, part=trims)
            trims = pid if trims is None else trims
    c.box(0, w, LEDGE[0], LEDGE[1], PANEL_TOP, COUNTER_H, COUNTER_TOP, tex={"top": ledge_top},
          name="ledge", flat=False)
    # Timbre cerca de un extremo.
    c.cylinder(1.62, 0.84, 0.05, COUNTER_H, COUNTER_H + 1, PLASTIC, name="bell_base")
    c.cylinder(1.62, 0.84, 0.04, COUNTER_H + 1, COUNTER_H + 4, BELL, radius_top=0.015, name="bell")
    return c


def counter_shadow_shapes():
    return [("bar", 0.25, 0.5, 1.75, 0.5, 0.45, 0, COUNTER_H)]


# ---------------------------------------------------------------------------- sofá de espera

SOFA_LEG = 2  # patitas negras bajo el faldón
SOFA_BASE = 12  # faldón
SEAT_TOP = 19  # cojines del asiento
ARM_TOP = 33  # brazos (más el rollo de arriba)
ARM_ROLL = 5  # radio del rollo del brazo (px)
BACK_FRAME = 30  # marco del respaldo, detrás de los cojines
BACK_TOP = 38  # cojines del respaldo (más que el `height` del juego, 24, para que se lea como sofá)
BACK_Y = (46 / 64.0, 60 / 64.0)  # cojines del respaldo
FRAME_Y = (56 / 64.0, 62 / 64.0)  # marco del respaldo
ARM_W = 16 / 64.0
SEATS = 3


def waiting_sofa(rotation):
    w, d = SOFA_ITEM["size"]
    c = iso.Canvas.furniture((w, d), SOFA_ITEM["height"], rotation)
    legs = None
    for x in (6 / 64.0, w - 10 / 64.0):
        for y in (8 / 64.0, 54 / 64.0):
            pid = c.box(x, x + 4 / 64.0, y, y + 4 / 64.0, 0, SOFA_LEG, PLASTIC, name="legs" if legs is None else None,
                        part=legs)
            legs = pid if legs is None else legs
    c.soft_box(3 / 64.0, w - 3 / 64.0, 5 / 64.0, 62 / 64.0, SOFA_LEG, SOFA_BASE, 2, SOFA_FRAME, name="base")
    inner = (3 / 64.0 + ARM_W, w - 3 / 64.0 - ARM_W)  # entre los brazos, sin meterse en ellos
    c.soft_box(inner[0], inner[1], FRAME_Y[0], FRAME_Y[1], SOFA_BASE - 2, BACK_FRAME, 3, SOFA_FRAME, name="frame")
    step = (inner[1] - inner[0]) / SEATS
    for k in range(SEATS):
        x0 = g(inner[0] + k * step)
        x1 = g(inner[0] + (k + 1) * step) - 1 / 64.0
        c.soft_box(x0, x1, 6 / 64.0, BACK_Y[0] + 2 / 64.0, SOFA_BASE - 1, SEAT_TOP, 4, SOFA, name="seat_%d" % k)
        c.soft_box(x0, x1, BACK_Y[0], BACK_Y[1], SEAT_TOP - 3, BACK_TOP, 5, SOFA, name="back_%d" % k)
        # Botón en el medio del cojín del respaldo.
        mid = (x0 + x1) / 2.0
        c.box(g(mid) - 1 / 64.0, g(mid) + 1 / 64.0, BACK_Y[0] - 1 / 64.0, BACK_Y[0], BACK_TOP - 9, BACK_TOP - 7,
              SOFA_FRAME, name="button_%d" % k, outline=False)
    for k, x in enumerate((3 / 64.0, w - 3 / 64.0 - ARM_W)):
        c.soft_box(x, x + ARM_W, 5 / 64.0, 62 / 64.0, SOFA_BASE - 2, ARM_TOP - ARM_ROLL, 3, SOFA_FRAME,
                   name="arm_%d" % k)
        cx = x + ARM_W / 2.0
        c.capsule((cx, 8 / 64.0, ARM_TOP - ARM_ROLL), (cx, 59 / 64.0, ARM_TOP - ARM_ROLL), ARM_ROLL + 2, SOFA,
                  name="roll_%d" % k)
    return c


def sofa_shadow_shapes():
    return [("bar", 0.3, 0.52, 1.7, 0.52, 0.44, 0, BACK_TOP)]


# ---------------------------------------------------------------------------- dispensador de agua

CAB_TOP = 34  # gabinete
BOTTLE_TOP = 68  # el `height` del juego (34) × 2
CAB_HALF = 12 / 64.0
BOTTLE_R = 0.2


def cabinet_front(ctx, s):
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    w = np.floor(ctx.w)
    h = np.floor(ctx.h)
    index = plain(ctx)
    # Panel oscuro con la llave roja y la azul.
    p0, p1 = np.floor(h * 0.62), np.floor(h * 0.9)
    panel = (b >= p0) & (b < p1) & (a >= 2) & (a < w - 2)
    index = np.where(panel, PANEL, index)
    index = np.where(panel & (np.mod(b - p0, 3) == 1) & (a >= w * 0.55), SLIT, index)
    tap = max(1.0, round(2 * s))
    for x0, color in ((np.floor(w * 0.22), TAP_RED), (np.floor(w * 0.22) + tap + 1, TAP_BLUE)):
        index = np.where((a >= x0) & (a < x0 + tap) & (b >= p0) & (b < p0 + max(2, round(3 * s))), color, index)
    # Rejillas: rayas cortas cada 2 px.
    grille = (b >= np.floor(h * 0.12)) & (b < np.floor(h * 0.45)) & (a >= w * 0.25) & (a < w * 0.75) & \
             (np.mod(b, 2) == 0)
    index = np.where(grille, SLIT, index)
    return np.where(b < 1, pal.RIGHT, index)


def bottle_side(ctx):
    b = np.floor(ctx.b)
    h = np.floor(ctx.h) if np.ndim(ctx.h) else ctx.h
    index = plain(ctx)
    index = np.where(b < h * 0.35, BOTTLE_DEEP, index)
    rings = None
    for f in (0.22, 0.5, 0.78):
        r0 = np.floor(h * f)
        ring = (b >= r0) & (b < r0 + 2)
        index = np.where(ring, np.where(b == r0, BOTTLE_RING_DARK, BOTTLE_RING), index)
    # Brillos: franja del lado de la luz y manchitas.
    shine = (ctx.t > -0.68) & (ctx.t < -0.56) & (b > 2) & (b < h - 3) & (np.mod(b, 9) != 4)
    index = np.where(shine, BOTTLE_SHINE, index)
    dots = (np.mod(np.floor(ctx.a) * 7 + b * 5, 41) == 0) & (ctx.t < 0.3) & (b > h * 0.35)
    return np.where(dots, BOTTLE_SHINE, index)


def bottle_cap(ctx):
    """Tapa: cuello del bidón y un brillo."""
    index = plain(ctx)
    index = np.where((ctx.t > 0.32) & (ctx.t < 0.5), BOTTLE_RING, index)
    index = np.where(ctx.t <= 0.18, BOTTLE_RING_DARK, index)
    return np.where((ctx.t > 0.7) & (ctx.t < 0.85), BOTTLE_SHINE, index)


def water_dispenser(rotation, scale=1.0):
    s = scale
    c = iso.Canvas.furniture((1, 1), WATER_ITEM["height"], rotation)
    half = g(CAB_HALF * s)
    cab_top = round(CAB_TOP * s)
    c.box(0.5 - half, 0.5 + half, 0.5 - half, 0.5 + half, 0, cab_top, CABINET,
          tex={iso.FRONT: lambda ctx: cabinet_front(ctx, s)}, name="cabinet", flat=False)
    c.cylinder(0.5, 0.5, BOTTLE_R * s, cab_top, round(BOTTLE_TOP * s), BOTTLE,
               tex={"side": bottle_side, "cap": bottle_cap}, name="bottle")
    return c


def water_shadow_shapes(scale=1.0):
    return [("disc", 0.5, 0.5, 0.21 * scale, 0, round(BOTTLE_TOP * scale))]


# ---------------------------------------------------------------------------- zafacón

BIN_TOP = 26  # más que el `height` del juego (10 → 20 px) para que se lea como cubo


def bin_side(ctx):
    """Costado de metal con banda oscura abajo y aro claro arriba."""
    b = np.floor(ctx.b)
    h = np.floor(ctx.h) if np.ndim(ctx.h) else ctx.h
    index = plain(ctx)
    index = np.where((b >= 2) & (b < 4), BIN_BAND, index)
    return np.where(b >= h - 2, BIN_RIM, index)


def trash_can(scale=1.0):
    """Cubo que se angosta abajo, con la bolsa doblada sobre el borde."""
    s = scale
    c = iso.Canvas.furniture((1, 1), TRASH_ITEM["height"])
    top = round(BIN_TOP * s)
    c.cylinder(0.5, 0.5, 0.115 * s, 0, top, BIN, radius_top=0.15 * s, open_top=True, tex={"side": bin_side},
               name="bin")
    # Bolsa: fondo adentro y doblez sobre el aro.
    c.cylinder(0.5, 0.5, 0.135 * s, top - max(3, round(5 * s)), top - 1, BAG, name="bag")
    c.cylinder(0.5, 0.5, 0.155 * s, top - 1, top + 1, BAG, open_top=True, name="bag_fold")
    return c


def trash_shadow_shapes(scale=1.0):
    return [("disc", 0.5, 0.5, 0.15 * scale, 0, round(BIN_TOP * scale))]


# ---------------------------------------------------------------------------- principal

def build(out_dir):
    files = []
    items = []

    def keep(c, name, shapes, **meta):
        c.finish()
        files.append(iso.save(c, out_dir, name, **meta))
        files.append(chair_plant.save_shadow(c, out_dir, name + "_shadow", shapes))
        items.append((name, sheet.on_background(c.image, scale=1)))

    for rotation in range(4):
        keep(reception_counter(rotation), "reception_counter_r%d" % rotation, counter_shadow_shapes(),
             height=COUNTER_ITEM["height"])
    for rotation in range(4):
        keep(waiting_sofa(rotation), "waiting_sofa_r%d" % rotation, sofa_shadow_shapes(),
             height=SOFA_ITEM["height"])
    for suffix, scale in (("", 1.0), ("_q", 0.6)):
        for rotation in range(4):
            keep(water_dispenser(rotation, scale), "water_dispenser%s_r%d" % (suffix, rotation),
                 water_shadow_shapes(scale), height=WATER_ITEM["height"], small=True, final_size=scale < 1.0,
                 curved=True)
    for suffix, scale in (("", 1.0), ("_q", 0.6)):
        keep(trash_can(scale), "trash_can" + suffix, trash_shadow_shapes(scale), height=TRASH_ITEM["height"],
             small=True, final_size=scale < 1.0, curved=True)
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    sheet.contact_sheet(items, columns=4, scale=3).save(os.path.join(folder, "reception.png"))
    return files
