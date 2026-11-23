"""Escritorios de Quincena Office como documentos Moana: modelo, proyección y exportación.

Lo usan los build.py de art/furniture/<escritorio>/. Cada uno da un ``DeskSpec`` (planta en
casillas, lienzo y largo del tablero) y llama a ``main``. Genera, por rotación r0–r3, el mueble
y su sombra (`<nombre>_r<n>.png` y `_shadow.png`, cada uno con su `.moana.json` editable) y el
manifest.json con el apoyo de cada PNG.

El modelo se escribe una vez en rotación 0 (frente con los cajones hacia -y) en unidades de 1/32
de casilla para x e y, y px de sprite para z. Cada caja se gira dentro de la planta y se proyecta
con la regla 2:1 (una unidad = 2 px a lo ancho y 1 hacia abajo). De cada caja se dibujan solo las
caras que miran al espectador: arriba, +y (izquierda en pantalla, -25 %) y +x (derecha, -40 %).
Los detalles (cajones, tiradores, vetas) van pegados a una cara del modelo y solo se dibujan si
esa cara queda a la vista tras girar.

Necesita Moana (no el Python del sistema de tools/sprites).
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

from PIL import Image

from moanart import api

CELL = 32  # unidades por casilla

# Medidas comunes (tools/sprites/pieces/desk.py). Superficie en z = 44 (height 22 x 2).
TOP_Z, SLAB = 44, 6
LEGS_Z = TOP_Z - SLAB
TOP_Y = (2, 22)  # fondo del tablero
PED_LEN = 9  # cajonera, a 1 unidad de la punta +x del tablero
PED_Y = (3, 21)
PED_Z0 = 3  # la cajonera va sobre un zócalo hundido
LEG = 3  # patas a 1 unidad de la punta -x y de los bordes
LEG_YS = (3, 18)
SKIRT_Y0, SKIRT_Z0 = 19, 22  # faldón de atrás, entre la pata de atrás y la cajonera
DRAWERS = ((6, 15), (16, 26), (27, 36))  # frentes separados por 1 px
GRAIN = [(5, 3, 13), (5, 17, 27), (9, 7, 21), (13, 2, 10), (13, 14, 28), (17, 5, 17), (20, 19, 27)]  # (y, x0, x1) cada 30
FOOT = 2  # pie más oscuro al pie de patas y cajonera (px)
EDGE_LINE_Z = LEGS_Z + 2  # línea del canto del tablero
APRON_Z0 = SKIRT_Z0 + 4  # travesaño entre las dos patas
SHADOW_SHIFT = (3, 1)  # la sombra se corre abajo a la derecha (unidades del mundo, tras girar)
SHADOW_INSET = 3

BASE = (0xDF, 0x82, 0x3D)


def shade(rgb: tuple[int, int, int], factor: float) -> str:
    r, g, b = (round(c * factor) for c in rgb)
    return f"#{r:02X}{g:02X}{b:02X}FF"


COLORS = {
    "ink": "#3C1300FF",  # contorno exterior: marrón muy oscuro, no negro
    "ink_in": "#6E2E0CFF",  # líneas entre piezas: más suaves que el contorno exterior
    "wood_light": "#EDA85DFF",  # brillo de 1 px en aristas
    "wood_top": shade(BASE, 1.0),  # cara de arriba: color base
    "wood_grain": "#CE7433FF",  # vetas del tablero
    "wood_left": shade(BASE, 0.75),  # cara izquierda (+y): -25 %
    "wood_right": shade(BASE, 0.60),  # cara derecha (+x): -40 %
    "wood_dark": shade(BASE, 0.42),  # sombra bajo el tablero, ranuras
    "wood_deep": shade(BASE, 0.30),  # zócalo y huecos
    "brass": "#E9B949FF",
    "brass_dark": "#9C6A1EFF",
    "shadow_ink": "#1A1C26FF",  # sombra de piso bajo patas y cajonera
    "shadow_soft": "#4A4E62FF",  # sombra de piso del tablero (el juego la dibuja al 30 %)
}

Point = tuple[int, int]
Vec = tuple[int, int, int]
Op = dict[str, object]

NEG_Y: Vec = (0, -1, 0)
POS_Y: Vec = (0, 1, 0)
POS_X: Vec = (1, 0, 0)
NEG_X: Vec = (-1, 0, 0)


@dataclass
class DeskSpec:
    name: str  # base del nombre de los PNG (desk_simple, desk_long…)
    size: tuple[int, int]  # planta en casillas (ancho x, fondo y) en rotación 0
    canvas: tuple[int, int]  # lienzo en px
    top_x: tuple[int, int] = (0, 0)  # puntas del tablero a lo largo de x (modelo estándar)
    model: Optional[Callable[["DeskSpec"], tuple[list["Box"], "Box"]]] = None  # sin él, ``standard_model``
    colors: Optional[dict[str, str]] = None  # sin ella, ``COLORS``
    contact: tuple[str, ...] = ("pedestal", "leg0", "leg1")  # piezas con sombra de contacto en el piso
    on_top: Optional[Callable[["DeskSpec"], list["Box"]]] = None  # lo que va encima del tablero (computadoras)
    max_colors: int = 16  # la guía pide 8–16 por mueble; un escritorio con su computadora son dos
    seat: Optional[float] = None  # dónde se sienta la persona (casillas desde la punta -x); sin él, el teclado

    def parts(self) -> tuple[list["Box"], "Box"]:
        return (self.model or standard_model)(self)

    def palette(self) -> dict[str, str]:
        return self.colors or COLORS

    def seat_x(self) -> Optional[float]:
        """Centro del teclado a lo largo del modelo, en casillas: ahí dibuja el juego a quien se sienta."""
        if self.seat is not None:
            return self.seat
        parts, _ = self.parts()
        parts = parts + (self.on_top(self) if self.on_top else [])
        keys = [b for b in parts if b.name == "keyboard"]
        return round((keys[0].x0 + keys[0].x1) / 2 / CELL, 4) if keys else None


@dataclass
class View:
    """Rotación y proyección de una planta de w x d unidades en un lienzo; la planta queda pegada abajo."""

    r: int
    w: int
    d: int
    canvas: tuple[int, int]

    @property
    def world(self) -> tuple[int, int]:
        return (self.w, self.d) if self.r % 2 == 0 else (self.d, self.w)

    @property
    def origin(self) -> Point:
        wx, wy = self.world
        return (2 * wy, self.canvas[1] - (wx + wy))

    @property
    def anchor(self) -> list[int]:
        """Centro del rombo de la casilla de anclaje (la de menor x, y), como en el juego."""
        ox, oy = self.origin
        return [ox, oy + CELL]

    def p(self, x: float, y: float, z: float) -> Point:
        ox, oy = self.origin
        return (round(ox + 2 * x - 2 * y), round(oy + x + y - z))

    def rot(self, x: float, y: float) -> tuple[float, float]:
        """r1 lleva el frente (-y) a +x, r2 a +y, r3 a -x."""
        w, d = self.w, self.d
        if self.r == 0:
            return x, y
        if self.r == 1:
            return d - y, x
        if self.r == 2:
            return w - x, d - y
        return y, w - x

    def rot_vec(self, v: Vec) -> Vec:
        x, y, z = v
        for _ in range(self.r):
            x, y = -y, x
        return (x, y, z)

    def visible(self, normal: Vec) -> bool:
        """Se ven la cara de arriba y las verticales que miran hacia +x/+y (también las giradas)."""
        x, y, z = self.rot_vec(normal)
        return z > 0 if z else x + y > 1e-6


def poly(op_id: str, color: str, points: list[Point]) -> Op:
    return {"id": op_id, "type": "polygon", "points": [list(pt) for pt in points], "color": color}


def band(op_id: str, color: str, a: Point, b: Point, rows: int, up: int = 0) -> Op:
    """``rows`` filas de pixel justo debajo de la arista a-b (subida ``up`` filas)."""
    a, b = (a[0], a[1] - up), (b[0], b[1] - up)
    return poly(op_id, color, [a, b, (b[0], b[1] + rows), (a[0], a[1] + rows)])


def vline(op_id: str, color: str, top: Point, bottom: Point) -> Op:
    (x, y0), (_, y1) = top, bottom
    return {"id": op_id, "type": "rect", "box": [x, y0, x + 1, y1], "color": color}


@dataclass
class Decal:
    """Detalle plano pegado a una cara del modelo, con esquinas en coordenadas de rotación 0.

    Con 2 esquinas es un tramo: ``rows`` filas bajo la arista (subido ``up``). Un color que
    empieza con @ depende de hacia dónde quede la cara tras girar (ver ``ROLES``).
    """

    name: str
    color: str
    normal: Vec
    corners: list[tuple[float, float, float]]
    rows: int = 1
    up: int = 0


# Tono de cada papel según la cara en pantalla: así un cajón se sombrea bien en cualquier rotación.
# Cada papel es un tono del material de la caja (``<material>_<tono>``, ver ``material``).
ROLES = {
    "left": {"@face": "left", "@lit": "top", "@dark": "right", "@deep": "deep"},
    "right": {"@face": "right", "@lit": "left", "@dark": "dark", "@deep": "deep"},
    "top": {"@face": "top", "@lit": "light", "@dark": "grain", "@deep": "dark"},
}


def resolve(color: str, normal: Vec, mat: str = "wood") -> str:
    if not color.startswith("@"):
        return color
    x, y, z = normal
    side = "top" if z else ("left" if y >= x else "right")
    return f"{mat}_{ROLES[side][color]}"


def material(name: str, base: tuple[int, int, int], light: str, grain: Optional[str] = None) -> dict[str, str]:
    """Tonos de un material: arriba el color base, izquierda -25 %, derecha -40 %, y sus sombras."""
    return {
        f"{name}_light": light,  # brillo de 1 px en aristas
        f"{name}_top": shade(base, 1.0),
        f"{name}_grain": grain or shade(base, 0.88),  # vetas o líneas sobre la cara de arriba
        f"{name}_left": shade(base, 0.75),
        f"{name}_right": shade(base, 0.60),
        f"{name}_dark": shade(base, 0.42),
        f"{name}_deep": shade(base, 0.30),
    }


@dataclass
class Box:
    name: str
    x0: float
    x1: float
    y0: float
    y1: float
    z0: float
    z1: float
    tone: int = 0  # -1 = una vuelta más oscura (zócalo)
    decals: list[Decal] = field(default_factory=list)
    mat: str = "wood"  # prefijo de sus colores en la paleta
    chamfer: float = 0  # > 0: esquinas verticales cortadas en diagonal (piezas chicas y redondeadas)
    quad: Optional[list[tuple[float, float]]] = None  # planta girada: 4 esquinas (rotación 0) en vez de x0..y1
    ink: str = ""  # prefijo de sus colores de contorno (``<ink>ink`` y ``<ink>ink_in``)

    @classmethod
    def prism(cls, name: str, quad: list[tuple[float, float]], z0: float, z1: float, **kw: object) -> "Box":
        """Pieza de planta cualquiera (cuadrilátero convexo), p. ej. una pantalla girada."""
        xs, ys = [q[0] for q in quad], [q[1] for q in quad]
        return cls(name, min(xs), max(xs), min(ys), max(ys), z0, z1, quad=quad, **kw)  # type: ignore[arg-type]

    def corners(self, v: "View") -> list[tuple[float, float]]:
        assert self.quad is not None
        return [v.rot(x, y) for x, y in self.quad]

    def rotated(self, v: View) -> tuple[float, float, float, float, float, float]:
        if self.quad:
            pts = self.corners(v)
            xs, ys = [q[0] for q in pts], [q[1] for q in pts]
            return min(xs), max(xs), min(ys), max(ys), self.z0, self.z1
        ax, ay = v.rot(self.x0, self.y0)
        bx, by = v.rot(self.x1, self.y1)
        return min(ax, bx), max(ax, bx), min(ay, by), max(ay, by), self.z0, self.z1


def face_rect(normal: Vec, plane: float, u0: float, u1: float, z0: float, z1: float) -> list[tuple[float, float, float]]:
    """Esquinas de un rectángulo vertical sobre el plano y = plane (normal ±y) o x = plane (normal ±x)."""
    if normal[1] != 0:
        return [(u0, plane, z1), (u1, plane, z1), (u1, plane, z0), (u0, plane, z0)]
    return [(plane, u0, z1), (plane, u1, z1), (plane, u1, z0), (plane, u0, z0)]


def side_bands(box: Box, name: str, color: str, z: float, rows: int = 1) -> list[Decal]:
    """Tramo horizontal de ``rows`` filas bajo la altura ``z`` en las cuatro caras laterales de la caja."""
    x0, x1, y0, y1 = box.x0, box.x1, box.y0, box.y1
    sides = {
        "ny": ((0, -1, 0), [(x0, y0, z), (x1, y0, z)]),
        "py": ((0, 1, 0), [(x0, y1, z), (x1, y1, z)]),
        "nx": ((-1, 0, 0), [(x0, y0, z), (x0, y1, z)]),
        "px": ((1, 0, 0), [(x1, y0, z), (x1, y1, z)]),
    }
    return [Decal(f"{name}_{k}", color, normal, corners, rows=rows) for k, (normal, corners) in sides.items()]


def sunken_panel(name: str, normal: Vec, plane: float, a0: float, a1: float, z0: float, z1: float) -> list[Decal]:
    """Tablero rehundido en una cara vertical: ranura oscura arriba y a un lado, brillo en el borde de abajo."""
    if normal[0] != 0:
        edge = [(plane, a0 + 1, z0), (plane, a1, z0)]
    else:
        edge = [(a0 + 1, plane, z0), (a1, plane, z0)]
    return [
        Decal(name, "@dark", normal, face_rect(normal, plane, a0, a1, z0, z1)),
        Decal(f"{name}_in", "@face", normal, face_rect(normal, plane, a0 + 1, a1, z0, z1 - 1)),
        Decal(f"{name}_lit", "@lit", normal, edge, up=1),
    ]


def drawer_pedestal(name: str, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float,
                    drawers: tuple[tuple[int, int], ...], panels: tuple[Vec, ...]) -> Box:
    """Cajonera con los cajones en el frente (-y) y un tablero rehundido en cada cara de ``panels``.

    Los cajones son una pila oscura enmarcada por la cajonera y frentes separados por 1 px, cada uno
    con brillo arriba y un tirador centrado de 4 x 2 px.
    """
    box = Box(name, x0, x1, y0, y1, z0, z1)
    u0, u1 = x0 + 1, x1 - 1
    box.decals.append(Decal("drawer_stack", "@deep", NEG_Y,
                            face_rect(NEG_Y, y0, u0, u1, drawers[0][0] - 1, drawers[-1][1] + 1)))
    pull0 = (x0 + x1) // 2 - 1
    for i, (d0, d1) in enumerate(drawers):
        zc = (d0 + d1) // 2
        box.decals += [
            Decal(f"drawer{i}_front", "@face", NEG_Y, face_rect(NEG_Y, y0, u0, u1, d0, d1)),
            Decal(f"drawer{i}_lit", "@lit", NEG_Y, [(u0, y0, d1), (u1, y0, d1)]),
            Decal(f"drawer{i}_pull", "brass", NEG_Y, face_rect(NEG_Y, y0, pull0, pull0 + 2, zc - 1, zc + 1)),
        ]
    for normal in panels:
        tag = {POS_Y: "py", POS_X: "px", NEG_X: "nx"}[normal]
        if normal[1] != 0:
            plane, a0, a1 = y1, x0, x1
        else:
            plane, a0, a1 = (x1 if normal[0] > 0 else x0), y0, y1
        box.decals += sunken_panel(f"panel_{tag}", normal, plane, a0 + 2, a1 - 2, z0 + 5, z1 - 5)
    return box


def grain(top: Box, z: float, color: str = "wood_grain") -> None:
    """Vetas a lo largo del tablero (x): el dibujo de GRAIN se repite cada 30 unidades."""
    tx0, tx1, ty0 = int(top.x0), int(top.x1), int(top.y0)
    i = 0
    for start in range(tx0, tx1, 30):
        for y, a, b in GRAIN:
            a, b = start + a, min(start + b, tx1 - 2)
            if b - a >= 4 and ty0 + y - TOP_Y[0] < top.y1 - 1:
                top.decals.append(Decal(f"grain{i}", color, (0, 0, 1), [(a, ty0 + y - TOP_Y[0], z), (b, ty0 + y - TOP_Y[0], z)]))
                i += 1


def standard_model(spec: DeskSpec) -> tuple[list[Box], Box]:
    """Escritorio de patas y una cajonera (sencillo y largo), en rotación 0."""
    tx0, tx1 = spec.top_x
    ty0, ty1 = TOP_Y
    px1 = tx1 - 1
    px0 = px1 - PED_LEN
    py0, py1 = PED_Y
    leg_x0 = tx0 + 1

    pedestal = drawer_pedestal("pedestal", px0, px1, py0, py1, PED_Z0, LEGS_Z, DRAWERS, (POS_Y, POS_X))

    legs = [Box(f"leg{i}", leg_x0, leg_x0 + LEG, y0, y0 + LEG, 0, LEGS_Z) for i, y0 in enumerate(LEG_YS)]
    for leg in legs:
        leg.decals += side_bands(leg, "foot", "@dark", FOOT, rows=FOOT)
    skirt = Box("skirt", leg_x0 + LEG, px0, SKIRT_Y0, SKIRT_Y0 + 1, SKIRT_Z0, LEGS_Z)
    skirt.decals += side_bands(skirt, "base", "@dark", SKIRT_Z0 + 1)
    mid = leg_x0 + LEG / 2
    apron = Box("apron", mid - 0.5, mid + 0.5, LEG_YS[0] + LEG, LEG_YS[1], APRON_Z0, LEGS_Z)
    apron.decals += side_bands(apron, "base", "@dark", APRON_Z0 + 1)

    under = [
        Box("plinth", px0 + 1, px1 - 1, py0 + 1, py1 - 1, 0, PED_Z0, tone=-1),
        pedestal,
        skirt,
        apron,
        *legs,
    ]

    top = Box("top", tx0, tx1, ty0, ty1, LEGS_Z, TOP_Z)
    top.decals += side_bands(top, "edge", "@dark", EDGE_LINE_Z)
    grain(top, TOP_Z)
    return under, top


def faces(box: Box, v: View) -> list[Op]:
    """Caras visibles (arriba, izquierda +y, derecha +x), brillo de aristas y detalles de la caja."""
    p = v.p
    x0, x1, y0, y1, z0, z1 = box.rotated(v)
    m = box.mat
    tones = ("top", "left", "right") if box.tone >= 0 else ("dark", "deep", "deep")
    top_c, left_c, right_c = (f"{m}_{t}" for t in tones)
    n = f"{box.name}_r{v.r}"
    if box.chamfer or box.quad:
        maker = prism_faces if box.quad else rounded_faces
        ops = maker(box, v, n, (top_c, left_c, right_c))
        for d in box.decals:
            if v.visible(d.normal):
                pts = [p(*v.rot(cx, cy), cz) for cx, cy, cz in d.corners]
                color = resolve(d.color, v.rot_vec(d.normal), m)
                ops.append(band(f"{n}_{d.name}", color, pts[0], pts[1], d.rows, up=d.up) if len(pts) == 2
                           else poly(f"{n}_{d.name}", color, pts))
        return ops
    ops: list[Op] = [
        poly(f"{n}_left", left_c, [p(x0, y1, z1), p(x1, y1, z1), p(x1, y1, z0), p(x0, y1, z0)]),
        poly(f"{n}_right", right_c, [p(x1, y0, z1), p(x1, y1, z1), p(x1, y1, z0), p(x1, y0, z0)]),
        poly(f"{n}_top", top_c, [p(x0, y0, z1), p(x1, y0, z1), p(x1, y1, z1), p(x0, y1, z1)]),
    ]
    for d in box.decals:
        if not v.visible(d.normal):
            continue
        color = resolve(d.color, v.rot_vec(d.normal), m)
        pts = [p(*v.rot(cx, cy), cz) for cx, cy, cz in d.corners]
        if len(pts) == 2:
            ops.append(band(f"{n}_{d.name}", color, pts[0], pts[1], d.rows, up=d.up))
        else:
            ops.append(poly(f"{n}_{d.name}", color, pts))
    if box.tone == 0:
        # Brillo de 1 px: aristas de arriba hacia el espectador y la esquina de adelante.
        ops += [
            band(f"{n}_lit_left", f"{m}_light", p(x0, y1, z1), p(x1, y1, z1), 1, up=1),
            band(f"{n}_lit_right", f"{m}_light", p(x1, y1, z1), p(x1, y0, z1), 1, up=1),
        ]
        if p(x1, y1, z0)[1] > p(x1, y1, z1)[1]:
            ops.append(vline(f"{n}_lit_corner", f"{m}_light", p(x1, y1, z1), p(x1, y1, z0)))
    return ops


def octagon(box: Box, v: View, z: float, inset: float = 0) -> list[Point]:
    """Planta de una caja con las esquinas cortadas (``chamfer``), proyectada a la altura z."""
    x0, x1, y0, y1, _, _ = box.rotated(v)
    x0, x1, y0, y1 = x0 + inset, x1 - inset, y0 + inset, y1 - inset
    c = min(box.chamfer, (x1 - x0) / 2, (y1 - y0) / 2)
    pts = [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]
    return [v.p(x, y, z) for x, y in pts]


def hull(points: list[Point]) -> list[Point]:
    """Envolvente convexa (cadena monótona)."""
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts

    def cross(o: Point, a: Point, b: Point) -> int:
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list[Point] = []
    upper: list[Point] = []
    for pt in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], pt) <= 0:
            lower.pop()
        lower.append(pt)
    for pt in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], pt) <= 0:
            upper.pop()
        upper.append(pt)
    return lower[:-1] + upper[:-1]


def silhouette(box: Box, v: View) -> list[Point]:
    p = v.p
    x0, x1, y0, y1, z0, z1 = box.rotated(v)
    if box.chamfer:
        return hull(octagon(box, v, z0) + octagon(box, v, z1))
    if box.quad:
        return hull([p(x, y, z) for x, y in box.corners(v) for z in (z0, z1)])
    return [p(x0, y0, z1), p(x1, y0, z1), p(x1, y0, z0), p(x1, y1, z0), p(x0, y1, z0), p(x0, y1, z1)]


def prism_faces(box: Box, v: View, n: str, colors: tuple[str, str, str]) -> list[Op]:
    """Caras de una pieza de planta girada: los lados que miran al espectador y la tapa, con brillo."""
    p = v.p
    _, _, _, _, z0, z1 = box.rotated(v)
    top_c, left_c, right_c = colors
    pts = box.corners(v)
    cx, cy = sum(q[0] for q in pts) / 4, sum(q[1] for q in pts) / 4
    ops: list[Op] = []
    for i in range(4):
        (ax, ay), (bx, by) = pts[i], pts[(i + 1) % 4]
        nx, ny = by - ay, ax - bx  # normal de la arista, hacia afuera
        if nx * ((ax + bx) / 2 - cx) + ny * ((ay + by) / 2 - cy) < 0:
            nx, ny = -nx, -ny
        if nx + ny <= 1e-6:
            continue
        color = left_c if ny >= nx else right_c
        ops.append(poly(f"{n}_side{i}", color, [p(ax, ay, z1), p(bx, by, z1), p(bx, by, z0), p(ax, ay, z0)]))
        ops.append(band(f"{n}_side{i}_lit", f"{box.mat}_light", p(ax, ay, z1), p(bx, by, z1), 1, up=1))
    ops.append(poly(f"{n}_top", top_c, [p(x, y, z1) for x, y in pts]))
    return ops


def rounded_faces(box: Box, v: View, n: str, colors: tuple[str, str, str]) -> list[Op]:
    """Caja de esquinas cortadas: costado en el tono izquierdo, la cara +x derecha, arriba y un brillo."""
    p = v.p
    x0, x1, y0, y1, z0, z1 = box.rotated(v)
    top_c, left_c, right_c = colors
    c = min(box.chamfer, (x1 - x0) / 2, (y1 - y0) / 2)
    ops = [poly(f"{n}_side", left_c, silhouette(box, v))]
    if y1 - y0 > 2 * c:
        ops.append(poly(f"{n}_right", right_c, [p(x1, y0 + c, z1), p(x1, y1 - c, z1), p(x1, y1 - c, z0), p(x1, y0 + c, z0)]))
    ops.append(poly(f"{n}_top", top_c, octagon(box, v, z1)))
    ops.append(poly(f"{n}_shine", f"{box.mat}_light", octagon(box, v, z1, inset=max(0.5, (min(x1 - x0, y1 - y0)) / 2 - 0.5))))
    return ops


MOVES = {"n": (0, -1), "s": (0, 1), "w": (-1, 0), "e": (1, 0)}


def outline(box: Box, v: View, color: str = "ink_in", tag: str = "ink") -> list[Op]:
    """Contorno de 1 px: la silueta corrida un pixel en las cuatro direcciones. Va justo antes de
    las caras de su pieza, así marca también el borde contra las piezas de atrás (en tono suave;
    el borde exterior del mueble lo repasa después ``outer_ink`` en el tono fuerte)."""
    shape = silhouette(box, v)
    color = box.ink + color
    return [
        poly(f"{box.name}_r{v.r}_{tag}_{k}", color, [(x + dx, y + dy) for x, y in shape])
        for k, (dx, dy) in MOVES.items()
    ]


def depth(box: Box, v: View) -> tuple[float, float]:
    x0, x1, y0, y1, z0, _ = box.rotated(v)
    return (x0 + x1 + y0 + y1, z0)


def doc(spec: DeskSpec, doc_id: str, masks: list[Op], layers: list[Op]) -> dict[str, object]:
    return {
        "schema_version": "1.0",
        "id": doc_id,
        "revision": 0,
        "seed": 0,
        "canvas": {"width": spec.canvas[0], "height": spec.canvas[1], "profile": "strict"},
        "palette": {"id": f"palette_{spec.name}", "colors": [{"id": k, "rgba": c} for k, c in spec.palette().items()], "ramps": []},
        "masks": masks,
        "layers": layers,
    }


def view(spec: DeskSpec, r: int) -> View:
    return View(r, spec.size[0] * CELL, spec.size[1] * CELL, spec.canvas)


def contact_ops(parts: list[Box], names: tuple[str, ...], v: View, z: float, color: str,
                shift: tuple[float, float] = (1, 0)) -> list[Op]:
    """Sombra de contacto: planta de cada pieza nombrada, 1 unidad más ancha y corrida, a la altura z."""
    p = v.p
    ops = []
    for b in parts:
        if b.name not in names:
            continue
        x0, x1, y0, y1, _, _ = b.rotated(v)
        x0, x1, y0, y1 = x0 - 1 + shift[0], x1 + 1 + shift[0], y0 - 1 + shift[1], y1 + 1 + shift[1]
        ops.append(poly(f"contact_{b.name}", color, [p(x0, y0, z), p(x1, y0, z), p(x1, y1, z), p(x0, y1, z)]))
    return ops


def outer_ink(spec: DeskSpec, pieces: list[Box], v: View) -> tuple[list[Op], list[Op]]:
    """Máscara ``outside`` (el lienzo menos la silueta de cada pieza) y el contorno fuerte de cada pieza."""
    masks = [{"id": f"sil_{b.name}", "type": "polygon", "points": [list(pt) for pt in silhouette(b, v)]} for b in pieces]
    masks += [
        {"id": "canvas_all", "type": "rect", "box": [0, 0, spec.canvas[0], spec.canvas[1]]},
        {"id": "outside", "type": "subtract", "masks": ["canvas_all", *[f"sil_{b.name}" for b in pieces]]},
    ]
    return masks, [op for b in pieces for op in outline(b, v, "ink", "outer")]


def desk_document(spec: DeskSpec, r: int) -> dict[str, object]:
    v = view(spec, r)
    p = v.p
    under, top = spec.parts()
    under = sorted(under, key=lambda b: depth(b, v))  # de atrás hacia adelante
    body = [op for b in under for op in [*outline(b, v), *faces(b, v)]]

    # Sombra del tablero: 2 filas oscuras bajo sus aristas, solo sobre las caras de lo de abajo.
    x0, x1, y0, y1, z0, _ = top.rotated(v)
    receivers: list[Op] = []
    for b in under:
        bx0, bx1, by0, by1, bz0, bz1 = b.rotated(v)
        receivers.append({"id": f"recv_{b.name}_left", "type": "polygon",
                          "points": [list(pt) for pt in [p(bx0, by1, bz1), p(bx1, by1, bz1), p(bx1, by1, bz0), p(bx0, by1, bz0)]]})
        receivers.append({"id": f"recv_{b.name}_right", "type": "polygon",
                          "points": [list(pt) for pt in [p(bx1, by0, bz1), p(bx1, by1, bz1), p(bx1, by1, bz0), p(bx1, by0, bz0)]]})
    masks = [*receivers, {"id": "under_top", "type": "union", "masks": [m["id"] for m in receivers]}]
    # Fuera del mueble: todo el lienzo menos la silueta de cada pieza.
    above = sorted(spec.on_top(spec), key=lambda b: depth(b, v)) if spec.on_top else []
    pieces = [*under, top, *above]
    outer_masks, outer = outer_ink(spec, pieces, v)
    masks += outer_masks
    under_shadow = [
        band("under_left", "wood_dark", p(x0, y1, z0), p(x1, y1, z0), 2),
        band("under_right", "wood_dark", p(x1, y1, z0), p(x1, y0, z0), 2),
    ]

    layers = [
        {"id": "body", "name": "Patas, faldón y cajonera", "operations": body},
        {"id": "under_shadow", "name": "Sombra del tablero", "mask_id": "under_top", "operations": under_shadow},
        {"id": "tabletop", "name": "Tablero", "operations": [*outline(top, v), *faces(top, v)]},
    ]
    if above:
        # Sombra de contacto de lo de encima, recortada al tablero, y luego las piezas.
        masks.append({"id": "top_face", "type": "polygon",
                      "points": [list(pt) for pt in [p(x0, y0, top.z1), p(x1, y0, top.z1), p(x1, y1, top.z1), p(x0, y1, top.z1)]]})
        layers += [
            {"id": "on_top_contact", "name": "Sombra sobre el tablero", "mask_id": "top_face",
             "operations": contact_ops(above, spec.contact, v, top.z1, "wood_shade")},
            {"id": "on_top", "name": "Encima del tablero", "operations": [op for b in above for op in [*outline(b, v), *faces(b, v)]]},
        ]
    layers.append({"id": "outer_ink", "name": "Contorno exterior", "mask_id": "outside", "operations": outer})
    return doc(spec, f"{spec.name}_r{r}", masks, layers)


def shadow_document(spec: DeskSpec, r: int) -> dict[str, object]:
    """Planta de cajonera, patas y centro del tablero, corrida abajo a la derecha y recortada a la planta."""
    v = view(spec, r)
    p = v.p
    under, top = spec.parts()
    i = SHADOW_INSET
    inner = Box("top_inner", top.x0 + i, top.x1 - i, top.y0 + i, top.y1 - i, 0, 0)
    feet = [b for b in under if b.name in spec.contact]
    sx, sy = SHADOW_SHIFT
    ops: list[Op] = []
    # Tablero: mancha suave corrida con la luz. Patas y cajonera: contacto oscuro 1 unidad más ancho.
    for b, color, grow, shift in [(inner, "shadow_soft", 0, (sx, sy))] + [(b, "shadow_ink", 1, (1, 0)) for b in feet]:
        x0, x1, y0, y1, _, _ = b.rotated(v)
        x0, x1, y0, y1 = x0 - grow + shift[0], x1 + grow + shift[0], y0 - grow + shift[1], y1 + grow + shift[1]
        ops.append(poly(f"shadow_{b.name}", color, [p(x0, y0, 0), p(x1, y0, 0), p(x1, y1, 0), p(x0, y1, 0)]))
    wx, wy = v.world
    floor = {"id": "floor_footprint", "type": "polygon",
             "points": [list(pt) for pt in [p(0, 0, 0), p(wx, 0, 0), p(wx, wy, 0), p(0, wy, 0)]]}
    layers = [{"id": "shadow", "name": "Sombra", "mask_id": "floor_footprint", "operations": ops}]
    return doc(spec, f"{spec.name}_r{r}_shadow", [floor], layers)


def render(spec: DeskSpec, document: dict[str, object]) -> Image.Image:
    result = api.render(api.load_document(document))
    return Image.frombytes("RGBA", spec.canvas, bytes(result.rgba))


def check(spec: DeskSpec, name: str, image: Image.Image) -> list[str]:
    """Reglas de la guía que se pueden medir: tamaño, alfa 0/255 y como mucho 16 colores."""
    problems = []
    if image.size != spec.canvas:
        problems.append(f"{name}: mide {image.size}, no {spec.canvas}")
    pixels = list(image.getdata())
    if {a for *_, a in pixels} - {0, 255}:
        problems.append(f"{name}: alfa distinto de 0 y 255")
    colors = {px for px in pixels if px[3] == 255}
    if len(colors) > spec.max_colors:
        problems.append(f"{name}: {len(colors)} colores (máx. {spec.max_colors})")
    return problems


def preview(spec: DeskSpec, images: list[Image.Image], path: Path, scale: int = 4) -> None:
    """Fila de arriba: el mueble de cada rotación sobre su sombra al 30 %; abajo, las sombras solas."""
    bg = (235, 235, 235, 255)
    cw, ch = spec.canvas
    sheet = Image.new("RGBA", (cw * 4 * scale, ch * 2 * scale), bg)
    for r in range(4):
        desk, shadow = images[2 * r], images[2 * r + 1]
        cell = Image.new("RGBA", spec.canvas, bg)
        faint = shadow.copy()
        faint.putalpha(shadow.getchannel("A").point(lambda a: 77 if a else 0))
        cell.alpha_composite(faint)
        cell.alpha_composite(desk)
        sheet.paste(cell.resize((cw * scale, ch * scale), Image.NEAREST), (r * cw * scale, 0))
        alone = Image.new("RGBA", spec.canvas, bg)
        alone.alpha_composite(shadow)
        sheet.paste(alone.resize((cw * scale, ch * scale), Image.NEAREST), (r * cw * scale, ch * scale))
    sheet.save(path)


Documents = Callable[[DeskSpec, int], dict[str, object]]


def main(spec: DeskSpec, here: Path, document: Optional[Documents] = None, shadow: Optional[Documents] = None) -> int:
    """Genera las 4 rotaciones y sus sombras (por defecto, como escritorio) y el manifest.json."""
    document = document or desk_document
    shadow = shadow or shadow_document
    parser = argparse.ArgumentParser(description=f"Genera {spec.name} (4 rotaciones y sus sombras) con Moana.")
    parser.add_argument("--out", type=Path, default=here, help="carpeta de salida (por defecto, la del build.py)")
    parser.add_argument("--preview", action="store_true", help=f"escribe también {spec.name}_preview.png")
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)

    images: list[Image.Image] = []
    problems: list[str] = []
    anchors: dict[str, dict[str, list[int]]] = {}
    for r in range(4):
        anchor = view(spec, r).anchor
        for name, built in ((f"{spec.name}_r{r}", document(spec, r)), (f"{spec.name}_r{r}_shadow", shadow(spec, r))):
            (out / f"{name}.moana.json").write_text(json.dumps(built, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            image = render(spec, built)
            image.save(out / f"{name}.png")
            images.append(image)
            anchors[f"{name}.png"] = {"anchor": anchor}
            problems += check(spec, name, image)
            print(f"{name}.png  apoyo {anchor}  recuadro {image.getbbox()}")
    manifest: dict[str, object] = {
        "_comentario": "Apoyo (px del sprite) de cada PNG de esta carpeta y, si tiene, dónde se sienta la persona "
                       "(seat, casillas desde la punta -x del modelo); lo escribe build.py y export_game.py lo pasa "
                       "al juego.", "sprites": anchors}
    if spec.seat_x() is not None:
        manifest["seats"] = {spec.name: spec.seat_x()}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.preview:
        preview(spec, images, out / f"{spec.name}_preview.png")
        print("vista previa", out / f"{spec.name}_preview.png")
    for line in problems:
        print("FALLO:", line)
    print("RESULTADO:", "OK" if not problems else f"{len(problems)} fallos")
    return 1 if problems else 0
