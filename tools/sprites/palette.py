# Colores y rampas de los sprites (docs/sprites_128.md, sección 4).
#
# Una rampa son 8 tonos de un mismo material, del más oscuro al más claro. Los tres de las
# caras planas son EXACTOS (lo mismo que Color.darkened de Godot):
#   BASE  = color base de data/*.json (cara de arriba)
#   LEFT  = base −25 % (cara izquierda)
#   RIGHT = base −40 % (cara derecha)
# El corrimiento de tono solo va en los demás (contorno, sombra profunda, brillos).
import colorsys

import numpy as np

# Índices de una rampa (de oscuro a claro).
OUTLINE = 0  # contorno: tono oscuro del mismo color, nunca negro puro
DEEP = 1  # sombra profunda: rendijas, huecos, sombra de contacto sobre la cara derecha
RIGHT = 2  # cara derecha: base −40 % exacto
LEFT = 3  # cara izquierda: base −25 % exacto
SOFT = 4  # detalle suave sobre la cara de arriba (base −12 %): vetas, marcas
BASE = 5  # cara de arriba: color base exacto
LIGHT = 6  # brillo de arista
SHINE = 7  # reflejo fuerte (metal, vidrio, pantallas)
STEP_COUNT = 8
STEP_NAMES = ["outline", "deep", "right", "left", "soft", "base", "light", "shine"]

LEFT_DARKEN = 0.25
RIGHT_DARKEN = 0.40
SOFT_DARKEN = 0.12
MIN_OUTLINE_VALUE = 12  # canal más alto mínimo del contorno (nunca negro puro)

# Un paso de sombra / de luz para cada índice (un paso = una cara, no un tono).
_DARKER = [OUTLINE, OUTLINE, DEEP, RIGHT, LEFT, LEFT, BASE, LIGHT]
_LIGHTER = [DEEP, RIGHT, LEFT, SOFT, BASE, LIGHT, SHINE, SHINE]

# Hacia dónde se corre el tono: sombras hacia el azul violáceo, luces hacia el amarillo.
COOL_HUE = 250.0 / 360.0
WARM_HUE = 50.0 / 360.0


def hex_to_rgb(value):
    """'c9b48a', '#c9b48a' o una terna -> (r, g, b) con enteros de 0 a 255."""
    if isinstance(value, (tuple, list, np.ndarray)):
        return (int(value[0]), int(value[1]), int(value[2]))
    text = str(value).strip().lstrip("#")
    if len(text) != 6:
        raise ValueError("color hex inválido: %r" % (value,))
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))


def rgb_to_hex(color):
    r, g, b = hex_to_rgb(color)
    return "%02x%02x%02x" % (r, g, b)


def _round_channel(value):
    return int(min(255, max(0, int(value + 0.5))))


def darken(color, amount):
    """Oscurece EXACTO como Color.darkened(amount) de Godot: canal × (1 − amount), redondeado.

    darken("c9b48a", 0.25) es la cara izquierda; darken(..., 0.40) la derecha.
    """
    r, g, b = hex_to_rgb(color)
    factor = 1.0 - float(amount)
    return (_round_channel(r * factor), _round_channel(g * factor), _round_channel(b * factor))


def lighten(color, amount):
    """Aclara como Color.lightened(amount): canal + (255 − canal) × amount."""
    r, g, b = hex_to_rgb(color)
    amount = float(amount)
    return (_round_channel(r + (255 - r) * amount), _round_channel(g + (255 - g) * amount),
            _round_channel(b + (255 - b) * amount))


def mix(color_a, color_b, weight):
    """Mezcla lineal: weight 0 = color_a, 1 = color_b."""
    a = hex_to_rgb(color_a)
    b = hex_to_rgb(color_b)
    return tuple(_round_channel(a[i] + (b[i] - a[i]) * float(weight)) for i in range(3))


def luminance(color):
    """Brillo percibido (0–255) de un color: 0.299 R + 0.587 G + 0.114 B."""
    r, g, b = hex_to_rgb(color)
    return 0.299 * r + 0.587 * g + 0.114 * b


