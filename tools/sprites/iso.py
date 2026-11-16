# Motor de sprites isométricos pixel por pixel (docs/sprites_128.md).
# Modelo: x, y en casillas (128×64 px; múltiplos de 1/32 para aristas 2:1), z en px de sprite (= height × 2).
# Pantalla: +x abajo-derecha, +y abajo-izquierda, +z arriba. Luz arriba-izquierda: arriba BASE, +y LEFT, +x RIGHT.
# El modelo va siempre en rotación 0 (frente a −y); el lienzo lo gira (r1 a +x, r2 a +y, r3 a −x).
import json
import math
import os

import numpy as np
from PIL import Image

import palette as pal

CELL_W = 128
CELL_H = 64
HALF_W = 64
HALF_H = 32
WORLD_SCALE = 2  # px de sprite por px del mundo
PAD = 32  # margen interno del lienzo: lo que cae ahí es un recorte (clipped)
GRID_STEP = 1.0 / 64.0  # x, y de una caja: múltiplos de esto (mejor de 1/32) para que salga 2:1

# Alto en pantalla de 1 casilla vertical en la proyección 2:1 real (128 / √2 × cos 30°): normales y esferas.
Z_METRIC = 78.4
RAY_SPEED = math.sqrt(2.0 * Z_METRIC * Z_METRIC + 64.0 * 64.0)

# Lado de pantalla de cada pixel (búfer Canvas.side).
SIDE_NONE = 0
SIDE_TOP = 1
SIDE_LEFT = 2
SIDE_RIGHT = 3
SIDE_CURVED = 4
SIDE_NAMES = {SIDE_TOP: "top", SIDE_LEFT: "left", SIDE_RIGHT: "right", SIDE_CURVED: "curved"}

# Caras del modelo (ctx.face y búfer Canvas.face).
TOP = "top"
FRONT = "y0"  # cara −y: el frente del mueble con rotación 0
BACK = "y1"  # cara +y: la espalda
X0 = "x0"  # cara −x
X1 = "x1"  # cara +x
SIDE = "side"  # manto de un cilindro
CAP = "cap"  # tapa de un cilindro o corte plano de un elipsoide
INNER = "inner"  # pared de adentro de un cilindro abierto
SURFACE = "surface"  # elipsoide, sdf, panel, sello
FACE_CODES = {TOP: 0, FRONT: 1, BACK: 2, X0: 3, X1: 4, SIDE: 5, CAP: 0, INNER: 6, SURFACE: 7}
FACE_NAMES = {0: TOP, 1: FRONT, 2: BACK, 3: X0, 4: X1, 5: SIDE, 6: INNER, 7: SURFACE}

# Dirección de la luz en (x, y, z) del mundo: arriba a la izquierda de la pantalla.
_LIGHT = np.array([-0.30, 0.45, 0.85])
LIGHT_DIR = _LIGHT / np.linalg.norm(_LIGHT)

# Bandas de sombreado de las curvas: (umbral de n·luz, índice de rampa), de más a menos luz.
LIGHT_BANDS = (
    (0.955, pal.LIGHT),
    (0.66, pal.BASE),
    (0.52, pal.SOFT),
    (0.10, pal.LEFT),
    (-0.44, pal.RIGHT),
    (-9.0, pal.DEEP),
)
# Bandas del manto de un cilindro por posición en pantalla (−1 izquierda, +1 derecha): (límite, índice).
CYLINDER_BANDS = (
    (-0.86, pal.LEFT),
    (-0.52, pal.SOFT),
    (0.08, pal.LEFT),
    (0.76, pal.RIGHT),
    (9.0, pal.DEEP),
)
# Pared de adentro de un cilindro abierto (se ve el fondo): la luz le da al lado derecho.
INNER_BANDS = (
    (0.15, pal.DEEP),
    (9.0, pal.RIGHT),
)

WALL_THICKNESS = 0.125  # 8 px de sprite
WALL_CANVAS_W = 72
WALL_CANVAS_TALL = 160
WALL_CANVAS_LOW = 64
WALL_LOW_HEIGHT = 20  # px de sprite (10 del mundo)

_DEPTH_EMPTY = -1.0e9

# Acabados (Canvas.finish(style=…)). 'salvaje' = STYLE.md: contorno del material (2 px contra el piso), línea
# interior, brillo de arista y esquinas recortadas. 'classic' = el del piloto.
STYLES = {
    "salvaje": {"outline": True, "highlight": "inner", "crease": "light", "occlusion": True,
                "inner_outline": "line", "outline_index": pal.OUTLINE, "line_index": pal.DEEP,
                "ground_outline": 2, "corners": True},
    "classic": {"outline": True, "highlight": "inner", "crease": True, "occlusion": True,
                "inner_outline": True, "outline_index": pal.OUTLINE, "line_index": pal.DEEP,
                "ground_outline": 1, "corners": False},
}
DEFAULT_STYLE = "salvaje"
GROUND_Z = 1.5  # px: un pixel de cara lateral con z hasta esto «toca el piso» (contorno grueso)


def world_px(height):
    """Alto en px del mundo (data/*.json) -> px de sprite."""
    return int(round(height * WORLD_SCALE))


def rhombus_mask(width=128, height=128):
    """Máscara (alto, ancho) del rombo de una casilla pegado abajo del lienzo (sección 3 de la guía)."""
    ys, xs = np.mgrid[0:height, 0:width]
    cy = ys - (height - CELL_H)
    cx = xs - (width - CELL_W) // 2
    return (np.abs(cx + 0.5 - HALF_W) / float(HALF_W) + np.abs(cy + 0.5 - HALF_H) / float(HALF_H)) <= 1.0


def canvas_size(size, height, flat=False):
    """Lienzo (ancho, alto) de un mueble (sección 6): size en casillas ya girado, height en px del mundo.
    flat = solo el rombo."""
    w, d = int(size[0]), int(size[1])
    width = (w + d) * HALF_W
    rhombus = (w + d) * HALF_H
    if flat:
        return (width, rhombus)
    total = rhombus + int(math.ceil(height * WORLD_SCALE))
    total = int(math.ceil(total / 32.0)) * 32
    if w + d == 2:
        total = max(total, 128)
    elif w + d == 4:
        total = max(total, 192)
    return (width, total)


def footprint_mask(width, height, size):
    """Máscara (alto, ancho) de la planta de size = (ancho, fondo) casillas pegada abajo del lienzo."""
    w, d = size
    ox = d * HALF_W
    oy = height - (w + d) * HALF_H
    ys, xs = np.mgrid[0:height, 0:width]
    rx = xs + 0.5 - ox
    ry = ys + 0.5 - oy
    u = (ry / HALF_H + rx / HALF_W) / 2.0
    v = (ry / HALF_H - rx / HALF_W) / 2.0
    return (u >= 0) & (u < w) & (v >= 0) & (v < d)


