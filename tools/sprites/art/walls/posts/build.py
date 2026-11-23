"""Postes de esquina de las paredes con Moana. Ver ../_walls_kit.py.

Un poste de 8×8 px de planta en un vértice, del alto del vecino más alto, para toda unión que lo lleva:
``wall_post_<−x><−y><+x><+y>`` con n (nada), l (bajo), t (alto), d (puerta baja) o h (puerta alta), en el color de
siempre (el juego arma el nombre igual, ``EdgePieceView.get_corner_sprite``); y las ocho esquinas con nombre
(``wall_tall_corner``, ``wall_<color>_low_corner_left``…) en los cinco colores. Se dibuja con los tramos vecinos
completos y se guarda solo su silueta: 16 px de ancho (24 en la jamba entre dos puertas) con el vértice en
(ancho / 2, alto − 4). Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/walls/posts/build.py [--out DIR] [--only TEXTO]
"""

import importlib.util
import sys
from pathlib import Path
from typing import Iterator

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import _walls_kit as k  # noqa: E402

_spec = importlib.util.spec_from_file_location("door_build", HERE.parent / "door" / "build.py")
door = importlib.util.module_from_spec(_spec)  # type: ignore[arg-type]
_spec.loader.exec_module(door)  # type: ignore[union-attr]

HEIGHTS = {"t": k.WALL_TOP, "l": k.LOW, "n": 0, "h": k.WALL_TOP, "d": k.LOW}
DOOR_CODES = ("d", "h")
CORNERS = {
    "wall_tall_corner": ("n", "n", "t", "t"),
    "wall_tall_corner_left": ("n", "t", "l", "n"),
    "wall_tall_corner_right": ("t", "n", "n", "l"),
    "wall_tall_corner_front": ("t", "t", "n", "n"),
    "wall_low_corner": ("l", "l", "n", "n"),
    "wall_low_corner_back": ("n", "n", "l", "l"),
    "wall_low_corner_left": ("n", "l", "l", "n"),
    "wall_low_corner_right": ("l", "n", "n", "l"),
}
POST_W = 16
MULLION_GROW = 1.0  # unidades más de silueta hacia las jambas entre dos puertas (2 px)
MULLION_EXTRA = 8
MULLIONS = (("d", "n", "d", "n"), ("n", "d", "n", "d"), ("h", "n", "h", "n"), ("n", "h", "n", "h"))
# Vecinos (−x, −y, +x, +y): borde y corrimiento (unidades) del tramo.
ARMS = (("y", -k.EDGE, 0.0), ("x", 0.0, -k.EDGE), ("y", 0.0, 0.0), ("x", 0.0, 0.0))


def corner_light(a: np.ndarray, c: np.ndarray, z: np.ndarray, tone: np.ndarray) -> np.ndarray:
    """Filo claro de 1 px en la arista de adelante del poste (da a la luz)."""
    out = tone.copy()
    out[(c > k.HALF - 0.1) & (a > k.HALF - 0.5) & (tone != "wall.top")] = "wall.light"
    return k.baseboard(out, z)


def post_combos() -> list[tuple[str, ...]]:
    """Uniones que llevan poste: dos tramos o más, salvo dos del mismo alto en línea, más las jambas entre dos
    puertas en línea. Cada una es (−x, −y, +x, +y)."""
    combos = []
    for a in "nlt":
        for b in "nlt":
            for c in "nltdh":
                for d in "nltdh":
                    nb = (a, b, c, d)
                    present = [n for n in nb if n != "n"]
                    straight = (a != "n" and c != "n" and HEIGHTS[a] == HEIGHTS[c] and b == d == "n") or \
                               (b != "n" and d != "n" and HEIGHTS[b] == HEIGHTS[d] and a == c == "n")
                    if len(present) >= 2 and not straight:
                        combos.append(nb)
    return combos + list(MULLIONS)


def post_name(nb: tuple[str, ...]) -> str:
    return "wall_post_" + "".join(nb)


