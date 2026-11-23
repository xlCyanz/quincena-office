"""Objetos de pared de Quincena Office con Moana (cuadros, reloj, pizarra, televisor, aire acondicionado),
sobre el modelo de sólidos de ``../furniture/_chair_kit.py``.

El objeto se modela una sola vez colgado de una pared en y = 0 con el frente hacia +y; x corre a lo largo
del borde (0 a 32 unidades por borde) y z es la altura en px. El lado de la pared ``_y`` es la rotación 0
y el de la pared ``_x`` la rotación 3, así los dibujos nunca salen espejados. Lienzo 64×128 con apoyo
(32, 112) en el medio del borde, o 128×192 con apoyo (64, 160) si ocupa dos bordes, como un tramo de pared.
En las texturas, la cara de adelante es ``Faces.back`` de ``../furniture/_boxes.py`` (``a`` de izquierda a
derecha, ``b`` hacia arriba, en px). Sin sombra: el objeto no toca el piso.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "furniture"))  # _chair_kit, _boxes

from _chair_kit import CELL, Mat, Solid, document, finish, moana_render, render, to_rgba  # noqa: E402
from _desk_kit import View  # noqa: E402
from _painter import document as painter_document  # noqa: E402

FACE = 2.0  # cara de la pared: 4 px de la línea del borde
BASE = 48.0  # z de la base de un objeto de pared (24 px del mundo)
AXES = {"y": 0, "x": 3}
_axis = {"now": "y"}


def current_axis() -> str:
    """Pared que se está dibujando ("x" o "y"): el fondo corre el objeto a la izquierda en _y y a la derecha
    en _x, así que lo que no entra centrado se corre a lo largo según la pared."""
    return _axis["now"]


@dataclass
class WallView(View):
    """Vista de un objeto de pared: el origen queda en la punta del borde, no al pie del lienzo."""

    edges: int = 1

    @property
    def origin(self) -> tuple[float, float]:
        top = self.canvas[1] - 32 * self.edges
        return (0.0 if self.r == 0 else 64.0 * self.edges, float(top))

    @property
    def anchor(self) -> list[float]:
        return [32.0 * self.edges, float(self.canvas[1] - 16 * self.edges)]


@dataclass
class WallSpec:
    name: str
    mats: dict[str, Mat]
    model: Callable[[], list[Solid]]
    max_colors: int = 32
    edges: int = 1  # bordes que ocupa a lo largo (el televisor, 2)
    base_z: float = BASE  # z de su base, que el juego usa para ordenarlo con lo que tiene delante
    suffix: str = ""  # tras el eje: "_play_3" en un cuadro de animación
    extra: Optional[Callable[[str], dict]] = None  # campos más del manifest según el eje (cuadro, base…)
    painter: bool = False

    @property
    def canvas(self) -> tuple[int, int]:
        return (64, 128) if self.edges == 1 else (128, 192)

    def view(self, axis: str) -> WallView:
        return WallView(AXES[axis], CELL * self.edges, CELL, self.canvas, self.edges)

    def palette(self) -> list[tuple[str, str]]:
        seen: dict[str, str] = {}
        for m in self.mats.values():
            for k, hexa in m.tones().items():
                seen.setdefault(f"{m.name}.{k}", hexa)
        return list(seen.items())


def main_wall(specs: list[WallSpec], here: Path) -> int:
    """Genera ``<nombre>_x`` y ``<nombre>_y`` de cada pieza con su documento Moana y un manifest.json."""
    parser = argparse.ArgumentParser(description="Genera " + ", ".join(s.name for s in specs) + " (_x, _y) con Moana.")
    parser.add_argument("--out", type=Path, default=here, help="carpeta de salida (por defecto, la del build.py)")
    parser.add_argument("--preview", action="store_true", help="escribe también <nombre>_preview.png")
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    sprites: dict[str, object] = {}
    for spec in specs:
        _one(spec, out, args.preview, problems, sprites)
    manifest = {"_comentario": "Apoyo (px del sprite) de cada PNG de esta carpeta; lo escribe build.py y export_game.py "
                               "lo pasa al juego.", "sprites": sprites}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    for line in problems:
        print("FALLO:", line)
    print("RESULTADO:", "OK" if not problems else f"{len(problems)} fallos")
    return 1 if problems else 0


def _one(spec: WallSpec, out: Path, preview: bool, problems: list[str], sprites: dict[str, object]) -> None:
    shown = []
    for axis in ("x", "y"):
        v = spec.view(axis)
        name = f"{spec.name}_{axis}{spec.suffix}"
        _axis["now"] = axis
        image = to_rgba(finish(render(spec.model(), v, spec.canvas), spec.mats), spec)  # type: ignore[arg-type]
        colors = {tuple(c) for c in image[image[..., 3] == 255][:, :3]}
        if len(colors) > spec.max_colors:
            problems.append(f"{name}: {len(colors)} colores (máx. {spec.max_colors})")
        alpha = image[..., 3] > 0
        if alpha[0].any() or alpha[-1].any() or alpha[:, 0].any() or alpha[:, -1].any():
            problems.append(f"{name}: toca el borde del lienzo")
        doc = painter_document(name, image) if spec.painter else document(name, image)
        (out / f"{name}.moana.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
        drawn = moana_render(doc)
        if not np.array_equal(drawn, image):
            problems.append(f"{name}: Moana no da los mismos pixeles que el dibujo")
        Image.fromarray(drawn, "RGBA").save(out / f"{name}.png")
        sprites[f"{name}.png"] = {"anchor": v.anchor, "base_z": int(spec.base_z),
                                  **(spec.extra(axis) if spec.extra else {})}
        shown.append(drawn)
    if preview:
        w, h = spec.canvas
        sheet = Image.new("RGBA", (w * len(shown) * 4, h * 4), (70, 72, 80, 255))
        for k, img in enumerate(shown):
            cell = Image.new("RGBA", spec.canvas, (70, 72, 80, 255))
            cell.alpha_composite(Image.fromarray(img, "RGBA"))
            sheet.paste(cell.resize((w * 4, h * 4), Image.NEAREST), (k * w * 4, 0))
        sheet.save(out / f"{spec.name}{spec.suffix}_preview.png")
