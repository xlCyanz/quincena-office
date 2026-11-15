# Personaje del piloto (docs/sprites_128.md, sección 9; estilo de tools/sprites/STYLE.md): empleado de
# oficina en 4 direcciones, de pie y sentado.
#
#   character_stand_r0 … r3      lienzo 128×128, pies en (64, 112), unos 100 px de alto
#   character_stand_r1_v1, _v2   la misma pose con otras paletas (piel, pelo, camisa, pantalón)
#   character_stand_shadow       sombra de los pies, un solo tono (el juego la pone con transparencia)
#   character_sit_r0 … r3        sentado, manos al frente como tecleando: la cadera (lo que apoya en el
#                                asiento) a SIT_SEAT_Z = 24 px sobre el piso, en la vertical del apoyo
#                                (64, 112) = centro de la casilla de la silla; los pies van adelante
#   character_stand_r1_s80       de pie dibujado a tamaño final (BODY_SCALE 0.8 del juego, ~80 px):
#                                el mismo modelo con SCALE 0.8 y los detalles a mano en su versión chica
#   character_layers/            una imagen por capa y dirección (puestas en el orden de LAYER_ORDER dan
#                                el sprite exacto), el cuerpo sin pelo (*_bald) para otro peinado y
#                                layers.json con los colores de cada tono por Look (no son sprites sueltos)
#   _sheets/character.png        hoja de contacto ×3 con escenas de pie y sentado sobre la silla
#                                (no es arte del juego)
#
# Estilo (STYLE.md): contorno casi negro del tono de cada capa, 2 px bajo las suelas; línea interior
# oscura de 1 px (DEEP) donde una pieza tapa a otra de la misma capa (el brazo sobre el torso);
# colores saturados con base / −25 % / −40 % exactos y un brillo; brazos abiertos con el codo
# doblado para que no se peguen al cuerpo.
#
# Cómo está hecho
# - El cuerpo es un modelo 3D chico hecho con campos de distancia (iso.sdf), escrito UNA vez en
#   «px del cuerpo» (lat = a la derecha del personaje, fwd = hacia su frente, z = alto). El lienzo
#   lo gira a las 4 direcciones y la luz se rehace sola en cada una.
# - El cuerpo entero va girado TURN (18.4°) hacia la cámara respecto del eje de la casilla: así la
#   línea de los hombros, el cinturón, las manos y los ojos siguen todos la MISMA proyección, una
#   escalera de 4 px por 1 (con el 2:1 completo un brazo cuelga 13 px más abajo que el otro y la
#   cabeza se ve ladeada; antes solo la cara se corregía y no coincidía con el cuerpo).
# - El motor solo da la forma y la luz de cada pixel. El sombreado (bandas con los tonos exactos
#   base / −25 % / −40 %), las líneas entre piezas, el contorno y los detalles se pintan aquí,
#   para controlar cada pixel: sin manchas de menos de 3 px, sin puntas de 1 px en la silueta.
# - La cara, el cuello de la camisa, la corbata, la hebilla y los pulgares se dibujan a mano en
#   pantalla (a este tamaño cada pixel cuenta), colocados con la proyección del modelo. Las
#   medidas del cuerpo dependen de la pose (Pose: de pie o sentado) y se escalan con Figure.k.
# - Capas: piel, pelo, camisa, corbata, pantalón, zapatos y cara, cada una con su rampa (Look).
#   Cambiar de empleado es cambiar los colores: los índices de tono de cada pixel no cambian
#   (build lo comprueba). build también mide lo que check.py no mide (pies, contorno, pixeles
#   sueltos, puntas, colores por capa, sombra) y falla si algo no se cumple.
import json
import math
import os

import numpy as np
from PIL import Image

import iso
import palette as pal
import sheet

PX = 1.0 / iso.Z_METRIC  # 1 px del cuerpo en casillas
CENTER = 0.5  # el personaje se para en el centro de la casilla
# Giro hacia la cámara: la pendiente en pantalla de una línea lateral es tan(45° − giro) / 2.
# Con 45° − atan(1/2) queda en 1/4: escalera limpia de 4 px por 1.
TURN = math.radians(45.0) - math.atan(0.5)

# Alturas del modelo en px de sprite (el piso es 0; la coronilla queda hacia 98).
BELT_Z = 36.0  # borde de abajo del cinturón
BELT_H = 3.0
CUFF_Z = 41.0  # muñeca
NECK_Z = 65.0  # base del cuello
HEAD_Z = 82.0  # centro de la cabeza
SIT_SEAT_Z = 24.0  # sentado: donde la cadera apoya en el asiento (guía, sección 9)
SIT_DROP = 4.0  # sentado, el torso y la cabeza quedan 4 px más abajo que de pie
SMALL_SCALE = 0.8  # BODY_SCALE del juego (OfficeCharacter): el personaje a tamaño final


class Pose(object):
    """Medidas de una pose en px del cuerpo. arm = (hombro, codo, muñeca, centro de la mano,
    radios de la mano) con lat hacia afuera (se espeja en el brazo izquierdo)."""

    def __init__(self, name, sit, arm, height):
        self.name = name
        self.sit = sit
        drop = SIT_DROP if sit else 0.0
        self.belt_z = BELT_Z - drop
        self.neck_z = NECK_Z - drop
        self.head_z = HEAD_Z - drop
        self.arm = arm
        self.height = height  # alto esperado sobre los pies (mínimo, máximo) a escala 1

    def arm_points(self, sign):
        return [(sign * p[0], p[1], p[2]) for p in self.arm[:4]]


# De pie: brazos abiertos hacia afuera y el codo apenas doblado hacia adelante; entre la mano y
# la cadera queda aire (el brazo no se pega al cuerpo).
STAND = Pose("stand", False, ((12.0, 0.0, 61.0), (14.4, 0.4, 51.0), (16.2, 2.4, CUFF_Z + 2.0),
                              (16.8, 3.0, CUFF_Z - 3.0), (3.5, 3.5, 4.4)), (96, 104))
# Sentado: el brazo baja junto al cuerpo hasta el codo y el antebrazo va al frente, casi
# horizontal, con las manos planas (palmas abajo) como sobre un teclado.
SIT = Pose("sit", True, ((12.0, 0.0, 57.0), (13.6, 1.0, 46.0), (9.6, 13.0, 45.0),
                         (8.6, 16.4, 44.6), (3.4, 4.0, 2.8)), (88, 98))

OUTLINE, DEEP, RIGHT, LEFT, BASE, LIGHT = pal.OUTLINE, pal.DEEP, pal.RIGHT, pal.LEFT, pal.BASE, pal.LIGHT

# Capas, de atrás hacia adelante para componerlas (LAYER_ORDER).
LAYER_ORDER = ("shoes", "pants", "shirt", "skin", "accent", "face", "hair")
LAYER_ID = dict((name, index) for index, name in enumerate(LAYER_ORDER))

# Bandas de luz por capa: (umbral mínimo de n·luz, tono), de más a menos luz. Los tonos son los
# exactos de la guía (base, −25 %, −40 %). Lo que mira a la izquierda queda en la base, lo que
# mira a la derecha en −25 % y lo que mira hacia abajo a la derecha (el canto que se aleja de la
# luz) en −40 %: con −40 % en todo lo que mira a la derecha el frente entero quedaría en sombra.
BANDS = {
    "shoes": ((0.72, LIGHT), (-9.0, BASE)),
    "pants": ((0.45, BASE), (-0.30, LEFT), (-9.0, RIGHT)),
    "shirt": ((0.20, BASE), (-0.40, LEFT), (-9.0, RIGHT)),
    "skin": ((-0.50, BASE), (-9.0, LEFT)),
    "hair": ((0.90, LIGHT), (-0.05, BASE), (-9.0, RIGHT)),
}

# Capas que se sombrean con la luz horizontal (Figure.horizontal_light).
FLAT_LIGHT = ("pants",)

SHADOW_COLOR = (26, 28, 38)  # el mismo tono de las sombras de los muebles
MIN_PATCH = 3  # una mancha de tono de menos pixeles se funde con lo de al lado


PLUM_HUE = 330.0 / 360.0  # el contorno corre al ciruela, como el borde de la «maqueta» (STYLE.md)


def layer_ramp(base, light=0.35, name=None):
    """Rampa corta de una capa, con el criterio de STYLE.md: contorno casi negro del mismo tono
    (base × 0.26, más saturado, corrido al ciruela: como 3c1300 para la madera df823d), línea
    interior DEEP (base × 0.5), −40 %, −25 % y base exactos de la guía y brillo cálido."""
    dark = pal.adjust(base, 0.26, 1.6, PLUM_HUE, 0.12, 0.30)
    deep = pal.adjust(base, 0.52, 1.25, PLUM_HUE, 0.06, 0.12)
    bright = pal.adjust(pal.lighten(base, light), 1.0, 0.95, pal.WARM_HUE, 0.10, 0.03)
    return pal.ramp(base, outline=dark, deep=deep, light=bright, shine=bright, name=name)


