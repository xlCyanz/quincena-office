# Sillas de oficina (4 rotaciones, enteras y en capas asiento/respaldo) y plantas, con el estilo de STYLE.md.
# Capas: el juego dibuja el respaldo encima del asiento en r0 y r3 y debajo en r1 y r2; la de abajo va
# entera y la de encima solo con sus pixeles visibles, así juntas dan la silla exacta.
# `height` de data/furniture.json es el alto del asiento (sillas) o de la maceta (plantas).
import math
import os
from collections import deque

import numpy as np
from PIL import Image

import iso
import palette as pal
import pattern
import sheet

ITEMS = iso.load_json("data/furniture.json")["items"]
CHAIR_ITEM = ITEMS["basic_chair"]
ERGO_ITEM = ITEMS["ergonomic_chair"]
SMALL_ITEM = ITEMS["small_plant"]
LARGE_ITEM = ITEMS["large_plant"]

# Rojo de la silla básica, más oscuro que el de la guía. Ningún tono de una silla puede coincidir con la
# ropa, la piel o el pelo de los personajes (lo comprueba export_game.py).
FABRIC = pal.style_ramp("a8323b", side="86262f", shadow="6c1e1f", outline="3a0b1c", deep="5f0f09", light="cf4f4b",
                        name="chair_red")
# Asiento de la ergonómica: azul oscuro con contorno casi negro.
FABRIC_ERGO = pal.style_ramp("33507a", outline="0e1626", light="4f73a3", name="chair_navy")
PLASTIC = pal.PLASTIC_BLACK
METAL = pal.METAL_LIGHT
# Barro con las caras de la guía (el lado de la tabla es gris y deja franjas en la maceta).
CLAY = pal.style("clay", declared=False, name="pot_clay")
CERAMIC = pal.CERAMIC_WHITE
POT_RED = pal.UPHOLSTERY_RED
# Tierra; su LIGHT es la corteza del tronco con luz (el lado del barro).
SOIL = pal.style_ramp("5d3526", outline="2a1206", light="8e6d53", name="soil")
LEAVES = pal.LEAVES
SHADOW_COLOR = (26, 28, 38)  # el mismo tono que Canvas.ground_shadow()
SHADOW_SHIFT = (0.10, 0.03)  # corrimiento de la sombra por cada 64 px de alto (casillas del mundo)

# ---------------------------------------------------------------------- silla

BACK_PARTS = ["back", "bracket"]
BACK_ON_TOP = (0, 3)  # rotaciones en las que el juego dibuja el respaldo encima del asiento
WHEEL_RADIUS = 0.04  # casillas: unas ruedas de 7 px de ancho en pantalla
WHEEL_Z = 2.8
STAR_TURN = 54  # un brazo apunta al frente: ninguna rueda queda bajo el soporte del respaldo
# El plástico no lleva brillo de arista: en piezas de 3 px quedaría un pixel suelto.
PLASTIC_BANDS = ((0.66, pal.LIGHT), (0.40, pal.BASE), (0.0, pal.LEFT), (-0.44, pal.RIGHT), (-9.0, pal.DEEP))
WHEEL_BANDS = ((0.55, pal.LEFT), (-0.2, pal.RIGHT), (-9.0, pal.DEEP))
COLUMN_BANDS = ((-0.10, pal.LEFT), (9.0, pal.RIGHT))
# Tela: reflejo, base, lado −25 %, −40 % y 1 px de sombra abajo (cojín abultado).
FABRIC_BANDS = ((0.93, pal.LIGHT), (0.50, pal.BASE), (0.05, pal.LEFT), (-0.40, pal.RIGHT), (-9.0, pal.DEEP))


def _spec(item, name, **kw):
    seat_top = iso.world_px(item["height"])
    spec = {"item": item, "name": name, "seat_top": seat_top, "fabric": FABRIC, "back_ramp": FABRIC,
            "seat_half": 15 / 64.0, "seat_cy": 31 / 64.0, "star": 0.26, "arms": False, "mesh": False}
    spec.update(kw)
    return spec


# Asiento a 24 px, la cadera del personaje sentado (character.SIT_SEAT_Z).
SEAT_TOP = 24
# Silla básica: cojín de 7 px y respaldo grueso.
BASIC = _spec(CHAIR_ITEM, "chair_basic", seat_top=SEAT_TOP, cushion=16, pan=13, hub=6, post=23,
              back=(18 / 64.0, 46 / 64.0, 46 / 64.0, 54 / 64.0, 28, 52), back_corner=7, back_edge=3.0,
              bracket_top=40)
# Ergonómica: la misma altura de asiento, respaldo alto de malla con marco, apoyabrazos.
ERGO = _spec(ERGO_ITEM, "chair_ergonomic", seat_top=SEAT_TOP, fabric=FABRIC_ERGO, back_ramp=PLASTIC, cushion=17, pan=14,
             hub=6, post=23, back=(17 / 64.0, 47 / 64.0, 48 / 64.0, 53 / 64.0, 27, 58), back_corner=8, back_edge=2.0,
             bracket_top=40, arms=True, mesh=True)


def _round_rect(px, py, half_x, half_y, radius):
    """Distancia (px) a un rectángulo de esquinas redondas centrado en el origen."""
    qx = np.abs(px) - (half_x - radius)
    qy = np.abs(py) - (half_y - radius)
    outside = np.sqrt(np.maximum(qx, 0.0) ** 2 + np.maximum(qy, 0.0) ** 2)
    return outside + np.minimum(np.maximum(qx, qy), 0.0) - radius


def _extrude(profile, across, edge):
    """Une un perfil 2D con su grosor (distancias en px) redondeando la arista `edge` px."""
    outside = np.sqrt(np.maximum(profile + edge, 0.0) ** 2 + np.maximum(across + edge, 0.0) ** 2)
    return np.minimum(np.maximum(profile, across), 0.0) + outside - edge