def adjust(color, value=1.0, saturation=1.0, hue_toward=None, hue_amount=0.0, tint=0.0):
    """Cambia un color en HSV: brillo × value, saturación × saturation y el tono corrido
    hue_amount (0–1 del camino más corto) hacia hue_toward (0–1). tint es la saturación mínima
    que se le da a un gris para que el corrimiento se note (0 = dejarlo gris).
    """
    r, g, b = [c / 255.0 for c in hex_to_rgb(color)]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if hue_toward is not None:
        if s < 0.04:
            h = hue_toward
            s = max(s, tint)
        else:
            delta = ((hue_toward - h + 0.5) % 1.0) - 0.5
            h = (h + delta * hue_amount) % 1.0
    s = min(1.0, max(0.0, s * saturation))
    v = min(1.0, max(0.0, v * value))
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return (_round_channel(r * 255.0), _round_channel(g * 255.0), _round_channel(b * 255.0))


def darker(index, steps=1):
    """Índice de rampa un paso de sombra más abajo (BASE→LEFT→RIGHT→DEEP→OUTLINE). Acepta arreglos."""
    table = np.array(_DARKER, dtype=np.int16)
    out = np.asarray(index).astype(np.int16)
    extra = out >= STEP_COUNT
    for _ in range(int(steps)):
        out = np.where(extra, out, table[np.clip(out, 0, STEP_COUNT - 1)])
    return out


def lighter(index, steps=1):
    """Índice de rampa un paso de luz más arriba (RIGHT→LEFT→SOFT→BASE→LIGHT→SHINE). Acepta arreglos."""
    table = np.array(_LIGHTER, dtype=np.int16)
    out = np.asarray(index).astype(np.int16)
    extra = out >= STEP_COUNT
    for _ in range(int(steps)):
        out = np.where(extra, out, table[np.clip(out, 0, STEP_COUNT - 1)])
    return out


class Ramp(object):
    """Lista de colores de un material. Los 8 primeros son los pasos OUTLINE…SHINE; con add()
    se suman tonos propios (índices 8, 9…), que darker()/lighter() dejan igual.

    ramp[i] da el color (r, g, b); ramp.base_hex el hex de origen; len(ramp) cuántos tiene.
    """

    def __init__(self, colors, base_hex=None, name=None):
        self.colors = [hex_to_rgb(c) for c in colors]
        self.base_hex = base_hex
        self.name = name or base_hex or "ramp"
        self.names = {}
        # True si LEFT / RIGHT no son el −25 % / −40 % calculado sino tonos declarados a mano
        # (rampas de STYLE.md): el manifiesto los anota y check.py los acepta (ver style_ramp).
        self.declared = False

    def __len__(self):
        return len(self.colors)

    def __getitem__(self, index):
        return self.colors[index]

    def __iter__(self):
        return iter(self.colors)

    def add(self, color, name=None):
        """Suma un tono propio (hex o terna) y devuelve su índice. Repetir un color devuelve el que ya estaba."""
        rgb = hex_to_rgb(color)
        if rgb in self.colors[STEP_COUNT:]:
            index = STEP_COUNT + self.colors[STEP_COUNT:].index(rgb)
        else:
            self.colors.append(rgb)
            index = len(self.colors) - 1
        if name:
            self.names[name] = index
        return index

    def index(self, name):
        """Índice de un paso por nombre ('base', 'left'…) o de un tono sumado con add(name=…)."""
        if name in self.names:
            return self.names[name]
        return STEP_NAMES.index(name)

    def replace(self, index, color):
        """Cambia un tono en el lugar (por ejemplo un contorno a mano). Devuelve la misma rampa."""
        self.colors[index] = hex_to_rgb(color)
        return self

    def table(self):
        """Arreglo uint8 (n, 3) para pintar con índices."""
        return np.array(self.colors, dtype=np.uint8)

    def hexes(self):
        return [rgb_to_hex(c) for c in self.colors]

    def faces(self):
        """Los tonos de las tres caras planas: {'top', 'left', 'right'} -> hex."""
        return {"top": rgb_to_hex(self.colors[BASE]), "left": rgb_to_hex(self.colors[LEFT]),
                "right": rgb_to_hex(self.colors[RIGHT])}


