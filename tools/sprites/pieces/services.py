# Baño, limpieza y servidores (estilo de tools/sprites/STYLE.md):
#
#   toilet_r0..r3            inodoro de cerámica blanca: tanque atrás con botón, taza y tapa (frente a −y)
#   sink_r0..r3              lavamanos de pedestal: columna, lavabo con su hueco, llave de metal
#   cleaning_closet_r0..r3   armario de limpieza gris azulado de dos puertas con rejillas y un cartel
#                            amarillo, con un balde y un trapeador al lado
#   server_rack_r0..r3       rack negro con servidores de luces verdes y azules tras la puerta de malla
#   <cada uno>_shadow        sombra en el piso, aparte
#   _sheets/services.png     hoja de contacto
import numpy as np

import iso
import palette as pal
from pieces._kit import Saver, g, grid, inside, plain, sunken

ITEMS = iso.load_json("data/furniture.json")["items"]
TOILET_ITEM = ITEMS["toilet"]
SINK_ITEM = ITEMS["sink"]
CLOSET_ITEM = ITEMS["cleaning_closet"]
RACK_ITEM = ITEMS["server_rack"]

CERAMIC = pal.style("ceramic_white", name="bath_ceramic")
CERAMIC_LINE = CERAMIC.add("8f989c")
WATER = CERAMIC.add("9fd0e6")
CHROME = pal.style("metal_light", name="bath_chrome")
CLOSET = pal.style_ramp("8fa3b8", outline="1f2a36", name="closet_body")
CLOSET_LINE = CLOSET.add("4e5f70")
CLOSET_HANDLE = CLOSET.add("e8ecee")
SIGN = CLOSET.add("f0c030")
SIGN_DARK = CLOSET.add("2a2a2a")
BUCKET = pal.style_ramp("f0c030", outline="3a2a06", name="mop_bucket")
MOP = pal.style("wood_orange", name="mop_handle")
MOP_HEAD = pal.style_ramp("e8e4d8", outline="3d3b44", name="mop_head")
RACK = pal.style_ramp("33383f", outline="07090b", name="server_rack")
RACK_LINE = RACK.add("15191d")
RACK_UNIT = RACK.add("4a525b")
LED_G = RACK.add("6fe08a")
LED_B = RACK.add("3fd0f0")
LED_A = RACK.add("f0b030")
MESH = RACK.add("5b646e")


# ---------------------------------------------------------------------------- inodoro

TANK_TOP = 26
BOWL_TOP = 15


def tank_front(ctx):
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    return np.where(b == h - 4, CERAMIC_LINE, index)  # junta de la tapa del tanque


def bowl_cap(ctx):
    """Tapa cerrada con el aro un tono más oscuro cerca del borde."""
    index = plain(ctx)
    return np.where((ctx.t > 0.78) & (ctx.t < 0.88), CERAMIC_LINE, index)


def toilet(rotation):
    c = iso.Canvas.furniture(TOILET_ITEM["size"], TOILET_ITEM["height"], rotation)
    c.box(g(0.34), g(0.66), g(0.7), g(0.84), 6, TANK_TOP, CERAMIC, tex={iso.FRONT: tank_front}, name="tank",
          flat=False)
    c.box(g(0.33), g(0.67), g(0.69), g(0.85), TANK_TOP, TANK_TOP + 2, CERAMIC, name="tank_lid")
    c.cylinder(0.5, 0.77, 0.03, TANK_TOP + 2, TANK_TOP + 3, CHROME, name="button")
    c.cylinder(0.5, 0.5, 0.12, 0, 8, CERAMIC, radius_top=0.17, name="foot")
    c.cylinder(0.5, 0.45, 0.2, 8, BOWL_TOP, CERAMIC, name="bowl")
    c.cylinder(0.5, 0.45, 0.2, BOWL_TOP, BOWL_TOP + 2, CERAMIC, tex={"cap": bowl_cap}, name="seat")
    return c


def toilet_shadow_shapes():
    return [("disc", 0.5, 0.47, 0.21, 0, BOWL_TOP), ("bar", 0.37, 0.77, 0.63, 0.77, 0.08, 0, TANK_TOP)]


# ---------------------------------------------------------------------------- lavamanos

BASIN_Z = 28
BASIN_TOP = 36


