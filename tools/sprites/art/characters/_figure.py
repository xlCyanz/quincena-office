"""Modelo de los personajes de Quincena Office (docs/sprites_128.md, sección 9; STYLE.md): cabeza grande y cuerpo
robusto, 4 direcciones, de pie, sentado y animaciones, en 8 conjuntos de ropa (STYLES) y 3 paletas (LOOKS). El
personal de limpieza (CLEANING_STYLES) tiene además trapear (mop) y caminar con el suape (mopwalk).

Lienzo 128×128 con los pies en (64, 112); sentado, la cadera a SIT_SEAT_Z sobre el piso. Modelo de campos de
distancia en px del cuerpo (lat, fwd, z) girado TURN hacia la cámara, rasterizado con ``tools/sprites/iso.py``;
sombreado, contorno y detalles se pintan pixel a pixel. ``build_one`` da la figura terminada y ``verify`` la revisa;
``build.py`` guarda cada cuadro como documento Moana.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))  # tools/sprites

import iso  # noqa: E402
import palette as pal  # noqa: E402

PX = 1.0 / iso.Z_METRIC  # 1 px del cuerpo en casillas
CENTER = 0.5  # el personaje se para en el centro de la casilla
# Giro hacia la cámara: con 45° − atan(1/2) una línea lateral queda en escalera de 4 px por 1.
TURN = math.radians(45.0) - math.atan(0.5)

# Alturas en px de sprite (piso 0, coronilla ~98).
BELT_Z = 32.0  # borde de abajo del cinturón
BELT_H = 3.0
CUFF_Z = 38.0  # muñeca
NECK_Z = 62.0  # base del cuello
HEAD_Z = 78.5  # centro de la cabeza (grande: 33 px; tapa el cuello)
SIT_SEAT_Z = 24.0  # sentado: donde la cadera apoya en el asiento (guía, sección 9)
SIT_DROP = 4.0  # sentado, el torso y la cabeza quedan 4 px más abajo que de pie
SMALL_SCALE = 0.8  # BODY_SCALE del juego (OfficeCharacter): el personaje a tamaño final


class Pose(object):
    """Medidas de una pose en px del cuerpo. arm = (hombro, codo, muñeca, centro y radios de la mano),
    lat hacia afuera. Por cuadro (lado −1 izquierda, +1 derecha): feet (adelante, levantado),
    swing (corrimiento de codo, muñeca y mano), hands (sube la mano), pitch (grados que gira el zapato:
    + talón arriba sobre la punta, − punta arriba sobre el talón), bob (sube el cuerpo), breath (suben
    hombros y cabeza)."""

    def __init__(self, name, sit, arm, height, feet=None, swing=None, hands=None, bob=0.0, breath=0.0, arms=None,
                 tool=None, pitch=None):
        self.name = name
        self.pitch = pitch or {}
        self.arms = arms or {}  # brazo propio por lado: (hombro, codo, muñeca, mano) sin el bob ni la respiración
        self.tool = tool  # suape: {"top", "bottom", "head"} en px del cuerpo (sin el bob)
        self.sit = sit
        drop = SIT_DROP if sit else 0.0
        self.bob = float(bob)
        self.breath = float(breath)
        self.belt_z = BELT_Z - drop + self.bob
        self.neck_z = NECK_Z - drop + self.bob + self.breath
        self.head_z = HEAD_Z - drop + self.bob + self.breath
        self.arm = arm
        self.height = height  # alto esperado sobre los pies (mínimo, máximo) a escala 1
        self.feet = feet or {}
        self.swing = swing or {}
        self.hands = hands or {}

    def foot(self, sign):
        return self.feet.get(sign, (0.0, 0.0))

    def foot_turn(self, sign):
        """(ángulo en radianes, pivote (fwd, z)) del zapato de un lado: gira sobre la punta o el talón."""
        step, lift = self.foot(sign)
        pitch = self.pitch.get(sign, 0.0)
        half, back, front, _height, _radius = SHOE
        pivot = (front - 1.5 if pitch > 0 else back + 1.5) + step
        return -math.radians(pitch), (pivot, lift)

    def arm_points(self, sign):
        lift = self.bob + self.breath
        if sign in self.arms:
            return [(p[0], p[1], p[2] + lift) for p in self.arms[sign]]
        swing = (0.0,) + tuple(self.swing.get(sign, (0.0, 0.0, 0.0)))
        up = (0.0, 0.0, 0.4 * self.hands.get(sign, 0.0), self.hands.get(sign, 0.0))
        return [(sign * p[0], p[1] + swing[i], p[2] + lift + up[i]) for i, p in enumerate(self.arm[:4])]


# De pie: brazos abiertos y el codo apenas doblado; queda aire entre la mano y la cadera.
STAND = Pose("stand", False, ((13.6, 0.0, 57.0), (16.0, 0.4, 47.5), (17.4, 2.4, CUFF_Z + 2.0),
                              (18.0, 3.0, CUFF_Z - 3.5), (4.6, 4.6, 5.2)), (96, 104))
# Sentado: antebrazo al frente, casi horizontal, manos planas como sobre un teclado.
SIT = Pose("sit", True, ((13.6, 0.0, 54.0), (15.0, 1.5, 44.6), (10.8, 16.0, 45.6),
                         (9.8, 20.5, 45.4), (4.2, 4.8, 3.3)), (86, 100))

# ---- animaciones: cada cuadro es una pose; el ciclo empalma
WALK_FRAMES = 8
IDLE_FRAMES = 4
TYPE_FRAMES = 4
STRIDE = 8.0  # cuánto se adelanta y se atrasa cada pie
FOOT_LIFT = 3.6  # cuánto sube el pie que avanza
ARM_SWING = (2.4, 6.5, 9.0)  # codo, muñeca y mano: van al revés de la pierna de su lado
ARM_LIFT = 2.6  # el brazo que va adelante dobla el codo: la mano sube esto
HEEL_UP = 24.0  # grados: el pie de atrás despega levantando el talón
TOE_UP = 14.0  # grados: el pie de adelante pisa con el talón, la punta arriba
WALK_BOB = 1.2  # el cuerpo sube esto al cruzar las piernas y baja al pisar


def walk_poses():
    """Caminar: pie izquierdo adelante (pisa con el talón) en el cuadro 3 y derecho en el 7; el de atrás
    despega con la punta; brazos al revés de su pierna, con el codo doblado al ir adelante."""
    poses = []
    for i in range(WALK_FRAMES):
        t = 2.0 * math.pi * i / WALK_FRAMES
        s, c = math.sin(t), math.cos(t)
        feet = {-1.0: (STRIDE * s, FOOT_LIFT * max(c, 0.0)), 1.0: (-STRIDE * s, FOOT_LIFT * max(-c, 0.0))}
        swing = {-1.0: tuple(-k * s for k in ARM_SWING), 1.0: tuple(k * s for k in ARM_SWING)}
        hands = {-1.0: ARM_LIFT * max(-s, 0.0), 1.0: ARM_LIFT * max(s, 0.0)}
        pitch = {}
        for sign, ahead, air in ((-1.0, s, c), (1.0, -s, -c)):
            if ahead < -0.1:
                pitch[sign] = HEEL_UP * (-ahead) ** 1.5
            elif ahead > 0.1:
                pitch[sign] = -TOE_UP * ahead * max(1.0 - 2.0 * abs(air), 0.0)
        poses.append(Pose("walk", False, STAND.arm, STAND.height, feet=feet, swing=swing, hands=hands,
                          bob=WALK_BOB * abs(c), pitch=pitch))
    return poses


def idle_poses():
    """De pie, respirando: hombros y cabeza suben 1 px y bajan."""
    return [Pose("idle", False, STAND.arm, STAND.height, breath=b) for b in (0.0, 0.6, 1.0, 0.6)][:IDLE_FRAMES]


def type_poses():
    """Sentado tecleando: sube una mano, baja, sube la otra, baja."""
    ups = ({-1.0: 2.0}, {-1.0: 0.6, 1.0: 0.6}, {1.0: 2.0}, {-1.0: 0.6, 1.0: 0.6})
    return [Pose("type", True, SIT.arm, SIT.height, hands=up) for up in ups][:TYPE_FRAMES]


ANIMATIONS = (("walk", walk_poses), ("idle", idle_poses), ("type", type_poses))

# ---- suape (solo el personal de limpieza: CLEANING_STYLES)
MOP_FRAMES = 4
MOPWALK_FRAMES = WALK_FRAMES
MOP_SWING = 7.0  # cuánto va de un lado a otro la mopa en el piso (px del cuerpo)
MOP_TOP = (2.0, 6.0, 64.0)  # punta de arriba del palo trapeando
MOP_REACH = 23.0  # a qué distancia al frente queda la mopa
MOP_HEAD = (10.5, 6.0, 2.6)  # radios de la mopa (lat, fwd, alto)
STICK_R = 1.7


def _arm_to(sign, hand, out=15.0):
    """Brazo de un lado que llega con la mano a `hand`: el codo sale hacia afuera y abajo."""
    shoulder = (sign * 13.6, 0.0, 57.0)
    elbow = (sign * out, (shoulder[1] + hand[1]) / 2.0 - 1.0, (shoulder[2] + hand[2]) / 2.0 - 4.0)
    wrist = tuple(hand[i] + (elbow[i] - hand[i]) * 0.18 for i in range(3))
    return (shoulder, elbow, wrist, hand)


def _on_stick(top, bottom, t):
    return tuple(top[i] + (bottom[i] - top[i]) * t for i in range(3))


def mop_poses():
    """Trapeando: las dos manos en el palo (la derecha arriba) y la mopa va y viene en el piso."""
    poses = []
    for i in range(MOP_FRAMES):
        swing = MOP_SWING * math.sin(2.0 * math.pi * i / MOP_FRAMES + math.pi / 4.0)
        top = (MOP_TOP[0] + 0.25 * swing, MOP_TOP[1], MOP_TOP[2])
        bottom = (swing, MOP_REACH, MOP_HEAD[2])
        arms = {1.0: _arm_to(1.0, _on_stick(top, bottom, 0.12)), -1.0: _arm_to(-1.0, _on_stick(top, bottom, 0.36))}
        tool = {"top": top, "bottom": bottom, "head": (swing, MOP_REACH + 1.0, MOP_HEAD[2])}
        poses.append(Pose("mop", False, STAND.arm, STAND.height, arms=arms, tool=tool, breath=0.4 * (i % 2)))
    return poses


def mopwalk_poses():
    """Caminando con el suape parado en la mano derecha (sin balancear ese brazo)."""
    poses = []
    for pose in walk_poses():
        hand = (16.6, 5.0, CUFF_Z - 2.0)
        top = (hand[0], hand[1] + 1.0, hand[2] + 24.0)
        bottom = (hand[0], hand[1] + 3.0, MOP_HEAD[2] + 3.0)
        arms = {1.0: _arm_to(1.0, hand, out=16.4)}
        swing = {-1.0: pose.swing.get(-1.0, (0.0, 0.0, 0.0))}
        poses.append(Pose("mopwalk", False, STAND.arm, STAND.height, feet=pose.feet, swing=swing, bob=pose.bob,
                          hands={-1.0: pose.hands.get(-1.0, 0.0)}, pitch=pose.pitch, arms=arms, tool={"top": top, "bottom": bottom, "head": (bottom[0], bottom[1] + 0.5, bottom[2])}))
    return poses


TOOL_ANIMATIONS = (("mop", mop_poses), ("mopwalk", mopwalk_poses))
CLEANING_STYLES = ("cleaning", "woman_cleaning")  # conjuntos con las poses del suape

OUTLINE, DEEP, RIGHT, LEFT, BASE, LIGHT = pal.OUTLINE, pal.DEEP, pal.RIGHT, pal.LEFT, pal.BASE, pal.LIGHT

# Capas, de atrás hacia adelante para componerlas (LAYER_ORDER).
LAYER_ORDER = ("shoes", "pants", "shirt", "jacket", "skin", "accent", "face", "hair", "stick", "mop")
LAYER_ID = dict((name, index) for index, name in enumerate(LAYER_ORDER))

# Bandas de luz por capa: (umbral mínimo de n·luz, tono), de más a menos luz. Izquierda = base,
# derecha = −25 %, abajo a la derecha = −40 %.
BANDS = {
    "shoes": ((0.72, LIGHT), (-0.25, BASE), (-9.0, LEFT)),
    "pants": ((0.45, BASE), (-0.30, LEFT), (-9.0, RIGHT)),
    "shirt": ((0.20, BASE), (-0.40, LEFT), (-9.0, RIGHT)),
    "jacket": ((0.20, BASE), (-0.40, LEFT), (-9.0, RIGHT)),
    "skin": ((0.93, LIGHT), (-0.45, BASE), (-9.0, LEFT)),
    "hair": ((0.90, LIGHT), (-0.05, BASE), (-9.0, RIGHT)),
    "stick": ((0.30, BASE), (-0.30, LEFT), (-9.0, RIGHT)),
    "mop": ((0.60, LIGHT), (-0.10, BASE), (-9.0, LEFT)),
}

# Capas que se sombrean con la luz horizontal (Figure.horizontal_light).
FLAT_LIGHT = ("pants",)

SHADOW_COLOR = (26, 28, 38)  # el mismo tono de las sombras de los muebles
MIN_PATCH = 3  # una mancha de tono de menos pixeles se funde con lo de al lado


PLUM_HUE = 330.0 / 360.0  # el contorno corre al ciruela, como el borde de la «maqueta» (STYLE.md)


def layer_ramp(base, light=0.35, name=None):
    """Rampa de una capa (STYLE.md): contorno (base × 0.26, al ciruela), línea DEEP (base × 0.5),
    −40 %, −25 %, base y brillo cálido."""
    dark = pal.adjust(base, 0.26, 1.6, PLUM_HUE, 0.12, 0.30)
    deep = pal.adjust(base, 0.52, 1.25, PLUM_HUE, 0.06, 0.12)
    bright = pal.adjust(pal.lighten(base, light), 1.0, 0.95, pal.WARM_HUE, 0.10, 0.03)
    return pal.ramp(base, outline=dark, deep=deep, light=bright, shine=bright, name=name)


STICK_COLOR = "4a8fd8"  # palo del suape
MOP_COLOR = "cfcab9"  # hilos de la mopa


class Look(object):
    """Una rampa por capa de un empleado; una instancia por variante (el lienzo distingue por objeto)."""

    def __init__(self, skin, hair, shirt, pants, shoes="e6e0d2", accent="c03d43", jacket=None):
        self.skin = layer_ramp(skin, light=0.30, name="skin")
        self.hair = layer_ramp(hair, light=0.28, name="hair")
        self.shirt = layer_ramp(shirt, light=0.45, name="shirt")
        self.pants = layer_ramp(pants, light=0.30, name="pants")
        self.jacket = layer_ramp(jacket or pants, light=0.30, name="jacket")  # saco: por defecto, traje entero
        self.shoes = layer_ramp(shoes, light=0.40, name="shoes")
        self.accent = layer_ramp(accent, light=0.30, name="accent")
        self.face = pal.palette(["1e1420", "fbf6ee"], name="face")  # pupila y blanco del ojo
        # Suape (el mismo en todos los aspectos): palo azul y mopa de hilos gris claro.
        self.stick = layer_ramp(STICK_COLOR, light=0.35, name="stick")
        self.mop = layer_ramp(MOP_COLOR, light=0.25, name="mop")

    def ramp(self, layer):
        return getattr(self, layer)


class Style(object):
    """Conjunto de ropa y cuerpo: cambia la forma (mangas, falda, pelo), no solo los colores."""

    def __init__(self, name, prefix, long_sleeve=False, tucked=False, collar=False, tie=False, skirt=False,
                 hair="side", waist=0.07, jacket=False):
        self.name = name
        self.prefix = prefix  # va en el nombre del sprite: character_<prefix>stand_r0
        self.long_sleeve = long_sleeve  # manga larga con puño (si no, manga corta)
        self.tucked = tucked  # camisa por dentro: se ve el cinturón o la pretina
        self.collar = collar  # cuello de camisa con sus dos puntas
        self.tie = tie  # corbata y hebilla
        self.skirt = skirt  # falda hasta la rodilla y piernas a la vista (del color de la camiseta = vestido)
        # Peinado: side (raya al costado), slick (para atrás, sin flequillo), crop (corto al ras), long (hasta los
        # hombros), bob (melena hasta la barbilla), bun (moño atrás) o ponytail (cola).
        self.hair = hair
        self.waist = waist  # cuánto se angosta el torso hacia la cintura
        self.jacket = jacket  # saco (capa jacket) sobre la camisa: se ve la V de la camisa y el puño


# executive = traje con camisa y corbata; office = camisa de manga larga y corbata; woman = vestido;
# woman_office = blusa y falda; woman_executive = saco y falda; casual = camiseta y jeans;
# cleaning / woman_cleaning = uniforme de limpieza: overol de una pieza con cuello y cinturón.
STYLES = (
    Style("casual", ""),
    Style("office", "office_", long_sleeve=True, tucked=True, collar=True, tie=True),
    Style("woman", "woman_", skirt=True, hair="long", waist=0.13),
    Style("woman_office", "woman_office_", long_sleeve=True, tucked=True, collar=True, skirt=True, hair="bun",
          waist=0.13),
    Style("executive", "executive_", long_sleeve=True, collar=True, tie=True, jacket=True, hair="slick"),
    Style("woman_executive", "woman_executive_", long_sleeve=True, collar=True, skirt=True, hair="bob",
          waist=0.13, jacket=True),
    Style("cleaning", "cleaning_", tucked=True, collar=True, hair="crop"),
    Style("woman_cleaning", "woman_cleaning_", tucked=True, collar=True, hair="ponytail", waist=0.13),
)
STYLE_BY_NAME = dict((style.name, style) for style in STYLES)

DARK_SHOES = "3e2c28"
CLEANING_UNIFORM = "4f8a5b"  # verde del overol de limpieza
# "" = base, "_v1" = piel oscura y pelo negro, "_v2" = piel clara y pelo claro (solo cambia la paleta).
LOOKS = {
    "casual": {
        "": Look(skin="f0b07a", hair="4a2c1c", shirt="e4d2a6", pants="41609e"),
        "_v1": Look(skin="8a5234", hair="241a1c", shirt="45b58a", pants="7a6a4a"),
        "_v2": Look(skin="f8d0a8", hair="df823d", shirt="d84a58", pants="3a3f5a"),
    },
    "office": {
        "": Look(skin="f0b07a", hair="4a2c1c", shirt="8fc4ee", pants="2f3656", shoes=DARK_SHOES),
        "_v1": Look(skin="8a5234", hair="241a1c", shirt="f1eee6", pants="3b3b44", shoes=DARK_SHOES, accent="2f6fb8"),
        "_v2": Look(skin="f8d0a8", hair="df823d", shirt="e9c9d8", pants="4a4038", shoes=DARK_SHOES, accent="3a8f6a"),
    },
    "woman": {
        "": Look(skin="f0b07a", hair="8a3b22", shirt="3aa6a0", pants="3aa6a0"),
        "_v1": Look(skin="8a5234", hair="241a1c", shirt="e2a13a", pants="e2a13a"),
        "_v2": Look(skin="f8d0a8", hair="e6b04a", shirt="b05ac0", pants="b05ac0"),
    },
    "executive": {
        "": Look(skin="f0b07a", hair="4a2c1c", shirt="f1eee6", pants="2c3458", shoes=DARK_SHOES),
        "_v1": Look(skin="8a5234", hair="241a1c", shirt="cfe2f4", pants="3c3c46", shoes=DARK_SHOES, accent="d9a23a"),
        "_v2": Look(skin="f8d0a8", hair="c9c4bc", shirt="f1eee6", pants="5c6072", shoes=DARK_SHOES, accent="2f6fb8"),
    },
    "woman_executive": {
        "": Look(skin="f0b07a", hair="8a3b22", shirt="f1eee6", pants="7c2f3c", shoes=DARK_SHOES),
        "_v1": Look(skin="8a5234", hair="241a1c", shirt="f1eee6", pants="2c3458", shoes=DARK_SHOES),
        "_v2": Look(skin="f8d0a8", hair="e6b04a", shirt="cfe2f4", pants="5c6072", shoes=DARK_SHOES),
    },
    # Uniforme de limpieza: el mismo verde para todos (camisa y pantalón = overol).
    "cleaning": {
        "": Look(skin="f0b07a", hair="4a2c1c", shirt=CLEANING_UNIFORM, pants=CLEANING_UNIFORM, shoes=DARK_SHOES),
        "_v1": Look(skin="8a5234", hair="241a1c", shirt=CLEANING_UNIFORM, pants=CLEANING_UNIFORM, shoes=DARK_SHOES),
        "_v2": Look(skin="f8d0a8", hair="df823d", shirt=CLEANING_UNIFORM, pants=CLEANING_UNIFORM, shoes=DARK_SHOES),
    },
    "woman_cleaning": {
        "": Look(skin="f0b07a", hair="8a3b22", shirt=CLEANING_UNIFORM, pants=CLEANING_UNIFORM, shoes=DARK_SHOES),
        "_v1": Look(skin="8a5234", hair="241a1c", shirt=CLEANING_UNIFORM, pants=CLEANING_UNIFORM, shoes=DARK_SHOES),
        "_v2": Look(skin="f8d0a8", hair="e6b04a", shirt=CLEANING_UNIFORM, pants=CLEANING_UNIFORM, shoes=DARK_SHOES),
    },
    "woman_office": {
        "": Look(skin="f0b07a", hair="8a3b22", shirt="f1eee6", pants="3a3f5a", shoes=DARK_SHOES),
        "_v1": Look(skin="8a5234", hair="241a1c", shirt="f0c7cf", pants="2f3656", shoes=DARK_SHOES),
        "_v2": Look(skin="f8d0a8", hair="e6b04a", shirt="a9d6c4", pants="4a4038", shoes=DARK_SHOES),
    },
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


def turn_point(point, angle, pivot):
    """Gira (fwd, z) alrededor de pivot (fwd, z) un ángulo en el plano del frente."""
    df, dz = point[0] - pivot[0], point[1] - pivot[1]
    ca, sa = math.cos(angle), math.sin(angle)
    return (pivot[0] + df * ca - dz * sa, pivot[1] + df * sa + dz * ca)


def f_pitch(fn, angle, pivot):
    """fn girada `angle` alrededor del eje lateral que pasa por pivot (fwd, z)."""
    if not angle:
        return fn
    ca, sa = math.cos(-angle), math.sin(-angle)

    def g(lat, fwd, z):
        df, dz = fwd - pivot[0], z - pivot[1]
        return fn(lat, pivot[0] + df * ca - dz * sa, pivot[1] + df * sa + dz * ca)

    return g


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
    """Manchas (4 vecinos) de mask con la misma clave: (etiqueta por pixel, tamaño); −1 = fuera de mask."""
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
    """Lienzo de personaje con búferes propios: light y nz (del motor), layer (índice de LAYER_ORDER),
    keep (dibujado a mano) y lat, fwd (coordenadas del cuerpo, tras measure())."""

    def __init__(self, rotation, look, pose=None, scale=1.0, style=None):
        self.c = iso.Canvas.character(rotation)
        self.look = look
        self.style = style or STYLES[0]
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

    # Vista canónica: mirando a la DERECHA de la pantalla (r1 de frente, r0 de espaldas); las otras
    # dos direcciones son su espejo (x -> 127 − x). La luz se decide por el lado real.

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
        """Agrega una pieza: fn en px del cuerpo, box = (lat0, lat1, fwd0, fwd1, z0, z1) que la contiene."""
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
        """Pinta un bloque desde la esquina (x, y); over = dónde se permite (por defecto lo dibujado)."""
        c = self.c
        mask = (c.X >= x) & (c.X < x + width) & (c.Y >= y) & (c.Y < y + height)
        if over is not None:
            mask &= over
        return self.tone(mask, index, layer, keep)

    def art(self, x, y, rows, legend, over=None, keep=True):
        """Dibujo a mano en la vista canónica desde la esquina (x, y): rows = un carácter por pixel
        (' ' o '.' = no tocar), legend = carácter -> (capa, tono); tono 'darker'/'lighter' = un paso sobre lo de debajo."""
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
        """Máscara de una línea de 1 px por una curva del cuerpo (points = [(lat, fwd, z), …]), solo sobre
        `over` donde queda a la vista y con al menos `minimum` pixeles. No pinta."""
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
        """Silueta limpia: sin puntas (opaco con un solo vecino opaco) ni muescas de 1 px."""
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
        """n·luz con solo la parte horizontal de la normal: bandas verticales limpias en las piernas."""
        lx, ly, lz = iso.LIGHT_DIR
        flat = np.sqrt(np.maximum(1.0 - self.nz ** 2, 1.0e-6))
        return (self.light - self.nz * lz) / flat / math.hypot(lx, ly)

    def shade(self):
        """Tono de cada pixel por bandas de luz según los umbrales de su capa."""
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
        """Funde las manchas de tono de menos de `minimum` pixeles y empareja bordes de banda (3 de 4
        vecinos mandan). No toca keep."""
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
        """Línea un paso más oscura entre piezas de la misma capa que quedaron del mismo tono, en el
        borde de la que está más cerca de la cámara."""
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
        """Contorno de 2 px contra el piso: también la fila de arriba del borde de abajo de los zapatos."""
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
        """Los pixeles sueltos (salvo keep) toman el color más repetido entre sus vecinos."""
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
        # Un pixel de contorno suelto toma el contorno de la capa vecina y se une a la línea.
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

SHOE_LAT = 6.8  # media separación de los zapatos
SHOE = (5.3, -5.6, 10.6, 7.6, 3.7)  # medio ancho, atrás, adelante, alto y radio del zapato
SIT_KNEE_FWD = 14.0  # sentado: la rodilla, hacia adelante de la cadera
SIT_FEET_FWD = 16.0  # sentado: los tobillos
CUFF = 0.72  # la manga larga llega a esta parte del antebrazo (codo → muñeca)
SKIRT_HEM = 19.0  # de pie: alto del ruedo de la falda (la rodilla)
SLEEVE = 0.72  # la manga corta llega a esta parte del brazo (hombro → codo)
HEAD_RADII = (17.0, 17.2, 17.2)  # cabeza grande y redonda


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
        step, lift = pose.foot(sign)
        box = (lat - half, lat + half, back + shift + step, front + shift + step, lift, height + lift)
        angle, pivot = pose.foot_turn(sign)
        reach = abs(angle) * (front - back)
        fig.solid("shoe_" + side, "shoes", f_pitch(f_box(*(box + (radius,))), angle, pivot),
                  box[:4] + (lift, height + lift + reach))
    cut_z = pose.belt_z + BELT_H
    cut = lambda lat, fwd, z: z - cut_z
    if fig.style.skirt:
        build_skirt(fig, cut_z)
    elif pose.sit:
        # Sentado: cadera redonda apoyada en SIT_SEAT_Z, muslos al frente y canillas que bajan.
        thigh_r = 6.6
        cut_z = max(cut_z, SIT_SEAT_Z + 2.0 * thigh_r + 0.3)  # el corte no rebana los muslos
        cut = lambda lat, fwd, z: z - cut_z
        thigh_z = SIT_SEAT_Z + thigh_r
        legs = []
        for sign in (-1.0, 1.0):
            hip = (sign * 5.4, -1.0, thigh_z)
            knee = (sign * 6.0, SIT_KNEE_FWD, thigh_z - 0.5)
            ankle = (sign * SHOE_LAT, SIT_FEET_FWD, 7.0)
            legs.append(f_blend(f_capsule(hip, knee, thigh_r, 6.2), f_capsule(knee, ankle, 6.0, 5.4), 1.5))
        seat = f_box(-11.2, 11.2, -7.0, 6.0, SIT_SEAT_Z, cut_z + 2.0, 5.5)
        body = f_blend(f_blend(legs[0], legs[1], 2.0), seat, 2.0)
        fig.solid("pants", "pants", f_intersect(body, cut),
                  (-13.5, 13.5, -8.5, SIT_FEET_FWD + 7.5, 2.0, cut_z))
    else:
        # Pantalón: cadera y piernas en una pieza (tubos fundidos arriba, cortados en el cinturón), así el
        # sombreado baja seguido; entre los tobillos quedan 3 px.
        both = [stand_leg(pose, sign, 7.0, 6.0, 6.0, pose.belt_z + 10.0) for sign in (-1.0, 1.0)]
        legs = f_blend(both[0], both[1], 2.5)
        reach = STRIDE + 2.0
        fig.solid("pants", "pants", f_intersect(legs, cut), (-14.0, 14.0, -8.5 - reach, 8.5 + reach, 2.0, cut_z))
    # Camisa: el torso es una caja redondeada, un poco más angosta en la cintura.
    fig.solid("torso", "jacket" if fig.style.jacket else "shirt", f_torso(pose, fig.style), (-13.2, 13.2, -8.6, 8.6, pose.belt_z - 4.0, pose.neck_z + 1.5))
    # Manga corta hasta SLEEVE del brazo; el resto del brazo y la mano son una pieza de piel.
    for side, sign in (("l", -1.0), ("r", 1.0)):
        shoulder, elbow, wrist, hand = pose.arm_points(sign)
        radii = pose.arm[4]
        hem = tuple(shoulder[i] + (elbow[i] - shoulder[i]) * SLEEVE for i in range(3))
        skin = f_blend(f_blend(f_capsule(shoulder, elbow, 5.0, 4.4), f_capsule(elbow, wrist, 4.4, 3.9), 1.0),
                       f_ellipsoid(hand, radii), 1.2)
        if sign not in pose.arms:
            # Pulgar: de pie sale hacia adelante; sentado, hacia adentro (sobre el teclado).
            if pose.sit:
                thumb = (hand[0] - sign * 3.6, hand[1] - 1.0, hand[2] + 0.6)
            else:
                thumb = (hand[0] - sign * 1.4, hand[1] + 3.6, hand[2] + 1.6)
            skin = f_blend(skin, f_ellipsoid(thumb, (1.8, 1.9, 2.3)), 0.5)
        points = (shoulder, elbow, wrist, hand)
        box = (min(p[0] for p in points) - 6.2, max(p[0] for p in points) + 6.2,
               min(p[1] for p in points) - 6.2, max(p[1] for p in points) + 6.2,
               min(p[2] for p in points) - 6.2, max(p[2] for p in points) + 6.2)
        fig.solid("hand_" + side, "skin", skin, box)
        if fig.style.long_sleeve:
            cuff = tuple(elbow[i] + (wrist[i] - elbow[i]) * CUFF for i in range(3))
            sleeve = f_blend(f_capsule(shoulder, elbow, 5.5, 5.2), f_capsule(elbow, cuff, 5.2, 4.9), 1.0)
        else:
            sleeve = f_capsule(shoulder, hem, 5.6, 5.4)
        fig.solid("arm_" + side, "jacket" if fig.style.jacket else "shirt", sleeve, box)
    if pose.tool:
        build_mop(fig, pose)
    # Cuello, cabeza y orejas.
    neck, head_z = pose.neck_z, pose.head_z
    fig.solid("neck", "skin", f_capsule((0.0, 0.0, neck - 2.0), (0.0, 0.3, neck + 6.0), 4.3),
              (-4.5, 4.5, -4.5, 4.8, neck - 5.0, neck + 9.0))
    fig.solid("head", "skin", f_ellipsoid((0.0, 0.5, head_z), HEAD_RADII),
              (-HEAD_RADII[0] - 0.3, HEAD_RADII[0] + 0.3, -HEAD_RADII[1] + 0.2, HEAD_RADII[1] + 0.8,
               head_z - HEAD_RADII[2] - 0.2, head_z + HEAD_RADII[2] + 0.2))
    ear = HEAD_RADII[0] + 0.1
    for side, sign in (("l", -1.0), ("r", 1.0)):
        fig.solid("ear_" + side, "skin", f_ellipsoid((sign * ear, -0.5, head_z - 3.5), (2.6, 3.0, 3.8)),
                  (sign * ear - 2.7, sign * ear + 2.7, -3.6, 2.6, head_z - 7.4, head_z + 0.4))
    if hair:
        build_hair(fig)


def build_mop(fig, pose):
    """Suape: palo de top a bottom y la mopa de hilos (un óvalo chato) abajo."""
    lift = pose.bob
    top, bottom, head = ((p[0], p[1], p[2] + lift) for p in (pose.tool["top"], pose.tool["bottom"], pose.tool["head"]))
    points = (top, bottom)
    box = (min(p[0] for p in points) - 2.0, max(p[0] for p in points) + 2.0,
           min(p[1] for p in points) - 2.0, max(p[1] for p in points) + 2.0,
           min(p[2] for p in points) - 2.0, max(p[2] for p in points) + 2.0)
    fig.solid("stick", "stick", f_capsule(top, bottom, STICK_R), box)
    rx, ry, rz = MOP_HEAD
    fig.solid("mop", "mop", f_ellipsoid(head, (rx, ry, rz + 0.6)),
              (head[0] - rx - 0.5, head[0] + rx + 0.5, head[1] - ry - 0.5, head[1] + ry + 0.5,
               max(head[2] - rz - 0.6, 0.0), head[2] + rz + 1.0))


def stand_leg(pose, sign, r_top, r_low, hip_lat, hip_z):
    """Pierna de pie: cadera → rodilla → tobillo; con el pie adelantado o levantado la rodilla se dobla."""
    hip, knee, ankle = leg_axis(pose, sign, hip_lat, hip_z)
    r_mid = (r_top + r_low) / 2.0
    return f_blend(f_capsule(hip, knee, r_top, r_mid), f_capsule(knee, ankle, r_mid, r_low), 1.5)


def leg_axis(pose, sign, hip_lat, hip_z):
    """(cadera, rodilla, tobillo) de una pierna de pie."""
    step, lift = pose.foot(sign)
    angle, pivot = pose.foot_turn(sign)
    fwd, z = turn_point((0.4 + step, 7.5 + lift), angle, pivot)
    ankle = (sign * SHOE_LAT, fwd, z)
    hip = (sign * hip_lat, 0.0, hip_z)
    # La rodilla de la pierna que va en el aire (o despega) sale hacia adelante.
    bend = 1.6 * lift + 0.06 * max(-math.degrees(angle), 0.0)
    knee = ((hip[0] + ankle[0]) / 2.0, (hip[1] + ankle[1]) / 2.0 + bend, (hip[2] + ankle[2]) / 2.0 + 0.3 * lift)
    return hip, knee, ankle


def build_skirt(fig, cut_z):
    """Falda (capa pants) y piernas de piel: de pie campana hasta SKIRT_HEM, sentada hasta la rodilla."""
    pose = fig.pose
    if pose.sit:
        thigh_r = 6.2
        thigh_z = SIT_SEAT_Z + thigh_r
        top = max(cut_z, SIT_SEAT_Z + 2.0 * thigh_r + 0.6)
        front = SIT_KNEE_FWD - 2.5
        lap = f_box(-12.2, 12.2, -7.0, front, SIT_SEAT_Z, top + 3.0, 5.5)
        fig.solid("pants", "pants", f_intersect(lap, lambda lat, fwd, z: z - top),
                  (-13.5, 13.5, -8.5, front + 1.0, SIT_SEAT_Z - 1.0, top))
        for side, sign in (("l", -1.0), ("r", 1.0)):
            thigh = (sign * 5.8, front - 5.0, thigh_z - 0.4)
            knee = (sign * 6.0, SIT_KNEE_FWD, thigh_z - 0.6)
            ankle = (sign * SHOE_LAT, SIT_FEET_FWD, 7.0)
            leg = f_blend(f_capsule(thigh, knee, 5.4, 5.2), f_capsule(knee, ankle, 5.0, 4.5), 1.5)
            fig.solid("leg_" + side, "skin", leg, (sign * 6.0 - 7.0, sign * 6.0 + 7.5, front - 11.0,
                                                    SIT_FEET_FWD + 6.5, 2.0, thigh_z + 6.5))
    else:
        box = f_box(-13.4, 13.4, -9.0, 9.0, SKIRT_HEM, cut_z + 4.0, 3.5)

        def bell(lat, fwd, z):
            k = 1.0 + 0.17 * np.clip((z - SKIRT_HEM) / (cut_z - SKIRT_HEM), 0.0, 1.0)
            return box(lat * k, fwd * k, z)

        fig.solid("pants", "pants", f_intersect(bell, lambda lat, fwd, z: z - cut_z),
                  (-14.4, 14.4, -10.0, 10.0, SKIRT_HEM - 1.0, cut_z))
        for side, sign in (("l", -1.0), ("r", 1.0)):
            leg = stand_leg(pose, sign, 5.2, 4.6, 5.8, SKIRT_HEM + 6.0)
            reach = STRIDE + 2.0
            fig.solid("leg_" + side, "skin", leg, (sign * 6.3 - 6.0, sign * 6.3 + 6.0, -6.0 - reach, 6.5 + reach, 2.0,
                                                    SKIRT_HEM + 8.0 + FOOT_LIFT))


HAIR_OFFSET = (0.0, -1.0, 1.6)  # centro del casquete respecto del centro de la cabeza
HAIR_RADII = (19.1, 19.7, 19.2)
LONG_HAIR = 27.0  # el pelo largo baja esto desde el centro de la cabeza
BOB_HAIR = 19.0  # la melena corta (bob) llega a la barbilla
PART_LAT = 5.6  # la raya del peinado, del lado derecho del personaje


def hair_center(fig):
    return (HAIR_OFFSET[0], HAIR_OFFSET[1], fig.pose.head_z + HAIR_OFFSET[2])


def build_hair(fig):
    """Pelo corto con raya al costado: casquete y flequillo hacia el lado largo."""
    head_z = fig.pose.head_z
    cap = f_ellipsoid(hair_center(fig), HAIR_RADII)

    def hairline(lat, fwd, z):
        # Alta en la frente (si no, tapa la cara), baja en las sienes y hasta la nuca.
        temple = np.clip((np.abs(lat) - 7.5) / 7.5, 0.0, 1.0) * np.clip((fwd + 2.5) / 7.5, 0.0, 1.0)
        line = head_z + 2.0 + fwd * 0.75 - 6.0 * temple
        return (line - z) * 0.8

    kind = fig.style.hair
    if kind == "crop":
        # Al ras: el casquete pegado a la cabeza.
        cap = f_ellipsoid(hair_center(fig), tuple(r - 1.2 for r in HAIR_RADII))
    hair = f_intersect(cap, hairline)
    if kind == "slick":
        # Para atrás: sin flequillo y con más volumen arriba.
        hair = f_blend(hair, f_ellipsoid((0.0, 1.0, head_z + 13.0), (13.0, 14.0, 7.0)), 1.5)
    elif kind != "crop":
        hair = f_union(hair, f_ellipsoid((-2.0, 8.8, head_z + 11.0), (11.5, 6.8, 5.6)))  # flequillo
    low = head_z - 16.0
    back = -21.2
    if kind in ("long", "bob"):
        # Melena: cae por atrás y por los lados hasta los hombros (long) o la barbilla (bob), sin tapar la cara.
        low = head_z - (LONG_HAIR if kind == "long" else BOB_HAIR)
        side = 18.0 if kind == "long" else 18.8
        mane = f_box(-side, side, -19.6, 1.0 if kind == "long" else 3.0, low + 0.5, head_z + 4.0, 7.5)
        hair = f_blend(hair, mane, 1.5)
    fig.solid("hair", "hair", hair, (-20.0, 20.0, back, 19.2, low - 0.5, head_z + 21.2))
    # Moño y cola van en pieza aparte: lines() los separa del casquete con una línea oscura.
    if kind == "bun":
        # Moño redondo alto, atrás de la coronilla: asoma sobre la cabeza también de frente.
        fig.solid("bun", "hair", f_ellipsoid((0.0, -16.5, head_z + 8.0), (7.0, 6.4, 6.4)),
                  (-7.5, 7.5, -23.5, -9.5, head_z + 2.0, head_z + 16.0))
    elif kind == "ponytail":
        # Cola: nace atrás de la coronilla y cae hasta la espalda, angostándose.
        tail = f_blend(f_ellipsoid((0.0, -19.0, head_z + 6.0), (4.6, 4.2, 4.2)),
                       f_capsule((0.0, -20.5, head_z + 4.0), (0.0, -19.5, head_z - 15.0), 4.2, 2.8), 1.5)
        fig.solid("tail", "hair", tail, (-5.0, 5.0, -25.5, -14.0, head_z - 18.5, head_z + 10.5))


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
    """Curvas del peinado en px del cuerpo: la raya y sus mechones, y los que caen hasta la nuca."""
    center = hair_center(fig)
    hz = fig.pose.head_z
    curves = []
    curves.append([hair_top(center, PART_LAT, fwd) for fwd in np.linspace(13.5, -4.0, 18)])
    for start, end, bend in ((9.4, 11.9, 1.9), (2.5, 0.6, 1.25), (-3.75, -9.4, 0.0)):
        curve = []
        for t in np.linspace(0.0, 1.0, 20):
            lat = PART_LAT - 2.5 - t * 18.0
            curve.append(hair_top(center, lat, start + (end - start) * t + bend * math.sin(t * math.pi)))
        curves.append(curve)
    curves.append([hair_top(center, PART_LAT + 2.5 + t * 8.7, 3.75 - 3.1 * t) for t in np.linspace(0.0, 1.0, 12)])
    # Por atrás: tres mechones cortos y curvos de la coronilla a la nuca.
    for lat_top, lat_end, top, bottom in ((-3.75, -13.0, 13.5, -7.5), (1.9, 3.1, 15.0, -4.0), (6.2, 13.7, 12.5, -6.0)):
        curve = []
        for t in np.linspace(0.0, 1.0, 18):
            curve.append(hair_back(center, lat_top + (lat_end - lat_top) * t * t, hz + top + (bottom - top) * t))
        curves.append(curve)
    return curves


def hair_details(fig):
    """Mechones un paso más oscuros y, de espaldas, la nuca en dientes de 2 px."""
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
    # Un pixel de mechón que queda sin otro de su color al lado vuelve a su tono.
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

def volume_details(fig):
    c = fig.c
    pose = fig.pose
    # El cuello queda a la sombra de la cabeza.
    neck = fig.of("neck")
    fig.tone(neck, fig.darker(c.shade))
    style = fig.style
    # Ruedo de la manga corta o puño de la manga larga: el final de la manga, un paso más oscuro.
    for side, sign in (("l", -1.0), ("r", 1.0)):
        shoulder, elbow, wrist, _hand = pose.arm_points(sign)
        start, end, part = (elbow, wrist, CUFF) if style.long_sleeve else (shoulder, elbow, SLEEVE)
        d = (np.array(end) - np.array(start)) * part
        length = float(np.linalg.norm(d))
        along = ((fig.lat - start[0]) * d[0] + (fig.fwd - start[1]) * d[1] + (fig.zb - start[2]) * d[2]) / length
        end_mask = fig.of("arm_" + side) & (along > length + 2.2)
        if style.jacket:
            fig.tone(end_mask, LIGHT, "shirt")  # asoma el puño de la camisa
        else:
            fig.tone(end_mask, fig.darker(c.shade))
    if style.tucked:
        # Cinturón (pantalón) o pretina (falda): la franja de arriba, en el tono del contorno.
        belt = fig.of("pants") & (fig.zb >= pose.belt_z)
        if pose.sit:
            belt &= fig.fwd < 5.5  # sentado, la cara de arriba de los muslos no es cinturón
        fig.tone(belt, OUTLINE if not style.skirt else fig.darker(c.shade))
    elif style.jacket or not style.skirt:
        # Ruedo de la camiseta, un paso más oscuro (el vestido no lo lleva).
        fig.tone(fig.of("torso") & (fig.zb < pose.belt_z + (-1.3 if style.jacket else 1.2)), fig.darker(c.shade))
    if style.skirt:
        # Ruedo de la falda.
        hem = fig.of("pants") & ((fig.fwd > SIT_KNEE_FWD - 4.6) if pose.sit else (fig.zb < SKIRT_HEM + 1.8))
        fig.tone(hem, fig.darker(c.shade))
    if style.collar and not fig.front:
        collar_band(fig)


def collar_band(fig):
    """De espaldas el cuello de la camisa es una banda de 2 px alrededor de la base del cuello."""
    c = fig.c
    neck_z = fig.pose.neck_z
    around = np.sqrt(fig.lat ** 2 + fig.fwd ** 2)
    torso = fig.of("torso")
    band = torso & (around < 7.2) & (fig.zb > neck_z - 2.5)
    fig.tone(band, LIGHT, "shirt" if fig.style.jacket else None)
    under = torso & ~band & (around < 8.6) & (fig.zb > neck_z - 4.0)
    fig.tone(under, fig.darker(c.shade))


def leg_line(fig):
    """Línea entre las piernas: oscurece el pixel de la pierna más cercana donde toca a la otra."""
    c = fig.c
    if fig.style.skirt:
        return np.zeros(c.alpha.shape, dtype=bool)  # las piernas son piezas aparte: las separa lines()
    pants = fig.of("pants")
    if fig.pose.sit:
        legs = pants & ((fig.fwd > 6.0) | (fig.zb < SIT_SEAT_Z - 2.0))
    else:
        legs = pants & (fig.zb < 23.0)
    side = np.where(fig.lat > 0, 1, -1)
    mark = np.zeros(c.alpha.shape, dtype=bool)
    for dy, dx in MOVES4:
        n_legs = shifted(legs, dy, dx, False)
        n_side = shifted(side, dy, dx, 0)
        n_depth = shifted(c.depth, dy, dx, -1.0e9)
        mark |= legs & n_legs & (n_side != side) & (c.depth >= n_depth) & ((c.depth > n_depth) | (side > 0))
    fig.tone(mark, np.where(c.shade <= RIGHT, OUTLINE, DEEP))
    return mark


# ---------------------------------------------------------------------- costuras
# Trazos de 1 px un paso más oscuros (o más claros) sobre la superficie del modelo: se ven en las 4
# direcciones sin dibujarlos a mano. Cada punto va un poco afuera de la superficie (OUT) para que quede
# delante de ella; los que quedan detrás de otra pieza no se pintan.

OUT = 0.35


def seam(fig, over, points, lighter=False, minimum=3):
    """Pinta una costura por points (px del cuerpo) sobre `over`, sin tocar el contorno; devuelve la máscara."""
    c = fig.c
    edge = c.alpha & (neighbours(c.alpha) < 4)
    line = fig.stroke(points, over & ~edge & ~fig.keep & (c.shade >= RIGHT), minimum)
    if not line.any():
        return line
    before = c.shade.copy()
    fig.tone(line, fig.lighter(c.shade) if lighter else fig.darker(c.shade), keep=True)
    # Un pixel de costura sin otro de su color al lado vuelve a su tono (no deja puntos sueltos).
    alone = fig.loose() & line
    c.paint(alone, before)
    fig.keep &= ~alone
    return line & ~alone


def torso_ring(fig, z, front=None, grow=0.0):
    """Puntos de la vuelta del torso a la altura z (de adelante, de atrás o entera)."""
    style, pose = fig.style, fig.pose
    g = (0.5 if style.jacket else 0.0) + grow
    top = pose.neck_z - 5.0
    waist = 1.0 + style.waist * min(max((top - z) / 22.0, 0.0), 1.0)
    a, b = (12.0 + g) / waist + OUT, 7.6 + g + OUT
    if front is None:
        angles = np.linspace(0.0, 2.0 * math.pi, 120)
    elif front:
        angles = np.linspace(0.0, math.pi, 60)
    else:
        angles = np.linspace(math.pi, 2.0 * math.pi, 60)
    pts = []
    for t in angles:
        ct, st = math.cos(t), math.sin(t)
        pts.append((a * math.copysign(abs(ct) ** 0.35, ct), b * math.copysign(abs(st) ** 0.35, st), z))
    return pts


def torso_line(fig, lat, z0, z1, back=False, n=24):
    """Vertical por el frente (o la espalda) del torso."""
    g = 0.5 if fig.style.jacket else 0.0
    fwd = -(7.6 + g + OUT) if back else 7.6 + g + OUT
    return [(lat, fwd, z) for z in np.linspace(z0, z1, n)]


def torso_hline(fig, lat0, lat1, z, back=False, n=16):
    g = 0.5 if fig.style.jacket else 0.0
    fwd = -(7.6 + g + OUT) if back else 7.6 + g + OUT
    return [(lat, fwd, z) for lat in np.linspace(lat0, lat1, n)]


def leg_points(fig, sign, around, t0, t1, n=24):
    """Puntos por la superficie de la pierna de pie (around: 0 = frente, 90 = afuera, 180 = atrás), de la
    cadera (t = 0) al tobillo (t = 1)."""
    pose = fig.pose
    hip, knee, ankle = leg_axis(pose, sign, 6.0, pose.belt_z + 10.0)
    pts = []
    for t in np.linspace(t0, t1, n):
        if t < 0.5:
            a, b, u, r = hip, knee, t / 0.5, 7.0 + (6.5 - 7.0) * t / 0.5
        else:
            a, b, u, r = knee, ankle, (t - 0.5) / 0.5, 6.5 + (6.0 - 6.5) * (t - 0.5) / 0.5
        p = [a[i] + (b[i] - a[i]) * u for i in range(3)]
        ang = math.radians(around)
        pts.append((p[0] + sign * (r + OUT) * math.sin(ang), p[1] + (r + OUT) * math.cos(ang), p[2]))
    return pts


def clothes_details(fig):
    """Costuras, bolsillos y pliegues de cada conjunto."""
    style, pose = fig.style, fig.pose
    torso = fig.of("torso")
    pants = fig.of("pants")
    belt, neck = pose.belt_z, pose.neck_z
    cleaning = style.name in CLEANING_STYLES
    # Torso.
    if style.jacket:
        # Saco: tapas de los bolsillos, bolsillo del pecho, costura y abertura de la espalda.
        for sign in (-1.0, 1.0):
            seam(fig, torso, torso_hline(fig, sign * 3.8, sign * 9.6, belt + 2.5))
        seam(fig, torso, torso_hline(fig, -9.4, -5.6, neck - 11.0))
        seam(fig, torso, torso_line(fig, 0.0, belt - 2.8, neck - 6.0, back=True))
    elif not style.collar:
        # Camiseta y vestido: cuello redondo y costura del hombro.
        ring = [(lat * 0.62, fwd * 0.95, neck + 1.0 + OUT) for lat, fwd, _z in torso_ring(fig, neck, grow=-0.4)]
        seam(fig, torso, ring, minimum=4)
        if style.skirt:
            # Vestido: costura de la cintura y pinzas del pecho.
            seam(fig, torso, torso_ring(fig, belt + 3.6))
            for sign in (-1.0, 1.0):
                seam(fig, torso, torso_line(fig, sign * 5.2, belt + 4.5, belt + 12.0))
    else:
        # Camisa, blusa y overol: canesú de la espalda y la tapeta de los botones.
        seam(fig, torso, torso_hline(fig, -11.5, 11.5, neck - 7.0, back=True))
        if not style.tie:
            seam(fig, torso, torso_line(fig, 0.0, belt + 4.0, neck - 6.5), lighter=cleaning)
        if cleaning:
            # Overol: bolsillo del pecho con su tapa.
            seam(fig, torso, torso_hline(fig, -10.0, -4.5, neck - 9.0))
            for lat in (-10.0, -4.5):
                seam(fig, torso, torso_line(fig, lat, neck - 15.0, neck - 9.0, n=10))
            seam(fig, torso, torso_hline(fig, -10.0, -4.5, neck - 15.0))
        elif not style.skirt:
            seam(fig, torso, torso_hline(fig, -9.6, -5.0, neck - 10.5))  # bolsillo de la camisa
    # Piernas y falda.
    if style.skirt and not pose.sit:
        # Falda: pliegues hacia el ruedo y, atrás, la abertura.
        top = belt + BELT_H - 1.0
        for lat in (-7.5, -2.5, 2.5, 7.5):
            pts = []
            for z in np.linspace(top - 1.0, SKIRT_HEM + 1.5, 20):
                k = 1.0 + 0.17 * min(max((z - SKIRT_HEM) / (belt + BELT_H - SKIRT_HEM), 0.0), 1.0)
                spread = 1.0 + 0.25 * (top - z) / (top - SKIRT_HEM)
                pts.append((lat * spread / k, 9.0 / k + OUT - 3.5 * (abs(lat) / 12.0) ** 4, z))
            seam(fig, pants, pts)
        seam(fig, pants, [(0.0, -(9.0 / 1.0) - OUT, z) for z in np.linspace(SKIRT_HEM + 1.0, SKIRT_HEM + 7.0, 8)])
    elif not style.skirt and not pose.sit:
        casual = style.name == "casual"
        for sign in (-1.0, 1.0):
            if casual:
                # Jean: costura de afuera, bolsillo de adelante y bolsillo de atrás.
                seam(fig, pants, leg_points(fig, sign, 90.0, 0.15, 0.95), lighter=True)
                seam(fig, pants, [(sign * (3.0 + 5.0 * t), 6.8 + OUT - 1.2 * t * t, belt - 0.5 - 5.5 * t * t)
                                  for t in np.linspace(0.0, 1.0, 14)])
                back = -(7.2 + OUT)
                pocket = [(sign * 3.2, back, belt - 1.5), (sign * 3.4, back, belt - 6.5), (sign * 6.0, back, belt - 8.0),
                          (sign * 8.6, back, belt - 6.5), (sign * 8.8, back, belt - 1.5)]
                seam(fig, pants, [p for a, b in zip(pocket, pocket[1:]) for p in
                                  [tuple(a[i] + (b[i] - a[i]) * t for i in range(3)) for t in np.linspace(0, 1, 6)]])
            elif not cleaning:
                # Pantalón de vestir: la raya de adelante.
                seam(fig, pants, leg_points(fig, sign, 0.0, 0.18, 0.92), lighter=True)
        if not casual:
            seam(fig, pants, [(0.0, 7.0 + OUT, z) for z in np.linspace(belt - 1.0, belt - 6.0, 6)])  # bragueta


# ---------------------------------------------------------------------- detalles a mano
# En la vista canónica (se espejan solos); cada uno tiene su versión chica (Figure.k < 0.9),
# dibujada de nuevo, no achicada.

def face(fig):
    """De frente: dos ojos oscuros altos y angostos, cejas del color del pelo y una boca corta (sin nariz)."""
    if not fig.front:
        return
    head = fig.of("head")
    head_z = fig.pose.head_z
    small = fig.k < 0.9
    legend = {"P": ("face", 0), "b": ("hair", RIGHT), "m": ("skin", DEEP)}
    rows = ["PP", "PP", "PP"] if small else ["PP", "PP", "PP", "PP"]
    for sign in (1, -1):
        x, y = fig.canon(sign * fig.near * EYE_LAT, EYE_FWD, head_z + EYE_DZ)
        fig.art(x - 1, y - 1, rows, legend, head)
        if not small:
            fig.art(x - 1, y - 4, ["bbb"], legend, head)  # ceja recta, 3 px sobre el ojo
    if not small:
        # Boca: 3 px entre los ojos y la barbilla (fuera de la sombra de abajo).
        x, y = fig.canon(0.0, EYE_FWD + 1.0, head_z + EYE_DZ - 5.0)
        fig.art(x - 1, y, ["mmm"], legend, head)


def collar_and_tie(fig):
    """Cuello de la camisa con sus dos puntas, la V de piel y la corbata con nudo y punta."""
    style = fig.style
    if not fig.front or not style.collar:
        return
    pose = fig.pose
    small = fig.k < 0.9
    kx, ky = fig.canon(0.0, 7.4, pose.neck_z - 2.5)  # centro del nudo
    cloth = fig.of("torso", "neck")
    legend = {"s": ("skin", LEFT), "C": ("shirt", LIGHT), "c": ("shirt", "darker"),
              "K": ("accent", LEFT), "T": ("accent", BASE), "t": ("accent", RIGHT)}
    if not style.tie:
        legend["K"] = ("skin", LEFT)  # sin corbata: cuello abierto
    if style.jacket:
        # Saco: la V de la camisa entre las solapas (línea oscura), con el nudo y un tramo de corbata.
        legend.update({"L": ("jacket", DEEP), "S": ("shirt", BASE), "B": ("jacket", OUTLINE)})
        if not style.tie:
            legend.update({"T": ("shirt", BASE), "t": ("shirt", BASE)})
        fig.art(kx - 8, ky - 5, [
            ".CCCsssssssCCC..",
            "LCCCCssssssCCCCL",
            ".LSCCCssssCCCSL.",
            "..LSSCCsssCCSL..",
            "...LSSCKKKCSL...",
            "....LSSKKKSL....",
            ".....LSTTtL.....",
            "......LTTtL.....",
            ".......LTL......",
            ".......LL.......",
            "................",
            "................",
            ".......BB.......",
            ".......BB.......",
        ], legend, cloth)
        return
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
    if not style.tie:
        return
    body = fig.of("torso")
    tx, ty = kx - 1, ky + (0 if small else 2)
    length = fig.canon(0.0, 7.4, pose.belt_z + 9.0)[1] - ty
    if small:
        rows = ["Tt"] * 4 + ["TTt"] * max(length - 4, 0) + ["Tt."]
    else:
        rows = ["TTt"] * 6 + ["TTTt"] * max(length - 6, 0) + ["TTt.", ".T.."]
    fig.art(tx, ty, rows, legend, body)
    # Hebilla: bloque de 2×2 en el cinturón, bajo la corbata.
    bx, by = fig.canon(0.0, 7.2, pose.belt_z + 1.8)
    fig.art(bx - 1, by - 1, ["WW", "WW"], {"W": ("face", 1)}, fig.of("pants"))


def hand_details(fig):
    """Pulgar: una rayita de 2 px que lo separa de la palma, del lado del frente (de pie)."""
    if fig.pose.sit or fig.k < 0.9:
        return
    for side, sign in (("l", -1.0), ("r", 1.0)):
        hand = fig.of("hand_" + side)
        if hand.sum() < 12:
            continue
        hx, hy, hz = fig.pose.arm_points(sign)[3]
        x, y = fig.canon(hx + sign * 0.4, hy + 1.6, hz)
        fig.art(x, y, ["n", "n"], {"n": ("skin", "darker")}, hand)


def f_torso(pose, style):
    """Torso robusto: caja muy redondeada, casi recta (camiseta suelta sobre el pantalón)."""
    grow = 0.5 if style.jacket else 0.0  # el saco es un poco más ancho y más largo
    low = -3.0 if style.jacket else (1.0 if style.tucked else -0.5)
    box = f_box(-12.0 - grow, 12.0 + grow, -7.6 - grow, 7.6 + grow, pose.belt_z + low, pose.neck_z + 1.0, 5.5)
    top = pose.neck_z - 5.0

    def fn(lat, fwd, z):
        waist = 1.0 + style.waist * np.clip((top - z) / 22.0, 0.0, 1.0)
        # Hombros caídos: arriba, hacia los lados, el torso baja un poco.
        slope = 0.12 * np.clip(np.abs(lat) - 6.0, 0.0, None)
        return box(lat * waist, fwd, z + slope)

    return fn


# ---------------------------------------------------------------------- armado

EYE_LAT = 4.9  # media separación de los ojos (los dos quedan dentro de la cara vista de 3/4)
EYE_FWD = 14.4  # la cara está sobre la superficie de la cabeza
EYE_DZ = -3.5  # alto de los ojos respecto del centro de la cabeza


def build_one(rotation, look, pose=None, scale=1.0, hair=True, details=True, style=None):
    """Figura terminada del personaje con una rotación (0–3), un Look, una pose y una escala."""
    fig = Figure(rotation, look, pose, scale, style)
    build_model(fig, hair)
    fig.clean_silhouette()
    fig.measure()
    fig.shade()
    volume_details(fig)
    fig.merge_small()
    fig.lines()
    leg_line(fig)
    clothes_details(fig)
    hair_details(fig)
    if details:
        face(fig)
        collar_and_tie(fig)
        hand_details(fig)
    fig.outline()
    fig.ground_line()
    # Un detalle a mano que quedó de un solo pixel (media tapado por la cabeza) deja de protegerse.
    fig.keep &= ~fig.loose()
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
# check.py solo mide formato y lienzo de los personajes; esto mide el resto.

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
    reach = 0.5 * max([abs(pose.foot(sign)[0]) for sign in (-1.0, 1.0)])  # caminando, el pie de adelante baja más
    if pose.tool:
        reach += MOP_REACH  # la mopa en el piso queda más adelante (más abajo en pantalla) que los pies
    if not low_y - reach <= ys.max() + 1 <= low_y + 6 + reach:
        problems.append("la fila más baja es %d (pies en %.1f)" % (ys.max(), low_y))
    tall = FEET[1] - ys.min()
    if not pose.height[0] * fig.k <= tall <= pose.height[1] * fig.k:
        problems.append("mide %d px sobre el apoyo (%d–%d)" % (tall, pose.height[0] * fig.k, pose.height[1] * fig.k))
    shoes_x = xs[layer[ys, xs] == LAYER_ID["shoes"]]
    if shoes_x.size == 0 or (not pose.tool and abs(shoes_x.mean() + 0.5 - low_x) > 3.5):  # el suape tapa un zapato
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


# ---------------------------------------------------------------------- sentado en su silla
# build.py compara profundidades pixel a pixel (misma casilla, centro en (0.5, 0.5)) y guarda por silla la parte
# que queda DELANTE de la persona; export_game.py compone silla + persona + esa parte. Las sillas las dibuja Moana
# (art/furniture/chair_*), que deja junto a cada rotación su profundidad.
CHAIRS = ("chair_basic", "chair_ergonomic")
# El lienzo de la silla tiene el centro de la casilla 16 px más arriba que el del personaje.
CHAIR_SHIFT = 16
# Margen de profundidad (casillas) que la silla le gana a la persona para taparla; con poco, el canto del cojín
# cruza sobre las piernas vistas de frente.
CHAIR_BIAS = 8.0 / 64.0
# <silla>_r<n>_depth.png: profundidad × DEPTH_SCALE − DEPTH_OFFSET (0 = vacío); ver art/furniture/_chair_kit.py.
DEPTH_SCALE = 10000.0
DEPTH_OFFSET = 1.0