def sdf_cushion(cx, cy, half_x, half_y, z0, z1, corner, edge):
    """Cojín horizontal de esquinas (corner px) y aristas (edge px) redondas; planta en casillas, alto en px."""
    def fn(x, y, z):
        plan = _round_rect((x - cx) * iso.Z_METRIC, (y - cy) * iso.Z_METRIC, half_x * iso.Z_METRIC,
                           half_y * iso.Z_METRIC, corner)
        return _extrude(plan, np.abs(z - (z0 + z1) / 2.0) - (z1 - z0) / 2.0, edge)

    return fn


def sdf_upright(x0, x1, y0, y1, z0, z1, corner, edge):
    """Cojín parado (respaldo): su cara ancha (plano x–z) tiene las esquinas redondas."""
    def fn(x, y, z):
        face = _round_rect((x - (x0 + x1) / 2.0) * iso.Z_METRIC, z - (z0 + z1) / 2.0,
                           (x1 - x0) / 2.0 * iso.Z_METRIC, (z1 - z0) / 2.0, corner)
        return _extrude(face, np.abs(y - (y0 + y1) / 2.0) * iso.Z_METRIC - (y1 - y0) / 2.0 * iso.Z_METRIC, edge)

    return fn


def seat_tex(spec):
    """Costura del asiento: una línea a 4 px del borde, solo en lo plano de arriba."""
    half, cy = spec["seat_half"] * 64.0, spec["seat_cy"]

    def tex(ctx):
        ring = np.maximum(np.abs(ctx.x - 0.5), np.abs(ctx.y - cy)) * 64.0
        seam = (ctx.nz > 0.9) & (ring >= half - 5.0) & (ring < half - 4.0)
        return np.where(seam, pal.LEFT, ctx.base)

    return tex


def back_tex(spec):
    """Respaldo: costura a 3 px del borde (tapizado) o marco con rayas de malla."""
    x0, x1, _, _, z0, z1 = spec["back"]

    def tex(ctx):
        wide = np.abs(ctx.ny) > 0.9
        a = (ctx.x - x0) * 64.0
        b = ctx.z - z0
        w, h = (x1 - x0) * 64.0, z1 - z0
        if not spec["mesh"]:
            frame = pattern.frame(a, b, 3, w - 3, 3, h - 3, 1)
            return np.where(wide & frame, pal.darker(ctx.base), ctx.base)
        inner = wide & (a > 3) & (a < w - 3) & (b > 3) & (b < h - 3)
        stripe = (np.floor(ctx.sy) % 2) == 0
        return np.where(inner, np.where(stripe, pal.DEEP, pal.RIGHT), ctx.base)

    return tex


def chair_model(c, spec, group=None):
    """Silla en rotación 0 (frente a −y, respaldo en +y). group = "seat" o "back" arma solo esa capa."""
    cx = 0.5
    cy = spec["seat_cy"]
    top, cushion, pan_z, hub = spec["seat_top"], spec["cushion"], spec["pan"], spec["hub"]
    bx0, bx1, by0, by1, bz0, bz1 = spec["back"]
    if group in (None, "seat"):
        # Base de estrella de 5 brazos con ruedas.
        for k in range(5):
            angle = math.radians(STAR_TURN + 72 * k)
            tx, ty = 0.5 + spec["star"] * math.cos(angle), 0.5 + spec["star"] * math.sin(angle)
            c.capsule((0.5, 0.5, 5.5), (tx, ty, 4.5), 2.2, PLASTIC, bands=PLASTIC_BANDS, name="base")
            # La rueda toca el piso: lo más bajo que se le ve queda a menos de 1 px de z = 0.
            c.sphere(tx, ty, WHEEL_Z, WHEEL_RADIUS, PLASTIC, bands=WHEEL_BANDS, name="base")
        c.cylinder(0.5, 0.5, 4 / 64, 2, hub, PLASTIC, bands=PLASTIC_BANDS, name="base")
        # Columna de metal: asoma entre el cubo de la base y la bandeja.
        c.cylinder(0.5, 0.5, 1 / 32, hub, pan_z + 1, METAL, bands=COLUMN_BANDS, cap=False, name="column",
                   outline=False)
        # Asiento: bandeja de plástico negro y cojín abultado.
        pan = spec["seat_half"] - 3 / 64
        c.sdf(sdf_cushion(cx, cy, pan, pan, pan_z, cushion + 1, 5, 1),
              (cx - pan, cx + pan, cy - pan, cy + pan, pan_z, cushion + 1), PLASTIC, bands=PLASTIC_BANDS, name="pan")
        half = spec["seat_half"]
        c.sdf(sdf_cushion(cx, cy, half, half, cushion, top, 8, 3.5),
              (cx - half, cx + half, cy - half, cy + half, cushion, top), spec["fabric"], tex=seat_tex(spec),
              bands=FABRIC_BANDS, name="seat")
        if spec["arms"]:
            # Apoyabrazos: un poste que sale de la bandeja y una almohadilla larga encima.
            for side in (-1, 1):
                ax = cx + side * (half + 1.5 / 64)
                c.capsule((ax - side * 6 / 64, cy + 3 / 64, cushion), (ax, cy + 3 / 64, cushion), 1.8, PLASTIC,
                          bands=PLASTIC_BANDS, name="arm")
                c.capsule((ax, cy + 3 / 64, cushion), (ax, cy + 3 / 64, top + 6), 1.8, PLASTIC,
                          bands=PLASTIC_BANDS, name="arm")
                c.capsule((ax, cy - 8 / 64, top + 7), (ax, cy + 8 / 64, top + 7), 2.4, PLASTIC,
                          bands=PLASTIC_BANDS, name="arm")
    if group in (None, "back"):
        # Soporte en «J»: brazo diagonal desde abajo del asiento, poste y placa.
        post = spec["post"]
        mid = (by0 + by1) / 2.0
        c.capsule((cx, cy + 10 / 64, pan_z + 1), (cx, mid + 1 / 64, post + 1), 2.2, PLASTIC, bands=PLASTIC_BANDS,
                  name="bracket")
        c.box(30 / 64, 34 / 64, by1 - 1 / 64, by1 + 1 / 64, post, spec["bracket_top"], PLASTIC, part="bracket")
        c.box(29 / 64, 35 / 64, by1 - 1 / 64, by1 + 1 / 64, spec["bracket_top"] - 6, spec["bracket_top"], PLASTIC,
              part="bracket")
        c.sdf(sdf_upright(bx0, bx1, by0, by1, bz0, bz1, spec["back_corner"], spec["back_edge"]),
              (bx0, bx1, by0, by1, bz0, bz1), spec["back_ramp"], tex=back_tex(spec),
              bands=PLASTIC_BANDS if spec["mesh"] else FABRIC_BANDS, name="back")


