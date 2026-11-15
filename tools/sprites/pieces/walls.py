# Paredes, puertas, ventanas y esquinas (docs/sprites_128.md, sección 8) en el estilo de
# tools/sprites/STYLE.md: cara de pared lisa (5 colores, WALL_COLORS), tapa y canto ciruela oscuro
# (WALL_CAP) con contorno, puertas con marco, tableros y manija, puerta doble de vidrio de la
# Recepción y ventana administrativa de aluminio con persiana veneciana.
#
#   wall_tall_x  wall_tall_y  wall_low_x  wall_low_y                 72×160 / 72×64
#   door[_wood|_office]_tall_x … _low_y                              72×160 / 72×64
#   glass_door_tall_x … _low_y                                       72×160 / 72×64
#   window_tall_x … _low_y                                           72×160 / 72×64
#   glass_door_double_a/_b_tall_x … _low_y   doble de vidrio sin marco en dos bordes (a, b)  72×160 / 72×64
#   door[_wood|_office]_tall_<eje>_open_1…6   la hoja abierta de 15° en 15° hasta 90° hacia adentro
#   glass_door_tall_<eje>_open_1…6            las dos hojas abren de 15° en 15° hasta 90° hacia afuera
#   window_tall_<eje>_blind_1…3               la persiana baja hasta cerrar
#   glass_door_double_a/_b_tall_<eje>_open_1…6   cada hoja abre de 15° en 15° hasta 90° hacia afuera
#   wall_tall_corner[_left|_right|_front]                     16×128, poste de esquina 8×8 px de planta
#   wall_low_corner[_back|_left|_right]                       16×28
#   wall_tall_x_shadow  wall_tall_y_shadow                    128×128, franja sobre la casilla de adentro
#
# Cada pieza y cada cuadro sale en los 5 colores: sin color en el nombre la fría, y el color antes
# de _tall/_low en las demás (door_wood_beige_tall_x_open_2).
#
# Cuadros de animación (kind wall_frame, solo de las piezas altas; el cuadro 0 es la pieza misma):
# la hoja abierta sale de los 72 px del tramo, así que cada animación va en su propio lienzo, igual
# para sus 3 cuadros. El manifiesto anota anchor (el mismo punto del piso que la pieza), base (la
# pieza cerrada) y base_offset (dónde cae el lienzo de la pieza dentro del cuadro): la pared
# alrededor queda pixel por pixel como en la pieza. Las bajas no tienen hoja: no se animan.
#
# La baja es el zócalo de la alta: la misma cara fría, la misma tapa (alto 20 en vez de 120).
#
# Puerta alta: el marco llega a 92 px (46 del mundo, la tabla de la guía) y encima sigue la pared
# hasta 120, dentro del mismo sprite, para que no quede hueco junto a las paredes altas. Por eso
# el manifiesto anota height 60 (el alto del sprite) y door_height 46 (el del marco).
# Puerta baja: sin hoja; dos jambas bajas y el umbral, para que se lea como un paso.
#
# Apoyo de los tramos: el punto medio del borde de la casilla, en el piso: (36, alto − 18). El
# borde va de (4, alto − 34) a (68, alto − 2) en los _y y de (68, alto − 34) a (4, alto − 2) en los
# _x. El manifiesto lo anota (anchor, anchor_at, edge, thickness y sort_bias).
#
# Esquinas (wall_*_corner*): un poste de 8×8 px de planta centrado en el vértice, que el juego
# dibuja DESPUÉS de los tramos que llegan a ese vértice (Y del vértice + POST_SORT_BIAS). Tapa la
# muesca de la junta en L. Cada orientación de la L ve otras caras del poste, así que hay una por
# orientación (se nombra por dónde queda la esquina en pantalla, con el local visto desde abajo):
#   wall_tall_corner        fondo (arriba): dos altas que salen hacia +x y +y
#   wall_tall_corner_left   izquierda: alta que llega desde −y y baja que sale hacia +x
#   wall_tall_corner_right  derecha: alta que llega desde −x y baja que sale hacia +y
#   wall_tall_corner_front  frente (abajo): dos altas que llegan desde −x y −y (local con entrantes)
#   wall_low_corner         frente: dos bajas que llegan desde −x y −y
#   wall_low_corner_back / _left / _right   las otras L de paredes bajas (tabiques interiores)
# Apoyo: el vértice en el piso, (8, alto − 4). Se dibujan con sus vecinos completos (con su z) y
# se guarda solo lo que cae dentro de la silueta del poste: así el contorno y los brillos quedan
# donde quedarían con la esquina armada.
#
# Hojas de revisión (en DIR): sheet_walls_room.png (local de 4×3 con puertas, ventanas y
# esquinas), sheet_walls_corners.png (esquinas ampliadas), sheet_walls_interior.png (tabiques
# bajos), sheet_walls_variants.png (las variantes de puerta y la de vidrio), sheet_walls_animations.png
# (cada animación de la pieza al último cuadro), sheet_walls_colors.png y _sheets/walls.png.
import math
import os
import re

import numpy as np

import iso
import palette as pal
import sheet

DATA = iso.load_json("data/construction.json")
WALL_DATA = DATA["wall"]
DOOR_DATA = DATA["door"]
WINDOW_DATA = DATA.get("window", {"height": 60})
GLASS_DOOR_DATA = DATA["glass_door"]
LOW_HEIGHT = DATA["low_wall_height"]  # px del mundo

HALF = iso.WALL_THICKNESS / 2.0  # medio grosor, en casillas (4 px)
LOW = iso.WALL_LOW_HEIGHT  # 20 px de sprite
WALL_TOP = iso.world_px(WALL_DATA["height"])  # 120
DOOR_TOP = iso.world_px(DOOR_DATA["height"])  # 92
CAP_H = 2  # alto de la tapa ciruela (su cara de arriba es el grosor de la pared)
# Sin contorno donde la pared da contra el piso: como en la referencia, la cara llega limpia al
# piso (el contorno grueso de los muebles ahí se ve como una raya negra a lo largo de la pared).
FLOOR_LINE = 0

# Orden de dibujo: por la Y del apoyo, como en el juego. Dos tramos que se tocan en una esquina
# pueden tener la MISMA Y: ahí va primero el _y y después el _x (sort_bias en el manifiesto).
SORT_BIAS_X = 0.5
# El poste va después de todos los tramos que llegan a su vértice (Y del vértice + 17).
POST_SORT_BIAS = 17.0

# ---------------------------------------------------------------------------- rampas

# Cara de la pared: WALL_COOL de STYLE.md (arriba 96acad, lados 899da0) con el contorno ciruela
# de la tapa, así toda la pared lleva el mismo borde oscuro de la «maqueta».
# Colores de la cara (todos con la tapa y el contorno ciruela). La fría es la de siempre y sus
# piezas no llevan color en el nombre; las demás van como wall_<color>_tall_x, door_<color>_…,
# window_<color>_… y wall_<color>_tall_corner_…. Cada una: (arriba, cara, brillo).
WALL_COLORS = (
    ("cool", "96acad", "899da0", "a3b6b7"),
    ("beige", "c2b7a3", "b3a792", "cfc5b3"),
    ("white", "d6d3cb", "c8c4bb", "e2e0d9"),
    ("sage", "9fb397", "91a689", "afc1a7"),
    ("peach", "d3ad97", "c69f88", "ddbca8"),
)
DEFAULT_COLOR = "cool"


def wall_ramp(color):
    for name, top, face, light in WALL_COLORS:
        if name == color:
            return pal.style_ramp(top, side=face, shadow=face, outline="21161a", deep="3e2e33",
                                  light=light, name="wall_" + name)
    raise KeyError(color)


def colored(name, color):
    """Nombre de una pieza en un color: el color va antes de _tall/_low (wall_tall_x ->
    wall_beige_tall_x, door_wood_tall_y_open_2 -> door_wood_beige_tall_y_open_2; la fría no cambia)."""
    if color == DEFAULT_COLOR:
        return name
    return re.sub(r"_(tall|low)(?=_|$)", r"_%s_\1" % color, name, count=1)


WALL = wall_ramp(DEFAULT_COLOR)


def use_color(color):
    """Cambia la rampa de la cara con la que se dibujan las piezas que siguen."""
    global WALL
    WALL = wall_ramp(color)
CAP = pal.WALL_CAP  # tapa y canto: 584549 arriba, 493539 / 3e2e33 a los lados, contorno 21161a