def ramp(base, outline=None, deep=None, soft=None, light=None, shine=None, name=None, shift=1.0):
    """Rampa de 8 tonos a partir del color base (hex de data/*.json).

    RIGHT, LEFT y BASE salen exactos (−40 %, −25 %, base). Los demás se calculan con un
    corrimiento de tono leve (shift lo escala; 0 = sin corrimiento) y se pueden fijar a mano
    pasando un hex en outline, deep, soft, light o shine.
    """
    base_rgb = hex_to_rgb(base)
    colors = [None] * STEP_COUNT
    colors[BASE] = base_rgb
    colors[LEFT] = darken(base_rgb, LEFT_DARKEN)
    colors[RIGHT] = darken(base_rgb, RIGHT_DARKEN)
    colors[OUTLINE] = hex_to_rgb(outline) if outline is not None else adjust(
        base_rgb, 0.40, 1.0 + 0.25 * shift, COOL_HUE, 0.10 * shift, 0.10 * shift)
    colors[DEEP] = hex_to_rgb(deep) if deep is not None else adjust(
        base_rgb, 0.50, 1.0 + 0.15 * shift, COOL_HUE, 0.06 * shift, 0.06 * shift)
    colors[SOFT] = hex_to_rgb(soft) if soft is not None else darken(base_rgb, SOFT_DARKEN)
    if light is not None:
        colors[LIGHT] = hex_to_rgb(light)
    else:
        colors[LIGHT] = adjust(lighten(base_rgb, 0.20), 1.0, 1.0 - 0.12 * shift, WARM_HUE, 0.08 * shift, 0.05 * shift)
    if shine is not None:
        colors[SHINE] = hex_to_rgb(shine)
    else:
        colors[SHINE] = adjust(lighten(base_rgb, 0.48), 1.0, 1.0 - 0.25 * shift, WARM_HUE, 0.12 * shift, 0.04 * shift)
    if max(colors[OUTLINE]) < MIN_OUTLINE_VALUE:
        # La guía pide un contorno «más oscuro del mismo color (no negro puro)»: con una base
        # casi negra se deja un mínimo azulado.
        colors[OUTLINE] = (MIN_OUTLINE_VALUE - 4, MIN_OUTLINE_VALUE - 4, MIN_OUTLINE_VALUE)
    return Ramp(colors, base_hex=rgb_to_hex(base_rgb), name=name)


def tones(base, factors, name=None):
    """Paleta libre para pisos: un color por factor de brillo (1.0 = base exacto, 0.9 = −10 %,
    1.08 = aclarado 8 % hacia el blanco). Devuelve una Ramp sin pasos con nombre: se usa por índice.
    """
    colors = []
    for factor in factors:
        if factor <= 1.0:
            colors.append(darken(base, 1.0 - factor))
        else:
            colors.append(lighten(base, factor - 1.0))
    return Ramp(colors, base_hex=rgb_to_hex(base), name=name)


def palette(colors, name=None):
    """Paleta libre a partir de una lista de hex o ternas, en el orden dado."""
    result = Ramp(colors, base_hex=None, name=name)
    return result


def face_colors(base):
    """Los tres colores exactos de una pieza de caras planas: {'top', 'left', 'right'} -> (r, g, b)."""
    return {"top": hex_to_rgb(base), "left": darken(base, LEFT_DARKEN), "right": darken(base, RIGHT_DARKEN)}


def mean_luminance(indices, ramp_or_colors, mask=None):
    """Brillo medio (0–255) de un arreglo de índices pintado con una paleta, dentro de mask."""
    table = np.array([hex_to_rgb(c) for c in ramp_or_colors], dtype=np.float64)
    lum = table[:, 0] * 0.299 + table[:, 1] * 0.587 + table[:, 2] * 0.114
    values = lum[np.asarray(indices)]
    if mask is not None:
        values = values[mask]
    return float(values.mean())


# ---------------------------------------------------------------------- estilo «Isometric Interiors»
#
# Rampas de tools/sprites/STYLE.md (hex sacados de las capturas de referencia). Cada fila de la
# tabla da contorno, sombra, lado, base (arriba) y brillo; cuando la sombra trae dos tonos, el
# más claro es la cara derecha (RIGHT) y el más oscuro la sombra profunda (DEEP, también la línea
# de las aristas interiores del acabado 'salvaje'). Los lados de la tabla NO son el −25 % / −40 %
# calculado: estas rampas salen con `declared = True` y check.py acepta esas caras tal cual, con
# la condición de que la luz siga arriba a la izquierda (brillo arriba > izquierda ≥ derecha).
#
# Dos cambios a la tabla, por la guía (docs/sprites_128.md manda): un contorno negro puro
# (plástico negro 000000, cerámica azul 020202) sube a MIN_OUTLINE_VALUE por canal (0c0c0c).
# El brillo del tapizado rojo (bc3f41) es casi igual a su base: queda así (es lo que se mide en
# la referencia); para un reflejo que se note usar SHINE.

