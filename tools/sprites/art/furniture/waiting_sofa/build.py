"""Sofá de espera de la Recepción de Quincena Office (2×1, cuatro rotaciones), hecho con Moana.
Ver ../_sofa.py.

Sofá rojo alto y mullido sobre patitas negras: faldón con costura, respaldo corrido alto de tapa redonda que une todo, tres
cojines de asiento abultados con vivo al frente, tres cojines de respaldo con botón más bajos que el respaldo, sobre los
asientos y brazos de una pieza con la tapa enrollada hacia afuera. Los cojines y brazos son ``puff``, que se
curvan igual hacia los cuatro lados, así el sofá se ve parejo en las cuatro rotaciones. Se sienta mirando a −y en rotación 0. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/waiting_sofa/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _boxes import box, ramp  # noqa: E402
from _chair_kit import PieceSpec, main_piece  # noqa: E402
from _sofa import puff, soft  # noqa: E402

GROUP = "sofa"
X0, X1, Y0, Y1 = 1.5, 62.5, 2.5, 31.0
ARM = 8.0
GAP = 0.8
SEATS = 3
LEG, BASE, SEAT, BACK = 2.0, 12.0, 19.0, 38.0
PILLOW = 33.0  # tapa de los cojines del respaldo, más bajos que el respaldo para que este los una
ARM_TOP = 32.0  # brazos, con el rollo

CUSHION = ramp("cushion", "#C03D43FF", "#A8353BFF", "#8A2A30FF", "#450E22FF", "#E06A6FFF", "#6D120AFF")
FRAME = ramp("frame", "#A8323AFF", "#8E2A31FF", "#741F26FF", "#450E22FF", "#C03D43FF", "#5A0F12FF")
LEGS = ramp("legs", "#313030FF", "#222020FF", "#1C1C1CFF", "#000000FF", "#4F4F4FFF", "#111111FF")


def model() -> list:
    s = [box("legs", GROUP, "legs", x, x + 2.0, y, y + 2.0, 0, LEG) for x in (4.0, 58.0) for y in (4.0, 27.0)]
    s.append(soft("base", GROUP, "frame", X0, X1, Y0, Y1, LEG, BASE, 0.5, "base"))
    inner = (X0 + ARM, X1 - ARM)
    # Respaldo corrido entre los brazos, de tapa redonda; los cojines se apoyan delante.
    s.append(puff("back", GROUP, "frame", inner[0] - 0.5, inner[1] + 0.5, Y1 - 5.0, Y1, BASE - 2, BACK, 1.5,
                  2.0, 6.0, "back"))
    step = (inner[1] - inner[0]) / SEATS
    for k in range(SEATS):
        x0 = inner[0] + k * step + (GAP / 2 if k else 0.3)
        x1 = inner[0] + (k + 1) * step - (GAP / 2 if k < SEATS - 1 else 0.3)
        s.append(puff(f"seat{k}", GROUP, "cushion", x0, x1, Y0 + 0.5, Y1 - 8.0, BASE - 1, SEAT, 2.0, 1.2, 3.0, "seat"))
        s.append(puff(f"pillow{k}", GROUP, "cushion", x0 - 0.2, x1 + 0.2, Y1 - 10.0, Y1 - 4.5, SEAT - 2, PILLOW, 3.0,
                      2.4, 8.0, "pillow"))
    for k, x in enumerate((X0, X1 - ARM)):
        # Brazo de una pieza con la tapa enrollada hacia afuera y la costura del rollo al frente.
        s.append(puff(f"arm{k}", GROUP, "frame", x, x + ARM, Y0, Y1, BASE - 2, ARM_TOP, 2.5, ARM / 2 - 0.6, 9.0,
                      "arm"))
    return s


SPEC = PieceSpec(
    name="waiting_sofa",
    mats={m.name: m for m in (CUSHION, FRAME, LEGS)},
    model=model,
    shadow=[("bar", 9.6, 16.6, 54.4, 16.6, 14.0, 0, BACK)],
    max_colors=20,
    size=(2, 1),
    canvas=(192, 128),
    rotations=(0, 1, 2, 3),
)

if __name__ == "__main__":
    raise SystemExit(main_piece(SPEC, HERE))
