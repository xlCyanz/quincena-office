"""Muebles de cajas para ``_chair_kit.PieceSpec``: material desde una rampa, caja y caras de una caja.

Los detalles (puertas, cajones, luces) se pintan con ``texture(mx, my, mz, tono)`` sobre coordenadas del
modelo en rotación 0; ``Faces`` dice a qué cara de la caja pertenece cada pixel y dónde cae en ella, en px:
``a`` a lo largo de la cara (de izquierda a derecha vista desde afuera) y ``b`` hacia arriba desde su base. El frente es −y.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from _chair_kit import Mat, Solid, slab


def mix(a: str, b: str, t: float = 0.5) -> str:
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#%02X%02X%02XFF" % tuple(round(x + (y - x) * t) for x, y in zip(ca, cb))


def ramp(name: str, base: str, left: str, right: str, ink: str, light: str, dark: str) -> Mat:
    """Material con la cara de arriba ``base``, las caras +y ``left`` y +x ``right``; ``upper`` (caras
    inclinadas) sale a mitad de base y left."""
    return Mat(name, light=light, top=base, upper=mix(base, left), left=left, right=right, dark=dark, ink=ink)


def colors(name: str, ink: str, **slots: str) -> Mat:
    """Material de colores sueltos para detalles: cada tono (light, top, upper, left, right, dark) es un color."""
    full = {k: slots.get(k, ink) for k in ("light", "top", "upper", "left", "right", "dark")}
    return Mat(name, ink=ink, **full)


def box(part: str, group: str, mat: str, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float,
        **kw: object) -> Solid:
    """Caja recta de x0 a x1, y0 a y1 (unidades) y z0 a z1 (px)."""
    return slab(part, group, mat, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, 0.01, z0, z1, **kw)


@dataclass
class Faces:
    """Caras de la caja (x0, x1, y0, y1, z0, z1) en los pixeles de una textura."""

    top: np.ndarray
    front: np.ndarray  # −y
    back: np.ndarray  # +y
    left: np.ndarray  # −x
    right: np.ndarray  # +x
    a: np.ndarray  # px de izquierda a derecha vista desde afuera (en la tapa, a lo largo de x)
    b: np.ndarray  # px desde la base de la cara (en la tapa, a lo largo de y)
    width: np.ndarray  # px de ancho de la cara
    height: float  # px de alto de las caras de los costados

    @property
    def sides(self) -> np.ndarray:
        return self.front | self.back | self.left | self.right


def faces(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, x0: float, x1: float, y0: float, y1: float, z0: float,
          z1: float) -> Faces:
    eps = 0.3
    top = mz > z1 - eps
    side = ~top
    front = side & (my < y0 + eps)
    back = side & ~front & (my > y1 - eps)
    left = side & ~front & ~back & (mx < x0 + eps)
    right = side & ~front & ~back & ~left
    along_x = front | back | top
    # De izquierda a derecha mirando la cara desde afuera (en la tapa, a lo largo de x).
    a = np.select([front, back, left, right], [x1 - mx, mx - x0, my - y0, y1 - my], mx - x0) * 2.0
    b = np.where(top, (my - y0) * 2.0, mz - z0)
    width = np.where(along_x, (x1 - x0) * 2.0, (y1 - y0) * 2.0)
    return Faces(top, front, back, left, right, a, b, width, z1 - z0)


def rect(f: Faces, a0: float, a1: float, b0: float, b1: float) -> np.ndarray:
    """Pixeles con a en [a0, a1) y b en [b0, b1) (negativos se cuentan desde el final de la cara)."""
    a0 = np.where(a0 < 0, f.width + a0, a0)
    a1 = np.where(a1 <= 0, f.width + a1, a1)
    return (f.a >= a0) & (f.a < a1) & (f.b >= b0) & (f.b < b1)


def frame(f: Faces, a0: float, a1: float, b0: float, b1: float) -> np.ndarray:
    """Borde de 1 px del rectángulo de ``rect``."""
    return rect(f, a0, a1, b0, b1) & ~rect(f, a0 + 1, a1 - 1, b0 + 1, b1 - 1)
