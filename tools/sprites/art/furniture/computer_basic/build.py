"""Computadora básica de Quincena Office (todo en uno crema de tubo, teclado y ratón), hecha con Moana.

Va encima de un escritorio; ver ../_computer_kit.py y ../_computers.py. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/computer_basic/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _computer_kit import DeskSpec, main  # noqa: E402
from _computers import COLORS_BASIC, basic_set  # noqa: E402

# El teclado entre x 10 y 22 deja a quien se sienta en el medio de la casilla.
SPEC = DeskSpec(name="computer_basic", size=(1, 1), canvas=(128, 160), model=lambda _s: (basic_set(10), None),
                colors=COLORS_BASIC, contact=("crt", "keyboard", "mouse"))

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