def _moved(mask, dy, dx):
    """out[y, x] = mask[y + dy, x + dx] (False fuera del arreglo)."""
    out = np.zeros_like(mask)
    h, w = mask.shape
    out[max(-dy, 0):h - max(dy, 0), max(-dx, 0):w - max(dx, 0)] = \
        mask[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)]
    return out


def _groups(mask, diagonal=True):
    """Grupos de pixeles unidos de una máscara (con o sin diagonales): lista de listas (y, x)."""
    seen = np.zeros_like(mask)
    h, w = mask.shape
    steps = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    if diagonal:
        steps += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    found = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        seen[y, x] = True
        queue = deque([(y, x)])
        group = []
        while queue:
            cy, cx = queue.popleft()
            group.append((cy, cx))
            for dy, dx in steps:
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        found.append(group)
    return found


def _long_runs(mask, minimum):
    """La máscara sin los tramos de menos de `minimum` pixeles (rayitas que se leen sueltas)."""
    out = np.zeros_like(mask)
    for group in _groups(mask):
        if len(group) >= minimum:
            for y, x in group:
                out[y, x] = True
    return out


def edge_light(c, part, index=pal.LIGHT, minimum=8, behind=None):
    """Brillo de 1 px por dentro de la arista superior izquierda de una pieza curva, sobre lo que mira arriba.
    Omite tramos de menos de `minimum` px; behind = piezas de atrás que cuentan como vacío."""
    own = c.select(part=part)
    solid = c.alpha if behind is None else c.alpha & ~c.select(part=behind)
    top_edge = own & ~_moved(solid, -1, 0)
    left_free = ~_moved(solid, -1, -2) & ~_moved(solid, -2, -2)
    line = own & _moved(top_edge & left_free, -1, 0) & ~top_edge
    line &= (c.shade == pal.BASE) | (c.shade == pal.SOFT)
    c.paint(_long_runs(line, minimum), index)


def crease_light(c, part, index=pal.LIGHT, minimum=8):
    """Brillo en la arista entre lo de arriba de una pieza curva y su cara izquierda (respaldos en «\\»)."""
    own = c.select(part=part)
    upper = own & ((c.shade == pal.BASE) | (c.shade == pal.SOFT))
    below = _moved(own & (c.shade == pal.LEFT), 1, 0)
    c.paint(_long_runs(upper & below, minimum), index)


def tidy_finish(c, parts=None, passes=3):
    """Quita los pixeles sueltos del acabado: el que no repite tono con ningún vecino toma el de un vecino
    de su material (no contorno)."""
    for _ in range(passes):
        c.finish(**c._finish_options)
        # Brillos de menos de 4 px se leen sueltos: vuelven al tono base.
        glint = c.alpha & (c.final_shade == pal.LIGHT)
        short = glint & ~_long_runs(glint, 4)
        if short.any():
            c.paint(short, pal.BASE)
            c.no_finish(short)
            c.finish(**c._finish_options)
        final = c.final_shade
        own = c.alpha if parts is None else c.select(part=parts)
        # Un pixel de contorno solo cuenta si quedó por dentro (rodeado): el de la silueta se queda.
        inner = _moved(c.alpha, -1, 0) & _moved(c.alpha, 1, 0) & _moved(c.alpha, 0, -1) & _moved(c.alpha, 0, 1)
        lonely = own & ((final != pal.OUTLINE) | inner)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy or dx:
                    lonely &= ~(_moved(c.alpha, dy, dx) & (_moved(final, dy, dx) == final)
                                & (_moved(c.ramp_id, dy, dx) == c.ramp_id))
        if not lonely.any():
            break
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            tone = _moved(final, dy, dx)
            ok = lonely & _moved(c.alpha, dy, dx) & (_moved(c.ramp_id, dy, dx) == c.ramp_id) & (tone != pal.OUTLINE)
            c.paint(ok, tone)
            c.no_finish(ok)
            lonely &= ~ok


def plug_holes(c, ramp, index, part, largest=12, finish=True, notches=False, other=None):
    """Tapa agujeros transparentes encerrados de hasta `largest` px con un tono del material, por detrás.
    finish=False los deja sin acabado; notches=True tapa también muescas (vacío con pieza en 3 lados);
    other = (piezas, pieza): lo tapado que toca esas piezas pasa a ser de `pieza`."""
    holes = np.zeros_like(c.alpha)
    h, w = c.alpha.shape
    for group in _groups(~c.alpha, diagonal=False):
        if len(group) > largest or any(y in (0, h - 1) or x in (0, w - 1) for y, x in group):
            continue
        for y, x in group:
            holes[y, x] = True
    if notches:
        near = (_moved(c.alpha, -1, 0).astype(np.int8) + _moved(c.alpha, 1, 0) + _moved(c.alpha, 0, -1)
                + _moved(c.alpha, 0, 1))
        holes |= ~c.alpha & (near >= 3)
    if not holes.any():
        return 0
    masks = [(holes, part)]
    if other is not None:
        theirs = c.select(part=other[0])
        touching = holes & (_moved(theirs, -1, 0) | _moved(theirs, 1, 0) | _moved(theirs, 0, -1)
                            | _moved(theirs, 0, 1))
        masks = [(holes & ~touching, part), (touching, other[1])]
    px, py = c.project(0.5, 0.5, 0)
    for mask, owner in masks:
        if mask.any():
            c.stamp(np.where(c.crop(mask), index, -1), 0.5, 0.5, 0, ramp,
                    hot=(int(math.floor(px)), int(math.floor(py))), depth_bias=-8.0, part=owner)
    if not finish:
        c.no_finish(holes)
    return int(holes.sum())


