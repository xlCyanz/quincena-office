# Escritorio sencillo (simple_desk), computadoras (basic/mid/pro) y segundo monitor, en sus 4
# rotaciones, con el estilo de tools/sprites/STYLE.md (madera naranja, plástico negro, pantalla
# encendida, contorno grueso del material).
#
#   desk_simple_r0..r3.png             128×128, apoyo (64, 96)
#   desk_simple_r0..r3_shadow.png      sombra en el piso, aparte
#   computer_basic_r0..r3.png          128×128, apoyo (64, 96), dibujada a 44 px sobre el piso
#   computer_mid_r0..r3.png            más grande y de dos tonos (cuerpo plateado, marco negro)
#   computer_pro_r0..r3.png            monitor alto azul marino y torre con luces sobre el tablero
#   second_monitor_r0..r3.png          monitor chico del lado +x del escritorio
#   *_shadow.png de las computadoras    sombra de contacto sobre el tablero (va entre el escritorio y la pieza)
#   _sheets/desk.png                   hoja de contacto del grupo (no es arte del juego)
#   _sheets/desk_seat.png              escritorio r0–r3 con su silla delante (para ver que el frente es coherente)
#
# El modelo se escribe una vez con rotación 0: el frente (donde va la silla, el hueco de las
# piernas) mira a −y. La cajonera queda del lado +x con sus cajones hacia el frente (hacia quien se
# sienta, a un lado de sus piernas); del lado −x van dos patas gruesas y atrás un faldón.
#
# Segundo monitor: el juego corre la computadora 0.15 casillas hacia −x del modelo y pone el
# monitor en +x (x 21–30/32). Por eso todo lo de las computadoras queda entre x 5 y 26/32.
import os

import numpy as np
from PIL import Image

import iso
import palette as pal
import pattern
import sheet

ITEMS = iso.load_json("data/furniture.json")["items"]
DESK = ITEMS["simple_desk"]
COMPUTERS = {"basic": ITEMS["basic_computer"], "mid": ITEMS["mid_computer"], "pro": ITEMS["pro_computer"]}
MONITOR = ITEMS["second_monitor"]

U = 1.0 / 32.0  # 1/32 de casilla: 2 px de ancho y 1 de alto en pantalla
TOP = iso.world_px(DESK["height"])  # 22 px del mundo -> z = 44
SLAB = 6  # grosor del tablero
LEGS = TOP - SLAB  # alto de patas y cajonera

# Rampas propias (se les suman tonos: no tocar las constantes compartidas de palette.py).
WOOD = pal.style("wood_orange", name="desk_wood")
PLASTIC = pal.style("plastic_black", name="desk_plastic")
KEYS_GREY = PLASTIC.add("6a6868", "key")  # teclas del teclado negro
METAL = pal.style("metal_light", name="desk_metal")
GLOW = pal.style("screen", name="desk_screen")  # pantalla encendida
GLOW_TEXT = GLOW.add("f2fbff", "text")
NAVY = pal.style_ramp("2c4373", outline="0c1226", light="4d6aa3", name="desk_navy")  # monitor pro
LED = pal.style_ramp("6fe08a", name="desk_led")
CYAN = pal.style_ramp("3fe0e8", name="desk_cyan")
MAGENTA = pal.style_ramp("e05ae0", name="desk_magenta")

# Planta del escritorio (en 1/32 de casilla). El tablero vuela 1–2 por cada lado y queda centrado
# en la casilla: la caja del sprite no salta al girar el mueble.
TOP_X0, TOP_X1, TOP_Y0, TOP_Y1 = 1, 31, 3, 29
PED_X0, PED_X1, PED_Y0, PED_Y1 = 21, 30, 5, 27  # cajonera
PED_Z0 = 3  # la cajonera va sobre un zócalo hundido
LEG = 3  # lado de las patas (6 px de pantalla por eje)
LEG_X0 = 2
LEG_YS = (5, 24)  # patas del lado −x: adelante y atrás
SKIRT_Y0, SKIRT_Z0 = 25, 18  # faldón de atrás, entre la pata de atrás y la cajonera
# Cajones: (primera fila, fila siguiente a la última) desde la base de la cajonera (35 px de alto).
DRAWERS = ((2, 12), (13, 23), (24, 34))
SHADOW_SHIFT = (0.10, 0.03)
SHADOW_INSET = 3
SHADOW_COLOR = (26, 28, 38)
CONTACT_SHIFT = (1.0, 0.3)
DESK_Z = iso.DESK_TOP  # 44