STYLE_TABLE = {
    # nombre: (contorno, sombra(s), lado, base(s), brillo)   — None = se calcula
    "wood_orange": ("3c1300", ("894522", "743b0e"), "c26b24", ("df823d",), "eda85d"),
    "wood_floor": ("25241f", ("5b2421", "783a13"), "9d6035", ("ad6d40", "a5663a"), "b67647"),
    "upholstery_red": ("450e22", ("6d120a", "7c2323"), "9b323a", ("c03d43",), "bc3f41"),
    "plastic_black": ("000000", ("1c1c1c",), "222020", ("313030",), "4f4f4f"),
    "metal_light": ("3d3b44", ("77888c",), "97a2aa", ("d0e1e0",), "ffffff"),
    "wall_cool": (None, ("899da0",), "899da0", ("96acad",), "a3b6b7"),
    "wall_beige": (None, ("9e9c8d",), "afa08d", ("c2c0b2",), "efdfbd"),
    "wall_cap": ("21161a", ("3e2e33",), "493539", ("584549",), "675a64"),
    "door": ("2a211b", ("5e3e29",), "8d6e4f", ("afa08d",), "efdfbd"),
    "ceramic_white": ("3e2e33", ("a4a2a1",), "bbb9b9", ("e8e8e8",), "ffffff"),
    "ceramic_blue": ("020202", ("3895ca", "3d90c0"), "479ed1", ("6dacce",), "6eaed4"),
    "leaves": ("242f12", ("425423", "4c6029"), "648132", ("9ecc42",), "cbf166"),
    "clay": ("4e1c05", ("5d3526",), "8e6d53", ("c56a33",), "e2804a"),
    "screen": ("202020", ("3d90c0",), "479ed1", ("6dacce",), "d0e1e0"),
}

STYLE_OUTLINE_VALUE = 0.25  # contorno calculado: base × 0.25 de brillo, más saturado (casi negro del mismo tono)
STYLE_OUTLINE_SATURATION = 1.35
STYLE_LIGHT = 0.30  # brillo calculado: base aclarada 30 %


def _no_pure_black(color):
    rgb = hex_to_rgb(color)
    if max(rgb) < MIN_OUTLINE_VALUE:
        return tuple(max(c, MIN_OUTLINE_VALUE) for c in rgb)
    return rgb


def style_ramp(base, side=None, shadow=None, outline=None, deep=None, soft=None, light=None, shine=None,
               name=None):
    """Rampa de 8 tonos con el criterio de STYLE.md a partir de un hex base SATURADO (cara de arriba).

    Por defecto las caras siguen la guía: LEFT = base −25 % y RIGHT = base −40 % exactos. Pasar
    side= (cara izquierda) y/o shadow= (cara derecha) usa esos tonos en su lugar: la rampa queda
    con `declared = True`, el manifiesto anota las caras y check.py las exige tal cual (en vez del
    −25 / −40 calculado). Lo demás, si no se pasa:
      outline  casi negro del mismo tono (base × 0.25, más saturado; nunca negro puro)
      deep     entre el contorno y la cara derecha (sombra profunda y línea de aristas interiores)
      soft     mitad de camino entre la base y el lado (vetas, costuras sobre la cara de arriba)
      light    base aclarada 30 % (brillo de arista)
      shine    el brillo aclarado otro 45 % (reflejos de metal, vidrio, pantallas)
    """
    base_rgb = hex_to_rgb(base)
    colors = [None] * STEP_COUNT
    colors[BASE] = base_rgb
    colors[LEFT] = hex_to_rgb(side) if side is not None else darken(base_rgb, LEFT_DARKEN)
    colors[RIGHT] = hex_to_rgb(shadow) if shadow is not None else darken(base_rgb, RIGHT_DARKEN)
    if outline is not None:
        colors[OUTLINE] = _no_pure_black(outline)
    else:
        colors[OUTLINE] = _no_pure_black(adjust(base_rgb, STYLE_OUTLINE_VALUE, STYLE_OUTLINE_SATURATION))
    colors[DEEP] = _no_pure_black(deep) if deep is not None else mix(colors[OUTLINE], colors[RIGHT], 0.45)
    colors[SOFT] = hex_to_rgb(soft) if soft is not None else mix(colors[BASE], colors[LEFT], 0.5)
    if light is not None:
        colors[LIGHT] = hex_to_rgb(light)
    else:
        colors[LIGHT] = lighten(base_rgb, STYLE_LIGHT)
    colors[SHINE] = hex_to_rgb(shine) if shine is not None else lighten(colors[LIGHT], 0.45)
    result = Ramp(colors, base_hex=rgb_to_hex(base_rgb), name=name)
    result.declared = (colors[LEFT] != darken(base_rgb, LEFT_DARKEN)
                       or colors[RIGHT] != darken(base_rgb, RIGHT_DARKEN))
    return result


