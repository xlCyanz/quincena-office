# Paredes, puertas, ventanas y esquinas (docs/sprites_128.md, sección 8) en el estilo de
# tools/sprites/STYLE.md: cara de pared lisa pastel fría (WALL_COOL), tapa y canto ciruela oscuro
# (WALL_CAP) con contorno, puerta beige con marco claro, tableros y manija metálica, y ventana
# con marco claro, vidrio celeste y persiana.
#
#   wall_tall_x  wall_tall_y  wall_low_x  wall_low_y         72×160 / 72×64
#   door_tall_x  door_tall_y  door_low_x  door_low_y         72×160 / 72×64
#   window_tall_x  window_tall_y  window_low_x  window_low_y  72×160 / 72×64
#   wall_tall_corner[_left|_right|_front]                     16×128, poste de esquina 8×8 px de planta
#   wall_low_corner[_back|_left|_right]                       16×28
#   wall_tall_x_shadow  wall_tall_y_shadow                    128×128, franja sobre la casilla de adentro
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
# bajos) y _sheets/walls.png (hoja de contacto ×3).
import os

import numpy as np

import iso
import palette as pal
import sheet

DATA = iso.load_json("data/construction.json")
WALL_DATA = DATA["wall"]
DOOR_DATA = DATA["door"]
WINDOW_DATA = DATA.get("window", {"height": 60})
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
    """Nombre de una pieza en un color: wall_tall_x -> wall_beige_tall_x (la fría no cambia)."""
    if color == DEFAULT_COLOR:
        return name
    head, rest = name.split("_", 1)
    return "%s_%s_%s" % (head, color, rest)


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


def leaf_face(ctx):
    """Cara de la hoja: dos tableros hundidos (ranura oscura arriba y a la izquierda, filo claro
    abajo y a la derecha), el de arriba más alto. Nada de veta: cara lisa."""
    a = np.floor((ctx.x - LEAF0) * 64.0)  # 0–43 a lo largo de la hoja
    b = np.floor(ctx.z - SILL)  # 0–85 desde el umbral
    base = np.asarray(ctx.base)
    index = base.copy()
    for a0, a1, b0, b1 in ((6, 38, 8, 36), (6, 38, 44, 78)):
        inside = (a >= a0) & (a < a1) & (b >= b0) & (b < b1)
        dark = inside & ((b == b1 - 1) | (a == a0))
        lit = inside & ((b == b0) | (a == a1 - 1)) & ~dark
        index = np.where(dark, LEAF_GROOVE, index)
        index = np.where(lit, LEAF_LIT, index)
    return index


def door_model(f, tall):
    """Puerta alta: pared a los lados (4 px) y encima del marco hasta 120, marco crema (jambas
    de 6 px y cabezal de 4), hoja beige hundida 2 px con dos tableros, umbral y manija.
    Puerta baja: la alta cortada a 20 px sin la hoja: pared, jambas bajas y el umbral."""
    height = WALL_TOP if tall else LOW
    # Pared a los lados (y encima, en la alta).
    if tall:
        wall_block(f, 0, DOOR_WALL, 0, DOOR_TOP, top=False)
        wall_block(f, 1 - DOOR_WALL, 1, 0, DOOR_TOP, top=False)
        wall_block(f, 0, 1, DOOR_TOP, height)
    else:
        wall_block(f, 0, DOOR_WALL, 0, height)
        wall_block(f, 1 - DOOR_WALL, 1, 0, height)
    # Marco: jambas, cabezal y umbral, del grosor de la pared.
    jamb_top = OPENING if tall else height
    f.box(JAMB0, JAMB1, -HALF, HALF, 0, jamb_top, FRAME, name="frame", part="frame")
    f.box(LEAF1, 1 - DOOR_WALL, -HALF, HALF, 0, jamb_top, FRAME, name="frame", part="frame")
    if tall:
        f.box(JAMB0, 1 - DOOR_WALL, -HALF, HALF, OPENING, DOOR_TOP, FRAME, name="frame", part="frame")
    f.box(LEAF0, LEAF1, -HALF, HALF, 0, SILL, LEAF, name="sill")
    if not tall:
        return
    # Hoja hundida y manija del lado de la jamba de adelante.
    f.box(LEAF0, LEAF1, -RECESS, RECESS, SILL, OPENING, LEAF, tex={iso.BACK: leaf_face}, name="leaf")
    hx = LEAF1 - 5 / 32.0
    f.box(hx, hx + 2 / 32.0, RECESS, RECESS + 1 / 64.0, HANDLE_Z - 6, HANDLE_Z + 6, METAL, name="plate",
          flat=False)
    f.box(hx - 4 / 32.0, hx + 2 / 32.0, RECESS + 1 / 64.0, RECESS + 2 / 64.0, HANDLE_Z, HANDLE_Z + 3, METAL,
          name="lever", flat=False)


def door_piece(axis, tall):
    c = iso.Canvas.wall(axis, tall)
    door_model(Frame(c), tall)
    paint_canto(c)
    return c


