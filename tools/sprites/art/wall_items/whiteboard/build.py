"""Pizarra blanca de Quincena Office (``whiteboard_x`` y ``_y``), hecha con Moana. Ver ../_wall_kit.py.

Marco de aluminio de 2 px en relieve con filo claro arriba y la superficie blanca 1 px más adentro: título
subrayado y lista en azul, gráfico con ejes negros y curva roja, círculo verde y una nota amarilla pegada.
Abajo, la bandeja de aluminio con marcadores azul y rojo y el borrador. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/wall_items/whiteboard/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _wall_kit import BASE, FACE, WallSpec, main_wall  # noqa: E402
from _boxes import box, colors, faces, ramp  # noqa: E402

GROUP = "board"
X0, X1 = 4.0, 28.0  # 48 px a lo largo (con el fondo, lo que entra en el lienzo)
TOP = BASE + 32.0  # `height` 16 × 2
BAR = 1.0  # 2 px de marco
DEPTH = 1.0
SURFACE = FACE + 0.5  # la superficie queda 1 px detrás del marco

ALU = ramp("alu", "#B7C0C6FF", "#A3ADB3FF", "#8D989FFF", "#3D3B44FF", "#E2E7EAFF", "#6F7A80FF")
BOARD = colors("board", "#3D3B44FF", light="#FFFFFFFF", top="#F7F7F2FF", upper="#E6E7E2FF", left="#3D6FB0FF",
               right="#C03D43FF", dark="#A9B1B4FF")  # dark: sombra del marco sobre la superficie
EXTRA = colors("extra", "#2B2526FF", light="#FFF3A6FF", top="#4C8A3AFF", upper="#F2D65CFF", left="#3D6FB0FF",
               right="#C03D43FF", dark="#4A4A52FF")


def board_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    f = faces(mx, my, mz, X0, X1, FACE, SURFACE, BASE, TOP)
    a, b = np.floor(f.a), np.floor(f.b)
    h = TOP - BASE
    out = tone.copy()
    front = f.back
    out[front] = "board.top"
    out[front & (a + (h - b) > 56) & (a + (h - b) < 61)] = "board.light"  # reflejo en diagonal
    title = (b == h - 6) & (a >= 5) & (a < 22) & (np.mod(a, 4) != 3)
    under = (b == h - 8) & (a >= 5) & (a < 24)
    items = np.zeros(a.shape, dtype=bool)
    for k in range(3):
        row = h - 12 - 4 * k
        items |= (b == row) & (a >= 7) & (a < 18 - 3 * k) & (np.mod(a, 5) != 4)
        items |= (b == row) & (a == 5)
    out[front & (title | under | items)] = "board.left"
    axes = ((a == 27) & (b >= 5) & (b < 20)) | ((b == 5) & (a >= 27) & (a < 43))
    out[front & axes] = "extra.dark"
    xs = a - 28
    curve = (xs >= 0) & (xs < 14) & (np.abs(b - (7 + np.floor(xs * 0.8))) < 0.6)
    out[front & curve] = "board.right"
    ring = np.abs(np.hypot(a - 38.5, b - (h - 8.5)) - 2.5) < 0.6
    out[front & ring] = "extra.top"
    note = (a >= 17) & (a < 23) & (b >= 3) & (b < 9)
    out[front & note] = "extra.upper"
    out[front & note & (b == 8)] = "extra.light"
    out[front & note & (b >= 4) & (b < 7) & (np.mod(b, 2) == 0) & (a >= 18) & (a < 22)] = "extra.dark"
    out[~front] = "alu.dark"
    return out


def paint(color: str, top: str = ""):
    """Textura de un solo color (con la tapa de otro, si se da): marcadores y borrador."""

    def texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
        out = np.full(tone.shape, color, dtype=object)
        if top:
            out[np.char.endswith(tone.astype(str), ".top")] = top
        return out

    return texture


def model() -> list:
    y1 = FACE + DEPTH
    kw = {"lit": True}
    return [
        box("surface", GROUP, "board", X0 + 0.5, X1 - 0.5, FACE, SURFACE, BASE + 1, TOP - 1, texture=board_texture),
        box("frame_top", GROUP, "alu", X0, X1, FACE, y1, TOP - 2, TOP, **kw),
        box("frame_bottom", GROUP, "alu", X0, X1, FACE, y1, BASE, BASE + 2, **kw),
        box("frame_left", GROUP, "alu", X0, X0 + BAR, FACE, y1, BASE + 2, TOP - 2, **kw),
        box("frame_right", GROUP, "alu", X1 - BAR, X1, FACE, y1, BASE + 2, TOP - 2, **kw),
        box("tray", GROUP, "alu", X0 + 2, X1 - 2, FACE, FACE + 2.5, BASE - 2, BASE, **kw),
        box("tray_lip", GROUP, "alu", X0 + 2, X1 - 2, FACE + 2.0, FACE + 2.5, BASE, BASE + 1),
        box("marker_blue", GROUP, "extra", 9.5, 12.0, FACE + 0.8, FACE + 1.8, BASE, BASE + 1.5,
            texture=paint("extra.left")),
        box("marker_red", GROUP, "board", 13.5, 16.0, FACE + 0.8, FACE + 1.8, BASE, BASE + 1.5,
            texture=paint("board.right")),
        box("eraser", GROUP, "extra", 19.0, 22.5, FACE + 0.4, FACE + 2.0, BASE, BASE + 2.5,
            texture=paint("extra.dark", "alu.upper")),
    ]


MATS = {m.name: m for m in (ALU, BOARD, EXTRA)}
SPECS = [WallSpec("whiteboard", MATS, model, max_colors=24)]

if __name__ == "__main__":
    raise SystemExit(main_wall(SPECS, HERE))