# Puerta (fila «Puerta» de STYLE.md): la hoja se ve en una cara lateral, así que su beige afa08d
# es la cara derecha (como en la referencia) y la izquierda un paso más clara.
LEAF = pal.style_ramp("c9baa2", side="b8a991", shadow="afa08d", outline="2a211b", deep="5e3e29",
                      light="efdfbd", name="door_leaf")
LEAF_GROOVE = LEAF.add("8d6e4f")  # ranura de los tableros (el «lado» de la fila Puerta)
LEAF_LIT = LEAF.add("e3d4b4")  # filo con luz de los tableros
# Marco claro (crema, el brillo de la fila Puerta).
FRAME = pal.style_ramp("fbf1da", side="f1e3c3", shadow="e8d6b0", outline="2a211b", deep="8d6e4f",
                       light="fffbf0", name="door_frame")
METAL = pal.METAL_LIGHT  # manija: metal claro con contorno oscuro
# Vidrio celeste (9fc7dc, el de la guía, en la cara derecha) y persiana marrón.
GLASS = pal.style_ramp("c6e6f4", side="aed6ea", shadow="9fc7dc", outline="2b3d4c", deep="5d8aa6",
                       light="e4f5fb", shine="ffffff", name="glass")
BLIND = pal.style_ramp("a57a50", side="8f663f", shadow="7f5935", outline="3a1f0e", deep="5a3a20",
                       light="c49a6a", name="blind")
BLIND_GAP = BLIND.add("5a3a20")  # rendija entre tablillas

# Aluminio oscuro (frame_color 4f5862 de la puerta de vidrio en la cara derecha): marco de la
# puerta de vidrio, de la puerta de oficina y de la ventana administrativa.
ALU = pal.style_ramp("68727c", side="5a646d", shadow="4f5862", outline="1d2227", deep="3a4149",
                     light="8a949d", shine="c3cbd2", name="aluminum")
# Vidrio de la puerta de la Recepción (a9d4e6 de data/construction.json en la cara derecha).
GLASS_DOOR = pal.style_ramp("c3e4f2", side="b4dcec", shadow="a9d4e6", outline="2b3d4c", deep="5d8aa6",
                            light="dff1f8", shine="ffffff", name="glass_door")
# Persiana veneciana de oficina: tablillas blancas con rendija gris.
VENETIAN = pal.style_ramp("eceeee", side="dfe2e3", shadow="d3d7d9", outline="5d6468", deep="a4abaf",
                          light="f7f8f8", name="venetian")
VENETIAN_GAP = VENETIAN.add("a4abaf")
# Puerta de madera (madera naranja de STYLE.md, un poco más oscura) con marco de madera.
WOOD_LEAF = pal.style_ramp("c0814f", side="ad6d40", shadow="9d6035", outline="3c1300", deep="783a13",
                           light="d39463", name="door_wood_leaf")
WOOD_GROOVE = WOOD_LEAF.add("783a13")
WOOD_LIT = WOOD_LEAF.add("d39463")
WOOD_FRAME = pal.style_ramp("a86a3c", side="94592f", shadow="834e28", outline="3c1300", deep="5b2a10",
                            light="c07d4c", name="door_wood_frame")
# Puerta de oficina: hoja lisa gris clara con mirilla de vidrio y marco de aluminio.
OFFICE_LEAF = pal.style_ramp("dadedf", side="c9cecf", shadow="bcc2c4", outline="2e3236", deep="6b7378",
                             light="eef0f0", name="door_office_leaf")
OFFICE_EDGE = OFFICE_LEAF.add("8f989d")  # borde de la mirilla
OFFICE_GLASS = OFFICE_LEAF.add("9fc7dc")
OFFICE_SHINE = OFFICE_LEAF.add("e4f5fb")


# ---------------------------------------------------------------------------- marco de dibujo

class _Along(object):
    """Contexto de textura con x = posición a lo largo del tramo (casillas, 0–1), sea cual sea
    la orientación con la que se dibujó. Lo demás se lee del contexto del motor."""

    def __init__(self, ctx, x):
        self._ctx = ctx
        self.x = x

    def __getattr__(self, name):
        return getattr(self._ctx, name)


# Caras del tramo (modelo de pared: x a lo largo, y a lo ancho) -> caras del mundo cuando el
# tramo corre a lo largo de +y (un _x dibujado en un lienzo sin giro).
_FACES_ALONG_Y = {iso.BACK: iso.X1, iso.FRONT: iso.X0, iso.X1: iso.BACK, iso.X0: iso.FRONT}


class Frame(object):
    """Dónde se dibuja el modelo de un tramo. En su propio lienzo (Canvas.wall) es la identidad:
    el lienzo ya gira el _x. Para los postes, el mismo modelo se dibuja en un lienzo sin giro
    junto a sus vecinos: along 'x' = el tramo corre a lo largo de +x desde (ox, oy) (un _y),
    along 'y' = a lo largo de +y (un _x); las caras y la textura se cambian solas. part: todas
    sus piezas se funden con esa (sin contorno entre ellas)."""

    def __init__(self, c, along="x", ox=0.0, oy=0.0, part=None):
        self.c = c
        self.along = along
        self.ox = ox
        self.oy = oy
        self.part = part

    def _face(self, face):
        return _FACES_ALONG_Y.get(face, face) if self.along == "y" else face

    def _wrap(self, fn):
        if fn is None:
            return None
        if self.along == "x":
            ox = self.ox
            return lambda ctx: fn(_Along(ctx, ctx.x - ox))
        oy = self.oy
        return lambda ctx: fn(_Along(ctx, ctx.y - oy))

    def _tex(self, tex):
        if tex is None or not isinstance(tex, dict):
            return self._wrap(tex)
        return dict((self._face(k), self._wrap(v)) for k, v in tex.items())

    def box(self, x0, x1, y0, y1, z0, z1, ramp, tex=None, faces=None, part=None, name=None, **kw):
        if faces is not None:
            faces = [self._face(f) for f in faces]
        if self.part is not None:
            name = None
            part = self.part
        elif isinstance(part, str) and part not in self.c._names:
            # La primera pieza de un grupo le da el nombre; las siguientes se funden con ella.
            name, part = part, None
        if self.along == "x":
            box = (self.ox + x0, self.ox + x1, self.oy + y0, self.oy + y1)
        else:
            box = (self.ox + y0, self.ox + y1, self.oy + x0, self.oy + x1)
        return self.c.box(box[0], box[1], box[2], box[3], z0, z1, ramp, tex=self._tex(tex), faces=faces,
                          part=part, name=name, **kw)


def _shift(mask, dy, dx):
    """out[y, x] = mask[y + dy, x + dx] (False fuera del arreglo)."""
    out = np.zeros_like(mask)
    h, w = mask.shape
    ys0, ys1 = max(-dy, 0), h - max(dy, 0)
    xs0, xs1 = max(-dx, 0), w - max(dx, 0)
    out[ys0:ys1, xs0:xs1] = mask[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx]
    return out


# ---------------------------------------------------------------------------- pared

def wall_block(f, x0, x1, z0, z1, top=True):
    """Bloque de pared del grosor entero: cara fría lisa; si llega arriba, tapa ciruela."""
    if top:
        f.box(x0, x1, -HALF, HALF, z0, z1 - CAP_H, WALL, name="wall", part="wall")
        f.box(x0, x1, -HALF, HALF, z1 - CAP_H, z1, CAP, name="cap", part="wall")
    else:
        f.box(x0, x1, -HALF, HALF, z0, z1, WALL, name="wall", part="wall")


def wall_model(f, height, x0=0.0, x1=1.0):
    """Tramo de pared: x de 0 a 1 a lo largo, ±4 px de grosor, cara lisa y tapa ciruela."""
    wall_block(f, x0, x1, 0, height)


def paint_canto(c):
    """El canto del tramo (x = 1 del modelo, el extremo de adelante) va en ciruela, como el
    corte de la «maqueta». En una pared seguida lo tapa el tramo siguiente; en una esquina, el
    poste."""
    cap = c.select(part="wall", face=iso.X1)
    if not cap.any():
        return
    side = c.face_side(iso.X1)
    c.paint(cap, pal.LEFT if side == "left" else pal.RIGHT, CAP)


def wall_piece(axis, tall):
    c = iso.Canvas.wall(axis, tall)
    height = WALL_TOP if tall else LOW
    wall_model(Frame(c), height)
    paint_canto(c)
    return c


# ---------------------------------------------------------------------------- sombra de la pared

