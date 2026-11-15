# Objetos de pared (docs/sprites_128.md, sección 7) en el estilo de tools/sprites/STYLE.md: cuadro
# (3 dibujos), reloj, pizarra, televisor (la pantalla de presentaciones) y aire acondicionado, para pared _x y _y.
#
#   painting_x / _y                    cuadro con marco de madera naranja y un paisaje
#   painting_abstract_x / _y           el mismo marco con bloques de color
#   painting_sea_x / _y                el mismo marco con mar y un velero
#   wall_clock_x / _y                  reloj redondo de aro negro, marcas y agujas a las 10:10
#   whiteboard_x / _y                  pizarra blanca con marco de aluminio, garabatos y bandeja
#   presentation_screen_x / _y         televisor negro apagado (reflejos) sobre una repisa de madera
#   air_conditioner_x / _y             split blanco de 8 px de fondo, rejilla arriba, salida y luz
#   _sheets/wall_items.png             hoja de contacto (no es arte del juego)
#   sheet_wall_items.png               los objetos colgados en una esquina de paredes altas
#
# Lienzo 64×128 (Canvas.wall_item): x de 0 a 1 a lo largo del borde, apoyo en el punto medio del
# borde en el piso (32, 112), el mismo punto que el apoyo de un tramo de pared. El objeto sale de
# la cara de la pared (y = medio grosor, 4 px) hacia la casilla y su base va a 48 px de sprite
# (24 del mundo, WALL_ITEM_BASE_PX del juego); el alto es el `height` de data/furniture.json × 2.
# Solo se ve la cara de adentro de las paredes altas del fondo: el juego no los dibuja en la cara
# de atrás, y en las paredes bajas los achica pegados abajo (no hay versión baja).
import os

import numpy as np

import iso
import palette as pal
import sheet
from pieces import walls

FURNITURE = iso.load_json("data/furniture.json")
_ITEMS = FURNITURE["items"] if "items" in FURNITURE else FURNITURE


def item_data(item_id):
    if isinstance(_ITEMS, dict):
        return _ITEMS[item_id]
    return next(entry for entry in _ITEMS if entry.get("id") == item_id)


BASE = iso.WALL_ITEM_BASE  # 48
FACE = walls.HALF  # la cara de la pared, en casillas desde la línea del borde (4 px)
PX = 1 / 64.0  # 1 px de sprite a lo largo de y (el fondo del objeto)


def tall(item_id):
    """Alto del objeto en px de sprite (el `height` del juego × 2)."""
    return iso.world_px(item_data(item_id)["height"])


# En un tramo _x el modelo corre de derecha a izquierda en pantalla: los dibujos se espejan para
# que se lean igual en las dos paredes. La pieza de turno lo fija con set_axis.
_MIRROR = [False]


def set_axis(axis):
    _MIRROR[0] = axis == "x"


def front(ctx, x0, z0, x1):
    """Coordenadas de la cara de adelante en px, vista de frente: a de izquierda a derecha desde el
    borde del objeto (x0–x1 a lo largo del tramo), b hacia arriba desde z0."""
    a = (x1 - ctx.x) if _MIRROR[0] else (ctx.x - x0)
    return np.floor(a * 64.0 + 1.0e-6), np.floor(ctx.z - z0 + 1.0e-6)


# ---------------------------------------------------------------------------- rampas

# Marco de madera naranja (STYLE.md) y los colores de los dibujos como tonos agregados.
FRAME = pal.style("wood_orange", name="painting")
SKY = FRAME.add("8fc9e4")
SKY_LIGHT = FRAME.add("b9def0")
SUN = FRAME.add("f6d36b")
HILL = FRAME.add("9ecc42")
HILL_DARK = FRAME.add("648132")
TRUNK = FRAME.add("743b0e")
SEA = FRAME.add("3d90c0")
SEA_LIGHT = FRAME.add("6dacce")
SAND = FRAME.add("e8cf98")
SAIL = FRAME.add("f4f1e8")
RED = FRAME.add("c03d43")
YELLOW = FRAME.add("eec04a")
BLUE = FRAME.add("3d6fb0")
CREAM = FRAME.add("efe6d2")
INK = FRAME.add("2b2526")

