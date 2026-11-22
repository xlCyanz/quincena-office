"""Escritorio largo con computadora (conjunto desk_long_pro1), hecho con Moana. Ver ../_desk_sets.py.

Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/desk_long_pro1/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _desk_kit import main  # noqa: E402
from _desk_sets import SETS  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main(SETS["desk_long_pro1"], HERE))
