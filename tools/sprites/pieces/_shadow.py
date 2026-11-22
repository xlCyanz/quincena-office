# Sombra de piso de un tono (discos y barras corridos con la altura), recortada a la planta del mueble.
# La usan las piezas del generador; con "_" generate.py no lo corre como grupo.
import numpy as np
from PIL import Image

import iso

SHADOW_COLOR = (26, 28, 38)  # el mismo tono que Canvas.ground_shadow()
SHADOW_SHIFT = (0.10, 0.03)  # corrimiento de la sombra por cada 64 px de alto (casillas del mundo)


def floor_shadow(c, shapes):
    """Sombra de un tono en el piso, recortada a la planta. shapes: ("disc", x, y, r, z0, z1) o
    ("bar", x0, y0, x1, y1, r, z0, z1); cada forma se corre SHADOW_SHIFT por cada 64 px de alto."""
    ys, xs = np.mgrid[0:c.height, 0:c.width]
    rx = xs + 0.5 - c.origin[0]
    ry = ys + 0.5 - c.origin[1]
    gu = (ry / 32.0 + rx / 64.0) / 2.0
    gv = (ry / 32.0 - rx / 64.0) / 2.0
    mask = np.zeros(gu.shape, dtype=bool)
    for shape in shapes:
        z0, z1 = shape[-2], shape[-1]
        for step in range(5):
            z = z0 + (z1 - z0) * step / 4.0
            su, sv = SHADOW_SHIFT[0] * z / 64.0, SHADOW_SHIFT[1] * z / 64.0
            if shape[0] == "disc":
                u, v = c.to_world(shape[1], shape[2])
                mask |= (gu - u - su) ** 2 + (gv - v - sv) ** 2 <= shape[3] * shape[3]
            else:
                ua, va = c.to_world(shape[1], shape[2])
                ub, vb = c.to_world(shape[3], shape[4])
                du, dv = ub - ua, vb - va
                along = np.clip(((gu - su - ua) * du + (gv - sv - va) * dv) / (du * du + dv * dv), 0.0, 1.0)
                mask |= ((gu - su - ua - du * along) ** 2 + (gv - sv - va - dv * along) ** 2
                         <= shape[5] * shape[5])
    w, d = c.world_size
    mask &= (gu >= 0) & (gu < w) & (gv >= 0) & (gv < d)
    rgba = np.zeros(mask.shape + (4,), dtype=np.uint8)
    rgba[mask, :3] = SHADOW_COLOR
    rgba[mask, 3] = 255
    return Image.fromarray(rgba, "RGBA")


def save_shadow(c, out_dir, name, shapes):
    return iso.save(floor_shadow(c, shapes), out_dir, name, kind="shadow", footprint=list(c.world_size),
                    anchor=list(c.anchor))