class Look(object):
    """Paletas de un empleado: una rampa por capa, a partir de un color cada una. Se crea una
    vez por variante (el lienzo distingue las rampas por objeto)."""

    def __init__(self, skin, hair, shirt, pants, shoes="4a3430", accent="c03d43"):
        self.skin = layer_ramp(skin, light=0.30, name="skin")
        self.hair = layer_ramp(hair, light=0.28, name="hair")
        self.shirt = layer_ramp(shirt, light=0.45, name="shirt")
        self.pants = layer_ramp(pants, light=0.30, name="pants")
        self.shoes = layer_ramp(shoes, light=0.40, name="shoes")
        self.accent = layer_ramp(accent, light=0.30, name="accent")
        self.face = pal.palette(["1e1420", "fbf6ee"], name="face")  # pupila y blanco del ojo

    def ramp(self, layer):
        return getattr(self, layer)


# Colores saturados y pocos tonos por capa (STYLE.md): camisa celeste con corbata roja (el rojo del
# tapizado c03d43), pantalón azul marino; las variantes cambian solo la paleta.
LOOKS = {
    "": Look(skin="f0b07a", hair="6e3418", shirt="62b2e4", pants="2f3a6e"),
    "_v1": Look(skin="9a5a34", hair="2a1a1e", shirt="45b58a", pants="6a4a32", accent="eda85d"),
    "_v2": Look(skin="f8d0a8", hair="df823d", shirt="d84a58", pants="35324a", accent="2f6fb8"),
}


# ---------------------------------------------------------------------- campos de distancia
# Todos en px del cuerpo: fn(lat, fwd, z) -> distancia con signo (negativa adentro).

def f_box(lat0, lat1, fwd0, fwd1, z0, z1, radius):
    """Caja con todas las aristas redondeadas `radius` px."""
    cx, cy, cz = (lat0 + lat1) / 2.0, (fwd0 + fwd1) / 2.0, (z0 + z1) / 2.0
    hx, hy, hz = (lat1 - lat0) / 2.0 - radius, (fwd1 - fwd0) / 2.0 - radius, (z1 - z0) / 2.0 - radius

    def fn(lat, fwd, z):
        qx, qy, qz = np.abs(lat - cx) - hx, np.abs(fwd - cy) - hy, np.abs(z - cz) - hz
        outside = np.sqrt(np.maximum(qx, 0.0) ** 2 + np.maximum(qy, 0.0) ** 2 + np.maximum(qz, 0.0) ** 2)
        return outside + np.minimum(np.maximum(qx, np.maximum(qy, qz)), 0.0) - radius

    return fn


def f_capsule(p0, p1, radius, radius_end=None):
    """Tubo de puntas redondas de p0 a p1 = (lat, fwd, z); radius_end = radio en p1 (afinado)."""
    ax, ay, az = [float(v) for v in p0]
    dx, dy, dz = p1[0] - ax, p1[1] - ay, p1[2] - az
    length2 = max(dx * dx + dy * dy + dz * dz, 1.0e-12)
    r1 = radius if radius_end is None else radius_end

    def fn(lat, fwd, z):
        px, py, pz = lat - ax, fwd - ay, z - az
        h = np.clip((px * dx + py * dy + pz * dz) / length2, 0.0, 1.0)
        return np.sqrt((px - dx * h) ** 2 + (py - dy * h) ** 2 + (pz - dz * h) ** 2) - (radius + (r1 - radius) * h)

    return fn


def f_ellipsoid(center, radii):
    """Elipsoide (distancia aproximada, buena cerca de la superficie)."""
    cx, cy, cz = center
    rx, ry, rz = radii

    def fn(lat, fwd, z):
        px, py, pz = lat - cx, fwd - cy, z - cz
        k0 = np.sqrt((px / rx) ** 2 + (py / ry) ** 2 + (pz / rz) ** 2)
        k1 = np.sqrt((px / rx ** 2) ** 2 + (py / ry ** 2) ** 2 + (pz / rz ** 2) ** 2)
        return np.where(k1 > 1.0e-9, k0 * (k0 - 1.0) / np.maximum(k1, 1.0e-9), -min(rx, ry, rz))

    return fn


def f_union(*fns):
    def fn(lat, fwd, z):
        out = fns[0](lat, fwd, z)
        for other in fns[1:]:
            out = np.minimum(out, other(lat, fwd, z))
        return out

    return fn


def f_blend(fn_a, fn_b, blend):
    """Unión con la junta suavizada `blend` px (una sola pieza, sin línea en la unión)."""

    def fn(lat, fwd, z):
        da, db = fn_a(lat, fwd, z), fn_b(lat, fwd, z)
        h = np.clip(0.5 + 0.5 * (db - da) / blend, 0.0, 1.0)
        return db + (da - db) * h - blend * h * (1.0 - h)

    return fn


def f_intersect(fn_a, fn_b):
    def fn(lat, fwd, z):
        return np.maximum(fn_a(lat, fwd, z), fn_b(lat, fwd, z))

    return fn


# ---------------------------------------------------------------------- utilidades de pixeles

MOVES4 = ((-1, 0), (1, 0), (0, -1), (0, 1))
MOVES8 = MOVES4 + ((-1, -1), (-1, 1), (1, -1), (1, 1))


def shifted(arr, dy, dx, fill):
    """out[y, x] = arr[y + dy, x + dx] (fill fuera del arreglo)."""
    out = np.full_like(arr, fill)
    h, w = arr.shape
    ys0, ys1 = max(-dy, 0), h - max(dy, 0)
    xs0, xs1 = max(-dx, 0), w - max(dx, 0)
    out[ys0:ys1, xs0:xs1] = arr[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx]
    return out


def neighbours(mask, moves=MOVES4):
    """Cuántos vecinos de cada pixel están en la máscara."""
    count = np.zeros(mask.shape, dtype=np.int16)
    for dy, dx in moves:
        count += shifted(mask, dy, dx, False)
    return count


def patches(key, mask):
    """Manchas (4 vecinos) de pixeles de mask con la misma clave. Devuelve (etiqueta por pixel,
    tamaño por etiqueta); la etiqueta −1 es «fuera de mask»."""
    label = np.full(key.shape, -1, dtype=np.int32)
    sizes = []
    h, w = key.shape
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if label[y0, x0] >= 0:
            continue
        current = len(sizes)
        value = key[y0, x0]
        stack = [(y0, x0)]
        label[y0, x0] = current
        size = 0
        while stack:
            y, x = stack.pop()
            size += 1
            for dy, dx in MOVES4:
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and label[ny, nx] < 0 and key[ny, nx] == value:
                    label[ny, nx] = current
                    stack.append((ny, nx))
        sizes.append(size)
    return label, np.array(sizes, dtype=np.int32)


# ---------------------------------------------------------------------- figura

