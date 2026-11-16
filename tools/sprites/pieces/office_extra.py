# Muebles de oficina extra (estilo de tools/sprites/STYLE.md):
#
#   executive_desk_r0..r3      2×1: escritorio ejecutivo de nogal: dos cajoneras enteras, panel con
#                              tableros hundidos del lado de la visita y tablero grueso con filo dorado
#   printer_r0..r3             impresora multifunción gris clara sobre un mueble bajo con puerta
#   filing_cabinet_r0..r3      archivero de metal de cuatro cajones con tirador y etiqueta
#   backup_battery_r0..r3      gabinete de baterías gris oscuro: pantalla, luces y cuatro módulos
#   meeting_table              2×2: mesa de reuniones redonda de madera sobre una columna (simétrica)
#   <cada uno>_shadow          sombra en el piso, aparte
#   _sheets/office_extra.png   hoja de contacto
#
# El escritorio tiene la superficie en z = 44 (iso.DESK_TOP), como el sencillo, aunque su `height` sea 26.
import numpy as np

import iso
import palette as pal
from pieces import desk as simple
from pieces._kit import Saver, drawers, g, grid, inside, plain, sunken

ITEMS = iso.load_json("data/furniture.json")["items"]
EXEC = ITEMS["executive_desk"]
PRINTER = ITEMS["printer"]
FILING = ITEMS["filing_cabinet"]
BATTERY = ITEMS["backup_battery"]
MEETING = ITEMS["meeting_table"]

U = simple.U
TOP = iso.DESK_TOP

WOOD = pal.style("wood_orange", name="wide_desk_wood")
WALNUT = pal.style_ramp("a0603a", outline="2a1206", light="bd7a4c", name="executive_walnut")
WALNUT_LINE = WALNUT.add("4a2410")
BRASS = WALNUT.add("e0b84a")  # filo dorado del tablero y tiradores
METAL = pal.style_ramp("aeb5b9", outline="2f3437", name="filing_metal")
METAL_LINE = METAL.add("5f676b")
METAL_HANDLE = METAL.add("e8ecee")
LABEL = METAL.add("f2ead2")
PRINT_BODY = pal.style_ramp("e8e9ea", side="cfd2d4", shadow="b3b8bb", outline="3d3b44", name="printer_body")
PRINT_DARK = PRINT_BODY.add("4a4f55")
PRINT_PAPER = PRINT_BODY.add("ffffff")
PRINT_SCREEN = PRINT_BODY.add("6dacce")
PRINT_GREEN = PRINT_BODY.add("6fe08a")
STAND = pal.style_ramp("6b7177", outline="1f2326", name="printer_stand")
STAND_LINE = STAND.add("41464b")
STAND_HANDLE = STAND.add("aab1b6")
LID = pal.style_ramp("9aa1a6", outline="2f3437", name="printer_lid")
BATTERY_BODY = pal.style_ramp("4f5a66", outline="12161b", name="battery_body")
BATTERY_LINE = BATTERY_BODY.add("2a3038")
BATTERY_LCD = BATTERY_BODY.add("7fe0b0")
BATTERY_LED = BATTERY_BODY.add("6fe08a")
BATTERY_AMBER = BATTERY_BODY.add("f0b030")
BATTERY_HANDLE = BATTERY_BODY.add("8c96a0")
TABLE_WOOD = pal.style("wood_orange", name="meeting_wood")
TABLE_EDGE = TABLE_WOOD.add("743b0e")
COLUMN = pal.style_ramp("4a4f55", outline="141619", name="meeting_column")


# ---------------------------------------------------------------------------- escritorio ejecutivo

EXEC_SLAB = 7
EXEC_PED = ((2 * U, 15 * U), (49 * U, 62 * U))
EXEC_Y = (4 * U, 28 * U)


def exec_top_side(ctx):
    """Canto del tablero con filo dorado de 1 px a media altura."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    return np.where(b == np.floor(h / 2.0), BRASS, index)


def exec_panel(ctx):
    """Panel de la visita: tres tableros hundidos."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    count = 3
    step = (w - 4) / float(count)
    for k in range(count):
        a0 = np.floor(2 + k * step) + 2
        a1 = np.floor(2 + (k + 1) * step) - 2
        index = sunken(index, a, b, a0, a1, 4, h - 4, WALNUT_LINE, pal.LIGHT)
    return np.where(b < 2, WALNUT_LINE, index)