# ---------------------------------------------------------------------------- texturas

def whole_runs(mask):
    """Deja solo tramos enteros de una línea 2:1 (quita pixeles sin vecino en su fila)."""
    return mask & (np.roll(mask, 1, axis=1) | np.roll(mask, -1, axis=1))


def drawer_front(ctx):
    """Frente de la cajonera: tres cajones con rendija oscura de 1 px alrededor, su canto de
    abajo con luz y un tirador hundido (ranura oscura con su borde claro debajo)."""
    index = ctx.base
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    w = int(ctx.w)
    for b0, b1 in DRAWERS:
        gap = pattern.frame(a, b, 1, w - 1, b0 - 1, b1 + 1, 1)
        index = np.where(gap, pal.DEEP, index)
        mid = (b0 + b1) // 2 + 1
        slot = whole_runs((a >= 5) & (a < w - 5) & ((b == mid) | (b == mid + 1)))
        index = np.where(slot, pal.DEEP, index)
        index = np.where(whole_runs((a >= 5) & (a < w - 5) & (b == mid - 1)), pal.LIGHT, index)
    return index


def side_panel(ctx):
    """Costado de afuera y espalda de la cajonera: un tablero grande hundido (detalle grande, no
    textura): línea oscura arriba y a la izquierda, canto claro abajo y a la derecha."""
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    a0, a1, b0, b1 = 4, int(ctx.w) - 4, 4, int(ctx.h) - 4
    inside = (a >= a0) & (a < a1) & (b >= b0) & (b < b1)
    dark = inside & ((b == b1 - 1) | (a == a0))
    lit = inside & ((b == b0) | (a == a1 - 1)) & ~dark
    index = np.where(dark, pal.darker(ctx.base), ctx.base)
    return np.where(lit, pal.lighter(ctx.base), index)


def under_top(ctx):
    """Sombra del tablero sobre lo que queda debajo: las 2 filas de arriba un paso más oscuras."""
    return np.where(ctx.b >= ctx.h - 2, pal.darker(ctx.base), ctx.base)


def with_under_top(fn):
    def tex(ctx):
        index = fn(ctx)
        return np.where(ctx.b >= ctx.h - 2, pal.darker(ctx.base), index)
    return tex


# ---------------------------------------------------------------------------- escritorio

def desk_model(c):
    """Escritorio con rotación 0: frente a −y."""
    # Zócalo hundido y cajonera con los cajones al frente; su cara hacia el hueco, en sombra.
    c.box((PED_X0 + 1) * U, (PED_X1 - 1) * U, (PED_Y0 + 1) * U, (PED_Y1 - 1) * U, 0, PED_Z0, WOOD,
          shade=-1, name="plinth")
    c.box(PED_X0 * U, PED_X1 * U, PED_Y0 * U, PED_Y1 * U, PED_Z0, LEGS, WOOD,
          tex={iso.FRONT: with_under_top(drawer_front), iso.X1: with_under_top(side_panel),
               iso.BACK: with_under_top(side_panel), iso.X0: under_top},
          shade={iso.X0: -1}, name="pedestal")
    # Patas gruesas del lado −x.
    for y0 in LEG_YS:
        c.box(LEG_X0 * U, (LEG_X0 + LEG) * U, y0 * U, (y0 + LEG) * U, 0, LEGS, WOOD,
              tex={"sides": under_top}, name="leg")
    # Faldón de atrás: por delante es el fondo del hueco (en sombra).
    c.box((LEG_X0 + LEG) * U, PED_X0 * U, SKIRT_Y0 * U, (SKIRT_Y0 + 1) * U, SKIRT_Z0, LEGS, WOOD,
          tex={"sides": under_top}, shade={iso.FRONT: -1}, name="skirt")
    # Tablero con vuelo (las puntas las recorta el acabado).
    c.box(TOP_X0 * U, TOP_X1 * U, TOP_Y0 * U, TOP_Y1 * U, LEGS, TOP, WOOD, name="top")