CLOCK = pal.style_ramp("f0ece0", side="ddd8ca", shadow="cec8b8", outline="1c1c1c", deep="3a3838",
                       light="fbf9f2", name="clock")
CLOCK_RIM = CLOCK.add("313030")
CLOCK_RIM_LIGHT = CLOCK.add("4f4f4f")
CLOCK_HAND = CLOCK.add("222020")
CLOCK_RED = CLOCK.add("c03d43")
CLOCK_TICK = CLOCK.add("5c5850")

BOARD = pal.style_ramp("f7f7f2", side="e6e7e2", shadow="d9dad5", outline="3d3b44", deep="77888c",
                       light="ffffff", name="whiteboard")
BOARD_ALU = BOARD.add("b7c0c6")
BOARD_ALU_DARK = BOARD.add("8d989f")
MARKER_BLUE = BOARD.add("3d6fb0")
MARKER_RED = BOARD.add("c03d43")
MARKER_GREEN = BOARD.add("4c8a3a")

# Televisor (en lugar de la pantalla de presentaciones, como el de la referencia): plástico negro con
# filo gris azulado, pantalla apagada con reflejos en diagonal, sobre una repisa de madera naranja.
TV = pal.style("plastic_black", name="presentation_screen")
TV_RIM = TV.add("4a4a5c")  # filo del marco
TV_RIM_DARK = TV.add("2c2c36")
TV_GLASS = TV.add("1b1b1d")  # pantalla apagada
TV_SHINE = TV.add("2f2f35")  # reflejo ancho
TV_SHINE2 = TV.add("3c3c44")  # reflejo angosto
TV_LED = TV.add("c03d43")
TV_BUTTON = TV.add("5a5a68")
SHELF = pal.style("wood_orange", name="tv_shelf")

# Split como el de la referencia: frente blanco verdoso, tapa gris con un panel claro al final,
# rejilla negra de salida abajo (debajo del frente, que sobresale), luz roja y tapa del extremo
# con un rectángulo hundido.
AIR = pal.style_ramp("eef4f2", side="dce6e3", shadow="cbd6d3", outline="2a2a30", deep="6f7a80",
                     light="ffffff", name="air_conditioner")
AIR_TOP = AIR.add("b4bbbf")  # tapa gris
AIR_TOP_EDGE = AIR.add("c9cfd2")  # filo redondeado entre la tapa y el frente
AIR_PANEL = AIR.add("cfd5d8")  # panel claro de la tapa, al final
AIR_PANEL_EDGE = AIR.add("9ba3a8")
AIR_GRILLE = AIR.add("1e1e24")  # rejilla de salida
AIR_GRILLE_LIT = AIR.add("4a4a52")
AIR_LED = AIR.add("c03d43")  # luz roja
AIR_LOGO = AIR.add("9aa4ac")
AIR_CAP_LINE = AIR.add("aab4b6")  # rectángulo hundido de la tapa del extremo


# ---------------------------------------------------------------------------- cuadro

PAINT_X = (0.25, 0.75)  # 32 px a lo largo
PAINT_DEPTH = 3 * PX
PAINT_BORDER = 3  # marco de 3 px


def _landscape(a, b, w, h, index):
    sky = b >= h * 0.45
    index = np.where(sky, np.where(b >= h * 0.78, SKY_LIGHT, SKY), index)
    sun = (a - w * 0.72) ** 2 + (b - h * 0.76) ** 2 <= 9.5
    index = np.where(sun, SUN, index)
    far = b < h * 0.45 + 3.0 * np.sin(a / 4.0 + 1.0) + 1.0
    index = np.where(far, HILL_DARK, index)
    near = b < h * 0.30 + 2.5 * np.sin(a / 6.0 + 3.5)
    index = np.where(near, HILL, index)
    # Un árbol a la izquierda: tronco y copa.
    trunk = (a >= 7) & (a < 9) & (b >= 3) & (b < 8)
    crown = (a - 8) ** 2 / 9.0 + (b - 10) ** 2 / 9.0 <= 1.0
    index = np.where(crown, HILL_DARK, index)
    return np.where(trunk, TRUNK, index)


