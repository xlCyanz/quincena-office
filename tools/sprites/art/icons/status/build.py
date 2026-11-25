"""Globos de estado de Quincena Office con Moana: se dibujan arriba a la derecha de la cabeza de un empleado.

* ``status_no_station`` (gris, «?»): no tiene puesto;
* ``status_tired`` (azul, «z»): cansado;
* ``status_upset`` (rojo, «!»): molesto;
* ``status_stressed`` (naranja, «#»): estresado;
* ``status_idle`` (gris claro, «…»): sin trabajo.

Lienzo 32×36: círculo de 29 px con contorno oscuro, luz arriba a la izquierda, sombra abajo a la derecha y una
colita abajo a la izquierda que apunta a la cabeza; el signo va en blanco con sombra de 1 px. Apoyo en el centro
del círculo (16, 15). Ningún tono puede ser de un personaje (los dibuja el mismo nodo, con el shader de paleta).
Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/icons/status/build.py [--out DIR] [--preview]
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

SIZE = (32, 36)
CENTER = (16.0, 15.0)
RADIUS = 13.5  # relleno; el contorno es 1 px más
INK = "f6f4ee"  # signo
# Icono -> color del globo y signo (a media resolución: cada carácter es un cuadro de 2×2 px).
ICONS = {
    "no_station": ("8a8f99", [".###.", "#...#", "....#", "...#.", "..#..", "..#..", ".....", "..#.."]),
    "tired": ("5b8bd9", [".....", ".....", "#####", "...#.", "..#..", ".#...", "#####", "....."]),
    "upset": ("d9534f", ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#..", "....."]),
    "stressed": ("e08a2c", [".....", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".....", "....."]),
    "idle": ("a6a6a6", [".....", ".....", ".....", ".....", ".....", "#.#.#", ".....", "....."]),
}


def rgb(hexa: str) -> np.ndarray:
    return np.array([int(hexa[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def mix(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    return np.round(a + (b - a) * t)


def bubble(base_hex: str, glyph: list[str]) -> np.ndarray:
    w, h = SIZE
    ys, xs = np.mgrid[0:h, 0:w]
    px, py = xs + 0.5 - CENTER[0], ys + 0.5 - CENTER[1]
    dist = np.hypot(px, py)
    # Colita: triángulo abajo a la izquierda, de la panza del círculo hacia la cabeza.
    tx, ty = xs + 0.5, ys + 0.5
    tail = (ty >= 24) & (ty <= 33) & (tx >= 4) & (tx - 4 <= (33 - ty) * 0.9) & (tx - 4 >= (33 - ty) * 0.15)
    fill = (dist <= RADIUS) | tail
    grown = np.zeros_like(fill)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            grown |= np.roll(np.roll(fill, dy, 0), dx, 1)
    outline = grown & ~fill
    base = rgb(base_hex)
    black = rgb("1c1e2a")
    out = np.zeros((h, w, 4), dtype=np.uint8)
    tones = {
        "outline": mix(base, black, 0.78),
        "shade": mix(base, black, 0.22),
        "base": base,
        "light": mix(base, rgb("ffffff"), 0.35),
        "ink": rgb(INK),
        "ink_shadow": mix(base, black, 0.45),
    }
    # Luz y sombra en medias lunas: la sombra es lo que queda fuera del círculo corrido arriba a la izquierda y
    # la luz, lo que queda fuera del corrido abajo a la derecha (más una mancha de brillo).
    out[outline] = [*tones["outline"], 255]
    out[fill] = [*tones["base"], 255]
    shade = tail | (np.hypot(px + 2.5, py + 2.5) > RADIUS)
    out[fill & shade] = [*tones["shade"], 255]
    light = (np.hypot(px - 2.0, py - 2.0) > RADIUS) & (px + py < -4) | (np.hypot(px + 5.5, py + 5.5) <= 2.6)
    out[fill & light & ~tail] = [*tones["light"], 255]
    # Signo centrado en el círculo, cada carácter 2×2, con sombra 1 px abajo a la derecha.
    rows, cols = len(glyph), len(glyph[0])
    x0 = int(CENTER[0] - cols)
    y0 = int(CENTER[1] - rows) + 1
    mark = np.zeros((h, w), dtype=bool)
    for r, line in enumerate(glyph):
        for c, ch in enumerate(line):
            if ch == "#":
                mark[y0 + 2 * r:y0 + 2 * r + 2, x0 + 2 * c:x0 + 2 * c + 2] = True
    shadow = np.roll(np.roll(mark, 1, 0), 1, 1) & ~mark & fill
    out[shadow] = [*tones["ink_shadow"], 255]
    out[mark] = [*tones["ink"], 255]
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Genera los globos de estado (status_*) con Moana.")
    parser.add_argument("--out", type=Path, default=HERE, help="carpeta de salida (por defecto, la del build.py)")
    parser.add_argument("--preview", action="store_true", help="escribe también status_preview.png")
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    sprites: dict[str, object] = {}
    shown = []
    for icon, (base, glyph) in ICONS.items():
        name = "status_" + icon
        image = bubble(base, glyph)
        alpha = image[..., 3] > 0
        if alpha[0].any() or alpha[-1].any() or alpha[:, 0].any() or alpha[:, -1].any():
            problems.append(f"{name}: toca el borde del lienzo")
        doc = document(name, image)
        (out / f"{name}.moana.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
        drawn = moana_render(doc)
        if not np.array_equal(drawn, image):
            problems.append(f"{name}: Moana no da los mismos pixeles que el dibujo")
        Image.fromarray(drawn, "RGBA").save(out / f"{name}.png")
        sprites[f"{name}.png"] = {"kind": "icon", "canvas": list(SIZE), "anchor": [CENTER[0], CENTER[1]]}
        shown.append(drawn)
    manifest = {"_comentario": "Apoyo (px del sprite) de cada PNG de esta carpeta; lo escribe build.py y export_game.py "
                               "lo pasa al juego.", "sprites": sprites}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.preview:
        w, h = SIZE
        sheet = Image.new("RGBA", (w * 6 * len(shown), h * 6), (200, 196, 186, 255))
        for k, img in enumerate(shown):
            cell = Image.new("RGBA", SIZE, (200, 196, 186, 255))
            cell.alpha_composite(Image.fromarray(img, "RGBA"))
            sheet.paste(cell.resize((w * 6, h * 6), Image.NEAREST), (k * w * 6, 0))
        sheet.save(out / "status_preview.png")
    for line in problems:
        print("FALLO:", line)
    print("RESULTADO:", "OK" if not problems else f"{len(problems)} fallos")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