def desk(rotation):
    c = iso.Canvas.furniture(DESK["size"], DESK["height"], rotation)
    desk_model(c)
    return c


def desk_shadow(rotation):
    """Sombra del escritorio: cajonera y patas enteras y, del tablero, solo el centro (metido
    SHADOW_INSET por lado), corrida abajo a la derecha."""
    c = iso.Canvas.furniture(DESK["size"], DESK["height"], rotation)
    c.box(PED_X0 * U, PED_X1 * U, PED_Y0 * U, PED_Y1 * U, 0, LEGS, WOOD)
    for y0 in LEG_YS:
        c.box(LEG_X0 * U, (LEG_X0 + LEG) * U, y0 * U, (y0 + LEG) * U, 0, LEGS, WOOD)
    c.box((TOP_X0 + SHADOW_INSET) * U, (TOP_X1 - SHADOW_INSET) * U, (TOP_Y0 + SHADOW_INSET) * U,
          (TOP_Y1 - SHADOW_INSET) * U, 0, TOP, WOOD)
    return c.ground_shadow(shift=SHADOW_SHIFT, color=SHADOW_COLOR)


# ---------------------------------------------------------------------------- piezas de las computadoras
#
# Cada spec: monitor (x0, x1, z0, z1 sobre el piso), su cuerpo, cómo se pinta el marco, el teclado y
# lo que lleve aparte (torre). La pantalla mira a −y (el frente del escritorio); su cara está en
# y = SCREEN_Y.

SCREEN_Y = 20
SCREEN_DEPTH = 2

SPECS = {
    # Básica: monitor negro de marco grueso, teclado negro con teclas grises.
    "basic": {"monitor": (8, 24, DESK_Z + 5, DESK_Z + 24), "body": PLASTIC, "bezel": (3, 3, 5),
              "frame": None, "keyboard": (11, 23, 7, 12), "board": PLASTIC, "keys": (KEYS_GREY, PLASTIC),
              "mouse": (7, 10, PLASTIC), "tower": None, "lines": 4},
    # Media: más grande, cuerpo plateado con marco negro alrededor de la pantalla y mentón plateado.
    "mid": {"monitor": (6, 26, DESK_Z + 5, DESK_Z + 28), "body": METAL, "bezel": (2, 2, 6),
            "frame": PLASTIC, "keyboard": (10, 24, 7, 12), "board": METAL, "keys": (pal.SHINE, METAL),
            "mouse": (7, 10, METAL), "tower": None, "lines": 5},
    # Pro: monitor alto azul marino de marco fino y torre negra con luces a su izquierda.
    "pro": {"monitor": (12, 26, DESK_Z + 5, DESK_Z + 32), "body": NAVY, "bezel": (2, 2, 4),
            "frame": PLASTIC, "keyboard": (11, 24, 7, 12), "board": PLASTIC, "keys": (pal.RIGHT, CYAN),
            "mouse": (8, 10, PLASTIC), "tower": (5, 10, 15, 25, DESK_Z + 24), "lines": 6},
}
SECOND = {"monitor": (21, 30, DESK_Z + 5, DESK_Z + 20), "body": PLASTIC, "bezel": (2, 3, 4), "frame": None,
          "lines": 3}