class Figure(object):
    """Un lienzo de personaje más los búferes propios de este módulo:
      light, nz   n·luz y componente vertical de la normal de cada pixel (los da el motor)
      layer       capa de cada pixel (índice de LAYER_ORDER)
      keep        detalles dibujados a mano: no se funden con lo de al lado
      lat, fwd    coordenadas del cuerpo de cada pixel (después de measure())
    """

    def __init__(self, rotation, look, pose=None, scale=1.0):
        self.c = iso.Canvas.character(rotation)
        self.look = look
        self.pose = pose or STAND
        self.k = float(scale)  # px de sprite por px del cuerpo (0.8 = tamaño final del juego)
        shape = self.c.alpha.shape
        self.light = np.zeros(shape)
        self.nz = np.zeros(shape)
        self.layer = np.full(shape, -1, dtype=np.int16)
        self.keep = np.zeros(shape, dtype=bool)
        self.lat = np.zeros(shape)
        self.fwd = np.zeros(shape)
        self.zb = np.zeros(shape)  # alto del cuerpo (z / k) de cada pixel
        # Sentido del giro: el que acerca el frente (o la espalda) a la vertical de la pantalla.
        best = None
        for sign in (1.0, -1.0):
            self._set_turn(sign * TURN)
            score = abs(self.screen(0, 1, 0)[0] - self.screen(0, 0, 0)[0])
            if best is None or score < best[0]:
                best = (score, sign)
        self._set_turn(best[1] * TURN)
        zero = np.array(self.screen(0, 0, 0))
        self.lat_step = np.array(self.screen(1, 0, 0)) - zero  # 1 px a la derecha del personaje, en pantalla
        self.fwd_step = np.array(self.screen(0, 1, 0)) - zero  # 1 px hacia su frente
        self.front = self.fwd_step[1] > 0  # se le ve la cara
        self.toward = 1 if self.fwd_step[0] > 0 else -1  # hacia qué lado de la pantalla mira
        self.near = 1 if self.lat_step[1] > 0 else -1  # signo de lat del lado que queda más abajo (cerca)

    def _set_turn(self, angle):
        self.cos, self.sin = math.cos(angle), math.sin(angle)

    # ------------------------------------------------------------------ coordenadas

    def at(self, lat, fwd, z):
        """Punto del modelo (casillas, casillas, px) de un punto del cuerpo."""
        rl = lat * self.cos - fwd * self.sin
        rf = lat * self.sin + fwd * self.cos
        return (CENTER + rl * PX * self.k, CENTER - rf * PX * self.k, float(z) * self.k)

    def screen(self, lat, fwd, z):
        """Pixel del lienzo (con decimales) de un punto del cuerpo."""
        return self.c.project(*self.at(lat, fwd, z))

    def pixel(self, lat, fwd, z):
        x, y = self.screen(lat, fwd, z)
        return int(math.floor(x)), int(math.floor(y))

    def to_body(self, x, y):
        rl = (x - CENTER) / (PX * self.k)
        rf = (CENTER - y) / (PX * self.k)
        return rl * self.cos + rf * self.sin, -rl * self.sin + rf * self.cos

    # Vista canónica: el personaje mirando hacia la DERECHA de la pantalla (r1 de frente, r0 de
    # espaldas). Las otras dos direcciones son su espejo (x -> 127 − x): los dibujos a mano se
    # escriben una vez en la vista canónica y la luz se decide aparte, por el lado real.

    def flip(self, x):
        return x if self.toward > 0 else 127 - x

    def canon(self, lat, fwd, z):
        """Pixel canónico (enteros) de un punto del cuerpo."""
        x, y = self.screen(lat, fwd, z)
        if self.toward < 0:
            x = 128.0 - x
        return int(math.floor(x)), int(math.floor(y))

    def canon_x(self):
        """Columna canónica de cada pixel del lienzo."""
        return self.c.X if self.toward > 0 else 127 - self.c.X

    # ------------------------------------------------------------------ piezas

    def solid(self, name, layer, fn, box, margin=2.0):
        """Agrega una pieza: fn = campo en px del cuerpo, box = (lat0, lat1, fwd0, fwd1, z0, z1)
        que la contiene. Guarda la luz de sus pixeles visibles."""
        c = self.c
        got = {}

        def grab(ctx):
            got["light"] = np.array(ctx.light, dtype=np.float64)
            got["nz"] = np.array(ctx.nz, dtype=np.float64)
            return None

        k = self.k

        def field(x, y, z):
            lat, fwd = self.to_body(x, y)
            return fn(lat, fwd, z / k) * k  # distancia en px de sprite

        lat0, lat1, fwd0, fwd1, z0, z1 = box
        corners = [self.at(lat, fwd, 0) for lat in (lat0 - margin, lat1 + margin)
                   for fwd in (fwd0 - margin, fwd1 + margin)]
        xs = [p[0] for p in corners]
        ys = [p[1] for p in corners]
        bounds = (min(xs), max(xs), min(ys), max(ys), max(z0 - margin, 0.0) * k, (z1 + margin) * k)
        pid = c.sdf(field, bounds, self.look.ramp(layer), name=name, tex=grab, steps=160)
        mine = c.part == pid
        if "light" in got:
            self.light[mine] = got["light"][mine]
            self.nz[mine] = got["nz"][mine]
        self.layer[mine] = LAYER_ID[layer]
        return pid

    def measure(self):
        """Coordenadas del cuerpo de cada pixel visible (después de armar el modelo)."""
        x, y = self.c.to_model(self.c.u, self.c.v)
        self.lat, self.fwd = self.to_body(x, y)
        self.zb = self.c.z / self.k

    def of(self, *names):
        """Máscara de los pixeles visibles de unas piezas (las que existan)."""
        known = [name for name in names if name in self.c._names]
        if not known:
            return np.zeros(self.c.alpha.shape, dtype=bool)
        return self.c.select(known)

    def on(self, layer):
        return self.c.alpha & (self.layer == LAYER_ID[layer])

    # ------------------------------------------------------------------ pintar

    def tone(self, mask, index, layer=None, keep=False):
        """Cambia el tono (y la capa) de pixeles ya dibujados."""
        mask = mask & self.c.alpha
        if layer is None:
            self.c.paint(mask, index)
        else:
            self.c.paint(mask, index, self.look.ramp(layer))
            self.layer[mask] = LAYER_ID[layer]
        if keep:
            self.keep |= mask
        return mask

    def block(self, x, y, width, height, index, layer=None, over=None, keep=True):
        """Pinta un bloque de pixeles del lienzo (x, y de la esquina de arriba a la izquierda).
        over = máscara donde se permite pintar (por defecto todo lo dibujado)."""
        c = self.c
        mask = (c.X >= x) & (c.X < x + width) & (c.Y >= y) & (c.Y < y + height)
        if over is not None:
            mask &= over
        return self.tone(mask, index, layer, keep)

    def art(self, x, y, rows, legend, over=None, keep=True):
        """Dibujo a mano en la vista canónica: rows = filas de texto, un carácter por pixel
        (' ' o '.' = no tocar); legend = carácter -> (capa, tono). El tono puede ser 'darker' o
        'lighter': un paso respecto de lo que hay debajo (sin cambiar de capa). (x, y) es la
        esquina de arriba a la izquierda en la vista canónica."""
        c = self.c
        for dy, row in enumerate(rows):
            for dx, char in enumerate(row):
                if char in " .":
                    continue
                layer, index = legend[char]
                mask = (c.X == self.flip(x + dx)) & (c.Y == y + dy)
                if over is not None:
                    mask = mask & over
                if index == "darker":
                    self.tone(mask, self.darker(c.shade), None, keep)
                elif index == "lighter":
                    self.tone(mask, self.lighter(c.shade), None, keep)
                else:
                    self.tone(mask, index, layer, keep)

    def stroke(self, points, over, minimum=4):
        """Línea de 1 px que sigue una curva del cuerpo: points = [(lat, fwd, z), …]. Solo se
        pinta sobre `over`, donde la curva queda a la vista (no del otro lado del volumen), y
        solo si se ven al menos `minimum` pixeles. Devuelve la máscara (sin pintar nada)."""
        c = self.c
        mask = np.zeros(c.alpha.shape, dtype=bool)
        last = None
        for lat, fwd, z in points:
            x, y, zz = self.at(lat, fwd, z)
            u, v = c.to_world(x, y)
            px, py = c.project(x, y, zz)
            here = (int(math.floor(px)), int(math.floor(py)), u + v + zz / 64.0)
            if last is not None:
                steps = max(abs(here[0] - last[0]), abs(here[1] - last[1]), 1)
                for i in range(steps + 1):
                    t = i / float(steps)
                    sx = int(round(last[0] + (here[0] - last[0]) * t)) + c.pad
                    sy = int(round(last[1] + (here[1] - last[1]) * t)) + c.pad
                    depth = last[2] + (here[2] - last[2]) * t
                    if 0 <= sy < mask.shape[0] and 0 <= sx < mask.shape[1] and over[sy, sx] \
                            and depth > c.depth[sy, sx] - 0.07:
                        mask[sy, sx] = True
            last = here
        if mask.sum() < minimum:
            mask[:] = False
        return mask

    def darker(self, index):
        """Un paso de sombra en la escala corta de las capas: brillo → base → −25 % → −40 % → contorno."""
        table = np.array([OUTLINE, OUTLINE, DEEP, RIGHT, LEFT, LEFT, BASE, BASE], dtype=np.int16)
        return table[np.asarray(index)]

    def lighter(self, index):
        """Un paso de luz: contorno → −40 % → −25 % → base → brillo."""
        table = np.array([RIGHT, RIGHT, LEFT, BASE, BASE, LIGHT, LIGHT, LIGHT], dtype=np.int16)
        return table[np.asarray(index)]

    # ------------------------------------------------------------------ silueta

    def erase(self, mask):
        c = self.c
        c.alpha[mask] = False
        c.part[mask] = -1
        c.fid[mask] = -1
        c.face[mask] = -1
        c.side[mask] = 0
        c.ramp_id[mask] = -1
        c.depth[mask] = -1.0e9
        self.layer[mask] = -1
        c.result = None

    def copy_pixel(self, y, x, sy, sx):
        """Crea el pixel (y, x) copiando todo del pixel (sy, sx)."""
        c = self.c
        for arr in (c.alpha, c.part, c.fid, c.face, c.side, c.ramp_id, c.depth, c.shade, c.u, c.v, c.z, c.a, c.b,
                    self.layer, self.light, self.nz, self.lat, self.fwd, self.zb):
            arr[y, x] = arr[sy, sx]
        c.result = None

    def clean_silhouette(self):
        """Silueta limpia: sin puntas (pixel opaco con un solo vecino opaco) ni muescas o
        rendijas de 1 px (pixel vacío entre dos opacos)."""
        c = self.c
        for _ in range(8):
            spikes = c.alpha & (neighbours(c.alpha) <= 1)
            a = c.alpha
            slit = ~a & ((shifted(a, 0, -1, False) & shifted(a, 0, 1, False))
                         | (shifted(a, -1, 0, False) & shifted(a, 1, 0, False)))
            if not spikes.any() and not slit.any():
                break
            self.erase(spikes)
            a = c.alpha
            for y, x in zip(*np.nonzero(slit)):
                # Se rellena con el vecino más cercano a la cámara (el que tapa).
                best = None
                for dy, dx in MOVES4:
                    if a[y + dy, x + dx] and (best is None or c.depth[y + dy, x + dx] > c.depth[best]):
                        best = (y + dy, x + dx)
                if best is not None and neighbours(a)[y, x] >= 2:
                    self.copy_pixel(y, x, best[0], best[1])

    # ------------------------------------------------------------------ sombreado

    def horizontal_light(self):
        """n·luz contando solo la parte horizontal de la normal (−1 … +1): en un tubo vertical
        (las piernas) da bandas verticales limpias, sin que la cadera o una rodilla las corten."""
        lx, ly, lz = iso.LIGHT_DIR
        flat = np.sqrt(np.maximum(1.0 - self.nz ** 2, 1.0e-6))
        return (self.light - self.nz * lz) / flat / math.hypot(lx, ly)

    def shade(self):
        """Tono de cada pixel por bandas de luz, con los umbrales de su capa (el pantalón, con
        la luz horizontal: horizontal_light)."""
        c = self.c
        flat_light = self.horizontal_light()
        for layer, bands in BANDS.items():
            mask = self.on(layer)
            light = flat_light if layer in FLAT_LIGHT else self.light
            if layer in FLAT_LIGHT:
                # Lo que mira hacia arriba (los muslos de un sentado) va con la luz de siempre.
                light = np.where(self.nz > 0.6, self.light, light)
            index = np.full(c.alpha.shape, bands[-1][1], dtype=np.int16)
            for limit, tone in reversed(bands):
                index = np.where(light >= limit, tone, index)
            c.paint(mask, index)

    def merge_small(self, minimum=MIN_PATCH, rounds=4):
        """Funde con lo de al lado las manchas de tono de menos de `minimum` pixeles (ruido del
        sombreado por bandas) y empareja los bordes de banda: un pixel con 3 de sus 4 vecinos de
        otro mismo tono toma ese tono. No toca lo dibujado a mano (keep)."""
        c = self.c
        for _ in range(rounds):
            changed = False
            key = c.ramp_id.astype(np.int32) * 16 + c.shade
            free = c.alpha & ~self.keep
            label, sizes = patches(key, c.alpha)
            small = free & (label >= 0) & (sizes[np.maximum(label, 0)] < minimum)
            votes = {}
            for dy, dx in MOVES4:
                n_key = shifted(key, dy, dx, -1)
                n_ok = shifted(c.alpha, dy, dx, False) & (shifted(c.ramp_id, dy, dx, -1) == c.ramp_id)
                votes[(dy, dx)] = np.where(n_ok, n_key, -1)
            stack = np.stack(list(votes.values()))
            # Tono más votado entre los vecinos de la misma rampa (distinto del propio).
            best = np.full(key.shape, -1, dtype=np.int32)
            best_count = np.zeros(key.shape, dtype=np.int16)
            for i in range(4):
                candidate = stack[i]
                count = np.zeros(key.shape, dtype=np.int16)
                for j in range(4):
                    count += (stack[j] == candidate) & (candidate >= 0)
                better = (count > best_count) & (candidate != key)
                best = np.where(better, candidate, best)
                best_count = np.where(better, count, best_count)
            bump = free & (best_count >= 3)
            target = (small & (best_count >= 1)) | bump
            if target.any():
                c.paint(target, (best % 16).astype(np.int16))
                changed = True
            if not changed:
                break

    def lines(self):
        """Líneas entre piezas de la misma capa (brazo sobre el torso, la oreja sobre la
        cabeza): solo donde las dos quedaron del MISMO tono y se fundirían; un paso más oscuro,
        en el borde de la pieza que queda más cerca de la cámara."""
        c = self.c
        a = c.alpha
        mark = np.zeros(a.shape, dtype=bool)
        for dy, dx in MOVES4:
            n_a = shifted(a, dy, dx, False)
            n_part = shifted(c.part, dy, dx, -1)
            n_depth = shifted(c.depth, dy, dx, -1.0e9)
            n_layer = shifted(self.layer, dy, dx, -1)
            n_shade = shifted(c.shade, dy, dx, 99)
            mark |= a & n_a & (n_layer == self.layer) & (n_part != c.part) & (c.depth > n_depth) & (n_shade >= RIGHT)
        mark &= ~self.keep
        # Línea interior oscura de 1 px del material (STYLE.md, rasgo 1), no el contorno.
        c.paint(mark, DEEP)
        return mark

    def outline(self):
        """Contorno de 1 px en la silueta con el tono de contorno de la capa de cada pixel."""
        c = self.c
        edge = c.alpha & (neighbours(c.alpha) < 4)
        c.paint(edge, OUTLINE)
        # El contorno de la cara (ojos pegados al borde) toma el de la piel.
        self.tone(edge & (self.layer == LAYER_ID["face"]), OUTLINE, "skin")
        return edge

    def ground_line(self):
        """Contorno de 2 px donde la figura da contra el piso (STYLE.md, rasgo 1): la fila de
        arriba del borde de abajo de los zapatos también va en el tono de contorno."""
        c = self.c
        shoes = c.alpha & (self.layer == LAYER_ID["shoes"])
        sole = shoes & ~shifted(c.alpha, 2, 0, False) & shifted(c.alpha, 1, 0, False)
        self.tone(sole, OUTLINE, keep=True)
        return sole

    def colors(self):
        """Color final de cada pixel como un entero (−1 = transparente)."""
        c = self.c
        out = np.full(c.alpha.shape, -1, dtype=np.int64)
        for rid, ramp in enumerate(c.ramps):
            table = ramp.table().astype(np.int64)
            packed = table[:, 0] * 65536 + table[:, 1] * 256 + table[:, 2]
            mask = c.alpha & (c.ramp_id == rid)
            out[mask] = packed[np.clip(c.shade[mask], 0, len(packed) - 1)]
        return out

    def loose(self, moves=MOVES8):
        """Pixeles sin ningún vecino de su mismo color."""
        color = self.colors()
        alone = self.c.alpha.copy()
        for dy, dx in moves:
            alone &= shifted(color, dy, dx, -1) != color
        return alone

    def absorb_loose(self):
        """Los pixeles sueltos que queden (salvo los dibujados a mano) toman el color más
        repetido entre sus vecinos."""
        c = self.c
        edge = c.alpha & (neighbours(c.alpha) < 4)
        for _ in range(4):
            # El contorno no se toca: un pixel del borde siempre lleva el tono de contorno.
            alone = self.loose() & ~self.keep & ~edge
            if not alone.any():
                break
            for y, x in zip(*np.nonzero(alone)):
                votes = {}
                for dy, dx in MOVES4:
                    ny, nx = y + dy, x + dx
                    if c.alpha[ny, nx]:
                        k = (int(c.ramp_id[ny, nx]), int(c.shade[ny, nx]), int(self.layer[ny, nx]))
                        votes[k] = votes.get(k, 0) + (2 if k[0] == c.ramp_id[y, x] else 1)
                if votes:
                    rid, index, layer = max(votes.items(), key=lambda item: item[1])[0]
                    c.shade[y, x] = index
                    c.ramp_id[y, x] = rid
                    self.layer[y, x] = layer
            c.result = None
        # Un pixel de contorno suelto (un zapato que asoma 1 px entre las piernas) toma el
        # contorno de la capa vecina: sigue siendo contorno y se une a la línea de al lado.
        alone = self.loose() & edge
        for y, x in zip(*np.nonzero(alone)):
            for dy, dx in MOVES8:
                ny, nx = y + dy, x + dx
                if edge[ny, nx] and c.ramp_id[ny, nx] != c.ramp_id[y, x] and c.shade[ny, nx] == OUTLINE:
                    c.ramp_id[y, x] = c.ramp_id[ny, nx]
                    self.layer[y, x] = self.layer[ny, nx]
                    break
        c.result = None

    # ------------------------------------------------------------------ salida

    def render(self):
        c = self.c
        c.no_finish(np.ones(c.alpha.shape, dtype=bool))
        return c.finish()

    def layer_mask(self, layer):
        return self.c.crop(self.on(layer))


