"""Cosas que van encima de un escritorio (computadoras) como documentos Moana. Usa _desk_kit.py.

Cada build.py da un ``DeskSpec`` de una casilla con lienzo 128 x 160 (apoyo (64, 128), como
`Canvas.on_desk` del generador) cuyo ``model`` devuelve (piezas, None) y llama a ``main`` de aquí.
El juego dibuja el sprite con su apoyo en el centro del escritorio; el tablero queda en z = 44.

El modelo va en rotación 0 con la pantalla mirando a -y, igual que los cajones del escritorio.
"""

from __future__ import annotations

from pathlib import Path

from _desk_kit import (NEG_X, NEG_Y, POS_X, POS_Y, TOP_Y, TOP_Z, Box, Decal, DeskSpec, depth, doc, face_rect,
                       faces, outer_ink, outline, poly, view)
from _desk_kit import main as kit_main

DESK_Z = TOP_Z  # 44: superficie del escritorio
DESK_TOP_X = (1, 31)  # tablero del escritorio sencillo: la sombra no se sale de él
CONTACT_SHIFT = (1, 0)


def glass(name: str, plane: float, x0: float, x1: float, z0: float, z1: float) -> list[Decal]:
    """Vidrio en la cara -y: base, sombra del bisel arriba y a la izquierda, y dos reflejos en diagonal."""
    w, h = x1 - x0, z1 - z0
    decals = [
        Decal(name, "glass_top", NEG_Y, face_rect(NEG_Y, plane, x0, x1, z0, z1)),
        Decal(f"{name}_shade_top", "glass_dark", NEG_Y, [(x0, plane, z1), (x1, plane, z1)]),
        Decal(f"{name}_shade_side", "glass_dark", NEG_Y, face_rect(NEG_Y, plane, x0, x0 + 0.5, z0, z1)),
        # Canto del bisel que recibe la luz, justo debajo del vidrio.
        Decal(f"{name}_sill", "@lit", NEG_Y, [(x0, plane, z0), (x1, plane, z0)]),
    ]
    # Reflejos: tiras que bajan de arriba a la derecha hacia abajo a la izquierda (2 px de alto por unidad).
    for k, (start, width) in enumerate(((0.55, 2.5), (0.78, 1.0))):
        a = x0 + 0.5 + w * start
        drop = min(h - 1, (a + width - x0 - 0.5) * 2)
        top = z1 - 1
        pts = [(a, top), (a + width, top), (a + width - drop / 2, top - drop), (a - drop / 2, top - drop)]
        pts = [(max(x0 + 0.5, min(x1, u)), z) for u, z in pts]
        decals.append(Decal(f"{name}_glare{k}", "glass_light", NEG_Y, [(u, plane, z) for u, z in pts]))
    return decals


def vents_top(box: Box, name: str, y0: float, y1: float, step: float = 1.5, inset: float = 1.5) -> None:
    """Rejilla en la cara de arriba: rayas oscuras a lo largo de x entre y0 e y1."""
    y = y0
    k = 0
    while y <= y1:
        box.decals.append(Decal(f"{name}{k}", "@deep", (0, 0, 1), [(box.x0 + inset, y, box.z1), (box.x1 - inset, y, box.z1)]))
        y += step
        k += 1


def keyboard(x0: float, x1: float, y0: float, y1: float, mat: str, key: str) -> Box:
    """Teclado de 2 px de alto con tres filas de teclas (1,5 unidades cada una, separadas por media)."""
    box = Box("keyboard", x0, x1, y0, y1, DESK_Z, DESK_Z + 2, mat=mat)
    z = DESK_Z + 2
    rows = (y0 + 1, (y0 + y1) / 2, y1 - 1)
    for i, y in enumerate(rows):
        u = x0 + 0.5 + (0.5 if i % 2 else 0)
        k = 0
        while u + 1.5 <= x1 - 0.5:
            length = 1.5
            if i == 2 and x0 + (x1 - x0) * 0.3 <= u <= x0 + (x1 - x0) * 0.6:  # barra espaciadora
                length = min((x1 - x0) * 0.35, x1 - 0.5 - u)
            box.decals.append(Decal(f"key{i}_{k}", key, (0, 0, 1), [(u, y, z), (u + length, y, z)]))
            u += length + 0.5
            k += 1
    return box


def mouse(x: float, y: float, mat: str) -> list[Box]:
    """Ratón: 3 x 4 unidades de planta con las esquinas cortadas, lomo más bajo al frente y la raya
    entre los dos botones. (x, y) es el centro de la planta."""
    body = Box("mouse", x - 1.5, x + 1.5, y - 2, y + 2, DESK_Z, DESK_Z + 2, mat=mat, chamfer=1)
    back = Box("mouse_back", x - 1, x + 1, y - 0.5, y + 1.5, DESK_Z + 2, DESK_Z + 3, mat=mat, chamfer=0.75)
    body.decals.append(Decal("buttons", "@deep", (0, 0, 1), [(x, y - 2, DESK_Z + 2), (x, y - 0.5, DESK_Z + 2)]))
    return [body, back]


def object_document(spec: DeskSpec, r: int) -> dict[str, object]:
    """Todas las piezas de atrás hacia adelante, cada una con su contorno suave, y el contorno fuerte afuera."""
    v = view(spec, r)
    parts, _ = spec.parts()
    parts = sorted(parts, key=lambda b: depth(b, v))
    body = [op for b in parts for op in [*outline(b, v), *faces(b, v)]]
    masks, outer = outer_ink(spec, parts, v)
    layers = [
        {"id": "body", "name": "Piezas", "operations": body},
        {"id": "outer_ink", "name": "Contorno exterior", "mask_id": "outside", "operations": outer},
    ]
    return doc(spec, f"{spec.name}_r{r}", masks, layers)


def contact_document(spec: DeskSpec, r: int) -> dict[str, object]:
    """Sombra de contacto sobre el tablero: planta de lo que apoya, 1 unidad más ancha y corrida a +x."""
    v = view(spec, r)
    p = v.p
    parts, _ = spec.parts()
    sx, sy = CONTACT_SHIFT
    ops = []
    for b in parts:
        if b.name not in spec.contact:
            continue
        x0, x1, y0, y1, _, _ = b.rotated(v)
        x0, x1, y0, y1 = x0 - 1 + sx, x1 + 1 + sx, y0 - 1 + sy, y1 + 1 + sy
        ops.append(poly(f"shadow_{b.name}", "shadow_ink", [p(x0, y0, DESK_Z), p(x1, y0, DESK_Z), p(x1, y1, DESK_Z), p(x0, y1, DESK_Z)]))
    top = Box("desk_top", DESK_TOP_X[0], DESK_TOP_X[1], TOP_Y[0], TOP_Y[1], 0, 0)
    x0, x1, y0, y1, _, _ = top.rotated(v)
    clip = {"id": "desk_top", "type": "polygon",
            "points": [list(pt) for pt in [p(x0, y0, DESK_Z), p(x1, y0, DESK_Z), p(x1, y1, DESK_Z), p(x0, y1, DESK_Z)]]}
    layers = [{"id": "shadow", "name": "Sombra", "mask_id": "desk_top", "operations": ops}]
    return doc(spec, f"{spec.name}_r{r}_shadow", [clip], layers)


def main(spec: DeskSpec, here: Path) -> int:
    return kit_main(spec, here, object_document, contact_document)


__all__ = ["DESK_Z", "NEG_X", "NEG_Y", "POS_X", "POS_Y", "Box", "Decal", "DeskSpec", "face_rect", "glass",
           "keyboard", "main", "mouse", "vents_top"]
