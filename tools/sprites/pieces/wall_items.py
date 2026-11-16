# Objetos de pared (docs/sprites_128.md, sección 7) para pared _x y _y.
#
#   painting_x / _y                    cuadro con marco de madera naranja y un paisaje
#   painting_abstract_x / _y           el mismo marco con bloques de color
#   painting_sea_x / _y                el mismo marco con mar y un velero
#   wall_clock_x / _y                  reloj redondo de aro negro, marcas y agujas a las 10:10
#   whiteboard_x / _y                  pizarra blanca con marco de aluminio, garabatos y bandeja
#   presentation_screen_x / _y         televisor apagado en dos bordes: lienzo 128×192, apoyo (64, 160)
#   presentation_screen_chart_x / _y   el mismo encendido con una presentación (Sala de reuniones):
#   presentation_screen_pie_x / _y     barras, torta con leyenda o portada con logo
#   presentation_screen_title_x / _y
#   …_chart_x_play_1 … _12 (y _pie, _title, _y)   la presentación se arma de a poco; el 12 es la pieza
#   air_conditioner_x / _y             split blanco de 8 px de fondo, rejilla arriba, salida y luz
#   _sheets/wall_items.png             hoja de contacto
#   sheet_wall_items.png               los objetos colgados en una esquina de paredes altas
#
# Lienzo 64×128 (Canvas.wall_item): x de 0 a 1 a lo largo del borde, apoyo en el medio del borde en el
# piso (32, 112), como un tramo de pared. Sale de la cara de la pared (4 px) con la base a 48 px de sprite
# (WALL_ITEM_BASE_PX); alto = `height` × 2. Solo cara de adentro de paredes altas (sin versión baja).
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


# En un tramo _x el modelo corre de derecha a izquierda: los dibujos se espejan (set_axis).
_MIRROR = [False]


def set_axis(axis):
    _MIRROR[0] = axis == "x"


def front(ctx, x0, z0, x1):
    """Coordenadas de la cara de adelante en px: a de izquierda a derecha desde x0, b hacia arriba desde z0."""
    a = (x1 - ctx.x) if _MIRROR[0] else (ctx.x - x0)
    return np.floor(a * 64.0 + 1.0e-6), np.floor(ctx.z - z0 + 1.0e-6)


# ---------------------------------------------------------------------------- rampas

# Marco de madera naranja y los colores de los dibujos como tonos agregados.
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

# Televisor (pantalla de presentaciones): marco negro con filo gris y dos soportes abajo.
TV = pal.style("plastic_black", name="presentation_screen")
TV_RIM = TV.add("6a6a78")  # filo de afuera, del lado de la luz
TV_RIM_DARK = TV.add("4a4a56")  # filo de afuera, en sombra
TV_FRAME = TV.add("2e2e34")  # marco
TV_GLASS = TV.add("1a1a1c")  # pantalla apagada
TV_SHINE = TV.add("3a3a42")  # reflejo
TV_SHINE2 = TV.add("2b2b31")  # reflejo tenue
# Presentaciones (pantalla encendida): diapositiva clara con barra azul.
SLIDE_BG = TV.add("e4ecee")
SLIDE_SHADE = TV.add("c9d6da")  # fondo de los gráficos, renglones de la leyenda
SLIDE_BLUE = TV.add("3d90c0")
SLIDE_BLUE2 = TV.add("6dacce")
SLIDE_ORANGE = TV.add("df823d")
SLIDE_GREEN = TV.add("8fbf3c")
SLIDE_RED = TV.add("c03d43")
SLIDE_TEXT = TV.add("4f5862")
SLIDE_WHITE = TV.add("ffffff")