def _abstract(a, b, w, h, index):
    index = np.where(np.ones_like(a, dtype=bool), CREAM, index)
    index = np.where((a < 10) & (b >= 8), RED, index)
    index = np.where((a >= 18) & (b < 6), BLUE, index)
    index = np.where((a >= 21) & (b >= 13), YELLOW, index)
    lines = (a == 10) | (a == 11) | (a == 20) | (b == 6) | (b == 7) | ((b == 12) & (a >= 11))
    return np.where(lines, INK, index)


def _sea(a, b, w, h, index):
    index = np.where(b >= h * 0.42, np.where(b >= h * 0.75, SKY_LIGHT, SKY), index)
    water = b < h * 0.42
    index = np.where(water, np.where(np.mod(a + 2 * b, 9) < 2, SEA_LIGHT, SEA), index)
    index = np.where(b < 3 + (a > w * 0.6) * 1.0, SAND, index)
    # Velero: casco y vela triangular.
    hull = (b >= 7) & (b < 9) & (a >= 8 + (b - 7)) & (a < 18 - (b - 7))
    hull = (b >= 7) & (b < 9) & (a >= 8) & (a < 18) & ~((b == 7) & ((a == 8) | (a == 17)))
    sail = (b >= 9) & (b < 18) & (a >= 13) & (a < 13 + (18 - b) * 0.7)
    mast = (a == 12) & (b >= 9) & (b < 19)
    index = np.where(sail, SAIL, index)
    index = np.where(hull, RED, index)
    return np.where(mast, TRUNK, index)


PAINTINGS = {"": _landscape, "abstract": _abstract, "sea": _sea}


def painting_face(art):
    height = tall("painting")
    width = (PAINT_X[1] - PAINT_X[0]) * 64.0

    def tex(ctx):
        a, b = front(ctx, PAINT_X[0], BASE, PAINT_X[1])
        index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(a.shape, ctx.base)
        inner = (a >= PAINT_BORDER) & (a < width - PAINT_BORDER) & (b >= PAINT_BORDER) & (b < height - PAINT_BORDER)
        drawn = art(a - PAINT_BORDER, b - PAINT_BORDER, width - 2 * PAINT_BORDER, height - 2 * PAINT_BORDER, index)
        index = np.where(inner, drawn, index)
        # Filo del marco: claro arriba y a la izquierda (la luz), sombra en el borde de adentro.
        lit = ~inner & ((b == height - 1) | (a == 0))
        index = np.where(lit, pal.LIGHT, index)
        shade = inner & ((b == height - PAINT_BORDER - 1) | (a == PAINT_BORDER))
        return np.where(shade, np.where(np.isin(drawn, (SKY, SKY_LIGHT, CREAM)), SKY if art is not _abstract else CREAM,
                                        drawn), index)
    return tex


def painting(axis, art=""):
    c = iso.Canvas.wall_item(axis)
    c.box(PAINT_X[0], PAINT_X[1], FACE, FACE + PAINT_DEPTH, BASE, BASE + tall("painting"), FRAME,
          tex={iso.BACK: painting_face(PAINTINGS[art])}, name="painting", flat=False)
    return c


# ---------------------------------------------------------------------------- reloj

CLOCK_D = 16  # diámetro en px (a lo largo y de alto)
CLOCK_X0 = 0.5 - CLOCK_D / 128.0
CLOCK_DEPTH = 3 * PX


def clock_face(ctx):
    a, b = front(ctx, CLOCK_X0, BASE, CLOCK_X0 + CLOCK_D / 64.0)
    r = CLOCK_D / 2.0
    da = a + 0.5 - r
    db = b + 0.5 - r
    dist = np.sqrt(da * da + db * db)
    index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(a.shape, ctx.base)
    index = np.where(dist >= r - 2.0, CLOCK_RIM, index)
    index = np.where((dist >= r - 2.0) & (da < 0) & (db > 0), CLOCK_RIM_LIGHT, index)
    # Marcas de las 12, 3, 6 y 9: un pixel junto al aro.
    ticks = ((a == r) & ((b == 2) | (b == CLOCK_D - 3))) | ((b == r) & ((a == 2) | (a == CLOCK_D - 3)))
    index = np.where(ticks, CLOCK_TICK, index)
    # Agujas a las 10:10: la corta hacia arriba a la izquierda, la larga hacia arriba a la derecha.
    hour = (da <= 0) & (db >= 0) & (np.abs(db - (-da) * 0.6) < 0.8) & (dist < 3.6)
    minute = (da >= 0) & (db >= 0) & (np.abs(db - da * 0.75) < 0.8) & (dist < 5.2)
    index = np.where(hour | minute, CLOCK_HAND, index)
    second = (np.abs(da) < 0.5) & (db < 0) & (dist < 5.0)
    index = np.where(second, CLOCK_RED, index)
    return np.where(dist < 0.9, CLOCK_RED, index)