# ---------------------------------------------------------------------- modelo

SHOE_LAT = 5.7  # media separación de los zapatos
SHOE = (3.7, -4.4, 8.4, 6.4, 2.8)  # medio ancho, atrás, adelante, alto y radio del zapato
SIT_KNEE_FWD = 13.5  # sentado: la rodilla, hacia adelante de la cadera
SIT_FEET_FWD = 15.5  # sentado: los tobillos


def shoe_fwd(pose):
    """Corrimiento de los zapatos hacia el frente (sentado, bajo las rodillas)."""
    return SIT_FEET_FWD - 2.0 if pose.sit else 0.0


def build_model(fig, hair=True):
    """El cuerpo, de abajo hacia arriba, en px del cuerpo."""
    pose = fig.pose
    half, back, front, height, radius = SHOE
    shift = shoe_fwd(pose)
    # Zapatos: separados unos 3 px, la punta hacia adelante.
    for side, sign in (("l", -1.0), ("r", 1.0)):
        lat = sign * SHOE_LAT
        box = (lat - half, lat + half, back + shift, front + shift, 0.0, height)
        fig.solid("shoe_" + side, "shoes", f_box(*(box + (radius,))), box)
    cut_z = pose.belt_z + BELT_H
    cut = lambda lat, fwd, z: z - cut_z
    if pose.sit:
        # Sentado: cadera redonda apoyada en SIT_SEAT_Z, muslos al frente y canillas que bajan.
        thigh_r = 5.6
        thigh_z = SIT_SEAT_Z + thigh_r
        legs = []
        for sign in (-1.0, 1.0):
            hip = (sign * 4.6, -1.0, thigh_z)
            knee = (sign * 5.2, SIT_KNEE_FWD, thigh_z - 0.5)
            ankle = (sign * SHOE_LAT, SIT_FEET_FWD, 6.5)
            legs.append(f_blend(f_capsule(hip, knee, thigh_r, 5.2), f_capsule(knee, ankle, 4.6, 4.0), 1.5))
        seat = f_box(-9.4, 9.4, -6.0, 5.0, SIT_SEAT_Z, cut_z + 2.0, 5.0)
        body = f_blend(f_blend(legs[0], legs[1], 2.0), seat, 2.0)
        fig.solid("pants", "pants", f_intersect(body, cut),
                  (-11.0, 11.0, -7.0, SIT_FEET_FWD + 6.0, 2.0, cut_z))
    else:
        # Pantalón: cadera y piernas en UNA pieza. Cada pierna es un tubo que sube hasta el
        # cinturón (cortado plano ahí) y las dos se funden arriba (unión suavizada): la cadera es
        # redonda como las piernas, así el sombreado baja seguido del cinturón a los zapatos. Se
        # abren un poco hacia los pies: entre los tobillos queda un hueco de 3 px.
        legs = f_blend(f_capsule((-4.5, 0.0, 46.0), (-SHOE_LAT, 0.4, 6.5), 5.3, 4.0),
                       f_capsule((4.5, 0.0, 46.0), (SHOE_LAT, 0.4, 6.5), 5.3, 4.0), 2.5)
        fig.solid("pants", "pants", f_intersect(legs, cut), (-10.5, 10.5, -6.5, 6.5, 2.0, cut_z))
    # Camisa: el torso es una sola caja redondeada (caras limpias: arriba los hombros, el pecho
    # y el costado), un poco más angosta en la cintura.
    fig.solid("torso", "shirt", f_torso(pose), (-10.5, 10.5, -6.5, 6.5, pose.belt_z + 1.0, pose.neck_z + 1.5))
    # Brazos (manga larga): hombro-codo y codo-muñeca, fundidos en el codo, y la mano.
    for side, sign in (("l", -1.0), ("r", 1.0)):
        shoulder, elbow, wrist, hand = pose.arm_points(sign)
        arm = f_blend(f_capsule(shoulder, elbow, 3.9, 3.6), f_capsule(elbow, wrist, 3.6, 3.3), 1.0)
        points = (shoulder, elbow, wrist)
        box = (min(p[0] for p in points) - 4.5, max(p[0] for p in points) + 4.5,
               min(p[1] for p in points) - 4.5, max(p[1] for p in points) + 4.5,
               min(p[2] for p in points) - 4.5, max(p[2] for p in points) + 4.5)
        fig.solid("arm_" + side, "shirt", arm, box)
        radii = pose.arm[4]
        fig.solid("hand_" + side, "skin", f_ellipsoid(hand, radii),
                  (hand[0] - radii[0] - 0.2, hand[0] + radii[0] + 0.2, hand[1] - radii[1] - 0.2,
                   hand[1] + radii[1] + 0.2, hand[2] - radii[2] - 0.2, hand[2] + radii[2] + 0.2))
    # Cuello, cabeza y orejas.
    neck, head_z = pose.neck_z, pose.head_z
    fig.solid("neck", "skin", f_capsule((0.0, 0.0, neck - 2.0), (0.0, 0.3, neck + 6.0), 4.3),
              (-4.5, 4.5, -4.5, 4.8, neck - 5.0, neck + 9.0))
    fig.solid("head", "skin", f_ellipsoid((0.0, 0.5, head_z), (12.8, 13.2, 13.5)),
              (-13.0, 13.0, -13.0, 14.0, head_z - 13.6, head_z + 13.6))
    for side, sign in (("l", -1.0), ("r", 1.0)):
        fig.solid("ear_" + side, "skin", f_ellipsoid((sign * 12.9, -0.5, head_z - 2.5), (2.2, 2.6, 3.2)),
                  (sign * 12.9 - 2.3, sign * 12.9 + 2.3, -3.2, 2.2, head_z - 5.8, head_z + 0.8))
    if hair:
        build_hair(fig)


