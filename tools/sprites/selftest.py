#!/usr/bin/env python3
# Prueba propia del motor: dibuja piezas de ejemplo con todas las primitivas y arma hojas para
# mirarlas. No es arte del juego.
#
#   python3 tools/sprites/selftest.py [--out DIR]
#
# Escribe en DIR (por defecto una carpeta temporal) los PNG de prueba, su manifiesto, las hojas
# sheet_*.png ampliadas, y corre check.py sobre la carpeta.
import argparse
import contextlib
import io
import json
import os
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import check  # noqa: E402
import iso  # noqa: E402
import palette as pal  # noqa: E402
import pattern  # noqa: E402
import sheet  # noqa: E402

WOOD = pal.ramp("9a7048")
DARK_WOOD = pal.ramp("6b4a32")
METAL = pal.ramp("b9bcc2")
WALL = pal.ramp("d8d0c4")
CLAY = pal.ramp("8a5a3c")
SOIL = pal.ramp("4a3528")
LEAF = pal.ramp("4f8a3c")
BLUE = pal.ramp("3d5a80")
RED = pal.ramp("a0523d")


def wood_top(ctx):
    """Veta a lo largo de x en la cara de arriba."""
    veins = pattern.grain(ctx.a, ctx.b, seed=5, density=0.5, length=18, row=4)
    return np.where(veins, pal.SOFT, ctx.base)


def wood_side(ctx):
    """Veta horizontal en una cara lateral."""
    veins = pattern.grain(ctx.a, ctx.b, seed=9, density=0.35, length=14, row=5)
    return np.where(veins, pal.darker(ctx.base), ctx.base)


def drawers(ctx):
    """Frente con tres cajones: rendija oscura alrededor de cada uno."""
    index = ctx.base
    for b0 in (3, 15, 27):
        edge = pattern.frame(ctx.a, ctx.b, 4, ctx.w - 4, b0, b0 + 11, 1)
        index = np.where(edge, pal.darker(ctx.base), index)
    return index


def cabinet(c):
    """Mueble de 2×1 asimétrico para ver las rotaciones: cuerpo con cajones al frente (−y),
    tablero con vuelo y una cajita arriba en la esquina (x0, frente)."""
    c.box(1 / 16, 31 / 16, 3 / 16, 15 / 16, 0, 38, WOOD, tex={iso.FRONT: drawers, "sides": wood_side}, name="body")
    for z in (8, 20, 32):
        c.box(11 / 16, 21 / 16, 5 / 32, 3 / 16, z, z + 2, METAL, name="handle%d" % z)
    c.box(0, 2, 2 / 16, 1, 38, 44, WOOD, tex={iso.TOP: wood_top, "sides": wood_side}, name="top")
    c.box(2 / 16, 8 / 16, 4 / 16, 9 / 16, 44, 56, BLUE, name="cube")
    c.cylinder(1.5, 0.6, 5 / 32, 44, 54, METAL, name="can")


def build_boxes(out_dir):
    files = []
    for rotation in range(4):
        c = iso.Canvas.furniture((2, 1), 28, rotation)
        cabinet(c)
        files.append(iso.save(c, out_dir, "box_test_r%d" % rotation))
        if rotation == 1:
            files.append(iso.save(c.ground_shadow(), out_dir, "box_test_r1_shadow", kind="shadow",
                                  footprint=list(c.world_size), anchor=list(c.anchor)))
    return files


def chair(c):
    """Silla con primitivas curvas para ver que también giran: asiento y respaldo acolchados
    (soft_box), respaldo en la espalda (+y), patas cilíndricas y un panel inclinado de apoyabrazos."""
    for x, y in ((0.30, 0.30), (0.70, 0.30), (0.30, 0.70), (0.70, 0.70)):
        c.cylinder(x, y, 1 / 32, 0, 18, METAL, name="leg")
    c.soft_box(0.22, 0.78, 0.22, 0.78, 16, 26, 4, BLUE, name="seat")
    c.soft_box(0.24, 0.76, 0.68, 0.80, 22, 52, 4, BLUE, name="back")
    c.panel((0.22, 0.30, 26), (0.0, 0.34, 0), (0.0, 0.06, 10), METAL, name="arm")


def build_chairs(out_dir):
    files = []
    for rotation in range(4):
        c = iso.Canvas.furniture((1, 1), 28, rotation)
        chair(c)
        files.append(iso.save(c, out_dir, "chair_test_r%d" % rotation))
    return files


def build_curves(out_dir):
    files = []
    # Cilindro, maceta abierta con tierra y cono.
    c = iso.Canvas.tile()
    c.cylinder(0.30, 0.30, 0.18, 0, 40, METAL, name="tube")
    c.cylinder(0.70, 0.62, 0.14, 0, 22, CLAY, radius_top=0.22, open_top=True, name="pot")
    c.cylinder(0.70, 0.62, 0.18, 14, 18, SOIL, name="soil", outline=False)
    c.cylinder(0.28, 0.78, 0.14, 0, 26, RED, radius_top=0.02, name="cone")
    files.append(iso.save(c, out_dir, "cylinder_test"))
    # Esfera, cúpula, cojín de aristas redondas y cápsula.
    c = iso.Canvas.tile()
    c.sphere(0.30, 0.30, 26, 0.22, RED, name="ball")
    c.ellipsoid(0.72, 0.30, 0, 0.20, 0.20, 22, LEAF, clip_z=(0, 22), dither=0.10, name="dome")
    c.soft_box(0.14, 0.60, 0.56, 0.94, 0, 18, 6, BLUE, name="cushion")
    c.capsule((0.80, 0.70, 4), (0.80, 0.90, 30), 4, METAL, name="rod")
    files.append(iso.save(c, out_dir, "ellipsoid_test"))
    # Caja de esquinas redondas, panel inclinado y sello a mano.
    c = iso.Canvas.tile()
    c.rounded_box(4 / 32, 20 / 32, 4 / 32, 28 / 32, 0, 30, 5 / 32, WALL, name="fridge")
    c.panel((0.70, 0.30, 0), (0.0, 0.5, 0), (0.12, 0.0, 34), DARK_WOOD, name="board")
    c.stamp([[-1, 6, 6, -1], [6, 5, 5, 6], [6, 5, 5, 6], [-1, 6, 6, -1]], 0.375, 0.5, 30, LEAF, name="mark")
    files.append(iso.save(c, out_dir, "rounded_test"))
    return files


