"""Iconos de la barra de la partida de Quincena Office con Moana (ui_<icono>): 24×24 a resolución nativa.

Godot los multiplica por el color del texto del botón (claro normal, oscuro al estar pulsado), por eso van en grises:
blanco, claro y oscuro para dar volumen. Cada icono se arma con rectángulos, discos y dibujos de texto. Apoyo en el
centro (12, 12). Desde el repositorio de Moana:

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

SIZE = (24, 24)
# Tonos (Godot multiplica el icono por el color del texto del botón): blanco, claro y oscuro.
W = (255, 255, 255, 255)
L = (206, 206, 206, 255)
D = (138, 138, 138, 255)
CLEAR = (0, 0, 0, 0)


class Canvas:
    """Lienzo de 24×24 a resolución nativa con rectángulos, discos y pixeles sueltos."""

    def __init__(self) -> None:
        self.px = np.zeros((SIZE[1], SIZE[0], 4), dtype=np.uint8)

    def rect(self, x: int, y: int, w: int, h: int, tone=W) -> "Canvas":
        self.px[y:y + h, x:x + w] = tone
        return self

    def dot(self, x: int, y: int, tone=W) -> "Canvas":
        self.px[y, x] = tone
        return self

    def disc(self, cx: float, cy: float, r: float, tone=W) -> "Canvas":
        ys, xs = np.mgrid[0:SIZE[1], 0:SIZE[0]]
        self.px[np.hypot(xs + 0.5 - cx, ys + 0.5 - cy) <= r] = tone
        return self

    def ring(self, cx: float, cy: float, r: float, width: float, tone=W) -> "Canvas":
        ys, xs = np.mgrid[0:SIZE[1], 0:SIZE[0]]
        dist = np.hypot(xs + 0.5 - cx, ys + 0.5 - cy)
        self.px[(dist <= r) & (dist > r - width)] = tone
        return self

    def rows(self, x: int, y: int, art: list[str]) -> "Canvas":
        """Pinta un dibujo de texto: # blanco, + claro, - oscuro, . nada (deja lo de abajo), x borra."""
        tones = {"#": W, "+": L, "-": D, "x": CLEAR}
        for r, line in enumerate(art):
            for c, ch in enumerate(line):
                if ch in tones:
                    self.px[y + r, x + c] = tones[ch]
        return self


def build_icon() -> np.ndarray:
    # Martillo: cabeza con cara a la derecha y uña a la izquierda, mango con empuñadura.
    c = Canvas()
    c.rows(2, 2, [
        "...##########+..",
        "..###########++#",
        ".############++#",
        "#############++#",
        "##-----------++#",
        "#.......--...--.",
    ])
    c.rect(9, 8, 3, 9, W).rect(11, 8, 1, 9, D).rect(9, 8, 3, 1, D)
    c.rect(8, 16, 5, 6, L).rect(12, 16, 1, 6, D).rect(8, 21, 5, 1, D)
    c.rect(9, 17, 1, 4, W)
    return c.px


def frame_icon() -> np.ndarray:
    # Encuadre: cuatro esquinas y una casilla isométrica con su borde en el medio.
    c = Canvas()
    for x, y, dx, dy in ((1, 1, 1, 1), (22, 1, -1, 1), (1, 22, 1, -1), (22, 22, -1, -1)):
        for i in range(7):
            c.dot(x + dx * i, y, W).dot(x, y + dy * i, W)
            c.dot(x + dx * i, y + dy, L if i > 0 else W).dot(x + dx, y + dy * i, L if i > 0 else W)
    c.rows(5, 8, [
        ".......##.......",
        ".....##++##.....",
        "...##++++++##...",
        ".##++++++++++##.",
        ".--##++++++##--.",
        "...--##++##--...",
        ".....--##--.....",
        ".......--.......",
    ])
    return c.px


def walls_icon() -> np.ndarray:
    # Pared de ladrillos con una flecha arriba y abajo a la derecha.
    c = Canvas()
    c.rect(1, 6, 14, 16, W)
    for y in (9, 13, 17):
        c.rect(1, y, 14, 1, D)
    for y, xs in ((6, (5, 11)), (10, (3, 8, 13)), (14, (5, 11)), (18, (3, 8, 13))):
        for x in xs:
            c.rect(x, y, 1, 3, D)
    c.rect(1, 21, 14, 1, L).rect(14, 6, 1, 16, L)
    c.rows(16, 1, [
        "...#...",
        "..###..",
        ".#####.",
        "#######",
    ])
    c.rect(18, 5, 3, 14, W).rect(20, 5, 1, 14, L)
    c.rows(16, 19, [
        "#######",
        ".#####.",
        "..###..",
        "...#...",
    ])
    return c.px


def staff_icon() -> np.ndarray:
    # Persona: cabeza con pelo, hombros redondeados y corbata.
    c = Canvas()
    c.disc(12, 7.5, 5, W)
    # Pelo: tapa la mitad de arriba de la cabeza y baja por los lados.
    c.rows(7, 2, [
        "..-----...",
        ".-------..",
        "---------.",
        "---------.",
        "--.....--.",
        "-.......-.",
    ])
    c.dot(15, 9, L).dot(15, 10, L).dot(14, 11, L)
    c.rows(3, 14, [
        "....########....",
        "..############..",
        ".######--######.",
        "#######--#######",
        "######----######",
        "######----######",
        "######----######",
        "#######--#######",
    ])
    c.rect(16, 15, 3, 7, L).rect(19, 17, 1, 5, L)
    c.rect(3, 21, 18, 1, D)
    return c.px