def floor_shadow(c, shapes):
    """Sombra de un tono en el piso, recortada a la planta. shapes: ("disc", x, y, r, z0, z1) o
    ("bar", x0, y0, x1, y1, r, z0, z1); cada forma se corre SHADOW_SHIFT por cada 64 px de alto."""
    ys, xs = np.mgrid[0:c.height, 0:c.width]
    rx = xs + 0.5 - c.origin[0]
    ry = ys + 0.5 - c.origin[1]
    gu = (ry / 32.0 + rx / 64.0) / 2.0
    gv = (ry / 32.0 - rx / 64.0) / 2.0
    mask = np.zeros(gu.shape, dtype=bool)
    for shape in shapes:
        z0, z1 = shape[-2], shape[-1]
        for step in range(5):
            z = z0 + (z1 - z0) * step / 4.0
            su, sv = SHADOW_SHIFT[0] * z / 64.0, SHADOW_SHIFT[1] * z / 64.0
            if shape[0] == "disc":
                u, v = c.to_world(shape[1], shape[2])
                mask |= (gu - u - su) ** 2 + (gv - v - sv) ** 2 <= shape[3] * shape[3]
            else:
                ua, va = c.to_world(shape[1], shape[2])
                ub, vb = c.to_world(shape[3], shape[4])
                du, dv = ub - ua, vb - va
                along = np.clip(((gu - su - ua) * du + (gv - sv - va) * dv) / (du * du + dv * dv), 0.0, 1.0)
                mask |= ((gu - su - ua - du * along) ** 2 + (gv - sv - va - dv * along) ** 2
                         <= shape[5] * shape[5])
    w, d = c.world_size
    mask &= (gu >= 0) & (gu < w) & (gv >= 0) & (gv < d)
    rgba = np.zeros(mask.shape + (4,), dtype=np.uint8)
    rgba[mask, :3] = SHADOW_COLOR
    rgba[mask, 3] = 255
    return Image.fromarray(rgba, "RGBA")


def save_shadow(c, out_dir, name, shapes):
    return iso.save(floor_shadow(c, shapes), out_dir, name, kind="shadow", footprint=list(c.world_size),
                    anchor=list(c.anchor))


def chair_shadow(spec):
    """Sombra de base, asiento y respaldo (cambia con la rotación)."""
    bx0, bx1, by0, by1, bz0, bz1 = spec["back"]
    return [("disc", 0.5, 0.5, spec["star"] + 0.02, 0, 6),
            ("disc", 0.5, spec["seat_cy"], 0.25, spec["cushion"], spec["seat_top"]),
            ("bar", bx0 + 0.07, (by0 + by1) / 2.0, bx1 - 0.07, (by0 + by1) / 2.0, 0.08, bz0, bz1)]


def chair_canvas(spec, rotation, group=None):
    """La silla (o una sola de sus capas) con sus retoques, lista para guardar."""
    c = iso.Canvas.furniture(spec["item"]["size"], spec["item"]["height"], rotation)
    chair_model(c, spec, group)
    # Agujeros y muescas entre patas, bandeja y soporte: en sombra, cada uno con su capa.
    if group == "back":
        plug_holes(c, PLASTIC, pal.DEEP, "bracket", notches=True)
    else:
        plug_holes(c, PLASTIC, pal.DEEP, "pan", notches=True,
                   other=(BACK_PARTS, "bracket") if group is None else None)
    if group in (None, "seat"):
        c.no_finish(c.select(part="column"))
        # En r1 y r2 el brillo sigue por encima del soporte que asoma.
        edge_light(c, "seat", behind=None if rotation in BACK_ON_TOP else BACK_PARTS)
    if group in (None, "back"):
        # La placa del soporte lleva su arista de arriba en el tono base del plástico.
        plate = c.select(part="bracket") & (c.z > spec["bracket_top"] - 1.0)
        c.paint(plate, pal.BASE)
        c.no_finish(plate & ~c.edges()["silhouette"])
        edge_light(c, "back")
        if "left" in (c.face_side(iso.BACK), c.face_side(iso.FRONT)):
            crease_light(c, "back")
    tidy_finish(c)
    return c


def chair_layers(spec, c, rotation):
    """(asiento, respaldo): la capa de abajo entera y la de arriba con sus pixeles visibles."""
    full = np.array(c.image)
    back_seen = c.crop(c.select(part=BACK_PARTS))
    seat_seen = c.crop(c.alpha) & ~back_seen
    under, seen_under, seen_over = ("seat", seat_seen, back_seen) if rotation in BACK_ON_TOP else \
        ("back", back_seen, seat_seen)
    below = np.array(chair_canvas(spec, rotation, under).image)
    below[seen_under] = full[seen_under]
    above = full.copy()
    above[~seen_over] = 0
    below, above = Image.fromarray(below, "RGBA"), Image.fromarray(above, "RGBA")
    return (below, above) if under == "seat" else (above, below)


