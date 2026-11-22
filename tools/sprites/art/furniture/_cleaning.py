"""Balde amarillo de trapear: lo comparten el armario de limpieza y el cubo con ruedas."""

from __future__ import annotations

import numpy as np

from _boxes import ramp

BUCKET = ramp("bucket", "#F0C030FF", "#D8A622FF", "#B5861AFF", "#3A2A06FF", "#FBE07AFF", "#8A6410FF")
WATER = ramp("water", "#8FB3C4FF", "#7A9DAEFF", "#64889AFF", "#2B3A44FF", "#B5D3E0FF", "#4F7182FF")
GREY = ramp("grey", "#7D868FFF", "#656D75FF", "#525960FF", "#22262BFF", "#A3ABB2FF", "#3D4349FF")


def bucket_top(cx: float, cy: float, rim: float, z_top: float):
    """Tapa del balde: aro amarillo y agua sucia adentro, con un reflejo."""

    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        out = tone.copy()
        top = mz > z_top - 0.3
        r = np.hypot(mx - cx, my - cy)
        inner = top & (r < rim - 0.9)
        out[inner] = "water.top"
        out[inner & (r < rim - 1.7) & (np.abs((mx - cx) + (my - cy) * 0.5 + 0.8) < 0.45)] = "water.light"
        out[top & (r >= rim - 0.9) & (r < rim - 0.5)] = "bucket.dark"
        return out

    return texture
