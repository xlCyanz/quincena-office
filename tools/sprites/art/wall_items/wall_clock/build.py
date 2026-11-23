"""Reloj de pared de Quincena Office (``wall_clock_x`` y ``_y``), hecho con Moana. Ver ../_wall_kit.py.

Disco de 20 px: aro negro de canto redondo (filo gris arriba a la izquierda) y esfera crema delante, con la
sombra del aro en su borde de arriba, marcas largas en 12, 3, 6 y 9 y puntos en las demás horas. Marca las
3:00 con el segundero rojo en el 6: las agujas siguen la vertical y el largo de la pared, así salen como
trazos limpios en la escalera 2:1. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/wall_items/wall_clock/build.py [--out DIR] [--preview]
"""

import math
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _wall_kit import BASE, FACE, WallSpec, main_wall  # noqa: E402
from _boxes import colors, ramp  # noqa: E402
from _chair_kit import Solid, _ring_faces  # noqa: E402

GROUP = "clock"
CX = 16.0
R = 10.0  # radio del aro en px
CZ = BASE + R
DIAL_R = 8.0
DIAL_Y = FACE + 2.4  # cara de la esfera

RIM = ramp("rim", "#313030FF", "#2A2828FF", "#222020FF", "#000000FF", "#6A6A6AFF", "#141414FF")
DIAL = colors("dial", "#1C1C1CFF", light="#FFFDF6FF", top="#F2EEE2FF", upper="#D9D3C2FF", left="#8A8478FF",
              right="#2A2828FF", dark="#C03D43FF")


def disc(part: str, mat: str, profile: list[tuple[float, float]], texture, sides: int = 28) -> Solid:
    """Disco pegado a la pared, de aros (radio en px, y) de atrás hacia adelante; x corre a la mitad."""

    def ring(rad: float, y: float) -> list[tuple[float, float, float]]:
        return [(CX + rad * math.cos(2 * math.pi * k / sides) / 2, y, CZ + rad * math.sin(2 * math.pi * k / sides))
                for k in range(sides)]

    rings = [ring(rad, y) for rad, y in profile]
    faces = [rings[0][::-1], rings[-1]]
    for lo, hi in zip(rings, rings[1:]):
        faces += _ring_faces(lo, hi)
    center = (CX, (profile[0][1] + profile[-1][1]) / 2, CZ)
    return Solid(part, GROUP, mat, faces, center, texture=texture)


def polar(mx: np.ndarray, mz: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    da = (mx - CX) * 2.0  # px a la derecha
    db = mz - CZ  # px hacia arriba
    return da, db, np.hypot(da, db), np.degrees(np.arctan2(da, db)) % 360  # ángulo: 0 arriba, horario


def dial_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    out = tone.copy()
    front = my > DIAL_Y - 0.2
    da, db, dist, ang = polar(mx, mz)
    out[front] = "dial.top"
    out[front & (dist > DIAL_R - 1.1) & (db > 0.5) & (da < 2.0)] = "dial.upper"  # sombra del aro
    for k in range(12):
        off = np.abs(((ang - k * 30 + 180) % 360) - 180) * math.pi / 180 * dist
        if k % 3 == 0:
            out[front & (off < 0.75) & (dist > 4.6) & (dist < 6.6)] = "dial.right"
        else:
            out[front & (off < 0.55) & (dist > 5.4) & (dist < 6.4)] = "dial.left"

    def hand(deg: float, width: float, length: float) -> np.ndarray:
        off = np.abs(((ang - deg + 180) % 360) - 180) * math.pi / 180 * dist
        return front & (off < width) & (dist < length)

    out[hand(180, 0.45, 6.0) | hand(0, 0.45, 1.6)] = "dial.dark"  # segundero en el 6, con contrapeso
    out[hand(90, 0.95, 4.0) | hand(0, 0.6, 5.6)] = "dial.right"  # horario a las 3, minutero en el 12
    out[front & (dist < 1.2)] = "dial.right"
    out[front & (dist < 0.6)] = "dial.dark"  # eje
    return out


def rim_texture(mx: np.ndarray, my: np.ndarray, mz: np.ndarray, tone: np.ndarray) -> np.ndarray:
    out = tone.copy()
    da, db, dist, ang = polar(mx, mz)
    edge = (my > FACE + 1.7) & (dist > R - 1.6) & ((ang > 280) | (ang < 20))  # filo de luz arriba a la izquierda
    out[edge] = "rim.light"
    return out


def model() -> list:
    rim = [(R - 0.6, FACE), (R, FACE + 0.6), (R, FACE + 1.3), (R - 0.7, FACE + 2.0), (R - 1.6, FACE + 2.3)]
    dial = [(DIAL_R, FACE + 1.8), (DIAL_R, DIAL_Y)]
    return [disc("rim", "rim", rim, rim_texture), disc("dial", "dial", dial, dial_texture)]


SPECS = [WallSpec("wall_clock", {m.name: m for m in (RIM, DIAL)}, model, max_colors=20)]

if __name__ == "__main__":
    raise SystemExit(main_wall(SPECS, HERE))
