"""Laptop de Quincena Office (solo sobre el escritorio ejecutivo), hecha con Moana.

Va encima de un escritorio; ver ../_computer_kit.py y ../_laptop.py. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/computer_laptop/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _computer_kit import DeskSpec, main  # noqa: E402
from _laptop import COLORS_LAPTOP, W, laptop  # noqa: E402

X0, Y0 = 16 - W / 2, 3  # centrada a lo largo de x
SPEC = DeskSpec(name="computer_laptop", size=(1, 1), canvas=(128, 160),
                model=lambda _s: (laptop(X0, Y0), None), colors=COLORS_LAPTOP, contact=("base",), seat=0.5)

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