def check_chair(spec, c, rotation, seat, back):
    """Comprueba que las capas recompongan la silla, que el respaldo no baje de la planta ni salga del
    lienzo y que no queden agujeros encerrados."""
    full = np.array(c.image)
    seat_px, back_px = np.array(seat), np.array(back)
    lower, upper = (seat_px, back_px) if rotation in BACK_ON_TOP else (back_px, seat_px)
    joined = lower.copy()
    joined[upper[..., 3] > 0] = upper[upper[..., 3] > 0]
    problems = []
    if (joined != full).any():
        problems.append("las capas no recomponen la silla")
    alpha = c.crop(c.alpha)
    if c.clipped:
        problems.append("se sale del lienzo")
    ys, xs = np.nonzero(back_px[..., 3] > 0)
    floor = iso.footprint_mask(c.width, c.height, c.world_size)
    lowest = np.where(floor.any(axis=0), floor.shape[0] - 1 - np.argmax(floor[::-1], axis=0), -1)
    if (ys > lowest[xs]).any():
        problems.append("el respaldo baja de la planta")
    h, w = alpha.shape
    for group in _groups(~alpha, diagonal=False):
        if not any(y in (0, h - 1) or x in (0, w - 1) for y, x in group):
            problems.append("agujero encerrado de %d px en (%d, %d)" % (len(group), group[0][1], group[0][0]))
    if len(_groups(back_px[..., 3] > 0)) != 1 or len(_groups(seat_px[..., 3] > 0)) != 1:
        problems.append("una capa quedó en varios pedazos")
    if problems:
        raise RuntimeError("%s_r%d: %s" % (spec["name"], rotation, "; ".join(problems)))


def build_chair(out_dir, spec):
    files = []
    name = spec["name"]
    for rotation in range(4):
        c = chair_canvas(spec, rotation)
        files.append(iso.save(c, out_dir, "%s_r%d" % (name, rotation)))
        files.append(save_shadow(c, out_dir, "%s_r%d_shadow" % (name, rotation), chair_shadow(spec)))
        meta = {"footprint": list(c.world_size), "anchor": list(c.anchor), "rotation": rotation,
                "height": spec["item"]["height"]}
        seat, back = chair_layers(spec, c, rotation)
        check_chair(spec, c, rotation, seat, back)
        order = "over" if rotation in BACK_ON_TOP else "under"
        # Las capas van como mueble para check.py; lo demás lo revisa check_chair().
        files.append(iso.save(seat, out_dir, "%s_seat_r%d" % (name, rotation), kind="furniture", layer="seat",
                              layer_of="%s_r%d.png" % (name, rotation), curved=True, **meta))
        files.append(iso.save(back, out_dir, "%s_back_r%d" % (name, rotation), kind="furniture", layer="back",
                              layer_of="%s_r%d.png" % (name, rotation), draw=order + "_seat", curved=True, **meta))
    return files


# ---------------------------------------------------------------------- hojas

def _leaf_spine(c, base, azimuth, elevation, bend, length, twist=0.0, steps=40):
    """Nervio de una hoja en px del lienzo desde base (x, y, z): azimut y elevación en grados; se dobla
    `bend` y gira `twist` grados hasta la punta. length en px."""
    x, y, z = base
    points = [c.project(x, y, z)]
    step = length / float(steps)
    for i in range(steps):
        f = (i + 0.5) / steps
        turn = math.radians(azimuth + twist * f)
        angle = math.radians(elevation - bend * f)
        run = math.cos(angle) * step / iso.Z_METRIC
        x += math.cos(turn) * run
        y += math.sin(turn) * run
        z += math.sin(angle) * step
        points.append(c.project(x, y, z))
    return np.array(points, dtype=np.float64)


def _leaf_width(t, shape, lit_side):
    """Medio ancho relativo (0–1) a lo largo de la hoja (t: 0 tallo, 1 punta); las dos mitades difieren
    para que ningún borde quede recto."""
    stalk = 0.06  # tramo de tallito sin lámina
    body = np.clip((t - stalk) / (1.0 - stalk), 0.0, 1.0)
    if shape == "round":  # paleta de punta redonda
        power = np.where(lit_side, 0.74, 0.96)
        wide = np.sqrt(np.clip(1.0 - np.abs(2.0 * body ** power - 1.0) ** 2.4, 0.0, 1.0))
        wide = wide * np.where(lit_side, 1.0, 0.86)
    else:  # ovalada, más ancha cerca del tallo y de punta aguda
        power = np.where(lit_side, 0.60, 0.84)
        wide = np.sin(math.pi * body ** power) ** 0.62
        wide = wide * np.where(lit_side, 1.0, 0.84)
    return np.where(t < stalk, 0.0, wide)


def leaf_pattern(spine, half_width, tones, shape="oval"):
    """Hoja en pantalla en dos tonos partidos por el nervio, con borde de 1 px. spine = puntos del nervio
    en px; tones = (luz, sombra, nervio o None, borde con luz, borde en sombra).
    Devuelve (índices, x0, y0) con −1 = vacío."""
    lit, dark, rib, edge_lit, edge_dark = tones
    margin = int(math.ceil(half_width)) + 2
    x0 = int(math.floor(spine[:, 0].min())) - margin
    y0 = int(math.floor(spine[:, 1].min())) - margin
    x1 = int(math.ceil(spine[:, 0].max())) + margin
    y1 = int(math.ceil(spine[:, 1].max())) + margin
    ys, xs = np.mgrid[y0:y1, x0:x1]
    px = xs + 0.5
    py = ys + 0.5
    seg = np.sqrt((np.diff(spine, axis=0) ** 2).sum(axis=1))
    travel = np.concatenate([[0.0], np.cumsum(seg)])
    total = max(travel[-1], 1.0e-6)
    best = np.full(px.shape, 1.0e9)
    best_t = np.zeros(px.shape)
    best_side = np.zeros(px.shape)
    for i in range(len(spine) - 1):
        ax, ay = spine[i]
        bx, by = spine[i + 1]
        dx, dy = bx - ax, by - ay
        length2 = max(dx * dx + dy * dy, 1.0e-9)
        h = np.clip(((px - ax) * dx + (py - ay) * dy) / length2, 0.0, 1.0)
        ox = px - (ax + dx * h)
        oy = py - (ay + dy * h)
        dist = np.sqrt(ox * ox + oy * oy)
        # Lado del nervio que mira a la luz (arriba a la izquierda de la pantalla).
        nx, ny = -dy, dx
        if nx * -0.45 + ny * -0.9 < 0:
            nx, ny = -nx, -ny
        side = ox * nx + oy * ny
        closer = dist < best
        best = np.where(closer, dist, best)
        best_t = np.where(closer, (travel[i] + seg[i] * h) / total, best_t)
        best_side = np.where(closer, side, best_side)
    lit_side = best_side >= 0.0
    width = half_width * _leaf_width(best_t, shape, lit_side)
    inside = _no_pimples(_tidy(best <= np.maximum(width, 0.75)))
    index = np.where(lit_side, lit, dark).astype(np.int16)
    if rib is not None:
        index = np.where((best < 0.75) & (best_t < 0.86) & (width > 2.0), rib, index)
    padded = np.pad(inside, 1, mode="constant")
    core = padded[:-2, 1:-1] & padded[2:, 1:-1] & padded[1:-1, :-2] & padded[1:-1, 2:]
    border = inside & ~core
    index = np.where(border, np.where(lit_side, edge_lit, edge_dark), index)
    index = np.where(inside, index, -1)
    return index, x0, y0