# Split: frente blanco verdoso, tapa gris, rejilla de salida bajo el frente y luz roja.
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
        # Filo del marco: claro arriba y a la izquierda, sombra adentro.
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
    # Agujas a las 10:10.
    hour = (da <= 0) & (db >= 0) & (np.abs(db - (-da) * 0.6) < 0.8) & (dist < 3.6)
    minute = (da >= 0) & (db >= 0) & (np.abs(db - da * 0.75) < 0.8) & (dist < 5.2)
    index = np.where(hour | minute, CLOCK_HAND, index)
    second = (np.abs(da) < 0.5) & (db < 0) & (dist < 5.0)
    index = np.where(second, CLOCK_RED, index)
    return np.where(dist < 0.9, CLOCK_RED, index)


def wall_clock(axis):
    """Reloj redondo armado en filas de 1 px, cada una del ancho del círculo."""
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
    # El aro de canto: caras de arriba y de los lados.
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
    # Gráfico a la derecha y un círculo verde.
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
    # Bandeja con dos marcadores, un poco más afuera.
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

# Televisor de 96 × 60 px en DOS bordes de la misma pared (x de 0 a 2), de z 50 a 110. Lienzo 128×192
# (TV_CANVAS) con apoyo en la esquina que comparten los dos bordes: (64, 160). En el juego ocupa uno.
TV_SPAN = 2
TV_X = (16 / 64.0, 112 / 64.0)  # 96 px a lo largo, centrado (su fondo lo corre ~9 px)
TV_Y = (FACE + 1 * PX, FACE + 5 * PX)  # 4 px de grueso: el canto se ve de costado
MOUNT_Y = (FACE + 1 * PX, FACE + 4 * PX)  # soportes, bajo el televisor
MOUNT_H = 4  # lo que asoman bajo el televisor
TV_FRAME_W = 2  # marco negro alrededor de la pantalla (sin contar el filo): delgado
TV_BOTTOM = 50  # de media pared…
TV_HEIGHT = 60  # …a z 110, casi el techo (120)
TV_CANVAS = (128, 192)
TV_ANCHOR = (64.0, 160.0)


def wide_wall_item(axis):
    """Lienzo de objeto de pared de dos bordes (128×192); x de 0 a 2 a lo largo."""
    width, height = TV_CANVAS
    origin = (128.0 if axis == "x" else 0.0, height - 64.0)
    c = iso.Canvas(width, height, origin, size=(TV_SPAN, 0), rotation=0, swap=axis == "x", kind="wall_item",
                   anchor=TV_ANCHOR)
    c.extra_meta.update({"axis": axis, "edges": TV_SPAN})
    return c


# Palabras de los renglones de texto de las diapositivas (largo en px; entre palabra y palabra, 1 px).
WORDS = (5, 3, 7, 4, 2, 6, 4, 5, 3, 6, 2, 4)


def text_row(u, v, u0, v0, length, shift=0):
    """Renglón de «texto» de 1 px de alto en la fila v0, de u0 a u0 + length, partido en palabras."""
    marks = np.zeros(int(length) + 1, dtype=bool)
    pos, k = 0, shift
    while pos < length:
        word = WORDS[k % len(WORDS)]
        marks[pos:min(pos + word, int(length))] = True
        pos += word + 1
        k += 1
    inside = (v == v0) & (u >= u0) & (u < u0 + length)
    return inside & marks[np.clip(u - u0, 0, int(length)).astype(int)]


# Animación de la presentación (_play_1 a _play_12; el último es la pieza quieta). Cada parte entra en su
# tramo de t (0 a 1).
PLAY_FRAMES = 12


