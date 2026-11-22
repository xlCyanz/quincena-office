"""Sillas y plantas con Moana: modelo de sólidos convexos, rasterizado propio y documento por tonos.

Las sillas son curvas (cojín abultado, ruedas, columna), así que no se arman con las cajas de
``_desk_kit``: cada pieza es un sólido convexo de caras planas (prisma de planta redondeada, cilindro,
hexaedro de 8 esquinas). Las caras se pintan con z-buffer por pixel, con la misma profundidad que el
generador de personajes (u + v + z / 64, en casillas), y de ahí salen:

- el tono de cada pixel (según hacia dónde mira la cara) y los detalles por coordenadas del modelo
  (costura del cojín, malla del respaldo);
- el contorno: oscuro por fuera de la silueta y suave donde una pieza tapa a otra;
- las capas asiento y respaldo (el juego dibuja el respaldo encima en r0 y r3, debajo en r1 y r2);
- ``<nombre>_r<n>_depth.png``: profundidad por pixel (16 bits) para saber qué parte de la silla tapa
  a quien se sienta (``tools/sprites/pieces/character.py``).

El documento Moana lleva una capa por tono con un rectángulo por tramo horizontal; ``build.py`` comprueba
que Moana dé los mismos pixeles. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/<silla>/build.py [--out DIR] [--preview]
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

import numpy as np
from PIL import Image

import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from _desk_kit import View  # noqa: E402
from _painter import document as painter_document  # noqa: E402
from moana import api  # noqa: E402

CELL = 32  # unidades por casilla
CANVAS = (128, 128)
BACK_ON_TOP = (0, 3)  # rotaciones en que el juego dibuja el respaldo encima del asiento
BACK_GROUP = "back"
SEAT_GROUP = "seat"
DEPTH_SCALE = 10000.0  # profundidad (casillas) × esto en el PNG de 16 bits
DEPTH_OFFSET = 1.0  # casillas: así la profundidad guardada nunca es negativa
EMPTY = -1.0e9
GAP = 2.0 / 64.0  # casillas que una pieza debe estar delante de otra para marcar la línea entre ellas
SHADOW_SHIFT = (0.10, 0.03)  # corrimiento de la sombra (casillas) por cada 64 px de alto

Vec3 = tuple[float, float, float]


# ---------------------------------------------------------------------------- materiales

@dataclass
class Mat:
    """Tonos de un material: de arriba (``top``) a la cara derecha (``right``), más brillo, sombra y contorno."""

    name: str
    light: str
    top: str
    upper: str
    left: str
    right: str
    dark: str
    ink: str

    def tones(self) -> dict[str, str]:
        return {k: getattr(self, k) for k in ("light", "top", "upper", "left", "right", "dark", "ink")}


# Brillo de cada tono (para elegir el de una cara inclinada).
LEVELS = (("top", 1.0), ("upper", 0.87), ("left", 0.75), ("right", 0.6))


def face_tone(n: np.ndarray) -> str:
    """Tono de una cara según su normal ya girada: arriba 1.0, cara +y 0.75, cara +x 0.6, y entre medio."""
    nx, ny, nz = n
    side = 0.6 + 0.15 * (max(ny, 0.0) / max(max(nx, 0.0) + max(ny, 0.0), 1e-9))
    value = max(nz, 0.0) * 1.0 + (1.0 - max(nz, 0.0)) * side
    return min(LEVELS, key=lambda t: abs(t[1] - value))[0]


# ---------------------------------------------------------------------------- sólidos

@dataclass
class Solid:
    """Sólido convexo: caras planas (esquinas en rotación 0) y el centro, para orientar las normales."""

    part: str
    group: str
    mat: str
    faces: list[list[Vec3]]
    center: Vec3
    lit: bool = False  # brillo de 1 px en el borde de arriba de sus caras de arriba
    two_sided: bool = False  # hoja: se ven las dos caras (la normal se da vuelta hacia quien mira)
    texture: Optional[Callable[[np.ndarray, np.ndarray, np.ndarray, np.ndarray], np.ndarray]] = None
    # texture(x, y, z, tono) -> tono: detalles por coordenadas del modelo (costuras, malla)


def _rounded_rect(cx: float, cy: float, hx: float, hy: float, r: float, steps: int = 3) -> list[tuple[float, float]]:
    pts = []
    r = min(r, hx, hy)
    for qx, qy, a0 in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        ox, oy = cx + qx * (hx - r), cy + qy * (hy - r)
        for k in range(steps + 1):
            a = math.radians(a0 + 90 * k / steps)
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    return pts


def _ring_faces(lower: list[Vec3], upper: list[Vec3]) -> list[list[Vec3]]:
    n = len(lower)
    return [[lower[i], lower[(i + 1) % n], upper[(i + 1) % n], upper[i]] for i in range(n)]


def slab(part: str, group: str, mat: str, cx: float, cy: float, hx: float, hy: float, r: float,
         z0: float, z1: float, bevel: float = 0.0, bevel_z: float = 0.0, **kw: object) -> Solid:
    """Prisma de planta redondeada de z0 a z1; con ``bevel`` la tapa entra esas unidades en los
    últimos ``bevel_z`` px (cojín abultado)."""
    outer = _rounded_rect(cx, cy, hx, hy, r)
    zs = z1 - bevel_z if bevel else z1
    lower = [(x, y, z0) for x, y in outer]
    mid = [(x, y, zs) for x, y in outer]
    faces = [lower[::-1]] + _ring_faces(lower, mid)
    top = mid
    if bevel:
        inner = [(x, y, z1) for x, y in _rounded_rect(cx, cy, hx - bevel, hy - bevel, max(r - bevel, 0.5))]
        faces += _ring_faces(mid, inner)
        top = inner
    faces.append(top)
    return Solid(part, group, mat, faces, (cx, cy, (z0 + z1) / 2), **kw)  # type: ignore[arg-type]


def upright(part: str, group: str, mat: str, cx: float, hx: float, y0: float, y1: float, z0: float, z1: float,
            r: float, bevel: float = 0.0, **kw: object) -> Solid:
    """Placa vertical de cara redondeada en x–z (respaldo), de y0 a y1; ``bevel`` achica las dos caras
    grandes esas unidades para que el canto se vea redondo."""
    # La placa se dibuja en x–z con z a la mitad (1 unidad = 2 px de alto), así el radio sale parejo.
    cz, hz = (z0 + z1) / 2, (z1 - z0) / 2
    ym = (y0 + y1) / 2

    def ring(y: float, inset: float) -> list[Vec3]:
        pts = _rounded_rect(cx, 0.0, hx - inset, hz / 2 - inset / 2, max(r - inset, 0.5))
        return [(x, y, cz + z * 2) for x, z in pts]

    if bevel:
        front, mid_front, mid_back, back = ring(y0, bevel), ring(y0 + bevel, 0), ring(y1 - bevel, 0), ring(y1, bevel)
        faces = [front, back[::-1]] + _ring_faces(front, mid_front) + _ring_faces(mid_front, mid_back) \
            + _ring_faces(mid_back, back)
    else:
        front, back = ring(y0, 0), ring(y1, 0)
        faces = [front, back[::-1]] + _ring_faces(front, back)
    return Solid(part, group, mat, faces, (cx, ym, cz), **kw)  # type: ignore[arg-type]


def cylinder(part: str, group: str, mat: str, cx: float, cy: float, r: float, z0: float, z1: float,
             sides: int = 10, r_top: Optional[float] = None, **kw: object) -> Solid:
    """Cilindro (o tronco de cono con ``r_top``) vertical de z0 a z1."""
    top = r if r_top is None else r_top

    def ring(radius: float, z: float) -> list[Vec3]:
        return [(cx + radius * math.cos(2 * math.pi * k / sides), cy + radius * math.sin(2 * math.pi * k / sides), z)
                for k in range(sides)]

    lower, upper = ring(r, z0), ring(top, z1)
    return Solid(part, group, mat, [lower[::-1], upper] + _ring_faces(lower, upper), (cx, cy, (z0 + z1) / 2),
                 **kw)  # type: ignore[arg-type]


def beam(part: str, group: str, mat: str, a: Vec3, b: Vec3, half_w: float, half_h: float, **kw: object) -> Solid:
    """Barra de sección rectangular de a a b (ancho horizontal 2·half_w unidades, alto 2·half_h px)."""
    ax, ay, az = a
    bx, by, bz = b
    dx, dy = bx - ax, by - ay
    length = math.hypot(dx, dy) or 1.0
    sx, sy = -dy / length * half_w, dx / length * half_w
    corners = []
    for px, py, pz in (a, b):
        corners.append([(px + sx, py + sy, pz - half_h), (px - sx, py - sy, pz - half_h),
                        (px - sx, py - sy, pz + half_h), (px + sx, py + sy, pz + half_h)])
    lo, hi = corners
    faces = [lo[::-1], hi] + _ring_faces(lo, hi)
    center = ((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2)
    return Solid(part, group, mat, faces, center, **kw)  # type: ignore[arg-type]


# ---------------------------------------------------------------------------- rasterizado

@dataclass
class Frame:
    """Lo que queda de pintar unas piezas: tono (nombre ``mat.tono``), pieza, grupo, profundidad y
    coordenadas del modelo por pixel."""

    tone: np.ndarray
    part: np.ndarray
    group: np.ndarray
    depth: np.ndarray
    lit_top: np.ndarray


def _affine(screen: list[tuple[float, float]], values: list[float]) -> tuple[float, float, float]:
    """Coeficientes (a, b, c) de value = a·sx + b·sy + c por tres puntos no alineados de la cara."""
    n = len(screen)
    best = None
    for i in range(n):
        for j in range(i + 1, n):
            for k in range(j + 1, n):
                (x0, y0), (x1, y1), (x2, y2) = screen[i], screen[j], screen[k]
                det = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
                if best is None or abs(det) > abs(best[0]):
                    best = (det, i, j, k)
    det, i, j, k = best  # type: ignore[misc]
    m = np.array([[screen[i][0], screen[i][1], 1.0], [screen[j][0], screen[j][1], 1.0],
                  [screen[k][0], screen[k][1], 1.0]])
    return tuple(np.linalg.solve(m, np.array([values[i], values[j], values[k]])))  # type: ignore[return-value]


def render(solids: list[Solid], v: View, canvas: tuple[int, int] = CANVAS) -> Frame:
    w, h = canvas
    ys, xs = np.mgrid[0:h, 0:w]
    sx, sy = xs + 0.5, ys + 0.5
    tone = np.full((h, w), "", dtype=object)
    part = np.full((h, w), "", dtype=object)
    group = np.full((h, w), "", dtype=object)
    depth = np.full((h, w), EMPTY)
    lit_top = np.zeros((h, w), dtype=bool)
    ox, oy = v.origin
    view_dir = np.array([1 / CELL, 1 / CELL, 1 / 64.0])
    for solid in solids:
        cx, cy = v.rot(solid.center[0], solid.center[1])
        center = np.array([cx, cy, solid.center[2]])
        for face in solid.faces:
            pts = np.array([[*v.rot(x, y), z] for x, y, z in face])
            normal = np.cross(pts[1] - pts[0], pts[2] - pts[0])
            if np.linalg.norm(normal) < 1e-9:
                normal = np.cross(pts[2] - pts[0], pts[-1] - pts[0])
            normal = normal / (np.linalg.norm(normal) or 1.0)
            if solid.two_sided:
                if np.dot(normal, view_dir) < 0:
                    normal = -normal
            elif np.dot(normal, pts.mean(axis=0) - center) < 0:
                normal = -normal
            # El modelo mide z en px y x, y en unidades de 2 px: la normal "real" pesa z a la mitad.
            real = normal * np.array([1.0, 1.0, 0.5])
            real = real / np.linalg.norm(real)
            if np.dot(normal, view_dir) <= 1e-9:
                continue
            screen = [(ox + 2 * x - 2 * y, oy + x + y - z) for x, y, z in pts]
            inside = np.ones((h, w), dtype=bool)
            area = 0.0
            for i in range(len(screen)):
                (ax, ay), (bx, by) = screen[i], screen[(i + 1) % len(screen)]
                area += ax * by - bx * ay
            sign = 1.0 if area > 0 else -1.0
            for i in range(len(screen)):
                (ax, ay), (bx, by) = screen[i], screen[(i + 1) % len(screen)]
                inside &= sign * ((bx - ax) * (sy - ay) - (by - ay) * (sx - ax)) >= -1e-9
            if not inside.any():
                continue
            d_vals = [(x + y) / CELL + z / 64.0 for x, y, z in pts]
            a, b, c = _affine(screen, d_vals)
            d = a * sx + b * sy + c
            win = inside & (d > depth + 1e-9)
            if not win.any():
                continue
            name = face_tone(real)
            ftone = np.full((h, w), f"{solid.mat}.{name}", dtype=object)
            if solid.texture is not None:
                coords = []
                for axis in range(3):
                    ca, cb, cc = _affine(screen, [float(p[axis]) for p in pts])
                    coords.append(ca * sx + cb * sy + cc)
                # Coordenadas del modelo en rotación 0: se deshace el giro de x, y.
                mx, my = _unrotate(v, coords[0], coords[1])
                ftone = solid.texture(mx, my, coords[2], ftone)
            tone[win] = ftone[win]
            part[win] = solid.part
            group[win] = solid.group
            depth[win] = d[win]
            lit_top[win] = solid.lit and name == "top"
    return Frame(tone, part, group, depth, lit_top)


def _unrotate(v: View, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    w, d = v.w, v.d
    if v.r == 0:
        return x, y
    if v.r == 1:
        return y, d - x
    if v.r == 2:
        return w - x, d - y
    return w - y, x


NEIGHBORS4 = ((-1, 0), (1, 0), (0, -1), (0, 1))


def _shift(arr: np.ndarray, dy: int, dx: int, fill: object) -> np.ndarray:
    out = np.full_like(arr, fill)
    h, w = arr.shape
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = arr[max(-dy, 0):h + min(-dy, 0),
                                                                    max(-dx, 0):w + min(-dx, 0)]
    return out


def finish(frame: Frame, mats: dict[str, Mat]) -> Frame:
    """Brillo de 1 px arriba, línea suave donde una pieza tapa a otra y contorno oscuro por fuera."""
    tone, part, group, depth = frame.tone.copy(), frame.part.copy(), frame.group.copy(), frame.depth.copy()
    filled = depth > EMPTY / 2
    mat_of = np.vectorize(lambda t: t.split(".")[0] if t else "")(tone)
    # Brillo: pixel de cara de arriba con luz cuyo vecino de arriba no es de la misma pieza.
    up_part = _shift(part, 1, 0, "")
    lit = frame.lit_top & (up_part != part)
    tone[lit] = np.vectorize(lambda m: f"{m}.light")(mat_of[lit]) if lit.any() else tone[lit]
    # Línea entre piezas: en la pieza de atrás, junto a una que está delante.
    seam = np.zeros_like(filled)
    for dy, dx in NEIGHBORS4:
        n_part = _shift(part, dy, dx, "")
        n_depth = _shift(depth, dy, dx, EMPTY)
        seam |= filled & (n_part != "") & (n_part != part) & (n_depth > depth + GAP)
    if seam.any():
        tone[seam] = np.vectorize(lambda m: f"{m}.dark")(mat_of[seam])
    # Contorno de afuera: 1 px alrededor de la silueta, del tono de contorno de la pieza vecina más cercana.
    best_depth = np.full(depth.shape, EMPTY)
    for dy, dx in NEIGHBORS4:
        n_depth = _shift(depth, dy, dx, EMPTY)
        n_mat = _shift(mat_of, dy, dx, "")
        n_part = _shift(part, dy, dx, "")
        n_group = _shift(group, dy, dx, "")
        take = ~filled & (n_depth > best_depth)
        best_depth[take] = n_depth[take]
        tone[take] = np.vectorize(lambda m: f"{m}.ink")(n_mat[take]) if take.any() else tone[take]
        part[take] = n_part[take]
        group[take] = n_group[take]
    ring = ~filled & (best_depth > EMPTY / 2)
    depth[ring] = best_depth[ring]
    return Frame(tone, part, group, depth, frame.lit_top)


# ---------------------------------------------------------------------------- silla

@dataclass
class ChairSpec:
    name: str
    mats: dict[str, Mat]
    model: Callable[[], list[Solid]]
    shadow: list[tuple]  # ("disc", x, y, r, z0, z1) o ("bar", x0, y0, x1, y1, r, z0, z1), en unidades
    shadow_color: str = "#1A1C26FF"
    max_colors: int = 16

    def palette(self) -> list[tuple[str, str]]:
        """(nombre ``mat.tono``, rgba) sin repetir colores."""
        seen: dict[str, str] = {}
        for m in self.mats.values():
            for k, hexa in m.tones().items():
                seen.setdefault(f"{m.name}.{k}", hexa)
        return list(seen.items())


def view(r: int) -> View:
    return View(r, CELL, CELL, CANVAS)


def to_rgba(frame: Frame, spec: ChairSpec, keep: Optional[np.ndarray] = None) -> np.ndarray:
    colors = dict(spec.palette())
    out = np.zeros(frame.tone.shape + (4,), dtype=np.uint8)
    for name in np.unique(frame.tone):
        if not name:
            continue
        hexa = colors[name]
        rgb = [int(hexa[i:i + 2], 16) for i in (1, 3, 5)]
        sel = frame.tone == name
        if keep is not None:
            sel &= keep
        out[sel, :3] = rgb
        out[sel, 3] = 255
    return out


def document(doc_id: str, rgba: np.ndarray) -> dict[str, object]:
    """Documento Moana: una capa por color con un rectángulo por tramo horizontal."""
    h, w = rgba.shape[:2]
    colors: list[tuple[int, int, int]] = []
    index = np.full((h, w), -1)
    alpha = rgba[..., 3] == 255
    for y, x in zip(*np.nonzero(alpha)):
        c = tuple(int(v) for v in rgba[y, x, :3])
        if c not in colors:
            colors.append(c)
        index[y, x] = colors.index(c)
    layers = []
    for k in range(len(colors)):
        ops = []
        for y in range(h):
            row = index[y] == k
            x = 0
            while x < w:
                if row[x]:
                    start = x
                    while x < w and row[x]:
                        x += 1
                    ops.append({"id": f"c{k}_{y}_{start}", "type": "rect", "box": [start, y, x, y + 1], "color": f"c{k}"})
                else:
                    x += 1
        if ops:
            layers.append({"id": f"tone{k}", "name": f"Tono {k}", "operations": ops})
    return {
        "schema_version": "1.0",
        "id": doc_id,
        "revision": 0,
        "seed": 0,
        "canvas": {"width": w, "height": h, "profile": "strict"},
        "palette": {"id": f"palette_{doc_id}", "ramps": [],
                    "colors": [{"id": f"c{k}", "rgba": "#%02X%02X%02XFF" % c} for k, c in enumerate(colors)]},
        "masks": [],
        "layers": layers,
    }


def moana_render(doc: dict[str, object]) -> np.ndarray:
    result = api.render(api.load_document(doc))
    canvas = doc["canvas"]  # type: ignore[index]
    return np.array(Image.frombytes("RGBA", (canvas["width"], canvas["height"]), bytes(result.rgba)))


def shadow_rgba(spec: ChairSpec, v: View) -> np.ndarray:
    """Sombra de un tono en el piso, recortada a la planta; cada forma se corre con su altura."""
    w, h = v.canvas
    ys, xs = np.mgrid[0:h, 0:w]
    ox, oy = v.origin
    rx, ry = xs + 0.5 - ox, ys + 0.5 - oy
    gu = (ry / 32.0 + rx / 64.0) / 2.0
    gv = (ry / 32.0 - rx / 64.0) / 2.0
    mask = np.zeros(gu.shape, dtype=bool)

    def world(x: float, y: float) -> tuple[float, float]:
        a, b = v.rot(x, y)
        return a / CELL, b / CELL

    for shape in spec.shadow:
        z0, z1 = shape[-2], shape[-1]
        for step in range(5):
            z = z0 + (z1 - z0) * step / 4.0
            su, sv = SHADOW_SHIFT[0] * z / 64.0, SHADOW_SHIFT[1] * z / 64.0
            if shape[0] == "disc":
                u, vv = world(shape[1], shape[2])
                r = shape[3] / CELL
                mask |= (gu - u - su) ** 2 + (gv - vv - sv) ** 2 <= r * r
            else:
                ua, va = world(shape[1], shape[2])
                ub, vb = world(shape[3], shape[4])
                r = shape[5] / CELL
                du, dv = ub - ua, vb - va
                along = np.clip(((gu - su - ua) * du + (gv - sv - va) * dv) / (du * du + dv * dv), 0.0, 1.0)
                mask |= (gu - su - ua - du * along) ** 2 + (gv - sv - va - dv * along) ** 2 <= r * r
    fu, fv = v.world[0] / CELL, v.world[1] / CELL
    mask &= (gu >= 0) & (gu < fu) & (gv >= 0) & (gv < fv)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    hexa = spec.shadow_color
    out[mask, :3] = [int(hexa[i:i + 2], 16) for i in (1, 3, 5)]
    out[mask, 3] = 255
    return out


def _pieces(mask: np.ndarray) -> int:
    """Cuántos pedazos (vecinos de 8) tiene una máscara."""
    seen = np.zeros_like(mask)
    count = 0
    h, w = mask.shape
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        count += 1
        stack = [(y, x)]
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
    return count


def chair_images(spec: ChairSpec, r: int) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """(silla entera, asiento, respaldo, profundidad) de una rotación."""
    v = view(r)
    solids = spec.model()
    whole_frame = finish(render(solids, v), spec.mats)
    whole = to_rgba(whole_frame, spec)
    over, under = (BACK_GROUP, SEAT_GROUP) if r in BACK_ON_TOP else (SEAT_GROUP, BACK_GROUP)
    below_frame = finish(render([s for s in solids if s.group == under], v), spec.mats)
    below = to_rgba(below_frame, spec)
    seen_under = whole_frame.group == under
    below[seen_under] = whole[seen_under]
    above = whole.copy()
    above[whole_frame.group != over] = 0
    seat, back = (below, above) if under == SEAT_GROUP else (above, below)
    depth = whole_frame.depth
    return whole, seat, back, depth


def save_depth(path: Path, depth: np.ndarray) -> None:
    out = np.zeros(depth.shape, dtype=np.uint16)
    filled = depth > EMPTY / 2
    out[filled] = np.clip(np.round((depth[filled] + DEPTH_OFFSET) * DEPTH_SCALE), 1, 65535).astype(np.uint16)
    Image.fromarray(out.astype(np.int32), "I").convert("I;16").save(path)


def check(spec: ChairSpec, name: str, whole: np.ndarray, seat: np.ndarray, back: np.ndarray, r: int) -> list[str]:
    problems = []
    lower, upper = (seat, back) if r in BACK_ON_TOP else (back, seat)
    joined = lower.copy()
    joined[upper[..., 3] > 0] = upper[upper[..., 3] > 0]
    if not np.array_equal(joined, whole):
        problems.append(f"{name}: las capas no recomponen la silla")
    colors = {tuple(c) for c in whole[whole[..., 3] == 255][:, :3]}
    if len(colors) > spec.max_colors:
        problems.append(f"{name}: {len(colors)} colores (máx. {spec.max_colors})")
    alpha = whole[..., 3] > 0
    if alpha[0].any() or alpha[-1].any() or alpha[:, 0].any() or alpha[:, -1].any():
        problems.append(f"{name}: toca el borde del lienzo")
    for layer, img in (("asiento", seat), ("respaldo", back)):
        if _pieces(img[..., 3] > 0) != 1:
            problems.append(f"{name}: la capa {layer} quedó en varios pedazos")
    return problems


def preview(spec: ChairSpec, rows: list[list[np.ndarray]], path: Path, scale: int = 4) -> None:
    bg = (70, 72, 80, 255)
    w, h = CANVAS
    sheet = Image.new("RGBA", (w * 4 * scale, h * len(rows) * scale), bg)
    for j, row in enumerate(rows):
        for r, img in enumerate(row):
            cell = Image.new("RGBA", CANVAS, bg)
            cell.alpha_composite(Image.fromarray(img, "RGBA"))
            sheet.paste(cell.resize((w * scale, h * scale), Image.NEAREST), (r * w * scale, j * h * scale))
    sheet.save(path)


def main(spec: ChairSpec, here: Path) -> int:
    parser = argparse.ArgumentParser(description=f"Genera {spec.name} (4 rotaciones, capas, sombra y profundidad).")
    parser.add_argument("--out", type=Path, default=here, help="carpeta de salida (por defecto, la del build.py)")
    parser.add_argument("--preview", action="store_true", help=f"escribe también {spec.name}_preview.png")
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    sprites: dict[str, dict[str, object]] = {}
    rows: list[list[np.ndarray]] = [[], [], [], []]
    anchor = view(0).anchor
    for r in range(4):
        whole, seat, back, depth = chair_images(spec, r)
        shadow = shadow_rgba(spec, view(r))
        name = f"{spec.name}_r{r}"
        problems += check(spec, name, whole, seat, back, r)
        images = {name: whole, f"{spec.name}_seat_r{r}": seat, f"{spec.name}_back_r{r}": back,
                  f"{name}_shadow": shadow}
        for file_name, img in images.items():
            doc = document(file_name, img)
            (out / f"{file_name}.moana.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
            drawn = moana_render(doc)
            if not np.array_equal(drawn, img):
                problems.append(f"{file_name}: Moana no da los mismos pixeles que el dibujo")
            Image.fromarray(drawn, "RGBA").save(out / f"{file_name}.png")
            sprites[f"{file_name}.png"] = {"anchor": list(anchor)}
        save_depth(out / f"{name}_depth.png", depth)
        rows[0].append(whole)
        rows[1].append(seat)
        rows[2].append(back)
        rows[3].append(shadow)
    manifest = {"_comentario": "Apoyo (px del sprite) de cada PNG de esta carpeta; lo escribe build.py y export_game.py "
                               "lo pasa al juego. <silla>_r<n>_depth.png es la profundidad por pixel para el "
                               "personaje sentado (no es un sprite).",
                "sprites": sprites}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.preview:
        preview(spec, rows, out / f"{spec.name}_preview.png")
    for line in problems:
        print("FALLO:", line)
    print("RESULTADO:", "OK" if not problems else f"{len(problems)} fallos")
    return 1 if problems else 0


# ---------------------------------------------------------------------------- piezas sueltas (plantas)

@dataclass
class PieceSpec:
    """Mueble sin capas: planta, lámpara, pecera… ``rotations`` (0,) da ``<nombre>.png``; si son varias,
    ``<nombre>_r<n>.png`` (el modelo, en rotación 0, se gira dentro de la planta ``size``)."""

    name: str
    mats: dict[str, Mat]
    model: Callable[[], list[Solid]]
    shadow: list[tuple]
    shadow_color: str = "#1A1C26FF"
    max_colors: int = 16
    size: tuple[int, int] = (1, 1)  # planta en casillas (rotación 0)
    canvas: tuple[int, int] = CANVAS
    rotations: tuple[int, ...] = (0,)
    painter: bool = False  # documento en orden de pintor (../_painter.py), para piezas con mucha textura

    def view(self, r: int) -> View:
        return View(r, self.size[0] * CELL, self.size[1] * CELL, self.canvas)

    def palette(self) -> list[tuple[str, str]]:
        return ChairSpec.palette(self)  # type: ignore[arg-type]


def main_piece(spec: PieceSpec, here: Path) -> int:
    """Genera la imagen y la sombra de cada rotación (ver ``PieceSpec``) con su manifest.json."""
    parser = argparse.ArgumentParser(description=f"Genera {spec.name} y su sombra con Moana.")
    parser.add_argument("--out", type=Path, default=here, help="carpeta de salida (por defecto, la del build.py)")
    parser.add_argument("--preview", action="store_true", help=f"escribe también {spec.name}_preview.png")
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    sprites = {}
    shown: list[np.ndarray] = []
    for r in spec.rotations:
        v = spec.view(r)
        base = spec.name if spec.rotations == (0,) else f"{spec.name}_r{r}"
        image = to_rgba(finish(render(spec.model(), v, spec.canvas), spec.mats), spec)  # type: ignore[arg-type]
        shadow = shadow_rgba(spec, v)  # type: ignore[arg-type]
        colors = {tuple(c) for c in image[image[..., 3] == 255][:, :3]}
        if len(colors) > spec.max_colors:
            problems.append(f"{base}: {len(colors)} colores (máx. {spec.max_colors})")
        alpha = image[..., 3] > 0
        if alpha[0].any() or alpha[-1].any() or alpha[:, 0].any() or alpha[:, -1].any():
            problems.append(f"{base}: toca el borde del lienzo")
        for file_name, img in ((base, image), (f"{base}_shadow", shadow)):
            doc = painter_document(file_name, img) if spec.painter else document(file_name, img)
            (out / f"{file_name}.moana.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
            drawn = moana_render(doc)
            if not np.array_equal(drawn, img):
                problems.append(f"{file_name}: Moana no da los mismos pixeles que el dibujo")
            Image.fromarray(drawn, "RGBA").save(out / f"{file_name}.png")
            sprites[f"{file_name}.png"] = {"anchor": list(v.anchor)}
        comp = shadow.copy()
        comp[alpha] = image[alpha]
        shown.append(comp)
    manifest = {"_comentario": "Apoyo (px del sprite) de cada PNG de esta carpeta; lo escribe build.py y export_game.py "
                               "lo pasa al juego.", "sprites": sprites}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.preview:
        w, h = spec.canvas
        sheet = Image.new("RGBA", (w * len(shown) * 4, h * 4), (70, 72, 80, 255))
        for k, img in enumerate(shown):
            cell = Image.new("RGBA", spec.canvas, (70, 72, 80, 255))
            cell.alpha_composite(Image.fromarray(img, "RGBA"))
            sheet.paste(cell.resize((w * 4, h * 4), Image.NEAREST), (k * w * 4, 0))
        sheet.save(out / f"{spec.name}_preview.png")
    for line in problems:
        print("FALLO:", line)
    print("RESULTADO:", "OK" if not problems else f"{len(problems)} fallos")
    return 1 if problems else 0