def _tidy(mask):
    """Quita los pixeles sueltos (sin vecino arriba, abajo ni a los lados)."""
    padded = np.pad(mask, 1, mode="constant")
    near = (padded[:-2, 1:-1].astype(np.int8) + padded[2:, 1:-1] + padded[1:-1, :-2] + padded[1:-1, 2:])
    return mask & (near >= 1)


def _no_pimples(mask):
    """Quita el pixel que sobresale solo de un borde recto de 5 px o más; las puntas finas se quedan."""
    padded = np.pad(mask, 3, mode="constant")
    h, w = mask.shape

    def at(dy, dx):
        return padded[3 + dy:3 + dy + h, 3 + dx:3 + dx + w]

    out = mask.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        # El único vecino está en (dy, dx); el borde recto corre de lado a lado de ese vecino.
        alone = mask & at(dy, dx) & ~at(-dy, -dx) & ~at(dx, dy) & ~at(-dx, -dy)
        flat = at(dy + dx, dx + dy) & at(dy - dx, dx - dy) & at(dy + 2 * dx, dx + 2 * dy) & at(dy - 2 * dx, dx - 2 * dy)
        out &= ~(alone & flat)
    return out


def _leaf_depth(c, leaf):
    """Profundidad (como la mide el motor) del punto medio de una hoja: para ordenarlas."""
    ax, ay = math.cos(math.radians(leaf["azimuth"])), math.sin(math.radians(leaf["azimuth"]))
    angle = math.radians(leaf["elevation"] - leaf["bend"] * 0.3)
    reach = leaf["length"] * 0.6
    x = leaf["base"][0] + ax * math.cos(angle) * reach / iso.Z_METRIC
    y = leaf["base"][1] + ay * math.cos(angle) * reach / iso.Z_METRIC
    z = leaf["base"][2] + math.sin(angle) * reach
    u, v = c.to_world(x, y)
    return u + v + z / 64.0


def add_leaves(c, ramp, leaves, pivot, name="leaves"):
    """Pone las hojas como sellos, de la más lejana a la más cercana, con la profundidad de pivot más un
    escalón por hoja (delante de maceta y tronco). Los sellos no giran."""
    order = sorted(leaves, key=lambda leaf: _leaf_depth(c, leaf))
    px, py = c.project(*pivot)
    px, py = int(math.floor(px)), int(math.floor(py))
    for rank, leaf in enumerate(order):
        spine = _leaf_spine(c, leaf["base"], leaf["azimuth"], leaf["elevation"], leaf["bend"], leaf["length"],
                            leaf.get("twist", 0.0))
        grid, x0, y0 = leaf_pattern(spine, leaf["width"], leaf["tones"], leaf.get("shape", "oval"))
        c.stamp(grid, pivot[0], pivot[1], pivot[2], ramp, hot=(px - x0, py - y0), depth_bias=1.0 + 0.01 * rank,
                name=name)


# Tonos (luz, sombra, nervio, borde con luz, borde en sombra); el borde en contorno oscuro separa
# cada hoja de las de atrás.
TONES_TOP = (pal.LIGHT, pal.BASE, None, pal.OUTLINE, pal.OUTLINE)
TONES_LIT = (pal.BASE, pal.LEFT, pal.LIGHT, pal.OUTLINE, pal.OUTLINE)
TONES_DIM = (pal.LEFT, pal.RIGHT, pal.BASE, pal.OUTLINE, pal.OUTLINE)
TONES_DARK = (pal.RIGHT, pal.DEEP, pal.LEFT, pal.OUTLINE, pal.OUTLINE)


def _leaf_tones(azimuth, level):
    """Tonos de una hoja según hacia dónde apunta (la luz viene de −x, +y del modelo) y su
    nivel (0 = abajo … 2 = arriba)."""
    ax, ay = math.cos(math.radians(azimuth)), math.sin(math.radians(azimuth))
    score = level * 0.95 + (-0.55 * ax + 0.83 * ay) * 0.8 - 0.1
    if score >= 2.0:
        return TONES_TOP
    if score >= 0.8:
        return TONES_LIT
    if score >= -0.4:
        return TONES_DIM
    return TONES_DARK


def fill_gaps(c, ramp, index, part="leaves", largest=10):
    """Los huecos chicos encerrados entre hojas se verían como motas del piso: van en sombra."""
    return plug_holes(c, ramp, index, part, largest)


# ---------------------------------------------------------------------- macetas

# Maceta torneada: límites relativos al radio de cada fila, así las franjas siguen la conicidad.
POT_BANDS = ((-0.74, pal.LEFT), (-0.40, pal.BASE), (0.10, pal.LEFT), (0.78, pal.RIGHT), (9.0, pal.DEEP))
LIP_WIDTH = 2 / 64.0  # grosor del labio visto desde arriba


def _plane_point(c, z):
    """Punto del mundo (u, v) que cae en cada pixel del lienzo sobre el plano horizontal z."""
    rx = c.X + 0.5 - c.origin[0]
    ry = c.Y + 0.5 - c.origin[1]
    return ((ry / 32.0 + rx / 64.0) / 2.0 + z / 64.0, (ry / 32.0 - rx / 64.0) / 2.0 + z / 64.0)