def post_image(nb: tuple[str, ...], color: str) -> tuple[np.ndarray, list[float], int]:
    height = max(HEIGHTS[c] for c in nb)
    big_w, big_h = 192, height + 112
    v = k.PieceView(0, 32, 32, (big_w, big_h), (96.0, big_h - 56.0))
    solids = []
    p = k.Along("y", part="post")
    p.box("post", "wall", -k.HALF, k.HALF, -k.HALF, k.HALF, 0, height - k.CAP_H, tex=corner_light)
    p.box("post", "cap", -k.HALF, k.HALF, -k.HALF, k.HALF, height - k.CAP_H, height, lit=True)
    solids += p.solids
    for code, (edge, ox, oy) in zip(nb, ARMS):
        if code == "n":
            continue
        back = ox < 0 or oy < 0
        f = k.Along(edge, ox, oy, part="post", group="nb")
        if code in DOOR_CODES:
            # Una puerta más baja que el poste va sin su pedazo de pared del lado del poste.
            skip = ("end" if back else "start") if HEIGHTS[code] < height else None
            door.model(f, "door", code == "h", skip=skip, leaf=False)
        else:
            # Un tramo más bajo que el poste arranca en su borde; si no, su cara tapa medio poste.
            start, end = 0.0, k.EDGE
            if HEIGHTS[code] < height:
                start, end = (0.0, k.EDGE - k.HALF) if back else (k.HALF, k.EDGE)
            k.wall_block(f, start, end, 0, HEIGHTS[code])
        solids += f.solids
    floor = k.Along("y", part="~floor", group="~")
    floor.box("~floor", "~", -k.HALF - 1.5, k.HALF + 1.5, -k.HALF - 1.5, k.HALF + 1.5, -8, 0)  # sin raya al pie
    solids += floor.solids
    mats = [k.wall_mat(color), k.CAP, door.LEAF, door.LEAF_X, door.FRAME, k.METAL]
    image, _depth = k.draw(solids, v, mats)
    # El contorno va dentro de la silueta del poste: cada pixel del poste junto al contorno de afuera lo toma.
    body = k.silhouette([s for s in solids if not s.part.startswith("~")], v)
    ring = (image[..., 3] == 255) & ~body
    grow = MULLION_GROW if nb in MULLIONS else 0.0
    gx = grow if nb[0] != "n" else 0.0
    gy = grow if nb[1] != "n" else 0.0
    alone = k.Along("y")
    alone.box("post", "wall", -k.HALF - gx, k.HALF + gx, -k.HALF - gy, k.HALF + gy, 0, height)
    inside = k.silhouette(alone.solids, v)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        take = inside & np.roll(np.roll(ring, -dy, 0), -dx, 1)
        image[take] = np.roll(np.roll(image, -dy, 0), -dx, 1)[take]
    image[~inside] = 0
    width = POST_W + (MULLION_EXTRA if grow else 0)
    x0 = int(v.org[0]) - width // 2
    y0 = int(v.org[1]) - height - 4
    out_h = height + 8
    crop = np.ascontiguousarray(image[y0:y0 + out_h, x0:x0 + width])
    return crop, [width / 2.0, out_h - 4.0], height


def entry(nb: tuple[str, ...], anchor: list[float], height: int, color: str) -> dict:
    return {"anchor": anchor, "kind": "post", "wall_color": color, "anchor_at": "vértice de la cuadrícula, en el piso",
            "neighbors": list(nb), "neighbor_order": "-x -y +x +y",
            "height": k.DATA["wall"]["height"] if height > k.LOW else k.DATA["low_wall_height"],
            "sort_after": "tramos del vértice: Y del vértice + %g" % k.POST_SORT_BIAS}


def sprites() -> Iterator[k.Sprite]:
    for color, *_ in k.WALL_COLORS:
        for corner, nb in sorted(CORNERS.items()):
            image, anchor, height = post_image(nb, color)
            yield k.Sprite(k.colored(corner, color), image, entry(nb, anchor, height, color))
    for nb in post_combos():
        image, anchor, height = post_image(nb, k.DEFAULT_COLOR)
        yield k.Sprite(post_name(nb), image, entry(nb, anchor, height, k.DEFAULT_COLOR))


if __name__ == "__main__":
    raise SystemExit(k.main("los postes de esquina", sprites, HERE))
