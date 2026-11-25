"""Iconos de la barra de la partida de Quincena Office con Moana (ui_<icono>): 24×24, blancos sobre transparente.

Godot los tiñe con el color del botón (claro normal, oscuro al estar pulsado), por eso van en blanco puro. Cada
icono se arma con rectángulos en una cuadrícula de 12×12 (como en el diseño de la interfaz) y se agranda ×2:
``+`` pinta y ``-`` vacía lo pintado antes. Apoyo en el centro (12, 12). Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/icons/ui/build.py [--out DIR] [--preview]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))  # art: _painter
sys.path.insert(0, str(HERE.parents[1] / "furniture"))  # _chair_kit

from _chair_kit import moana_render  # noqa: E402
from _painter import document  # noqa: E402

GRID = 12
SCALE = 2
SIZE = (GRID * SCALE, GRID * SCALE)
INK = (255, 255, 255, 255)
# Icono -> rectángulos (signo, x, y, ancho, alto) en la cuadrícula de 12.
ICONS = {
    # Martillo.
    "build": [("+", 1, 1, 7, 3), ("-", 1, 3, 1, 1), ("+", 4, 4, 2, 7)],
    # Encuadre: cuatro esquinas.
    "frame": [("+", 1, 1, 4, 1), ("+", 1, 1, 1, 4), ("+", 7, 1, 4, 1), ("+", 10, 1, 1, 4),
              ("+", 1, 10, 4, 1), ("+", 1, 7, 1, 4), ("+", 7, 10, 4, 1), ("+", 10, 7, 1, 4), ("+", 5, 5, 2, 2)],
    # Flecha arriba y abajo.
    "walls": [("+", 5, 2, 2, 8), ("+", 3, 3, 6, 1), ("+", 4, 2, 4, 1), ("+", 5, 1, 2, 1),
              ("+", 3, 8, 6, 1), ("+", 4, 9, 4, 1), ("+", 5, 10, 2, 1)],
    # Persona.
    "staff": [("+", 4, 1, 4, 4), ("+", 2, 6, 8, 5), ("-", 2, 6, 1, 1), ("-", 9, 6, 1, 1)],
    # Portapapeles con renglones.
    "projects": [("+", 1, 2, 10, 9), ("+", 4, 1, 4, 2), ("-", 3, 5, 6, 1), ("-", 3, 7, 6, 1), ("-", 3, 9, 4, 1)],
    # Reloj.
    "teams": [("+", 1, 1, 10, 10), ("-", 2, 2, 8, 8), ("-", 1, 1, 1, 1), ("-", 10, 1, 1, 1), ("-", 1, 10, 1, 1),
              ("-", 10, 10, 1, 1), ("+", 5, 3, 2, 4), ("+", 6, 5, 3, 2)],
    # Banco con columnas.
    "bank": [("+", 5, 1, 2, 1), ("+", 3, 2, 6, 1), ("+", 1, 3, 10, 1), ("+", 2, 5, 2, 5), ("+", 5, 5, 2, 5),
             ("+", 8, 5, 2, 5), ("+", 1, 10, 10, 1)],
    # Edificio con ventanas.
    "company": [("+", 2, 1, 8, 10), ("-", 3, 2, 2, 2), ("-", 7, 2, 2, 2), ("-", 3, 5, 2, 2), ("-", 7, 5, 2, 2),
                ("-", 5, 8, 2, 3)],
    # Puerta con flecha de salida.
    "ceo": [("+", 1, 1, 6, 10), ("-", 2, 2, 4, 8), ("+", 4, 6, 1, 1), ("+", 7, 5, 4, 2), ("+", 9, 4, 1, 4)],
    # Engranaje.
    "settings": [("+", 2, 2, 8, 8), ("-", 4, 4, 4, 4), ("+", 5, 0, 2, 2), ("+", 5, 10, 2, 2), ("+", 0, 5, 2, 2),
                 ("+", 10, 5, 2, 2)],
}


def icon(rects: list[tuple[str, int, int, int, int]]) -> np.ndarray:
    grid = np.zeros((GRID, GRID), dtype=bool)
    for sign, x, y, w, h in rects:
        grid[y:y + h, x:x + w] = sign == "+"
    mark = np.kron(grid, np.ones((SCALE, SCALE), dtype=bool))
    out = np.zeros((SIZE[1], SIZE[0], 4), dtype=np.uint8)
    out[mark] = INK
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Genera los iconos de la barra (ui_*) con Moana.")
    parser.add_argument("--out", type=Path, default=HERE, help="carpeta de salida (por defecto, la del build.py)")
    parser.add_argument("--preview", action="store_true", help="escribe también ui_preview.png")
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    sprites: dict[str, object] = {}
    shown = []
    for key, rects in ICONS.items():
        name = "ui_" + key
        image = icon(rects)
        if not (image[..., 3] > 0).any():
            problems.append(f"{name}: está vacío")
        doc = document(name, image)
        (out / f"{name}.moana.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
        drawn = moana_render(doc)
        if not np.array_equal(drawn, image):
            problems.append(f"{name}: Moana no da los mismos pixeles que el dibujo")
        Image.fromarray(drawn, "RGBA").save(out / f"{name}.png")
        sprites[f"{name}.png"] = {"kind": "icon", "canvas": list(SIZE), "anchor": [SIZE[0] / 2, SIZE[1] / 2]}
        shown.append(drawn)
    manifest = {"_comentario": "Apoyo (px del sprite) de cada PNG de esta carpeta; lo escribe build.py y export_game.py "
                               "lo pasa al juego.", "sprites": sprites}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.preview:
        w, h = SIZE
        sheet = Image.new("RGBA", (w * 4 * len(shown), h * 4), (48, 53, 74, 255))
        for k, img in enumerate(shown):
            cell = Image.new("RGBA", SIZE, (48, 53, 74, 255))
            cell.alpha_composite(Image.fromarray(img, "RGBA"))
            sheet.paste(cell.resize((w * 4, h * 4), Image.NEAREST), (k * w * 4, 0))
        sheet.save(out / "ui_preview.png")
    for line in problems:
        print("FALLO:", line)
    print("RESULTADO:", "OK" if not problems else f"{len(problems)} fallos")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
