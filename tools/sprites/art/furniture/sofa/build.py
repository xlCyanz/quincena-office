"""Sofá de la Sala de descanso de Quincena Office (2×1, cuatro rotaciones), hecho con Moana. Ver ../_sofa.py.

Sofá lila: base sobre cuatro patas de madera, dos cojines de asiento abultados, dos cojines de respaldo
con botón contra el marco y brazos rectos acolchados con costura; sombra de 1 px al pie de cada cojín. El frente mira a −y en rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/sofa/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, ramp  # noqa: E402
from _chair_kit import PieceSpec, main_piece  # noqa: E402
from _sofa import soft  # noqa: E402

GROUP = "sofa"
X0, X1, Y0, Y1 = 2.0, 62.0, 4.0, 30.0
ARM = 6.0
GAP = 1.6  # unidades entre los cojines
LEG, BASE, SEAT, ARM_TOP, BACK = 4.0, 11.0, 18.0, 24.0, 32.0

CUSHION = ramp("cushion", "#8F6CBFFF", "#7A5CA8FF", "#5E4682FF", "#2A1640FF", "#B198D2FF", "#46325FFF")
FRAME = ramp("frame", "#75539FFF", "#634689FF", "#4E376DFF", "#2A1640FF", "#8F6CBFFF", "#37234EFF")
WOOD = ramp("wood", "#B86A32FF", "#9A5428FF", "#743B0EFF", "#2A1208FF", "#DF823DFF", "#5B2A10FF")


def model() -> list:
    s = [box("legs", GROUP, "wood", x, x + 2.5, y, y + 2.5, 0, LEG) for x in (3.0, 58.5) for y in (5.0, 26.5)]
    s.append(soft("base", GROUP, "frame", X0, X1, Y0, Y1, LEG, BASE, 0.5, "base"))
    inner = (X0 + ARM, X1 - ARM)
    s.append(soft("back", GROUP, "frame", inner[0], inner[1], Y1 - 6, Y1, BASE - 2, BACK, 1.5, "back"))
    half = (inner[1] - inner[0]) / 2
    for k in range(2):
        x0 = inner[0] + k * half + (GAP / 2 if k else 0.0)  # hueco entre los dos cojines
        x1 = inner[0] + (k + 1) * half - (0.0 if k else GAP / 2)
        s.append(soft(f"seat{k}", GROUP, "cushion", x0, x1, Y0 + 0.5, Y1 - 6.5, BASE - 1, SEAT, 1.5))
        s.append(soft(f"pillow{k}", GROUP, "cushion", x0 + 0.4, x1 - 0.4, Y1 - 10, Y1 - 5.5, SEAT - 1, BACK - 3, 1.0, "pillow"))
    for k, x in enumerate((X0, X1 - ARM)):
        s.append(soft(f"arm{k}", GROUP, "frame", x, x + ARM, Y0, Y1, BASE - 2, ARM_TOP, 1.0, "arm"))
    return s


SPEC = PieceSpec(
    name="sofa",
    mats={m.name: m for m in (CUSHION, FRAME, WOOD)},
    model=model,
    shadow=[("bar", 9.6, 16.6, 54.4, 16.6, 13.44, 0, BACK)],
    size=(2, 1),
    canvas=(192, 128),
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
