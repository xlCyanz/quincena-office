"""Mueble bajo de cocina (1×1) que comparten el microondas y la cafetera: dos puertas de madera naranja con
sus tiradores junto al medio, zócalo oscuro y mesón gris claro. Ver ``_boxes.py``."""

from __future__ import annotations

import numpy as np

from _boxes import box, faces, frame, ramp, rect

CAB = (4.5, 27.5, 5.8, 26.2, 0.0, 22.0)
WORKTOP = (3.8, 28.2, 5.1, 26.9, 22.0, 25.0)
WORK_TOP = WORKTOP[5]

WOOD = ramp("wood", "#DF823DFF", "#C26B24FF", "#894522FF", "#3C1300FF", "#EDA85DFF", "#5B2A10FF")
STONE = ramp("stone", "#D9D4CAFF", "#A39F98FF", "#827F79FF", "#3D3B44FF", "#F2EFE8FF", "#5C5A5CFF")
MATS = (WOOD, STONE)


def cabinet_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Dos puertas hundidas con tirador de metal junto a la junta del medio y zócalo oscuro."""
    f = faces(mx, my, mz, *CAB)
    out = tone.copy()
    mid = f.width / 2
    top = f.height - 2
    out[f.front & (frame(f, 2, mid - 0.5, 3, top) | frame(f, mid + 0.5, -2, 3, top))] = "wood.dark"
    knob = (np.abs(f.a - (mid - 3.5)) < 0.5) | (np.abs(f.a - (mid + 3)) < 0.5)
    out[f.front & knob & (f.b >= top - 8) & (f.b < top - 4)] = "wood.light"
    out[f.sides & (f.b < 2)] = "wood.dark"
    return out


def counter() -> list:
    return [box("cabinet", "counter", "wood", *CAB, texture=cabinet_texture),
            box("worktop", "counter", "stone", *WORKTOP, lit=True)]


SHADOW = ("bar", 16.0, 9.6, 16.0, 22.4, 11.84, 0, WORK_TOP)

