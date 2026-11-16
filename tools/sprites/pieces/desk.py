# Escritorio sencillo (simple_desk), computadoras (basic/mid/pro) y segundo monitor, en sus 4
# rotaciones, con el estilo de tools/sprites/STYLE.md (madera naranja, plástico negro, pantalla
# encendida, contorno grueso del material).
#
#   desk_simple_r0..r3.png             128×128, apoyo (64, 96)
#   desk_simple_r0..r3_shadow.png      sombra en el piso, aparte
#   computer_basic_r0..r3.png          128×160, apoyo (64, 128), dibujada a 44 px sobre el piso
#   computer_basic: monitor de tubo beige sobre su caja acostada (computadora vieja)
#   computer_mid_r0..r3.png            monitor plano negro, ancho y delgado
#   computer_pro_r0..r3.png            todo en uno plateado y torre negra con luz azul sobre el tablero
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
import math
import os

import numpy as np
from PIL import Image

import iso
import palette as pal
import pattern
import sheet

ITEMS = iso.load_json("data/furniture.json")["items"]
DESK = ITEMS["simple_desk"]
COMPUTERS = {"basic": ITEMS["basic_computer"], "pro": ITEMS["pro_computer"]}
LONG = ITEMS["long_desk"]

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
# Vidrio de pantalla: oscuro y brillante (plano) o gris azulado (tubo), con reflejos en diagonal.
GLASS = pal.style_ramp("34343c", outline="101014", light="5a5a66", name="desk_glass")
TUBE = pal.style_ramp("6b8a92", outline="1e2a30", light="9db8be", name="desk_tube")
BEIGE = pal.style_ramp("e4d6b4", outline="4a3f2c", light="f6eed8", name="desk_beige")
BEIGE_KEYS = BEIGE.add("c9b88f", "key")

# Planta del escritorio (en 1/32 de casilla): tablero rectangular, 30 de ancho por 20 de fondo, pegado al
# frente de la casilla (donde va la silla); atrás queda libre. La pantalla va cerca de quien se sienta.
TOP_X0, TOP_X1, TOP_Y0, TOP_Y1 = 1, 31, 2, 22
PED_X0, PED_X1, PED_Y0, PED_Y1 = 21, 30, 4, 20  # cajonera
PED_Z0 = 3  # la cajonera va sobre un zócalo hundido
LEG = 3  # lado de las patas (6 px de pantalla por eje)
LEG_X0 = 2
LEG_YS = (4, 17)  # patas del lado −x: adelante y atrás
SKIRT_Y0, SKIRT_Z0 = 18, 18  # faldón de atrás, entre la pata de atrás y la cajonera
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

def desk_model(c, x0=None, x1=None):
    """Escritorio con rotación 0: frente a −y. x0 y x1 = puntas del tablero (por defecto las del
    sencillo); la cajonera va en la punta +x y las patas en la −x."""
    x0 = TOP_X0 if x0 is None else x0
    x1 = TOP_X1 if x1 is None else x1
    ped0, ped1 = x1 - (TOP_X1 - PED_X0), x1 - (TOP_X1 - PED_X1)
    leg0 = x0 + (LEG_X0 - TOP_X0)
    # Zócalo hundido y cajonera con los cajones al frente; su cara hacia el hueco, en sombra.
    c.box((ped0 + 1) * U, (ped1 - 1) * U, (PED_Y0 + 1) * U, (PED_Y1 - 1) * U, 0, PED_Z0, WOOD,
          shade=-1, name="plinth")
    c.box(ped0 * U, ped1 * U, PED_Y0 * U, PED_Y1 * U, PED_Z0, LEGS, WOOD,
          tex={iso.FRONT: with_under_top(drawer_front), iso.X1: with_under_top(side_panel),
               iso.BACK: with_under_top(side_panel), iso.X0: under_top},
          shade={iso.X0: -1}, name="pedestal")
    # Patas gruesas del lado −x.
    for y0 in LEG_YS:
        c.box(leg0 * U, (leg0 + LEG) * U, y0 * U, (y0 + LEG) * U, 0, LEGS, WOOD,
              tex={"sides": under_top}, name="leg")
    # Faldón de atrás: por delante es el fondo del hueco (en sombra).
    c.box((leg0 + LEG) * U, ped0 * U, SKIRT_Y0 * U, (SKIRT_Y0 + 1) * U, SKIRT_Z0, LEGS, WOOD,
          tex={"sides": under_top}, shade={iso.FRONT: -1}, name="skirt")
    # Tablero con vuelo (las puntas las recorta el acabado).
    c.box(x0 * U, x1 * U, TOP_Y0 * U, TOP_Y1 * U, LEGS, TOP, WOOD, name="top")