def projects_icon() -> np.ndarray:
    # Portapapeles con pinza, renglones y una marca de hecho.
    c = Canvas()
    c.rect(3, 3, 18, 20, L).rect(4, 4, 16, 18, W)
    c.rect(4, 21, 16, 1, D).rect(19, 4, 1, 18, L)
    c.rows(8, 1, [
        "..####..",
        "########",
        "#------#",
        "########",
    ])
    for y in (9, 13, 17):
        c.rect(11, y, 7, 2, D)
    for y in (9, 13):
        c.rows(6, y - 1, ["...-", "-.--", ".--."])
    c.rect(6, 17, 3, 2, D)
    return c.px


def teams_icon() -> np.ndarray:
    # Reloj de pared: aro, marcas de las horas y agujas.
    c = Canvas()
    c.disc(12, 12, 10.5, L).disc(12, 12, 8.5, W)
    c.ring(12, 12, 10.5, 1.2, D)
    for x, y in ((11, 4), (11, 18), (4, 11), (18, 11)):
        c.rect(x, y, 2, 2, D)
    c.rect(11, 6, 2, 7, D).rect(12, 11, 5, 2, D)
    c.rect(11, 11, 2, 2, W).dot(11, 11, D)
    return c.px


def bank_icon() -> np.ndarray:
    # Banco: frontón, friso, tres columnas y escalones.
    c = Canvas()
    c.rows(1, 1, [
        "..........##..........",
        "........######........",
        "......##########......",
        "....##############....",
        "..##################..",
        "######################",
    ])
    c.rect(4, 4, 16, 2, W).rect(10, 3, 4, 2, D)
    c.rect(2, 7, 20, 2, L).rect(2, 8, 20, 1, D)
    for x in (4, 10, 16):
        c.rect(x, 10, 4, 8, W).rect(x + 3, 10, 1, 8, L)
    c.rect(2, 18, 20, 2, L).rect(1, 20, 22, 2, W).rect(1, 21, 22, 1, D)
    return c.px


def company_icon() -> np.ndarray:
    # Edificio de oficinas alto con otro más bajo al lado; ventanas y puerta.
    c = Canvas()
    c.rect(3, 2, 11, 20, W).rect(13, 2, 1, 20, L)
    c.rect(14, 9, 8, 13, L).rect(21, 9, 1, 13, D)
    for y in (4, 8, 12):
        for x in (5, 9):
            c.rect(x, y, 2, 2, D)
    for y in (11, 15):
        for x in (16, 19):
            c.rect(x, y, 2, 2, D)
    c.rect(7, 17, 3, 5, D).rect(3, 21, 19, 1, D)
    return c.px


def ceo_icon() -> np.ndarray:
    # Salir: puerta abierta con marco y una flecha hacia afuera.
    c = Canvas()
    c.rect(2, 2, 12, 20, L).rect(4, 4, 8, 18, CLEAR)
    c.rows(4, 3, [
        "##......",
        "####....",
        "######..",
        "######..",
        "######..",
        "######..",
        "######..",
        "######..",
        "####-#..",
        "######..",
        "######..",
        "######..",
        "######..",
        "######..",
        "######..",
        "####....",
        "##......",
    ])
    c.rect(2, 21, 12, 1, D)
    c.rows(13, 7, [
        "....#....",
        "....##...",
        "#########",
        "##########",
        "#########",
        "....##...",
        "....#....",
    ])
    return c.px


def settings_icon() -> np.ndarray:
    # Engranaje de ocho dientes (cada 45°) con el centro hueco.
    c = Canvas()
    ys, xs = np.mgrid[0:SIZE[1], 0:SIZE[0]]
    dx, dy = xs + 0.5 - 12, ys + 0.5 - 12
    dist = np.hypot(dx, dy)
    angle = np.degrees(np.arctan2(dy, dx)) % 45.0
    tooth = (np.minimum(angle, 45.0 - angle) * np.pi / 180.0 * dist <= 2.1) & (dist <= 11.0)
    body = dist <= 8.0
    c.px[tooth | body] = W
    c.px[(tooth & ~body) & (dx + dy > 2)] = L
    c.ring(12, 12, 8.0, 1.0, L)
    c.disc(12, 12, 4.0, D).disc(12, 12, 2.5, CLEAR)
    return c.px


def shop_icon() -> np.ndarray:
    # Tienda: bolsa de compras con un asa en arco y dos remaches.
    c = Canvas()
    c.rows(7, 1, [
        "..######..",
        ".##....##.",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
    ])
    c.rect(3, 7, 18, 15, W).rect(3, 7, 18, 2, L).rect(18, 9, 3, 13, L).rect(3, 21, 18, 1, D)
    c.rect(7, 9, 2, 2, D).rect(15, 9, 2, 2, D)
    return c.px


# Icono -> función que lo dibuja.
ICONS = {
    "build": build_icon, "frame": frame_icon, "walls": walls_icon, "staff": staff_icon, "projects": projects_icon,
    "teams": teams_icon, "bank": bank_icon, "company": company_icon, "ceo": ceo_icon, "settings": settings_icon,
    "shop": shop_icon,
}


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
    for key, draw in ICONS.items():
        name = "ui_" + key
        image = draw()
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
