"""Paredes de Quincena Office con Moana: tramos, puertas, ventanas, postes de esquina y la sombra de la pared alta,
sobre el modelo de sólidos de ``../furniture/_chair_kit.py``.

Un tramo se modela a lo largo de su borde: ``a`` de 0 a 32 unidades (1/32 de casilla, 2 px de piso), ``c`` a lo
ancho (la pared va de −2 a +2: 8 px) con la cara de adentro en +c, y z en px. ``Along`` lo pasa al mundo: el
``_y`` corre a lo largo de x y el ``_x`` a lo largo de y (como el generador viejo, el _x es el _y espejado: la
bisagra y la manija quedan del mismo lado de la pantalla). Lienzos 72×160 (altos) y 72×64 (bajos) con apoyo en el
medio del borde, en el piso: (36, alto − 18).

Para que el tramo empalme con el anterior y no tenga raya contra el piso, se dibuja con dos «fantasmas» (partes
que empiezan con ``~``): el tramo de atrás (a de −32 a 0) y el piso. Tapan el contorno y la línea entre piezas y
después se borran. Los postes se dibujan con sus vecinos completos y se recortan a la silueta del poste.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Iterator, Optional

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]  # el repositorio del juego
sys.path.insert(0, str(HERE.parent / "furniture"))  # _chair_kit, _boxes
sys.path.insert(0, str(HERE.parent))  # _painter

from _chair_kit import EMPTY, GAP, NEIGHBORS4, Frame, Mat, Solid, _ring_faces, _shift, moana_render, render, slab  # noqa: E402
from _desk_kit import View  # noqa: E402
from _boxes import colors, mix  # noqa: E402
from _painter import document as painter_document  # noqa: E402

DATA = json.loads((ROOT / "data" / "construction.json").read_text(encoding="utf-8"))
SCALE = 2  # px de sprite por px del mundo
WALL_TOP = DATA["wall"]["height"] * SCALE  # 120
DOOR_TOP = DATA["door"]["height"] * SCALE  # 92
GLASS_TOP = DATA["glass_door"]["height"] * SCALE  # 100
LOW = DATA["low_wall_height"] * SCALE  # 20
CAP_H = 2  # alto de la tapa ciruela
HALF = 2.0  # medio grosor de la pared (4 px)
RECESS = 1.0  # medio grosor de lo que va hundido (hoja, vidrio)
EDGE = 32.0  # unidades por borde

CANVAS_W, CANVAS_TALL, CANVAS_LOW = 72, 160, 64
BOTTOM = 34  # px del origen (a = 0, c = 0) a la punta de abajo del lienzo
SEAM_GAP = 0.4 / 32  # menos que GAP de las sillas: la hoja hundida 2 px también marca su ranura
# Líneas oscuras fijas entre piezas de la misma profundidad: el canto del marco contra la pared y el pie de la
# hoja sobre el umbral.
LINES = (("frame", "wall"), ("leaf", "sill"))
SORT_BIAS_X = 0.5  # con la misma Y va primero el _y
POST_SORT_BIAS = 17.0  # el poste va después de los tramos de su vértice

# Colores de la cara (nombre, arriba, cara, brillo), todos con la tapa ciruela; la fría va sin color en el nombre.
WALL_COLORS = (
    ("cool", "#96ACADFF", "#899DA0FF", "#A3B6B7FF"),
    ("beige", "#C2B7A3FF", "#B3A792FF", "#CFC5B3FF"),
    ("white", "#D6D3CBFF", "#C8C4BBFF", "#E2E0D9FF"),
    ("sage", "#9FB397FF", "#91A689FF", "#AFC1A7FF"),
    ("peach", "#D3AD97FF", "#C69F88FF", "#DDBCA8FF"),
)
DEFAULT_COLOR = "cool"


def hexes(*rgb: tuple[int, int, int]) -> list[str]:
    return ["#%02X%02X%02XFF" % c for c in rgb]


def ramp8(name: str, outline: str, deep: str, right: str, left: str, soft: str, base: str, light: str) -> Mat:
    """Material con los pasos de la rampa vieja: contorno, sombra, derecha, izquierda, suave, base, brillo."""
    return Mat(name, light=light, top=base, upper=soft, left=left, right=right, dark=deep, ink=outline)


def wall_mat(color: str) -> Mat:
    for name, top, face, light in WALL_COLORS:
        if name == color:
            return Mat("wall", light=light, top=top, upper=mix(top, face), left=face, right=face, dark="#3E2E33FF",
                       ink="#21161AFF")
    raise KeyError(color)


CAP = ramp8("cap", "#21161AFF", "#2E2125FF", "#3E2E33FF", "#493539FF", "#513D41FF", "#584549FF", "#675A64FF")
METAL = ramp8("metal", "#3D3B44FF", "#575E64FF", "#77888CFF", "#97A2AAFF", "#B4C2C5FF", "#D0E1E0FF", "#FFFFFFFF")
ALU = ramp8("alu", "#1D2227FF", "#3A4149FF", "#4F5862FF", "#5A646DFF", "#616B75FF", "#68727CFF", "#8A949DFF")
GHOST = colors("~", "#FF00FFFF")


def colored(name: str, color: str) -> str:
    """Nombre de una pieza en un color (wall_tall_x -> wall_beige_tall_x; la fría no cambia)."""
    if color == DEFAULT_COLOR:
        return name
    return re.sub(r"_(tall|low)(?=_|$)", r"_%s_\1" % color, name, count=1)


# ---------------------------------------------------------------------------- modelo a lo largo del borde

Tex = Callable[[np.ndarray, np.ndarray, np.ndarray, np.ndarray], np.ndarray]  # (a, c, z, tono) -> tono


@dataclass
class Along:
    """Un borde en el mundo: ``edge`` "y" corre a lo largo de x, "x" a lo largo de y; ``ox``, ``oy`` (unidades)
    corren el borde; ``part`` funde todas sus piezas en una (los vecinos de un poste); ``group`` las marca."""

    edge: str
    ox: float = 0.0
    oy: float = 0.0
    part: Optional[str] = None
    group: str = "self"
    solids: list[Solid] = field(default_factory=list)

    def world(self, a: float, c: float) -> tuple[float, float]:
        return (self.ox + a, self.oy + c) if self.edge == "y" else (self.ox + c, self.oy + a)

    def local(self, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        return (x - self.ox, y - self.oy) if self.edge == "y" else (y - self.oy, x - self.ox)

    def _wrap(self, tex: Optional[Tex]) -> Optional[Callable]:
        if tex is None:
            return None

        def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
            a, c = self.local(mx, my)
            return tex(a, c, mz, tone)

        return texture

    def box(self, part: str, mat: str, a0: float, a1: float, c0: float, c1: float, z0: float, z1: float,
            tex: Optional[Tex] = None, lit: bool = False) -> Solid:
        x0, y0 = self.world(a0, c0)
        x1, y1 = self.world(a1, c1)
        x0, x1 = sorted((x0, x1))
        y0, y1 = sorted((y0, y1))
        solid = slab(self.part or part, self.group, mat, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2,
                     0.01, z0, z1, lit=lit, texture=self._wrap(tex))
        self.solids.append(solid)
        return solid

    def hexa(self, part: str, mat: str, o: tuple[float, float, float], u: tuple[float, float, float],
             v: tuple[float, float, float], w: tuple[float, float, float], tex: Optional[Tex] = None) -> Solid:
        """Caja con cualquier giro: esquina ``o`` y lados u, v, w en (a, c, z)."""

        def p(a: float, c: float, z: float) -> tuple[float, float, float]:
            x, y = self.world(a, c)
            return (x, y, z)

        def add(*vs: tuple[float, float, float]) -> tuple[float, float, float]:
            return tuple(sum(k) for k in zip(*vs))  # type: ignore[return-value]

        corners = {}
        for i in (0, 1):
            for j in (0, 1):
                for k in (0, 1):
                    q = add(o, tuple(i * t for t in u), tuple(j * t for t in v), tuple(k * t for t in w))
                    corners[(i, j, k)] = p(*q)
        quads = [[(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)],
                 [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)], [(0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1)],
                 [(0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)], [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]]
        faces = [[corners[k] for k in q] for q in quads]
        center = tuple(np.mean([corners[k] for k in corners], axis=0))
        solid = Solid(self.part or part, self.group, mat, faces, center, texture=self._wrap(tex))  # type: ignore[arg-type]
        self.solids.append(solid)
        return solid


BASEBOARD = 4  # px del rodapié ciruela al pie de la pared


def baseboard(tone: np.ndarray, z: np.ndarray) -> np.ndarray:
    """Rodapié del color de la tapa, con el tono de la cara (izquierda o derecha) y un filo arriba."""
    out = tone.copy()
    low = z < BASEBOARD - 1
    edge = (z >= BASEBOARD - 1) & (z < BASEBOARD)
    for side in ("left", "right", "upper"):
        on = tone == f"wall.{side}"
        out[on & low] = f"cap.{side}"
        out[on & edge] = "cap.upper" if side != "right" else "cap.left"
    return out


def canto_light(f: Along, light: bool) -> Tex:
    """Rodapié y, en la punta del _x (``light``), filo claro de 1 px entre el canto y la cara (da a la luz)."""

    def tex(a: np.ndarray, c: np.ndarray, z: np.ndarray, tone: np.ndarray) -> np.ndarray:
        out = tone.copy()
        if light and f.edge == "x":
            out[(a > EDGE - 0.1) & (c > HALF - 0.5) & (tone != "wall.top")] = "wall.light"
        return baseboard(out, z)

    return tex


def jamb_light(a_edge: float, mat: str) -> Tex:
    """Filo claro de 1 px en la arista de adelante de una jamba que da al hueco (``a_edge``)."""

    def tex(a: np.ndarray, c: np.ndarray, z: np.ndarray, tone: np.ndarray) -> np.ndarray:
        out = tone.copy()
        out[(np.abs(a - a_edge) < 0.5) & (c > HALF - 0.1) & (tone != f"{mat}.top")] = f"{mat}.light"
        return out

    return tex


def wall_block(f: Along, a0: float, a1: float, z0: float, z1: float, top: bool = True) -> None:
    """Bloque de pared del grosor entero; con ``top``, tapa ciruela arriba (pared y tapa son una pieza)."""
    tex = canto_light(f, a1 == EDGE and f.group == "self" and f.part is None)
    if top:
        f.box("wall", "wall", a0, a1, -HALF, HALF, z0, z1 - CAP_H, tex=tex)
        f.box("wall", "cap", a0, a1, -HALF, HALF, z1 - CAP_H, z1, lit=True)
    else:
        f.box("wall", "wall", a0, a1, -HALF, HALF, z0, z1, tex=tex)


def ghosts_at(edge: str, height: float, start: float) -> list[Solid]:
    """Tramo fantasma que termina en ``start`` (a lo largo)."""
    behind = Along(edge, part="~wall", group="~")
    wall_block(behind, start - EDGE, start, 0, height)
    for s in behind.solids:
        s.mat = "~"
    return behind.solids


def ghosts(edge: str, height: float) -> list[Solid]:
    """Tramo de atrás y piso: tapan el contorno de la unión y del pie, y se borran al final."""
    behind = Along(edge, part="~wall", group="~")
    wall_block(behind, -EDGE, 0.0, 0, height)
    floor = Along(edge, part="~floor", group="~")
    floor.box("~floor", "~", -EDGE, 2 * EDGE, -HALF - 0.5, HALF + 1.5, -8, 0)  # franja al pie, no detrás
    for s in behind.solids:
        s.mat = "~"
    return behind.solids + floor.solids


# ---------------------------------------------------------------------------- vista y acabado

@dataclass
class PieceView(View):
    org: tuple[float, float] = (0.0, 0.0)

    @property
    def origin(self) -> tuple[float, float]:
        return self.org


def wall_canvas(edge: str, tall: bool, grow: tuple[int, int, int, int] = (0, 0, 0, 0)) -> PieceView:
    """Vista del lienzo de un tramo; ``grow`` (izquierda, arriba, derecha, abajo) lo agranda sin mover el tramo."""
    h = CANVAS_TALL if tall else CANVAS_LOW
    gl, gt, gr, gb = grow
    ox = HALF * 2 if edge == "y" else CANVAS_W - HALF * 2
    return PieceView(0, 32, 32, (CANVAS_W + gl + gr, h + gt + gb), (ox + gl, h - BOTTOM + gt))


def ink_side(edge: str) -> str:
    """Lado del lienzo donde cae el canto de la punta del tramo."""
    return "right" if edge == "y" else "left"


def piece_anchor(tall: bool) -> list[float]:
    h = CANVAS_TALL if tall else CANVAS_LOW
    return [CANVAS_W / 2.0, float(h - 18)]


def finish(frame: Frame, ink_side: Optional[str] = None) -> Frame:
    """Como ``_chair_kit.finish`` pero los fantasmas no marcan línea ni llevan contorno, y al final se borran.
    ``ink_side`` ("left"/"right"): la columna de ese borde del lienzo va de contorno (el canto del tramo llega
    justo al borde, así el contorno queda adentro)."""
    tone, part, group, depth = frame.tone.copy(), frame.part.copy(), frame.group.copy(), frame.depth.copy()
    filled = depth > EMPTY / 2
    ghost = np.vectorize(lambda p: p.startswith("~"))(part)
    mat_of = np.vectorize(lambda t: t.split(".")[0] if t else "")(tone)
    up_part = _shift(part, 1, 0, "")
    lit = frame.lit_top & (up_part != part) & ~_shift(ghost, 1, 0, False)
    if lit.any():
        tone[lit] = np.vectorize(lambda m: f"{m}.light")(mat_of[lit])
    seam = np.zeros_like(filled)
    for dy, dx in NEIGHBORS4:
        n_part = _shift(part, dy, dx, "")
        n_depth = _shift(depth, dy, dx, EMPTY)
        n_ghost = _shift(ghost, dy, dx, False)
        seam |= filled & ~ghost & ~n_ghost & (n_part != "") & (n_part != part) & (n_depth > depth + SEAM_GAP)
        for mine, other in LINES:
            seam |= (part == mine) & (n_part == other)
    if seam.any():
        tone[seam] = np.vectorize(lambda m: f"{m}.dark")(mat_of[seam])
    best = np.full(depth.shape, EMPTY)
    for dy, dx in NEIGHBORS4:
        n_depth = _shift(depth, dy, dx, EMPTY)
        n_mat = _shift(mat_of, dy, dx, "")
        n_part = _shift(part, dy, dx, "")
        n_group = _shift(group, dy, dx, "")
        take = ~filled & (n_depth > best)
        best[take] = n_depth[take]
        if take.any():
            tone[take] = np.vectorize(lambda m: f"{m}.ink")(n_mat[take])
        part[take] = n_part[take]
        group[take] = n_group[take]
    ring = ~filled & (best > EMPTY / 2)
    depth[ring] = best[ring]
    if ink_side:
        col = 0 if ink_side == "left" else tone.shape[1] - 1
        edge = filled[:, col] & ~ghost[:, col]
        tone[edge, col] = [f"{m}.ink" for m in mat_of[edge, col]]
    gone = np.vectorize(lambda p: p.startswith("~"))(part)
    # Contorno suelto (sin nada pintado alrededor) que quedó de un fantasma.
    ink = np.vectorize(lambda t: t.endswith(".ink"))(tone) & ~gone
    body = (tone != "") & ~ink & ~gone
    near = np.zeros_like(body)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                near |= _shift(body, dy, dx, False)
    gone |= ink & ~near
    tone[gone] = ""
    part[gone] = ""
    group[gone] = ""
    depth[gone] = EMPTY
    return Frame(tone, part, group, depth, frame.lit_top)


def to_rgba(tone: np.ndarray, mats: Iterable[Mat]) -> np.ndarray:
    table = {}
    for m in mats:
        for k, hexa in m.tones().items():
            table[f"{m.name}.{k}"] = [int(hexa[i:i + 2], 16) for i in (1, 3, 5)]
    out = np.zeros(tone.shape + (4,), dtype=np.uint8)
    for name in np.unique(tone):
        if name:
            sel = tone == name
            out[sel, :3] = table[name]
            out[sel, 3] = 255
    return out


def draw(solids: list[Solid], v: PieceView, mats: Iterable[Mat], ink_side: Optional[str] = None
         ) -> tuple[np.ndarray, np.ndarray]:
    """Pinta y acaba: (rgba, profundidad)."""
    frame = finish(render(solids, v, v.canvas), ink_side)
    return to_rgba(frame.tone, mats), frame.depth


def silhouette(solids: list[Solid], v: PieceView) -> np.ndarray:
    return render(solids, v, v.canvas).depth > EMPTY / 2


# ---------------------------------------------------------------------------- salida

@dataclass
class Sprite:
    name: str
    rgba: np.ndarray
    entry: dict


def crop_frames(frames: list[np.ndarray], base: tuple[int, int, int, int]) -> tuple[tuple[int, int, int, int], list[int]]:
    """Recuadro común de los cuadros de una animación y del tramo (x0, y0, ancho, alto en el lienzo grande)."""
    alpha = np.zeros(frames[0].shape[:2], dtype=bool)
    for arr in frames:
        alpha |= arr[..., 3] == 255
    bx, by, bw, bh = base
    alpha[by:by + bh, bx:bx + bw] = True
    ys, xs = np.nonzero(alpha)
    y0, y1, x0, x1 = int(ys.min()), int(ys.max()) + 1, int(xs.min()), int(xs.max()) + 1
    return (x0, y0, x1 - x0, y1 - y0), [bx - x0, by - y0]


def main(title: str, sprites: Callable[[], Iterator[Sprite]], here: Path) -> int:
    """Escribe cada PNG con su documento Moana (comprueba que Moana dé los mismos pixeles) y el manifest.json."""
    parser = argparse.ArgumentParser(description=f"Genera {title} con Moana.")
    parser.add_argument("--out", type=Path, default=here, help="carpeta de salida (por defecto, la del build.py)")
    parser.add_argument("--only", default="", help="solo los nombres que contengan esto")
    args = parser.parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    entries: dict[str, dict] = {}
    count = 0
    for s in sprites():
        if args.only and args.only not in s.name:
            continue
        doc = painter_document(s.name, s.rgba)
        (out / f"{s.name}.moana.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
        drawn = moana_render(doc)
        if not np.array_equal(drawn, s.rgba):
            problems.append(f"{s.name}: Moana no da los mismos pixeles que el dibujo")
        Image.fromarray(drawn, "RGBA").save(out / f"{s.name}.png")
        entries[f"{s.name}.png"] = s.entry
        count += 1
    if not args.only:
        manifest = {"_comentario": "Apoyo (px del sprite) y datos de cada PNG de esta carpeta; lo escribe build.py y "
                                   "export_game.py lo pasa al juego.", "sprites": entries}
        (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    for line in problems:
        print("FALLO:", line)
    print(f"{count} sprites")
    print("RESULTADO:", "OK" if not problems else f"{len(problems)} fallos")
    return 1 if problems else 0


def wall_entry(edge: str, tall: bool, color: str, **extra: object) -> dict:
    return {"anchor": piece_anchor(tall), "kind": "wall", "axis": edge, "tall": tall,
            "height": DATA["wall"]["height"] if tall else DATA["low_wall_height"],
            "sort_bias": SORT_BIAS_X if edge == "x" else 0.0, "wall_color": color, **extra}


def angle_cos(deg: float) -> tuple[float, float]:
    t = math.radians(deg)
    return math.cos(t), math.sin(t)


__all__ = ["Along", "CAP", "ALU", "METAL", "GHOST", "Mat", "Solid", "Sprite", "colors", "hexes", "mix", "ramp8",
           "_ring_faces"]


# ---------------------------------------------------------------------------- hojas que giran

@dataclass
class Leaf:
    """Hoja con bisagra en ``hinge`` (a), de ``width`` unidades hacia ``sign`` (±1), girada ``angle`` grados
    hacia +c (o −c con ``outward``), de z0 a z1 y ``2·RECESS`` de grosor."""

    hinge: float
    sign: float
    width: float
    angle: float
    outward: bool
    z0: float
    z1: float

    def __post_init__(self) -> None:
        out = -1.0 if self.outward else 1.0
        t = math.radians(self.angle)
        turn = self.sign * out * t
        self.d = (self.sign * self.width * math.cos(t), out * self.width * math.sin(t))  # a lo largo de la hoja
        self.n = (-math.sin(turn), math.cos(turn))  # la cara que da adentro cuando está cerrada
        self.h = (self.hinge + self.sign * out * RECESS * math.sin(t), 0.0)  # gira sin salirse de la jamba
        self.px = self.width * 2.0

    def point(self, a: float, k: float, b: float) -> tuple[float, float, float]:
        """a: px desde la bisagra; k: unidades hacia adentro desde el medio; b: px desde z0."""
        t = a / self.px
        return (self.h[0] + self.d[0] * t + self.n[0] * k, self.h[1] + self.d[1] * t + self.n[1] * k, self.z0 + b)

    def coords(self, a: np.ndarray, c: np.ndarray, z: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """(px desde la bisagra, unidades hacia adentro, px desde z0) de un punto (a, c, z)."""
        ra, rc = a - self.h[0], c - self.h[1]
        dd = self.d[0] ** 2 + self.d[1] ** 2
        along = (ra * self.d[0] + rc * self.d[1]) / dd * self.px
        k = ra * self.n[0] + rc * self.n[1]
        return along, k, z - self.z0

    def add(self, f: Along, mat: str, face: Optional[Callable], hardware: Iterable[tuple] = ()) -> None:
        """La hoja (``face(a, b, k, tono)`` pinta sus caras grandes) y sus herrajes
        (a0, a1, k0, k1, b0, b1, material), en px desde la bisagra, unidades hacia adentro y px desde z0."""
        tex = None
        if face is not None:
            def tex(a: np.ndarray, c: np.ndarray, z: np.ndarray, tone: np.ndarray) -> np.ndarray:
                la, lk, lb = self.coords(a, c, z)
                big = (np.abs(lk) > RECESS - 0.25) & (lb < self.z1 - self.z0 - 0.3)
                out = face(np.floor(la), np.floor(lb), lk, tone)
                return np.where(big, out, tone)
        f.hexa("leaf", mat, self.point(0, -RECESS, 0), (self.d[0], self.d[1], 0.0),
               (self.n[0] * 2 * RECESS, self.n[1] * 2 * RECESS, 0.0), (0.0, 0.0, self.z1 - self.z0), tex)
        for a0, a1, k0, k1, b0, b1, hmat in hardware:
            t = (a1 - a0) / self.px
            f.hexa("hardware", hmat, self.point(a0, k0, b0), (self.d[0] * t, self.d[1] * t, 0.0),
                   (self.n[0] * (k1 - k0), self.n[1] * (k1 - k0), 0.0), (0.0, 0.0, b1 - b0))


def frame_sprites(names: list[str], images: list[np.ndarray], grow: tuple[int, int, int, int], tall: bool,
                  entry: Callable[[int], dict]) -> Iterator["Sprite"]:
    """Cuadros de una animación recortados a un recuadro común; el apoyo y ``base_offset`` se corren con él."""
    gl, gt = grow[0], grow[1]
    base = (gl, gt, CANVAS_W, CANVAS_TALL if tall else CANVAS_LOW)
    (x0, y0, w, h), offset = crop_frames(images, base)
    anchor = [piece_anchor(tall)[0] + offset[0], piece_anchor(tall)[1] + offset[1]]
    for step, (name, arr) in enumerate(zip(names, images), 1):
        crop = np.ascontiguousarray(arr[y0:y0 + h, x0:x0 + w])
        yield Sprite(name, crop, {"anchor": anchor, "kind": "wall_frame", "base_offset": offset, "frame": step,
                                  "frames": len(images), **entry(step)})