def style_desk(c):
    """Escritorio con el estilo de STYLE.md (rampas con caras declaradas y acabado 'salvaje'):
    patas, cajonera con tirador, tablero con vuelo y cosas encima (monitor, maceta con hojas,
    cojín) para ver contorno, línea interior, brillo de arista y esquinas recortadas."""
    wood, black = pal.WOOD_ORANGE, pal.PLASTIC_BLACK
    for x, y in ((3 / 32, 5 / 32), (57 / 32, 5 / 32), (3 / 32, 25 / 32), (57 / 32, 25 / 32)):
        c.box(x, x + 3 / 32, y, y + 3 / 32, 0, 38, wood, name="leg")
    c.box(36 / 32, 58 / 32, 6 / 32, 26 / 32, 14, 38, wood, name="drawers")
    c.box(40 / 32, 54 / 32, 5 / 32, 6 / 32, 24, 28, wood, shade=-1, name="handle")
    c.box(1 / 32, 63 / 32, 3 / 32, 29 / 32, 38, 44, wood, name="top")
    c.box(8 / 32, 26 / 32, 20 / 32, 23 / 32, 44, 72, black, name="monitor")
    c.box(14 / 32, 20 / 32, 21 / 32, 24 / 32, 44, 50, black, name="foot")
    c.cylinder(48 / 32, 16 / 32, 0.12, 44, 56, pal.CLAY, open_top=True, name="pot")
    c.sphere(48 / 32, 16 / 32, 64, 0.16, pal.LEAVES, name="leaves")
    c.soft_box(30 / 32, 40 / 32, 8 / 32, 18 / 32, 44, 50, 3, pal.UPHOLSTERY_RED, name="cushion")


def build_style(out_dir):
    files = []
    for rotation in range(4):
        c = iso.Canvas.furniture((2, 1), 36, rotation)
        style_desk(c)
        files.append(iso.save(c, out_dir, "style_test_r%d" % rotation))
    return files


def floor_tile(variant):
    """Losas 2×2 con junta, bisel y manchas repartidas con cantidad exacta por tono."""
    grid = iso.tile_grid()
    colors = pal.palette([pal.darken("b39c72", 0.28), "b39c72", pal.darken("c9b48a", 0.06), "c9b48a",
                          pal.lighten("c9b48a", 0.10)])
    joint_i, dark_i, mid_i, base_i, light_i = range(5)
    joint = pattern.joints(grid.U, grid.V, 32, 2)
    lit, dark = pattern.bevel(grid.U, grid.V, 32, 2, 1)
    inner = grid.mask & ~joint & ~lit & ~dark
    value = pattern.blobs(grid.u, grid.v, seed=40 + variant)
    levels = pattern.exact_levels(value, inner, [300], group=grid.domino, tie=pattern.bayer(grid.iu, grid.iv, 4))
    index = np.full(grid.mask.shape, base_i, dtype=np.int16)
    index[inner & (levels == 0)] = mid_i
    index[lit] = light_i
    index[dark] = dark_i
    index[joint] = joint_i
    return grid.image(index, colors)


def build_floor(out_dir):
    files = []
    for variant in range(4):
        files.append(iso.save(floor_tile(variant), out_dir, "floor_test_%d" % variant, kind="floor",
                              material="test", variant=variant, base_colors=["c9b48a", "b39c72"]))
    return files


def _wall_face(tall):
    def face(ctx):
        index = ctx.base
        if tall:
            index = np.where(ctx.b < 12, pal.darker(ctx.base), index)  # zócalo
            index = np.where((ctx.b >= 12) & (ctx.b < 13), pal.lighter(ctx.base), index)
        return index

    return face


def wall_piece(axis, tall):
    c = iso.Canvas.wall(axis, tall)
    height = 120 if tall else iso.WALL_LOW_HEIGHT
    half = iso.WALL_THICKNESS / 2.0
    c.box(0, 1, -half, half, 0, height, WALL, tex={iso.BACK: _wall_face(tall)}, name="wall")
    return c


def build_walls(out_dir):
    files = []
    for axis in ("x", "y"):
        for tall in (True, False):
            name = "wall_test_%s_%s" % ("tall" if tall else "low", axis)
            files.append(iso.save(wall_piece(axis, tall), out_dir, name, height=60 if tall else 10))
    return files


