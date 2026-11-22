"""Piezas comunes de las sillas de oficina (rotación 0: frente a -y, respaldo en +y; x, y en unidades de 1/32
de casilla, z en px). Ver _chair_kit.py."""

from __future__ import annotations

import math

import numpy as np

from _chair_kit import BACK_GROUP, SEAT_GROUP, Mat, Solid, beam, cylinder, slab, upright

C = 16.0  # centro de la casilla
SEAT_TOP = 24  # la cadera del personaje sentado (character.SIT_SEAT_Z)
STAR = 8.3  # radio de la base de estrella
STAR_TURN = 54  # un brazo apunta al frente: ninguna rueda queda bajo el soporte del respaldo

RED = Mat("red", light="#CF4F4BFF", top="#A8323BFF", upper="#972C35FF", left="#86262FFF", right="#6C1E1FFF",
          dark="#5F0F09FF", ink="#3A0B1CFF")
NAVY = Mat("navy", light="#4F73A3FF", top="#33507AFF", upper="#2C466BFF", left="#263C5CFF", right="#1F3049FF",
           dark="#162236FF", ink="#0E1626FF")
PLASTIC = Mat("plastic", light="#4F4F4FFF", top="#313030FF", upper="#2A2828FF", left="#222020FF",
              right="#1C1C1CFF", dark="#131313FF", ink="#0C0C0CFF")
METAL = Mat("metal", light="#C9CDD3FF", top="#A3A8B0FF", upper="#8E939BFF", left="#7A7F87FF", right="#61656CFF",
            dark="#4A4D53FF", ink="#0C0C0CFF")

STEP = {"light": "top", "top": "upper", "upper": "left", "left": "right", "right": "dark", "dark": "dark",
        "ink": "ink"}


def darker(tone: np.ndarray, where: np.ndarray) -> np.ndarray:
    """Un tono más oscuro en ``where`` (mismo material)."""
    out = tone.copy()
    for k in zip(*np.nonzero(where)):
        mat, name = out[k].split(".")
        out[k] = f"{mat}.{STEP[name]}"
    return out


def rounded_sdf(x: np.ndarray, y: np.ndarray, cx: float, cy: float, hx: float, hy: float, r: float) -> np.ndarray:
    qx = np.abs(x - cx) - (hx - r)
    qy = np.abs(y - cy) - (hy - r)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


def base(hub_top: float = 7.0, column_top: float = 14.0) -> list[Solid]:
    """Base de estrella de 5 brazos con ruedas, cubo de plástico y columna de metal."""
    out = []
    for k in range(5):
        a = math.radians(STAR_TURN + 72 * k)
        tx, ty = C + STAR * math.cos(a), C + STAR * math.sin(a)
        out.append(beam("star", SEAT_GROUP, "plastic", (C, C, 5.5), (tx, ty, 4.2), 0.9, 1.1, lit=True))
        out.append(cylinder("wheel", SEAT_GROUP, "plastic", tx, ty, 1.3, 0.0, 3.2, sides=8))
    out.append(cylinder("hub", SEAT_GROUP, "plastic", C, C, 2.2, 2.0, hub_top, lit=True))
    out.append(cylinder("column", SEAT_GROUP, "metal", C, C, 0.9, hub_top, column_top, sides=8))
    return out


def cushion(mat: str, cy: float, half: float, z0: float, pan_z: float) -> list[Solid]:
    """Bandeja de plástico y cojín abultado con una costura a 2 unidades del canto."""

    def seam(x: np.ndarray, y: np.ndarray, z: np.ndarray, tone: np.ndarray) -> np.ndarray:
        d = rounded_sdf(x, y, C, cy, half, half, 3.0)
        return darker(tone, (z > SEAT_TOP - 0.5) & (d > -3.4) & (d < -2.6))

    return [
        slab("pan", SEAT_GROUP, "plastic", C, cy, half - 1.2, half - 1.2, 2.5, pan_z, z0 + 1),
        slab("seat", SEAT_GROUP, mat, C, cy, half, half, 3.0, z0, SEAT_TOP, bevel=1.2, bevel_z=2.5, lit=True,
             texture=seam),
    ]


def bracket(cy: float, top: float) -> list[Solid]:
    """Soporte en «J» del respaldo: brazo desde abajo del asiento hasta un poste detrás."""
    return [
        beam("bracket", BACK_GROUP, "plastic", (C, cy + 3.0, 14.5), (C, 25.3, 22.0), 1.0, 1.2),
        slab("post", BACK_GROUP, "plastic", C, 25.6, 1.1, 0.8, 0.3, 20.5, top, lit=True),
    ]


def padded_back(mat: str, hx: float, y0: float, y1: float, z0: float, z1: float) -> Solid:
    """Respaldo acolchado con un panel marcado por una costura."""
    cz = (z0 + z1) / 2

    def panel(x: np.ndarray, y: np.ndarray, z: np.ndarray, tone: np.ndarray) -> np.ndarray:
        on_face = y < y0 + 0.6  # solo el frente; atrás va liso
        d = rounded_sdf(x, (z - cz) / 2, C, 0.0, hx - 2.2, (z1 - z0) / 4 - 1.4, 1.5)
        return darker(tone, on_face & (np.abs(d) < 0.45))

    return upright("back", BACK_GROUP, mat, C, hx, y0, y1, z0, z1, 3.0, bevel=0.8, lit=True, texture=panel)


def mesh_back(hx: float, y0: float, y1: float, z0: float, z1: float) -> Solid:
    """Respaldo de malla: marco liso y, adentro, la malla un tono más oscura con tiras cada 2 px."""
    cz = (z0 + z1) / 2

    def mesh(x: np.ndarray, y: np.ndarray, z: np.ndarray, tone: np.ndarray) -> np.ndarray:
        on_face = (y < y0 + 0.6) | (y > y1 - 0.6)
        d = rounded_sdf(x, (z - cz) / 2, C, 0.0, hx, (z1 - z0) / 4, 3.5)
        inner = on_face & (d < -1.4)
        return darker(darker(tone, inner), inner & (np.floor(z) % 2 == 0))

    return upright("back", BACK_GROUP, "plastic", C, hx, y0, y1, z0, z1, 3.5, bevel=0.7, lit=True, texture=mesh)
