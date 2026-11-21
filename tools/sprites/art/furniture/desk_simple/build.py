"""Escritorio sencillo (1 x 1) de Quincena Office, hecho con Moana. El modelo está en ../_desk_kit.py.

Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/desk_simple/build.py [--out DIR] [--preview]

Sin --out reescribe esta carpeta. El apoyo de cada PNG va en manifest.json.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _desk_kit import DeskSpec, main  # noqa: E402

SPEC = DeskSpec(name="desk_simple", size=(1, 1), canvas=(128, 128), top_x=(1, 31))

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
