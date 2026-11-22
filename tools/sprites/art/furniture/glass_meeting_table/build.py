"""Mesa de reuniones de vidrio (2 x 2, rectangular) de Quincena Office, hecha con Moana.

Tablero de vidrio sobre cuatro patas y un marco cromados. Los PNG no admiten transparencia a medias,
así que lo que se ve a través del vidrio (marco y patas) se pinta encima del tablero en un tono más
oscuro. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/furniture/glass_meeting_table/build.py [--out DIR] [--preview]
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from _desk_kit import (COLORS, Box, Decal, DeskSpec, depth, doc, faces, main, material, outer_ink,  # noqa: E402
                       outline, view)

TOP_Z = 40  # height 20 del catálogo = 40 px
GLASS = 2  # grosor del vidrio en px
TOP = (2, 62, 10, 54)  # tablero: x0, x1, y0, y1 en unidades (la planta es de 64 x 64)
LEG = 2  # lado de cada pata
LEGS_X, LEGS_Y = (7, 55), (15, 47)  # esquina -x/-y de las patas
RAIL_Z = (TOP_Z - GLASS - 3, TOP_Z - GLASS)  # marco bajo el vidrio

COLORS_GLASS = {
    "ink": "#1E3438FF",
    "ink_in": "#4F7A80FF",
    **material("glass", (0x9C, 0xD2, 0xD6), "#E8FBFCFF", grain="#7FB4BAFF"),
    **material("chrome", (0x9E, 0xA4, 0xAC), "#F2F5F8FF"),
    "shadow_ink": COLORS["shadow_ink"],
    "shadow_soft": COLORS["shadow_soft"],
}


def model(_spec: DeskSpec) -> tuple[list[Box], Box]:
    x0, x1, y0, y1 = TOP
    lx0, lx1 = LEGS_X[0], LEGS_X[1] + LEG
    ly0, ly1 = LEGS_Y[0], LEGS_Y[1] + LEG
    legs = [Box(f"leg{i}", x, x + LEG, y, y + LEG, 0, RAIL_Z[0], mat="chrome")
            for i, (x, y) in enumerate((x, y) for x in LEGS_X for y in LEGS_Y)]
    rails = [
        Box("rail_front", lx0, lx1, ly0, ly0 + LEG, *RAIL_Z, mat="chrome"),
        Box("rail_back", lx0, lx1, ly1 - LEG, ly1, *RAIL_Z, mat="chrome"),
        Box("rail_left", lx0, lx0 + LEG, ly0 + LEG, ly1 - LEG, *RAIL_Z, mat="chrome"),
        Box("rail_right", lx1 - LEG, lx1, ly0 + LEG, ly1 - LEG, *RAIL_Z, mat="chrome"),
    ]
    top = Box("top", x0, x1, y0, y1, TOP_Z - GLASS, TOP_Z, mat="glass")
    z = TOP_Z
    # El marco visto a través del vidrio: un rectángulo más oscuro, y las patas en sus esquinas.
    frame = [(lx0, ly0), (lx1, ly0), (lx1, ly1), (lx0, ly1)]
    for i, (a, b) in enumerate(zip(frame, frame[1:] + frame[:1])):
        top.decals.append(Decal(f"frame{i}", "@dark", (0, 0, 1), [(a[0], a[1], z), (b[0], b[1], z)]))
    # Reflejos: dos franjas en diagonal y el canto claro del frente.
    for k, (u, w) in enumerate(((x0 + 14, 6), (x0 + 24, 2))):
        top.decals.append(Decal(f"glare{k}", "@lit", (0, 0, 1),
                                [(u, y1 - 2, z), (u + w, y1 - 2, z), (u + w + 12, y0 + 2, z), (u + 12, y0 + 2, z)]))
    return [*legs, *rails], top


def document(spec: DeskSpec, r: int) -> dict[str, object]:
    """Patas y marco de atrás hacia adelante, el vidrio encima y el contorno fuerte afuera."""
    v = view(spec, r)
    under, top = spec.parts()
    parts = sorted(under, key=lambda b: depth(b, v)) + [top]
    body = [op for b in parts for op in [*outline(b, v), *faces(b, v)]]
    masks, outer = outer_ink(spec, parts, v)
    layers = [
        {"id": "body", "name": "Piezas", "operations": body},
        {"id": "outer_ink", "name": "Contorno exterior", "mask_id": "outside", "operations": outer},
    ]
    return doc(spec, f"{spec.name}_r{r}", masks, layers)


SPEC = DeskSpec(name="glass_meeting_table", size=(2, 2), canvas=(256, 192), model=model, colors=COLORS_GLASS,
                contact=("leg0", "leg1", "leg2", "leg3"))

if __name__ == "__main__":
    raise SystemExit(main(SPEC, HERE, document))