def exec_side(ctx):
    a, b, w, h = grid(ctx)
    index = sunken(plain(ctx), a, b, 3, w - 3, 4, h - 4, WALNUT_LINE, pal.LIGHT)
    return np.where(b < 2, WALNUT_LINE, index)


def executive_desk(rotation):
    c = iso.Canvas.furniture(EXEC["size"], EXEC["height"], rotation)
    under = TOP - EXEC_SLAB
    peds = None
    for x0, x1 in EXEC_PED:
        pid = c.box(x0, x1, EXEC_Y[0], EXEC_Y[1], 0, under, WALNUT,
                    tex={iso.FRONT: drawers(3, WALNUT_LINE, BRASS, margin=1, foot=3), "sides": exec_side,
                         iso.BACK: exec_side},
                    name="pedestals" if peds is None else None, part=peds, flat=False)
        peds = pid if peds is None else peds
    # Panel de la visita (atrás, +y).
    c.box(EXEC_PED[0][1], EXEC_PED[1][0], 24 * U, 27 * U, 4, under, WALNUT, tex={iso.BACK: exec_panel},
          shade={iso.FRONT: -1}, name="modesty", flat=False)
    c.box(1 * U, 63 * U, 2 * U, 30 * U, under, TOP, WALNUT, tex={"sides": exec_top_side}, name="top", flat=False)
    return c


def exec_shadow_shapes():
    return [("bar", 0.2, 0.5, 1.8, 0.5, 0.42, 0, TOP)]


# ---------------------------------------------------------------------------- impresora

STAND_TOP = 18
BODY_TOP = 30
LID_TOP = 34


def stand_front(ctx):
    """Mueble bajo con una puerta y tirador."""
    a, b, w, h = grid(ctx)
    index = sunken(plain(ctx), a, b, 2, w - 2, 2, h - 2, STAND_LINE, pal.LIGHT)
    index = np.where(inside(a, b, w - 6, w - 4, np.floor(h / 2.0) - 2, np.floor(h / 2.0) + 3), STAND_HANDLE, index)
    return np.where(b < 1, STAND_LINE, index)


def printer_front(ctx):
    """Bandeja de papel abajo, la ranura de salida con una hoja y la línea del escáner."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    index = np.where(inside(a, b, 3, w - 3, 2, 3), PRINT_DARK, index)  # junta de la bandeja
    index = np.where(inside(a, b, np.floor(w / 2.0) - 5, np.floor(w / 2.0) + 5, 4, 5), PRINT_DARK, index)  # tirador
    index = np.where(inside(a, b, 4, w - 4, h - 5, h - 3), PRINT_DARK, index)  # ranura de salida
    index = np.where(inside(a, b, 7, w - 7, h - 4, h - 3), PRINT_PAPER, index)  # la hoja que sale
    return np.where(b < 1, pal.RIGHT, index)


def printer_top(ctx):
    """Panel de control en la franja de adelante: pantalla celeste y botón verde."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    index = np.where(inside(a, b, 4, 14, 0, 3), PRINT_SCREEN, index)
    return np.where(inside(a, b, 17, 19, 0, 2), PRINT_GREEN, index)


def printer(rotation):
    c = iso.Canvas.furniture(PRINTER["size"], PRINTER["height"], rotation)
    c.box(g(0.2), g(0.8), g(0.22), g(0.78), 0, STAND_TOP, STAND, tex={iso.FRONT: stand_front}, name="stand",
          flat=False)
    c.box(g(0.22), g(0.78), g(0.25), g(0.75), STAND_TOP, BODY_TOP, PRINT_BODY,
          tex={iso.FRONT: printer_front, "top": printer_top}, name="body", flat=False)
    c.box(g(0.25), g(0.75), g(0.42), g(0.73), BODY_TOP, LID_TOP, LID, name="lid")
    return c


def printer_shadow_shapes():
    return [("bar", 0.32, 0.5, 0.68, 0.5, 0.26, 0, LID_TOP)]


# ---------------------------------------------------------------------------- archivero

FILING_TOP = 52


def filing_side(ctx):
    a, b, w, h = grid(ctx)
    return sunken(plain(ctx), a, b, 3, w - 3, 4, h - 3, METAL_LINE, pal.LIGHT)


def filing_cabinet(rotation):
    c = iso.Canvas.furniture(FILING["size"], FILING["height"], rotation)
    c.box(g(0.26), g(0.74), g(0.2), g(0.8), 0, FILING_TOP - 2, METAL,
          tex={iso.FRONT: drawers(4, METAL_LINE, METAL_HANDLE, margin=1, foot=2, handle_w=0.35, label=LABEL),
               "sides": filing_side, iso.BACK: filing_side}, name="body", flat=False)
    c.box(g(0.25), g(0.75), g(0.19), g(0.81), FILING_TOP - 2, FILING_TOP, METAL, name="lid")
    return c