SHADOW_DEPTH = {"x": 3 / 16.0, "y": 5 / 32.0}  # casillas desde el borde: 8 y 6 px fuera de la pared
SHADOW_COLOR = (26, 28, 38)  # el mismo tono de las sombras de los muebles (Canvas.ground_shadow)


def wall_shadow(axis):
    """Sombra de contacto de una pared alta sobre la casilla de adentro: una franja pegada al
    borde (el de arriba a la izquierda del rombo para un _x, el de arriba a la derecha para un _y)."""
    grid = iso.tile_grid()
    across = grid.u if axis == "x" else grid.v
    mask = grid.mask & (across < SHADOW_DEPTH[axis])
    rgba = np.zeros(mask.shape + (4,), dtype=np.uint8)
    rgba[mask] = SHADOW_COLOR + (255,)
    return sheet.Image.fromarray(rgba, "RGBA")


# ---------------------------------------------------------------------------- puerta

# Medidas a lo largo del tramo (en 1/32 de casilla = 2 px): pared 0–2, jamba 2–5, hoja 5–27,
# jamba 27–30, pared 30–32. La hoja queda 2 px hundida (su cara en y = 1/32).
DOOR_WALL = 2 / 32.0
JAMB0, JAMB1 = 2 / 32.0, 5 / 32.0
LEAF0, LEAF1 = 5 / 32.0, 27 / 32.0
RECESS = 1 / 32.0  # medio grosor de lo que va hundido (hoja, vidrio)
SILL = 2  # umbral
LINTEL = 4  # alto del cabezal del marco
OPENING = DOOR_TOP - LINTEL  # 88: arriba de la hoja
HANDLE_Z = 44
# Ángulos de la hoja en los cuadros de abrir (_open_1 a _open_6); el 0 es la pieza cerrada.
SWING_ANGLES = (15, 30, 45, 60, 75, 90)
# La hoja girada toma solo los tonos de cara según la luz (sin caer en el contorno ni en la sombra
# profunda): de frente a la luz arriba, de lado la izquierda y de espaldas la derecha.
LEAF_BANDS = ((0.66, pal.BASE), (0.10, pal.LEFT), (-9.0, pal.RIGHT))


def panels_index(a, b, base, panels, groove, lit):
    """Tableros hundidos en una hoja: a = px a lo largo desde la bisagra, b = px desde el umbral.
    Ranura oscura arriba y a la izquierda, filo claro abajo y a la derecha."""
    index = np.asarray(base).copy() if np.ndim(base) else np.full(np.shape(a), base)
    for a0, a1, b0, b1 in panels:
        inside = (a >= a0) & (a < a1) & (b >= b0) & (b < b1)
        dark = inside & ((b == b1 - 1) | (a == a0))
        light = inside & ((b == b0) | (a == a1 - 1)) & ~dark
        index = np.where(dark, groove, index)
        index = np.where(light, lit, index)
    return index