def desk(rotation):
    c = iso.Canvas.furniture(DESK["size"], DESK["height"], rotation)
    desk_model(c)
    return c


def desk_shadow(rotation, size=None, x0=None, x1=None):
    """Sombra del escritorio: cajonera y patas enteras y, del tablero, solo el centro (metido
    SHADOW_INSET por lado), corrida abajo a la derecha."""
    x0 = TOP_X0 if x0 is None else x0
    x1 = TOP_X1 if x1 is None else x1
    ped0, ped1 = x1 - (TOP_X1 - PED_X0), x1 - (TOP_X1 - PED_X1)
    leg0 = x0 + (LEG_X0 - TOP_X0)
    c = iso.Canvas.furniture(size or DESK["size"], DESK["height"], rotation)
    c.box(ped0 * U, ped1 * U, PED_Y0 * U, PED_Y1 * U, 0, LEGS, WOOD)
    for y0 in LEG_YS:
        c.box(leg0 * U, (leg0 + LEG) * U, y0 * U, (y0 + LEG) * U, 0, LEGS, WOOD)
    c.box((x0 + SHADOW_INSET) * U, (x1 - SHADOW_INSET) * U, (TOP_Y0 + SHADOW_INSET) * U,
          (TOP_Y1 - SHADOW_INSET) * U, 0, TOP, WOOD)
    return c.ground_shadow(shift=SHADOW_SHIFT, color=SHADOW_COLOR)


# ---------------------------------------------------------------------------- piezas de las computadoras
#
# Cada spec: monitor (x0, x1, z0, z1 sobre el piso), su cuerpo, cómo se pinta el marco, el teclado y
# lo que lleve aparte (torre). La pantalla mira a −y (el frente del escritorio); su cara está en
# y = SCREEN_Y.

SCREEN_Y = 13
SCREEN_DEPTH = 2

# Dos niveles que se distinguen de lejos por la silueta y el color:
#   básica  todo en uno crema de los 80: caja alta, pantalla chica arriba, ranura del disquete; sin
#           torre; teclado y ratón crema
#   pro     monitor plano negro, torre negra con luz azul, teclado y ratón negros
# Pantalla del pro: un monitor de 24" 16:9 mide unos 54 × 32 cm con el marco y su borde de abajo queda
# a unos 10 cm de la mesa. Ancho: 54 cm = 17 unidades (34 px a lo largo del eje). Alto: con la escala
# de los muebles (0.59 px/cm) se ve aplastada frente a su ancho; se usa la de esta proyección
# (0.78 px/cm): 32 cm = 25 px, y el pie 8 px.
# depth = fondo de la caja de la pantalla; case = caja acostada debajo (x0, x1, y0, y1, alto);
# stand = si lleva pie; slot = ranura del disquete en el mentón; glass = vidrio de la pantalla;
# bulge = bulto de atrás; vents = ranuras en los costados.
SW, SZ0, SZ1 = 17, 8, 33


def flat(x0, x1=None, z0=SZ0, z1=SZ1):
    """Pantalla plana negra del pro (por defecto, la de 17 unidades)."""
    x1 = x0 + SW if x1 is None else x1
    return {"monitor": (x0, x1, DESK_Z + z0, DESK_Z + z1), "body": PLASTIC, "bezel": (1, 1, 3), "frame": None,
            "depth": 2, "case": None, "glass": GLASS, "bulge": True, "vents": False}


def black_set(spec, keyboard_x, mouse_x, tower):
    """Suma a una pantalla el teclado y el ratón negros y la torre (x0, x1, y0, y1, z1[, base])."""
    spec = dict(spec, keyboard=(keyboard_x, keyboard_x + 14, 2, 7), board=PLASTIC, keys=(KEYS_GREY, PLASTIC),
                mouse=(mouse_x, 4, PLASTIC), tower=tower[:5])
    if len(tower) > 5:
        spec["tower_base"] = tower[5]
    return spec


