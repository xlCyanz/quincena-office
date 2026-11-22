"""Alfombra decorativa de Quincena Office (2×2, se pisa como un piso), hecha con Moana.

Plana: cada pixel del rombo se lleva a la planta (a, b de 0 a 128 px a lo largo de x e y) y se pinta el
diseño: borde vino oscuro, banda crema con greca entre filetes dorados, campo vino con trama de tejido,
rombitos en las esquinas y medallón central de rombos en capas con cuatro puntas. Lienzo 256×128, apoyo (128, 32). Desde el
repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/rug/build.py [--out DIR] [--preview]
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent))
sys.path.insert(0, str(HERE.parent))

from _chair_kit import moana_render  # noqa: E402
from _painter import document  # noqa: E402

NAME = "rug"
CANVAS = (256, 128)
ORIGIN = (128.0, 0.0)  # pantalla del punto (0, 0, 0) de la planta
ANCHOR = [128, 32]
SIZE = 128  # px de diseño por lado (2 casillas de 64)
COLORS = {
    "field": "#9C4F5EFF", "weave": "#894553FF", "dark": "#7A3846FF", "cream": "#E8D6B0FF",
    "cream_dark": "#CDB993FF", "gold": "#D4A046FF", "navy": "#34456BFF", "pink": "#BA848EFF",
}


def design(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Nombre del color en cada punto (a, b) del diseño."""
    edge = np.minimum(np.minimum(a, SIZE - 1 - a), np.minimum(b, SIZE - 1 - b))
    out = np.full(a.shape, "field", dtype=object)
    out[(np.mod(a + 2 * b, 8) == 0) & (np.mod(b, 4) == 0)] = "weave"  # trama del tejido
    out[edge < 2] = "dark"
    band = (edge >= 3) & (edge < 13)
    out[band] = "cream"
    along = np.where(np.minimum(a, SIZE - 1 - a) == edge, b, a)
    out[band & ((edge == 3) | (edge == 12))] = "cream_dark"  # la banda se hunde un poco en sus bordes
    greca = band & (edge >= 6) & (edge < 10) & (np.mod(along, 8) < 4) & (np.mod(along + edge, 8) < 6)
    out[greca] = "dark"
    out[(edge == 13) | (edge == 2)] = "gold"
    field = edge >= 14
    # Medallón: rombos en capas (un cuadrado del diseño es un rombo en pantalla).
    da = np.abs(a + 0.5 - SIZE / 2.0)
    db = np.abs(b + 0.5 - SIZE / 2.0)
    diamond = np.maximum(da, db) * 1.4
    # Puntas del medallón: rombitos sobre los ejes del diseño.
    tips = np.full(a.shape, 99.0)
    for ca, cb in ((SIZE / 2 - 27, SIZE / 2), (SIZE / 2 + 27, SIZE / 2), (SIZE / 2, SIZE / 2 - 27),
                   (SIZE / 2, SIZE / 2 + 27)):
        tips = np.minimum(tips, np.maximum(np.abs(a + 0.5 - ca), np.abs(b + 0.5 - cb)) * 1.4)
    out[field & ((diamond < 34) | (tips < 9))] = "dark"
    out[field & ((diamond < 30) | (tips < 6))] = "gold"
    out[diamond < 26] = "navy"
    out[diamond < 17] = "field"
    out[(diamond < 17) & (np.mod(a + b, 4) == 0)] = "pink"
    out[diamond < 9] = "cream"
    out[diamond < 4] = "gold"
    # Rombitos en las esquinas del campo.
    for ca, cb in ((30, 30), (98, 30), (30, 98), (98, 98)):
        corner = np.maximum(np.abs(a + 0.5 - ca), np.abs(b + 0.5 - cb)) * 1.4
        out[field & (corner < 9)] = "gold"
        out[field & (corner < 5)] = "navy"
    return out


def draw() -> np.ndarray:
    w, h = CANVAS
    ys, xs = np.mgrid[0:h, 0:w]
    rx, ry = xs + 0.5 - ORIGIN[0], ys + 0.5 - ORIGIN[1]
    gu, gv = (ry / 32.0 + rx / 64.0) / 2.0, (ry / 32.0 - rx / 64.0) / 2.0
    inside = (gu >= 0) & (gu < 2) & (gv >= 0) & (gv < 2)
    a, b = np.floor(np.clip(gu, 0, 1.999) * 64), np.floor(np.clip(gv, 0, 1.999) * 64)
    names = design(a, b)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    for name, hexa in COLORS.items():
        sel = inside & (names == name)
        out[sel] = [int(hexa[i:i + 2], 16) for i in (1, 3, 5, 7)]
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Genera la alfombra con Moana.")
    parser.add_argument("--out", type=Path, default=HERE, help="carpeta de salida (por defecto, la del build.py)")
    parser.add_argument("--preview", action="store_true", help="escribe también rug_preview.png")
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    image = draw()
    doc = document(NAME, image)
    (out / f"{NAME}.moana.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
    drawn = moana_render(doc)
    ok = np.array_equal(drawn, image)
    Image.fromarray(drawn, "RGBA").save(out / f"{NAME}.png")
    manifest = {"_comentario": "Apoyo (px del sprite) de cada PNG de esta carpeta; lo escribe build.py y export_game.py "
                               "lo pasa al juego.", "sprites": {f"{NAME}.png": {"anchor": ANCHOR}}}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.preview:
        Image.fromarray(drawn, "RGBA").resize((CANVAS[0] * 4, CANVAS[1] * 4), Image.NEAREST).save(
            out / f"{NAME}_preview.png")
    if not ok:
        print("FALLO: rug: Moana no da los mismos pixeles que el dibujo")
    print("RESULTADO:", "OK" if ok else "1 fallo")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
