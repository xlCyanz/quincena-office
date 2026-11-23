"""Televisor de pared de Quincena Office (``presentation_screen_x`` y ``_y``: la pantalla de
presentaciones, en dos bordes), hecho con Moana. Ver ../_wall_kit.py.

96 × 60 px de media pared a casi el techo, colgado de dos soportes cortos: marco negro delgado en relieve con
filo gris del lado de la luz, logo y luz de encendido en el marco de abajo, y la pantalla 1 px más adentro.
Apagada lleva reflejos finos en diagonal. Encendida (Sala de reuniones) muestra una diapositiva clara con
barra de título azul: barras (``_chart``), torta con leyenda (``_pie``) o portada con logo (``_title``), y la
luz verde; cada una se arma de a poco en 12 cuadros (``<pieza>_<eje>_play_1`` a ``_12``, el último es la
pieza quieta). Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/wall_items/presentation_screen/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _wall_kit import FACE, WallSpec, current_axis, main_wall  # noqa: E402
from _boxes import box, colors, faces, ramp  # noqa: E402

GROUP = "tv"
X0, X1 = 8.0, 56.0  # 96 px a lo largo de los dos bordes
Z0, Z1 = 50.0, 110.0  # de media pared a casi el techo (120)
BACK = FACE + 0.5  # separado de la pared por los soportes
GLASS = FACE + 2.0
FRONT = FACE + 2.5  # el marco sobresale 1 px de la pantalla
SIDE, LOWER = 1.5, 4.0  # marco: 3 px a los lados y arriba, 4 px abajo

PLASTIC = ramp("plastic", "#313030FF", "#222020FF", "#1C1C1CFF", "#000000FF", "#6A6A78FF", "#111111FF")
SCREEN = colors("screen", "#000000FF", light="#4A4A56FF", top="#1A1A1CFF", upper="#3A3A42FF", left="#2B2B31FF",
                right="#8C96A0FF", dark="#0E0E10FF")
SLIDE = colors("slide", "#000000FF", light="#FFFFFFFF", top="#E4ECEEFF", upper="#C9D6DAFF", left="#3D90C0FF",
               right="#6DACCEFF", dark="#4F5862FF")
ACCENT = colors("accent", "#000000FF", light="#6FE08AFF", top="#DF823DFF", upper="#8FBF3CFF", left="#C03D43FF",
                right="#C03D43FF", dark="#C03D43FF")
BG, SHADE, BLUE, BLUE2, TEXT, WHITE = (f"slide.{k}" for k in ("top", "upper", "left", "right", "dark", "light"))
ORANGE, GREEN, RED = "accent.top", "accent.upper", "accent.left"
FRAMES = 12


WORDS = (5, 3, 7, 4, 2, 6, 4, 5, 3, 6, 2, 4)


def text_row(u: np.ndarray, v: np.ndarray, u0: int, v0: int, length: int, shift: int = 0) -> np.ndarray:
    """Renglón de «texto» de 1 px en la fila v0, de u0 a u0 + length, partido en palabras."""
    marks = np.zeros(int(length) + 1, dtype=bool)
    pos, k = 0, shift
    while pos < length:
        word = WORDS[k % len(WORDS)]
        marks[pos:min(pos + word, int(length))] = True
        pos += word + 1
        k += 1
    inside = (v == v0) & (u >= u0) & (u < u0 + length)
    return inside & marks[np.clip(u - u0, 0, int(length)).astype(int)]


def ease(t: float, start: float = 0.0, length: float = 1.0) -> float:
    """0 antes de start, 1 después de start + length y una curva suave en el medio."""
    x = min(max((t - start) / length, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def reveal(mask: np.ndarray, u: np.ndarray, u0: int, length: int, amount: float) -> np.ndarray:
    """Deja ver la parte izquierda de un renglón (se escribe de izquierda a derecha)."""
    return mask & (u < u0 + np.ceil(length * amount))


def slide(variant: str, u: np.ndarray, v: np.ndarray, gw: int, gh: int, t: float) -> np.ndarray:
    """Diapositiva de frente: u desde la izquierda, v desde arriba (px); t = avance (1 = completa)."""
    out = np.full(u.shape, BG, dtype=object)
    bar = v < 7
    out[bar] = BLUE
    if variant != "title":
        out[reveal(text_row(u, v, 4, 3, 30, 1), u, 4, 30, ease(t, 0.0, 0.3))] = WHITE
    out[bar & (v >= 2) & (v < 5) & (u >= gw - 6) & (u < gw - 3)] = ORANGE
    if variant == "chart":
        x0, y1 = 6, gh - 5
        axis = ease(t, 0.0, 0.2)
        out[(u == x0) & (v <= y1) & (v >= y1 - np.ceil((y1 - 11) * axis))] = TEXT
        out[(v == y1) & (u >= x0) & (u < x0 + np.ceil((60 - x0) * axis))] = TEXT
        for k, h in enumerate((10, 15, 13, 21, 26, 32)):
            bx = x0 + 4 + k * 8
            grow = np.ceil(h * ease(t, 0.12 + k * 0.08, 0.35))
            col = ORANGE if k == 5 else (BLUE if k % 2 == 0 else BLUE2)
            out[(u >= bx) & (u < bx + 5) & (v < y1) & (v >= y1 - grow)] = col
            out[(u == bx + 4) & (v < y1) & (v >= y1 - grow) & (grow > 1)] = TEXT if col == ORANGE else BLUE  # canto
        for k, col in enumerate((BLUE, BLUE2, ORANGE)):
            ly = 14 + k * 6
            show = ease(t, 0.5 + k * 0.1, 0.25)
            if show > 0:
                out[(u >= 66) & (u < 69) & (v >= ly) & (v < ly + 3)] = col
            out[reveal(text_row(u, v, 71, ly + 1, gw - 75, k * 3), u, 71, gw - 75, show)] = TEXT
        notes = ease(t, 0.8, 0.2)
        out[reveal(text_row(u, v, 66, 36, gw - 70, 5), u, 66, gw - 70, notes)
            | reveal(text_row(u, v, 66, 39, gw - 74, 8), u, 66, gw - 74, notes)] = SHADE
    elif variant == "pie":
        cu, cv, r = 22.0, 29.5, 15.0
        du, dv = u + 0.5 - cu, v + 0.5 - cv
        dist = np.hypot(du, dv)
        turn = np.mod(np.arctan2(du, -dv) / (2 * np.pi), 1.0)  # 0 arriba, en el sentido del reloj
        sweep = ease(t, 0.05, 0.6)
        pie = (dist < r) & (turn < sweep + 1.0e-6) if sweep < 1.0 else dist < r
        part = np.where(turn < 0.48, BLUE, np.where(turn < 0.78, ORANGE, GREEN))
        out[pie] = part[pie]
        out[pie & (dist > r - 1.2) & (turn > 0.55) & (turn < 0.95)] = TEXT  # canto en sombra
        cut = pie & (dist > 1.0) & ((np.abs(turn - 0.48) * 2 * np.pi * dist < 0.6)
                                    | (np.abs(turn - 0.78) * 2 * np.pi * dist < 0.6)
                                    | ((turn < 0.02) | (turn > 0.995)) & (np.abs(du) < 0.6))
        out[cut] = BG
        for k, col in enumerate((BLUE, ORANGE, GREEN)):
            ly = 16 + k * 8
            show = ease(t, 0.25 + k * 0.2, 0.25)
            if show > 0:
                out[(u >= 46) & (u < 50) & (v >= ly) & (v < ly + 4)] = col
            length = 20 + 6 * (k % 2)
            out[reveal(text_row(u, v, 53, ly + 1, length, k * 4), u, 53, length, show)] = TEXT
            out[reveal(text_row(u, v, 53, ly + 3, 12, k * 4 + 2), u, 53, 12, show)] = SHADE
    else:
        lx, ly = gw // 2 - 6, 13
        size = ease(t, 0.0, 0.35)
        half = 6.0 * size
        cx, cy = lx + 6.0, ly + 6.0
        logo = (np.abs(u + 0.5 - cx) < half) & (np.abs(v + 0.5 - cy) < half)
        out[logo] = BLUE
        out[logo & (np.abs(u + 0.5 - cx) + np.abs(v + 0.5 - cy) < 4.5 * size)] = ORANGE
        for row, length, col, start in ((30, 46, TEXT, 0.3), (31, 46, TEXT, 0.3), (35, 34, BLUE2, 0.5),
                                        (41, 20, SHADE, 0.65)):
            u0 = (gw - length) // 2
            out[reveal(text_row(u, v, u0, row, length, row), u, u0, length, ease(t, start, 0.3))] = col
        foot = ease(t, 0.8, 0.2)
        line = (v == gh - 4) & (u >= 8) & (u < 8 + np.ceil((gw - 16) * foot))
        out[line & (np.mod(u, 4) != 3)] = SHADE
        out[line & (u >= gw - 14) & (u < gw - 8)] = RED
    return out


# Inclinación de los reflejos en cada pared, para que en las dos caigan igual de empinados en pantalla.
SLANT = {"x": 0.4, "y": -1.2}


def glass_texture(variant: str, t: float):
    """Pantalla apagada (``variant`` vacío) o con la diapositiva ``variant`` al avance ``t``."""

    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        f = faces(mx, my, mz, X0 + SIDE, X1 - SIDE, BACK, GLASS, Z0 + LOWER, Z1 - SIDE * 2)
        a, b = np.floor(f.a), np.floor(f.b)
        gw, gh = int((X1 - X0 - 2 * SIDE) * 2), int(Z1 - Z0 - LOWER - SIDE * 2)
        out = tone.copy()
        front = f.back
        out[~front] = "screen.dark"
        if variant:
            screen = slide(variant, a, gh - 1 - b, gw, gh, t)
            out[front] = screen[front]
            return out
        k = SLANT[current_axis()]
        d = np.floor((a + (gh - b) * k - min(0.0, gh * k)) * 120.0 / (gw + gh * abs(k)))
        out[front] = "screen.top"
        out[front & ((d >= 50) & (d < 60))] = "screen.left"  # reflejo ancho y tenue
        out[front & ((d == 42) | (d == 46) | (d == 74) | (d == 98))] = "screen.upper"  # reflejos finos
        out[front & (b >= gh - 1)] = "screen.dark"  # sombra del marco de arriba
        return out

    return texture


def bezel_texture(on: bool):
    """Marco de abajo: logo y luz de encendido (verde si la pantalla está encendida)."""

    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        return _bezel(mx, my, mz, tone, on)

    return texture


def _bezel(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray, on: bool) -> np.ndarray:
    f = faces(mx, my, mz, X0, X1, BACK, FRONT, Z0, Z0 + LOWER)
    a, b = np.floor(f.a), np.floor(f.b)
    out = tone.copy()
    w = (X1 - X0) * 2
    out[f.back & (b == 1) & (a >= w / 2 - 3) & (a < w / 2 + 3)] = "screen.right"  # logo
    out[f.back & (b == 1) & (a >= w - 8) & (a < w - 7)] = "accent.light" if on else "screen.light"
    return out


def model_for(variant: str = "", t: float = 1.0):
    def model() -> list:
        kw = {"lit": True}
        mounts = [box(f"mount{k}", GROUP, "plastic", x, x + 2.0, FACE, BACK + 1.0, Z0 - 4, Z0 + 6)
                  for k, x in enumerate((X0 + 10.0, X1 - 12.0))]
        return mounts + [
            box("body", GROUP, "plastic", X0 + 0.3, X1 - 0.3, BACK, GLASS - 0.3, Z0 + 0.3, Z1 - 0.3),
            box("glass", GROUP, "screen", X0 + SIDE, X1 - SIDE, BACK, GLASS, Z0 + LOWER, Z1 - SIDE * 2,
                texture=glass_texture(variant, t)),
            box("bezel_top", GROUP, "plastic", X0, X1, BACK, FRONT, Z1 - SIDE * 2, Z1, **kw),
            box("bezel_bottom", GROUP, "plastic", X0, X1, BACK, FRONT, Z0, Z0 + LOWER,
                texture=bezel_texture(bool(variant)), **kw),
            box("bezel_left", GROUP, "plastic", X0, X0 + SIDE, BACK, FRONT, Z0 + LOWER, Z1 - SIDE * 2, **kw),
            box("bezel_right", GROUP, "plastic", X1 - SIDE, X1, BACK, FRONT, Z0 + LOWER, Z1 - SIDE * 2, **kw),
        ]

    return model


MATS = {m.name: m for m in (PLASTIC, SCREEN, SLIDE, ACCENT)}
NAME = "presentation_screen"


def frame_extra(base: str, step: int):
    def extra(axis: str) -> dict:
        return {"base": f"{base}_{axis}.png", "frame": step, "frames": FRAMES, "animation": "play"}

    return extra


SPECS = [WallSpec(NAME, MATS, model_for(), max_colors=20, edges=2, base_z=Z0)]
for variant in ("chart", "pie", "title"):
    base = f"{NAME}_{variant}"
    SPECS.append(WallSpec(base, MATS, model_for(variant), max_colors=32, edges=2, base_z=Z0))
    SPECS += [WallSpec(base, MATS, model_for(variant, step / FRAMES), max_colors=32, edges=2, base_z=Z0,
                       suffix=f"_play_{step}", extra=frame_extra(base, step)) for step in range(1, FRAMES + 1)]

if __name__ == "__main__":
    raise SystemExit(main_wall(SPECS, HERE))