def build_sheets(out_dir):
    files = []

    def img(name):
        return sheet.load(os.path.join(out_dir, name + ".png"))

    tiles = [img("floor_test_%d" % i) for i in range(4)]
    rotations = [("r%d" % r, sheet.on_floor(img("box_test_r%d" % r), tiles, scale=1,
                                             anchor=(iso.Canvas.furniture((2, 1), 28, r).anchor)))
                 for r in range(4)]
    path = os.path.join(out_dir, "sheet_rotations.png")
    sheet.contact_sheet(rotations, columns=2, scale=2).save(path)
    files.append(path)
    path = os.path.join(out_dir, "sheet_chairs.png")
    sheet.contact_sheet([("r%d" % r, sheet.on_floor(img("chair_test_r%d" % r), tiles, scale=1, cells=0))
                         for r in range(4)], columns=4, scale=4).save(path)
    files.append(path)
    path = os.path.join(out_dir, "sheet_curves.png")
    sheet.contact_sheet([(n, sheet.on_floor(img(n), tiles, scale=1)) for n in
                         ("cylinder_test", "ellipsoid_test", "rounded_test")], columns=3, scale=2).save(path)
    files.append(path)
    path = os.path.join(out_dir, "sheet_style.png")
    sheet.contact_sheet([("r%d" % r, sheet.on_floor(img("style_test_r%d" % r), tiles, scale=1,
                                                     anchor=iso.Canvas.furniture((2, 1), 36, r).anchor))
                         for r in range(4)], columns=2, scale=3).save(path)
    files.append(path)
    path = os.path.join(out_dir, "sheet_floor.png")
    sheet.tile_mosaic(tiles, 5, 5, seed=2, scale=3).save(path)
    files.append(path)
    # Escena: cuarto de 4×4 con paredes altas al fondo y bajas adelante, y el mueble adentro.
    scene = sheet.Scene(4, 4, top=150)
    scene.fill_floor(tiles, seed=4)
    for i in range(4):
        scene.add_wall(img("wall_test_tall_y"), i, -1, "y")
        scene.add_wall(img("wall_test_tall_x"), -1, i, "x")
        scene.add_wall(img("wall_test_low_y"), i, 3, "y")
        scene.add_wall(img("wall_test_low_x"), 3, i, "x")
    c = iso.Canvas.furniture((2, 1), 28, 1)
    scene.add_shadow(img("box_test_r1_shadow"), 1, 1, anchor=c.anchor, opacity=0.3)
    scene.add(img("box_test_r1"), 1, 1, anchor=c.anchor, size=c.world_size)
    scene.add(img("cylinder_test"), 3, 0)
    scene.add(img("ellipsoid_test"), 0, 3)
    scene.add(img("rounded_test"), 3, 3)
    path = os.path.join(out_dir, "sheet_scene.png")
    scene.render(scale=3).save(path)
    files.append(path)
    return files


# ---------------------------------------------------------------------- medidas del motor

class Tally(object):
    """Cuenta de comprobaciones medidas (no a ojo)."""

    def __init__(self):
        self.good = 0
        self.bad = []

    def check(self, ok, message):
        if ok:
            self.good += 1
        else:
            self.bad.append(message)
            print("MAL    " + message)
        return ok


def _runs(values):
    out = []
    for value in values:
        if out and out[-1][0] == value:
            out[-1][1] += 1
        else:
            out.append([value, 1])
    return out


def stair_errors(mask):
    """Errores de escalera 2:1 de una región convexa: huecos por columna, columnas salteadas y
    tramos interiores del borde de arriba o de abajo (entre dos escalones de ±1 en el mismo
    sentido) que no miden 2 px."""
    cols = np.nonzero(mask.any(axis=0))[0]
    if len(cols) == 0:
        return 0
    bad = int((np.diff(cols) != 1).sum())
    tops, bottoms = [], []
    for x in cols:
        rows = np.nonzero(mask[:, x])[0]
        tops.append(int(rows[0]))
        bottoms.append(int(rows[-1]))
        bad += int(rows[-1] - rows[0] + 1 - len(rows))
    for profile in (tops, bottoms):
        runs = _runs(profile)
        for i in range(1, len(runs) - 1):
            step_in = runs[i][0] - runs[i - 1][0]
            step_out = runs[i + 1][0] - runs[i][0]
            if abs(step_in) == 1 and step_in == step_out and runs[i][1] != 2:
                bad += 1
    return bad


def row_holes(mask):
    holes = 0
    for row in mask:
        xs = np.nonzero(row)[0]
        if len(xs):
            holes += int(xs[-1] - xs[0] + 1 - len(xs))
    return holes


def _rotate_point(rotation, w, d, x, y):
    if rotation == 0:
        return x, y
    if rotation == 1:
        return d - y, x
    if rotation == 2:
        return w - x, d - y
    return y, w - x


