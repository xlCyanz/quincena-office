"""Piezas de las plantas (rotación 0; x, y en unidades de 1/32 de casilla, z en px). Ver _chair_kit.py.

Cada hoja es una superficie de dos caras: un nervio que sale con un azimut y una elevación y se dobla hacia
abajo, ancho según su forma, con las dos mitades algo caídas (pliegue) y el nervio un tono más claro."""

from __future__ import annotations

import math

import numpy as np

from _chair_kit import Mat, Solid, Vec3, cylinder

C = 16.0
GROUP = "plant"

LEAF = Mat("leaf", light="#CBF166FF", top="#9ECC42FF", upper="#81A73AFF", left="#648132FF", right="#4C6029FF",
           dark="#425423FF", ink="#242F12FF")
CLAY = Mat("clay", light="#DB8A4EFF", top="#C56A33FF", upper="#AD5D2CFF", left="#945026FF", right="#76401FFF",
           dark="#602C11FF", ink="#4E1C05FF")
SOIL = Mat("soil", light="#8E6D53FF", top="#5D3526FF", upper="#53301FFF", left="#46281DFF", right="#3A2016FF",
           dark="#30180EFF", ink="#2A1206FF")
CERAMIC = Mat("ceramic", light="#FFFFFFFF", top="#E8E8E8FF", upper="#D2D1D1FF", left="#BBB9B9FF", right="#A4A2A1FF",
              dark="#6C6265FF", ink="#3E2E33FF")
RED = Mat("red", light="#C03D43FF", top="#C03D43FF", upper="#C03D43FF", left="#9B323AFF", right="#7C2323FF",
          dark="#7C2323FF", ink="#3E2E33FF")  # franja de la maceta: tres tonos, contorno de la cerámica

ORDER = ("dark", "right", "left", "upper", "top", "light")


def shift(tone: np.ndarray, where: np.ndarray, steps: int) -> np.ndarray:
    """Sube (steps > 0) o baja tonos dentro de su material; el contorno no se toca."""
    out = tone.copy()
    for k in zip(*np.nonzero(where)):
        mat, name = out[k].split(".")
        if name in ORDER:
            out[k] = f"{mat}.{ORDER[min(max(ORDER.index(name) + steps, 0), len(ORDER) - 1)]}"
    return out


def leaf(name: str, base: Vec3, azimuth: float, elevation: float, bend: float, length: float, width: float,
         twist: float = 0.0, shape: str = "oval", fold: float = 0.35, level: int = 1, steps: int = 6) -> Solid:
    """Hoja de ``length`` unidades y ``width`` de ancho máximo; ángulos en grados. ``level`` 0 la oscurece
    un tono (hojas de abajo), 2 la aclara."""
    az = math.radians(azimuth)
    h = (math.cos(az), math.sin(az))
    perp = (-math.sin(az), math.cos(az))
    tw = math.radians(twist)
    x, y, z = base
    spine: list[Vec3] = [(x, y, z)]
    for i in range(steps):
        pitch = math.radians(elevation - bend * (i + 0.5) / steps)
        d = length / steps
        x += h[0] * math.cos(pitch) * d
        y += h[1] * math.cos(pitch) * d
        z += 2 * math.sin(pitch) * d
        spine.append((x, y, z))
    lefts, rights = [], []
    for i, (sx, sy, sz) in enumerate(spine):
        t = i / steps
        if shape == "round":
            w = width * math.sin(math.pi * min(t ** 0.7, 1.0)) ** 0.45
        else:
            w = width * math.sin(math.pi * t) ** 0.6
        w = max(w, 0.25 if i == 0 else 0.0) / 2
        ox, oy, oz = perp[0] * math.cos(tw) * w, perp[1] * math.cos(tw) * w, 2 * math.sin(tw) * w
        drop = 2 * fold * w
        lefts.append((sx + ox, sy + oy, sz + oz - drop))
        rights.append((sx - ox, sy - oy, sz - oz - drop))
    faces = []
    for i in range(steps):
        faces.append([spine[i], lefts[i], lefts[i + 1], spine[i + 1]])
        faces.append([spine[i], spine[i + 1], rights[i + 1], rights[i]])
    pts = np.array(spine)

    def vein(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        # Distancia (en unidades, z a la mitad) del pixel al nervio.
        p = np.stack([mx, my, mz / 2], axis=-1)
        best = np.full(mx.shape, 1e9)
        for a, b in zip(pts[:-1], pts[1:]):
            a2, b2 = np.array([a[0], a[1], a[2] / 2]), np.array([b[0], b[1], b[2] / 2])
            ab = b2 - a2
            t = np.clip(((p - a2) @ ab) / max(ab @ ab, 1e-9), 0.0, 0.85)
            best = np.minimum(best, np.linalg.norm(p - (a2 + t[..., None] * ab), axis=-1))
        out = shift(tone, np.ones(mx.shape, dtype=bool), level - 1) if level != 1 else tone
        return shift(out, best < 0.45, 1)

    center = tuple(pts.mean(axis=0))
    return Solid(name, GROUP, "leaf", faces, center, two_sided=True, texture=vein)  # type: ignore[arg-type]


def pot(mat: str, r0: float, r1: float, height: float, lip: float, z0: float = 0.0, band=None,
        soil: bool = True) -> list[Solid]:
    """Maceta de tronco de cono con labio; arriba, el canto del labio y la tierra (con su sombra)."""
    rim = r1 + 0.5

    def body_band(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        if band is None:
            return tone
        b0, b1, other = band
        out = tone.copy()
        sel = (mz >= b0) & (mz < b1)
        for k in zip(*np.nonzero(sel)):
            out[k] = f"{other}.{out[k].split('.')[1]}"
        return out

    def mouth(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        out = tone.copy()
        top = mz > height - 0.3
        r = np.hypot(mx - C, my - C)
        inner = top & (r < rim - 1.0)
        if soil:
            out[inner] = "soil.top"
            # Sombra del labio sobre la tierra, del lado de atrás.
            back = inner & (np.hypot(mx - C - 0.8, my - C - 0.8) > rim - 1.4)
            out[back] = "soil.left"
        else:
            out[inner] = "leaf.dark"
        if soil:
            lip_lit = top & ~inner & (mx + my < 2 * C - rim * 0.5)
            out[lip_lit] = f"{mat}.light"
        return out

    return [
        cylinder("pot", GROUP, mat, C, C, r0, z0, height - lip + 0.5, sides=14, r_top=r1, texture=body_band),
        cylinder("rim", GROUP, mat, C, C, rim, height - lip, height, sides=14, r_top=rim, lit=False, texture=mouth),
    ]