def wall_clock(axis):
    """Reloj redondo: filas de 1 px de alto, cada una tan ancha como el círculo en esa fila."""
    c = iso.Canvas.wall_item(axis)
    z0 = BASE + (tall("wall_clock") - CLOCK_D) // 2
    r = CLOCK_D / 2.0
    part = None
    for row in range(CLOCK_D):
        dz = row + 0.5 - r
        half = int(round(np.sqrt(max(r * r - dz * dz, 0.0))))
        if half <= 0:
            continue
        x0 = CLOCK_X0 + (r - half) / 64.0
        x1 = CLOCK_X0 + (r + half) / 64.0
        pid = c.box(x0, x1, FACE, FACE + CLOCK_DEPTH, z0 + row, z0 + row + 1, CLOCK,
                    tex={iso.BACK: lambda ctx, z0=z0: clock_face_at(ctx, z0)},
                    name="clock" if part is None else None, part=part, flat=False)
        part = pid if part is None else part
    # El aro se ve también de canto: pintar las caras de arriba y de los lados con el aro.
    rim = c.select(part=part) & ~c.select(part=part, face=iso.BACK)
    c.paint(rim, CLOCK_RIM, CLOCK)
    return c


def clock_face_at(ctx, z0):
    class _Shift(object):
        pass
    shifted = _Shift()
    shifted.x = ctx.x
    shifted.z = ctx.z - (z0 - BASE)
    shifted.base = ctx.base
    return clock_face(shifted)


# ---------------------------------------------------------------------------- pizarra

BOARD_X = (6 / 64.0, 58 / 64.0)  # 52 px a lo largo
BOARD_DEPTH = 2 * PX
TRAY_H = 2


def board_face(ctx):
    a, b = front(ctx, BOARD_X[0], BASE, BOARD_X[1])
    width = np.floor((BOARD_X[1] - BOARD_X[0]) * 64.0)
    height = tall("whiteboard")
    index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(a.shape, ctx.base)
    # Título subrayado y lista, en azul.
    title = (b == height - 6) & (a >= 5) & (a < 22) & (np.mod(a, 4) != 3)
    under = (b == height - 8) & (a >= 5) & (a < 24)
    items = np.zeros(a.shape, dtype=bool)
    for k in range(3):
        row = height - 12 - 4 * k
        items |= (b == row) & (a >= 7) & (a < 18 - 3 * k) & (np.mod(a, 5) != 4)
        items |= (b == row) & (a == 5)
    index = np.where(title | under | items, MARKER_BLUE, index)
    # Un gráfico a la derecha: ejes negros y una línea roja que sube; un círculo verde.
    axes = ((a == 29) & (b >= 6) & (b < 22)) | ((b == 6) & (a >= 29) & (a < 46))
    index = np.where(axes, CLOCK_HAND_BOARD, index)
    xs = a - 30
    curve = (xs >= 0) & (xs < 15) & (np.abs(b - (8 + np.floor(xs * 0.9))) < 0.6)
    index = np.where(curve, MARKER_RED, index)
    ring = np.abs(np.sqrt((a - 41.5) ** 2 + (b - (height - 7.5)) ** 2) - 3.0) < 0.6
    index = np.where(ring, MARKER_GREEN, index)
    # Marco de aluminio de 2 px: claro arriba y a la izquierda.
    frame = (a < 2) | (a >= width - 2) | (b < 2) | (b >= height - 2)
    lit = frame & ((b >= height - 1) | (a < 1))
    index = np.where(frame, BOARD_ALU_DARK, index)
    return np.where(lit, BOARD_ALU, index)