def measure():
    """Mide lo que la guía fija con números. Devuelve la cantidad de fallos."""
    t = Tally()
    # Sección 3: el rombo.
    ys, xs = np.mgrid[0:128, 0:128]
    formula = (np.abs(xs + 0.5 - 64) / 64.0 + np.abs(ys - 64 + 0.5 - 32) / 32.0 <= 1.0) & (ys >= 64)
    mask = iso.rhombus_mask()
    t.check(np.array_equal(mask, formula) and int(mask.sum()) == 4096, "rombo = fórmula de la sección 3, 4,096 px")
    t.check(np.nonzero(mask[64])[0].tolist() == [63, 64], "fila 64 del rombo: x 63–64")
    for row in (95, 96):
        t.check(int(mask[row].sum()) == 126 and int(np.nonzero(mask[row])[0][0]) == 1, "fila %d del rombo: 126 px (x 1–126)" % row)
    grid = iso.tile_grid()
    t.check(np.array_equal(grid.mask, formula) and np.array_equal(iso.footprint_mask(128, 128, (1, 1)), formula),
            "tile_grid y footprint_mask dan el mismo rombo")
    _dominoes, sizes = np.unique(grid.domino[grid.mask], return_counts=True)
    t.check(len(sizes) == 2048 and set(sizes.tolist()) == {2}, "el rombo son 2,048 dominós de 2 px")
    big = np.zeros((320, 640), dtype=np.int32)
    for i in range(-2, 3):
        for j in range(-2, 3):
            x, y = 256 + (i - j) * 64, 128 + (i + j) * 32
            if 0 <= x <= 512 and 0 <= y <= 256:
                big[y:y + 64, x:x + 128] += mask[64:]
    t.check(int(big[128:192, 256:384].min()) == 1 and int(big[128:192, 256:384].max()) == 1,
            "desplazar el rombo ±64/±32: sin huecos ni encimados")
    # Sección 5: los patrones de pattern.py se repiten cada casilla (medido en una planta de 3×3).
    big_grid = iso.tile_grid((3, 3))
    planks = pattern.planks(big_grid.U, big_grid.V, 4, "u", 1, 32, 3)
    fields = {
        "value_noise": pattern.value_noise(big_grid.u, big_grid.v, 4, 3),
        "blobs": pattern.blobs(big_grid.u, big_grid.v, seed=5),
        "joints": pattern.joints(big_grid.U, big_grid.V, 32, 2),
        "bevel": pattern.bevel(big_grid.U, big_grid.V, 32, 2, 1)[0],
        "planks": planks["piece"] * 4096 + np.floor(planks["along"]) * 2 + planks["seam"],
        "grain": pattern.grain(planks["along"], planks["across"] + planks["index"] * 16, seed=2, length=16, row=4, period=32),
        "grain periódico": pattern.grain(big_grid.U, big_grid.V, seed=1, length=16, row=4, period=64, row_period=16),
        "stamp_points": pattern.stamp_points(big_grid.iu, big_grid.iv, pattern.scatter(20, 4, 64, 5), ((0, 0), (1, 1))),
        "dither": pattern.dither(pattern.blobs(big_grid.u, big_grid.v, seed=2), big_grid.x, big_grid.y, 3),
    }
    for name, field in sorted(fields.items()):
        field = np.asarray(field, dtype=np.float64)
        same = True
        for dx in (64, -64):  # la casilla vecina en +x y en +y
            a = field[:big_grid.height - 32, max(0, -dx):big_grid.width - max(0, dx)]
            b = field[32:, max(0, dx):big_grid.width - max(0, -dx)]
            both = (big_grid.mask[:big_grid.height - 32, max(0, -dx):big_grid.width - max(0, dx)]
                    & big_grid.mask[32:, max(0, dx):big_grid.width - max(0, -dx)])
            same = same and bool(np.allclose(a[both], b[both], atol=1.0e-9))
        t.check(same, "pattern.%s se repite cada casilla en los dos ejes" % name)
    # Sección 6: lienzos y apoyo.
    for size, height, expected in (((1, 1), 22, (128, 128)), ((1, 1), 14, (128, 128)), ((1, 1), 30, (128, 128)),
                                   ((1, 1), 34, (128, 160)), ((1, 1), 40, (128, 160)), ((1, 1), 44, (128, 160)),
                                   ((2, 1), 12, (192, 128)), ((2, 1), 16, (192, 128)), ((2, 1), 22, (192, 160)),
                                   ((2, 1), 26, (192, 160)), ((2, 2), 12, (256, 192)), ((2, 2), 20, (256, 192))):
        t.check(iso.canvas_size(size, height) == expected, "lienzo de %s con alto %d = %s" % (size, height, expected))
    t.check(iso.canvas_size((2, 2), 1, True) == (256, 128), "lienzo de la alfombra = 256×128")
    for size in ((1, 1), (2, 1), (2, 2)):
        for rotation in range(4):
            c = iso.Canvas.furniture(size, 22, rotation)
            w, d = c.world_size
            t.check(c.anchor == (d * 64, c.height - (w + d) * 32 + 32) and (c.width, c.height) == iso.canvas_size((w, d), 22),
                    "apoyo en el centro del rombo de la casilla de anclaje: %s r%d" % (size, rotation))
    # Sección 6: el frente mira a donde dice la guía.
    for rotation, expected in enumerate(((1, -1), (1, 1), (-1, 1), (-1, -1))):
        c = iso.Canvas.furniture((1, 1), 22, rotation)
        c.box(12 / 32.0, 20 / 32.0, 0, 4 / 32.0, 0, 10, WOOD)  # bloque pegado al frente (−y)
        rows, cols = np.nonzero(c.crop(c.alpha))
        got = (1 if cols.mean() > 64 else -1, 1 if rows.mean() > 91 else -1)
        t.check(got == expected, "frente con r%d hacia %s (esperado %s)" % (rotation, got, expected))
    # Cajas: escalera 2:1 en las tres caras y la silueta, tonos exactos, giro = transformar a mano.
    rng = np.random.RandomState(7)
    stairs = 0
    different = 0
    for trial in range(120):
        size = ((1, 1), (2, 1), (2, 2), (1, 2))[trial % 4]
        w, d = size
        boxes = []
        for k in range(1 if trial % 2 else 3):
            bx = sorted(rng.choice(np.arange(0, w * 32 + 1), 2, replace=False) / 32.0)
            by = sorted(rng.choice(np.arange(0, d * 32 + 1), 2, replace=False) / 32.0)
            z0 = int(rng.randint(0, 20))
            boxes.append((bx[0], bx[1], by[0], by[1], z0, z0 + int(rng.randint(1, 36)), (WOOD, BLUE, METAL)[k]))
        for rotation in range(4):
            c = iso.Canvas.furniture(size, 28, rotation)
            for box in boxes:
                c.box(*box)
            if len(boxes) == 1:
                for side in (iso.SIDE_TOP, iso.SIDE_LEFT, iso.SIDE_RIGHT):
                    stairs += stair_errors(c.side == side)
                stairs += stair_errors(c.alpha)
            world = size if rotation % 2 == 0 else (d, w)
            c2 = iso.Canvas.furniture(world, 28, 0)
            for x0, x1, y0, y1, z0, z1, ramp in boxes:
                a0, b0 = _rotate_point(rotation, w, d, x0, y0)
                a1, b1 = _rotate_point(rotation, w, d, x1, y1)
                c2.box(a0, a1, b0, b1, z0, z1, ramp)
            if not np.array_equal(np.array(c.image), np.array(c2.image)):
                different += 1
    t.check(stairs == 0, "escalera 2:1 limpia en caras y silueta de 60 cajas × 4 rotaciones (%d errores)" % stairs)
    t.check(different == 0, "girar el modelo = transformar las coordenadas a mano (%d distintas de 480)" % different)
    red = pal.ramp("c0392b")
    for rotation in range(4):
        c = iso.Canvas.furniture((2, 1), 26, rotation)
        c.box(2 / 32.0, 60 / 32.0, 3 / 32.0, 29 / 32.0, 0, 40, red)
        image = np.array(c.image)
        side = c.crop(c.side)
        for code, amount in ((iso.SIDE_TOP, 0.0), (iso.SIDE_LEFT, 0.25), (iso.SIDE_RIGHT, 0.40)):
            pixels = image[side == code][:, :3]
            colors, counts = np.unique(pixels, axis=0, return_counts=True)
            modal = tuple(int(v) for v in colors[np.argmax(counts)])
            t.check(modal == pal.darken("c0392b", amount) and counts.max() > 0.85 * counts.sum(),
                    "cara con −%d %% exacto, r%d (%s)" % (int(amount * 100), rotation, pal.rgb_to_hex(modal)))
        opaque = image[..., 3] > 0
        t.check(set(np.unique(image[..., 3]).tolist()) <= {0, 255}, "alfa solo 0/255, r%d" % rotation)
        t.check(not (opaque & (image[..., :3] == 0).all(axis=2)).any(), "contorno que no es negro puro, r%d" % rotation)
        outline = tuple(int(v) for v in image[np.nonzero(opaque.any(axis=1))[0][0], np.nonzero(opaque[np.nonzero(opaque.any(axis=1))[0][0]])[0][0], :3])
        t.check(outline == red[pal.OUTLINE], "la silueta lleva el tono de contorno de la rampa, r%d" % rotation)
    t.check(max(pal.ramp("000000")[pal.OUTLINE]) > 0, "el contorno de una base negra no es negro puro")
    # Acabado 'salvaje' (STYLE.md): rampas, contorno de 2 px contra el piso, brillo de arista,
    # esquinas recortadas, línea interior; 'classic' sigue como antes.
    t.check(iso.DEFAULT_STYLE == "salvaje", "el acabado por defecto es 'salvaje'")
    for key, ramp in sorted(pal.STYLE_RAMPS.items()):
        t.check(ramp.declared and pal.light_order_ok(ramp) and min(max(c) for c in ramp) >= pal.MIN_OUTLINE_VALUE,
                "rampa %s: caras declaradas, luz arriba a la izquierda y sin negro puro" % key)
    plain = pal.style_ramp("2e86c1")
    t.check(not plain.declared and plain[pal.LEFT] == pal.darken("2e86c1", 0.25)
            and plain[pal.RIGHT] == pal.darken("2e86c1", 0.40), "style_ramp sin side/shadow: −25 % y −40 % exactos")
    t.check(pal.style_ramp("2e86c1", side="2a70a0").declared, "style_ramp con side= queda con caras declaradas")
    for rotation in range(4):
        c = iso.Canvas.furniture((1, 1), 22, rotation)
        c.box(8 / 32.0, 24 / 32.0, 8 / 32.0, 24 / 32.0, 0, 30, pal.WOOD_ORANGE, name="block")
        c.box(12 / 32.0, 18 / 32.0, 12 / 32.0, 18 / 32.0, 30, 36, pal.CLAY, name="cup")
        image = np.array(c.image)
        shade, alpha, side = c.crop(c.final_shade), c.crop(c.final_alpha), c.crop(c.side)
        raw = c.crop(c.alpha)
        cut = raw & ~alpha
        t.check(int(cut.sum()) == 2 and set(side[cut].tolist()) <= {iso.SIDE_TOP, iso.SIDE_LEFT, iso.SIDE_RIGHT},
                "salvaje: se recortan las 2 puntas de la cara de arriba de la caja de abajo, r%d (%d px)"
                % (rotation, int(cut.sum())))
        lower = np.zeros(raw.shape, dtype=bool)
        lower[:-1] = raw[:-1] & ~raw[1:]
        ground = lower & (side != iso.SIDE_TOP) & (c.crop(c.z) <= iso.GROUND_Z)
        above = np.zeros(raw.shape, dtype=bool)
        above[:-1] = ground[1:]
        t.check(ground.sum() > 20 and (shade[ground] == pal.OUTLINE).all() and (shade[above & raw] == pal.OUTLINE).all(),
                "salvaje: contorno de 2 px donde la silueta da contra el piso, r%d" % rotation)
        fa = c.final_alpha
        inside = fa & np.roll(fa, 1, 0) & np.roll(fa, -1, 0) & np.roll(fa, 1, 1) & np.roll(fa, -1, 1)
        crease = c.edges()["crease_left"] & inside
        t.check(crease.sum() > 10 and bool((c.final_shade[crease] == pal.LIGHT).all()),
                "salvaje: brillo LIGHT en la arista entre la cara de arriba y la izquierda, r%d" % rotation)
        cup = c.select(part="cup") & c.final_alpha
        t.check(bool((cup & (c.final_shade == pal.DEEP)).sum() > 4),
                "salvaje: línea DEEP alrededor de la pieza apoyada sobre otra, r%d" % rotation)
        classic = iso.Canvas.furniture((1, 1), 22, rotation)
        classic.box(8 / 32.0, 24 / 32.0, 8 / 32.0, 24 / 32.0, 0, 30, WOOD)
        classic.finish(style="classic")
        t.check(bool((classic.final_alpha == classic.alpha).all()), "classic: sin esquinas recortadas, r%d" % rotation)
        t.check(not (image[..., 3] > 0)[~alpha].any(), "el PNG no tiene los pixeles recortados, r%d" % rotation)
    # Texturas: cada (a, b) entero de una cara lateral es 1 px; en la de arriba, 2 px (un dominó) o ninguno.
    deformed = 0
    for rotation in range(4):
        c = iso.Canvas.furniture((2, 1), 26, rotation)
        c.box(4 / 32.0, 56 / 32.0, 6 / 32.0, 26 / 32.0, 0, 30, WOOD)
        for code in (iso.SIDE_TOP, iso.SIDE_LEFT, iso.SIDE_RIGHT):
            m = c.side == code
            key = np.floor(c.a[m]).astype(np.int64) * 4096 + np.floor(c.b[m]).astype(np.int64)
            _keys, counts = np.unique(key, return_counts=True)
            wanted = {2} if code == iso.SIDE_TOP else {1}
            deformed += int(set(counts.tolist()) != wanted)
            if code != iso.SIDE_TOP:  # a = columnas de pantalla, b = filas: ni se estira ni se tuerce
                xs_m, a_m = c.X[m], np.floor(c.a[m])
                deformed += int(len(np.unique(a_m - xs_m)) != 1 and len(np.unique(a_m + xs_m)) != 1)
    t.check(deformed == 0, "las coordenadas de textura (a, b) caen 1:1 en pixeles en las 4 rotaciones (%d caras mal)" % deformed)
    # Curvas: sin huecos (formas convexas: ninguna fila con transparentes en medio).
    holes = 0
    for rotation in range(4):
        shapes = []
        c = iso.Canvas.tile(rotation); c.cylinder(0.5, 0.45, 0.3, 0, 40, METAL); shapes.append(c)
        c = iso.Canvas.tile(rotation); c.cylinder(0.5, 0.5, 0.3, 0, 40, METAL, radius_top=0.0); shapes.append(c)
        c = iso.Canvas.tile(rotation); c.cylinder(0.5, 0.5, 0.2, 0, 30, CLAY, radius_top=0.3, open_top=True); shapes.append(c)
        c = iso.Canvas.tile(rotation); c.ellipsoid(0.5, 0.4, 20, 0.4, 0.2, 12, BLUE); shapes.append(c)
        c = iso.Canvas.tile(rotation); c.ellipsoid(0.5, 0.5, 0, 0.3, 0.3, 30, LEAF, clip_z=(0, 30)); shapes.append(c)
        c = iso.Canvas.tile(rotation); c.rounded_box(4 / 32.0, 28 / 32.0, 6 / 32.0, 22 / 32.0, 0, 30, 5 / 32.0, WALL); shapes.append(c)
        c = iso.Canvas.tile(rotation); c.panel((0.3, 0.3, 0), (0.0, 0.5, 0), (0.12, 0.0, 34), DARK_WOOD); shapes.append(c)
        for radius in (0.05, 0.22):
            c = iso.Canvas.tile(rotation); c.sphere(0.5, 0.5, 30, radius, RED); shapes.append(c)
        for radius in (1, 4, 9):
            c = iso.Canvas.tile(rotation); c.soft_box(0.2, 0.8, 0.25, 0.7, 0, 20, radius, BLUE); shapes.append(c)
        for radius in (1, 2, 5):
            c = iso.Canvas.tile(rotation); c.capsule((0.3, 0.3, 4), (0.7, 0.6, 40), radius, METAL); shapes.append(c)
        for c in shapes:
            alpha = c.crop(c.alpha)
            holes += row_holes(alpha) + row_holes(alpha.T) + int(alpha.sum() == 0) + int(c.image is None or c.clipped)
    t.check(holes == 0, "primitivas curvas sin huecos ni recortes en las 4 rotaciones (%d)" % holes)
    # Paredes: tres tramos puestos en fila = una pared de 3 casillas, pixel por pixel (menos las puntas).
    half = iso.WALL_THICKNESS / 2.0
    for axis in ("x", "y"):
        for tall in (True, False):
            height = 120 if tall else iso.WALL_LOW_HEIGHT
            c = wall_piece(axis, tall)
            one = np.array(c.image)
            rows = one.shape[0]
            composite = np.zeros((rows + 64, 200, 4), dtype=np.uint8)
            step = (-64, 32) if axis == "x" else (64, 32)
            start = 128 if axis == "x" else 0
            for k in range(3):
                region = composite[step[1] * k:step[1] * k + rows, start + step[0] * k:start + step[0] * k + 72]
                region[one[..., 3] > 0] = one[one[..., 3] > 0]
            long_wall = iso.Canvas(200, rows + 64, (c.origin[0] + (128 if axis == "x" else 0), c.origin[1]), size=(3, 0),
                                   swap=axis == "x", kind="wall")
            long_wall.box(0, 3, -half, half, 0, height, WALL, tex={iso.BACK: _wall_face(tall)})
            diff = (composite != np.array(long_wall.image)).any(axis=2)
            inner = diff[:, 12:188]
            t.check(not inner.any(), "3 tramos de pared %s %s = una pared de 3 (%d px distintos lejos de las puntas)"
                    % ("alta" if tall else "baja", axis, int(inner.sum())))
            t.check((c.width, c.height) == (72, 160 if tall else 64) and c.anchor == (36.0, c.height - 18.0),
                    "pared %s %s: lienzo 72×%d y apoyo (36, %d)" % ("alta" if tall else "baja", axis, c.height, c.height - 18))
    print("MEDIDAS: %d bien, %d mal" % (t.good, len(t.bad)))
    return len(t.bad)