def filing_shadow_shapes():
    return [("bar", 0.5, 0.25, 0.5, 0.75, 0.26, 0, FILING_TOP)]


# ---------------------------------------------------------------------------- baterías

BATTERY_TOP = 44


def battery_front(ctx):
    """Pantalla verde y luces arriba; cuatro módulos con su asa y una franja ámbar abajo."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    top0 = h - 11
    index = np.where(inside(a, b, 3, w - 3, top0, h - 3), BATTERY_LINE, index)
    index = np.where(inside(a, b, 5, 15, top0 + 2, h - 5), BATTERY_LCD, index)
    index = np.where(inside(a, b, w - 9, w - 7, top0 + 3, top0 + 5), BATTERY_LED, index)
    index = np.where(inside(a, b, w - 6, w - 4, top0 + 3, top0 + 5), BATTERY_AMBER, index)
    count = 4
    step = (top0 - 3) / float(count)
    for k in range(count):
        b0 = np.floor(2 + k * step)
        b1 = np.floor(2 + (k + 1) * step)
        index = np.where(inside(a, b, 2, w - 2, b1 - 1, b1), BATTERY_LINE, index)
        mid = np.floor((b0 + b1) / 2.0)
        index = np.where(inside(a, b, np.floor(w / 2.0) - 5, np.floor(w / 2.0) + 5, mid, mid + 2), BATTERY_HANDLE,
                         index)
        index = np.where(inside(a, b, 3, 5, b0 + 1, b1 - 2), BATTERY_LED, index)
    return np.where(b < 2, BATTERY_LINE, index)


def battery_side(ctx):
    """Rejillas de ventilación arriba en los costados."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    vents = inside(a, b, 4, w - 4, h - 16, h - 4) & (np.mod(b, 3) == 0)
    index = np.where(vents, BATTERY_LINE, index)
    return np.where(b < 2, BATTERY_LINE, index)


def backup_battery(rotation):
    c = iso.Canvas.furniture(BATTERY["size"], BATTERY["height"], rotation)
    c.box(g(0.24), g(0.76), g(0.26), g(0.74), 0, BATTERY_TOP, BATTERY_BODY,
          tex={iso.FRONT: battery_front, "sides": battery_side}, name="body", flat=False)
    return c


def battery_shadow_shapes():
    return [("bar", 0.5, 0.32, 0.5, 0.68, 0.27, 0, BATTERY_TOP)]


# ---------------------------------------------------------------------------- mesa de reuniones

TABLE_TOP = 40
TABLE_SLAB = 5
TABLE_R = 0.8


def table_cap(ctx):
    """Tapa de madera con un aro más oscuro cerca del canto."""
    index = plain(ctx)
    return np.where((ctx.t > 0.86) & (ctx.t < 0.9), TABLE_EDGE, index)


def meeting_table():
    c = iso.Canvas.furniture(MEETING["size"], MEETING["height"])
    c.cylinder(1.0, 1.0, 0.36, 0, 3, COLUMN, radius_top=0.3, name="foot")
    c.cylinder(1.0, 1.0, 0.09, 3, TABLE_TOP - TABLE_SLAB, COLUMN, name="column")
    c.cylinder(1.0, 1.0, TABLE_R, TABLE_TOP - TABLE_SLAB, TABLE_TOP, TABLE_WOOD, tex={"cap": table_cap}, name="top")
    return c


def meeting_shadow_shapes():
    return [("disc", 1.0, 1.0, 0.7, 0, TABLE_TOP)]


# ---------------------------------------------------------------------------- principal

def build(out_dir):
    s = Saver(out_dir)
    s.rotations(executive_desk, "executive_desk", exec_shadow_shapes(), height=EXEC["height"])
    s.rotations(printer, "printer", printer_shadow_shapes(), height=PRINTER["height"])
    s.rotations(filing_cabinet, "filing_cabinet", filing_shadow_shapes(), height=FILING["height"])
    s.rotations(backup_battery, "backup_battery", battery_shadow_shapes(), height=BATTERY["height"])
    s.keep(meeting_table(), "meeting_table", meeting_shadow_shapes(), height=MEETING["height"], curved=True)
    return s.sheet("office_extra")
