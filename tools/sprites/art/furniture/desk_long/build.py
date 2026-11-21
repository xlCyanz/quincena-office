"""Escritorio largo (2 x 1) de Quincena Office, hecho con Moana. El modelo está en ../_desk_kit.py.

Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/desk_long/build.py [--out DIR] [--preview]

Sin --out reescribe esta carpeta. El apoyo de cada PNG va en manifest.json.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _desk_kit import DeskSpec, main  # noqa: E402

# Lienzo del juego actual (data/sprites.json): 192 x 192, apoyo (64, 128) y (128, 128).
SPEC = DeskSpec(name="desk_long", size=(2, 1), canvas=(192, 192), top_x=(9, 55))

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE))