def pot(c, radius_bottom, radius_top, height, lip=5, saucer=False, covered=False, ramp=None, band=None):
    """Maceta con labio y tierra, centrada en la casilla. Radios en casillas.
    covered = la mata tapa la boca: el labio entero queda en la sombra de las hojas.
    ramp = material (barro por defecto); band = (z0, z1, rampa): franja de otro color."""
    ramp = ramp or CLAY
    cx, cy = 0.5, 0.5
    z0 = 0
    if saucer:
        c.cylinder(cx, cy, radius_bottom + 4 / 64, 0, 3, ramp, radius_top=radius_bottom + 6 / 64, bands=POT_BANDS,
                   name="saucer")
        z0 = 2
    c.cylinder(cx, cy, radius_bottom, z0, height - lip + 1, ramp, radius_top=radius_top, cap=False, bands=POT_BANDS,
               name="pot")
    rim = radius_top + 1 / 64
    c.cylinder(cx, cy, rim, height - lip, height, ramp, open_top=True, bands=POT_BANDS, name="rim")
    mouth = c.select(part="rim")
    if not covered:
        c.cylinder(cx, cy, rim - LIP_WIDTH, height - 4, height - 3, SOIL, name="soil", outline=False)
        mouth = c.select(part="rim") | c.select(part="soil")
    u, v = _plane_point(c, height)
    du, dv = u - cx, v - cy
    reach = np.sqrt(du * du + dv * dv)
    ring = mouth & (reach <= rim) & (reach > rim - LIP_WIDTH)
    c.paint(ring, pal.BASE, ramp=ramp)
    outline = c.edges()["silhouette"]
    if not covered:
        lit = ring & ~outline & (_moved(outline, -1, 0) | _moved(outline, 0, -1))
        lit &= (du - dv < -0.25 * rim) & (du + dv < 0)
        c.paint(_long_runs(lit, 6), pal.LIGHT, ramp=ramp)
    c.no_finish(ring & ~outline)
    if not covered:
        soil = c.select(part="soil") & ~ring
        c.no_finish(soil)
        inner = rim - LIP_WIDTH
        shade = (c.u - cx - 0.035) ** 2 + (c.v - cy + 0.05) ** 2 > inner * inner
        c.paint(soil & shade, pal.LEFT)
    if band is not None:
        # Franja pintada: los mismos tonos de la maceta, en la rampa de la franja.
        stripe = c.select(part="pot") & (c.z >= band[0]) & (c.z < band[1])
        c.paint(stripe, c.shade, ramp=band[2])
    shadow = c.select(part="pot") & (c.z > height - lip - 3.2)
    if covered:
        shadow |= c.select(part="rim")
    c.paint(shadow, np.maximum(pal.darker(c.shade), pal.DEEP))
    plug_holes(c, ramp, pal.DEEP if covered else pal.BASE, "rim", finish=False)


def thick_outline(c, width=2):
    """Contorno de `width` px (la planta chica se achica al 60 % y 1 px se perdería)."""
    c.finish(**c._finish_options)
    solid = c.alpha
    edge = np.zeros_like(solid)
    for dy in range(-width + 1, width):
        for dx in range(-width + 1, width):
            if abs(dy) + abs(dx) < width:
                edge |= ~_moved(solid, dy, dx)
    ring = solid & edge
    c.paint(ring, pal.OUTLINE)
    c.no_finish(ring)


# ---------------------------------------------------------------------- plantas

# Anillos de la planta chica: (hojas, elevación, caída, largo, ancho, nivel, giro, torsión).
SMALL_RINGS = ((5, 14, 50, 31, 10.5, 0, 20, 12), (5, 46, 48, 29, 10.0, 1, 56, -12), (3, 80, 46, 25, 9.0, 2, 10, 10))


def small_plant(c, scale=1.0, rings=SMALL_RINGS):
    """Mata de hojas anchas en tres pisos sobre maceta de barro; scale achica todo (versión a tamaño final)."""
    s = scale
    pot(c, 10 / 64 * s, 14 / 64 * s, 22 * s, lip=max(3, int(round(5 * s))), covered=True)
    top = 22 * s
    crown = (0.5, 0.5, top + 1)
    # Corazón de la mata: tapa la boca de la maceta con verde en sombra (no se ve la tierra).
    c.ellipsoid(0.5, 0.5, top + 1, 12 / 64 * s, 12 / 64 * s, 7 * s, LEAVES,
                bands=((0.80, pal.RIGHT), (-9.0, pal.DEEP)), clip_z=(top, top + 20 * s), name="leaves", shadow=False)
    leaves = []
    for count, elevation, bend, length, width, level, turn, twist in rings:
        for k in range(count):
            azimuth = turn + 360.0 * k / count
            leaves.append({"base": crown, "azimuth": azimuth, "elevation": elevation, "bend": bend,
                           "length": length * s, "width": max(width * s, 4.0), "tones": _leaf_tones(azimuth, level),
                           "shape": "round", "twist": twist if k % 2 else -twist})
    add_leaves(c, LEAVES, leaves, crown)
    fill_gaps(c, LEAVES, pal.OUTLINE)


# Retoques por hoja de la planta grande (número de hoja -> cambios).
LARGE_TWEAKS = {9: {"bend": 24, "elevation": -12, "twist": -20}, 6: {"bend": 16, "elevation": 6},
                12: {"elevation": -8, "bend": 8}}