HAIR_OFFSET = (0.0, -0.8, 1.2)  # centro del casquete respecto del centro de la cabeza
HAIR_RADII = (14.4, 15.0, 14.8)
PART_LAT = 4.5  # la raya del peinado, del lado derecho del personaje


def hair_center(fig):
    return (HAIR_OFFSET[0], HAIR_OFFSET[1], fig.pose.head_z + HAIR_OFFSET[2])


def build_hair(fig):
    """Pelo corto con raya al costado: casquete que cubre arriba y atrás y flequillo peinado
    hacia el lado largo."""
    head_z = fig.pose.head_z
    cap = f_ellipsoid(hair_center(fig), HAIR_RADII)

    def hairline(lat, fwd, z):
        # Alta en la frente (la vista es desde arriba: si no, el pelo tapa la cara), baja en las
        # sienes y hasta la nuca por atrás.
        temple = np.clip((np.abs(lat) - 6.0) / 6.0, 0.0, 1.0) * np.clip((fwd + 2.0) / 6.0, 0.0, 1.0)
        line = head_z + 2.5 + fwd * 0.75 - 4.0 * temple
        return (line - z) * 0.8

    fringe = f_ellipsoid((-1.5, 7.0, head_z + 9.5), (9.0, 5.4, 4.2))
    fig.solid("hair", "hair", f_union(f_intersect(cap, hairline), fringe),
              (-14.6, 14.6, -16.0, 14.4, head_z - 12.0, head_z + 16.2))


def hair_top(center, lat, fwd):
    """Punto de la superficie del casquete encima de (lat, fwd)."""
    cx, cy, cz = center
    rx, ry, rz = HAIR_RADII
    inside = max(1.0 - ((lat - cx) / rx) ** 2 - ((fwd - cy) / ry) ** 2, 0.0)
    return (lat, fwd, cz + rz * math.sqrt(inside))


def hair_back(center, lat, z):
    """Punto de la superficie de atrás del casquete a la altura z."""
    cx, cy, cz = center
    rx, ry, rz = HAIR_RADII
    inside = max(1.0 - ((lat - cx) / rx) ** 2 - ((z - cz) / rz) ** 2, 0.0)
    return (lat, cy - ry * math.sqrt(inside), z)


