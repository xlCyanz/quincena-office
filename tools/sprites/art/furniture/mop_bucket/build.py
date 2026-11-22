"""Cubo de trapear de Quincena Office (una sola imagen), hecho con Moana. Ver ../_cleaning.py.

Balde amarillo sobre cuatro ruedas negras, con agua sucia y el escurridor gris atrás (palanca y rejilla).
El juego lo pone junto a quien trapea (OfficeCharacter); va en assets/sprites/characters/. Desde el
repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/mop_bucket/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, faces, ramp, rect  # noqa: E402
from _chair_kit import PieceSpec, beam, cylinder, main_piece  # noqa: E402
from _cleaning import BUCKET, GREY, WATER, bucket_top  # noqa: E402

GROUP = "bucket"
CX, CY = 16.0, 16.6
WHEELS, TOP = 3.0, 17.0
WRINGER = (12.8, 19.2, 10.2, 13.4, TOP - 3.0, TOP + 5.0)

WHEEL = ramp("wheel", "#33363CFF", "#2A2D32FF", "#212428FF", "#0E0F12FF", "#4E5258FF", "#17191CFF")


def wringer_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Rejilla de ranuras al frente y atrás del escurridor."""
    f = faces(mx, my, mz, *WRINGER)
    out = tone.copy()
    out[(f.front | f.back) & rect(f, 2, -2, 2, f.height - 2) & (np.mod(f.a, 2) < 1)] = "grey.dark"
    return out


def model() -> list:
    s = [cylinder(f"wheel{k}", GROUP, "wheel", x, y, 1.1, 0.0, WHEELS, sides=8) for k, (x, y) in
         enumerate(((12.5, 12.5), (19.5, 12.5), (12.5, 20.2), (19.5, 20.2)))]
    s += [
        cylinder("bucket", GROUP, "bucket", CX, CY, 4.2, WHEELS, TOP, sides=16, r_top=4.9, lit=True,
                 texture=bucket_top(CX, CY, 4.9, TOP)),
        box("wringer", GROUP, "grey", *WRINGER, lit=True, texture=wringer_texture),
        beam("lever", GROUP, "grey", (CX + 2.4, 11.8, TOP + 5.0), (CX + 2.4, 18.0, TOP + 9.0), 0.5, 0.6),
    ]
    return s


SPEC = PieceSpec(
    name="mop_bucket",
    mats={m.name: m for m in (BUCKET, WATER, GREY, WHEEL)},
    model=model,
    shadow=[("disc", CX, CY, 5.1, 0, TOP)],
    max_colors=24,
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
