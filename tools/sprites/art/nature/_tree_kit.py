"""Árboles, arbustos y setos con Moana: trazado de rayos sobre formas redondas.

Las copas son bultos de hojas (esferas con el borde rizado por ruido), los troncos y ramas cápsulas que
se angostan y los abetos conos; cada pixel lanza un rayo de la vista isométrica y se queda con la
primera forma que toca. Del punto tocado salen:

- el tono: la luz (arriba a la izquierda) sobre una normal que mezcla la del bulto con la de la copa
  entera, más sombra adentro de la copa y abajo, más una textura de hojas por ruido en 3D;
- la línea de sombra bajo cada bulto que tapa a otro (y bajo la copa sobre el tronco);
- el contorno oscuro de 1 px por fuera de la silueta, del tono de contorno de lo que rodea.

Coordenadas del modelo: x, y en casillas (0 a 1 es la casilla de apoyo) y z en px, como el resto del arte;
en pantalla, p(x, y, z) = (ox + 64·(x − y), oy + 32·(x + y) − z). El documento Moana lleva una capa por
tono con un rectángulo por tramo horizontal (ver ``../furniture/_chair_kit.py``).
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Callable, Optional

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "furniture"))
from _chair_kit import SHADOW_SHIFT, moana_render  # noqa: E402

Z_METRIC = 78.4  # px de alto por casilla de largo (vista isométrica 2:1)
RAY = np.array([1 / 64.0, 1 / 64.0, 1 / Z_METRIC])  # paso del rayo hacia la vista por px de z, en casillas
RAY_LEN = float(np.linalg.norm(RAY))
LIGHT = np.array([-0.25, 0.55, 0.8]) / np.linalg.norm([-0.25, 0.55, 0.8])  # hacia la luz: arriba a la izquierda
GAP = 3.0 / 64.0  # casillas que un bulto debe estar delante de otro para marcar la sombra entre ellos
EMPTY = -1.0e9
SHADOW_COLOR = "#1A1C26FF"
Vec3 = tuple[float, float, float]


# ---------------------------------------------------------------------------- tonos

@dataclass
class Ramp:
    """Tonos de oscuro a claro y el contorno."""

    name: str
    tones: tuple[str, ...]
    ink: str


LEAVES = Ramp("leaves", ("#366A19FF", "#4A811FFF", "#5F9627FF", "#73A82EFF", "#86B934FF", "#9DCB3CFF",
                         "#B4D84AFF"), "#2A5214FF")  # hojas de árboles, arbustos y setos


# ---------------------------------------------------------------------------- ruido

_PERM = np.random.RandomState(7).permutation(256)
_PERM = np.concatenate([_PERM, _PERM])
_GRAD = np.random.RandomState(8).uniform(-1.0, 1.0, 256)


def noise3(p: np.ndarray, seed: int = 0) -> np.ndarray:
    """Ruido de valor suave en 3D (−1 a 1); ``p`` con forma (..., 3)."""
    p = p + seed * 17.31
    i = np.floor(p).astype(np.int64)
    f = p - i
    u = f * f * (3.0 - 2.0 * f)
    i &= 255

    def corner(dx: int, dy: int, dz: int) -> np.ndarray:
        h = _PERM[_PERM[_PERM[i[..., 0] + dx] + i[..., 1] + dy] + i[..., 2] + dz]
        return _GRAD[h]

    def lerp(a: np.ndarray, b: np.ndarray, t: np.ndarray) -> np.ndarray:
        return a + (b - a) * t

    x0 = lerp(lerp(corner(0, 0, 0), corner(1, 0, 0), u[..., 0]), lerp(corner(0, 1, 0), corner(1, 1, 0), u[..., 0]),
              u[..., 1])
    x1 = lerp(lerp(corner(0, 0, 1), corner(1, 0, 1), u[..., 0]), lerp(corner(0, 1, 1), corner(1, 1, 1), u[..., 0]),
              u[..., 1])
    return lerp(x0, x1, u[..., 2])


# ---------------------------------------------------------------------------- formas

@dataclass
class Shape:
    """Forma redonda: ``ball`` (centro, radio, estirada en z), ``capsule`` (de ``a`` a ``b`` con radios
    ``r`` y ``r2``), ``cone`` (eje vertical de ``a`` a ``b``, radio ``r`` abajo y ``r2`` arriba) o ``box``
    (``a`` y ``b`` esquinas opuestas, borde redondeado ``r``). Medidas en casillas salvo z (px)."""

    kind: str
    part: str
    ramp: str
    a: Vec3
    r: float
    b: Vec3 = (0.0, 0.0, 0.0)
    r2: float = 0.0
    stretch: float = 1.0
    shade: str = "leaf"  # leaf (copa), bark (corteza), dot (flor o fruto), clip (seto)
    center: Optional[Vec3] = None  # centro de la copa a la que pertenece (luz general y sombra de adentro)
    radius: float = 0.5  # radio de esa copa (casillas)
    half: float = 0.0  # media altura de esa copa (casillas; 0 = igual al radio)
    bump: float = 0.012  # rizado del borde (casillas)
    seed: int = 0

    def metric(self, p: Vec3) -> np.ndarray:
        return np.array([p[0], p[1], p[2] / Z_METRIC])


def ball(part: str, ramp: str, c: Vec3, r: float, **kw: object) -> Shape:
    return Shape("ball", part, ramp, c, r, **kw)  # type: ignore[arg-type]


def capsule(part: str, ramp: str, a: Vec3, b: Vec3, r: float, r2: Optional[float] = None, **kw: object) -> Shape:
    kw.setdefault("shade", "bark")
    kw.setdefault("bump", 0.0)
    return Shape("capsule", part, ramp, a, r, b, r if r2 is None else r2, **kw)  # type: ignore[arg-type]


def cone(part: str, ramp: str, x: float, y: float, z0: float, z1: float, r0: float, r1: float, **kw: object) -> Shape:
    return Shape("cone", part, ramp, (x, y, z0), r0, (x, y, z1), r1, **kw)  # type: ignore[arg-type]


def box(part: str, ramp: str, lo: Vec3, hi: Vec3, r: float, **kw: object) -> Shape:
    kw.setdefault("shade", "clip")
    return Shape("box", part, ramp, lo, r, hi, **kw)  # type: ignore[arg-type]


def sdf(s: Shape, p: np.ndarray) -> np.ndarray:
    """Distancia (casillas, aproximada por fuera) de los puntos ``p`` (n, 3) a la forma."""
    a = s.metric(s.a)
    if s.kind == "ball":
        q = (p - a) * np.array([1.0, 1.0, 1.0 / s.stretch])
        d = (np.linalg.norm(q, axis=-1) - s.r) * min(1.0, s.stretch)
    elif s.kind == "capsule":
        b = s.metric(s.b)
        ba = b - a
        h = np.clip(((p - a) @ ba) / float(ba @ ba), 0.0, 1.0)
        d = np.linalg.norm(p - a - h[:, None] * ba, axis=-1) - (s.r + (s.r2 - s.r) * h)
    elif s.kind == "cone":
        b = s.metric(s.b)
        hh = (b[2] - a[2]) / 2.0
        mid = (a[2] + b[2]) / 2.0
        q = np.stack([np.hypot(p[:, 0] - a[0], p[:, 1] - a[1]), p[:, 2] - mid], axis=-1)
        k1 = np.array([s.r2, hh])
        k2 = np.array([s.r2 - s.r, 2.0 * hh])
        ca = np.stack([q[:, 0] - np.minimum(q[:, 0], np.where(q[:, 1] < 0, s.r, s.r2)), np.abs(q[:, 1]) - hh], axis=-1)
        t = np.clip(((k1 - q) @ k2) / float(k2 @ k2), 0.0, 1.0)
        cb = q - k1 + t[:, None] * k2
        sign = np.where((cb[:, 0] < 0) & (ca[:, 1] < 0), -1.0, 1.0)
        d = sign * np.sqrt(np.minimum((ca * ca).sum(-1), (cb * cb).sum(-1)))
    else:
        b = s.metric(s.b)
        c, half = (a + b) / 2.0, np.abs(b - a) / 2.0 - s.r
        q = np.abs(p - c) - half
        d = np.linalg.norm(np.maximum(q, 0.0), axis=-1) + np.minimum(q.max(-1), 0.0) - s.r
    if s.bump:
        d = d - s.bump * noise3(p * 28.0, s.seed)
    return d


def screen_box(s: Shape, origin: tuple[float, float]) -> tuple[float, float, float, float]:
    """Rectángulo de pantalla (x0, y0, x1, y1) que cubre la forma, con margen."""
    ox, oy = origin
    pts = [s.a, s.b] if s.kind != "ball" else [s.a]
    reach = max(s.r, s.r2) * 1.42 + s.bump * 2
    xs, ys = [], []
    for x, y, z in pts:
        sx, sy = ox + 64 * (x - y), oy + 32 * (x + y) - z
        zr = reach * Z_METRIC * (s.stretch if s.kind == "ball" else 1.0)
        xs += [sx - reach * 64 * 1.42, sx + reach * 64 * 1.42]
        ys += [sy - max(zr, reach * 64), sy + max(zr, reach * 64)]
    if s.kind == "box":
        (x0, y0, z0), (x1, y1, z1) = s.a, s.b
        for x in (x0, x1):
            for y in (y0, y1):
                for z in (z0, z1):
                    xs.append(ox + 64 * (x - y))
                    ys.append(oy + 32 * (x + y) - z)
    return min(xs) - 3, min(ys) - 3, max(xs) + 3, max(ys) + 3


# ---------------------------------------------------------------------------- trazado

@dataclass
class Hit:
    shape: np.ndarray  # índice de la forma por pixel (−1 = vacío)
    point: np.ndarray  # punto tocado (casillas, z en casillas)
    depth: np.ndarray  # u + v + z/64 (casillas)


def trace(shapes: list[Shape], canvas: tuple[int, int], origin: tuple[float, float], floor: bool = True) -> Hit:
    """Primera forma que toca cada rayo, de adelante hacia atrás. ``floor`` corta todo en z = 0."""
    w, h = canvas
    ox, oy = origin
    ys, xs = np.mgrid[0:h, 0:w]
    A = (xs.ravel() + 0.5 - ox) / 64.0
    B = (ys.ravel() + 0.5 - oy) / 32.0
    base = np.stack([(A + B) / 2.0, (B - A) / 2.0, np.zeros_like(A)], axis=-1)  # punto del rayo con z = 0
    boxes = [screen_box(s, origin) for s in shapes]
    sxp, syp = xs.ravel() + 0.5, ys.ravel() + 0.5
    near = [np.nonzero((sxp >= b[0]) & (sxp <= b[2]) & (syp >= b[1]) & (syp <= b[3]))[0] for b in boxes]
    top = max(max(s.a[2], s.b[2]) + max(s.r, s.r2) * Z_METRIC * s.stretch for s in shapes) + 8
    n = w * h
    z = np.full(n, top)  # z del rayo en px
    best = np.full(n, -1)
    alive = np.zeros(n, dtype=bool)
    for idx in near:
        alive[idx] = True
    member = np.zeros((len(shapes), n), dtype=bool)
    for k, idx in enumerate(near):
        member[k, idx] = True
    for _ in range(400):
        live = np.nonzero(alive)[0]
        if not len(live):
            break
        p = base[live] + z[live, None] * RAY
        dist = np.full(len(live), 1e9)
        which = np.full(len(live), -1)
        for k, s in enumerate(shapes):
            sel = member[k, live]
            if not sel.any():
                continue
            d = sdf(s, p[sel])
            cur = dist[sel]
            take = d < cur
            cur[take] = d[take]
            dist[sel] = cur
            wk = which[sel]
            wk[take] = k
            which[sel] = wk
        if floor:
            dist = np.maximum(dist, -p[:, 2])
        hit = dist < 0.002
        best[live[hit]] = which[hit]
        alive[live[hit]] = False
        step = np.maximum(dist * 0.6, 0.0015) / RAY_LEN
        z[live] -= np.where(hit, 0.0, step)
        gone = z[live] < -4
        alive[live[gone & ~hit]] = False
    point = base + z[:, None] * RAY
    depth = point[:, 0] + point[:, 1] + point[:, 2] * Z_METRIC / 64.0
    depth = np.where(best >= 0, depth, EMPTY)
    return Hit(best.reshape(h, w), point.reshape(h, w, 3), depth.reshape(h, w))


def normals(shapes: list[Shape], hit: Hit) -> np.ndarray:
    """Normal (casillas) de la forma tocada en cada pixel, por diferencias de su distancia."""
    out = np.zeros(hit.point.shape)
    e = 0.004
    for k, s in enumerate(shapes):
        sel = hit.shape == k
        if not sel.any():
            continue
        p = hit.point[sel]
        g = np.zeros(p.shape)
        flat = replace(s, bump=0.0) if s.shade == "clip" else s  # seto: caras parejas, el rizado solo en el borde
        for axis in range(3):
            dv = np.zeros(3)
            dv[axis] = e
            g[:, axis] = sdf(flat, p + dv) - sdf(flat, p - dv)
        out[sel] = g / np.maximum(np.linalg.norm(g, axis=-1, keepdims=True), 1e-9)
    return out


# ---------------------------------------------------------------------------- tono

def shade(shapes: list[Shape], ramps: dict[str, Ramp], hit: Hit, nrm: np.ndarray) -> np.ndarray:
    """Índice de tono (0 = el más oscuro de la rampa) por pixel; −1 vacío."""
    h, w = hit.shape.shape
    index = np.full((h, w), -1)
    for k, s in enumerate(shapes):
        sel = hit.shape == k
        if not sel.any():
            continue
        n = nrm[sel]
        p = hit.point[sel]
        count = len(ramps[s.ramp].tones)
        if s.shade == "leaf":
            c = s.metric(s.center or s.a)
            g = (p - c) / np.array([s.radius, s.radius, s.half or s.radius])  # copa como elipsoide
            dist = np.linalg.norm(g, axis=-1)
            g = g / np.maximum(dist, 1e-9)[:, None]
            v = 0.55 * (n @ LIGHT) + 0.7 * (g @ LIGHT)
            v -= 0.6 * np.clip(1.0 - dist, 0.0, 1.0)  # adentro de la copa, a la sombra
            v -= 0.25 * np.clip(-g[:, 2], 0.0, 1.0)  # panza de la copa
            v += 0.13 * noise3(p * 30.0, s.seed + 3)
            value = (v + 0.75) / 2.05
        elif s.shade == "clip":
            v = n @ LIGHT - 0.3 * (1.0 - np.abs(n[:, 2])) + 0.2 * noise3(p * 20.0, s.seed + 3)
            value = (v + 0.8) / 1.7
        elif s.shade == "dot":
            value = np.where(n @ LIGHT > 0.6, 1.0, 0.5)
        else:
            v = n @ LIGHT
            value = (v + 0.3) / 1.2
        index[sel] = np.clip(np.floor(value * count), 0, count - 1).astype(int)
    return index


def despeckle(index: np.ndarray, owner: np.ndarray, passes: int = 3) -> np.ndarray:
    """Un pixel sin vecino (de 8) de su tono y su forma toma el tono más repetido entre sus vecinos de la forma."""
    h, w = index.shape
    for _ in range(passes):
        pad_i = np.pad(index, 1, constant_values=-9)
        pad_o = np.pad(owner, 1, constant_values=-9)
        same = np.zeros((h, w), dtype=int)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx or dy:
                    same += (pad_i[1 + dy:1 + dy + h, 1 + dx:1 + dx + w] == index) & \
                            (pad_o[1 + dy:1 + dy + h, 1 + dx:1 + dx + w] == owner)
        ys, xs = np.nonzero((owner >= 0) & (same == 0))
        if not len(ys):
            break
        out = index.copy()
        for y, x in zip(ys, xs):
            around = [pad_i[y + 1 + dy, x + 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                      if (dx or dy) and pad_o[y + 1 + dy, x + 1 + dx] == owner[y, x]]
            if around:
                out[y, x] = max(set(around), key=around.count)
        index = out
    return index


# ---------------------------------------------------------------------------- sprite

@dataclass
class Sprite:
    """Un PNG: lienzo, planta (casillas del mundo) y formas; ``shadow`` como en ``_chair_kit`` pero en casillas."""

    name: str
    canvas: tuple[int, int]
    footprint: tuple[int, int]
    shapes: list[Shape]
    shadow: list[tuple]
    max_colors: int = 16
    seams: Callable[[str, str], bool] = lambda front, back: True  # qué bulto marca sombra sobre cuál

    @property
    def origin(self) -> tuple[float, float]:
        fw, fd = self.footprint
        return 64.0 * fd, float(self.canvas[1] - 32 * (fw + fd))

    @property
    def anchor(self) -> list[int]:
        ox, oy = self.origin
        return [int(ox), int(oy + 32)]


def draw(sprite: Sprite, ramps: dict[str, Ramp]) -> np.ndarray:
    shapes = sprite.shapes
    hit = trace(shapes, sprite.canvas, sprite.origin)
    nrm = normals(shapes, hit)
    index = shade(shapes, ramps, hit, nrm)
    owner = hit.shape
    index = despeckle(index, owner)
    h, w = owner.shape
    ramp_of = [ramps[s.ramp] for s in shapes]
    part_of = np.array([s.part for s in shapes] + [""], dtype=object)
    part = part_of[owner]
    # Sombra bajo lo que tapa: el pixel de abajo de una forma que está delante, de otra pieza.
    darken = np.zeros((h, w), dtype=bool)
    for dy, dx in ((1, 0), (0, 1), (0, -1)):  # vecino de arriba, de la izquierda y de la derecha
        n_owner = np.full((h, w), -1)
        n_depth = np.full((h, w), EMPTY)
        n_owner[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = owner[max(-dy, 0):h + min(-dy, 0),
                                                                               max(-dx, 0):w + min(-dx, 0)]
        n_depth[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = hit.depth[max(-dy, 0):h + min(-dy, 0),
                                                                                  max(-dx, 0):w + min(-dx, 0)]
        n_part = np.where(n_owner >= 0, part_of[n_owner], "")
        seam = (owner >= 0) & (n_owner >= 0) & (n_part != part) & (n_depth > hit.depth + GAP)
        for y, x in zip(*np.nonzero(seam)):
            if sprite.seams(shapes[n_owner[y, x]].part, shapes[owner[y, x]].part):
                darken[y, x] = True
    index[darken] = np.maximum(index[darken] - 2, 0)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    for y, x in zip(*np.nonzero(owner >= 0)):
        hexa = ramp_of[owner[y, x]].tones[index[y, x]]
        out[y, x] = [int(hexa[i:i + 2], 16) for i in (1, 3, 5, 7)]
    # Contorno de afuera: del vecino (de 4) que está más adelante.
    filled = owner >= 0
    best = np.full((h, w), EMPTY)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        n_owner = np.full((h, w), -1)
        n_depth = np.full((h, w), EMPTY)
        n_owner[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = owner[max(-dy, 0):h + min(-dy, 0),
                                                                               max(-dx, 0):w + min(-dx, 0)]
        n_depth[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = hit.depth[max(-dy, 0):h + min(-dy, 0),
                                                                                  max(-dx, 0):w + min(-dx, 0)]
        take = ~filled & (n_owner >= 0) & (n_depth > best)
        best[take] = n_depth[take]
        for y, x in zip(*np.nonzero(take)):
            hexa = ramp_of[n_owner[y, x]].ink
            out[y, x] = [int(hexa[i:i + 2], 16) for i in (1, 3, 5, 7)]
    return out


def shadow_rgba(sprite: Sprite) -> np.ndarray:
    """Sombra de un tono en el piso, recortada a la planta; cada forma se corre con su altura."""
    w, h = sprite.canvas
    ys, xs = np.mgrid[0:h, 0:w]
    ox, oy = sprite.origin
    rx, ry = xs + 0.5 - ox, ys + 0.5 - oy
    gu = (ry / 32.0 + rx / 64.0) / 2.0
    gv = (ry / 32.0 - rx / 64.0) / 2.0
    mask = np.zeros(gu.shape, dtype=bool)
    for shape in sprite.shadow:
        z0, z1 = shape[-2], shape[-1]
        for step in range(5):
            z = z0 + (z1 - z0) * step / 4.0
            su, sv = SHADOW_SHIFT[0] * z / 64.0, SHADOW_SHIFT[1] * z / 64.0
            if shape[0] == "disc":
                mask |= (gu - shape[1] - su) ** 2 + (gv - shape[2] - sv) ** 2 <= shape[3] ** 2
            else:
                ua, va, ub, vb = shape[1:5]
                du, dv = ub - ua, vb - va
                along = np.clip(((gu - su - ua) * du + (gv - sv - va) * dv) / (du * du + dv * dv), 0.0, 1.0)
                mask |= (gu - su - ua - du * along) ** 2 + (gv - sv - va - dv * along) ** 2 <= shape[5] ** 2
    fw, fd = sprite.footprint
    mask &= (gu >= 0) & (gu < fw) & (gv >= 0) & (gv < fd)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[mask] = [int(SHADOW_COLOR[i:i + 2], 16) for i in (1, 3, 5, 7)]
    return out


def document(doc_id: str, rgba: np.ndarray) -> dict[str, object]:
    """Documento Moana en orden de pintor: una capa por color (del más usado al menos, o de oscuro a claro:
    el orden que dé menos rectángulos). Cada capa
    pinta tramos horizontales que cubren su color y los que se pintan después (que lo tapan), así salen
    muchos menos rectángulos; tramos iguales en filas seguidas van en un solo rectángulo."""
    h, w = rgba.shape[:2]
    alpha = rgba[..., 3] == 255
    flat = rgba[..., :3].reshape(-1, 3)
    keys = (flat[:, 0].astype(np.int64) << 16) | (flat[:, 1].astype(np.int64) << 8) | flat[:, 2]
    keys = np.where(alpha.ravel(), keys, -1).reshape(h, w)
    values, counts = np.unique(keys[alpha], return_counts=True)
    by_count = [int(v) for v in values[np.argsort(-counts, kind="stable")]]
    luma = [((v >> 16) & 255) * 3 + ((v >> 8) & 255) * 6 + (v & 255) for v in by_count]
    by_light = [v for _, v in sorted(zip(luma, by_count))]  # tonos anidados: lo claro suele ir adentro
    order, layers = min(((o, _layers(keys, o)) for o in (by_count, by_light)),
                        key=lambda t: sum(len(layer["operations"]) for layer in t[1]))
    return {
        "schema_version": "1.0",
        "id": doc_id,
        "revision": 0,
        "seed": 0,
        "canvas": {"width": w, "height": h, "profile": "strict"},
        "palette": {"id": f"palette_{doc_id}", "ramps": [],
                    "colors": [{"id": f"c{k}", "rgba": "#%06XFF" % v} for k, v in enumerate(order)]},
        "masks": [],
        "layers": layers,
    }


def _layers(keys: np.ndarray, order: list[int]) -> list[dict[str, object]]:
    """Capas del documento pintando los colores en ese orden."""
    h, w = keys.shape
    rank = np.full((h, w), -1)
    for k, v in enumerate(order):
        rank[keys == v] = k
    layers = []
    for k, v in enumerate(order):
        cover = rank >= k
        spans: dict[tuple[int, int], int] = {}  # (x0, x1) abierto -> fila de arriba
        boxes = []
        for y in range(h + 1):
            row: list[tuple[int, int]] = []
            if y < h:
                x = 0
                while x < w:
                    if cover[y, x]:
                        start = x
                        while x < w and cover[y, x]:
                            x += 1
                        if (rank[y, start:x] == k).any():
                            row.append((start, x))
                    else:
                        x += 1
            for span in list(spans):
                if span not in row:
                    boxes.append((span[0], spans.pop(span), span[1], y))
            for span in row:
                spans.setdefault(span, y)
        ops = [{"id": f"c{k}_{y0}_{x0}", "type": "pixel", "at": [x0, y0], "color": f"c{k}"}
               if (x1 - x0, y1 - y0) == (1, 1) else  # pesa menos en el documento (Moana cuenta nodos)
               {"id": f"c{k}_{y0}_{x0}", "type": "rect", "box": [x0, y0, x1, y1], "color": f"c{k}"}
               for x0, y0, x1, y1 in sorted(boxes, key=lambda b: (b[1], b[0]))]
        layers.append({"id": f"tone{k}", "name": f"Tono {k}", "operations": ops})
    return layers


def preview(images: list[np.ndarray], path: Path, scale: int = 3) -> None:
    bg = (70, 72, 80, 255)
    cw = max(i.shape[1] for i in images)
    ch = max(i.shape[0] for i in images)
    cols = min(len(images), 8)
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cw * cols * scale, ch * rows * scale), bg)
    for k, img in enumerate(images):
        cell = Image.new("RGBA", (cw, ch), bg)
        cell.alpha_composite(Image.fromarray(img, "RGBA"), (0, ch - img.shape[0]))
        sheet.paste(cell.resize((cw * scale, ch * scale), Image.NEAREST), ((k % cols) * cw * scale,
                                                                          (k // cols) * ch * scale))
    sheet.save(path)


def main(sprites: list[Sprite], ramps: dict[str, Ramp], here: Path, title: str) -> int:
    """Genera ``<nombre>.png`` y ``<nombre>_shadow.png`` de cada sprite con su manifest.json."""
    parser = argparse.ArgumentParser(description=f"Genera {title} con Moana.")
    parser.add_argument("--out", type=Path, default=here, help="carpeta de salida (por defecto, la del build.py)")
    parser.add_argument("--preview", action="store_true", help="escribe también preview.png")
    parser.add_argument("--only", default="", help="nombres separados por coma (para probar)")
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    only = set(filter(None, args.only.split(",")))
    problems: list[str] = []
    sprites_meta: dict[str, dict[str, object]] = {}
    shown: list[np.ndarray] = []
    for sprite in sprites:
        if only and sprite.name not in only:
            continue
        image = draw(sprite, ramps)
        shadow = shadow_rgba(sprite)
        colors = {tuple(c) for c in image[image[..., 3] == 255][:, :3]}
        if len(colors) > sprite.max_colors:
            problems.append(f"{sprite.name}: {len(colors)} colores (máx. {sprite.max_colors})")
        alpha = image[..., 3] > 0
        if alpha[0].any() or alpha[-1].any() or alpha[:, 0].any() or alpha[:, -1].any():
            problems.append(f"{sprite.name}: toca el borde del lienzo")
        ys, xs = np.nonzero(alpha)
        ox, oy = sprite.origin
        rx, ry = xs + 0.5 - ox, ys + 0.5 - oy
        gu, gv = (ry / 32.0 + rx / 64.0) / 2.0, (ry / 32.0 - rx / 64.0) / 2.0
        if ((gu >= sprite.footprint[0]) | (gv >= sprite.footprint[1])).any():
            problems.append(f"{sprite.name}: sale por debajo de la planta")
        for file_name, img in ((sprite.name, image), (f"{sprite.name}_shadow", shadow)):
            doc = document(file_name, img)
            (out / f"{file_name}.moana.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
            drawn = moana_render(doc)
            if not np.array_equal(drawn, img):
                problems.append(f"{file_name}: Moana no da los mismos pixeles que el dibujo")
            Image.fromarray(drawn, "RGBA").save(out / f"{file_name}.png")
            sprites_meta[f"{file_name}.png"] = {"anchor": sprite.anchor}
        comp = shadow.copy()
        comp[image[..., 3] > 0] = image[image[..., 3] > 0]
        shown.append(comp)
    if not only:
        manifest = {"_comentario": "Apoyo (px del sprite) de cada PNG de esta carpeta; lo escribe build.py y "
                                   "export_game.py lo pasa al juego.", "sprites": sprites_meta}
        (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.preview:
        preview(shown, out / "preview.png")
    for line in problems:
        print("FALLO:", line)
    print("RESULTADO:", "OK" if not problems else f"{len(problems)} fallos")
    return 1 if problems else 0


# ---------------------------------------------------------------------------- copas

def crown(part: str, ramp: str, center: Vec3, profile: Callable[[float], float], z0: float, z1: float,
          count: int, size: tuple[float, float], seed: int, fill: bool = True, low: float = 0.02,
          **kw: object) -> list[Shape]:
    """Copa de ``count`` bultos sobre la superficie de revolución ``profile(t)`` (radio en casillas, t de
    0 abajo a 1 arriba, entre z0 y z1 px; desde ``low``) y un relleno por el eje para que no se vea a través."""
    rng = np.random.RandomState(seed)
    cx, cy, _ = center
    widest = max(profile(t) for t in np.linspace(0, 1, 41))
    mid = (cx, cy, (z0 + z1) / 2.0)
    common = dict(center=mid, radius=widest, half=(z1 - z0) / 2.0 / Z_METRIC, seed=seed)
    common.update(kw)
    shapes: list[Shape] = []
    if fill:
        for t in np.linspace(0.06, 0.94, 12):
            r = min(profile(t) * 0.85, (z1 - z0) / Z_METRIC * min(t, 1 - t) + 0.02)
            if r > 0.02:
                shapes.append(ball(f"{part}.core", ramp, (cx, cy, z0 + t * (z1 - z0)), r,
                                   **common))  # type: ignore[arg-type]
    placed = 0
    tries = 0
    while placed < count and tries < 20000:
        tries += 1
        t = rng.uniform(low, 0.98)
        if rng.uniform(0, widest) > max(profile(t), widest * 0.2):
            continue
        theta = rng.uniform(0, 2 * math.pi)
        r = min(rng.uniform(*size), profile(t) * 0.8 + 0.02)
        radial = max(profile(t) - r * 0.55, 0.0)
        z = z0 + t * (z1 - z0)
        z = min(z, z1 - r * Z_METRIC * 0.6)
        shapes.append(ball(f"{part}.{placed}", ramp, (cx + radial * math.cos(theta), cy + radial * math.sin(theta), z), r,
                           **common))  # type: ignore[arg-type]
        placed += 1
    return shapes


def ball_profile(radius: float) -> Callable[[float], float]:
    return lambda t: radius * math.sqrt(max(0.0, 1.0 - (2.0 * t - 1.0) ** 2))


def drop_profile(radius: float, peak: float = 0.3, power: float = 1.5) -> Callable[[float], float]:
    """Lo más ancho a ``peak`` de la altura y de ahí se cierra hasta la punta."""
    def fn(t: float) -> float:
        if t < peak:
            return radius * math.sqrt(max(0.0, 1.0 - ((peak - t) / peak) ** 2))
        return radius * max(0.0, 1.0 - ((t - peak) / (1.0 - peak)) ** power)
    return fn


def dome_profile(radius: float) -> Callable[[float], float]:
    return lambda t: radius * math.sqrt(max(0.0, 1.0 - t * t))


def dots(part: str, ramp: str, crown_shapes: list[Shape], count: int, seed: int, size: tuple[float, float],
         min_z: float = 0.0) -> list[Shape]:
    """Flores o frutos sobre los bultos de la copa que miran a la vista."""
    rng = np.random.RandomState(seed)
    outer = [s for s in crown_shapes if s.center and s.a[2] >= min_z and
             (s.a[0] - s.center[0]) + (s.a[1] - s.center[1]) > 0.02]
    out: list[Shape] = []
    for _ in range(count):
        s = outer[rng.randint(len(outer))]
        d = np.array([s.a[0] - s.center[0], s.a[1] - s.center[1], (s.a[2] - s.center[2]) / Z_METRIC])  # type: ignore[index]
        d = d / max(np.linalg.norm(d), 1e-6) + np.array([0.35, 0.35, 0.3]) + rng.uniform(-0.35, 0.35, 3)
        d /= np.linalg.norm(d)
        p = (s.a[0] + d[0] * s.r * 0.95, s.a[1] + d[1] * s.r * 0.95, s.a[2] + d[2] * s.r * 0.95 * Z_METRIC)
        out.append(ball(part, ramp, p, rng.uniform(*size), shade="dot", bump=0.0))
    return out
