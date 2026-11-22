"""Computadora pro de Quincena Office (pantalla plana negra, torre, teclado y ratón), hecha con Moana.

Va encima de un escritorio; ver ../_computer_kit.py y ../_computers.py. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/computer_pro/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _computer_kit import DeskSpec, main  # noqa: E402
from _computers import COLORS_PRO, pro_set, tower  # noqa: E402

SPEC = DeskSpec(name="computer_pro", size=(1, 1), canvas=(128, 160),
                model=lambda _s: (pro_set(11, 12, 8, tower(3, 8, 9, 21)), None), colors=COLORS_PRO,
                contact=("foot", "keyboard", "mouse", "tower"))

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