def basin_top(ctx):
    """Hueco del lavabo: óvalo hundido con agua clara y desagüe."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    u = (a + 0.5 - w / 2.0) / (w * 0.36)
    v = (b + 0.5 - h * 0.45) / (h * 0.32)
    r = u * u + v * v
    index = np.where(r < 1.0, CERAMIC_LINE, index)
    index = np.where(r < 0.75, WATER, index)
    return np.where(r < 0.06, CERAMIC_LINE, index)


def sink(rotation):
    c = iso.Canvas.furniture(SINK_ITEM["size"], SINK_ITEM["height"], rotation)
    c.cylinder(0.5, 0.62, 0.07, 0, BASIN_Z, CERAMIC, radius_top=0.09, name="pedestal")
    c.box(g(0.24), g(0.76), g(0.36), g(0.84), BASIN_Z, BASIN_TOP, CERAMIC, tex={"top": basin_top}, name="basin",
          flat=False)
    c.box(g(0.47), g(0.53), g(0.74), g(0.8), BASIN_TOP, BASIN_TOP + 7, CHROME, name="faucet")
    c.box(g(0.47), g(0.53), g(0.64), g(0.74), BASIN_TOP + 5, BASIN_TOP + 7, CHROME, name="spout")
    c.box(g(0.4), g(0.45), g(0.75), g(0.79), BASIN_TOP, BASIN_TOP + 3, CHROME, name="tap_l")
    c.box(g(0.55), g(0.6), g(0.75), g(0.79), BASIN_TOP, BASIN_TOP + 3, CHROME, name="tap_r")
    return c


def sink_shadow_shapes():
    return [("bar", 0.32, 0.6, 0.68, 0.6, 0.22, 0, BASIN_TOP)]


# ---------------------------------------------------------------------------- armario de limpieza

CLOSET_TOP = 62


def closet_front(ctx):
    """Dos puertas con rejillas arriba y abajo, tiradores y un cartel amarillo de piso mojado."""
    a, b, w, h = grid(ctx)
    mid = np.floor(w / 2.0)
    index = sunken(plain(ctx), a, b, 2, mid - 1, 3, h - 3, CLOSET_LINE, pal.LIGHT)
    index = sunken(index, a, b, mid + 1, w - 2, 3, h - 3, CLOSET_LINE, pal.LIGHT)
    for a0, a1 in ((4, mid - 3), (mid + 3, w - 4)):
        for b0, b1 in ((6, 13), (h - 13, h - 6)):
            index = np.where(inside(a, b, a0, a1, b0, b1) & (np.mod(b, 2) == 0), CLOSET_LINE, index)
    for a0 in (mid - 3, mid + 2):
        index = np.where(inside(a, b, a0, a0 + 1, np.floor(h / 2.0) - 4, np.floor(h / 2.0) + 4), CLOSET_HANDLE,
                         index)
    sign = inside(a, b, 5, mid - 5, np.floor(h * 0.55), np.floor(h * 0.55) + 8)
    index = np.where(sign, SIGN, index)
    index = np.where(sign & inside(a, b, 7, mid - 7, np.floor(h * 0.55) + 2, np.floor(h * 0.55) + 6) &
                     (np.mod(a, 2) == 0), SIGN_DARK, index)
    return np.where(b < 2, CLOSET_LINE, index)


def cleaning_closet(rotation):
    c = iso.Canvas.furniture(CLOSET_ITEM["size"], CLOSET_ITEM["height"], rotation)
    c.box(g(0.3), g(0.84), g(0.42), g(0.86), 0, CLOSET_TOP, CLOSET, tex={iso.FRONT: closet_front}, name="body",
          flat=False)
    # Balde amarillo con trapeador, delante a la izquierda.
    c.cylinder(0.2, 0.24, 0.1, 0, 10, BUCKET, radius_top=0.12, open_top=True, name="bucket")
    c.cylinder(0.2, 0.24, 0.1, 6, 9, MOP_HEAD, name="mop_head")
    c.capsule((0.2, 0.24, 8), (0.16, 0.36, 46), 1.5, MOP, name="mop")
    return c


def closet_shadow_shapes():
    return [("bar", 0.57, 0.5, 0.57, 0.78, 0.3, 0, CLOSET_TOP), ("disc", 0.2, 0.24, 0.13, 0, 10)]


# ---------------------------------------------------------------------------- rack de servidores

RACK_TOP = 88


def rack_front(ctx):
    """Marco negro y, detrás de la puerta de malla, servidores de 1 y 2 unidades con sus luces."""
    a, b, w, h = grid(ctx)
    index = plain(ctx)
    bay = inside(a, b, 3, w - 3, 5, h - 4)
    index = np.where(bay, RACK_LINE, index)
    heights = (4, 4, 7, 4, 7, 4, 4, 7, 4, 7, 4, 4, 7)
    b0 = 6
    for k, uh in enumerate(heights):
        unit = bay & inside(a, b, 4, w - 4, b0, b0 + uh - 1)
        index = np.where(unit, RACK_UNIT, index)
        row = b0 + uh - 3
        index = np.where(unit & (b == row) & (a >= 6) & (a < 8), LED_G, index)
        index = np.where(unit & (b == row) & (a >= 9) & (a < 11), LED_B if k % 3 else LED_A, index)
        index = np.where(unit & (b == row) & (a >= w - 14) & (a < w - 6) & (np.mod(a, 2) == 0), RACK_LINE, index)
        b0 += uh
    mesh = bay & (np.mod(a + b, 6) == 0) & (index == RACK_UNIT)
    index = np.where(mesh, MESH, index)
    return np.where(b < 3, RACK_LINE, index)


def rack_side(ctx):
    a, b, w, h = grid(ctx)
    index = sunken(plain(ctx), a, b, 3, w - 3, 5, h - 4, RACK_LINE, pal.LIGHT)
    return np.where(b < 3, RACK_LINE, index)


def server_rack(rotation):
    c = iso.Canvas.furniture(RACK_ITEM["size"], RACK_ITEM["height"], rotation)
    c.box(g(0.22), g(0.78), g(0.18), g(0.82), 0, RACK_TOP, RACK, tex={iso.FRONT: rack_front, "sides": rack_side,
                                                                       iso.BACK: rack_side},
          name="body", flat=False)
    return c


def rack_shadow_shapes():
    return [("bar", 0.5, 0.28, 0.5, 0.72, 0.3, 0, RACK_TOP)]


# ---------------------------------------------------------------------------- principal

def build(out_dir):
    s = Saver(out_dir)
    s.rotations(toilet, "toilet", toilet_shadow_shapes(), height=TOILET_ITEM["height"], curved=True)
    s.rotations(sink, "sink", sink_shadow_shapes(), height=SINK_ITEM["height"], curved=True)
    s.rotations(cleaning_closet, "cleaning_closet", closet_shadow_shapes(), height=CLOSET_ITEM["height"],
                curved=True)
    s.rotations(server_rack, "server_rack", rack_shadow_shapes(), height=RACK_ITEM["height"])
    return s.sheet("services")
