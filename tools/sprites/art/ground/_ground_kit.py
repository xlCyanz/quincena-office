"""Casillas de suelo de Quincena Office (pasto, camino, acera, calle) como documentos Moana.

Una casilla es el rombo de 128 x 64 px abajo de un lienzo de 128 x 128 (apoyo (64, 96), como un piso).
Se dibuja sobre su rejilla isométrica: 64 x 64 celdas de eje (``a`` a lo largo de x, ``b`` a lo largo de y);
cada celda son 2 px de pantalla, así toda línea sobre un eje sale en escalera 2:1. La rejilla es periódica
(la celda 64 es la 0 de la vecina), por eso lo que se pinta en ella empalma solo con la casilla de al lado.

Reglas de docs/sprites_128.md, sección 5, que el kit cumple y comprueba:

* las 4 variantes de un material (y las familias de pasto entre sí) tienen **el mismo anillo del borde**
  (``RING`` celdas): el ruido del anillo es común y el de cada variante entra de a poco (``BLEND``);
* las figuras de pantalla (matas, piedras) que caen sobre el anillo son comunes y se dibujan también en
  las copias de la casilla vecina, así cruzan el borde sin cortarse; las de cada variante quedan adentro;
* cada variante tiene **la misma cantidad de celdas por tono** (se reparten por rango, no por umbral),
  así de lejos no se ve un tablero de ajedrez.

El PNG lo dibuja Moana: cada documento tiene una capa por color con un ``rect`` por tramo de pixeles.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

import numpy as np
from PIL import Image

from moana import api

N = 64  # celdas de eje por casilla y lado
SIZE = 128
ORIGIN = (64, 64)  # esquina de arriba del rombo
ANCHOR = [64, 96]
RING = 4  # celdas del borde iguales en todas las variantes
BLEND = 6  # celdas en que el dibujo de la variante entra sobre el del anillo
# Desplazamientos de pantalla de las 8 casillas vecinas (más la propia): +x baja a la derecha, +y a la izquierda.
NEIGHBORS = [(64 * i - 64 * j, 32 * i + 32 * j) for i in (-1, 0, 1) for j in (-1, 0, 1)]


def _pixel_grid() -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    ys, xs = np.mgrid[0:SIZE, 0:SIZE]
    rx = xs + 0.5 - ORIGIN[0]
    ry = ys + 0.5 - ORIGIN[1]
    u = (ry / 32.0 + rx / 64.0) / 2.0
    v = (ry / 32.0 - rx / 64.0) / 2.0
    mask = (u >= 0) & (u < 1) & (v >= 0) & (v < 1)
    return mask, np.floor(u * N).astype(int), np.floor(v * N).astype(int)


MASK, PA, PB = _pixel_grid()  # rombo y celda de eje de cada pixel
A, B = np.mgrid[0:N, 0:N]  # celdas de eje
EDGE = np.minimum(np.minimum(A, B), np.minimum(N - 1 - A, N - 1 - B))  # celdas hasta el borde
IN_RING = EDGE < RING
WEIGHT = np.clip((EDGE - RING + 1) / float(BLEND), 0.0, 1.0)  # 0 en el anillo, 1 adentro


# ---------------------------------------------------------------------------- ruido periódico

def noise(seed: int, period: int) -> np.ndarray:
    """Ruido de valor periódico sobre la rejilla: ``period`` nudos por lado (divide a 64), suavizado."""
    rng = np.random.default_rng(seed)
    nodes = rng.random((period, period))
    step = N / float(period)
    a = (A + 0.5) / step
    b = (B + 0.5) / step
    a0 = np.floor(a).astype(int)
    b0 = np.floor(b).astype(int)
    fa, fb = a - a0, b - b0
    fa, fb = fa * fa * (3 - 2 * fa), fb * fb * (3 - 2 * fb)
    n00 = nodes[a0 % period, b0 % period]
    n10 = nodes[(a0 + 1) % period, b0 % period]
    n01 = nodes[a0 % period, (b0 + 1) % period]
    n11 = nodes[(a0 + 1) % period, (b0 + 1) % period]
    return (n00 * (1 - fa) + n10 * fa) * (1 - fb) + (n01 * (1 - fa) + n11 * fa) * fb


def fbm(seed: int, octaves: tuple[tuple[int, float], ...]) -> np.ndarray:
    """Suma de ruidos (periodo, peso)."""
    total = sum(w for _, w in octaves)
    return sum(noise(seed + 17 * k, p) * w for k, (p, w) in enumerate(octaves)) / total


def waves(seed: int, low: int, high: int, count: int = 14) -> np.ndarray:
    """Campo suave y orgánico: suma de ondas periódicas (frecuencias enteras, así empalma) en direcciones al
    azar, de ``low`` a ``high`` ciclos por casilla. No deja los rombos del ruido interpolado. De 0 a 1."""
    rng = np.random.default_rng(seed)
    total = np.zeros((N, N))
    for _ in range(count):
        while True:
            m, n = (int(v) for v in rng.integers(-high, high + 1, size=2))
            if low <= max(abs(m), abs(n)) <= high:
                break
        phase = rng.random() * 2 * np.pi
        total += np.cos(2 * np.pi * (m * A + n * B) / N + phase) / np.hypot(m, n)
    return (total - total.min()) / (total.max() - total.min())


def hash_cells(seed: int) -> np.ndarray:
    """Un número al azar fijo por celda (grano suelto)."""
    return np.random.default_rng(seed).random((N, N))


def blended(shared: np.ndarray, own: np.ndarray) -> np.ndarray:
    """El campo común en el anillo y el de la variante adentro, con una franja de transición."""
    return shared * (1 - WEIGHT) + own * WEIGHT


def levels(field_: np.ndarray, shared: np.ndarray, shares: tuple[float, ...],
           ring_shares: Optional[tuple[float, ...]] = None) -> np.ndarray:
    """Reparte el campo en ``len(shares)`` tonos (0 = el valor más bajo). Los cortes del anillo salen del
    campo común con ``ring_shares`` (iguales para todas las variantes); los de adentro, del campo de la
    variante con ``shares``; en la franja de transición los cortes pasan de unos a otros de a poco, así no
    queda un escalón que dibuje la rejilla de casillas."""
    ring_shares = ring_shares or shares
    ring_cuts = np.quantile(shared, np.cumsum(ring_shares)[:-1])
    inner_cuts = np.quantile(field_[~IN_RING], np.cumsum(shares)[:-1])
    out = np.zeros((N, N), dtype=int)
    for ring_cut, inner_cut in zip(ring_cuts, inner_cuts):
        cut = ring_cut * (1 - WEIGHT) + inner_cut * WEIGHT
        out += (field_ >= cut).astype(int)
    return out


def dither(cells: np.ndarray, pairs: tuple[tuple[int, int], ...]) -> np.ndarray:
    """Trama de 1 px en el borde de las manchas: en cada par (oscuro, claro), las celdas claras que tocan
    una oscura se oscurecen en damero (``A % 2``, que alterna entre dominós vecinos en pantalla). El anillo
    sigue igual en todas las variantes: no se toca la última fila del anillo, que mira al interior."""
    out = cells.copy()
    stable = (EDGE < RING - 1) | (EDGE >= RING)
    checker = (A % 2) == 0
    for low, high in pairs:
        near = np.zeros_like(cells, dtype=bool)
        for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            near |= np.roll(cells, (da, db), axis=(0, 1)) == low
        out[(cells == high) & near & checker & stable] = low
    return out


def specks(cells: np.ndarray, shared: np.ndarray, own: np.ndarray, share: float,
           step: int, allowed: tuple[int, ...]) -> np.ndarray:
    """Grano suelto: una parte ``share`` de las celdas baja (step -1) o sube (+1) un tono, si su tono está
    en ``allowed``. El anillo usa el azar común; adentro, el de la variante."""
    picked = levels(blended(shared, own), shared, (share, 1 - share)) == 0
    out = cells.copy()
    hit = picked & np.isin(cells, allowed)
    out[hit] = cells[hit] + step
    return out


# ---------------------------------------------------------------------------- figuras de pantalla

@dataclass
class Shape:
    """Figura de pixeles de pantalla; cada letra es un tono de la paleta (``colors``), '.' es vacío."""

    rows: tuple[str, ...]
    colors: dict[str, int]

    def pixels(self) -> list[tuple[int, int, int]]:
        return [(x, y, self.colors[ch]) for y, row in enumerate(self.rows) for x, ch in enumerate(row) if ch != "."]

    @property
    def size(self) -> tuple[int, int]:
        return max(len(r) for r in self.rows), len(self.rows)


class Tile:
    """Índices de paleta de una casilla (-1 fuera del rombo) más lo ocupado por figuras."""

    def __init__(self, cells: np.ndarray) -> None:
        self.index = np.where(MASK, cells[PA.clip(0, N - 1), PB.clip(0, N - 1)], -1)
        self.used = np.zeros((SIZE, SIZE), dtype=bool)

    def put(self, shape: Shape, x: int, y: int, wrap: bool) -> None:
        for dx, dy in NEIGHBORS if wrap else [(0, 0)]:
            for px, py, color in shape.pixels():
                sx, sy = x + px + dx, y + py + dy
                if 0 <= sx < SIZE and 0 <= sy < SIZE and MASK[sy, sx]:
                    self.index[sy, sx] = color
                    self.used[sy, sx] = True


def _fits(used: np.ndarray, shape: Shape, x: int, y: int, inner: bool, gap: int) -> bool:
    """La figura entra: (inner) toda dentro del rombo y fuera del anillo, sin tocar otra a ``gap`` px."""
    for px, py, _ in shape.pixels():
        sx, sy = x + px, y + py
        if inner:
            if not (0 <= sx < SIZE and 0 <= sy < SIZE and MASK[sy, sx]):
                return False
            if EDGE[PA[sy, sx], PB[sy, sx]] < RING + 1:
                return False
        for ox, oy in NEIGHBORS if not inner else [(0, 0)]:
            for gx in range(-gap, gap + 1):
                for gy in range(-gap, gap + 1):
                    qx, qy = sx + ox + gx, sy + oy + gy
                    if 0 <= qx < SIZE and 0 <= qy < SIZE and used[qy, qx]:
                        return False
    return True


def _mark(used: np.ndarray, shape: Shape, x: int, y: int, wrap: bool) -> None:
    for ox, oy in NEIGHBORS if wrap else [(0, 0)]:
        for px, py, _ in shape.pixels():
            qx, qy = x + px + ox, y + py + oy
            if 0 <= qx < SIZE and 0 <= qy < SIZE:
                used[qy, qx] = True


def scatter(shapes: list[Shape], seed: int, inner: bool, used: Optional[np.ndarray] = None,
            gap: int = 1) -> list[tuple[Shape, int, int]]:
    """Coloca cada figura de la lista en un lugar al azar fijo. ``inner``: dentro de la variante (lejos
    del borde); si no, sobre el anillo (común a todas las variantes, se repite en las vecinas)."""
    rng = np.random.default_rng(seed)
    used = np.zeros((SIZE, SIZE), dtype=bool) if used is None else used
    ys, xs = np.nonzero(MASK & (IN_RING[PA.clip(0, N - 1), PB.clip(0, N - 1)] != inner))
    placed = []
    for shape in shapes:
        w, h = shape.size
        for _ in range(4000):
            k = int(rng.integers(len(xs)))
            x, y = int(xs[k]) - w // 2, int(ys[k]) - h + 1
            if _fits(used, shape, x, y, inner, gap):
                _mark(used, shape, x, y, not inner)
                placed.append((shape, x, y))
                break
        else:
            raise ValueError(f"no entra la figura {shape.rows[0]!r} (semilla {seed})")
    return placed


# ---------------------------------------------------------------------------- materiales

@dataclass
class Material:
    """Un suelo: paleta, sus 4 variantes y el anillo común. ``draw(variant)`` devuelve la Tile."""

    name: str
    palette: list[str]
    draw: Callable[[int], Tile]
    variants: int = 4


@dataclass
class Group:
    """Materiales que se construyen y comprueban juntos (``ring_groups``: los que comparten anillo)."""

    materials: list[Material]
    ring_groups: list[list[str]] = field(default_factory=list)


def _runs(index: np.ndarray, color: int) -> list[tuple[int, int, int]]:
    out = []
    for y in range(SIZE):
        row = index[y] == color
        x = 0
        while x < SIZE:
            if row[x]:
                start = x
                while x < SIZE and row[x]:
                    x += 1
                out.append((y, start, x))
            else:
                x += 1
    return out


def document(name: str, palette: list[str], index: np.ndarray) -> dict[str, object]:
    """Documento Moana: una capa por tono con un rect por tramo de pixeles."""
    layers = []
    for color in range(len(palette)):
        ops = [{"id": f"c{color}_{y}_{x0}", "type": "rect", "box": [x0, y, x1, y + 1], "color": f"c{color}"}
               for y, x0, x1 in _runs(index, color)]
        if ops:
            layers.append({"id": f"tone{color}", "name": f"Tono {color} ({palette[color]})", "operations": ops})
    return {
        "schema_version": "1.0",
        "id": name,
        "revision": 0,
        "seed": 0,
        "canvas": {"width": SIZE, "height": SIZE, "profile": "strict"},
        "palette": {"id": f"palette_{name}", "colors": [{"id": f"c{k}", "rgba": f"#{c.upper()}FF"}
                                                       for k, c in enumerate(palette)], "ramps": []},
        "masks": [],
        "layers": layers,
    }


def _expected(palette: list[str], index: np.ndarray) -> Image.Image:
    table = np.array([[int(c[i:i + 2], 16) for i in (0, 2, 4)] for c in palette], dtype=np.uint8)
    rgba = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    inside = index >= 0
    rgba[inside, :3] = table[index[inside]]
    rgba[inside, 3] = 255
    return Image.fromarray(rgba, "RGBA")


def _lum(image: Image.Image) -> float:
    arr = np.asarray(image).astype(float)
    inside = arr[..., 3] > 0
    return float((arr[inside, :3] @ np.array([0.299, 0.587, 0.114])).mean())


def mosaic(tiles: list[Image.Image], cols: int, rows: int, seed: int, scale: int = 3) -> Image.Image:
    """Casillas al azar fijo en un rombo de cols x rows, para revisar costuras y repetición."""
    rng = np.random.default_rng(seed)
    w = (cols + rows) * 64
    h = (cols + rows) * 32 + 64
    out = Image.new("RGBA", (w, h), (40, 40, 40, 255))
    for j in range(rows):
        for i in range(cols):
            tile = tiles[int(rng.integers(len(tiles)))]
            x = rows * 64 - 64 + 64 * i - 64 * j
            y = 32 * i + 32 * j
            out.alpha_composite(tile, (x, y))
    return out.resize((w * scale // 2, h * scale // 2), Image.NEAREST)


def main(group: Group, here: Path) -> int:
    parser = argparse.ArgumentParser(description="Genera las casillas de suelo con Moana.")
    parser.add_argument("--out", type=Path, default=here, help="carpeta de salida (por defecto, la del build.py)")
    parser.add_argument("--preview", type=Path, help="carpeta donde dejar mosaicos de revisión")
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    images: dict[str, list[Image.Image]] = {}
    anchors: dict[str, dict[str, list[int]]] = {}
    for material in group.materials:
        images[material.name] = []
        lums = []
        for variant in range(material.variants):
            tile = material.draw(variant)
            name = f"{material.name}_{variant}"
            doc = document(name, material.palette, tile.index)
            (out / f"{name}.moana.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
            result = api.render(api.load_document(doc))
            image = Image.frombytes("RGBA", (SIZE, SIZE), bytes(result.rgba))
            if image.tobytes() != _expected(material.palette, tile.index).tobytes():
                problems.append(f"{name}: Moana no da los mismos pixeles que el dibujo")
            colors = {px for px in image.getdata() if px[3] == 255}
            if len(colors) > 16:
                problems.append(f"{name}: {len(colors)} colores (máx. 16)")
            image.save(out / f"{name}.png")
            images[material.name].append(image)
            anchors[f"{name}.png"] = {"anchor": ANCHOR}
            lums.append(_lum(image))
        spread = (max(lums) - min(lums)) / max(lums)
        print(f"{material.name}: brillo medio {min(lums):.1f}–{max(lums):.1f} ({spread:.1%})")
        if spread > 0.02:
            problems.append(f"{material.name}: las variantes no tienen el mismo brillo ({spread:.1%})")
    # Anillo común: las celdas del borde son iguales en todas las variantes (y familias que lo comparten).
    ring_px = MASK & IN_RING[PA.clip(0, N - 1), PB.clip(0, N - 1)]
    for names in [[m.name] for m in group.materials] + group.ring_groups:
        arrays = [np.asarray(img)[ring_px] for n in names for img in images[n]]
        if not all(np.array_equal(arrays[0], other) for other in arrays[1:]):
            problems.append(f"{'/'.join(names)}: el anillo del borde no es igual en todas")
    manifest = {"_comentario": "Apoyo (px del sprite) de cada casilla de suelo de esta carpeta; lo escribe build.py "
                               "y export_game.py arma con ellas el atlas assets/tiles/ground.png.",
                "sprites": anchors}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
        for name, tiles in images.items():
            mosaic(tiles, 6, 6, seed=3).save(args.preview / f"{name}_mosaic.png")
    for line in problems:
        print("FALLO:", line)
    print("RESULTADO:", "OK" if not problems else f"{len(problems)} fallos")
    return 1 if problems else 0