def monitor(c, spec):
    """Monitor: pie, cuello, la caja de la pantalla y el bulto de atrás; pinta la pantalla."""
    x0, x1, z0, z1 = spec["monitor"]
    body = spec["body"]
    mid = (x0 + x1) / 2.0
    half = max(2, (x1 - x0) // 4)
    c.box((mid - half) * U, (mid + half) * U, (SCREEN_Y - 1) * U, (SCREEN_Y + 5) * U, DESK_Z, DESK_Z + 2, body,
          name="foot")
    c.box((mid - 2) * U, (mid + 2) * U, (SCREEN_Y + SCREEN_DEPTH + 1) * U, (SCREEN_Y + SCREEN_DEPTH + 2) * U,
          DESK_Z + 2, z0 + 6, body, name="neck")
    c.box(x0 * U, x1 * U, SCREEN_Y * U, (SCREEN_Y + SCREEN_DEPTH) * U, z0, z1, body, name="screen")
    inset = max(2, (x1 - x0) // 4)
    c.box((x0 + inset) * U, (x1 - inset) * U, (SCREEN_Y + SCREEN_DEPTH) * U, (SCREEN_Y + SCREEN_DEPTH + 1) * U,
          z0 + 3, z1 - 4, body, name="bulge")
    c.style_part("screen", rim="full")
    paint_screen(c, spec)
    paint_back(c)


def paint_screen(c, spec):
    """Cara de la pantalla: marco (bisel) del cuerpo o de otro tono, pantalla encendida con una
    barra arriba, margen y renglones de código, y la luz de encendido en el mentón."""
    x0, x1, z0, z1 = spec["monitor"]
    side, top, chin = spec["bezel"]
    face = c.select(part="screen", face=iso.FRONT)
    a = np.floor(c.a)
    b = np.floor(c.b)
    w = (x1 - x0) * 2
    h = z1 - z0
    if spec["frame"] is not None:
        # Marco de otro tono alrededor de la pantalla (el mentón queda del color del cuerpo).
        frame = face & (b >= chin - 1)
        c.paint(frame, pal.BASE, spec["frame"])
    display = face & (a >= side) & (a < w - side) & (b >= chin) & (b < h - top)
    c.paint(display, pal.BASE, GLOW)
    # Sombra del marco sobre la pantalla (arriba y a la izquierda), barra de título y margen.
    c.paint(display & ((b == h - top - 1) | (a == side)), pal.RIGHT, GLOW)
    c.paint(display & (b < h - top - 1) & (b >= h - top - 4) & (a > side), pal.LEFT, GLOW)
    c.paint(display & (a > side) & (a < side + 4) & (b < h - top - 4), pal.LEFT, GLOW)
    rows = spec["lines"]
    starts = (0, 2, 2, 0, 4, 2)
    lengths = (0.45, 0.55, 0.3, 0.5, 0.35, 0.45)
    inner = w - 2 * side - 6
    for row in range(rows):
        line_b = h - top - 6 - 3 * row
        if line_b < chin + 1:
            break
        start = side + 4 + starts[row]
        length = max(4, int(inner * lengths[row]) // 2 * 2)
        line = display & (b == line_b) & (a >= start) & (a < start + length)
        c.paint(whole_runs(line), GLOW_TEXT, GLOW)
    # Reflejo: una diagonal clara en la esquina de arriba a la derecha.
    glare = display & (a + (h - b) >= w - side - 2) & (a + (h - b) < w - side + 1) & (b > chin + 2)
    c.paint(glare & (a < w - side - 1), pal.LIGHT, GLOW)
    # Luz de encendido en el mentón.
    led = face & (a >= w - side - 4) & (a < w - side - 2) & (b == chin // 2)
    c.paint(led, pal.BASE, LED)


def paint_back(c):
    """Espalda: bulto con dos ranuras de ventilación (línea oscura con su canto claro abajo)."""
    a = np.floor(c.a)
    b = np.floor(c.b)
    bulge = c.select(part="bulge", face=iso.BACK)
    width = int(np.max(np.where(bulge, a, 0))) + 1 if bulge.any() else 0
    height = int(np.max(np.where(bulge, b, 0))) + 1 if bulge.any() else 0
    for slot in (height - 3, height - 6):
        along = bulge & (a >= 3) & (a < width - 3)
        c.paint(whole_runs(along & (b == slot)), pal.DEEP)
        c.paint(whole_runs(along & (b == slot - 1)), pal.LIGHT)


def keyboard(c, spec):
    """Teclado: base delgada y tres filas de teclas pintadas encima (la de adelante con la barra
    espaciadora); ratón al lado −x (la derecha de quien se sienta)."""
    kx0, kx1, ky0, ky1 = spec["keyboard"]
    board = spec["board"]
    c.box(kx0 * U, kx1 * U, ky0 * U, ky1 * U, DESK_Z, DESK_Z + 2, board, name="keyboard")
    key_index, key_ramp = spec["keys"]
    top = c.select(part="keyboard", face=iso.TOP)
    a = np.floor(c.a)
    b = np.floor(c.b)
    w = (kx1 - kx0) * 2
    for row, b0 in enumerate((1, 4, 7)):
        line = top & (b >= b0) & (b < b0 + 2) & (a >= 2) & (a < w - 2)
        cut = np.mod(c.X + 2 * (row % 2), 4) == 3
        if row == 0:
            cut = cut & ~((a >= 9) & (a < w - 9))
        c.paint(line & ~cut, key_index, key_ramp)
    mx, my, mouse_ramp = spec["mouse"]
    c.ellipsoid(mx * U, my * U, DESK_Z, 1.5 * U, 2.0 * U, 3.5, mouse_ramp,
                clip_z=(DESK_Z, DESK_Z + 3.5), name="mouse")


def tower(c, spec):
    """Torre de la pro: caja negra con franja de luz al frente, ventana con luces en los costados y
    rejilla atrás."""
    x0, x1, y0, y1, z1 = spec["tower"]
    c.box(x0 * U, x1 * U, y0 * U, y1 * U, DESK_Z, z1, PLASTIC, name="tower")
    a = np.floor(c.a)
    b = np.floor(c.b)
    h = z1 - DESK_Z
    front = c.select(part="tower", face=iso.FRONT)
    c.paint(front & (a >= 2) & (a < 4) & (b >= 4) & (b < h - 4), pal.BASE, CYAN)
    c.paint(front & (a >= 6) & (a < 8) & (b >= h - 6) & (b < h - 4), pal.BASE, LED)
    for face in (iso.X0, iso.X1):
        side = c.select(part="tower", face=face)
        w = (y1 - y0) * 2
        window = side & (a >= 3) & (a < w - 3) & (b >= 4) & (b < h - 4)
        c.paint(window, pal.DEEP)
        c.paint(window & (b >= h - 9) & (b < h - 7) & (a >= 5) & (a < w - 5), pal.BASE, MAGENTA)
        c.paint(window & (b >= 7) & (b < 9) & (a >= 5) & (a < w - 5), pal.BASE, CYAN)
        fan = window & (b >= 11) & (b < h - 11) & (a >= w // 2 - 3) & (a < w // 2 + 3)
        c.paint(fan, pal.LEFT, MAGENTA)
    back = c.select(part="tower", face=iso.BACK)
    w = (x1 - x0) * 2
    for row in range(6, h - 6, 3):
        c.paint(whole_runs(back & (b == row) & (a >= 2) & (a < w - 2)), pal.DEEP)


def computer_model(c, kind):
    spec = SPECS[kind]
    if spec["tower"] is not None:
        tower(c, spec)
    monitor(c, spec)
    keyboard(c, spec)


def computer_height(kind):
    """Alto para el lienzo: el del JSON o el del dibujo, el mayor (en px del mundo)."""
    z1 = SPECS[kind]["monitor"][3]
    if SPECS[kind]["tower"] is not None:
        z1 = max(z1, SPECS[kind]["tower"][4])
    return max(COMPUTERS[kind]["height"], int(np.ceil((z1 - DESK_Z) / 2.0)))


def computer(kind, rotation):
    c = iso.Canvas.on_desk(rotation, computer_height(kind))
    computer_model(c, kind)
    return c


def second_monitor(rotation):
    c = iso.Canvas.on_desk(rotation, max(MONITOR["height"], (SECOND["monitor"][3] - DESK_Z + 1) // 2))
    monitor(c, SECOND)
    return c


def contact_shadow(rotation, height, boxes, mouse=None):
    """Sombra de contacto de un tono sobre el tablero (para poner con transparencia entre el
    escritorio y la pieza). Se arma en el piso y se sube 44 px."""
    c = iso.Canvas.on_desk(rotation, height)
    for x0, x1, y0, y1, h in boxes:
        c.box(x0 * U, x1 * U, y0 * U, y1 * U, 0, h, PLASTIC)
    if mouse is not None:
        c.ellipsoid(mouse[0] * U, mouse[1] * U, 0, 1.5 * U, 2.0 * U, 3.5, PLASTIC, clip_z=(0, 2))
    low = c.ground_shadow(shift=CONTACT_SHIFT, color=SHADOW_COLOR, clip=False)
    lifted = Image.new("RGBA", low.size, (0, 0, 0, 0))
    lifted.paste(low, (0, -DESK_Z))
    return lifted


def computer_shadow(kind, rotation):
    spec = SPECS[kind]
    x0, x1, _z0, _z1 = spec["monitor"]
    mid = (x0 + x1) / 2.0
    half = max(2, (x1 - x0) // 4)
    kx0, kx1, ky0, ky1 = spec["keyboard"]
    boxes = [(mid - half, mid + half, SCREEN_Y - 1, SCREEN_Y + 5, 2), (kx0, kx1, ky0, ky1, 2)]
    if spec["tower"] is not None:
        tx0, tx1, ty0, ty1, _tz = spec["tower"]
        boxes.append((tx0, tx1, ty0, ty1, 6))
    return contact_shadow(rotation, computer_height(kind), boxes, spec["mouse"][:2])


def second_monitor_shadow(rotation):
    x0, x1, _z0, _z1 = SECOND["monitor"]
    mid = (x0 + x1) / 2.0
    half = max(2, (x1 - x0) // 4)
    return contact_shadow(rotation, MONITOR["height"], [(mid - half, mid + half, SCREEN_Y - 1, SCREEN_Y + 5, 2)])


# ---------------------------------------------------------------------------- salida

def with_shadow(base, shadow, opacity=0.3, offset=(0, 0)):
    """Pone una sombra de un tono sobre una imagen con transparencia (para las vistas)."""
    faded = np.array(shadow)
    faded[..., 3] = (faded[..., 3] * opacity).astype(np.uint8)
    base.alpha_composite(Image.fromarray(faded, "RGBA"), offset)


# Corrimiento en pantalla de 1 casilla hacia +x del modelo, por rotación (para la vista con segundo monitor).
MODEL_X_STEP = {0: (64, 32), 1: (-64, 32), 2: (-64, -32), 3: (64, -32)}
COMPUTER_SHIFT = 0.15


def shifted(image, rotation, amount):
    step = MODEL_X_STEP[rotation]
    dx, dy = int(round(step[0] * amount)), int(round(step[1] * amount))
    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    out.alpha_composite(image, (max(dx, 0), max(dy, 0)), (max(-dx, 0), max(-dy, 0)))
    return out


def contact_sheet(out_dir):
    """Hoja de contacto: piezas sueltas y armadas sobre un piso con sus sombras."""
    def load(name):
        return sheet.load(os.path.join(out_dir, name + ".png"))

    items = []
    for r in range(4):
        items.append(("desk_simple_r%d" % r, load("desk_simple_r%d" % r)))
    for kind in ("basic", "mid", "pro"):
        for r in range(4):
            both = sheet.plain_tile()
            with_shadow(both, load("desk_simple_r%d_shadow" % r))
            both.alpha_composite(load("desk_simple_r%d" % r))
            with_shadow(both, load("computer_%s_r%d_shadow" % (kind, r)))
            both.alpha_composite(load("computer_%s_r%d" % (kind, r)))
            items.append(("computer_%s_r%d" % (kind, r), both))
    for r in range(4):
        both = sheet.plain_tile()
        with_shadow(both, load("desk_simple_r%d_shadow" % r))
        both.alpha_composite(load("desk_simple_r%d" % r))
        comp = shifted(load("computer_basic_r%d" % r), r, -COMPUTER_SHIFT)
        comp_shadow = shifted(load("computer_basic_r%d_shadow" % r), r, -COMPUTER_SHIFT)
        mon, mon_shadow = load("second_monitor_r%d" % r), load("second_monitor_r%d_shadow" % r)
        with_shadow(both, comp_shadow)
        with_shadow(both, mon_shadow)
        # Lo de +x del modelo queda más cerca en r0 y r1: se dibuja después.
        layers = [comp, mon] if r in (0, 1) else [mon, comp]
        for layer in layers:
            both.alpha_composite(layer)
        items.append(("second_monitor_r%d (+ basica corrida)" % r, both))
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    path = os.path.join(folder, "desk.png")
    sheet.contact_sheet(items, columns=4, scale=3).save(path)
    return path


def seat_sheet(out_dir):
    """Escena: cada escritorio con computadora y su silla en la casilla del frente, mirándolo (si la
    silla está generada; si no, un rombo claro marca dónde va)."""
    def load(name):
        path = os.path.join(out_dir, name + ".png")
        return sheet.load(path) if os.path.isfile(path) else None

    scene = sheet.Scene(6, 6, top=100, margin=12)
    scene.fill_floor([sheet.plain_tile()])
    marker = sheet.plain_tile("e9d9a8")
    # (rotación, casilla del escritorio, casilla de la silla = la del frente)
    for rotation, desk_cell, seat_cell in ((1, (1, 1), (2, 1)), (2, (4, 1), (4, 2)), (3, (4, 4), (3, 4)),
                                           (0, (1, 4), (1, 3))):
        scene.add_shadow(load("desk_simple_r%d_shadow" % rotation), desk_cell[0], desk_cell[1], anchor=(64, 96))
        scene.add(load("desk_simple_r%d" % rotation), desk_cell[0], desk_cell[1], anchor=(64, 96))
        scene.add(load("computer_pro_r%d" % rotation), desk_cell[0], desk_cell[1], anchor=(64, 96), bias=0.5)
        chair = load("chair_basic_r%d" % ((rotation + 2) % 4))
        if chair is not None:
            scene.add(chair, seat_cell[0], seat_cell[1], anchor=(64, 96))
        else:
            scene.floor(marker, seat_cell[0], seat_cell[1])
    folder = os.path.join(out_dir, "_sheets")
    path = os.path.join(folder, "desk_seat.png")
    scene.render(scale=3).save(path)
    return path


def build(out_dir):
    files = []
    for rotation in range(4):
        c = desk(rotation)
        files.append(iso.save(c, out_dir, "desk_simple_r%d" % rotation))
        files.append(iso.save(desk_shadow(rotation), out_dir, "desk_simple_r%d_shadow" % rotation, kind="shadow",
                              footprint=list(c.world_size), anchor=list(c.anchor)))
        for kind in ("basic", "mid", "pro"):
            name = "computer_%s_r%d" % (kind, rotation)
            files.append(iso.save(computer(kind, rotation), out_dir, name))
            files.append(iso.save(computer_shadow(kind, rotation), out_dir, name + "_shadow", kind="shadow",
                                  anchor=[64, 96], surface_z=DESK_Z))
        files.append(iso.save(second_monitor(rotation), out_dir, "second_monitor_r%d" % rotation))
        files.append(iso.save(second_monitor_shadow(rotation), out_dir, "second_monitor_r%d_shadow" % rotation,
                              kind="shadow", anchor=[64, 96], surface_z=DESK_Z))
    contact_sheet(out_dir)
    seat_sheet(out_dir)
    return files