def style(key, declared=True, name=None):
    """Rampa NUEVA de una fila de STYLE_TABLE ('wood_orange', 'leaves'…). declared=True usa el lado
    y la sombra de la tabla (lo de las constantes WOOD_ORANGE…); declared=False deja las caras de
    la guía (−25 % / −40 % de la base) y toma de la tabla el resto (contorno, sombra profunda, brillo).
    Una segunda base de la tabla (piso de tablones) queda como tono propio con nombre 'base2'."""
    outline, shadows, side, bases, light = STYLE_TABLE[key]
    ordered = sorted(shadows, key=luminance, reverse=True)
    right = ordered[0]
    deep = ordered[1] if len(ordered) > 1 else None
    if declared:
        result = style_ramp(bases[0], side=side, shadow=right, outline=outline, deep=deep, light=light,
                            name=name or key)
    else:
        result = style_ramp(bases[0], outline=outline, deep=deep, light=light, name=name or key)
    for extra in bases[1:]:
        result.add(extra, name="base2")
    return result


# Constantes con nombre (una rampa por material; crearlas una vez y reutilizarlas).
WOOD_ORANGE = style("wood_orange")  # escritorios, mesas, estantes
WOOD_FLOOR = style("wood_floor")  # piso de tablones, madera oscura
UPHOLSTERY_RED = style("upholstery_red")  # sillas, sofás, alfombra
PLASTIC_BLACK = style("plastic_black")  # silla de oficina, monitor, aparatos
METAL_LIGHT = style("metal_light")  # metal claro, electrodomésticos
WALL_COOL = style("wall_cool")  # cara interior de la pared (pastel frío)
WALL_BEIGE = style("wall_beige")  # pared beige (alternativa)
WALL_CAP = style("wall_cap")  # tapa de la pared, canto de la losa y zócalo (ciruela oscuro)
DOOR = style("door")
CERAMIC_WHITE = style("ceramic_white")  # inodoro, lavamanos, piso blanco (OUTLINE = la junta)
CERAMIC_BLUE = style("ceramic_blue")  # cuadros azules
LEAVES = style("leaves")
CLAY = style("clay")  # maceta, barro
SCREEN = style("screen")  # pantalla encendida
STYLE_RAMPS = {
    "wood_orange": WOOD_ORANGE, "wood_floor": WOOD_FLOOR, "upholstery_red": UPHOLSTERY_RED,
    "plastic_black": PLASTIC_BLACK, "metal_light": METAL_LIGHT, "wall_cool": WALL_COOL, "wall_beige": WALL_BEIGE,
    "wall_cap": WALL_CAP, "door": DOOR, "ceramic_white": CERAMIC_WHITE, "ceramic_blue": CERAMIC_BLUE,
    "leaves": LEAVES, "clay": CLAY, "screen": SCREEN,
}


def light_order_ok(ramp_or_faces):
    """True si la luz sigue arriba a la izquierda: brillo de arriba > izquierda ≥ derecha."""
    faces = ramp_or_faces.faces() if isinstance(ramp_or_faces, Ramp) else ramp_or_faces
    top, left, right = (luminance(faces[k]) for k in ("top", "left", "right"))
    return top > left >= right