def cream(x0):
    """El todo en uno crema con su teclado y su ratón, desde x0."""
    return {"monitor": (x0, x0 + 12, DESK_Z, DESK_Z + 34), "body": BEIGE, "bezel": (4, 4, 14), "frame": None,
            "depth": 10, "case": None, "stand": False, "slot": True, "glass": TUBE, "bulge": False, "vents": True,
            "keyboard": (x0, x0 + 12, 3, 8), "board": BEIGE, "keys": (BEIGE_KEYS, BEIGE), "mouse": (x0 + 15, 6, BEIGE),
            "tower": None}


def wing(inner_x, side, width=SW, z0=SZ0, z1=SZ1, turn=0.5):
    """Pantalla girada hacia quien se sienta: sale del borde de la principal en inner_x hacia afuera
    (side −1 o +1) y hacia el frente. turn = cuánto viene al frente por cada unidad de ancho."""
    return {"wing": (inner_x, side), "width": width, "z": (z0, z1), "turn": turn}


def shifted_spec(spec, dx):
    """La misma pieza corrida dx unidades a lo largo del escritorio."""
    out = dict(spec)
    if "wing" in out:
        out["wing"] = (out["wing"][0] + dx, out["wing"][1])
        return out
    x0, x1, z0, z1 = out["monitor"]
    out["monitor"] = (x0 + dx, x1 + dx, z0, z1)
    if "keyboard" in out:
        k = out["keyboard"]
        out["keyboard"] = (k[0] + dx, k[1] + dx, k[2], k[3])
        out["mouse"] = (out["mouse"][0] + dx,) + tuple(out["mouse"][1:])
    if out.get("tower") is not None:
        t = out["tower"]
        out["tower"] = (t[0] + dx, t[1] + dx) + tuple(t[2:])
    return out


TOWER_ON = (9, 21, DESK_Z + 26)  # torre sobre el tablero: y0, y1 y hasta dónde sube
# Sobre un escritorio de una casilla (y, centradas, sobre el ejecutivo): un sprite aparte.
SPECS = {
    "basic": [cream(10)],
    "pro": [black_set(flat(11), 12, 8, (3, 8) + TOWER_ON)],
}
# Escritorio largo: tablero de 46 unidades (92 px) centrado en sus dos casillas (de 9 a 55). Sus
# conjuntos van dibujados con el escritorio en un solo sprite (la torre del de tres pantallas va
# debajo de la mesa y un sprite aparte no podría quedar detrás del tablero). Medidas desde la punta
# −x del tablero; nada amontonado en una punta.
LONG_X0, LONG_X1 = 9, 55
LONG_CANVAS_HEIGHT = 40  # px del mundo: lo que sube la pantalla más alta sobre el piso
LONG_SETS = {
    "": [],
    "basic": [cream(17)],
    # torre · pantalla al medio
    "pro1": [black_set(flat(15), 17, 34, (3, 8) + TOWER_ON)],
    # torre · principal · segunda girada, de punta a punta
    "pro2": [black_set(flat(10), 11, 7, (2, 7) + TOWER_ON), wing(27.5, 1)],
    # tres en alas y la torre en el piso, debajo de la mesa
    "pro3": [black_set(flat(15), 16, 33, (5, 10, 7, 19, 28, 0)), wing(14.5, -1), wing(32.5, 1)],
}
for _key in LONG_SETS:
    LONG_SETS[_key] = [shifted_spec(_spec, LONG_X0 - TOP_X0) for _spec in LONG_SETS[_key]]


def seat_x(specs, default):
    """Dónde queda el centro del teclado a lo largo del modelo, en casillas (ahí va quien se sienta)."""
    for spec in specs:
        if "keyboard" in spec:
            return (spec["keyboard"][0] + spec["keyboard"][1]) / 2.0 * U
    return default


