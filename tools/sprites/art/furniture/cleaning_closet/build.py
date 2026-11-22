"""Armario de limpieza de Quincena Office (1×1, cuatro rotaciones), hecho con Moana. Ver ../_cleaning.py.

Armario gris azulado de esquinas redondeadas sobre un zócalo, con dos puertas en relieve (rejillas arriba
y abajo, tiradores cromados y el cartel amarillo de piso mojado) y dos rociadores encima. Delante, el balde
amarillo con el trapeador y su escurridor. El frente mira a −y en rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/cleaning_closet/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _bath import CHROME  # noqa: E402
from _boxes import box, colors, faces, ramp, rect  # noqa: E402
from _chair_kit import PieceSpec, beam, cylinder, main_piece, slab  # noqa: E402
from _cleaning import BUCKET, GREY, WATER, bucket_top  # noqa: E402

GROUP = "closet"
X0, X1, Y0, Y1 = 9.6, 27.0, 13.6, 27.4
FY0 = 12.4
PLINTH, TOP = 2.0, 62.0
DOORS = ((18.5, 26.5), (10.1, 18.1))  # izquierda y derecha mirando el frente
BUCKET_C = (6.0, 8.0)
BUCKET_TOP = 10.0

BODY = ramp("body", "#8FA3B8FF", "#7A8FA4FF", "#62768AFF", "#1F2A36FF", "#B4C4D3FF", "#4E5F70FF")
WOOD = ramp("wood", "#DF823DFF", "#C26B24FF", "#894522FF", "#3C1300FF", "#EDA85DFF", "#743B0EFF")
MOP = ramp("mop", "#E8E4D8FF", "#D2CCBCFF", "#B7B09EFF", "#3D3B44FF", "#FFFFFFFF", "#8F8878FF")
SIGN = colors("sign", "#2A2A2AFF", top="#F0C030FF", upper="#2A2A2AFF")
SPRAY_A = ramp("spray_a", "#4F9BD0FF", "#3F84B5FF", "#336D96FF", "#0F2A3DFF", "#8FC8EBFF", "#24506FFF")
SPRAY_B = ramp("spray_b", "#6FE08AFF", "#55C26FFF", "#43A35AFF", "#123A1CFF", "#A8F0B8FF", "#2F7A41FF")


def door_texture(x0: float, x1: float, sign: bool):
    """Rejillas arriba y abajo, y en la de la izquierda el cartel amarillo de piso mojado."""

    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        f = faces(mx, my, mz, x0, x1, FY0, Y0 + 0.5, PLINTH + 0.5, TOP - 1.5)
        out = tone.copy()
        h = f.height
        for b0, b1 in ((4, 12), (h - 12, h - 4)):
            vent = f.front & rect(f, 3, -3, b0, b1)
            out[vent] = "body.right"
            out[vent & (np.mod(f.b, 2) < 1)] = "body.dark"
        if sign:
            s0 = np.floor(h * 0.5)
            card = f.front & rect(f, 4, -4, s0, s0 + 9)
            out[card] = "sign.top"
            out[card & rect(f, 6, -6, s0 + 2, s0 + 7) & (np.mod(f.a, 2) < 1)] = "sign.upper"
        return out

    return texture


def spray(part: str, mat: str, cx: float, cy: float) -> list:
    return [cylinder(part, GROUP, mat, cx, cy, 1.4, TOP, TOP + 6.0, sides=8, lit=True),
            box(f"{part}_head", GROUP, "grey", cx - 0.8, cx + 0.8, cy - 1.6, cy + 0.8, TOP + 6.0, TOP + 8.0, lit=True)]


def model() -> list:
    s = [
        box("plinth", GROUP, "body", X0 + 0.6, X1 - 0.6, Y0 - 0.6, Y1 - 0.6, 0, PLINTH),
        slab("body", GROUP, "body", (X0 + X1) / 2, (Y0 + Y1) / 2, (X1 - X0) / 2, (Y1 - Y0) / 2, 1.2, PLINTH, TOP,
             bevel=0.6, bevel_z=1.5, lit=True),
    ]
    for k, (x0, x1) in enumerate(DOORS):
        s.append(slab(f"door{k}", GROUP, "body", (x0 + x1) / 2, (FY0 + Y0 + 0.5) / 2, (x1 - x0) / 2,
                      (Y0 + 0.5 - FY0) / 2, 0.5, PLINTH + 0.5, TOP - 1.5, bevel=0.3, bevel_z=1.0, lit=True,
                      texture=door_texture(x0, x1, k == 0)))
    for k, x in enumerate((18.9, 17.0)):  # tiradores junto a la junta del medio
        s.append(box(f"handle{k}", GROUP, "chrome", x, x + 0.8, FY0 - 0.9, FY0, 26.0, 38.0, lit=True))
    s += spray("spray_a", "spray_a", 14.0, 20.0) + spray("spray_b", "spray_b", 20.5, 22.5)
    s += [
        cylinder("bucket", GROUP, "bucket", *BUCKET_C, 3.0, 0.0, BUCKET_TOP, sides=14, r_top=3.6, lit=True,
                 texture=bucket_top(*BUCKET_C, 3.6, BUCKET_TOP)),
        box("wringer", GROUP, "grey", BUCKET_C[0] - 1.8, BUCKET_C[0] + 1.8, BUCKET_C[1] + 2.0, BUCKET_C[1] + 3.6,
            BUCKET_TOP - 2.0, BUCKET_TOP + 3.0, lit=True),
        cylinder("mop_head", GROUP, "mop", BUCKET_C[0], BUCKET_C[1] - 0.4, 2.0, BUCKET_TOP - 1.0, BUCKET_TOP + 1.0,
                 sides=10, lit=True),
        beam("mop", GROUP, "wood", (BUCKET_C[0], BUCKET_C[1] - 0.4, BUCKET_TOP), (4.6, 12.0, 46.0), 0.6, 0.6),
    ]
    return s


SPEC = PieceSpec(
    name="cleaning_closet",
    mats={m.name: m for m in (BODY, CHROME, WOOD, MOP, SIGN, SPRAY_A, SPRAY_B, BUCKET, WATER, GREY)},
    model=model,
    shadow=[("bar", 18.2, 16.0, 18.2, 25.0, 9.6, 0, 20), ("disc", *BUCKET_C, 4.0, 0, BUCKET_TOP)],
    max_colors=44,
    rotations=(0, 1, 2, 3),
    painter=True,
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