# ---------------------------------------------------------------------------- ventana

# Ventana alta: pared abajo (0–38) y arriba (102–120), pared a los lados (8 px), marco crema
# (alféizar 38–42, cabezal 98–102, jambas de 4 px y parante en el medio), vidrio hundido 2 px y
# persiana a medio bajar. La baja es una franja de ventana en la pared de 20.
WIN_WALL = 4 / 32.0
WIN_JAMB = 6 / 32.0
WIN_KINDS = {
    True: {"sill": (38, 42), "head": (98, 102), "blind": 78},
    False: {"sill": (4, 6), "head": (16, 18), "blind": None},
}


def glass_face(ctx):
    """Vidrio: en cada hoja dos reflejos cortos en diagonal (uno de 2 px y otro de 1 px)."""
    a = np.floor(ctx.x * 64.0)
    z = np.floor(ctx.z)
    pane = np.mod(a - WIN_JAMB * 64.0, 22.0)  # 0–21 dentro de cada hoja
    d = pane + np.mod(z, 64.0) * 0.5
    low = np.mod(z, 64.0)
    shine = ((d >= 9) & (d < 11) | (d >= 14) & (d < 15)) & (pane >= 2) & (pane < 18)
    return np.where(shine & (low > 0), pal.SHINE, ctx.base)


def blind_face(ctx):
    """Persiana: tablillas de 4 px con una rendija oscura y un filo claro abajo."""
    row = np.mod(np.floor(ctx.z), 4.0)
    base = np.asarray(ctx.base)
    index = np.where(row == 0, BLIND_GAP, base)
    return np.where(row == 3, pal.lighter(base), index)


def window_model(f, tall):
    height = WALL_TOP if tall else LOW
    spec = WIN_KINDS[tall]
    sill0, sill1 = spec["sill"]
    head0, head1 = spec["head"]
    # Pared alrededor.
    wall_block(f, 0, WIN_WALL, 0, height)
    wall_block(f, 1 - WIN_WALL, 1, 0, height)
    wall_block(f, WIN_WALL, 1 - WIN_WALL, 0, sill0, top=False)
    wall_block(f, WIN_WALL, 1 - WIN_WALL, head1, height)
    # Marco.
    f.box(WIN_WALL, 1 - WIN_WALL, -HALF, HALF, sill0, sill1, FRAME, name="frame", part="frame")
    f.box(WIN_WALL, 1 - WIN_WALL, -HALF, HALF, head0, head1, FRAME, name="frame", part="frame")
    f.box(WIN_WALL, WIN_JAMB, -HALF, HALF, sill1, head0, FRAME, name="frame", part="frame")
    f.box(1 - WIN_JAMB, 1 - WIN_WALL, -HALF, HALF, sill1, head0, FRAME, name="frame", part="frame")
    f.box(15 / 32.0, 17 / 32.0, -HALF, HALF, sill1, head0, FRAME, name="frame", part="frame")
    # Vidrio hundido y, en la alta, la persiana delante del vidrio.
    f.box(WIN_JAMB, 1 - WIN_JAMB, -RECESS, RECESS, sill1, head0, GLASS, tex={iso.BACK: glass_face},
          name="glass", flat=False)
    if spec["blind"] is not None:
        for x0, x1 in ((WIN_JAMB, 15 / 32.0), (17 / 32.0, 1 - WIN_JAMB)):
            f.box(x0, x1, -RECESS, RECESS + 1 / 64.0, spec["blind"], head0, BLIND, tex={iso.BACK: blind_face},
                  name="blind", flat=False)


def window_piece(axis, tall):
    c = iso.Canvas.wall(axis, tall)
    window_model(Frame(c), tall)
    paint_canto(c)
    return c


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
CODE_PIECES = {"t": "wall_tall", "l": "wall_low", "d": "door_tall", "b": "door_low",
               "w": "window_tall", "v": "window_low"}
CODE_FAMILY = {"t": "t", "d": "t", "w": "t", "l": "l", "b": "l", "v": "l"}


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
    """Tramos, puertas, ventanas y postes con la cara del color de turno (use_color)."""
    makers = (("wall", wall_piece), ("door", door_piece), ("window", window_piece))
    for piece, maker in makers:
        for tall in (True, False):
            for axis in ("x", "y"):
                name = "%s_%s_%s" % (piece, "tall" if tall else "low", axis)
                c = maker(axis, tall)
                meta = anchor_meta(c, axis)
                if not tall:
                    meta["height"] = LOW_HEIGHT
                elif piece == "door":
                    # El sprite llega a 120 (pared encima del marco); el marco, a 92.
                    meta["height"] = WALL_DATA["height"]
                    meta["door_height"] = DOOR_DATA["height"]
                elif piece == "window":
                    meta["height"] = WINDOW_DATA["height"]
                else:
                    meta["height"] = WALL_DATA["height"]
                c.finish(ground_outline=FLOOR_LINE)
                name = colored(name, color)
                files.append(iso.save(c, out_dir, name, wall_color=color, **meta))
                names.append(name)
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