def draw_wing(c, spec, index):
    """Pantalla girada: dos paneles (cara y espalda) con su canto de arriba y de la punta, sobre su pie."""
    inner_x, side = spec["wing"]
    width = spec["width"]
    z0, z1 = spec["z"]
    y = SCREEN_Y
    length = math.sqrt(1.0 + spec["turn"] ** 2)
    dx, dy = side * width / length, -width * spec["turn"] / length
    nx, ny = (-dy / width, dx / width)  # normal unitaria; se elige la que mira al frente (−y)
    if ny > 0:
        nx, ny = -nx, -ny
    h = z1 - z0
    mid = (round((inner_x + dx / 2.0) * 2.0) / 2.0, round((y + dy / 2.0) * 2.0) / 2.0)  # el pie, en la rejilla
    c.box((mid[0] - 3) * U, (mid[0] + 3) * U, (mid[1] - 1) * U, (mid[1] + 4) * U, DESK_Z, DESK_Z + 2, PLASTIC,
          name="wfoot%d" % index)
    c.box((mid[0] - 1) * U, (mid[0] + 1) * U, (mid[1] + 1.5) * U, (mid[1] + 2.5) * U, DESK_Z + 2, DESK_Z + z0 + 5,
          PLASTIC, name="wneck%d" % index)
    front = "wfront%d" % index
    c.panel((inner_x * U, y * U, DESK_Z + z0), (dx * U, dy * U, 0), (0, 0, h), PLASTIC, index=pal.LEFT, name=front)
    t = 1.6  # grosor
    back = "wback%d" % index
    c.panel(((inner_x - nx * t) * U, (y - ny * t) * U, DESK_Z + z0), (dx * U, dy * U, 0), (0, 0, h), PLASTIC,
            index=pal.RIGHT, name=back)
    c.panel((inner_x * U, y * U, DESK_Z + z1), (dx * U, dy * U, 0), (-nx * t * U, -ny * t * U, 0), PLASTIC,
            index=pal.BASE, name="wtop%d" % index)
    c.panel(((inner_x + dx) * U, (y + dy) * U, DESK_Z + z0), (-nx * t * U, -ny * t * U, 0), (0, 0, h), PLASTIC,
            index=pal.DEEP, name="wend%d" % index)
    a = np.floor(c.a)
    b = np.floor(c.b)
    w = width * 2
    face = c.select(part=front)
    display = face & (a >= 2) & (a < w - 2) & (b >= 3) & (b < h - 2)
    c.paint(display, pal.BASE, GLASS)
    c.paint(display & ((b == h - 3) | (a == 2)), pal.RIGHT, GLASS)
    diagonal = a + (h - b)
    glare = display & (((diagonal >= w * 0.62) & (diagonal < w * 0.62 + 5))
                       | ((diagonal >= w * 0.62 + 8) & (diagonal < w * 0.62 + 10)))
    c.paint(glare & (a > 2) & (b < h - 3), pal.LIGHT, GLASS)
    # Espalda: el mismo bulto con ranuras que la pantalla recta, pintado.
    rear = c.select(part=back)
    plate = rear & (a >= w // 4) & (a < w - w // 4) & (b >= 3) & (b < h - 4)
    c.paint(plate, pal.LEFT)
    for slot in (h - 8, h - 11):
        c.paint(plate & (b == slot) & (a >= w // 4 + 3) & (a < w - w // 4 - 3), pal.DEEP)


def draw_set(c, specs):
    """Dibuja un conjunto (pantallas, teclado, ratón, torre) sobre el lienzo."""
    for index, spec in enumerate(specs):
        if "wing" in spec:
            draw_wing(c, spec, index)
            continue
        if spec.get("tower") is not None:
            tower(c, spec)
        monitor(c, spec)
        if "keyboard" in spec:
            keyboard(c, spec)


def monitor(c, spec):
    """Monitor: pie y cuello (o la caja acostada de la computadora vieja), la caja de la pantalla y
    el bulto de atrás; pinta la pantalla."""
    x0, x1, z0, z1 = spec["monitor"]
    body = spec["body"]
    depth = spec["depth"]
    mid = (x0 + x1) / 2.0
    if spec["case"] is not None:
        cx0, cx1, cy0, cy1, ch = spec["case"]
        c.box(cx0 * U, cx1 * U, cy0 * U, cy1 * U, DESK_Z, DESK_Z + ch, body, name="case")
        paint_case(c, spec)
    elif spec.get("stand", True):
        half = max(2, (x1 - x0) // 4)
        c.box((mid - half) * U, (mid + half) * U, (SCREEN_Y - 1) * U, (SCREEN_Y + 5) * U, DESK_Z, DESK_Z + 2, body,
              name="foot")
        c.box((mid - 2) * U, (mid + 2) * U, (SCREEN_Y + depth + 1) * U, (SCREEN_Y + depth + 2) * U,
              DESK_Z + 2, z0 + 6, body, name="neck")
    c.box(x0 * U, x1 * U, SCREEN_Y * U, (SCREEN_Y + depth) * U, z0, z1, body, name="screen")
    if spec["bulge"]:
        inset = max(2, (x1 - x0) // 4)
        c.box((x0 + inset) * U, (x1 - inset) * U, (SCREEN_Y + depth) * U, (SCREEN_Y + depth + 1) * U,
              z0 + 3, z1 - 4, body, name="bulge")
    c.style_part("screen", rim="full")
    paint_screen(c, spec)
    if spec["bulge"]:
        paint_back(c)
    if spec["vents"]:
        paint_vents(c, spec)


def paint_case(c, spec):
    """Caja acostada de la computadora vieja: ranura del disquete, su botón y la luz de encendido."""
    cx0, cx1, _cy0, _cy1, ch = spec["case"]
    front = c.select(part="case", face=iso.FRONT)
    a = np.floor(c.a)
    b = np.floor(c.b)
    w = (cx1 - cx0) * 2
    c.paint(whole_runs(front & (b == ch - 3) & (a >= w - 16) & (a < w - 4)), pal.DEEP)
    c.paint(whole_runs(front & (b == ch - 4) & (a >= w - 16) & (a < w - 4)), pal.LIGHT)
    c.paint(front & (b >= 1) & (b < 3) & (a >= 4) & (a < 6), pal.BASE, LED)
    c.paint(whole_runs(front & (b == 1) & (a >= 10) & (a < 18)), pal.RIGHT)


def paint_vents(c, spec):
    """Ranuras de ventilación verticales en los costados del monitor de tubo."""
    _x0, _x1, z0, z1 = spec["monitor"]
    a = np.floor(c.a)
    b = np.floor(c.b)
    h = z1 - z0
    w = spec["depth"] * 2
    for face in (iso.X0, iso.X1):
        side = c.select(part="screen", face=face)
        for column in range(6, w - 3, 3):
            c.paint(side & (a == column) & (b >= 4) & (b < h - 4), pal.DEEP)


def paint_screen(c, spec):
    """Cara de la pantalla: marco (bisel) del cuerpo o de otro tono, vidrio oscuro con la sombra del
    marco arriba y a la izquierda y dos reflejos en diagonal, y la luz de encendido en el mentón."""
    x0, x1, z0, z1 = spec["monitor"]
    side, top, chin = spec["bezel"]
    glass = spec["glass"]
    face = c.select(part="screen", face=iso.FRONT)
    a = np.floor(c.a)
    b = np.floor(c.b)
    w = (x1 - x0) * 2
    h = z1 - z0
    if spec["frame"] is not None:
        # Marco de otro tono alrededor de la pantalla (el mentón queda del color del cuerpo).
        frame = face & (b >= chin - 1)
        c.paint(frame, pal.RIGHT, spec["frame"])
    display = face & (a >= side) & (a < w - side) & (b >= chin) & (b < h - top)
    c.paint(display, pal.BASE, glass)
    c.paint(display & ((b == h - top - 1) | (a == side)), pal.RIGHT, glass)
    # Reflejos: una diagonal ancha y otra fina, de arriba a la derecha hacia abajo.
    diagonal = a + (h - b)
    wide = display & (diagonal >= w * 0.62) & (diagonal < w * 0.62 + 5)
    thin = display & (diagonal >= w * 0.62 + 8) & (diagonal < w * 0.62 + 10)
    inner = display & (a > side) & (b < h - top - 1)
    c.paint((wide | thin) & inner, pal.LIGHT, glass)
    if spec.get("slot"):
        # Todo en uno de los 80: ranura del disquete en el mentón, a la derecha, y un zócalo marcado abajo.
        slot_b = chin // 2 + 1
        c.paint(whole_runs(face & (b == slot_b) & (a >= w // 2) & (a < w - side - 1)), pal.DEEP)
        c.paint(whole_runs(face & (b == slot_b - 1) & (a >= w // 2) & (a < w - side - 1)), pal.LIGHT)
        c.paint(whole_runs(face & (b == 2)), pal.RIGHT)
        c.paint(face & (a >= side) & (a < side + 2) & (b >= slot_b - 1) & (b <= slot_b), pal.BASE, LED)
        return
    # Luz de encendido en el mentón.
    led = face & (a >= w - side - 5) & (a < w - side - 3) & (b == max(chin // 2, 1))
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
    """Torre (el CPU) sobre el tablero. tower_style "retro": caja crema con dos bahías, ranura del
    disquete, botón y luz; si no, caja negra moderna con franja de luz al frente y ventana con
    luces en los costados. Rejilla atrás en las dos."""
    x0, x1, y0, y1, z1 = spec["tower"]
    body = spec.get("tower_body", PLASTIC)
    base = spec.get("tower_base", DESK_Z)  # 0 = en el piso, al lado del escritorio
    c.box(x0 * U, x1 * U, y0 * U, y1 * U, base, z1, body, name="tower")
    a = np.floor(c.a)
    b = np.floor(c.b)
    h = z1 - base
    front = c.select(part="tower", face=iso.FRONT)
    fw = (x1 - x0) * 2
    if spec.get("tower_style") == "retro":
        for top in (h - 3, h - 8):  # dos bahías: marco hundido con su canto claro abajo
            bay = front & (a >= 1) & (a < fw - 1) & (b >= top - 3) & (b < top)
            c.paint(bay, pal.LEFT)
            c.paint(whole_runs(bay & (b == top - 1)), pal.DEEP)
            c.paint(whole_runs(bay & (b == top - 3)), pal.LIGHT)
        c.paint(whole_runs(front & (b == h - 14) & (a >= 2) & (a < fw - 2)), pal.DEEP)  # disquete
        c.paint(front & (a >= 2) & (a < 4) & (b >= 3) & (b < 5), pal.BASE, LED)
        c.paint(front & (a >= fw - 4) & (a < fw - 2) & (b >= 3) & (b < 5), pal.RIGHT)
        for face in (iso.X0, iso.X1):
            side = c.select(part="tower", face=face)
            w = (y1 - y0) * 2
            for row in range(4, 11, 2):
                c.paint(whole_runs(side & (b == row) & (a >= 4) & (a < w - 4)), pal.DEEP)
    else:
        c.paint(front & (a >= 2) & (a < 4) & (b >= 4) & (b < h - 4), pal.BASE, CYAN)
        c.paint(front & (a >= 6) & (a < 8) & (b >= h - 6) & (b < h - 4), pal.BASE, LED)
        for face in (iso.X0, iso.X1):
            side = c.select(part="tower", face=face)
            w = (y1 - y0) * 2
            window = side & (a >= 3) & (a < w - 3) & (b >= 4) & (b < h - 4)
            c.paint(window, pal.DEEP)
            c.paint(window & (b >= h - 9) & (b < h - 7) & (a >= 5) & (a < w - 5), pal.BASE, CYAN)
            c.paint(window & (b >= 7) & (b < 9) & (a >= 5) & (a < w - 5), pal.BASE, CYAN)
            fan = window & (b >= 11) & (b < h - 11) & (a >= w // 2 - 3) & (a < w // 2 + 3)
            c.paint(fan, pal.RIGHT, CYAN)
    back = c.select(part="tower", face=iso.BACK)
    for row in range(6, h - 6, 3):
        c.paint(whole_runs(back & (b == row) & (a >= 2) & (a < fw - 2)), pal.DEEP)


def set_height(specs):
    """Alto para el lienzo de un conjunto, en px del mundo."""
    z1 = DESK_Z
    for spec in specs:
        if "wing" in spec:
            z1 = max(z1, DESK_Z + spec["z"][1])
        else:
            z1 = max(z1, spec["monitor"][3])
    return int(np.ceil((z1 - DESK_Z) / 2.0))


def computer(kind, rotation):
    c = iso.Canvas.on_desk(rotation, max(COMPUTERS[kind]["height"], set_height(SPECS[kind])))
    draw_set(c, SPECS[kind])
    return c


def long_desk(rotation, key):
    """Escritorio largo (2×1) con el conjunto `key` de LONG_SETS encima ("" = vacío)."""
    c = iso.Canvas.furniture(LONG["size"], LONG_CANVAS_HEIGHT, rotation)
    desk_model(c, LONG_X0, LONG_X1)
    draw_set(c, LONG_SETS[key])
    return c


def long_desk_shadow(rotation):
    return desk_shadow(rotation, LONG["size"], LONG_X0, LONG_X1)


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


def monitor_shadow_box(spec):
    """Lo que apoya el monitor sobre el tablero: su pie, la caja acostada o el aparato entero."""
    x0, x1, _z0, _z1 = spec["monitor"]
    if spec["case"] is not None:
        cx0, cx1, cy0, cy1, ch = spec["case"]
        return (cx0, cx1, cy0, cy1, ch)
    if not spec.get("stand", True):
        return (x0, x1, SCREEN_Y, SCREEN_Y + spec["depth"], 6)
    mid = (x0 + x1) / 2.0
    half = max(2, (x1 - x0) // 4)
    return (mid - half, mid + half, SCREEN_Y - 1, SCREEN_Y + 5, 2)


def computer_shadow(kind, rotation):
    spec = SPECS[kind][0]
    kx0, kx1, ky0, ky1 = spec["keyboard"]
    boxes = [monitor_shadow_box(spec), (kx0, kx1, ky0, ky1, 2)]
    if spec["tower"] is not None:
        tx0, tx1, ty0, ty1, _tz = spec["tower"]
        boxes.append((tx0, tx1, ty0, ty1, 6))
    return contact_shadow(rotation, max(COMPUTERS[kind]["height"], set_height(SPECS[kind])), boxes, spec["mouse"][:2])


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


def desk_base(load, rotation):
    """Piso, sombra y escritorio en un lienzo del alto de lo que va encima (32 px más que el suyo)."""
    low = sheet.plain_tile()
    with_shadow(low, load("desk_simple_r%d_shadow" % rotation))
    low.alpha_composite(load("desk_simple_r%d" % rotation))
    base = Image.new("RGBA", (low.size[0], low.size[1] + 32), (0, 0, 0, 0))
    base.paste(low, (0, 32))
    return base


def contact_sheet(out_dir):
    """Hoja de contacto: escritorio sencillo con cada computadora y el largo con cada conjunto."""
    def load(name):
        return sheet.load(os.path.join(out_dir, name + ".png"))

    items = []
    for r in range(4):
        items.append(("desk_simple_r%d" % r, load("desk_simple_r%d" % r)))
    for kind in ("basic", "pro"):
        for r in range(4):
            both = desk_base(load, r)
            with_shadow(both, load("computer_%s_r%d_shadow" % (kind, r)))
            both.alpha_composite(load("computer_%s_r%d" % (kind, r)))
            items.append(("computer_%s_r%d" % (kind, r), both))
    for key in LONG_KEYS:
        for r in range(4):
            name = long_name(key, r)
            image = load(name)
            both = Image.new("RGBA", image.size, (0, 0, 0, 0))
            with_shadow(both, load(name + "_shadow"))
            both.alpha_composite(image)
            items.append((name, both))
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    path = os.path.join(folder, "desk.png")
    sheet.contact_sheet(items, columns=4, scale=3).save(path)
    return path


LONG_KEYS = ("", "basic", "pro1", "pro2", "pro3")


def long_name(key, rotation):
    return "desk_long%s_r%d" % ("_" + key if key else "", rotation)


def seats():
    """Para el juego: a qué altura del modelo (en casillas, a lo largo del mueble) queda el teclado de
    cada sprite, que es donde se dibuja quien se sienta."""
    result = {"computer_basic": seat_x(SPECS["basic"], 0.5), "computer_pro": seat_x(SPECS["pro"], 0.5)}
    for key in LONG_KEYS:
        result["desk_long" + ("_" + key if key else "")] = seat_x(LONG_SETS[key], (LONG_X0 + LONG_X1) / 2.0 * U)
    return result


def build(out_dir):
    files = []
    for rotation in range(4):
        c = desk(rotation)
        files.append(iso.save(c, out_dir, "desk_simple_r%d" % rotation))
        files.append(iso.save(desk_shadow(rotation), out_dir, "desk_simple_r%d_shadow" % rotation, kind="shadow",
                              footprint=list(c.world_size), anchor=list(c.anchor)))
        for kind in ("basic", "pro"):
            name = "computer_%s_r%d" % (kind, rotation)
            files.append(iso.save(computer(kind, rotation), out_dir, name))
            files.append(iso.save(computer_shadow(kind, rotation), out_dir, name + "_shadow", kind="shadow",
                                  anchor=[64, 128], surface_z=DESK_Z))
        shadow = long_desk_shadow(rotation)
        for key in LONG_KEYS:
            c = long_desk(rotation, key)
            name = long_name(key, rotation)
            files.append(iso.save(c, out_dir, name, seat_x=seats()["desk_long" + ("_" + key if key else "")]))
            files.append(iso.save(shadow, out_dir, name + "_shadow", kind="shadow", footprint=list(c.world_size),
                                  anchor=list(c.anchor)))
    contact_sheet(out_dir)
    return files