CLOCK_HAND_BOARD = BOARD.add("2b2526")


def whiteboard(axis):
    c = iso.Canvas.wall_item(axis)
    height = tall("whiteboard")
    c.box(BOARD_X[0], BOARD_X[1], FACE, FACE + BOARD_DEPTH, BASE, BASE + height, BOARD,
          tex={iso.BACK: board_face}, name="board")
    # Bandeja para los marcadores, abajo, un poco más afuera, con dos marcadores encima.
    c.box(BOARD_X[0] + 4 / 64.0, BOARD_X[1] - 4 / 64.0, FACE, FACE + 5 * PX, BASE - TRAY_H, BASE, BOARD,
          name="tray")
    tray = c.select(part=c.part_id("tray"))
    c.paint(tray & ~c.select(part=c.part_id("tray"), face=iso.TOP), pal.RIGHT, BOARD)
    c.paint(c.select(part=c.part_id("tray"), face=iso.TOP), BOARD_ALU, BOARD)
    c.box(19 / 64.0, 24 / 64.0, FACE + 2 * PX, FACE + 4 * PX, BASE, BASE + 2, BOARD, name="marker_blue")
    c.paint(c.select(part=c.part_id("marker_blue")), MARKER_BLUE, BOARD)
    c.box(27 / 64.0, 32 / 64.0, FACE + 2 * PX, FACE + 4 * PX, BASE, BASE + 2, BOARD, name="marker_red")
    c.paint(c.select(part=c.part_id("marker_red")), MARKER_RED, BOARD)
    return c


# ---------------------------------------------------------------------------- televisor

TV_X = (16 / 64.0, 60 / 64.0)  # 44 px a lo largo (el fondo de la repisa lo corre 12 px)
TV_Y = (FACE + 2 * PX, FACE + 5 * PX)  # 3 px de grueso, despegado 2 px de la pared
SHELF_X = (14 / 64.0, 62 / 64.0)
SHELF_DEPTH = 8 * PX
SHELF_H = 2
FEET = 2  # patitas entre la repisa y el televisor
TV_BEZEL = 3
# Más alto que el `height` del juego (14 → 28 px): como el de la referencia, 44 × 32 px.
TV_HEIGHT = 32


def tv_face(ctx):
    z0 = BASE + SHELF_H + FEET
    a, b = front(ctx, TV_X[0], z0, TV_X[1])
    width = np.floor((TV_X[1] - TV_X[0]) * 64.0)
    height = TV_HEIGHT
    index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(a.shape, ctx.base)
    # Filo gris en el borde de afuera, claro arriba y a la izquierda (la luz).
    outer = (a == 0) | (a == width - 1) | (b == 0) | (b == height - 1)
    index = np.where(outer, np.where((b == height - 1) | (a == 0), TV_RIM, TV_RIM_DARK), index)
    # Pantalla apagada con su borde hundido y dos reflejos en diagonal.
    glass = (a >= TV_BEZEL) & (a < width - TV_BEZEL) & (b >= TV_BEZEL) & (b < height - TV_BEZEL)
    ga = a - TV_BEZEL
    gb = b - TV_BEZEL
    d = np.floor(ga - gb * 1.2)
    wide = (d >= -4) & (d < 5)
    thin = (d >= 9) & (d < 11)
    screen = np.where(wide, TV_SHINE, np.where(thin, TV_SHINE2, TV_GLASS))
    edge = glass & ((a == TV_BEZEL) | (b == height - TV_BEZEL - 1))
    index = np.where(glass, np.where(edge, pal.OUTLINE, screen), index)
    # Luz roja abajo a la izquierda y tres botones en el marco izquierdo.
    index = np.where((b == 1) & (a >= 2) & (a < 4), TV_LED, index)
    buttons = (a == 1) & (b >= 4) & (b < 9) & (np.mod(b, 2) == 0)
    return np.where(buttons, TV_BUTTON, index)