# ---------------------------------------------------------------------- check.py detecta fallos

def _silent_check(directory):
    """Corre check.py sin imprimir. Devuelve (código, líneas de FALLA y AVISO)."""
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        code = check.run(directory)
    return code, [line for line in buffer.getvalue().splitlines() if line.startswith(("FALLA", "AVISO"))]


def negative_tests(out_dir):
    """Rompe a propósito una cosa por vez en una copia de los sprites de prueba y exige que
    check.py la detecte con el mensaje esperado. Devuelve la cantidad de casos NO detectados."""
    names = [n for n in os.listdir(out_dir) if n.endswith(".json") or (n.endswith(".png") and not n.startswith("sheet_"))]
    work = tempfile.mkdtemp(prefix="quincena_sprites_negative_")
    left = pal.darken(WOOD.base_hex, 0.25)
    right = pal.darken(WOOD.base_hex, 0.40)
    grid = iso.tile_grid()

    def edit(name, change):
        def apply(directory):
            path = os.path.join(directory, name)
            arr = np.array(Image.open(path))
            result = change(arr)
            Image.fromarray(arr if result is None else result).save(path)
        return apply

    def edit_all_floors(change):
        def apply(directory):
            for variant in range(4):
                edit("floor_test_%d.png" % variant, change)(directory)
        return apply

    def manifest(name, **changes):
        def apply(directory):
            path = os.path.join(directory, "manifest_selftest.json")
            with open(path, "r") as handle:
                data = json.load(handle)
            for entry in data["sprites"]:
                if entry["file"] == name:
                    entry.update(changes)
            with open(path, "w") as handle:
                json.dump(data, handle)
        return apply

    def recolor(arr, old, new):
        arr[(arr[..., :3] == np.array(old, dtype=np.uint8)).all(axis=2) & (arr[..., 3] > 0), :3] = new

    def set_alpha(arr, value):
        arr[90:94, 90:94, 3] = value

    def blacken(arr):
        rows, cols = np.nonzero(arr[..., 3] > 0)
        arr[rows[:30], cols[:30], :3] = 0

    def brighten(arr):
        opaque = arr[..., 3] > 0
        arr[..., :3][opaque] = np.clip(arr[..., :3][opaque].astype(np.int32) + 2, 0, 255)

    def tint(arr):
        opaque = arr[..., 3] > 0
        arr[..., 0][opaque] = np.clip(arr[..., 0][opaque].astype(np.int32) + 3, 0, 255)
        arr[..., 2][opaque] = np.clip(arr[..., 2][opaque].astype(np.int32) - 3, 0, 255)

    def ring(arr):
        arr[grid.mask & (grid.iu == 0), :3] = (200, 190, 150)

    def seam_line(arr):
        arr[grid.mask & (grid.iu >= 62), :3] = (240, 235, 220)

    def gradient(arr):
        factor = 0.85 + 0.3 * grid.U / 64.0
        arr[..., :3][grid.mask] = np.clip(arr[..., :3][grid.mask] * factor[grid.mask][:, None], 0, 255).astype(np.uint8)

    def noise(arr):
        rng = np.random.RandomState(1)
        inner = grid.mask & (grid.iu > 1) & (grid.iu < 62) & (grid.iv > 1) & (grid.iv < 62)
        dark = inner & (rng.rand(*grid.mask.shape) < 0.5) & (((grid.x + grid.y) % 2) == 0)
        arr[dark, :3] = (arr[dark, :3] * 0.9).astype(np.uint8)

    def hole(arr):
        arr[100, 64, 3] = 0

    def gap(arr):
        arr[:, 64:66, 3] = 0

    def rebuilt_wall(name, axis, tall, height, joins=True, start=0.0, color=None):
        def apply(directory):
            c = iso.Canvas.wall(axis, tall, joins=joins)
            half = iso.WALL_THICKNESS / 2.0
            c.box(start, 1, -half, half, 0, height, WALL if color is None else pal.ramp(color))
            c.image.save(os.path.join(directory, name))
        return apply

    cases = [
        ("alfa 128 en un mueble", edit("box_test_r1.png", lambda a: set_alpha(a, 128)), "FALLA", "alfa"),
        ("alfa 254 en un piso", edit("floor_test_0.png", lambda a: set_alpha(a, 254)), "FALLA", "alfa"),
        ("PNG sin canal alfa", lambda d: Image.open(os.path.join(d, "box_test_r1.png")).convert("RGB").save(
            os.path.join(d, "box_test_r1.png")), "FALLA", "RGBA"),
        ("negro puro en el contorno", edit("box_test_r1.png", blacken), "FALLA", "negro"),
        ("nombre que no es snake_case", lambda d: os.rename(os.path.join(d, "cylinder_test.png"),
                                                              os.path.join(d, "Cylinder-Test.png")), "FALLA", "snake_case"),
        ("rombo corrido 1 px a la derecha", edit("floor_test_1.png", lambda a: np.roll(a, 1, axis=1)), "FALLA", "rombo"),
        ("rombo corrido 1 px hacia abajo", edit("floor_test_1.png", lambda a: np.roll(a, 1, axis=0)), "FALLA", "rombo"),
        ("un hueco en un piso", edit("floor_test_2.png", hole), "FALLA", "rombo"),
        ("variante 2 niveles más clara", edit("floor_test_3.png", brighten), "FALLA", "brillo"),
        ("variante con otro tinte", edit("floor_test_3.png", tint), "FALLA", "color medio"),
        ("borde distinto en una variante", edit("floor_test_1.png", ring), "FALLA", "borde"),
        ("línea clara en un lado de la casilla", edit_all_floors(seam_line), "FALLA", "costura"),
        ("degradado que no se repite", edit_all_floors(gradient), "FALLA", "salto"),
        ("ruido suelto de 1 px", edit_all_floors(noise), "AVISO", "sueltos"),
        ("falta una variante", lambda d: os.remove(os.path.join(d, "floor_test_3.png")), "AVISO", "variantes"),
        ("mueble bajado 30 px", edit("box_test_r2.png", lambda a: np.roll(a, 30, axis=0)), "FALLA", "planta"),
        ("mueble corrido 40 px", edit("box_test_r2.png", lambda a: np.roll(a, 40, axis=1)), "FALLA", "planta"),
        ("lienzo de otro tamaño", lambda d: Image.open(os.path.join(d, "box_test_r0.png")).crop((0, 0, 192, 128)).save(
            os.path.join(d, "box_test_r0.png")), "FALLA", "lienzo"),
        ("cara izquierda −27 %", edit("box_test_r3.png", lambda a: recolor(a, left, pal.darken(WOOD.base_hex, 0.27))),
         "FALLA", "cara left"),
        ("cara derecha −44 %", edit("box_test_r3.png", lambda a: recolor(a, right, pal.darken(WOOD.base_hex, 0.44))),
         "FALLA", "cara right"),
        ("cara de arriba con otro base", edit("box_test_r3.png", lambda a: recolor(a, WOOD[pal.BASE], (155, 113, 73))),
         "FALLA", "cara top"),
        ("el motor marcó recorte", manifest("box_test_r1.png", clipped=True), "FALLA", "recorte"),
        ("apoyo en otro lugar", manifest("box_test_r1.png", anchor=[64, 64]), "FALLA", "apoyo"),
        ("caja fuera de la rejilla", manifest("box_test_r1.png", off_grid=["leg"]), "FALLA", "rejilla"),
        ("mueble flotando", manifest("box_test_r1.png", min_z=12.0), "FALLA", "piso"),
        ("textura que tapa la cara", manifest("box_test_r1.png", flat_faces=[
            {"base": WOOD.base_hex, "top": 0, "top_total": 900, "top_plain": 100}]), "FALLA", "lisa"),
        ("sombra fuera de la planta", edit("box_test_r1_shadow.png", lambda a: a.__setitem__(
            (slice(4, 12), slice(4, 12)), (26, 28, 38, 255))), "FALLA", "sombra"),
        ("pared con contorno en los extremos", rebuilt_wall("wall_test_tall_x.png", "x", True, 120, joins=False),
         "FALLA", "empalme"),
        ("pared con un hueco de 2 px", edit("wall_test_tall_y.png", gap), "FALLA", "empalme"),
        ("pared que no llega al extremo", rebuilt_wall("wall_test_tall_y.png", "y", True, 120, start=2 / 32.0),
         "FALLA", "empalme"),
        ("pared alta de 100 px", rebuilt_wall("wall_test_tall_y.png", "y", True, 100), "FALLA", "alto"),
        ("pared baja de otro color", rebuilt_wall("wall_test_low_x.png", "x", False, 20, color="c8c0b4"),
         "FALLA", "cara de arriba"),
        ("pared baja de 30 px", rebuilt_wall("wall_test_low_x.png", "x", False, 30), "FALLA", "alto"),
        ("lado declarado de otro tono", edit("style_test_r1.png", lambda a: recolor(
            a, pal.WOOD_ORANGE[pal.LEFT], pal.darken(pal.WOOD_ORANGE.base_hex, 0.25))), "FALLA", "lado declarado"),
        ("caras declaradas con la luz al revés", manifest("style_test_r1.png", flat_faces=[
            {"base": "df823d", "declared": True, "faces": {"top": "df823d", "left": "743b0e", "right": "c26b24"},
             "top": 1, "left": 1, "right": 1}]), "FALLA", "luz arriba"),
        ("pared en otro lienzo", edit("wall_test_low_y.png", lambda a: np.pad(a, ((0, 0), (0, 8), (0, 0)))),
         "FALLA", "lienzo"),
    ]
    missed = 0
    try:
        for label, breaker, level, needle in cases:
            folder = os.path.join(work, "case")
            if os.path.isdir(folder):
                shutil.rmtree(folder)
            os.makedirs(folder)
            for name in names:
                shutil.copy(os.path.join(out_dir, name), os.path.join(folder, name))
            breaker(folder)
            code, lines = _silent_check(folder)
            hit = [line for line in lines if line.startswith(level) and needle in line]
            if not hit or (level == "FALLA" and code != 1):
                missed += 1
                print("NO DETECTA  %s (esperaba %s con «%s»; salió: %s)" % (label, level, needle, " | ".join(lines)[:300]))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("PRUEBAS NEGATIVAS de check.py: %d de %d fallos puestos a propósito detectados" % (len(cases) - missed, len(cases)))
    return missed


def main():
    parser = argparse.ArgumentParser(description="Prueba propia del motor de sprites.")
    parser.add_argument("--out", default=None, help="carpeta de salida (por defecto una temporal)")
    args = parser.parse_args()
    out_dir = args.out or os.path.join(tempfile.gettempdir(), "quincena_sprites_selftest")
    failed = measure()
    iso.reset_registry()
    files = []
    files += build_boxes(out_dir)
    files += build_chairs(out_dir)
    files += build_curves(out_dir)
    files += build_floor(out_dir)
    files += build_walls(out_dir)
    files += build_style(out_dir)
    iso.write_manifest(out_dir, "selftest")
    sheets = build_sheets(out_dir)
    print("%d sprites y %d hojas en %s" % (len(files), len(sheets), out_dir))
    status = check.run(out_dir)
    failed += negative_tests(out_dir)
    if failed:
        print("PRUEBA DEL MOTOR: FALLA (%d)" % failed)
    return 1 if (status or failed) else 0


if __name__ == "__main__":
    sys.exit(main())