def hair_strands(fig):
    """Curvas del peinado en px del cuerpo: la raya y los mechones que salen de ella hacia el
    lado largo, uno hacia el lado corto y los que caen por atrás hasta la nuca."""
    center = hair_center(fig)
    dz = fig.pose.head_z - HEAD_Z
    curves = []
    curves.append([hair_top(center, PART_LAT, fwd) for fwd in np.linspace(11.0, -3.0, 15)])
    for start, end, bend in ((7.5, 9.5, 1.5), (2.0, 0.5, 1.0), (-3.0, -7.5, 0.0)):
        curve = []
        for t in np.linspace(0.0, 1.0, 16):
            lat = PART_LAT - 2.0 - t * 14.5
            curve.append(hair_top(center, lat, start + (end - start) * t + bend * math.sin(t * math.pi)))
        curves.append(curve)
    curves.append([hair_top(center, PART_LAT + 2.0 + t * 7.0, 3.0 - 2.5 * t) for t in np.linspace(0.0, 1.0, 10)])
    # Por atrás: tres mechones que salen de la coronilla y se abren hacia la nuca, curvos
    # (el corrimiento crece con el cuadrado de lo que bajan), cortos para que no parezcan rayas.
    for lat_top, lat_end, top, bottom in ((-3.0, -10.5, 93.0, 76.0), (1.5, 2.5, 94.0, 79.0), (5.0, 11.0, 92.0, 77.0)):
        curve = []
        for t in np.linspace(0.0, 1.0, 14):
            curve.append(hair_back(center, lat_top + (lat_end - lat_top) * t * t, top + dz + (bottom - top) * t))
        curves.append(curve)
    return curves


def hair_details(fig):
    """Mechones (un paso más oscuros: parten el brillo en manchas menores) y, de espaldas, la
    nuca recortada en dientes de 2 px."""
    c = fig.c
    hair = fig.on("hair")
    if not hair.any():
        return
    done = np.zeros(c.alpha.shape, dtype=bool)
    # Los mechones no tocan la silueta: ahí va el contorno y quedarían cortados en puntos.
    edge = c.alpha & (neighbours(c.alpha) < 4)
    curves = hair_strands(fig)
    if fig.k < 0.9:
        curves = curves[:1] + curves[2:3] + curves[4:5] + curves[6:7]  # chico: menos mechones
    for curve in curves:
        line = fig.stroke(curve, hair & (c.shade >= BASE) & ~edge)
        # Un mechón no toca a otro: quedarían manchas en vez de líneas.
        if (line & (neighbours(done, MOVES8) > 0)).sum() > 1:
            continue
        done |= line
    # Un pixel de mechón sin otro al lado (8 vecinos) es un punto suelto: fuera.
    done &= neighbours(done, MOVES8) > 0
    before = c.shade.copy()
    fig.tone(done, np.where(c.shade == LIGHT, BASE, RIGHT), keep=True)
    # Donde un mechón cruza del brillo a la base cambia de color: el pixel que queda sin otro
    # de su color al lado vuelve a su tono (no deja puntos sueltos).
    alone = fig.loose() & done
    c.paint(alone, before)
    fig.keep &= ~alone
    if not fig.front:
        nape_teeth(fig)


def nape_teeth(fig):
    """Nuca: el borde de abajo del pelo baja 2 px en dientes de 2 px de ancho cada 4."""
    c = fig.c
    hair = fig.on("hair")
    below = fig.of("neck", "head", "torso")
    column = fig.canon_x()
    edge = hair & shifted(below, 1, 0, False)
    xs = column[edge]
    if xs.size == 0:
        return
    for x in range(int(xs.min()) + 1, int(xs.max()), 4):
        for dx in (0, 1):
            ys = c.Y[edge & (column == x + dx)]
            if ys.size:
                fig.block(fig.flip(x + dx), int(ys.max()) + 1, 1, 2, RIGHT, "hair", below)


# ---------------------------------------------------------------------- detalles de volumen
# Salen de las coordenadas del cuerpo de cada pixel, así giran con el modelo.

def volume_details(fig):
    c = fig.c
    pose = fig.pose
    # El cuello queda a la sombra de la cabeza.
    neck = fig.of("neck")
    fig.tone(neck, fig.darker(c.shade))
    # Cinturón: la franja de arriba del pantalón, en el tono del contorno.
    belt = fig.of("pants") & (fig.zb >= pose.belt_z)
    if pose.sit:
        belt &= fig.fwd < 5.5  # sentado, la cara de arriba de los muslos no es cinturón
    fig.tone(belt, OUTLINE)
    # Puño de la manga: el final del antebrazo, un paso más oscuro.
    for side, sign in (("l", -1.0), ("r", 1.0)):
        _shoulder, elbow, wrist, _hand = pose.arm_points(sign)
        d = np.array(wrist) - np.array(elbow)
        length = float(np.linalg.norm(d))
        along = ((fig.lat - elbow[0]) * d[0] + (fig.fwd - elbow[1]) * d[1] + (fig.zb - elbow[2]) * d[2]) / length
        fig.tone(fig.of("arm_" + side) & (along > length + 1.6), fig.darker(c.shade))
    if not fig.front:
        collar_band(fig)


def collar_band(fig):
    """De espaldas el cuello de la camisa es una banda de 2 px alrededor de la base del cuello."""
    c = fig.c
    neck_z = fig.pose.neck_z
    around = np.sqrt(fig.lat ** 2 + fig.fwd ** 2)
    torso = fig.of("torso")
    band = torso & (around < 7.2) & (fig.zb > neck_z - 2.5)
    fig.tone(band, LIGHT)
    under = torso & ~band & (around < 8.6) & (fig.zb > neck_z - 4.0)
    fig.tone(under, fig.darker(c.shade))


def leg_line(fig):
    """Línea entre las piernas (son una sola pieza con la cadera): donde un pixel de una pierna
    toca a la otra, se oscurece el de la pierna que queda más cerca."""
    c = fig.c
    pants = fig.of("pants")
    if fig.pose.sit:
        legs = pants & ((fig.fwd > 6.0) | (fig.zb < SIT_SEAT_Z - 2.0))
    else:
        legs = pants & (fig.zb < 28.5)
    side = np.where(fig.lat > 0, 1, -1)
    mark = np.zeros(c.alpha.shape, dtype=bool)
    for dy, dx in MOVES4:
        n_legs = shifted(legs, dy, dx, False)
        n_side = shifted(side, dy, dx, 0)
        n_depth = shifted(c.depth, dy, dx, -1.0e9)
        mark |= legs & n_legs & (n_side != side) & (c.depth >= n_depth) & ((c.depth > n_depth) | (side > 0))
    fig.tone(mark, np.where(c.shade <= RIGHT, OUTLINE, DEEP))
    return mark


# ---------------------------------------------------------------------- detalles a mano
# Se dibujan en la vista canónica (mirando a la derecha) y se espejan solos. Cada uno tiene su
# versión chica (Figure.k < 0.9) para el personaje a tamaño final: no se achica un dibujo de
# pixeles, se dibuja de nuevo.

def face(fig):
    """Ojos con su blanco, cejas, nariz y boca sobre la piel de la cabeza (solo de frente)."""
    if not fig.front:
        return
    head = fig.of("head")
    head_z = fig.pose.head_z
    small = fig.k < 0.9
    legend = {"P": ("face", 0), "W": ("face", 1), "b": ("hair", RIGHT), "n": ("skin", LEFT), "m": ("skin", RIGHT)}
    # Ojos: sobre la superficie de la cabeza, a ±EYE_LAT del centro de la cara.
    for sign in (1, -1):
        x, y = fig.canon(sign * fig.near * EYE_LAT, EYE_FWD, head_z + EYE_DZ)
        if small:
            fig.art(x - 1, y - 1, ["WP", "WP", "WP"], legend, head)
            fig.art(x - 1, y - 3, ["bbb"], legend, head)
        else:
            fig.art(x - 1, y - 1, ["WPP", "WPP", "WPP"], legend, head)
            fig.art(x - 1, y - 3, ["bbbb"], legend, head)
    x, y = fig.canon(0.0, EYE_FWD, head_z + EYE_DZ)
    if small:
        fig.art(x + 1, y + 2, ["nn"], legend, head)
        fig.art(x - 1, y + 4, ["mmm"], legend, head)
    else:
        fig.art(x + 1, y + 2, ["n", "nn"], legend, head)
        fig.art(x - 1, y + 5, ["mmmm"], legend, head)