def presentation_screen(axis):
    """Televisor sobre una repisa de pared (la pieza del juego sigue siendo presentation_screen)."""
    c = iso.Canvas.wall_item(axis)
    c.box(SHELF_X[0], SHELF_X[1], FACE, FACE + SHELF_DEPTH, BASE, BASE + SHELF_H, SHELF, name="shelf")
    z0 = BASE + SHELF_H
    feet = None
    for x in (TV_X[0] + 5 / 64.0, TV_X[1] - 8 / 64.0):
        pid = c.box(x, x + 3 / 64.0, TV_Y[0], TV_Y[1], z0, z0 + FEET, TV, name="feet" if feet is None else None,
                    part=feet)
        feet = pid if feet is None else feet
    c.box(TV_X[0], TV_X[1], TV_Y[0], TV_Y[1], z0 + FEET, z0 + FEET + TV_HEIGHT, TV,
          tex={iso.BACK: tv_face}, name="tv", flat=False)
    return c


# ---------------------------------------------------------------------------- aire acondicionado

AIR_X = (16 / 64.0, 60 / 64.0)  # 44 px a lo largo: largo y bajo (el fondo lo corre 14 px)
AIR_DEPTH = 10 * PX
GRILLE_DEPTH = 7 * PX  # la rejilla queda 3 px más adentro que el frente
GRILLE_H = 6  # alto de la rejilla, abajo
GRILLE_X = (AIR_X[0] + 3 / 64.0, AIR_X[1] - 5 / 64.0)


def air_face(ctx):
    a, b = front(ctx, AIR_X[0], BASE + GRILLE_H, AIR_X[1])
    width = np.floor((AIR_X[1] - AIR_X[0]) * 64.0)
    height = tall("air_conditioner") - GRILLE_H
    index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(a.shape, ctx.base)
    # Arriba el filo redondeado: una fila más clara.
    index = np.where(b == height - 1, pal.LIGHT, index)
    # Marca gris arriba a la izquierda y luz roja abajo a la derecha (2×2).
    index = np.where((b >= height - 5) & (b < height - 3) & (a >= 4) & (a < 8), AIR_LOGO, index)
    led = (b >= 3) & (b < 5) & (a >= width - 13) & (a < width - 11)
    return np.where(led, AIR_LED, index)


def air_top(ctx):
    across = np.floor((ctx.y - FACE) * 64.0 + 1.0e-6)  # 0 junto a la pared, 9 al frente
    along = np.floor((ctx.x - AIR_X[0]) * 64.0 + 1.0e-6)
    if _MIRROR[0]:
        along = np.floor((AIR_X[1] - AIR_X[0]) * 64.0) - 1 - along
    index = np.full(across.shape, AIR_TOP)
    index = np.where(across >= 8, AIR_TOP_EDGE, index)
    # Panel claro al final de la derecha, con su borde.
    width = np.floor((AIR_X[1] - AIR_X[0]) * 64.0)
    panel = (along >= width - 12) & (along < width - 2) & (across >= 2) & (across < 7)
    edge = panel & ((along == width - 12) | (across == 6))
    index = np.where(panel, AIR_PANEL, index)
    return np.where(edge, AIR_PANEL_EDGE, index)


def air_end(ctx):
    # Tapa del extremo: rectángulo hundido (1 px) dentro de un borde de 2 px.
    along = np.floor((ctx.y - FACE) * 64.0 + 1.0e-6)
    up = np.floor(ctx.z - BASE - GRILLE_H + 1.0e-6)
    height = tall("air_conditioner") - GRILLE_H
    index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(along.shape, ctx.base)
    box = (along >= 2) & (along < 8) & (up >= 2) & (up < height - 3)
    ring = box & ((along == 2) | (along == 7) | (up == 2) | (up == height - 4))
    return np.where(ring, AIR_CAP_LINE, index)


def air_grille(ctx):
    a, b = front(ctx, GRILLE_X[0], BASE, GRILLE_X[1])
    # Rejilla de aletas: filas alternas con un punto claro cada 2 px (como un tejido).
    lit = (np.mod(a + b, 2) == 0) & (np.mod(b, 2) == 1)
    return np.where(lit, AIR_GRILLE_LIT, AIR_GRILLE)