def vision_index(a, b, base, slot):
    """Mirilla de la puerta de oficina: vidrio con borde gris y un reflejo en diagonal."""
    index = np.asarray(base).copy() if np.ndim(base) else np.full(np.shape(a), base)
    a0, a1, b0, b1 = slot
    inside = (a >= a0) & (a < a1) & (b >= b0) & (b < b1)
    edge = inside & ((a == a0) | (a == a1 - 1) | (b == b0) | (b == b1 - 1))
    shine = inside & ~edge & (np.mod(a - a0 + (b - b0) // 2, 9) == 3)
    index = np.where(inside, OFFICE_GLASS, index)
    index = np.where(shine, OFFICE_SHINE, index)
    return np.where(edge, OFFICE_EDGE, index)


# Tipos de puerta que giran. layout: (pared, fin de la jamba, hoja desde, hoja hasta) a lo largo,
# en 1/32 de casilla; la del otro lado es simétrica. Con marco oscuro va 8 px de pared a cada lado
# (como la ventana): si no, el marco queda pegado a la unión con el tramo vecino y se ve el corte.
# panels: tableros (a0, a1, b0, b1) en px de la hoja (ancho de la hoja × 86).
NARROW = (2, 5, 5, 27)  # hoja de 44 px
WIDE = (4, 6, 6, 26)  # hoja de 40 px
DOOR_TYPES = {
    "door": {"leaf": LEAF, "frame": FRAME, "groove": LEAF_GROOVE, "lit": LEAF_LIT, "layout": NARROW,
             "panels": ((6, 38, 8, 36), (6, 38, 44, 78)), "slot": None},
    "door_wood": {"leaf": WOOD_LEAF, "frame": WOOD_FRAME, "groove": WOOD_GROOVE, "lit": WOOD_LIT, "layout": WIDE,
                  "panels": ((4, 18, 6, 26), (22, 36, 6, 26), (4, 18, 32, 52), (22, 36, 32, 52),
                             (4, 18, 58, 80), (22, 36, 58, 80)), "slot": None},
    "door_office": {"leaf": OFFICE_LEAF, "frame": ALU, "groove": None, "lit": None, "layout": WIDE, "panels": (),
                    "slot": (7, 14, 40, 78)},
}


def door_layout(spec):
    wall, jamb, leaf0, leaf1 = (v / 32.0 for v in spec["layout"])
    return wall, jamb, leaf0, leaf1


def leaf_index(spec, a, b, base):
    if spec["panels"]:
        return panels_index(a, b, base, spec["panels"], spec["groove"], spec["lit"])
    if spec["slot"]:
        return vision_index(a, b, base, spec["slot"])
    return base


def leaf_panel_for(spec):
    """Textura de la hoja (panel): ctx.a = px desde la bisagra, ctx.b = px desde el umbral."""
    def tex(ctx):
        return leaf_index(spec, np.floor(ctx.a), np.floor(ctx.b), ctx.base)
    return tex


def rbox(c, o, u, v, w, ramp, tex=None, bands=None, side_index=None, top_index=None, name=None, part=None):
    """Caja con cualquier giro, hecha de seis paneles: o = esquina (x, y, z), u, v, w = sus tres
    lados (dx, dy, dz). Las dos caras grandes (u × w) llevan la textura; los cantos (v × w) toman
    side_index y arriba y abajo (u × v) top_index (o la luz si no se dan). Devuelve la pieza."""
    def add(a, b):
        return (a[0] + b[0], a[1] + b[1], a[2] + b[2])

    faces = ((o, u, w, tex, None), (add(o, v), u, w, tex, None), (o, v, w, None, side_index),
             (add(o, u), v, w, None, side_index), (o, u, v, None, top_index), (add(o, w), u, v, None, top_index))
    for origin, ea, eb, face_tex, index in faces:
        pid = c.panel(origin, ea, eb, ramp, tex=face_tex, index=index, bands=bands,
                      name=None if part is not None else name, part=part)
        part = pid if part is None else part
    return part


def hinged_leaf(c, hinge_x, sign, width, angle, outward, z0, z1, ramp, tex, side_index, top_index, hardware=()):
    """Hoja con bisagra en x = hinge_x, de `width` casillas hacia +x (sign 1) o −x (sign −1), 2 px
    de grueso centrada en y = 0, girada `angle` grados hacia +y (adentro) o −y (outward). El mismo
    armado para la hoja cerrada (angle 0) y para los cuadros abiertos, así se ven iguales.
    hardware: herrajes [(a0, a1, k0, k1, b0, b1, ramp)]: a en px desde la bisagra a lo largo de la
    hoja, k en casillas desde el centro de la hoja hacia su cara de adentro (negativo, la de afuera),
    b en px desde z0; giran con la hoja."""
    out = -1.0 if outward else 1.0
    t = math.radians(angle)
    turn = sign * out * t
    d = (sign * width * math.cos(t), out * width * math.sin(t))
    n = (-math.sin(turn), math.cos(turn))  # la cara que da adentro cuando está cerrada
    hinge = (hinge_x + sign * out * RECESS * math.sin(t), 0.0)  # gira sin salirse de la jamba
    px = width * 64.0

    def point(a, k, b):
        return (hinge[0] + d[0] * a / px + n[0] * k, hinge[1] + d[1] * a / px + n[1] * k, z0 + b)

    rbox(c, point(0, -RECESS, 0), (d[0], d[1], 0.0), (n[0] * 2 * RECESS, n[1] * 2 * RECESS, 0.0),
         (0.0, 0.0, z1 - z0), ramp, tex=tex, bands=LEAF_BANDS, side_index=side_index, top_index=top_index,
         name="leaf")
    for a0, a1, k0, k1, b0, b1, part_ramp in hardware:
        f = (a1 - a0) / px
        rbox(c, point(a0, k0, b0), (d[0] * f, d[1] * f, 0.0), (n[0] * (k1 - k0), n[1] * (k1 - k0), 0.0),
             (0.0, 0.0, b1 - b0), part_ramp, name="hardware")


def door_handle(px):
    """Manija de las puertas que giran: placa de 4 px y palanca de 12 px hacia la bisagra, del lado
    de adentro, a 6 px del canto libre."""
    return ((px - 10, px - 6, RECESS, RECESS + 1 / 64.0, HANDLE_Z - 6 - SILL, HANDLE_Z + 6 - SILL, METAL),
            (px - 18, px - 6, RECESS + 1 / 64.0, RECESS + 2 / 64.0, HANDLE_Z - SILL, HANDLE_Z + 3 - SILL, METAL))


def swung_leaf(c, spec, angle):
    """Hoja de una puerta que gira hacia adentro (angle 0 = cerrada)."""
    _wall, _jamb, leaf0, leaf1 = door_layout(spec)
    width = leaf1 - leaf0
    hinged_leaf(c, leaf0, 1.0, width, angle, False, SILL, OPENING, spec["leaf"], leaf_panel_for(spec),
                pal.LEFT, pal.BASE, door_handle(width * 64.0))


def door_model(f, tall, kind="door", angle=0):
    """Puerta alta: pared a los lados y encima del marco hasta 120, marco (jambas y cabezal de 4),
    hoja de 2 px con sus tableros (o mirilla), umbral y manija. angle: la hoja abierta hacia
    adentro (0 = cerrada). Puerta baja: la alta cortada a 20 px sin la hoja."""
    spec = DOOR_TYPES[kind]
    frame = spec["frame"]
    wall, jamb, leaf0, leaf1 = door_layout(spec)
    height = WALL_TOP if tall else LOW
    if tall:
        wall_block(f, 0, wall, 0, DOOR_TOP, top=False)
        wall_block(f, 1 - wall, 1, 0, DOOR_TOP, top=False)
        wall_block(f, 0, 1, DOOR_TOP, height)
    else:
        wall_block(f, 0, wall, 0, height)
        wall_block(f, 1 - wall, 1, 0, height)
    jamb_top = OPENING if tall else height
    f.box(wall, jamb, -HALF, HALF, 0, jamb_top, frame, name="frame", part="frame")
    f.box(1 - jamb, 1 - wall, -HALF, HALF, 0, jamb_top, frame, name="frame", part="frame")
    if tall:
        f.box(wall, 1 - wall, -HALF, HALF, OPENING, DOOR_TOP, frame, name="frame", part="frame")
    f.box(leaf0, leaf1, -HALF, HALF, 0, SILL, spec["leaf"], name="sill")
    if tall:
        swung_leaf(f.c, spec, angle)


# ---------------------------------------------------------------------------- puerta doble de vidrio

# La de la Recepción (data/construction.json, glass_door): marco de aluminio hasta 100 px (50 del
# mundo), pared encima hasta 120, 8 px de pared a cada lado (como la ventana: el aluminio no toca
# la unión). Dos hojas de vidrio de 20 px con perfil de aluminio y tirador vertical, cada una con
# la bisagra en su jamba; se juntan en el medio. Al abrir (_open_1 a _open_6) las dos giran de 15°
# en 15° hasta 90° hacia afuera (−y, el lado de la calle).
GLASS_TOP = iso.world_px(GLASS_DOOR_DATA["height"])  # 100
GLASS_HEAD = GLASS_TOP - 4  # 96: arriba del vidrio
GLASS_WALL = 4 / 32.0
GLASS_IN0, GLASS_IN1 = 6 / 32.0, 26 / 32.0  # hueco entre las jambas
PANE = (GLASS_IN1 - GLASS_IN0) / 2.0  # 10/32: cada hoja
GLASS_ANGLES = (15, 30, 45, 60, 75, 90)
RAIL = 1 / 32.0  # perfil de aluminio (2 px)
PULL = (30, 62)  # tirador vertical: de z 30 a 62
# El perfil de aluminio de las hojas va en la textura del vidrio: tonos agregados a su rampa.
GLASS_ALU = GLASS_DOOR.add("5a646d")
GLASS_ALU_DARK = GLASS_DOOR.add("4f5862")


def glass_leaf_face(ctx):
    """Hoja de vidrio con perfil: a = px desde la bisagra (0–20), b = px desde el umbral. Perfil
    de 2 px a los lados y arriba, zócalo de 4 abajo y reflejos en diagonal."""
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    width = np.floor(PANE * 64.0)
    height = GLASS_HEAD - SILL
    index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(a.shape, ctx.base)
    d = np.mod(a + b * 0.5, 24.0)
    shine = ((d >= 8) & (d < 10) | (d >= 13) & (d < 14)) & (b > 6)
    index = np.where(shine, pal.SHINE, index)
    frame = (a < 2) | (a >= width - 2) | (b < 4) | (b >= height - 2)
    index = np.where(frame, GLASS_ALU, index)
    return np.where(frame & ((a == 0) | (a == width - 1) | (b == 0)), GLASS_ALU_DARK, index)


def glass_leaf(c, hinge_x, sign, angle):
    """Hoja de la puerta de vidrio con marco (angle 0 = cerrada; abre hacia afuera) con su tirador
    vertical de metal junto al canto libre, de los dos lados."""
    px = PANE * 64.0
    pull = tuple((px - 5, px - 4, k0, k1, PULL[0] - SILL, PULL[1] - SILL, METAL)
                 for k0, k1 in ((RECESS, RECESS + 1 / 64.0), (-RECESS - 1 / 64.0, -RECESS)))
    hinged_leaf(c, hinge_x, sign, PANE, angle, True, SILL, GLASS_HEAD, GLASS_DOOR, glass_leaf_face,
                GLASS_ALU, GLASS_ALU, pull)


def glass_door_model(f, tall, angle=0):
    height = WALL_TOP if tall else LOW
    if tall:
        wall_block(f, 0, GLASS_WALL, 0, GLASS_TOP, top=False)
        wall_block(f, 1 - GLASS_WALL, 1, 0, GLASS_TOP, top=False)
        wall_block(f, 0, 1, GLASS_TOP, height)
    else:
        wall_block(f, 0, GLASS_WALL, 0, height)
        wall_block(f, 1 - GLASS_WALL, 1, 0, height)
    top = GLASS_HEAD if tall else height
    f.box(GLASS_WALL, GLASS_IN0, -HALF, HALF, 0, top, ALU, name="frame", part="frame")
    f.box(GLASS_IN1, 1 - GLASS_WALL, -HALF, HALF, 0, top, ALU, name="frame", part="frame")
    if tall:
        f.box(GLASS_WALL, 1 - GLASS_WALL, -HALF, HALF, GLASS_HEAD, GLASS_TOP, ALU, name="frame", part="frame")
    f.box(GLASS_IN0, GLASS_IN1, -HALF, HALF, 0, SILL, ALU, name="sill")
    if tall:
        glass_leaf(f.c, GLASS_IN0, 1.0, angle)
        glass_leaf(f.c, GLASS_IN1, -1.0, angle)


# ---------------------------------------------------------------------------- puerta doble de vidrio sin marco

# Variante de la Recepción que ocupa DOS bordes seguidos: dos hojas de vidrio templado sin marco de
# 48 px (0.75 m) cada una, hueco de 96 px, 16 px de pared a cada lado y pared encima desde 100 px
# (50 del mundo, como la de vidrio). Herrajes de metal en las esquinas de la bisagra y un tirador
# largo junto al medio. Se dibuja como un modelo de x 0 a 2 y se guarda en dos mitades, cada una
# un tramo normal de 72×160: glass_door_double_a (x 0–1, va en el borde de menor x o y) y _b
# (x 1–2). Las bajas son solo los dos trozos de pared con el hueco entre ellos.
# Al abrir (_open_1 a _open_6) cada hoja gira de 15° en 15° hasta 90° hacia afuera (−y).
DOUBLE_WALL = 8 / 32.0  # 16 px de pared a cada lado
DOUBLE_GAP = 1 / 64.0  # medio hueco entre las dos hojas (1 px cada una)
DOUBLE_TOP = GLASS_TOP  # 100
DOUBLE_BOTTOM = 1  # la hoja queda 1 px sobre el piso
DOUBLE_PULL = (26, 74)
DOUBLE_ANGLES = (15, 30, 45, 60, 75, 90)
DOUBLE_EDGE = GLASS_DOOR.add("8fb8cc")  # canto del vidrio templado


def double_leaf_face(ctx):
    """Vidrio sin marco: a = px desde la bisagra (0–47), b = px desde abajo. Canto del vidrio y
    reflejos en diagonal largos."""
    a = np.floor(ctx.a)
    b = np.floor(ctx.b)
    width = np.floor((1.0 - DOUBLE_WALL - DOUBLE_GAP) * 64.0)
    height = DOUBLE_TOP - DOUBLE_BOTTOM
    index = np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(a.shape, ctx.base)
    d = np.mod(a + b * 0.5, 30.0)
    shine = ((d >= 10) & (d < 12) | (d >= 16) & (d < 17)) & (b > 8) & (b < height - 8)
    index = np.where(shine, pal.SHINE, index)
    edge = (a < 1) | (a >= width - 1) | (b < 1) | (b >= height - 1)
    return np.where(edge, DOUBLE_EDGE, index)


def double_leaf(c, hinge_x, sign, angle):
    """Hoja sin marco (angle 0 = cerrada; abre hacia afuera): herrajes de 6 px que abrazan el vidrio
    arriba y abajo junto a la bisagra y tirador largo junto al canto libre, de los dos lados."""
    width = 1.0 - DOUBLE_WALL - DOUBLE_GAP
    px = width * 64.0
    height = DOUBLE_TOP - DOUBLE_BOTTOM
    hold = (-RECESS - 1 / 64.0, RECESS + 1 / 64.0)
    hardware = [(0, 6, hold[0], hold[1], 0, 6, METAL), (0, 6, hold[0], hold[1], height - 6, height, METAL)]
    for k0, k1 in ((RECESS, RECESS + 1 / 64.0), (-RECESS - 1 / 64.0, -RECESS)):
        hardware.append((px - 6, px - 5, k0, k1, DOUBLE_PULL[0], DOUBLE_PULL[1], METAL))
    hinged_leaf(c, hinge_x, sign, width, angle, True, DOUBLE_BOTTOM, DOUBLE_TOP, GLASS_DOOR, double_leaf_face,
                DOUBLE_EDGE, DOUBLE_EDGE, hardware)


def double_glass_model(f, tall, half=None, angle=0):
    """Modelo de x 0 a 2. half 'a' o 'b' dibuja solo esa mitad (con su hoja); None, las dos."""
    height = WALL_TOP if tall else LOW
    halves = ("a", "b") if half is None else (half,)
    for h in halves:
        stub = (0.0, DOUBLE_WALL) if h == "a" else (2.0 - DOUBLE_WALL, 2.0)
        wall_block(f, stub[0], stub[1], 0, height)
        if not tall:
            continue
        inner = (DOUBLE_WALL, 1.0) if h == "a" else (1.0, 2.0 - DOUBLE_WALL)
        wall_block(f, inner[0], inner[1], DOUBLE_TOP, height)
        if h == "a":
            double_leaf(f.c, DOUBLE_WALL, 1.0, angle)
        else:
            double_leaf(f.c, 2.0 - DOUBLE_WALL, -1.0, angle)


# ---------------------------------------------------------------------------- ventana

# Ventana administrativa: marco de aluminio oscuro, dos hojas con parante en el medio y un
# travesaño que deja una banda fija arriba, vidrio hundido y persiana veneciana blanca. Alta:
# pared abajo (0–28) y arriba (108–120), pared de 8 px a los lados, alféizar 28–32, cabezal
# 104–108. La baja es una franja de ventana en la pared de 20 (sin persiana).
WIN_WALL = 4 / 32.0
WIN_JAMB = 6 / 32.0
WIN_MULLION = (15 / 32.0, 17 / 32.0)
WIN_KINDS = {
    True: {"sill": (28, 32), "head": (104, 108), "transom": (84, 86)},
    False: {"sill": (4, 6), "head": (16, 18), "transom": None},
}
# Persiana: abajo de la tela en la pieza cerrada (_blind_0 = la pieza) y en _blind_1 a _blind_6.
BLIND_LEVELS = (70, 64, 58, 51, 45, 38, 32)


def glass_face(ctx):
    """Vidrio: en cada hoja dos reflejos cortos en diagonal (uno de 2 px y otro de 1 px)."""
    a = np.floor(ctx.x * 64.0)
    z = np.floor(ctx.z)
    pane = np.mod(a - WIN_JAMB * 64.0, 22.0)
    d = pane + np.mod(z, 64.0) * 0.5
    low = np.mod(z, 64.0)
    shine = ((d >= 9) & (d < 11) | (d >= 14) & (d < 15)) & (pane >= 2) & (pane < 18)
    return np.where(shine & (low > 0), pal.SHINE, ctx.base)


def venetian_face(ctx):
    """Persiana veneciana: tablillas de 3 px con rendija gris y un filo claro."""
    row = np.mod(np.floor(ctx.z), 3.0)
    base = np.asarray(ctx.base)
    index = np.where(row == 0, VENETIAN_GAP, base)
    return np.where(row == 2, pal.lighter(base), index)


def window_model(f, tall, blind=None):
    height = WALL_TOP if tall else LOW
    spec = WIN_KINDS[tall]
    sill0, sill1 = spec["sill"]
    head0, head1 = spec["head"]
    wall_block(f, 0, WIN_WALL, 0, height)
    wall_block(f, 1 - WIN_WALL, 1, 0, height)
    wall_block(f, WIN_WALL, 1 - WIN_WALL, 0, sill0, top=False)
    wall_block(f, WIN_WALL, 1 - WIN_WALL, head1, height)
    f.box(WIN_WALL, 1 - WIN_WALL, -HALF, HALF + 1 / 64.0, sill0, sill1, ALU, name="frame", part="frame")
    f.box(WIN_WALL, 1 - WIN_WALL, -HALF, HALF, head0, head1, ALU, name="frame", part="frame")
    f.box(WIN_WALL, WIN_JAMB, -HALF, HALF, sill1, head0, ALU, name="frame", part="frame")
    f.box(1 - WIN_JAMB, 1 - WIN_WALL, -HALF, HALF, sill1, head0, ALU, name="frame", part="frame")
    f.box(WIN_MULLION[0], WIN_MULLION[1], -HALF / 2, HALF / 2, sill1, head0, ALU, name="frame", part="frame")
    if spec["transom"]:
        t0, t1 = spec["transom"]
        f.box(WIN_JAMB, 1 - WIN_JAMB, -HALF / 2, HALF / 2, t0, t1, ALU, name="frame", part="frame")
    f.box(WIN_JAMB, 1 - WIN_JAMB, -RECESS, RECESS, sill1, head0, GLASS, tex={iso.BACK: glass_face},
          name="glass", flat=False)
    if tall:
        level = BLIND_LEVELS[blind or 0]
        # Caja de la persiana arriba y tela de tablillas hasta `level`, con la barra de abajo.
        f.box(WIN_JAMB, 1 - WIN_JAMB, RECESS, RECESS + 1 / 64.0, level + 2, head0, VENETIAN,
              tex={iso.BACK: venetian_face}, name="blind", flat=False)
        f.box(WIN_JAMB, 1 - WIN_JAMB, RECESS, RECESS + 2 / 64.0, level, level + 2, ALU, name="blind_bar",
              flat=False)


# ---------------------------------------------------------------------------- esquinas

# Vecinos de un vértice en el orden (−x, −y, +x, +y): n nada, t pared alta, l pared baja.
POST_HEIGHTS = {"t": WALL_TOP, "l": LOW, "n": 0}
CORNERS = {
    "wall_tall_corner": ("n", "n", "t", "t"),
    "wall_tall_corner_left": ("n", "t", "l", "n"),
    "wall_tall_corner_right": ("t", "n", "n", "l"),
    "wall_tall_corner_front": ("t", "t", "n", "n"),
    "wall_low_corner": ("l", "l", "n", "n"),
    "wall_low_corner_back": ("n", "n", "l", "l"),
    "wall_low_corner_left": ("n", "l", "l", "n"),
    "wall_low_corner_right": ("l", "n", "n", "l"),
}
POST_W = 16  # el poste mide 16 px de ancho en pantalla (8×8 de planta)


def post_piece(neighbors):
    """Poste de 8×8 px de planta en un vértice, del alto del vecino más alto. Se dibuja en un
    lienzo grande con los cuatro tramos vecinos completos (con su z y fundidos con el poste) y se
    guarda solo lo que cae dentro de la silueta del poste, recortado a 16 px de ancho con el
    vértice en (8, alto − 4)."""
    height = max(POST_HEIGHTS[code] for code in neighbors)
    big_w, big_h = 192, height + 112
    origin = (96.0, big_h - 56.0)
    c = iso.Canvas(big_w, big_h, origin, size=(1, 1), rotation=0, swap=False, kind="post", anchor=origin)
    # Donde una pared alta termina sobre una baja (esquinas izquierda y derecha) el poste es el
    # corte de la pared y va entero en ciruela, como el canto de la «maqueta» de la referencia.
    ramp = CAP if neighbors in (CORNERS["wall_tall_corner_left"], CORNERS["wall_tall_corner_right"]) else WALL
    post = c.box(-HALF, HALF, -HALF, HALF, 0, height - CAP_H, ramp, name="post")
    c.box(-HALF, HALF, -HALF, HALF, height - CAP_H, height, CAP, part=post)
    for code, along, ox, oy in ((neighbors[0], "x", -1.0, 0.0), (neighbors[1], "y", 0.0, -1.0),
                                (neighbors[2], "x", 0.0, 0.0), (neighbors[3], "y", 0.0, 0.0)):
        if code != "n":
            # Un tramo más bajo que el poste arranca en el borde del poste, no en el vértice: si no,
            # su cara (del mismo plano que la del poste) tapa medio poste y en las esquinas ciruela
            # queda una franja fría hasta el piso. Los del alto del poste siguen desde el vértice.
            start, end = 0.0, 1.0
            if POST_HEIGHTS[code] < height:
                start, end = (0.0, 1.0 - HALF) if ox < 0 or oy < 0 else (HALF, 1.0)
            wall_model(Frame(c, along, ox, oy, part=post), POST_HEIGHTS[code], start, end)
    image = np.array(c.finish(ground_outline=FLOOR_LINE))
    alone = iso.Canvas(big_w, big_h, origin, size=(1, 1), rotation=0, swap=False, kind="post", anchor=origin)
    alone.box(-HALF, HALF, -HALF, HALF, 0, height, WALL)
    inside = np.array(alone.image)[..., 3] == 255
    image[~inside] = 0
    x0 = int(origin[0]) - POST_W // 2
    y0 = int(origin[1]) - height - 4
    out_h = height + 8
    crop = image[y0:y0 + out_h, x0:x0 + POST_W]
    return sheet.Image.fromarray(np.ascontiguousarray(crop), "RGBA"), (POST_W / 2.0, out_h - 4.0)


# ---------------------------------------------------------------------------- hojas de prueba

def _load(out_dir, name):
    return sheet.load(os.path.join(out_dir, name + ".png"))


def _floor_tiles(out_dir):
    """Las cerámicas si ya están generadas; si no, una casilla lisa de prueba."""
    tiles = []
    for variant in range(4):
        path = os.path.join(out_dir, "floor_ceramic_%d.png" % variant)
        if os.path.isfile(path):
            tiles.append(sheet.load(path))
    return tiles if len(tiles) == 4 else [sheet.plain_tile()]


# Código de la escena -> pieza. t/l pared, d/b puerta, w/v ventana (alta/baja).
# k/m puerta de madera, o/p de oficina, g/h de vidrio y q/r la doble sin marco (mitades a y b;
# s/u sus bajas) (alta/baja).
CODE_PIECES = {"t": "wall_tall", "l": "wall_low", "d": "door_tall", "b": "door_low",
               "w": "window_tall", "v": "window_low", "k": "door_wood_tall", "m": "door_wood_low",
               "o": "door_office_tall", "p": "door_office_low", "g": "glass_door_tall", "h": "glass_door_low",
               "q": "glass_door_double_a_tall", "r": "glass_door_double_b_tall",
               "s": "glass_door_double_a_low", "u": "glass_door_double_b_low"}
CODE_FAMILY = {"t": "t", "d": "t", "w": "t", "k": "t", "o": "t", "g": "t", "q": "t", "r": "t",
               "l": "l", "b": "l", "v": "l", "m": "l", "p": "l", "h": "l", "s": "l", "u": "l"}


class WallLayout(object):
    """Bordes de una escena de prueba: (x, y, eje) -> código. Pone los tramos, las sombras de
    las altas y el poste de cada vértice en L."""

    def __init__(self):
        self.edges = {}

    def put(self, x, y, axis, code):
        self.edges[(x, y, axis)] = code

    def vertex_neighbors(self, vx, vy):
        # Un _y (x, y) va de (x, y + 1) a (x + 1, y + 1); un _x (x, y), de (x + 1, y) a (x + 1, y + 1).
        get = self.edges.get
        codes = (get((vx - 1, vy - 1, "y"), "n"), get((vx - 1, vy - 1, "x"), "n"),
                 get((vx, vy - 1, "y"), "n"), get((vx - 1, vy, "x"), "n"))
        return tuple(CODE_FAMILY.get(code, "n") for code in codes)

    def apply(self, scene, out_dir, posts=True, shadows=None, color=DEFAULT_COLOR):
        for (x, y, axis), code in sorted(self.edges.items()):
            image = _load(out_dir, colored("%s_%s" % (CODE_PIECES[code], axis), color))
            scene.add_wall(image, x, y, axis, bias=SORT_BIAS_X if axis == "x" else 0.0)
            if shadows is not None and CODE_FAMILY[code] == "t":
                if axis == "x":
                    scene.add_shadow(shadows["x"], x + 1, y, anchor=(64, 96), opacity=0.3)
                else:
                    scene.add_shadow(shadows["y"], x, y + 1, anchor=(64, 96), opacity=0.3)
        missing = []
        if not posts:
            return missing
        by_neighbors = dict((v, k) for k, v in CORNERS.items())
        vertices = set()
        for (x, y, axis) in self.edges:
            vertices.add((x + 1, y) if axis == "x" else (x, y + 1))
            vertices.add((x + 1, y + 1))
        for vx, vy in sorted(vertices):
            neighbors = self.vertex_neighbors(vx, vy)
            present = [n for n in neighbors if n != "n"]
            straight = (neighbors[0] == neighbors[2] != "n" and neighbors[1] == neighbors[3] == "n") or \
                       (neighbors[1] == neighbors[3] != "n" and neighbors[0] == neighbors[2] == "n")
            if len(present) < 2 or straight:
                continue
            name = by_neighbors.get(neighbors)
            if name is None:
                missing.append(neighbors)
                continue
            image = _load(out_dir, colored(name, color))
            px, py = scene.cell_point(vx, vy)
            ax, ay = image.size[0] / 2.0, image.size[1] - 4.0
            scene._items.append((py + POST_SORT_BIAS, len(scene._items), image,
                                 int(round(px - ax)), int(round(py - ay))))
        return missing


def room_layout(cols=4, rows=3, doors_on="y"):
    """Local de cols × rows: altas al fondo con una puerta y una ventana, bajas al frente con
    una puerta y una ventana (en las paredes _y o en las _x)."""
    layout = WallLayout()
    for i in range(cols):
        back = {1: "w", 2: "d"}.get(i, "t") if doors_on == "y" else "t"
        front = {1: "b", 3: "v"}.get(i, "l") if doors_on == "y" else "l"
        layout.put(i, -1, "y", back)
        layout.put(i, rows - 1, "y", front)
    for j in range(rows):
        back = {0: "w", 1: "d"}.get(j, "t") if doors_on == "x" else "t"
        front = {1: "b", 2: "v"}.get(j, "l") if doors_on == "x" else "l"
        layout.put(-1, j, "x", back)
        layout.put(cols - 1, j, "x", front)
    return layout


def variants_layout(cols=6, rows=3):
    """Local con las variantes en las paredes altas: ventana, puertas de madera, de vidrio, de
    oficina y la doble de vidrio sin marco (dos bordes) al fondo, y sus bajas al frente."""
    layout = WallLayout()
    back = {0: "w", 1: "k", 2: "g", 3: "o", 4: "q", 5: "r"}
    front = {1: "m", 2: "h", 3: "s", 4: "u"}
    for i in range(cols):
        layout.put(i, -1, "y", back.get(i, "t"))
        layout.put(i, rows - 1, "y", front.get(i, "l"))
    for j in range(rows):
        layout.put(-1, j, "x", {0: "d", 1: "w", 2: "g"}.get(j, "t"))
        layout.put(cols - 1, j, "x", {1: "b"}.get(j, "l"))
    return layout


def animation_sheet(out_dir):
    """Cada animación en una fila, de la pieza cerrada al último cuadro, para los dos ejes: cada
    cuadro pegado con su apoyo en el mismo punto."""
    manifest = dict((e["file"], e) for e in iso.registry())
    rows = []
    for family, _model, frames, _extra in FAMILIES:
        if not frames:
            continue
        label, count = frames
        for axis in ("y", "x"):
            names = ["%s_tall_%s" % (family, axis)]
            names += ["%s_tall_%s_%s_%d" % (family, axis, label, step) for step in range(1, count + 1)]
            rows.append(names)
    cell_w, cell_h = 176, 200
    width = max(len(r) for r in rows) * cell_w
    out = sheet.Image.new("RGBA", (width, len(rows) * cell_h), (69, 74, 89, 255))
    for r, names in enumerate(rows):
        for k, name in enumerate(names):
            image = _load(out_dir, name)
            offset = manifest.get(name + ".png", {}).get("base_offset", (0, 0))
            x = k * cell_w + 52 - offset[0]
            y = r * cell_h + 36 - offset[1]
            out.alpha_composite(image, (int(x), int(y)))
    out = out.resize((out.size[0] * 2, out.size[1] * 2), sheet.Image.NEAREST)
    out.save(os.path.join(out_dir, "sheet_walls_animations.png"))


def interior_layout():
    """Tabiques bajos: un cuarto cerrado con una puerta baja y las cuatro L de paredes bajas."""
    layout = WallLayout()
    for i in range(1, 4):
        layout.put(i, 0, "y", "l")
        layout.put(i, 3, "y", "b" if i == 2 else "l")
        layout.put(0, i, "x", "v" if i == 2 else "l")
        layout.put(3, i, "x", "l")
    return layout


def _add_character(out_dir, scene, x, y):
    path = os.path.join(out_dir, "character_stand_r1.png")
    if os.path.isfile(path):
        scene.add(sheet.load(path), x, y, anchor=(64, 112))


def build_scene(out_dir, layout, cols, rows, top, seed, posts=True, people=(), color=DEFAULT_COLOR):
    scene = sheet.Scene(cols, rows, top=top)
    scene.fill_floor(_floor_tiles(out_dir), seed=seed)
    shadows = dict((axis, _load(out_dir, "wall_tall_%s_shadow" % axis)) for axis in ("x", "y"))
    missing = layout.apply(scene, out_dir, posts, shadows, color)
    for x, y in people:
        _add_character(out_dir, scene, x, y)
    return scene, missing


def corner_crops(scene, corners, half=24, scale=6):
    """Recortes ampliados alrededor de vértices: [(x, y, alto sobre el piso en px)]."""
    image = scene.render(scale=1)
    crops = []
    for x, y, lift in corners:
        px, py = scene.cell_point(x, y)
        crops.append(image.crop((int(px - half), int(py - lift - half), int(px + half), int(py - lift + half))))
    return sheet.contact_sheet(crops, columns=len(crops), scale=scale, labels=False)


def review_sheets(out_dir, names):
    cols, rows = 4, 3
    rooms = []
    for doors_on in ("y", "x"):
        scene, _missing = build_scene(out_dir, room_layout(cols, rows, doors_on), cols, rows, 150, 4,
                                      people=((1, 1),))
        rooms.append(scene)
    sheet.contact_sheet([room.render(scale=1) for room in rooms], columns=2, scale=3, labels=False).save(
        os.path.join(out_dir, "sheet_walls_room.png"))
    bare, _missing = build_scene(out_dir, room_layout(cols, rows, "y"), cols, rows, 150, 4, posts=False)
    room = rooms[0]
    views = [corner_crops(room, [(0, 0, 112), (0, 0, 10), (0, rows, 112), (0, rows, 10), (cols, 0, 112),
                                 (cols, 0, 10), (cols, rows, 12)]),
             corner_crops(bare, [(0, 0, 112), (0, 0, 10), (0, rows, 112), (0, rows, 10), (cols, 0, 112),
                                 (cols, 0, 10), (cols, rows, 12)])]
    sheet.contact_sheet(views, columns=1, scale=1, labels=False).save(os.path.join(out_dir, "sheet_walls_corners.png"))
    interior, _missing = build_scene(out_dir, interior_layout(), 5, 5, 40, 7, people=((1, 1),))
    interior.render(scale=3).save(os.path.join(out_dir, "sheet_walls_interior.png"))
    variants, _missing = build_scene(out_dir, variants_layout(), 6, 3, 150, 5, people=((2, 1),))
    variants.render(scale=3).save(os.path.join(out_dir, "sheet_walls_variants.png"))
    animation_sheet(out_dir)
    colors = []
    for color, _top, _face, _light in WALL_COLORS:
        scene, _missing = build_scene(out_dir, room_layout(cols, rows, "y"), cols, rows, 150, 4,
                                      people=((1, 1),), color=color)
        colors.append((color, scene.render(scale=1)))
    sheet.contact_sheet(colors, columns=len(colors), scale=2).save(os.path.join(out_dir, "sheet_walls_colors.png"))
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    items = [(name, sheet.on_background(_load(out_dir, name), scale=1)) for name in names]
    sheet.contact_sheet(items, columns=6, scale=3).save(os.path.join(folder, "walls.png"))


# ---------------------------------------------------------------------------- principal

def anchor_meta(c, axis):
    """Datos del punto de apoyo para el manifiesto (punto medio del borde, en el piso)."""
    start = c.project(0.0, 0.0, 0.0)
    end = c.project(1.0, 0.0, 0.0)
    return {
        "anchor_at": "punto medio del borde de la casilla, en el piso",
        "edge": [[float(start[0]), float(start[1])], [float(end[0]), float(end[1])]],
        "thickness": int(round(iso.WALL_THICKNESS * 64)),
        "sort_bias": SORT_BIAS_X if axis == "x" else 0.0,
    }


# Piezas por familia: (nombre, modelo(f, tall, paso), cuadros, metadatos). Los cuadros son los
# pasos de la animación (paso 0 = la pieza cerrada) y salen solo en la alta: puertas que giran
# (_open_1 a _open_6, la hoja abierta de 15° en 15° hasta 90° hacia adentro), la de vidrio (_open_1 a
# _open_6, las dos hojas abren hacia afuera) y la ventana (_blind_1 a _blind_6, la persiana baja hasta
# cerrar).
def _door_family(kind):
    return (kind, lambda f, tall, step: door_model(f, tall, kind, SWING_ANGLES[step - 1] if step else 0),
            ("open", len(SWING_ANGLES)), {"door_height": DOOR_DATA["height"]})


FAMILIES = (
    ("wall", lambda f, tall, step: wall_model(f, WALL_TOP if tall else LOW), None, {}),
    _door_family("door"),
    _door_family("door_wood"),
    _door_family("door_office"),
    ("glass_door", lambda f, tall, step: glass_door_model(f, tall, GLASS_ANGLES[step - 1] if step else 0),
     ("open", len(GLASS_ANGLES)), {"door_height": GLASS_DOOR_DATA["height"]}),
    ("window", lambda f, tall, step: window_model(f, tall, step), ("blind", len(BLIND_LEVELS) - 1),
     {"height": WINDOW_DATA["height"]}),
)
# Lo que la hoja abierta sale del lienzo de la pared (izquierda, arriba, derecha, abajo, en px);
# después se recorta a lo que se usa en todos los cuadros.
FRAME_GROW = {"door": (48, 0, 48, 32), "glass_door": (32, 24, 32, 8)}  # la de vidrio abre hacia atrás


def make_piece(model, axis, tall, step=0, canvas=None):
    c = canvas or iso.Canvas.wall(axis, tall)
    model(Frame(c), tall, step)
    paint_canto(c)
    return c


def wide_wall_canvas(axis, tall, grow):
    """Lienzo de pared más grande con el mismo dibujo: la pared cae en los mismos pixeles que en
    Canvas.wall, corrida (izquierda, arriba)."""
    ref = iso.Canvas.wall(axis, tall)
    gl, gt, gr, gb = grow
    origin = (ref.origin[0] + gl, ref.origin[1] + gt)
    anchor = (ref.anchor[0] + gl, ref.anchor[1] + gt)
    c = iso.Canvas(ref.width + gl + gr, ref.height + gt + gb, origin, size=(1, 0), rotation=0, swap=ref.swap,
                   kind="wall_frame", anchor=anchor)
    c.repeat = list(ref.repeat)
    c.extra_meta.update(ref.extra_meta)
    return c, ref


def frame_set(out_dir, family, model, frames, axis, color, base_name):
    """Cuadros de la animación de una pieza alta, todos en el mismo lienzo y con el mismo apoyo
    que la pieza (corrido base_offset)."""
    label, count = frames
    if family in DOOR_TYPES:
        grow = FRAME_GROW["door"]
    else:
        grow = FRAME_GROW.get(family, (0, 0, 0, 0))
    images = []
    clipped = []
    ref = None
    for step in range(1, count + 1):
        c, ref = wide_wall_canvas(axis, True, grow)
        make_piece(model, axis, True, step, canvas=c)
        images.append(np.array(c.finish(ground_outline=FLOOR_LINE)))
        clipped.append(bool(c.clipped))
    gl, gt = grow[0], grow[1]
    alpha = np.zeros(images[0].shape[:2], dtype=bool)
    for arr in images:
        alpha |= arr[..., 3] == 255
    alpha[gt:gt + ref.height, gl:gl + ref.width] = True
    ys, xs = np.nonzero(alpha)
    y0, y1, x0, x1 = int(ys.min()), int(ys.max()) + 1, int(xs.min()), int(xs.max()) + 1
    offset = [gl - x0, gt - y0]
    anchor = [ref.anchor[0] + offset[0], ref.anchor[1] + offset[1]]
    files = []
    for step, arr in enumerate(images, 1):
        crop = np.ascontiguousarray(arr[y0:y1, x0:x1])
        name = colored("%s_tall_%s_%s_%d" % (family, axis, label, step), color)
        files.append(iso.save(sheet.Image.fromarray(crop, "RGBA"), out_dir, name, kind="wall_frame",
                              anchor=anchor, base=colored("%s_tall_%s" % (family, axis), color) + ".png",
                              base_offset=offset, frame=step, frames=count, animation=label, axis=axis,
                              wall_color=color, clipped=clipped[step - 1]))
    return files


# Lienzo de trabajo de la doble: entran los dos tramos, un tramo de pared a cada lado (para que el
# acabado empalme con las paredes vecinas) y las hojas abiertas hacia atrás.
DOUBLE_GROW = (136, 56, 136, 104)


def _double_render(axis, tall, half, angle, neighbors):
    c, ref = wide_wall_canvas(axis, tall, DOUBLE_GROW)
    c.repeat = []
    f = Frame(c)
    if neighbors:
        height = WALL_TOP if tall else LOW
        wall_model(f, height, -1.0, 0.0)
        wall_model(f, height, 2.0, 3.0)
    double_glass_model(f, tall, half, angle)
    if not neighbors:
        paint_canto(c)
    image = np.array(c.finish(ground_outline=FLOOR_LINE))
    p = c.pad
    depth = c.depth[p:p + c.height, p:p + c.width]
    return image, depth, c, ref


def double_half_image(axis, tall, half, angle=0):
    """La mitad como la vería el juego: sus pixeles (los de la mitad sola), con el acabado de la
    puerta armada entre dos paredes donde lo que se ve es de ella; donde la tapa otra pieza queda
    lo suyo, como en un tramo normal."""
    whole, whole_depth, c, ref = _double_render(axis, tall, None, angle, True)
    alone, alone_depth, _c, _ref = _double_render(axis, tall, half, angle, False)
    mine = alone[..., 3] == 255
    same = mine & (np.abs(whole_depth - alone_depth) < 1.0e-6) & (whole[..., 3] == 255)
    out = np.where(same[..., None], whole, alone)
    out[~mine] = 0
    return out, c, ref


def double_set(out_dir, color, files, names):
    """Las dos mitades (alta y baja, los dos ejes) y los cuadros de abrir de las altas."""
    for axis in ("x", "y"):
        for tall in (True, False):
            gl, gt = DOUBLE_GROW[0], DOUBLE_GROW[1]
            for k, half in enumerate(("a", "b")):
                image, c, ref = double_half_image(axis, tall, half)
                step = (np.array(ref.project(1.0, 0.0, 0.0)) - np.array(ref.project(0.0, 0.0, 0.0)))
                ox, oy = int(round(gl + step[0] * k)), int(round(gt + step[1] * k))
                base = np.ascontiguousarray(image[oy:oy + ref.height, ox:ox + ref.width])
                meta = anchor_meta(ref, axis)
                meta.update({"kind": "wall", "axis": axis, "tall": tall, "joins": False, "anchor": list(ref.anchor),
                             "height": WALL_DATA["height"] if tall else LOW_HEIGHT, "pair": half,
                             "pair_with": "b" if half == "a" else "a", "clipped": bool(c.clipped)})
                if tall:
                    meta["door_height"] = GLASS_DOOR_DATA["height"]
                name = colored("glass_door_double_%s_%s_%s" % (half, "tall" if tall else "low", axis), color)
                files.append(iso.save(sheet.Image.fromarray(base, "RGBA"), out_dir, name, wall_color=color, **meta))
                names.append(name)
                if not tall:
                    continue
                frames = []
                clipped = []
                for angle in DOUBLE_ANGLES:
                    frame, fc, _r = double_half_image(axis, True, half, angle)
                    frames.append(frame)
                    clipped.append(bool(fc.clipped))
                alpha = np.zeros(frames[0].shape[:2], dtype=bool)
                for arr in frames:
                    alpha |= arr[..., 3] == 255
                alpha[oy:oy + ref.height, ox:ox + ref.width] = True
                ys, xs = np.nonzero(alpha)
                y0, y1, x0, x1 = int(ys.min()), int(ys.max()) + 1, int(xs.min()), int(xs.max()) + 1
                offset = [ox - x0, oy - y0]
                anchor = [ref.anchor[0] + offset[0], ref.anchor[1] + offset[1]]
                for n, arr in enumerate(frames, 1):
                    crop = np.ascontiguousarray(arr[y0:y1, x0:x1])
                    fname = colored("glass_door_double_%s_tall_%s_open_%d" % (half, axis, n), color)
                    files.append(iso.save(sheet.Image.fromarray(crop, "RGBA"), out_dir, fname, kind="wall_frame",
                                          anchor=anchor, base=name + ".png", base_offset=offset, frame=n,
                                          frames=len(DOUBLE_ANGLES), animation="open", axis=axis, pair=half,
                                          wall_color=color, clipped=clipped[n - 1]))


def build(out_dir):
    files = []
    names = []
    for color, _top, _face, _light in WALL_COLORS:
        use_color(color)
        build_color(out_dir, color, files, names if color == DEFAULT_COLOR else [])
    use_color(DEFAULT_COLOR)
    for axis in ("x", "y"):
        name = "wall_tall_%s_shadow" % axis
        files.append(iso.save(wall_shadow(axis), out_dir, name, kind="shadow", footprint=[1, 1], anchor=[64, 96],
                              placed_on="casilla de adentro, delante de la pared alta del borde"))
        names.append(name)
    review_sheets(out_dir, names)  # la hoja de piezas, solo en el color de siempre
    return files


def build_color(out_dir, color, files, names):
    """Tramos, puertas, ventanas, sus cuadros y postes con la cara del color de turno (use_color)."""
    for family, model, frames, extra in FAMILIES:
        for tall in (True, False):
            for axis in ("x", "y"):
                c = make_piece(model, axis, tall)
                meta = anchor_meta(c, axis)
                if tall:
                    meta["height"] = WALL_DATA["height"]
                    meta.update(extra)
                else:
                    meta["height"] = LOW_HEIGHT
                c.finish(ground_outline=FLOOR_LINE)
                name = colored("%s_%s_%s" % (family, "tall" if tall else "low", axis), color)
                files.append(iso.save(c, out_dir, name, wall_color=color, **meta))
                names.append(name)
                if tall and frames:
                    files.extend(frame_set(out_dir, family, model, frames, axis, color, name))
    double_set(out_dir, color, files, names)
    for corner, neighbors in sorted(CORNERS.items()):
        image, anchor = post_piece(neighbors)
        height = max(POST_HEIGHTS[code] for code in neighbors)
        name = colored(corner, color)
        files.append(iso.save(image, out_dir, name, kind="post", anchor=list(anchor), wall_color=color,
                              anchor_at="vértice de la cuadrícula, en el piso",
                              neighbors=list(neighbors), neighbor_order="-x -y +x +y",
                              height=WALL_DATA["height"] if height > LOW else LOW_HEIGHT,
                              sort_after="tramos del vértice: Y del vértice + %g" % POST_SORT_BIAS))
        names.append(name)