def collar_and_tie(fig):
    """Cuello de la camisa con sus dos puntas, la V de piel y la corbata con nudo y punta."""
    if not fig.front:
        return
    pose = fig.pose
    small = fig.k < 0.9
    kx, ky = fig.canon(0.0, 5.8, pose.neck_z - 1.5)  # centro del nudo
    cloth = fig.of("torso", "neck")
    legend = {"s": ("skin", LEFT), "C": ("shirt", LIGHT), "c": ("shirt", "darker"),
              "K": ("accent", LEFT), "T": ("accent", BASE), "t": ("accent", RIGHT)}
    if small:
        fig.art(kx - 6, ky - 4, [
            ".CCsssssCC..",
            "..CCsssCC...",
            "...CCKKCC...",
            ".....KK.....",
        ], legend, cloth)
    else:
        fig.art(kx - 8, ky - 5, [
            ".CCCsssssssCCC..",
            ".cCCCssssssCCCc.",
            "..cCCCssssCCCc..",
            "...cCCCsssCCc...",
            "....cCCKKKCc....",
            ".....ccKKK......",
            ".......KKK......",
        ], legend, cloth)
    body = fig.of("torso")
    tx, ty = kx - 1, ky + (0 if small else 2)
    length = fig.canon(0.0, 5.8, pose.belt_z + 9.0)[1] - ty
    if small:
        rows = ["Tt"] * 4 + ["TTt"] * max(length - 4, 0) + ["Tt."]
    else:
        rows = ["TTt"] * 6 + ["TTTt"] * max(length - 6, 0) + ["TTt.", ".T.."]
    fig.art(tx, ty, rows, legend, body)
    # Hebilla: bloque de 2×2 en el cinturón, bajo la corbata.
    bx, by = fig.canon(0.0, 5.6, pose.belt_z + 1.8)
    fig.art(bx - 1, by - 1, ["WW", "WW"], {"W": ("face", 1)}, fig.of("pants"))


def hand_details(fig):
    """Pulgar: una rayita de 2 px que lo separa de la palma, del lado del frente (de pie)."""
    if fig.pose.sit or fig.k < 0.9:
        return
    for side, sign in (("l", -1.0), ("r", 1.0)):
        hand = fig.of("hand_" + side)
        if hand.sum() < 12:
            continue
        hx, hy, hz = fig.pose.arm[3]
        x, y = fig.canon(sign * (hx + 0.4), hy + 1.6, hz)
        fig.art(x, y, ["n", "n"], {"n": ("skin", "darker")}, hand)


def f_torso(pose):
    """Torso: caja redondeada que se angosta 1.2 px por lado hacia la cintura."""
    box = f_box(-9.8, 9.8, -5.8, 5.8, pose.belt_z + 1.0, pose.neck_z + 1.0, 4.0)
    top = pose.neck_z - 5.0

    def fn(lat, fwd, z):
        waist = 1.0 + 0.13 * np.clip((top - z) / 22.0, 0.0, 1.0)
        return box(lat * waist, fwd, z)

    return fn


# ---------------------------------------------------------------------- armado

EYE_LAT = 4.0  # media separación de los ojos
EYE_FWD = 10.5  # la cara está sobre la superficie de la cabeza
EYE_DZ = -1.0  # alto de los ojos respecto del centro de la cabeza


def build_one(rotation, look, pose=None, scale=1.0, hair=True, details=True):
    """Figura terminada del personaje con una rotación (0–3), un Look, una pose y una escala."""
    fig = Figure(rotation, look, pose, scale)
    build_model(fig, hair)
    fig.clean_silhouette()
    fig.measure()
    fig.shade()
    volume_details(fig)
    fig.merge_small()
    fig.lines()
    leg_line(fig)
    hair_details(fig)
    if details:
        face(fig)
        collar_and_tie(fig)
        hand_details(fig)
    fig.outline()
    fig.ground_line()
    fig.absorb_loose()
    fig.render()
    return fig


def foot_shadow():
    """Sombra de los pies: un óvalo isométrico de un tono, corrido hacia abajo a la derecha."""
    ys, xs = np.mgrid[0:128, 0:128]
    rx = xs + 0.5 - 64.0
    ry = ys + 0.5 - 80.0
    u = (ry / iso.HALF_H + rx / iso.HALF_W) / 2.0
    v = (ry / iso.HALF_H - rx / iso.HALF_W) / 2.0
    mask = ((u - 0.55) / 0.19) ** 2 + ((v - 0.50) / 0.15) ** 2 <= 1.0
    rgba = np.zeros((128, 128, 4), dtype=np.uint8)
    rgba[mask, :3] = SHADOW_COLOR
    rgba[mask, 3] = 255
    return Image.fromarray(rgba, "RGBA")


# ---------------------------------------------------------------------- revisión propia
# check.py solo mide formato y lienzo en los personajes; esto mide el resto y build falla si algo
# no se cumple.

FEET = (64, 112)


def verify(fig, name):
    """Lista de problemas del sprite terminado (vacía si está bien)."""
    c = fig.c
    pose = fig.pose
    problems = []
    alpha = c.crop(c.alpha)
    shade = c.crop(c.final_shade)
    layer = c.crop(fig.layer)
    ys, xs = np.nonzero(alpha)
    # Apoyo: los pies (sentado, la cadera) sobre (64, 112) y el alto de la pose a su escala.
    low_x, low_y = fig.screen(0.0, shoe_fwd(pose) + 2.0, 0.0)
    if not low_y <= ys.max() + 1 <= low_y + 6:
        problems.append("la fila más baja es %d (pies en %.1f)" % (ys.max(), low_y))
    tall = FEET[1] - ys.min()
    if not pose.height[0] * fig.k <= tall <= pose.height[1] * fig.k:
        problems.append("mide %d px sobre el apoyo (%d–%d)" % (tall, pose.height[0] * fig.k, pose.height[1] * fig.k))
    shoes_x = xs[layer[ys, xs] == LAYER_ID["shoes"]]
    if shoes_x.size == 0 or abs(shoes_x.mean() + 0.5 - low_x) > 3.5:
        problems.append("los zapatos no están centrados en x = %.1f" % low_x)
    if pose.sit:
        hip_x, hip_y = fig.screen(0.0, 0.0, SIT_SEAT_Z)
        if abs(hip_x - FEET[0]) > 0.5 or abs(hip_y - (FEET[1] - SIT_SEAT_Z * fig.k)) > 0.5:
            problems.append("la cadera no queda sobre el apoyo")
    # Silueta limpia: sin puntas de 1 px ni agujeros de 1 px; todo el borde en tono de contorno.
    spikes = alpha & (neighbours(alpha) <= 1)
    holes = ~alpha & (neighbours(alpha) == 4)
    if spikes.any():
        problems.append("puntas de 1 px en %s" % list(zip(*np.nonzero(spikes)[::-1]))[:6])
    if holes.any():
        problems.append("agujeros de 1 px en %s" % list(zip(*np.nonzero(holes)[::-1]))[:6])
    edge = alpha & (neighbours(alpha) < 4)
    if (edge & (shade != OUTLINE)).any():
        problems.append("%d pixeles del borde sin tono de contorno" % int((edge & (shade != OUTLINE)).sum()))
    # Contorno continuo: cada pixel del borde toca (8 vecinos) a otro pixel del borde.
    lone_edge = edge & (neighbours(edge, MOVES8) == 0)
    if lone_edge.any():
        problems.append("contorno cortado en %s" % list(zip(*np.nonzero(lone_edge)[::-1]))[:6])
    # Sin pixeles sueltos: ninguno sin otro de su mismo color entre sus 8 vecinos.
    loose = c.crop(fig.loose())
    if loose.any():
        problems.append("pixeles sueltos en %s" % list(zip(*np.nonzero(loose)[::-1]))[:6])
    # Paleta corta: 6 tonos o menos por capa (contorno, línea, −40 %, −25 %, base, brillo; la cara, 2).
    rgba = np.array(c.image)
    for layer_name in LAYER_ORDER:
        here = alpha & (layer == LAYER_ID[layer_name])
        count = len(set(map(tuple, rgba[here][:, :3].tolist())))
        if count > (2 if layer_name == "face" else 6):
            problems.append("la capa %s tiene %d colores" % (layer_name, count))
    return ["%s: %s" % (name, p) for p in problems]


# ---------------------------------------------------------------------- capas y hojas

def export_layers(fig, bald, folder, name):
    """Una imagen por capa (con los colores del Look) que, puestas una sobre otra en el orden
    de LAYER_ORDER, dan el sprite exacto (se comprueba), más el cuerpo sin pelo (`_bald`) para
    poner otro peinado encima. No son sprites sueltos para check.py: van en character_layers/."""
    sprite = np.array(fig.c.image)
    stack = np.zeros(sprite.shape, dtype=np.uint8)
    for layer_name in LAYER_ORDER:
        image = fig.c.layer(mask=fig.on(layer_name))
        part = np.array(image)
        stack[part[..., 3] > 0] = part[part[..., 3] > 0]
        image.save(os.path.join(folder, "%s_%s.png" % (name, layer_name)))
    assert np.array_equal(stack, sprite), "%s: las capas no componen el sprite" % name
    bald.c.image.save(os.path.join(folder, "%s_bald.png" % name))