def air_conditioner(axis):
    c = iso.Canvas.wall_item(axis)
    top = BASE + tall("air_conditioner")
    c.box(GRILLE_X[0], GRILLE_X[1], FACE, FACE + GRILLE_DEPTH, BASE, BASE + GRILLE_H, AIR,
          tex={iso.BACK: air_grille}, name="grille", flat=False)
    c.paint(c.select(part=c.part_id("grille")) & ~c.select(part=c.part_id("grille"), face=iso.BACK), AIR_GRILLE, AIR)
    c.box(AIR_X[0], AIR_X[1], FACE, FACE + AIR_DEPTH, BASE + GRILLE_H, top, AIR,
          tex={iso.BACK: air_face, iso.TOP: air_top, iso.X0: air_end, iso.X1: air_end}, name="air_conditioner",
          flat=False)
    return c


# ---------------------------------------------------------------------------- principal

PIECES = (
    ("painting", "painting", lambda axis: painting(axis)),
    ("painting_abstract", "painting", lambda axis: painting(axis, "abstract")),
    ("painting_sea", "painting", lambda axis: painting(axis, "sea")),
    ("wall_clock", "wall_clock", wall_clock),
    ("whiteboard", "whiteboard", whiteboard),
    ("presentation_screen", "presentation_screen", presentation_screen),
    ("air_conditioner", "air_conditioner", air_conditioner),
)


def corner_sheet(out_dir, images):
    """Una esquina del fondo: tres tramos altos _x a la izquierda y tres _y a la derecha, con los
    objetos colgados (el juego los dibuja después de la pared)."""
    wall_x = walls.wall_piece("x", True)
    wall_x.finish(ground_outline=walls.FLOOR_LINE)
    wall_y = walls.wall_piece("y", True)
    wall_y.finish(ground_outline=walls.FLOOR_LINE)
    wall_images = {"x": wall_x.image, "y": wall_y.image}
    wall_anchor = {"x": wall_x.anchor, "y": wall_y.anchor}
    corner = (300.0, 150.0)  # vértice del fondo en la hoja
    width, height = 600, 330
    canvas = sheet.Image.new("RGBA", (width, height), sheet.BACKGROUND + (255,) if len(sheet.BACKGROUND) == 3
                             else sheet.BACKGROUND)
    hung = {"x": ["painting", "wall_clock", "whiteboard", "painting_sea"],
            "y": ["presentation_screen", "air_conditioner", "painting_abstract", "wall_clock"]}
    for axis in ("y", "x"):
        for k in range(4):
            # Punto medio del borde k: los _y bajan hacia la derecha, los _x hacia la izquierda.
            step = (32.0 + 64.0 * k, 16.0 + 32.0 * k)
            mid = (corner[0] + step[0], corner[1] + step[1]) if axis == "y" else (corner[0] - step[0], corner[1] + step[1])
            ax, ay = wall_anchor[axis]
            canvas.alpha_composite(wall_images[axis], (int(round(mid[0] - ax)), int(round(mid[1] - ay))))
    for axis in ("y", "x"):
        for k, name in enumerate(hung[axis]):
            step = (32.0 + 64.0 * k, 16.0 + 32.0 * k)
            mid = (corner[0] + step[0], corner[1] + step[1]) if axis == "y" else (corner[0] - step[0], corner[1] + step[1])
            image = images[(name, axis)]
            canvas.alpha_composite(image, (int(round(mid[0] - 32)), int(round(mid[1] - 112))))
    canvas.resize((width * 2, height * 2), sheet.Image.NEAREST).save(os.path.join(out_dir, "sheet_wall_items.png"))


def build(out_dir):
    files = []
    images = {}
    items = []
    for name, item_id, model in PIECES:
        for axis in ("x", "y"):
            set_axis(axis)
            c = model(axis)
            c.finish()
            sprite = "%s_%s" % (name, axis)
            files.append(iso.save(c, out_dir, sprite, kind="wall_item", item=item_id, axis=axis,
                                  height=item_data(item_id)["height"], base_z=BASE,
                                  anchor_at="punto medio del borde de la casilla, en el piso (como el tramo de pared)",
                                  placed_on="cara de adentro de una pared alta"))
            images[(name, axis)] = c.image
            items.append((sprite, sheet.on_background(c.image, scale=1)))
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    sheet.contact_sheet(items, columns=6, scale=3).save(os.path.join(folder, "wall_items.png"))
    corner_sheet(out_dir, images)
    return files
