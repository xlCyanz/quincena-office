"""Cojines y bloques acolchados de los sofás (sala de descanso y recepción), sobre ``_chair_kit.slab``."""

from __future__ import annotations

import math

import numpy as np

from _boxes import faces
from _chair_kit import Solid, _ring_faces, _rounded_rect, slab


def detail(mat: str, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, kind: str):
    """Sombra de 1 px al pie de cada bloque y, según ``kind``: botón del cojín de respaldo, costuras del brazo y del respaldo."""

    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        f = faces(mx, my, mz, x0, x1, y0, y1, z0, z1)
        out = tone.copy()
        out[f.sides & (f.b < 1.0)] = f"{mat}.dark"
        if kind == "pillow":
            button = f.front & (np.abs(f.a - f.width / 2) < 1.5) & (np.abs(f.b - f.height * 0.55) < 1.0)
            out[button] = f"{mat}.dark"
        elif kind == "arm":  # costura bajo el rollo del brazo, al frente y atrás
            out[(f.front | f.back) & (f.b >= f.height - 4) & (f.b < f.height - 3) & (f.a >= 1) & (f.a < f.width - 1)] = \
                f"{mat}.dark"
        elif kind == "back":  # costura a lo largo del respaldo, por detrás
            out[f.back & (f.b >= f.height - 5) & (f.b < f.height - 4) & (f.a >= 1) & (f.a < f.width - 1)] = \
                f"{mat}.dark"
        elif kind == "seat":  # vivo de 1 px en el canto del frente del cojín
            out[f.front & (f.b >= f.height - 4) & (f.b < f.height - 3)] = f"{mat}.light"
        elif kind == "base":
            out[f.sides & (f.b >= 1.0) & (f.b < 2.0)] = f"{mat}.right"
        return out

    return texture


def soft(part: str, group: str, mat: str, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float,
         bevel: float = 1.0, kind: str = "") -> Solid:
    """Bloque acolchado: esquinas redondeadas y la tapa que entra ``bevel`` unidades en los últimos 2 px."""
    return slab(part, group, mat, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, 1.5, z0, z1,
                bevel=bevel, bevel_z=2.0, lit=True, texture=detail(mat, x0, x1, y0, y1, z0, z1, kind))


def puff(part: str, group: str, mat: str, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float,
         r: float, round_xy: float, round_z: float, kind: str = "", steps: int = 4) -> Solid:
    """Bloque abultado parejo por los cuatro lados: planta redondeada de radio ``r`` y tapa que se curva
    hacia adentro ``round_xy`` unidades en los últimos ``round_z`` px (un cuarto de elipse), así se ve
    igual desde cualquier rotación."""
    cx, cy, hx, hy = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    rings = [[(x, y, z0) for x, y in _rounded_rect(cx, cy, hx, hy, r)]]
    for k in range(steps + 1):
        a = math.pi / 2 * k / steps
        inset = round_xy * (1 - math.cos(a))
        z = z1 - round_z + round_z * math.sin(a)
        pts = _rounded_rect(cx, cy, max(hx - inset, 0.3), max(hy - inset, 0.3), max(r - inset, 0.3))
        rings.append([(x, y, z) for x, y in pts])
    faces_ = [rings[0][::-1]]
    for lo, hi in zip(rings, rings[1:]):
        faces_ += _ring_faces(lo, hi)
    faces_.append(rings[-1])
    return Solid(part, group, mat, faces_, (cx, cy, (z0 + z1) / 2), lit=True,
                 texture=detail(mat, x0, x1, y0, y1, z0, z1, kind))  # type: ignore[arg-type]