class TileGrid(object):
    """Coordenadas de cada pixel de una casilla de piso (o planta mayor). Arreglos alto × ancho:
      mask    pixeles de la planta
      x, y    pixel del lienzo
      u, v    coordenadas de casilla (0–1); U, V = u × 64 («px de eje»)
      iu, iv  floor(U), floor(V): cada par de suma par es un dominó de 2 px; los impares no tienen pixeles
      domino  número único del dominó (para pattern.exact_levels(group=…))
    """

    def __init__(self, cells=(1, 1), top_space=None):
        w, d = int(cells[0]), int(cells[1])
        self.cells = (w, d)
        self.width = (w + d) * HALF_W
        rhombus = (w + d) * HALF_H
        if top_space is None:
            top_space = (w, d) == (1, 1)
        self.height = max(rhombus, 128) if top_space else rhombus
        self.origin = (d * HALF_W, self.height - rhombus)
        ys, xs = np.mgrid[0:self.height, 0:self.width]
        self.x = xs
        self.y = ys
        rx = xs + 0.5 - self.origin[0]
        ry = ys + 0.5 - self.origin[1]
        self.u = (ry / HALF_H + rx / HALF_W) / 2.0
        self.v = (ry / HALF_H - rx / HALF_W) / 2.0
        self.U = self.u * 64.0
        self.V = self.v * 64.0
        self.iu = np.floor(self.U).astype(np.int64)
        self.iv = np.floor(self.V).astype(np.int64)
        self.mask = (self.u >= 0) & (self.u < w) & (self.v >= 0) & (self.v < d)
        self.domino = (self.iu + 4096) * 16384 + (self.iv + 4096)

    def image(self, indices, colors):
        """Imagen RGBA a partir de un arreglo de índices y una paleta (Ramp o lista de colores)."""
        return tile_image(self, indices, colors)

    def pixel_of(self, iu, iv):
        """Pixel (x, y) izquierdo del dominó (iu, iv) de la rejilla isométrica (iu + iv par)."""
        return (int(self.origin[0] + iu - iv - 1), int(self.origin[1] + (iu + iv) // 2))

    def wrap(self, x, y):
        """Lleva un pixel que se salió de la planta al lado opuesto (la vecina es la misma casilla)."""
        w, d = self.cells
        rx = x + 0.5 - self.origin[0]
        ry = y + 0.5 - self.origin[1]
        i = int(math.floor((ry / HALF_H + rx / HALF_W) / 2.0 / w))
        j = int(math.floor((ry / HALF_H - rx / HALF_W) / 2.0 / d))
        return (int(x - (i * w - j * d) * HALF_W), int(y - (i * w + j * d) * HALF_H))


def tile_grid(cells=(1, 1), top_space=None):
    """TileGrid de una casilla de piso (128×128) o de una planta mayor (solo el rombo)."""
    return TileGrid(cells, top_space)


def tile_image(grid, indices, colors):
    """Pinta grid.mask con colors[indices] y deja el resto transparente. Devuelve una imagen RGBA."""
    table = np.array([pal.hex_to_rgb(c) for c in colors], dtype=np.uint8)
    indices = np.asarray(indices)
    rgba = np.zeros((grid.height, grid.width, 4), dtype=np.uint8)
    safe = np.clip(np.where(grid.mask, indices, 0), 0, len(table) - 1)
    rgba[..., :3] = table[safe]
    rgba[..., 3] = np.where(grid.mask, 255, 0)
    rgba[~grid.mask] = 0
    return Image.fromarray(rgba, "RGBA")


class FaceContext(object):
    """Lo que recibe una textura: tex(ctx) -> índices de rampa (o None). Arreglos del lienzo interno:
      face    cara del modelo ('top', 'y0', 'y1', 'x0', 'x1'; en curvas 'side', 'cap', 'inner', 'surface')
      side    lado de pantalla: 'top', 'left', 'right' o 'curved'
      base    índice de rampa sin textura
      a, b    px dentro de la cara (64 por casilla): en los lados a de izquierda a derecha visto de frente y
              b el alto; arriba a sobre x y b sobre y desde (x0, y0). Giran con el modelo
      w, h    tamaño de la cara; x, y, z punto del modelo; sx, sy pixel del lienzo
      light   n·luz (−1 a 1) en curvas, con la normal nx, ny, nz; t posición −1…+1 en cilindros
    """

    def __init__(self):
        self.face = TOP
        self.side = "top"
        self.base = None
        self.a = None
        self.b = None
        self.w = 0.0
        self.h = 0.0
        self.x = None
        self.y = None
        self.z = None
        self.sx = None
        self.sy = None
        self.light = None
        self.nx = None
        self.ny = None
        self.nz = None
        self.t = None


def _bands(value, bands, upper=False):
    """Índices de rampa por bandas. upper=False: (umbral mínimo, índice) de mayor a menor;
    upper=True: (límite superior, índice) de menor a mayor."""
    out = np.full(value.shape, bands[-1][1], dtype=np.int16)
    if upper:
        for limit, index in reversed(bands):
            out = np.where(value < limit, index, out)
    else:
        for limit, index in reversed(bands):
            out = np.where(value >= limit, index, out)
    return out


def _shift(arr, dy, dx, fill):
    """out[y, x] = arr[y + dy, x + dx] (fill fuera del arreglo)."""
    out = np.full_like(arr, fill)
    h, w = arr.shape
    ys0, ys1 = max(-dy, 0), h - max(dy, 0)
    xs0, xs1 = max(-dx, 0), w - max(dx, 0)
    out[ys0:ys1, xs0:xs1] = arr[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx]
    return out


def _drop_isolated(mask):
    """Quita de una máscara los pixeles que no tienen ningún vecino (8 direcciones) en ella."""
    near = np.zeros(mask.shape, dtype=bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                near |= _shift(mask, dy, dx, False)
    return mask & near


def _despeckle(shade, part, mask):
    """Un pixel de curva sin vecino (4 direcciones) de su pieza y tono toma el tono más repetido entre
    sus vecinos de la pieza: evita líneas punteadas donde una banda mide menos de 1 px."""
    moves = ((0, -1), (-1, 0), (0, 1), (1, 0))
    n_shade = [_shift(shade, dy, dx, -99) for dy, dx in moves]
    n_same = [_shift(part, dy, dx, -1) == part for dy, dx in moves]
    lonely = mask.copy()
    for other, same in zip(n_shade, n_same):
        lonely &= ~(same & (other == shade))
    best = shade.copy()
    best_score = np.zeros(shade.shape, dtype=np.int16)
    for i in range(4):
        score = np.zeros(shade.shape, dtype=np.int16)
        for j in range(4):
            score += (n_same[i] & n_same[j] & (n_shade[i] == n_shade[j])).astype(np.int16)
        better = score > best_score
        best = np.where(better, n_shade[i], best)
        best_score = np.where(better, score, best_score)
    return np.where(lonely & (best_score > 0), best, shade)


def _on_grid(value, step):
    """True si value es múltiplo de step (con la tolerancia de los decimales)."""
    scaled = float(value) / step
    return abs(scaled - round(scaled)) < 1.0e-6


class Canvas(object):
    """Lienzo con z-buffer por software. Constructores:

      Canvas.furniture(size, height, rotation)  mueble (sección 6)
      Canvas.tile()                             128×128, una casilla (chicos, sobre el piso)
      Canvas.on_desk()                          128×128 para computadoras (z=0 es el piso)
      Canvas.wall(axis, tall)                   pared / puerta / ventana (sección 8)
      Canvas.wall_item(axis)                    objeto de pared 64×128 (sección 7)
      Canvas.character()                        personaje 128×128, pies en (64, 112)
      Canvas.tree()                             árbol 128×256, apoyo en (64, 224)
      Canvas.custom(width, height, origin)      cualquier otro

    Se agregan volúmenes en coordenadas del modelo (rotación 0) y finish() da la imagen. Búferes
    (alto+2·PAD × ancho+2·PAD): alpha, depth, part, face, side, shade, ramp_id, u, v, z, a, b.
    """

    def __init__(self, width, height, origin, size=(1, 1), rotation=0, swap=False, kind="custom",
                 anchor=None, model_height=None, pad=PAD):
        self.width = int(width)
        self.height = int(height)
        self.origin = (float(origin[0]), float(origin[1]))
        self.size = (float(size[0]), float(size[1]))
        self.rotation = int(rotation) % 4
        self.swap = bool(swap)
        self.kind = kind
        self.model_height = model_height
        self.pad = int(pad)
        self.anchor = anchor
        self.extra_meta = {}
        self._setup_transform()
        hh = self.height + 2 * self.pad
        ww = self.width + 2 * self.pad
        ys, xs = np.mgrid[0:hh, 0:ww]
        self.X = xs - self.pad
        self.Y = ys - self.pad
        self._rx = self.X + 0.5 - self.origin[0]
        self._ry = self.Y + 0.5 - self.origin[1]
        # Punto del piso (z = 0) que cae en cada pixel; a la altura z es (gu + z/64, gv + z/64).
        self._gu = (self._ry / HALF_H + self._rx / HALF_W) / 2.0
        self._gv = (self._ry / HALF_H - self._rx / HALF_W) / 2.0
        shape = (hh, ww)
        self.alpha = np.zeros(shape, dtype=bool)
        self.depth = np.full(shape, _DEPTH_EMPTY, dtype=np.float64)
        self.part = np.full(shape, -1, dtype=np.int32)
        self.face = np.full(shape, -1, dtype=np.int16)
        self.fid = np.full(shape, -1, dtype=np.int32)
        self.side = np.zeros(shape, dtype=np.int8)
        self.shade = np.zeros(shape, dtype=np.int16)
        self.ramp_id = np.full(shape, -1, dtype=np.int16)
        self.flat = np.zeros(shape, dtype=bool)
        self.u = np.zeros(shape, dtype=np.float64)
        self.v = np.zeros(shape, dtype=np.float64)
        self.z = np.zeros(shape, dtype=np.float64)
        self.a = np.zeros(shape, dtype=np.float64)
        self.b = np.zeros(shape, dtype=np.float64)
        self._no_outline = np.zeros(shape, dtype=bool)
        self._no_finish = np.zeros(shape, dtype=bool)
        self._smooth = np.zeros(shape, dtype=bool)  # curvas sin textura ni trama: se les quitan los pixeles sueltos
        self.min_z = None
        self.repeat = []  # copias vecinas para el acabado: [(dx, dy, cambio de profundidad), …]
        self.ramps = []
        self.parts = []  # por id: {"name", "outline", "shadow"}
        self._names = {}
        self._footprints = []  # para la sombra del piso
        self.curved = False
        self.clipped = False
        self.off_grid = []  # cajas con coordenadas fuera de la rejilla (sus aristas no salen 2:1)
        self.result = None
        self.final_shade = None
        self.final_alpha = None  # alfa después del acabado (sin las esquinas recortadas)
        self._finish_options = {}

    # ------------------------------------------------------------------ constructores

    @classmethod
    def furniture(cls, size=(1, 1), height=22, rotation=0, canvas=None, flat=False, kind="furniture"):
        """Lienzo de un mueble: size (ancho, fondo) del modelo en rotación 0 y height en px del mundo,
        como en data/furniture.json. canvas fuerza otro tamaño. Apoyo: centro del rombo de anclaje."""
        rotation = int(rotation) % 4
        w, d = size
        world = (w, d) if rotation % 2 == 0 else (d, w)
        if canvas is None:
            canvas = canvas_size(world, height, flat)
        width, total = canvas
        ox = world[1] * HALF_W
        oy = total - (world[0] + world[1]) * HALF_H
        c = cls(width, total, (ox, oy), size=size, rotation=rotation, kind=kind,
                anchor=(ox, oy + HALF_H), model_height=height)
        if flat:
            c.extra_meta["flat"] = True
        return c

    @classmethod
    def tile(cls, rotation=0, kind="furniture", height=32):
        """128×128 con apoyo en (64, 96): muebles 1×1 de hasta 64 px de alto y muebles chicos."""
        return cls.furniture((1, 1), height, rotation, canvas=(128, 128), kind=kind)

    @classmethod
    def on_desk(cls, rotation=0, height=12):
        """128×160 para computadoras: apoyo en (64, 128), z = 0 en el piso y el tablero en DESK_TOP."""
        c = cls.furniture((1, 1), height, rotation, canvas=(128, 160), kind="on_desk")
        return c

    @classmethod
    def wall(cls, axis="x", tall=True, kind="wall", joins=True):
        """Tramo de pared de 72×160 (alta) o 72×64 (baja); apoyo en el medio del borde: (36, alto − 18).
        Modelo: x de 0 a 1 a lo largo, y ±1/16 de grosor; se ven la cara 'y1', el canto 'x1' y 'top'.
        axis 'x' se ve «/» (cara a la derecha, −40 %); 'y' «\\» (a la izquierda, −25 %). joins=True
        acaba el tramo como si tuviera vecinos iguales (sin línea en la unión)."""
        height = WALL_CANVAS_TALL if tall else WALL_CANVAS_LOW
        half = WALL_THICKNESS / 2.0
        bottom = (1.0 + half) * HALF_H  # 34 px del origen a la punta de abajo de la planta
        if axis == "x":
            origin = (WALL_CANVAS_W - half * 64.0, height - bottom)
            anchor = (origin[0] - 32.0, origin[1] + 16.0)
            c = cls(WALL_CANVAS_W, height, origin, size=(1, 0), rotation=0, swap=True, kind=kind, anchor=anchor)
            if joins:
                c.repeat = [(-HALF_W, HALF_H, 1.0), (HALF_W, -HALF_H, -1.0)]
        else:
            origin = (half * 64.0, height - bottom)
            anchor = (origin[0] + 32.0, origin[1] + 16.0)
            c = cls(WALL_CANVAS_W, height, origin, size=(1, 0), rotation=0, swap=False, kind=kind, anchor=anchor)
            if joins:
                c.repeat = [(HALF_W, HALF_H, 1.0), (-HALF_W, -HALF_H, -1.0)]
        c.extra_meta.update({"axis": axis, "tall": bool(tall), "joins": bool(joins)})
        return c

    @classmethod
    def wall_item(cls, axis="x"):
        """Objeto de pared de 64×128, apoyo (32, 112). Modelo: x de 0 a 1, la pared en y = 0 y el objeto
        hacia +y (cara 'y1'); base en z = WALL_ITEM_BASE. Dejar libre x < 0.1 y x > 0.9."""
        if axis == "x":
            c = cls(64, 128, (64.0, 96.0), size=(1, 0), rotation=0, swap=True, kind="wall_item", anchor=(32.0, 112.0))
        else:
            c = cls(64, 128, (0.0, 96.0), size=(1, 0), rotation=0, swap=False, kind="wall_item", anchor=(32.0, 112.0))
        c.extra_meta.update({"axis": axis})
        return c

    @classmethod
    def character(cls, rotation=0):
        """Personaje 128×128 con los pies en (64, 112), parado en (0.5, 0.5) mirando a −y."""
        return cls(128, 128, (64.0, 80.0), size=(1, 1), rotation=rotation, kind="character", anchor=(64.0, 112.0))

    @classmethod
    def tree(cls):
        """Árbol: 128×256 con el rombo abajo y apoyo en (64, 224)."""
        return cls(128, 256, (64.0, 192.0), size=(1, 1), rotation=0, kind="tree", anchor=(64.0, 224.0))

    @classmethod
    def custom(cls, width, height, origin, size=(1, 1), rotation=0, kind="custom", anchor=None):
        """Lienzo libre; origin = pixel del punto (0, 0, 0) (punta de arriba del rombo de anclaje)."""
        return cls(width, height, origin, size=size, rotation=rotation, kind=kind, anchor=anchor)

    # ------------------------------------------------------------------ transformación

    def _setup_transform(self):
        w, d = self.size
        if self.swap:
            w, d = d, w
        r = self.rotation
        if r == 0:
            m = np.array([[1.0, 0.0], [0.0, 1.0]])
            t = np.array([0.0, 0.0])
        elif r == 1:
            m = np.array([[0.0, -1.0], [1.0, 0.0]])
            t = np.array([d, 0.0])
        elif r == 2:
            m = np.array([[-1.0, 0.0], [0.0, -1.0]])
            t = np.array([w, d])
        else:
            m = np.array([[0.0, 1.0], [-1.0, 0.0]])
            t = np.array([0.0, w])
        if self.swap:
            m = m.dot(np.array([[0.0, 1.0], [1.0, 0.0]]))
        self._m = m
        self._t = t
        self.world_size = (w, d) if r % 2 == 0 else (d, w)
        names = {(1, 0): X1, (-1, 0): X0, (0, 1): BACK, (0, -1): FRONT}
        inv = m.T
        du = inv.dot(np.array([1.0, 0.0]))
        dv = inv.dot(np.array([0.0, 1.0]))
        # Cara del modelo que queda mirando a +u (derecha en pantalla) y a +v (izquierda).
        self.right_face = names[(int(round(du[0])), int(round(du[1])))]
        self.left_face = names[(int(round(dv[0])), int(round(dv[1])))]

    def to_world(self, x, y):
        """Punto del modelo (casillas) -> punto del mundo ya girado (u, v)."""
        m, t = self._m, self._t
        return (m[0, 0] * x + m[0, 1] * y + t[0], m[1, 0] * x + m[1, 1] * y + t[1])

    def to_model(self, u, v):
        """Punto del mundo (u, v) -> punto del modelo (x, y). Acepta arreglos."""
        m, t = self._m, self._t
        du = u - t[0]
        dv = v - t[1]
        return (m[0, 0] * du + m[1, 0] * dv, m[0, 1] * du + m[1, 1] * dv)

    def project(self, x, y, z=0.0):
        """Pixel del lienzo final (con decimales) donde cae el punto (x, y, z) del modelo."""
        u, v = self.to_world(x, y)
        return (self.origin[0] + (u - v) * HALF_W, self.origin[1] + (u + v) * HALF_H - z)

    def face_side(self, face):
        """Lado de pantalla ('top', 'left', 'right' o None) de una cara del modelo con esta rotación."""
        if face == TOP:
            return "top"
        if face == self.left_face:
            return "left"
        if face == self.right_face:
            return "right"
        return None

    # ------------------------------------------------------------------ piezas y rampas

    def _ramp_id(self, ramp):
        for index, known in enumerate(self.ramps):
            if known is ramp:
                return index
        self.ramps.append(ramp)
        return len(self.ramps) - 1

    def _part_ids(self, part):
        """Ids de pieza desde un id, un nombre (todas las que lo llevan) o una lista."""
        if isinstance(part, str):
            if part not in self._names:
                raise KeyError("no hay ninguna pieza llamada %r (hay: %s)"
                               % (part, ", ".join(sorted(self._names)) or "ninguna"))
            return list(self._names[part])
        if isinstance(part, (list, tuple, set)):
            ids = []
            for item in part:
                ids.extend(self._part_ids(item))
            return ids
        return [int(part)]

    def _new_part(self, name, part, outline, shadow=True):
        if part is not None:
            # Fundirse con otra pieza: con un nombre repetido, la primera que lo usó.
            return self._part_ids(part)[0]
        self.parts.append({"name": name, "outline": bool(outline), "shadow": bool(shadow), "rim": None})
        pid = len(self.parts) - 1
        if name:
            self._names.setdefault(name, []).append(pid)
        return pid

    def part_id(self, name):
        """Id de la pieza con ese nombre (el `name` de box, cylinder…); si varias lo llevan, la primera."""
        return self._part_ids(name)[0]

    def style_part(self, part, outline=None, rim=None):
        """Cambia el acabado de una pieza (id o nombre). outline = contorno de silueta; rim = borde donde
        tapa a otra pieza: 'full' contorno, 'soft' un paso, 'left' solo a la izquierda, 'line' línea DEEP
        de 1 px, 'none' nada."""
        for pid in self._part_ids(part):
            if outline is not None:
                self.parts[pid]["outline"] = bool(outline)
            if rim is not None:
                self.parts[pid]["rim"] = rim
        self.result = None

    def _resolve_tex(self, tex, face):
        if tex is None:
            return None
        if isinstance(tex, dict):
            if face in tex:
                return tex[face]
            if face not in (TOP, CAP) and "sides" in tex:
                return tex["sides"]
            return tex.get("all")
        return tex

    @staticmethod
    def _resolve_shade(shade, face):
        if isinstance(shade, dict):
            return int(shade.get(face, shade.get("all", 0)))
        return int(shade)

    def _apply_shade(self, base, shade):
        if shade < 0:
            return pal.darker(base, -shade)
        if shade > 0:
            return pal.lighter(base, shade)
        return base

    def _put(self, mask, depth, shade, pid, face, side, rid, u, v, z, a, b, flat=False, smooth=False):
        m = mask & (depth >= self.depth - 1.0e-7)
        if not m.any():
            return m
        self._smooth[m] = smooth
        lowest = float(np.min(np.broadcast_to(z, m.shape)[mask]))
        self.min_z = lowest if self.min_z is None else min(self.min_z, lowest)
        self.depth[m] = depth[m]
        self.alpha[m] = True
        self.part[m] = pid
        self.face[m] = FACE_CODES[face]
        self.fid[m] = pid * 8 + FACE_CODES[face]
        self.side[m] = side
        self.shade[m] = np.broadcast_to(shade, m.shape)[m]
        self.ramp_id[m] = rid
        self.flat[m] = flat
        self.u[m] = np.broadcast_to(u, m.shape)[m]
        self.v[m] = np.broadcast_to(v, m.shape)[m]
        self.z[m] = np.broadcast_to(z, m.shape)[m]
        self.a[m] = np.broadcast_to(a, m.shape)[m]
        self.b[m] = np.broadcast_to(b, m.shape)[m]
        self.result = None
        return m

    def _context(self, face, side, base, a, b, w, h, u, v, z):
        ctx = FaceContext()
        ctx.face = face
        ctx.side = SIDE_NAMES.get(side, "curved")
        ctx.base = np.broadcast_to(np.asarray(base, dtype=np.int16), self.alpha.shape)
        ctx.a = a
        ctx.b = b
        ctx.w = w
        ctx.h = h
        x, y = self.to_model(u, v)
        ctx.x = x
        ctx.y = y
        ctx.z = np.broadcast_to(z, self.alpha.shape)
        ctx.sx = self.X
        ctx.sy = self.Y
        return ctx

    def _textured(self, tex, ctx):
        if tex is None:
            return ctx.base, True
        out = tex(ctx)
        if out is None:
            return ctx.base, True
        return np.broadcast_to(np.asarray(out).astype(np.int16), self.alpha.shape), False

    # ------------------------------------------------------------------ caja

    def box(self, x0, x1, y0, y1, z0, z1, ramp, tex=None, shade=0, faces=None, name=None, part=None,
            outline=True, shadow=True, flat=True):
        """Caja recta de (x0, y0, z0) a (x1, y1, z1) en el modelo. Devuelve el id de la pieza.

        tex      tex(ctx) o dict por cara ({'top', iso.FRONT, 'sides', 'all'}); sin textura, tono exacto
        shade    pasos de sombra (−1 = más oscura) o dict por cara
        faces    caras a dibujar (por defecto las que se ven)
        name     nombre para select(); part = pieza con la que se funde (sin contorno entre ellas)
        outline  False = sin contorno; shadow False = fuera de ground_shadow(); flat False = no cuenta
                 como cara lisa para check.py (tramas enteras)
        En el mismo plano gana la que se dibuja después.
        """
        ua, va = self.to_world(x0, y0)
        ub, vb = self.to_world(x1, y1)
        u0, u1 = min(ua, ub), max(ua, ub)
        v0, v1 = min(va, vb), max(va, vb)
        pid = self._new_part(name, part, outline, shadow)
        rid = self._ramp_id(ramp)
        xa, xb = min(x0, x1), max(x0, x1)
        ya, yb = min(y0, y1), max(y0, y1)
        if not (all(_on_grid(value, GRID_STEP) for value in (x0, x1, y0, y1))
                and _on_grid(z0, 0.5) and _on_grid(z1, 0.5)):
            label = name or self.parts[pid]["name"] or "caja %d" % pid
            if label not in self.off_grid:
                self.off_grid.append(label)
        if shadow:
            self._footprints.append(("rect", u0, u1, v0, v1, z0, z1))
        gu, gv = self._gu, self._gv
        # Cara de arriba.
        if faces is None or TOP in faces:
            u = gu + z1 / 64.0
            v = gv + z1 / 64.0
            mask = (u >= u0) & (u < u1) & (v >= v0) & (v < v1)
            if mask.any():
                x, y = self.to_model(u, v)
                ctx = self._context(TOP, SIDE_TOP, pal.BASE, (x - xa) * 64.0, (y - ya) * 64.0,
                                    (xb - xa) * 64.0, (yb - ya) * 64.0, u, v, z1)
                base = self._apply_shade(ctx.base, self._resolve_shade(shade, TOP))
                ctx.base = np.broadcast_to(base, self.alpha.shape)
                index, plain = self._textured(self._resolve_tex(tex, TOP), ctx)
                self._put(mask, u + v + z1 / 64.0, index, pid, TOP, SIDE_TOP, rid, u, v, z1, ctx.a, ctx.b,
                          flat and self._resolve_shade(shade, TOP) == 0)
        # Cara izquierda en pantalla (+v) y derecha (+u).
        for side, face in ((SIDE_LEFT, self.left_face), (SIDE_RIGHT, self.right_face)):
            if faces is not None and face not in faces:
                continue
            if side == SIDE_LEFT:
                u = self._rx / HALF_W + v1
                v = np.full(self.alpha.shape, v1)
                z = (u + v1) * HALF_H - self._ry
                mask = (u >= u0) & (u < u1) & (z > z0) & (z <= z1)
                default = pal.LEFT
            else:
                v = u1 - self._rx / HALF_W
                u = np.full(self.alpha.shape, u1)
                z = (u1 + v) * HALF_H - self._ry
                mask = (v >= v0) & (v < v1) & (z > z0) & (z <= z1)
                default = pal.RIGHT
            if not mask.any():
                continue
            x, y = self.to_model(u, v)
            if face == BACK:
                a, w = (x - xa) * 64.0, (xb - xa) * 64.0
            elif face == FRONT:
                a, w = (xb - x) * 64.0, (xb - xa) * 64.0
            elif face == X1:
                a, w = (yb - y) * 64.0, (yb - ya) * 64.0
            else:
                a, w = (y - ya) * 64.0, (yb - ya) * 64.0
            ctx = self._context(face, side, default, a, z - z0, w, float(z1 - z0), u, v, z)
            offset = self._resolve_shade(shade, face)
            base = self._apply_shade(ctx.base, offset)
            ctx.base = np.broadcast_to(base, self.alpha.shape)
            index, plain = self._textured(self._resolve_tex(tex, face), ctx)
            self._put(mask, u + v + z / 64.0, index, pid, face, side, rid, u, v, z, ctx.a, ctx.b,
                      flat and offset == 0)
        return pid

    def slab(self, x0, x1, y0, y1, z, ramp, tex=None, shade=0, name=None, part=None, outline=False):
        """Parche plano horizontal a la altura z (solo cara de arriba): tapetes, marcas, papeles."""
        return self.box(x0, x1, y0, y1, z, z, ramp, tex=tex, shade=shade, faces=(TOP,), name=name, part=part,
                        outline=outline, shadow=False, flat=False)

    # ------------------------------------------------------------------ cilindro / cono truncado

    def cylinder(self, cx, cy, radius, z0, z1, ramp, radius_top=None, tex=None, cap=True, open_top=False,
                 bands=None, shade=0, name=None, part=None, outline=True, shadow=True):
        """Cilindro vertical (cono truncado con radius_top) de centro (cx, cy), radio en casillas, de z0 a z1.

        cap       tapa de arriba ('cap', BASE)
        open_top  sin tapa: se ve la pared de adentro ('inner'); el contenido va en otro cilindro más angosto
        bands     ((límite de t, índice), …), t de −1 a +1; por defecto CYLINDER_BANDS
        tex       tex(ctx) o dict 'side'/'cap'/'inner'; en el manto ctx.a = arco en px desde el frente
        Radio 0.5 llena la casilla (90 px de ancho).
        """
        self.curved = True
        cu, cv = self.to_world(cx, cy)
        r0 = float(radius)
        r1 = r0 if radius_top is None else float(radius_top)
        pid = self._new_part(name, part, outline, shadow)
        rid = self._ramp_id(ramp)
        if shadow:
            self._footprints.append(("disc", cu, cv, max(r0, r1), z0, z1))
        gu, gv = self._gu, self._gv
        da = gu - cu
        db = gv - cv
        height = float(z1 - z0)
        k = (r1 - r0) / height if height > 0 else 0.0
        c0 = r0 - k * z0
        qa = 2.0 - (64.0 * k) ** 2
        qb = 2.0 * (da + db) - 2.0 * c0 * 64.0 * k
        qc = da * da + db * db - c0 * c0
        with np.errstate(invalid="ignore", divide="ignore"):
            if abs(qa) < 1.0e-9:
                t_a = -qc / qb
                t_b = t_a
                real = np.isfinite(t_a)
            else:
                disc = qb * qb - 4.0 * qa * qc
                real = disc >= 0
                root = np.sqrt(np.where(real, disc, 0.0))
                t_a = (-qb + root) / (2.0 * qa)
                t_b = (-qb - root) / (2.0 * qa)
        t_near = np.maximum(t_a, t_b)
        t_far = np.minimum(t_a, t_b)

        def surface(t, face, band_table, upper):
            z = 64.0 * t
            rad = c0 + k * z
            with np.errstate(invalid="ignore"):
                ok = real & (z > z0) & (z <= z1) & (rad > 0)
            if not ok.any():
                return
            u = gu + t
            v = gv + t
            safe = np.where(rad > 1.0e-9, rad, 1.0)
            pos = np.clip((da - db) / (safe * math.sqrt(2.0)), -1.0, 1.0)
            nu = (da + t) / safe
            nv = (db + t) / safe
            mx, my = self._m.T.dot(np.array([1.0, 0.0])), self._m.T.dot(np.array([0.0, 1.0]))
            nxm = mx[0] * nu + my[0] * nv
            nym = mx[1] * nu + my[1] * nv
            angle = (np.arctan2(nym, nxm) + math.pi / 2.0) % (2.0 * math.pi)
            base = _bands(pos, band_table, upper=True)
            ctx = self._context(face, SIDE_CURVED, base, angle * max(r0, r1) * 64.0, z - z0,
                                2.0 * math.pi * max(r0, r1) * 64.0, height, u, v, z)
            ctx.t = pos
            ctx.nx, ctx.ny, ctx.nz = nxm, nym, np.zeros_like(nxm)
            ctx.light = nu * LIGHT_DIR[0] + nv * LIGHT_DIR[1]
            offset = self._resolve_shade(shade, face)
            ctx.base = np.broadcast_to(self._apply_shade(ctx.base, offset), self.alpha.shape)
            index, plain = self._textured(self._resolve_tex(tex, face), ctx)
            self._put(ok, np.where(ok, u + v + z / 64.0, _DEPTH_EMPTY), index, pid, face, SIDE_CURVED, rid,
                      u, v, z, ctx.a, ctx.b, smooth=plain)

        if open_top:
            surface(t_far, INNER, INNER_BANDS, True)
        surface(t_near, SIDE, bands or CYLINDER_BANDS, True)
        if cap and not open_top and r1 > 0:
            u = gu + z1 / 64.0
            v = gv + z1 / 64.0
            dist = np.sqrt((u - cu) ** 2 + (v - cv) ** 2)
            mask = dist <= r1
            if mask.any():
                x, y = self.to_model(u, v)
                ctx = self._context(CAP, SIDE_TOP, pal.BASE, (x - cx + r1) * 64.0, (y - cy + r1) * 64.0,
                                    2.0 * r1 * 64.0, 2.0 * r1 * 64.0, u, v, z1)
                ctx.t = dist / r1
                offset = self._resolve_shade(shade, CAP)
                ctx.base = np.broadcast_to(self._apply_shade(ctx.base, offset), self.alpha.shape)
                index, _plain = self._textured(self._resolve_tex(tex, CAP), ctx)
                self._put(mask, u + v + z1 / 64.0, index, pid, CAP, SIDE_TOP, rid, u, v, z1, ctx.a, ctx.b)
        return pid

    # ------------------------------------------------------------------ elipsoide

    def ellipsoid(self, cx, cy, cz, rx, ry, rz, ramp, tex=None, bands=None, dither=0.0, clip_z=None,
                  shade=0, name=None, part=None, outline=True, shadow=True):
        """Elipsoide de centro (cx, cy) en casillas y cz en px; rx, ry en casillas y rz en px.

        bands   ((umbral de n·luz, índice), …); por defecto LIGHT_BANDS
        dither  ancho de trama Bayer entre bandas (p. ej. 0.08); 0 = corte limpio
        clip_z  (z mín, z máx): el corte de arriba se ve como tapa plana ('cap')
        Para una esfera redonda en pantalla usar sphere().
        """
        self.curved = True
        cu, cv = self.to_world(cx, cy)
        ru, rv = (rx, ry) if abs(self._m[0, 0]) > 0.5 else (ry, rx)
        ru, rv, rz = float(ru), float(rv), float(rz)
        pid = self._new_part(name, part, outline, shadow)
        rid = self._ramp_id(ramp)
        z_lo, z_hi = (cz - rz, cz + rz) if clip_z is None else (max(clip_z[0], cz - rz), min(clip_z[1], cz + rz))
        if shadow:
            self._footprints.append(("ellipse", cu, cv, ru, rv, z_lo, z_hi))
        gu, gv = self._gu, self._gv
        da = gu - cu
        db = gv - cv
        qa = 1.0 / ru ** 2 + 1.0 / rv ** 2 + 4096.0 / rz ** 2
        qb = 2.0 * (da / ru ** 2 + db / rv ** 2 - 64.0 * cz / rz ** 2)
        qc = da ** 2 / ru ** 2 + db ** 2 / rv ** 2 + cz ** 2 / rz ** 2 - 1.0
        disc = qb * qb - 4.0 * qa * qc
        real = disc >= 0
        t = (-qb + np.sqrt(np.where(real, disc, 0.0))) / (2.0 * qa)
        z = 64.0 * t
        ok = real & (z > z_lo - 1.0e-9) & (z <= z_hi + 1.0e-9)
        u = gu + t
        v = gv + t
        nu = (da + t) / ru ** 2
        nv = (db + t) / rv ** 2
        nz = (z - cz) * Z_METRIC / rz ** 2
        length = np.sqrt(nu ** 2 + nv ** 2 + nz ** 2)
        length = np.where(length > 1.0e-12, length, 1.0)
        nu, nv, nz = nu / length, nv / length, nz / length
        light = nu * LIGHT_DIR[0] + nv * LIGHT_DIR[1] + nz * LIGHT_DIR[2]
        self._curved_put(ok, u, v, z, nu, nv, nz, light, ramp, rid, pid, tex, bands, dither, shade, SURFACE,
                         (cx - rx, cy - ry, cz - rz), (2.0 * rx * 64.0, 2.0 * rz))
        if clip_z is not None and z_hi < cz + rz - 1.0e-9:
            uc = gu + z_hi / 64.0
            vc = gv + z_hi / 64.0
            inside = ((uc - cu) / ru) ** 2 + ((vc - cv) / rv) ** 2 + ((z_hi - cz) / rz) ** 2 <= 1.0
            if inside.any():
                x, y = self.to_model(uc, vc)
                ctx = self._context(CAP, SIDE_TOP, pal.BASE, (x - cx + rx) * 64.0, (y - cy + ry) * 64.0,
                                    2.0 * rx * 64.0, 2.0 * ry * 64.0, uc, vc, z_hi)
                offset = self._resolve_shade(shade, CAP)
                ctx.base = np.broadcast_to(self._apply_shade(ctx.base, offset), self.alpha.shape)
                index, _plain = self._textured(self._resolve_tex(tex, CAP), ctx)
                self._put(inside, uc + vc + z_hi / 64.0, index, pid, CAP, SIDE_TOP, rid, uc, vc, z_hi, ctx.a, ctx.b)
        return pid

    def sphere(self, cx, cy, cz, radius, ramp, **kwargs):
        """Esfera (radio en casillas) que se ve redonda en pantalla: rz = radio × Z_METRIC."""
        return self.ellipsoid(cx, cy, cz, radius, radius, radius * Z_METRIC, ramp, **kwargs)

    def _curved_put(self, ok, u, v, z, nu, nv, nz, light, ramp, rid, pid, tex, bands, dither, shade, face,
                    corner, extent):
        if not ok.any():
            return
        value = light
        if dither:
            import pattern
            value = light + (pattern.bayer(self.X, self.Y, 4) - 0.5) * float(dither)
        base = _bands(value, bands or LIGHT_BANDS, upper=False)
        x, y = self.to_model(u, v)
        ctx = self._context(face, SIDE_CURVED, base, (x - corner[0]) * 64.0, z - corner[2], extent[0], extent[1],
                            u, v, z)
        inv = self._m.T
        ctx.nx = inv[0, 0] * nu + inv[0, 1] * nv
        ctx.ny = inv[1, 0] * nu + inv[1, 1] * nv
        ctx.nz = nz
        ctx.light = light
        offset = self._resolve_shade(shade, face)
        ctx.base = np.broadcast_to(self._apply_shade(ctx.base, offset), self.alpha.shape)
        index, plain = self._textured(self._resolve_tex(tex, face), ctx)
        self._put(ok, np.where(ok, u + v + z / 64.0, _DEPTH_EMPTY), index, pid, face, SIDE_CURVED, rid,
                  u, v, z, ctx.a, ctx.b, smooth=plain and not dither)

    # ------------------------------------------------------------------ caja de esquinas redondas

    def rounded_box(self, x0, x1, y0, y1, z0, z1, radius, ramp, tex=None, shade=0, name=None, part=None,
                    outline=True, shadow=True):
        """Caja con las aristas verticales redondeadas (radio en casillas) y tapa plana; una sola pieza.
        Las caras rectas salen exactas. Para redondear también arriba usar soft_box()."""
        radius = min(float(radius), abs(x1 - x0) / 2.0, abs(y1 - y0) / 2.0)
        xa, xb = min(x0, x1), max(x0, x1)
        ya, yb = min(y0, y1), max(y0, y1)
        pid = self._new_part(name, part, outline, shadow)
        for cx, cy in ((xa + radius, ya + radius), (xb - radius, ya + radius),
                       (xa + radius, yb - radius), (xb - radius, yb - radius)):
            self.cylinder(cx, cy, radius, z0, z1, ramp, tex=self._round_tex(tex), shade=shade, part=pid,
                          shadow=shadow)
        if xb - xa > 2.0 * radius:
            self.box(xa + radius, xb - radius, ya, yb, z0, z1, ramp, tex=tex, shade=shade, part=pid, shadow=shadow)
        if yb - ya > 2.0 * radius:
            self.box(xa, xb, ya + radius, yb - radius, z0, z1, ramp, tex=tex, shade=shade, part=pid, shadow=shadow)
        return pid

    def _round_tex(self, tex):
        # En las esquinas solo se aplica la textura de la tapa (como 'top'); el manto queda en bandas.
        if tex is None:
            return None
        top = self._resolve_tex(tex, TOP)
        return {CAP: top} if top is not None else None

    # ------------------------------------------------------------------ panel inclinado

    def panel(self, origin, edge_a, edge_b, ramp, tex=None, index=None, bands=None, name=None, part=None,
              outline=True, shadow=False):
        """Paralelogramo plano inclinado (respaldos, pantallas): origin = (x, y, z) y lados edge_a, edge_b
        como (dx, dy, dz); en tex, ctx.a y ctx.b en px a lo largo de cada lado. Se ve por los dos lados;
        tono por bandas o index fijo. Bordes sin escalera 2:1."""
        self.curved = True
        pid = self._new_part(name, part, outline, shadow)
        rid = self._ramp_id(ramp)
        ou, ov = self.to_world(origin[0], origin[1])
        oz = float(origin[2])

        def edge_world(edge):
            m = self._m
            return np.array([m[0, 0] * edge[0] + m[0, 1] * edge[1], m[1, 0] * edge[0] + m[1, 1] * edge[1],
                             float(edge[2])])

        ea = edge_world(edge_a)
        eb = edge_world(edge_b)
        normal = np.cross(ea, eb)
        ray = np.array([1.0, 1.0, 64.0])
        denom = float(normal.dot(ray))
        if abs(denom) < 1.0e-12:
            return pid  # de canto: no se ve
        gu, gv = self._gu, self._gv
        t = (normal[0] * (ou - gu) + normal[1] * (ov - gv) + normal[2] * oz) / denom
        pu = gu + t - ou
        pv = gv + t - ov
        pz = 64.0 * t - oz
        # Resolver p = s·ea + w·eb por mínimos cuadrados (matriz de Gram 2×2).
        gaa, gab, gbb = ea.dot(ea), ea.dot(eb), eb.dot(eb)
        det = gaa * gbb - gab * gab
        pa = pu * ea[0] + pv * ea[1] + pz * ea[2]
        pb = pu * eb[0] + pv * eb[1] + pz * eb[2]
        s = (pa * gbb - pb * gab) / det
        w = (pb * gaa - pa * gab) / det
        mask = (s >= 0) & (s < 1) & (w >= 0) & (w < 1)
        if not mask.any():
            return pid
        phys = np.array([1.0, 1.0, 1.0 / Z_METRIC])
        n_phys = np.cross(ea * phys, eb * phys)
        n_phys = n_phys / np.linalg.norm(n_phys)
        view = np.array([1.0, 1.0, 64.0 / Z_METRIC])
        if n_phys.dot(view) < 0:
            n_phys = -n_phys
        light = float(n_phys.dot(LIGHT_DIR))
        base = index if index is not None else int(_bands(np.array([light]), bands or LIGHT_BANDS)[0])
        len_a = math.sqrt((ea[0] * 64.0) ** 2 + (ea[1] * 64.0) ** 2 + ea[2] ** 2)
        len_b = math.sqrt((eb[0] * 64.0) ** 2 + (eb[1] * 64.0) ** 2 + eb[2] ** 2)
        u = gu + t
        v = gv + t
        z = 64.0 * t
        ctx = self._context(SURFACE, SIDE_CURVED, base, s * len_a, w * len_b, len_a, len_b, u, v, z)
        ctx.light = np.full(self.alpha.shape, light)
        idx, _plain = self._textured(self._resolve_tex(tex, SURFACE), ctx)
        self._put(mask, np.where(mask, u + v + z / 64.0, _DEPTH_EMPTY), idx, pid, SURFACE, SIDE_CURVED, rid,
                  u, v, z, ctx.a, ctx.b)
        return pid

    # ------------------------------------------------------------------ campo de distancia (formas libres)

    def sdf(self, fn, bounds, ramp, tex=None, bands=None, dither=0.0, shade=0, name=None, part=None,
            outline=True, shadow=True, steps=96):
        """Forma libre dada por fn(x, y, z) -> distancia con signo en px (negativa adentro), cortada a
        bounds = (x0, x1, y0, y1, z0, z1). Sombreado por bandas; bordes sin escalera 2:1."""
        self.curved = True
        pid = self._new_part(name, part, outline, shadow)
        rid = self._ramp_id(ramp)
        x0, x1, y0, y1, z0, z1 = bounds
        ua, va = self.to_world(x0, y0)
        ub, vb = self.to_world(x1, y1)
        u0, u1 = min(ua, ub), max(ua, ub)
        v0, v1 = min(va, vb), max(va, vb)
        if shadow:
            self._footprints.append(("rect", u0, u1, v0, v1, z0, z1))
        gu, gv = self._gu.ravel(), self._gv.ravel()
        t_in_u = u1 - gu
        t_in_v = v1 - gv
        t_in_z = np.full(gu.shape, z1 / 64.0)
        t_in = np.minimum(np.minimum(t_in_u, t_in_v), t_in_z)
        t_out = np.maximum(np.maximum(u0 - gu, v0 - gv), z0 / 64.0)
        active_idx = np.nonzero(t_in > t_out + 1.0e-9)[0]
        if active_idx.size == 0:
            return pid
        gua, gva = gu[active_idx], gv[active_idx]
        t = t_in[active_idx].copy()
        t_end = t_out[active_idx]
        entry = np.where(t_in_z[active_idx] <= np.minimum(t_in_u[active_idx], t_in_v[active_idx]), 2,
                         np.where(t_in_u[active_idx] <= t_in_v[active_idx], 0, 1))

        def field(tt, uu, vv):
            x, y = self.to_model(uu + tt, vv + tt)
            return fn(x, y, 64.0 * tt)

        alive = np.ones(t.shape, dtype=bool)
        hit = np.zeros(t.shape, dtype=bool)
        first = np.zeros(t.shape, dtype=bool)
        for step in range(int(steps)):
            if not alive.any():
                break
            d = field(t, gua, gva)
            close = alive & (d < 0.04)
            if step == 0:
                first = close.copy()
            hit |= close
            alive &= ~close
            t = np.where(alive, t - np.maximum(d, 0.02) / RAY_SPEED, t)
            alive &= t > t_end
        if not hit.any():
            return pid
        sel = np.nonzero(hit)[0]
        th, uh, vh = t[sel], gua[sel], gva[sel]
        eps = 0.6

        def grad(du, dv, dz):
            return (field(th + dz / 64.0, uh + du - dz / 64.0, vh + dv - dz / 64.0)
                    - field(th - dz / 64.0, uh - du + dz / 64.0, vh - dv + dz / 64.0))

        nu = grad(eps / Z_METRIC, 0.0, 0.0)
        nv = grad(0.0, eps / Z_METRIC, 0.0)
        nz = grad(0.0, 0.0, eps)
        ent = entry[sel]
        cut = first[sel]
        nu = np.where(cut, (ent == 0) * 1.0, nu)
        nv = np.where(cut, (ent == 1) * 1.0, nv)
        nz = np.where(cut, (ent == 2) * 1.0, nz)
        length = np.sqrt(nu ** 2 + nv ** 2 + nz ** 2)
        length = np.where(length > 1.0e-12, length, 1.0)
        nu, nv, nz = nu / length, nv / length, nz / length
        shape = self.alpha.shape

        def full(values, fill=0.0):
            out = np.full(gu.shape, fill, dtype=np.float64)
            out[active_idx[sel]] = values
            return out.reshape(shape)

        ok = np.zeros(gu.shape, dtype=bool)
        ok[active_idx[sel]] = True
        ok = ok.reshape(shape)
        t_full = full(th)
        u = self._gu + t_full
        v = self._gv + t_full
        z = 64.0 * t_full
        nu_f, nv_f, nz_f = full(nu), full(nv), full(nz, 1.0)
        light = nu_f * LIGHT_DIR[0] + nv_f * LIGHT_DIR[1] + nz_f * LIGHT_DIR[2]
        self._curved_put(ok, u, v, z, nu_f, nv_f, nz_f, light, ramp, rid, pid, tex, bands, dither, shade, SURFACE,
                         (min(x0, x1), min(y0, y1), z0), (abs(x1 - x0) * 64.0, float(z1 - z0)))
        return pid

    def soft_box(self, x0, x1, y0, y1, z0, z1, radius, ramp, **kwargs):
        """Caja con todas las aristas redondeadas (radius en px): cojines, asientos, sofás."""
        fn = sdf_round_box(x0, x1, y0, y1, z0, z1, radius)
        return self.sdf(fn, (x0, x1, y0, y1, z0, z1), ramp, **kwargs)

    def capsule(self, p0, p1, radius, ramp, **kwargs):
        """Cápsula de p0 a p1 = (x, y, z), radio en px: brazos, patas, tubos."""
        fn = sdf_capsule(p0, p1, radius)
        pad = radius / Z_METRIC
        bounds = (min(p0[0], p1[0]) - pad, max(p0[0], p1[0]) + pad, min(p0[1], p1[1]) - pad,
                  max(p0[1], p1[1]) + pad, min(p0[2], p1[2]) - radius, max(p0[2], p1[2]) + radius)
        return self.sdf(fn, bounds, ramp, **kwargs)

    # ------------------------------------------------------------------ sello dibujado a mano

    def stamp(self, pattern, x, y, z, ramp, hot=None, depth_bias=0.0, name=None, part=None, outline=True,
              side=SIDE_CURVED):
        """Pega un dibujo a mano (filas de índices, −1 = transparente). El pixel hot (por defecto el centro
        de la fila de abajo) cae en (x, y, z) y todo toma esa profundidad + depth_bias. No gira con el modelo."""
        grid = np.array(pattern, dtype=np.int16)
        if grid.ndim != 2:
            raise ValueError("pattern debe ser una lista de filas del mismo largo")
        rows, cols = grid.shape
        if hot is None:
            hot = (cols // 2, rows - 1)
        px, py = self.project(x, y, z)
        left = int(math.floor(px)) - hot[0] + self.pad
        top = int(math.floor(py)) - hot[1] + self.pad
        pid = self._new_part(name, part, outline, False)
        rid = self._ramp_id(ramp)
        hh, ww = self.alpha.shape
        mask = np.zeros((hh, ww), dtype=bool)
        index = np.zeros((hh, ww), dtype=np.int16)
        y0, y1 = max(top, 0), min(top + rows, hh)
        x0, x1 = max(left, 0), min(left + cols, ww)
        if y0 >= y1 or x0 >= x1:
            self.clipped = True
            return pid
        if (y1 - y0, x1 - x0) != (rows, cols):
            self.clipped = True
        sub = grid[y0 - top:y1 - top, x0 - left:x1 - left]
        mask[y0:y1, x0:x1] = sub >= 0
        index[y0:y1, x0:x1] = np.maximum(sub, 0)
        u, v = self.to_world(x, y)
        depth = np.full((hh, ww), u + v + z / 64.0 + depth_bias)
        self._put(mask, depth, index, pid, SURFACE, side, rid, u, v, z,
                  (self.X - (left - self.pad)).astype(np.float64), (self.Y - (top - self.pad)).astype(np.float64))
        return pid

    # ------------------------------------------------------------------ selección y retoque

    def select(self, part=None, face=None, side=None):
        """Máscara de pixeles visibles por pieza (id, nombre o lista), cara del modelo y/o lado de pantalla."""
        mask = self.alpha.copy()
        if part is not None:
            mask &= np.isin(self.part, self._part_ids(part))
        if face is not None:
            mask &= self.face == FACE_CODES[face]
        if side is not None:
            code = {v: k for k, v in SIDE_NAMES.items()}[side]
            mask &= self.side == code
        return mask

    def paint(self, mask, index, ramp=None):
        """Cambia el índice (y la rampa) de los pixeles visibles de mask, p. ej.
        c.paint(c.select(part='body', face=iso.FRONT) & (c.b > 10), pal.DEEP). Deja de contar como cara lisa."""
        m = mask & self.alpha
        self.shade[m] = np.broadcast_to(np.asarray(index, dtype=np.int16), m.shape)[m]
        if ramp is not None:
            self.ramp_id[m] = self._ramp_id(ramp)
        self.flat[m] = False
        self._smooth[m] = False
        self.result = None
        return m

    def no_outline(self, mask):
        """Marca pixeles sin contorno de silueta (empalmes, bordes contra el piso)."""
        self._no_outline |= mask
        self.result = None

    def no_finish(self, mask):
        """Marca pixeles sin ningún acabado (contorno, brillo, aristas ni sombra de contacto)."""
        self._no_finish |= mask
        self.result = None

    def open_ends(self, start=True, end=True, margin=2.5):
        """Deja sin acabado los extremos en x de una pieza (margin en px), para piezas en fila; las
        paredes no lo necesitan."""
        x, _y = self.to_model(self.u, self.v)
        along = x * 64.0
        if start:
            self.no_finish(self.alpha & (along < margin))
        if end:
            self.no_finish(self.alpha & (along > 64.0 - margin))

    # ------------------------------------------------------------------ acabado

    def _buffers(self):
        return {"alpha": self.alpha, "fid": self.fid, "part": self.part, "depth": self.depth, "side": self.side,
                "shade": self.shade, "ramp": self.ramp_id, "no_outline": self._no_outline,
                "no_finish": self._no_finish, "smooth": self._smooth, "z": self.z}

    def _repeated_buffers(self):
        """Búferes con las copias vecinas (self.repeat) compuestas por profundidad.
        Devuelve (búferes, margen y, margen x, máscara de lo propio)."""
        my = max(abs(int(r[1])) for r in self.repeat)
        mx = max(abs(int(r[0])) for r in self.repeat)
        fills = {"alpha": False, "fid": -1, "part": -1, "depth": _DEPTH_EMPTY, "side": 0, "shade": 0,
                 "ramp": -1, "no_outline": False, "no_finish": False, "smooth": False, "z": 0.0}
        base = {}
        for key, arr in self._buffers().items():
            base[key] = np.pad(arr, ((my, my), (mx, mx)), mode="constant", constant_values=fills[key])
        out = dict((key, arr.copy()) for key, arr in base.items())
        own = base["alpha"].copy()
        for dx, dy, ddepth in self.repeat:
            moved = dict((key, _shift(arr, -int(dy), -int(dx), fills[key])) for key, arr in base.items())
            depth = np.where(moved["alpha"], moved["depth"] + ddepth, _DEPTH_EMPTY)
            win = moved["alpha"] & (depth > out["depth"])
            for key in out:
                out[key][win] = depth[win] if key == "depth" else moved[key][win]
            own &= ~win
        return out, my, mx, own

    @staticmethod
    def _edges_from(b, gap=0.045, occlusion_gap=0.04):
        a = b["alpha"]
        fid, part, depth, side = b["fid"], b["part"], b["depth"], b["side"]
        up_a, down_a = _shift(a, -1, 0, False), _shift(a, 1, 0, False)
        left_a, right_a = _shift(a, 0, -1, False), _shift(a, 0, 1, False)
        sil = a & ~(up_a & down_a & left_a & right_a)
        up_fid, up_depth = _shift(fid, -1, 0, -1), _shift(depth, -1, 0, _DEPTH_EMPTY)
        left_depth = _shift(depth, 0, -1, _DEPTH_EMPTY)
        up_part, left_part = _shift(part, -1, 0, -1), _shift(part, 0, -1, -1)
        top = a & (side == SIDE_TOP)
        exposed_up = (~up_a) | ((up_fid != fid) & (up_depth < depth - gap))
        upper = top & exposed_up
        l2_fid, l2_depth = _shift(fid, 0, -2, -1), _shift(depth, 0, -2, _DEPTH_EMPTY)
        r2_fid, r2_depth = _shift(fid, 0, 2, -1), _shift(depth, 0, 2, _DEPTH_EMPTY)
        l2_out = (l2_fid != fid) & (l2_depth < depth - gap * 0.5)
        r2_out = (r2_fid != fid) & (r2_depth < depth - gap * 0.5)
        upper_left = upper & l2_out
        upper_right = upper & r2_out & ~l2_out
        down_part, down_side = _shift(part, 1, 0, -1), _shift(side, 1, 0, 0)
        right_part, right_side = _shift(part, 0, 1, -1), _shift(side, 0, 1, 0)
        crease_left = top & (down_part == part) & (down_side == SIDE_LEFT)
        crease_right = top & (down_part == part) & (down_side == SIDE_RIGHT)
        crease_vertical = a & (side == SIDE_LEFT) & (right_part == part) & (right_side == SIDE_RIGHT)
        occluded_raw = a & ((up_a & (up_part != part) & (up_depth > depth + occlusion_gap))
                            | (left_a & (left_part != part) & (left_depth > depth + occlusion_gap)))
        # Junto a una arista 2:1 «\» el vecino izquierdo daría una línea punteada: ahí no cae sombra.
        occluded = _drop_isolated(occluded_raw)
        up_side = _shift(side, -1, 0, 0)
        contact = top & up_a & (up_part != part) & (up_side != SIDE_TOP) & (up_side != SIDE_NONE) & ~occluded_raw
        contact = _drop_isolated(contact | occluded) & contact
        front_left = _drop_isolated(a & left_a & (left_part != part) & (left_depth < depth - occlusion_gap))
        # front: borde contra otra pieza; lo lleva la más cercana o, a igual profundidad, la agregada después.
        front = np.zeros(a.shape, dtype=bool)
        for dy, dx in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            n_a = _shift(a, dy, dx, False)
            n_part = _shift(part, dy, dx, -1)
            n_depth = _shift(depth, dy, dx, _DEPTH_EMPTY)
            nearer = n_depth < depth - occlusion_gap
            touching = (np.abs(n_depth - depth) <= occlusion_gap) & (part > n_part)
            front |= a & n_a & (n_part != part) & (nearer | touching)
        front = _drop_isolated(front)
        return {"silhouette": sil, "upper": upper, "upper_left": upper_left, "upper_right": upper_right,
                "crease_left": crease_left, "crease_right": crease_right, "crease_vertical": crease_vertical,
                "occluded": occluded, "contact": contact, "front_left": front_left, "front": front}

    def edges(self, gap=0.045, occlusion_gap=0.04):
        """Máscaras de borde de los búferes (sin los vecinos de pared):
          silhouette       opaco con vecino transparente
          upper            arriba con su arista de arriba expuesta; upper_left / upper_right por lado
          crease_left      arriba justo encima de la cara izquierda de la misma pieza; crease_right ídem
          crease_vertical  cara izquierda pegada a la derecha de la misma pieza
          occluded         con otra pieza más cerca arriba o a la izquierda
          contact          arriba justo debajo de la base de otra pieza apoyada
          front_left       más cercano que su vecino izquierdo de otra pieza; front, que algún vecino
        """
        return self._edges_from(self._buffers(), gap, occlusion_gap)

    def _corner_cut(self, b):
        """Recorta 1 px las puntas izquierda y derecha de las caras de arriba, donde la arista 2:1 se
        junta con la vertical de la silueta."""
        a = b["alpha"]
        part = b["part"]

        def empty(dy, dx):
            return ~_shift(a, dy, dx, False)

        tip = a & empty(-1, 0) & ((empty(0, -1) & empty(-1, -1) & empty(1, -1))
                                  | (empty(0, 1) & empty(-1, 1) & empty(1, 1)))
        near_top = (b["side"] == SIDE_TOP) & a
        near = near_top.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy or dx:
                    near |= _shift(near_top, dy, dx, False) & (_shift(part, dy, dx, -1) == part)
        return tip & near & ~b["no_finish"] & ~b["no_outline"]

    def _shade_from(self, b, options):
        """(índices finales, alfa) a partir de unos búferes (propios o extendidos de una pared)."""
        o = options
        outline, highlight, crease, occlusion = o["outline"], o["highlight"], o["crease"], o["occlusion"]
        inner_outline, outline_index, line_index = o["inner_outline"], o["outline_index"], o["line_index"]
        if o["corners"]:
            b = dict(b)
            b["alpha"] = b["alpha"] & ~self._corner_cut(b)
        a = b["alpha"]
        side, fid = b["side"], b["fid"]
        shade = _despeckle(b["shade"], b["part"], a & b["smooth"])
        e = self._edges_from(b)
        if occlusion:
            shade = np.where(e["occluded"] | e["contact"], pal.darker(shade), shade)
        default_rim = inner_outline if isinstance(inner_outline, str) else ("left" if inner_outline else "none")
        rims = [p["rim"] or default_rim for p in self.parts] + ["none"]
        part_or_none = np.where(a, b["part"], len(self.parts))
        rim_of = np.array(rims)[part_or_none]
        m = (rim_of == "left") & e["front_left"] & (side != SIDE_TOP)
        m |= (rim_of == "soft") & e["front"]
        # Arista superior derecha sobre otra cara del mismo tono (respaldo ante asiento): un paso de sombra.
        same_behind = (_shift(b["ramp"], -1, 0, -1) == b["ramp"]) & (_shift(b["shade"], -1, 0, -1) == b["shade"])
        m |= (rim_of != "none") & (rim_of != "line") & e["upper_right"] & _shift(a, -1, 0, False) & same_behind
        shade = np.where(m, pal.darker(shade), shade)
        # 'line': línea DEEP de 1 px donde una pieza tapa a otra del mismo sprite.
        line = (rim_of == "line") & e["front"]
        rim_full = (rim_of == "full") & e["front"]
        if crease == "light":
            # Brillo LIGHT de 1 px en las aristas que dan a la luz.
            shade = np.where(e["crease_left"] | e["crease_right"] | e["crease_vertical"], pal.LIGHT, shade)
        elif crease:
            shade = np.where(e["crease_left"] | e["crease_vertical"], pal.lighter(shade), shade)
        shade = np.where(line & ~e["silhouette"], line_index, shade)
        part_outline = np.array([p["outline"] for p in self.parts] + [True], dtype=bool)
        sil = e["silhouette"] & part_outline[part_or_none] & ~b["no_outline"]
        if o["ground_outline"] is not None and int(o["ground_outline"]) == 0:
            # Sin contorno donde la silueta da contra el piso (paredes).
            down_a = _shift(a, 1, 0, False)
            sil = sil & ~(~down_a & (side != SIDE_TOP) & (b["z"] <= GROUND_Z))
        elif o["ground_outline"] and int(o["ground_outline"]) > 1:
            # Contorno más grueso contra el piso: pixel de abajo de una cara lateral en z = 0 y los n − 1 de encima.
            down_a = _shift(a, 1, 0, False)
            ground = sil & ~down_a & (side != SIDE_TOP) & (b["z"] <= GROUND_Z)
            thick = ground.copy()
            grow = ground
            for _ in range(int(o["ground_outline"]) - 1):
                grow = _shift(grow, 1, 0, False) & a & (_shift(b["part"], 1, 0, -1) == b["part"]) & (side != SIDE_TOP)
                thick |= grow
            sil = sil | (thick & part_outline[part_or_none] & ~b["no_outline"])
        if highlight == "edge":
            lit = e["upper_left"]
            shade = np.where(lit, pal.LIGHT, shade)
            sil = sil & ~lit
        if outline:
            shade = np.where(sil, outline_index, shade)
        shade = np.where(rim_full, outline_index, shade)
        sil = sil | rim_full
        if highlight in ("inner", "upper"):
            # Arista con contorno: el brillo va una línea más adentro; sin contorno, en la arista.
            edge = e["upper_left"] if highlight == "inner" else e["upper"]
            drawn = sil if outline else rim_full
            covered = edge & drawn
            below = _shift(covered, -1, 0, False) & (_shift(fid, -1, 0, -1) == fid)
            below &= a & (side == SIDE_TOP) & ~drawn & ~e["occluded"]
            shade = np.where(below | (edge & ~drawn), pal.LIGHT, shade)
        return np.where(b["no_finish"], b["shade"], shade), a

    def finish(self, outline=None, highlight=None, crease=None, occlusion=None, inner_outline=None,
               outline_index=None, style=None, ground_outline=None, corners=None, line_index=None):
        """Aplica el acabado y devuelve la imagen RGBA. style = preset ('salvaje' por defecto o 'classic');
        cada opción explícita lo cambia.

        outline        contorno de 1 px en la silueta (outline_index)
        ground_outline grosor del contorno contra el piso (2 en 'salvaje', 0 = sin contorno)
        highlight      brillo en la arista superior izquierda: 'inner', 'edge', 'upper' (las dos) o None
        crease         'light' = brillo en las aristas que dan a la luz; True = un paso más claro; False = nada
        occlusion      oscurece un paso bajo otra pieza más cercana y en la línea de contacto
        inner_outline  borde donde tapa a otra pieza: 'line', True/'left', 'soft', 'full' o False/'none'
                       (por pieza con style_part(rim=…))
        corners        recorta 1 px las puntas de las caras de arriba (no en lienzos planos)
        En paredes se calcula con los vecinos puestos. Se puede volver a llamar con otras opciones.
        """
        given = {"outline": outline, "highlight": highlight, "crease": crease, "occlusion": occlusion,
                 "inner_outline": inner_outline, "outline_index": outline_index, "ground_outline": ground_outline,
                 "corners": corners, "line_index": line_index}
        style = style or DEFAULT_STYLE
        if style not in STYLES:
            raise ValueError("estilo de acabado desconocido: %r (hay: %s)" % (style, ", ".join(sorted(STYLES))))
        options = dict(STYLES[style])
        for key, value in given.items():
            if value is not None:
                options[key] = value
        if self.extra_meta.get("flat"):
            options["corners"] = False
        # highlight=None no se distingue de «no pasado»: usar highlight=False.
        if options["highlight"] is False:
            options["highlight"] = None
        self._finish_options = dict((k, v) for k, v in given.items() if v is not None)
        self._finish_options["style"] = style
        a = self.alpha
        shade, final_alpha = self._shade_from(self._buffers(), options)
        if self.repeat:
            ext, my, mx, own = self._repeated_buffers()
            ext_shade, ext_alpha = self._shade_from(ext, options)
            hh, ww = a.shape
            ext_shade = ext_shade[my:my + hh, mx:mx + ww]
            ext_alpha = ext_alpha[my:my + hh, mx:mx + ww]
            own = own[my:my + hh, mx:mx + ww]
            shade = np.where(own, ext_shade, shade)
            final_alpha = np.where(own, ext_alpha, final_alpha)
        a = a & final_alpha
        tables = [r.table() for r in self.ramps]
        rgba = np.zeros(a.shape + (4,), dtype=np.uint8)
        for rid, table in enumerate(tables):
            m = a & (self.ramp_id == rid)
            if m.any():
                rgba[m, :3] = table[np.clip(shade[m], 0, len(table) - 1)]
        rgba[..., 3] = np.where(a, 255, 0)
        p = self.pad
        inner = np.zeros(a.shape, dtype=bool)
        inner[p:p + self.height, p:p + self.width] = True
        if (a & ~inner).any():
            self.clipped = True
        self.final_shade = shade
        self.final_alpha = a
        self.result = Image.fromarray(rgba[p:p + self.height, p:p + self.width], "RGBA")
        return self.result

    @property
    def image(self):
        """La imagen terminada (llama a finish() con las últimas opciones si hace falta)."""
        if self.result is None:
            self.finish(**self._finish_options)
        return self.result

    def layer(self, parts=None, mask=None):
        """Imagen terminada solo con los pixeles visibles de unas piezas y/o una máscara (capas aparte)."""
        image = np.array(self.image)
        keep = np.ones(self.alpha.shape, dtype=bool)
        if parts is not None:
            keep &= np.isin(self.part, self._part_ids(parts))
        if mask is not None:
            keep &= mask
        image[~self.crop(keep & self.alpha)] = 0
        return Image.fromarray(image, "RGBA")

    def crop(self, arr):
        """Recorta un búfer interno al tamaño del lienzo final."""
        p = self.pad
        return arr[p:p + self.height, p:p + self.width]

    # ------------------------------------------------------------------ sombra en el piso

    def ground_shadow(self, shift=(0.10, 0.03), color=(26, 28, 38), clip=True):
        """Sombra para *_shadow.png: la planta corrida abajo-derecha (shift en casillas por cada 64 px de
        alto), de un solo tono opaco y recortada a la planta (clip)."""
        gu, gv = self._gu, self._gv
        mask = np.zeros(self.alpha.shape, dtype=bool)
        steps = 6
        for item in self._footprints:
            kind = item[0]
            top = item[-1]
            bottom = item[-2]
            for i in range(steps + 1):
                zz = bottom + (top - bottom) * i / float(steps)
                su = shift[0] * zz / 64.0
                sv = shift[1] * zz / 64.0
                if kind == "rect":
                    _k, u0, u1, v0, v1 = item[:5]
                    mask |= (gu >= u0 + su) & (gu < u1 + su) & (gv >= v0 + sv) & (gv < v1 + sv)
                elif kind == "disc":
                    _k, cu, cv, rad = item[:4]
                    mask |= (gu - cu - su) ** 2 + (gv - cv - sv) ** 2 <= rad * rad
                else:
                    _k, cu, cv, ru, rv = item[:5]
                    mask |= ((gu - cu - su) / ru) ** 2 + ((gv - cv - sv) / rv) ** 2 <= 1.0
        if clip:
            w, d = self.world_size
            mask &= (gu >= 0) & (gu < max(w, 1.0e-9)) & (gv >= 0) & (gv < max(d, 1.0e-9))
        rgba = np.zeros(mask.shape + (4,), dtype=np.uint8)
        rgba[mask, :3] = pal.hex_to_rgb(color)
        rgba[mask, 3] = 255
        p = self.pad
        return Image.fromarray(rgba[p:p + self.height, p:p + self.width], "RGBA")

    # ------------------------------------------------------------------ datos para el manifiesto

    def meta(self):
        """Datos del sprite para el manifiesto (lienzo, apoyo, planta, caras lisas, recorte)."""
        image = self.image
        data = {
            "kind": self.kind,
            "canvas": [self.width, self.height],
            "anchor": [self.anchor[0], self.anchor[1]] if self.anchor is not None else None,
            "footprint": [self.world_size[0], self.world_size[1]],
            "rotation": self.rotation,
            "clipped": bool(self.clipped),
            "curved": bool(self.curved),
            "off_grid": list(self.off_grid),
            "flat_faces": self.flat_faces(),
        }
        if self.model_height is not None:
            data["height"] = self.model_height
        if self.min_z is not None:
            data["min_z"] = round(self.min_z, 2)
        arr = np.array(image)
        opaque = arr[..., 3] > 0
        data["colors"] = int(len(np.unique(arr[opaque][:, :3], axis=0))) if opaque.any() else 0
        data.update(self.extra_meta)
        return data

    def flat_faces(self):
        """Por rampa y lado: pixeles en el tono exacto en la imagen final, visibles ('<lado>_total') y
        exactos antes del acabado ('<lado>_plain'), para check.py. No cuenta lo pintado ni flat=False."""
        self.image
        out = []
        for rid, ramp in enumerate(self.ramps):
            if ramp.base_hex is None or len(ramp) < pal.STEP_COUNT:
                continue
            entry = {"base": ramp.base_hex}
            if getattr(ramp, "declared", False):
                # Caras declaradas a mano (rampas de STYLE.md): check.py exige estos tonos.
                entry["declared"] = True
                entry["faces"] = ramp.faces()
            total = 0
            for side, name, index in ((SIDE_TOP, "top", pal.BASE), (SIDE_LEFT, "left", pal.LEFT),
                                      (SIDE_RIGHT, "right", pal.RIGHT)):
                face = self.final_alpha & self.flat & (self.ramp_id == rid) & (self.side == side)
                count = int(self.crop(face & (self.final_shade == index)).sum())
                entry[name] = count
                entry[name + "_total"] = int(self.crop(face).sum())
                # Sin contar el acabado: lo que la textura dejó en el tono exacto de la cara.
                entry[name + "_plain"] = int(self.crop(face & (self.shade == index)).sum())
                total += entry[name + "_total"]
            if total > 0:
                out.append(entry)
        return out


DESK_TOP = 44  # z de la superficie de un escritorio (22 px del mundo): base de computadoras
WALL_ITEM_BASE = 48  # z de la base de un objeto de pared (24 px del mundo)


# ---------------------------------------------------------------------- campos de distancia

def sdf_round_box(x0, x1, y0, y1, z0, z1, radius):
    """Caja de (x0, y0, z0) a (x1, y1, z1) con todas las aristas redondeadas `radius` px."""
    cx, cy, cz = (x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0
    hx = abs(x1 - x0) / 2.0 * Z_METRIC
    hy = abs(y1 - y0) / 2.0 * Z_METRIC
    hz = abs(z1 - z0) / 2.0
    radius = min(float(radius), hx, hy, hz)

    def fn(x, y, z):
        qx = np.abs((x - cx) * Z_METRIC) - (hx - radius)
        qy = np.abs((y - cy) * Z_METRIC) - (hy - radius)
        qz = np.abs(z - cz) - (hz - radius)
        outside = np.sqrt(np.maximum(qx, 0.0) ** 2 + np.maximum(qy, 0.0) ** 2 + np.maximum(qz, 0.0) ** 2)
        inside = np.minimum(np.maximum(qx, np.maximum(qy, qz)), 0.0)
        return outside + inside - radius

    return fn


def sdf_capsule(p0, p1, radius):
    """Tubo de puntas redondas de p0 a p1 = (x, y, z), radio en px."""
    ax, ay, az = p0[0] * Z_METRIC, p0[1] * Z_METRIC, float(p0[2])
    bx, by, bz = p1[0] * Z_METRIC, p1[1] * Z_METRIC, float(p1[2])
    dx, dy, dz = bx - ax, by - ay, bz - az
    length2 = max(dx * dx + dy * dy + dz * dz, 1.0e-12)

    def fn(x, y, z):
        px, py, pz = x * Z_METRIC - ax, y * Z_METRIC - ay, z - az
        h = np.clip((px * dx + py * dy + pz * dz) / length2, 0.0, 1.0)
        return np.sqrt((px - dx * h) ** 2 + (py - dy * h) ** 2 + (pz - dz * h) ** 2) - radius

    return fn


def sdf_ellipsoid(cx, cy, cz, rx, ry, rz):
    """Elipsoide (aproximado) con radios rx, ry en casillas y rz en px."""
    ax, ay, az = rx * Z_METRIC, ry * Z_METRIC, float(rz)
    scale = min(ax, ay, az)

    def fn(x, y, z):
        k = np.sqrt(((x - cx) * Z_METRIC / ax) ** 2 + ((y - cy) * Z_METRIC / ay) ** 2 + ((z - cz) / az) ** 2)
        return (k - 1.0) * scale

    return fn


def sdf_torus(cx, cy, cz, radius, tube):
    """Aro horizontal: radio del aro en casillas, grosor del tubo (radio) en px."""
    big = radius * Z_METRIC

    def fn(x, y, z):
        ring = np.sqrt(((x - cx) * Z_METRIC) ** 2 + ((y - cy) * Z_METRIC) ** 2) - big
        return np.sqrt(ring ** 2 + (z - cz) ** 2) - tube

    return fn


def sdf_union(*fns):
    def fn(x, y, z):
        out = fns[0](x, y, z)
        for other in fns[1:]:
            out = np.minimum(out, other(x, y, z))
        return out

    return fn


def sdf_smooth_union(fn_a, fn_b, blend=4.0):
    """Unión con la junta suavizada (blend en px): cuerpos orgánicos, cojines pegados."""

    def fn(x, y, z):
        da, db = fn_a(x, y, z), fn_b(x, y, z)
        h = np.clip(0.5 + 0.5 * (db - da) / blend, 0.0, 1.0)
        return db + (da - db) * h - blend * h * (1.0 - h)

    return fn


def sdf_subtract(fn_a, fn_b):
    """fn_a menos fn_b (huecos)."""

    def fn(x, y, z):
        return np.maximum(fn_a(x, y, z), -fn_b(x, y, z))

    return fn


def sdf_intersect(fn_a, fn_b):
    def fn(x, y, z):
        return np.maximum(fn_a(x, y, z), fn_b(x, y, z))

    return fn


# ---------------------------------------------------------------------- guardar y manifiesto

_REGISTRY = []


def guess_kind(name):
    """Tipo de sprite según el nombre de archivo de la guía (None si no se reconoce)."""
    stem = name[:-4] if name.endswith(".png") else name
    if stem.endswith("_shadow"):
        return "shadow"
    if stem.startswith("floor_") or stem.startswith("ground_"):
        return "floor"
    for suffix in ("_tall_x", "_tall_y", "_low_x", "_low_y"):
        if stem.endswith(suffix):
            return "wall"
    if stem.startswith("tree_"):
        return "tree"
    if stem.startswith("dirt_"):
        return "overlay"
    if stem.startswith("bush_") or stem.startswith("hedge_"):
        return "bush"
    return None


def reset_registry():
    """Vacía la lista de sprites guardados (generate.py lo llama antes de cada módulo)."""
    del _REGISTRY[:]


def registry():
    return list(_REGISTRY)


def save(sprite, out_dir, name, **meta):
    """Guarda un sprite (Canvas o imagen PIL) como PNG RGBA y lo anota para el manifiesto. Devuelve la ruta.

    name  nombre de la guía, con o sin .png ('desk_simple_r1')
    meta  datos extra; con una imagen PIL pasar kind ('floor', 'shadow'…). Con un Canvas salen solos.
    """
    if not name.endswith(".png"):
        name = name + ".png"
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    entry = {"file": name}
    if isinstance(sprite, Canvas):
        image = sprite.image
        entry.update(sprite.meta())
    else:
        image = sprite
        if image.mode != "RGBA":
            image = image.convert("RGBA")
        entry.update({"canvas": [image.size[0], image.size[1]]})
    entry.update(meta)
    if "kind" not in entry:
        kind = guess_kind(name)
        if kind is not None:
            entry["kind"] = kind
    path = os.path.join(out_dir, name)
    image.save(path)
    for index, known in enumerate(_REGISTRY):
        if known["file"] == name:
            _REGISTRY[index] = entry
            break
    else:
        _REGISTRY.append(entry)
    return path


def write_manifest(out_dir, group):
    """Escribe manifest_<group>.json con lo guardado desde reset_registry()."""
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    path = os.path.join(out_dir, "manifest_%s.json" % group)
    data = {"group": group, "sprites": sorted(_REGISTRY, key=lambda e: e["file"])}
    temp = path + ".tmp%d" % os.getpid()
    with open(temp, "w") as handle:
        json.dump(data, handle, indent=1, sort_keys=True)
        handle.write("\n")
    os.replace(temp, path)
    return path


def load_json(relative_path):
    """Lee un JSON del proyecto, p. ej. load_json('data/furniture.json')."""
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    with open(os.path.join(root, relative_path), "r") as handle:
        return json.load(handle)