def large_plant(c):
    """Arbolito de hojas grandes en racimos, en maceta blanca de franja roja con plato."""
    pot(c, 8 / 64, 12 / 64, 28, lip=6, saucer=True, ramp=CERAMIC, band=(9, 15, POT_RED))
    cx, cy = 0.5, 0.5
    top = 62
    c.capsule((cx, cy, 24), (cx, cy, 42), 1.8, SOIL, bands=((0.25, pal.LIGHT), (-9.0, pal.LEFT)), name="stem",
              shadow=False, outline=False)
    leaves = []
    count = 13
    for k in range(count):
        f = k / float(count - 1)
        z = 38 + (top - 38) * f
        azimuth = 200 + 137.5 * k
        elevation = 18 + 56 * f
        level = 0 if f < 0.3 else (1 if f < 0.7 else 2)
        leaf = {"base": (cx, cy, z), "azimuth": azimuth, "elevation": elevation, "bend": 80 - 44 * f,
                "length": 32 - 9 * f, "width": 10.5 - 2.5 * f, "tones": _leaf_tones(azimuth, level),
                "shape": "oval", "twist": 22 if k % 2 else -22}
        for key, change in LARGE_TWEAKS.get(k, {}).items():
            leaf[key] += change
        leaves.append(leaf)
    add_leaves(c, LEAVES, leaves, (cx, cy, 56))
    fill_gaps(c, LEAVES, pal.OUTLINE)


def build_plants(out_dir):
    files = []
    c = iso.Canvas.tile(height=SMALL_ITEM["height"])
    small_plant(c)
    c.style_part("leaves", rim="none")
    c.finish(occlusion=False)
    tidy_finish(c)
    thick_outline(c, 2)
    files.append(iso.save(c, out_dir, "plant_small"))
    files.append(save_shadow(c, out_dir, "plant_small_shadow",
                             [("disc", 0.5, 0.5, 0.20, 0, 0), ("disc", 0.5, 0.5, 0.26, 30, 40)]))
    # A tamaño final (60 %): el mismo diseño redibujado chico, con 1 px de contorno.
    c = iso.Canvas.tile(height=SMALL_ITEM["height"])
    small_plant(c, 0.6, rings=((5, 14, 50, 31, 11.0, 0, 20, 12), (4, 48, 48, 29, 10.5, 1, 56, -12),
                               (2, 82, 46, 25, 10.0, 2, 10, 10)))
    c.style_part("leaves", rim="none")
    c.finish(occlusion=False)
    tidy_finish(c)
    files.append(iso.save(c, out_dir, "plant_small_q"))
    files.append(save_shadow(c, out_dir, "plant_small_q_shadow",
                             [("disc", 0.5, 0.5, 0.12, 0, 0), ("disc", 0.5, 0.5, 0.16, 18, 24)]))
    c = iso.Canvas.furniture(LARGE_ITEM["size"], LARGE_ITEM["height"])
    large_plant(c)
    c.style_part("leaves", rim="none")
    c.finish(occlusion=False)
    tidy_finish(c)
    files.append(iso.save(c, out_dir, "plant_large"))
    files.append(save_shadow(c, out_dir, "plant_large_shadow",
                             [("disc", 0.5, 0.5, 0.22, 0, 0), ("disc", 0.5, 0.5, 0.26, 50, 70)]))
    return files


# ---------------------------------------------------------------------- hojas de revisión

def _load(out_dir, name):
    path = sheet.find(out_dir, name)
    return sheet.load(path) if path else None


def build_sheets(out_dir):
    """Hoja de contacto en _sheets/chair_plant.png: piezas sueltas y una escena con escritorios."""
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    info = sheet.manifest(out_dir)
    tiles = [t for t in (_load(out_dir, "floor_ceramic_%d.png" % i) for i in range(4)) if t is not None]
    if not tiles:
        tiles = [sheet.plain_tile()]
    scene = sheet.Scene(7, 6, top=100, margin=12)
    scene.fill_floor(tiles, seed=4)

    def put(name, x, y):
        image = _load(out_dir, name + ".png")
        if image is None:
            return
        entry = info.get(name + ".png", {})
        anchor = entry.get("anchor") or (64, image.size[1] - 32)
        size = entry.get("footprint") or (1, 1)
        shadow = _load(out_dir, name + "_shadow.png")
        if shadow is not None:
            scene.add_shadow(shadow, x, y, anchor=anchor, opacity=0.3)
        scene.add(image, x, y, anchor=anchor, size=size)

    # Cada escritorio con su silla en la casilla de su frente, mirándolo (rotación opuesta).
    for rotation, desk, chair in ((1, (2, 1), (3, 1)), (2, (5, 0), (5, 1)), (3, (5, 3), (4, 3)), (0, (1, 4), (1, 3))):
        put("desk_simple_r%d" % rotation, desk[0], desk[1])
        put("chair_basic_r%d" % ((rotation + 2) % 4), chair[0], chair[1])
    put("chair_ergonomic_r1", 3, 5)
    put("chair_ergonomic_r2", 5, 5)
    put("chair_ergonomic_r0", 2, 3)
    for name, cell in (("plant_large", (0, 0)), ("plant_small", (3, 0)), ("plant_small", (0, 2)),
                       ("plant_large", (6, 3)), ("plant_small", (3, 3)), ("plant_large", (0, 5)),
                       ("plant_small", (6, 0))):
        put(name, cell[0], cell[1])
    person = _load(out_dir, "character_stand_r2.png")
    if person is not None:
        scene.add(person, 2, 2, anchor=(64, 112))
    view = scene.render(scale=3)
    names = []
    for chair in ("chair_basic", "chair_ergonomic"):
        names += (["%s_r%d" % (chair, r) for r in range(4)] + ["%s_seat_r%d" % (chair, r) for r in range(4)]
                  + ["%s_back_r%d" % (chair, r) for r in range(4)])
    names += ["plant_small", "plant_small_q", "plant_large"]
    parts = sheet.contact_sheet([(n, _load(out_dir, n + ".png")) for n in names], columns=4, scale=3)
    width = max(view.size[0], parts.size[0])
    page = Image.new("RGBA", (width, view.size[1] + parts.size[1]), sheet.BACKGROUND + (255,))
    page.alpha_composite(view, ((width - view.size[0]) // 2, 0))
    page.alpha_composite(parts, ((width - parts.size[0]) // 2, view.size[1]))
    page.save(os.path.join(folder, "chair_plant.png"))


def build(out_dir):
    files = build_chair(out_dir, BASIC) + build_chair(out_dir, ERGO) + build_plants(out_dir)
    build_sheets(out_dir)
    return files