def ease(t, start=0.0, length=1.0):
    """0 antes de start, 1 después de start + length y una curva suave (smoothstep) en el medio."""
    x = min(max((t - start) / length, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def reveal(mask, u, u0, length, amount):
    """Deja ver solo la parte izquierda de un renglón (se escribe de izquierda a derecha)."""
    return mask & (u < u0 + np.ceil(length * amount))


def slide(variant, u, v, gw, gh, t=1.0):
    """Diapositiva de frente: u desde la izquierda, v desde arriba (px); t = avance (1 = completa)."""
    index = np.full(u.shape, SLIDE_BG)
    # Barra azul de título arriba (7 px) con el título en blanco y un punto naranja de logo.
    bar = v < 7
    index = np.where(bar, SLIDE_BLUE, index)
    if variant != "title":
        title = reveal(text_row(u, v, 4, 3, 30, 1), u, 4, 30, ease(t, 0.0, 0.3))
        index = np.where(title, SLIDE_WHITE, index)
    index = np.where(bar & (v >= 2) & (v < 5) & (u >= gw - 6) & (u < gw - 3), SLIDE_ORANGE, index)
    if variant == "chart":
        # Ejes que se trazan, barras que suben una tras otra (azul, la última naranja) y la leyenda.
        x0, y1 = 6, gh - 5
        axis = ease(t, 0.0, 0.2)
        index = np.where((u == x0) & (v <= y1) & (v >= y1 - np.ceil((y1 - 11) * axis)), SLIDE_TEXT, index)
        index = np.where((v == y1) & (u >= x0) & (u < x0 + np.ceil((60 - x0) * axis)), SLIDE_TEXT, index)
        for k, h in enumerate((10, 15, 13, 21, 26, 33)):
            bx = x0 + 4 + k * 8
            grow = np.ceil(h * ease(t, 0.12 + k * 0.08, 0.35))
            col = SLIDE_ORANGE if k == 5 else (SLIDE_BLUE if k % 2 == 0 else SLIDE_BLUE2)
            index = np.where((u >= bx) & (u < bx + 5) & (v < y1) & (v >= y1 - grow), col, index)
        for k, col in enumerate((SLIDE_BLUE, SLIDE_BLUE2, SLIDE_ORANGE)):
            ly = 14 + k * 6
            show = ease(t, 0.5 + k * 0.1, 0.25)
            if show > 0:
                index = np.where((u >= 66) & (u < 69) & (v >= ly) & (v < ly + 3), col, index)
            row = reveal(text_row(u, v, 71, ly + 1, gw - 75, k * 3), u, 71, gw - 75, show)
            index = np.where(row, SLIDE_TEXT, index)
        notes = ease(t, 0.8, 0.2)
        index = np.where(reveal(text_row(u, v, 66, 36, gw - 70, 5), u, 66, gw - 70, notes) |
                         reveal(text_row(u, v, 66, 39, gw - 74, 8), u, 66, gw - 74, notes), SLIDE_SHADE, index)
    elif variant == "pie":
        # Torta en tres partes que se dibuja en un barrido, y la leyenda.
        cu, cv, r = 22.0, 29.5, 15.0
        du, dv = u + 0.5 - cu, v + 0.5 - cv
        dist = np.sqrt(du * du + dv * dv)
        turn = np.mod(np.arctan2(du, -dv) / (2 * np.pi), 1.0)  # 0 arriba, en el sentido del reloj
        sweep = ease(t, 0.05, 0.6)
        pie = (dist < r) & (turn < sweep + 1.0e-6) if sweep < 1.0 else dist < r
        part = np.where(turn < 0.48, SLIDE_BLUE, np.where(turn < 0.78, SLIDE_ORANGE, SLIDE_GREEN))
        index = np.where(pie, part, index)
        cut = pie & (dist > 1.0) & ((np.abs(turn - 0.48) * 2 * np.pi * dist < 0.6) |
                                    (np.abs(turn - 0.78) * 2 * np.pi * dist < 0.6) |
                                    ((turn < 0.02) | (turn > 0.995)) & (np.abs(du) < 0.6))
        index = np.where(cut, SLIDE_BG, index)
        for k, col in enumerate((SLIDE_BLUE, SLIDE_ORANGE, SLIDE_GREEN)):
            ly = 16 + k * 8
            # Cada renglón entra cuando el barrido llega a su parte.
            show = ease(t, 0.25 + k * 0.2, 0.25)
            if show > 0:
                index = np.where((u >= 46) & (u < 50) & (v >= ly) & (v < ly + 4), col, index)
            length = 20 + 6 * (k % 2)
            index = np.where(reveal(text_row(u, v, 53, ly + 1, length, k * 4), u, 53, length, show), SLIDE_TEXT, index)
            index = np.where(reveal(text_row(u, v, 53, ly + 3, 12, k * 4 + 2), u, 53, 12, show), SLIDE_SHADE, index)
    else:
        # Portada: el logo crece, se escriben título y subtítulo y al final la fecha.
        lx, ly = gw // 2 - 6, 13
        size = ease(t, 0.0, 0.35)
        half = 6.0 * size
        cx, cy = lx + 6.0, ly + 6.0
        logo = (np.abs(u + 0.5 - cx) < half) & (np.abs(v + 0.5 - cy) < half)
        index = np.where(logo, SLIDE_BLUE, index)
        diamond = np.abs(u + 0.5 - cx) + np.abs(v + 0.5 - cy) < 4.5 * size
        index = np.where(logo & diamond, SLIDE_ORANGE, index)
        for row, length, col, start in ((30, 46, SLIDE_TEXT, 0.3), (31, 46, SLIDE_TEXT, 0.3),
                                        (35, 34, SLIDE_BLUE2, 0.5), (41, 20, SLIDE_SHADE, 0.65)):
            u0 = (gw - length) // 2
            row_mask = reveal(text_row(u, v, u0, row, length, row), u, u0, length, ease(t, start, 0.3))
            index = np.where(row_mask, col, index)
        foot = ease(t, 0.8, 0.2)
        line = (v == gh - 4) & (u >= 8) & (u < 8 + np.ceil((gw - 16) * foot))
        index = np.where(line & (np.mod(u, 4) != 3), SLIDE_SHADE, index)
        index = np.where(line & (u >= gw - 14) & (u < gw - 8), SLIDE_RED, index)
    return index


def tv_face_for(variant, t=1.0):
    def tv_face(ctx):
        a, b = front(ctx, TV_X[0], TV_BOTTOM, TV_X[1])
        width = np.floor((TV_X[1] - TV_X[0]) * 64.0)
        height = TV_HEIGHT
        index = np.full(a.shape, TV_FRAME)
        # Filo de 1 px afuera, claro arriba y a la izquierda (la luz).
        outer = (a == 0) | (a == width - 1) | (b == 0) | (b == height - 1)
        index = np.where(outer, np.where((b == height - 1) | (a == 0), TV_RIM, TV_RIM_DARK), index)
        inset = 1 + TV_FRAME_W
        glass = (a >= inset) & (a < width - inset) & (b >= inset) & (b < height - inset)
        ga = a - inset
        gb = b - inset
        gw = width - 2 * inset
        gh = height - 2 * inset
        if variant:
            # Encendida: la diapositiva llena la pantalla, sin borde hundido.
            screen = slide(variant, ga, gh - 1 - gb, int(gw), int(gh), t)
            return np.where(glass, screen, index)
        # Apagada: hundida 1 px y reflejos en «\». En la _x, menos peso de b deja la línea igual de parada.
        k = 0.4 if _MIRROR[0] else 0.8
        d = np.floor((ga + gb * k) * 122.0 / (gw + gh * k))
        lines = (d == 44) | (d == 47) | (d == 76) | (d == 100)
        soft = (d >= 51) & (d < 62)
        screen = np.where(lines, TV_SHINE, np.where(soft, TV_SHINE2, TV_GLASS))
        edge = glass & ((a == inset) | (b == height - inset - 1))
        return np.where(glass, np.where(edge, pal.OUTLINE, screen), index)
    return tv_face


def presentation_screen(axis, variant="", t=1.0):
    """Televisor de dos bordes. variant: "" apagado o "chart", "pie", "title"; t = avance (1 = completa)."""
    c = wide_wall_item(axis)
    mounts = None
    for x in (TV_X[0] + 20 / 64.0, TV_X[1] - 23 / 64.0):
        pid = c.box(x, x + 4 / 64.0, MOUNT_Y[0], MOUNT_Y[1], TV_BOTTOM - MOUNT_H, TV_BOTTOM, TV,
                    name="mounts" if mounts is None else None, part=mounts)
        mounts = pid if mounts is None else mounts
    c.box(TV_X[0], TV_X[1], TV_Y[0], TV_Y[1], TV_BOTTOM, TV_BOTTOM + TV_HEIGHT, TV,
          tex={iso.BACK: tv_face_for(variant, t)}, name="tv", flat=False)
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
    # Marca gris y luz roja (2×2).
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
    # Rejilla de aletas: filas alternas con un punto claro cada 2 px.
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
    ("presentation_screen_chart", "presentation_screen", lambda axis: presentation_screen(axis, "chart")),
    ("presentation_screen_pie", "presentation_screen", lambda axis: presentation_screen(axis, "pie")),
    ("presentation_screen_title", "presentation_screen", lambda axis: presentation_screen(axis, "title")),
    ("air_conditioner", "air_conditioner", air_conditioner),
)


# Las presentaciones que se animan (nombre de la pieza -> variante).
PLAYS = {"presentation_screen_chart": "chart", "presentation_screen_pie": "pie", "presentation_screen_title": "title"}


def corner_sheet(out_dir, images):
    """Esquina del fondo con tres tramos altos _x y tres _y y los objetos colgados."""
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
            "y": ["presentation_screen", "air_conditioner", "painting_abstract"]}
    span = {"presentation_screen": TV_SPAN}
    for axis in ("y", "x"):
        for k in range(4):
            # Punto medio del borde k: los _y bajan hacia la derecha, los _x hacia la izquierda.
            step = (32.0 + 64.0 * k, 16.0 + 32.0 * k)
            mid = (corner[0] + step[0], corner[1] + step[1]) if axis == "y" else (corner[0] - step[0], corner[1] + step[1])
            ax, ay = wall_anchor[axis]
            canvas.alpha_composite(wall_images[axis], (int(round(mid[0] - ax)), int(round(mid[1] - ay))))
    for axis in ("y", "x"):
        k = 0
        for name in hung[axis]:
            # Punto medio de los bordes que ocupa (k … k + n − 1).
            n = span.get(name, 1)
            step = (32.0 * n + 64.0 * k, 16.0 * n + 32.0 * k)
            k += n
            mid = (corner[0] + step[0], corner[1] + step[1]) if axis == "y" else (corner[0] - step[0], corner[1] + step[1])
            image, anchor = images[(name, axis)]
            canvas.alpha_composite(image, (int(round(mid[0] - anchor[0])), int(round(mid[1] - anchor[1]))))
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
                                  height=item_data(item_id)["height"],
                                  base_z=TV_BOTTOM if item_id == "presentation_screen" else BASE,
                                  anchor_at="punto medio del borde de la casilla, en el piso (como el tramo de pared)",
                                  placed_on="cara de adentro de una pared alta"))
            images[(name, axis)] = (c.image, c.anchor)
            items.append((sprite, sheet.on_background(c.image, scale=1)))
            if name in PLAYS:
                for step in range(1, PLAY_FRAMES + 1):
                    f = presentation_screen(axis, PLAYS[name], step / float(PLAY_FRAMES))
                    f.finish()
                    files.append(iso.save(f, out_dir, "%s_play_%d" % (sprite, step), kind="wall_item_frame",
                                          item=item_id, axis=axis, base=sprite + ".png", frame=step,
                                          frames=PLAY_FRAMES, animation="play"))
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    sheet.contact_sheet(items, columns=6, scale=3).save(os.path.join(folder, "wall_items.png"))
    corner_sheet(out_dir, images)
    return files