def layer_info():
    """Orden de las capas y colores de cada tono por Look, para cambiar paletas en el juego."""
    tones = {"outline": OUTLINE, "right": RIGHT, "left": LEFT, "base": BASE, "light": LIGHT}
    info = {"order": list(LAYER_ORDER), "looks": {}}
    for suffix, look in sorted(LOOKS.items()):
        entry = {}
        for layer_name in LAYER_ORDER:
            table = look.ramp(layer_name).table()
            if layer_name == "face":
                entry[layer_name] = {"pupil": pal.rgb_to_hex(table[0]), "eye_white": pal.rgb_to_hex(table[1])}
            else:
                entry[layer_name] = dict((key, pal.rgb_to_hex(table[index])) for key, index in tones.items())
        info["looks"][suffix[1:] or "base"] = entry
    return info


def front_cell(fig):
    """Casilla vecina (dx, dy) hacia la que mira la figura (donde va el escritorio)."""
    c = fig.c
    u0, v0 = c.to_world(*fig.at(0.0, 0.0, 0.0)[:2])
    u1, v1 = c.to_world(*fig.at(0.0, 40.0, 0.0)[:2])
    du, dv = u1 - u0, v1 - v0
    return (int(np.sign(du)), 0) if abs(du) > abs(dv) else (0, int(np.sign(dv)))


def chair_scene(out_dir, fig, name, tiles, load):
    """Un sentado sobre la silla del piloto (chair_basic_seat/back), con el escritorio delante si
    están generados; sin silla, sobre el piso solo. Respaldo encima en r0 y r3 (BACK_ON_TOP de
    chair_plant), debajo en r1 y r2."""
    rotation = fig.c.rotation
    scene = sheet.Scene(3, 3, top=70, margin=4)
    scene.fill_floor(tiles, seed=rotation)
    seat = load("chair_basic_seat_r%d.png" % rotation)
    back = load("chair_basic_back_r%d.png" % rotation)
    on_top = rotation in (0, 3)
    if seat is not None and back is not None:
        scene.add(back, 1, 1, bias=1.0 if on_top else -2.0)
        scene.add(seat, 1, 1, bias=-1.0)
    dx, dy = front_cell(fig)
    desk = load("desk_simple_r%d.png" % ((rotation + 2) % 4))
    if desk is not None:
        scene.add(desk, 1 + dx, 1 + dy)
    scene.add(load(name + ".png"), 1, 1, anchor=FEET)
    return scene.render(scale=1)


def build_sheet(out_dir, figures):
    """_sheets/character.png (×3): todos los sprites sobre fondo (más el de pie achicado al 80 %
    con vecino más cercano, para comparar con el dibujado a tamaño final), una escena de pie sobre
    cerámica junto al escritorio y la silla del piloto, y los sentados sobre la silla."""
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)

    def load(file_name):
        path = os.path.join(out_dir, file_name)
        return sheet.load(path) if os.path.isfile(path) else None

    tiles = [t for t in (load("floor_ceramic_%d.png" % i) for i in range(4)) if t is not None] or [sheet.plain_tile()]
    scene = sheet.Scene(5, 3, top=110, margin=12)
    scene.fill_floor(tiles, seed=2)
    shadow = load("character_stand_shadow.png")
    desk = load("desk_simple_r1.png")
    chair = load("chair_basic_r3.png")
    if desk is not None:
        scene.add(desk, 1, 1)
    if chair is not None:
        scene.add(chair, 2, 1)
    for name, cell in (("character_stand_r2", (3, 1)), ("character_stand_r1", (0, 0)), ("character_stand_r0", (2, 2)),
                       ("character_stand_r3", (4, 0)), ("character_stand_r1_v1", (1, 2)),
                       ("character_stand_r1_v2", (4, 2))):
        image = load(name + ".png")
        if image is None:
            continue
        if shadow is not None:
            scene.add_shadow(shadow, cell[0], cell[1], anchor=FEET, opacity=0.3)
        scene.add(image, cell[0], cell[1], anchor=FEET)
    view = scene.render(scale=3)
    items = [(name, fig.c.image) for name, fig in figures]
    stand = dict(figures)["character_stand_r1"].c.image
    shrunk = stand.resize((int(round(128 * SMALL_SCALE)),) * 2, Image.NEAREST)
    padded = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    padded.alpha_composite(shrunk, (int(round(64 - 64 * SMALL_SCALE)), int(round(112 - 112 * SMALL_SCALE))))
    items.append(("r1 achicado 80 %", padded))
    parts = sheet.contact_sheet(items, columns=6, scale=3)
    sits = [chair_scene(out_dir, fig, name, tiles, load) for name, fig in figures if name.startswith("character_sit")]
    row = Image.new("RGBA", (sum(i.size[0] for i in sits), max(i.size[1] for i in sits)), sheet.BACKGROUND + (255,))
    x = 0
    for image in sits:
        row.alpha_composite(image, (x, 0))
        x += image.size[0]
    row = sheet.upscale(row, 3)
    width = max(view.size[0], parts.size[0], row.size[0])
    page = Image.new("RGBA", (width, view.size[1] + parts.size[1] + row.size[1]), sheet.BACKGROUND + (255,))
    page.alpha_composite(parts, ((width - parts.size[0]) // 2, 0))
    page.alpha_composite(view, ((width - view.size[0]) // 2, parts.size[1]))
    page.alpha_composite(row, ((width - row.size[0]) // 2, parts.size[1] + view.size[1]))
    page.save(os.path.join(folder, "character.png"))


def build(out_dir):
    files = []
    figures = []
    problems = []
    layers_dir = os.path.join(out_dir, "character_layers")
    if not os.path.isdir(layers_dir):
        os.makedirs(layers_dir)
    for pose in (STAND, SIT):
        for rotation in range(4):
            fig = build_one(rotation, LOOKS[""], pose)
            name = "character_%s_r%d" % (pose.name, rotation)
            problems += verify(fig, name)
            meta = {"pose": pose.name, "layers": list(LAYER_ORDER)}
            if pose.sit:
                meta["seat_z"] = SIT_SEAT_Z
            files.append(iso.save(fig.c, out_dir, name, **meta))
            export_layers(fig, build_one(rotation, LOOKS[""], pose, hair=False), layers_dir, name)
            figures.append((name, fig))
        if pose is STAND:
            base = figures[1][1]
            for suffix in ("_v1", "_v2"):
                fig = build_one(1, LOOKS[suffix])
                name = "character_stand_r1%s" % suffix
                # Solo cambia la paleta: los índices de tono de cada pixel son los de la variante base.
                if not (np.array_equal(fig.c.final_shade, base.c.final_shade)
                        and np.array_equal(fig.c.ramp_id, base.c.ramp_id)):
                    problems.append("%s: no es solo un cambio de paleta" % name)
                problems += verify(fig, name)
                files.append(iso.save(fig.c, out_dir, name, pose="stand", variant=suffix[1:]))
                figures.append((name, fig))
            # A tamaño final (BODY_SCALE 0.8): el mismo modelo con k = 0.8 y los detalles chicos.
            fig = build_one(1, LOOKS[""], STAND, SMALL_SCALE)
            name = "character_stand_r1_s80"
            problems += verify(fig, name)
            files.append(iso.save(fig.c, out_dir, name, pose="stand", scale=SMALL_SCALE, layers=list(LAYER_ORDER)))
            export_layers(fig, build_one(1, LOOKS[""], STAND, SMALL_SCALE, hair=False), layers_dir, name)
            figures.append((name, fig))
    shadow = foot_shadow()
    if not np.array(shadow)[FEET[1], FEET[0], 3]:
        problems.append("character_stand_shadow: no pasa por los pies")
    files.append(iso.save(shadow, out_dir, "character_stand_shadow", kind="shadow", footprint=[1, 1],
                          anchor=list(FEET)))
    with open(os.path.join(layers_dir, "layers.json"), "w") as handle:
        json.dump(layer_info(), handle, indent=2, sort_keys=True)
    build_sheet(out_dir, figures)
    if problems and not os.environ.get("CHARACTER_NO_FAIL"):
        raise AssertionError("revisión del personaje:\n  " + "\n  ".join(problems))
    for problem in problems:
        print("  aviso: " + problem)
    return files
