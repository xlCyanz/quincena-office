#!/usr/bin/env python3
# Verificador de la lista de revisión de docs/sprites_128.md (sección 11).
#
#   python3 tools/sprites/check.py DIR [--verbose] [--group grupo[,grupo]]
#
# Revisa todos los PNG de DIR (menos los que empiezan con sheet_, scene_, preview_ o _) y lee
# los manifest*.json que escribe generate.py. Imprime los fallos y avisos y al final
# «RESULTADO: OK» o «RESULTADO: FALLA». Sale con código 0 o 1.
#
# Qué comprueba:
#   todos       PNG RGBA de 8 bits, alfa solo 0/255, cantidad de colores (aviso), lienzo según
#               la guía, que nada quede recortado, y que el manifiesto coincida con el PNG
#   pisos       rombo exacto de 4,096 px, prueba de desplazar ±64/±32 sin huecos ni encimados,
#               4 variantes con el mismo borde, sin costura medible en las 16 parejas × 2 ejes,
#               mismo brillo medio (BRIGHTNESS_TOLERANCE)
#   muebles     apoyo en el centro del rombo de la casilla de anclaje, nada por debajo de la
#               planta, la pieza llega al piso, caras lisas con los tonos exactos base / −25 % /
#               −40 % que declara el manifiesto (o, en una rampa con caras declaradas de STYLE.md,
#               los tonos de "faces" con la luz arriba a la izquierda), escalera 2:1 abajo (aviso)
#   paredes     lienzo 72×160 / 72×64, apoyo, empalme con el tramo vecino sin hueco ni línea, y
#               la baja con la misma cara de arriba que la alta
import argparse
import glob
import json
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import iso  # noqa: E402
import palette as pal  # noqa: E402

# Tolerancias (explícitas, en unidades de 0 a 255).
BRIGHTNESS_TOLERANCE = 0.25  # diferencia máxima de brillo medio entre variantes de un piso
CHANNEL_TOLERANCE = 0.5  # ídem por canal R, G, B
SEAM_FACTOR = 1.25  # la costura puede contrastar hasta esto × la línea interior más marcada…
SEAM_TOLERANCE = 1.0  # … más esto
JUMP_WIDTHS = (4, 12)  # anchos de banda (líneas de la rejilla) para medir el salto de color en la costura
JUMP_TOLERANCE = 1.5  # el salto puede pasar del mayor salto interior × SEAM_FACTOR en esto
MAX_FLOOR_COLORS = 16
MIN_FLAT_SHARE = 0.5  # parte mínima de cada lado liso de una rampa que debe quedar en su tono exacto
MIN_FACE_PIXELS = 24  # lados con menos pixeles visibles que esto no se miden (tiradores, patas finas)
MAX_LOOSE_PIXELS = 0.04  # fracción de pixeles sin vecino de su color a partir de la que se avisa (pisos)
WALL_HEIGHT_TOLERANCE = 2  # px de sprite de margen en el alto medido de una pared
MAX_SPRITE_COLORS = 32
VARIANTS = 4
SKIP_PREFIXES = ("sheet_", "scene_", "preview_", "_")
WALL_HEIGHTS = {"wall": 60, "door": 46, "window": 60, "glass_door": 50}  # px del mundo


class Report(object):
    def __init__(self, verbose=False):
        self.failures = []
        self.warnings = []
        self.passed = 0
        self.verbose = verbose

    def check(self, name, ok, message):
        if ok:
            self.passed += 1
            if self.verbose:
                print("OK     %s: %s" % (name, message))
        else:
            self.failures.append("%s: %s" % (name, message))
            print("FALLA  %s: %s" % (name, message))
        return ok

    def warn(self, name, message):
        self.warnings.append("%s: %s" % (name, message))
        print("AVISO  %s: %s" % (name, message))


def _lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def load_manifests(directory, groups=None):
    """Entradas de los manifest*.json de la carpeta (archivo -> datos). Con groups, solo las de
    esos grupos (manifest_<grupo>.json)."""
    entries = {}
    for path in sorted(glob.glob(os.path.join(directory, "manifest*.json"))):
        try:
            with open(path, "r") as handle:
                data = json.load(handle)
        except (IOError, ValueError):
            continue
        if groups is not None and data.get("group") not in groups:
            continue
        for entry in data.get("sprites", []):
            entries[entry["file"]] = entry
    return entries


def guess_kind(name):
    return iso.guess_kind(name)


# ---------------------------------------------------------------------- comprobaciones comunes

def check_common(report, name, image, arr, entry, kind):
    ok = report.check(name, image.mode == "RGBA", "PNG RGBA (modo %s)" % image.mode)
    if not ok:
        return False
    alpha = arr[..., 3]
    values = set(np.unique(alpha).tolist())
    report.check(name, values <= {0, 255}, "alfa solo 0/255 (hay %s)" % sorted(values - {0, 255})[:5])
    opaque = alpha == 255
    report.check(name, opaque.any(), "tiene pixeles opacos")
    report.check(name, re.match(r"^[a-z][a-z0-9_]*\.png$", name) is not None,
                 "nombre en inglés y snake_case (minúsculas, números y _)")
    if kind != "shadow":
        black = int((opaque & (arr[..., :3] == 0).all(axis=2)).sum())
        report.check(name, black == 0, "sin negro puro (el contorno es un tono oscuro del mismo color): %d px" % black)
    colors = len(np.unique(arr[opaque][:, :3], axis=0)) if opaque.any() else 0
    limit = MAX_FLOOR_COLORS if kind == "floor" else MAX_SPRITE_COLORS
    if colors > limit:
        report.warn(name, "%d colores (más de %d)" % (colors, limit))
    if entry is not None:
        canvas = entry.get("canvas")
        if canvas is not None:
            report.check(name, list(canvas) == [arr.shape[1], arr.shape[0]],
                         "el lienzo del manifiesto %s es el del PNG %dx%d" % (canvas, arr.shape[1], arr.shape[0]))
        report.check(name, not entry.get("clipped", False), "nada se sale del lienzo (el motor marcó recorte)")
        off_grid = entry.get("off_grid") or []
        report.check(name, not off_grid,
                     "cajas en la rejilla (x, y múltiplos de 1/64 de casilla, z entero) para que sus aristas "
                     "salgan 2:1: %d fuera (%s)" % (len(off_grid), ", ".join(str(n) for n in off_grid[:6])))
    flat = bool((entry or {}).get("flat", False))
    if kind not in ("floor", "overlay", "shadow") and not flat and (entry is None or "clipped" not in entry):
        # Sin el dato de recorte del motor solo se puede sospechar por los bordes del lienzo.
        if opaque[0].any() or opaque[:, 0].any() or opaque[:, -1].any():
            report.warn(name, "toca un borde del lienzo y no hay manifiesto del motor para saber si es un recorte")
    return True


def bottom_runs(alpha, top=False):
    """Tramos irregulares de la escalera del borde de abajo (o del de arriba, con top=True):
    largos distintos de 2 entre dos escalones de ±1 en el mismo sentido."""
    height, width = alpha.shape
    bottom = np.full(width, -1)
    cols = np.nonzero(alpha.any(axis=0))[0]
    for x in cols:
        rows = np.nonzero(alpha[:, x])[0]
        bottom[x] = np.min(rows) if top else np.max(rows)
    bad = 0
    x = 0
    runs = []
    while x < width:
        if bottom[x] < 0:
            x += 1
            continue
        start = x
        while x + 1 < width and bottom[x + 1] == bottom[start]:
            x += 1
        runs.append((start, x))
        x += 1
    for index in range(1, len(runs) - 1):
        start, end = runs[index]
        prev_end = runs[index - 1][1]
        next_start = runs[index + 1][0]
        if prev_end != start - 1 or next_start != end + 1:
            continue
        step_in = bottom[start] - bottom[prev_end]
        step_out = bottom[next_start] - bottom[end]
        if abs(step_in) == 1 and step_in == step_out and (end - start + 1) != 2:
            bad += 1
    return bad


# ---------------------------------------------------------------------- pisos

def tile_region(arr):
    """Los 128×64 del rombo de un piso (el lienzo puede ser 128×128 con la mitad de arriba vacía)."""
    return arr[arr.shape[0] - 64:, :, :]


def check_floor(report, name, arr):
    size_ok = arr.shape[1] == 128 and arr.shape[0] in (64, 128)
    if not report.check(name, size_ok, "lienzo de piso 128×128 o 128×64 (es %dx%d)" % (arr.shape[1], arr.shape[0])):
        return False
    alpha = arr[..., 3] == 255
    rhombus = iso.rhombus_mask(128, arr.shape[0])
    count = int(alpha.sum())
    exact = report.check(name, bool(np.array_equal(alpha, rhombus)) and count == 4096,
                         "rombo exacto de 4,096 px (tiene %d, %d fuera de lugar)" % (count, int((alpha ^ rhombus).sum())))
    tile = tile_region(arr)[..., 3] == 255
    big = np.zeros((64 * 3, 128 * 3), dtype=np.int32)
    for dx, dy in ((0, 0), (64, 32), (-64, 32), (64, -32), (-64, -32), (128, 0), (-128, 0), (0, 64), (0, -64)):
        big[64 + dy:128 + dy, 128 + dx:256 + dx] += tile
    window = big[64:128, 128:256]
    report.check(name, int(window.min()) == 1 and int(window.max()) == 1,
                 "desplazar ±64/±32: sin huecos (%d) ni encimados (%d)" % (int((window == 0).sum()), int((window > 1).sum())))
    if exact:
        loose = loose_pixels(tile_region(arr))
        if loose > MAX_LOOSE_PIXELS:
            report.warn(name, "%.1f %% de pixeles sueltos (sin ningún vecino de su color, contando la casilla "
                              "repetida): la guía pide bloques y tramas ordenadas, no ruido de 1 px (aviso desde %.0f %%)"
                        % (loose * 100.0, MAX_LOOSE_PIXELS * 100.0))
    return exact


def loose_pixels(tile):
    """Fracción de pixeles del rombo (128×64) que no tienen ningún vecino (4 direcciones) de su
    mismo color. Los vecinos de fuera del rombo son los de la misma casilla repetida."""
    mask = tile[..., 3] == 255
    big = np.zeros((64 * 3, 128 * 3, 3), dtype=np.int32) - 1
    for dx, dy in ((0, 0), (64, 32), (-64, 32), (64, -32), (-64, -32)):
        region = big[64 + dy:128 + dy, 128 + dx:256 + dx]
        region[mask] = tile[mask][:, :3]
    centre = big[64:128, 128:256]
    same = np.zeros(mask.shape, dtype=bool)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        same |= (big[64 + dy:128 + dy, 128 + dx:256 + dx] == centre).all(axis=2)
    return float((mask & ~same).sum()) / max(int(mask.sum()), 1)


def _lattice(height, width, origin_x, origin_y):
    ys, xs = np.mgrid[0:height, 0:width]
    rx = xs + 0.5 - origin_x
    ry = ys + 0.5 - origin_y
    return np.floor(ry + rx / 2.0).astype(np.int64), np.floor(ry - rx / 2.0).astype(np.int64)


def seam_contrast(tile_a, tile_b, axis):
    """Contraste medio (0–255) entre pixeles vecinos a cada lado de la costura de A con B puesta
    en su lado +u (axis 'u', abajo-derecha) o +v (abajo-izquierda), y el mayor contraste de las
    líneas paralelas interiores de las dos casillas. Devuelve (costura, mayor interior)."""
    canvas = np.zeros((96, 192, 4), dtype=np.float64)
    ax = 0 if axis == "u" else 64
    bx = 64 if axis == "u" else 0
    for tile, px, py in ((tile_a, ax, 0), (tile_b, bx, 32)):
        region = canvas[py:py + 64, px:px + 128]
        m = tile[..., 3] == 255
        region[m] = tile[m]
    iu, iv = _lattice(96, 192, ax + 64, 0)
    line = iu if axis == "u" else iv
    opaque = canvas[..., 3] == 255
    diff = np.abs(canvas[1:, :, :3] - canvas[:-1, :, :3]).mean(axis=2)
    valid = opaque[1:] & opaque[:-1]
    lines = line[1:]
    sums = np.bincount(lines[valid].ravel() - lines.min(), weights=diff[valid].ravel(), minlength=256)
    counts = np.bincount(lines[valid].ravel() - lines.min(), minlength=256)
    offset = -int(lines.min())
    with np.errstate(invalid="ignore", divide="ignore"):
        means = np.where(counts > 0, sums / np.maximum(counts, 1), 0.0)
    seam = float(means[64 + offset])
    inner = [float(means[k + offset]) for k in range(2, 127) if k != 64 and counts[k + offset] >= 16]
    return seam, (max(inner) if inner else 0.0)


def seam_jump(tile_a, tile_b, axis, width):
    """Salto de color medio (0–255) entre las `width` líneas de antes y de después de la costura
    de A con B (como en seam_contrast), y el mayor salto entre bandas vecinas del mismo ancho en
    el interior. Detecta lo que no se repite (un degradado, una mancha cortada) aunque el borde
    sea una junta. Devuelve (salto en la costura, mayor salto interior)."""
    canvas = np.zeros((96, 192, 4), dtype=np.float64)
    ax = 0 if axis == "u" else 64
    bx = 64 if axis == "u" else 0
    for tile, px, py in ((tile_a, ax, 0), (tile_b, bx, 32)):
        region = canvas[py:py + 64, px:px + 128]
        m = tile[..., 3] == 255
        region[m] = tile[m]
    iu, iv = _lattice(96, 192, ax + 64, 0)
    line = iu if axis == "u" else iv
    opaque = (canvas[..., 3] == 255) & (line >= 0) & (line < 128)
    counts = np.bincount(line[opaque], minlength=128).astype(np.float64)
    means = np.zeros((128, 3))
    for channel in range(3):
        sums = np.bincount(line[opaque], weights=canvas[..., channel][opaque], minlength=128)
        means[:, channel] = sums / np.maximum(counts, 1.0)

    def jump(k):
        return float(np.abs(means[k - width:k].mean(axis=0) - means[k:k + width].mean(axis=0)).mean())

    inner = [jump(k) for k in list(range(width, 64 - width + 1)) + list(range(64 + width, 128 - width + 1))]
    return jump(64), (max(inner) if inner else 0.0)


def check_floor_group(report, material, names, arrays):
    label = material + "_*"
    indices = sorted(names)
    if len(indices) != VARIANTS or indices != list(range(VARIANTS)):
        report.warn(label, "se esperaban las variantes _0 a _%d y hay %s" % (VARIANTS - 1, indices))
    tiles = [tile_region(arrays[i]).astype(np.float64) for i in indices]
    iu, iv = _lattice(64, 128, 64, 0)
    mask = iso.rhombus_mask(128, 64)
    ring = mask & ((iu == 0) | (iu == 63) | (iv == 0) | (iv == 63))
    first = tiles[0][ring][:, :3]
    same = all(np.array_equal(first, t[ring][:, :3]) for t in tiles[1:])
    report.check(label, same, "mismo borde (anillo de la casilla) en todas las variantes")
    worst = (0.0, 0.0, "")
    failed = []
    for a, tile_a in zip(indices, tiles):
        for b, tile_b in zip(indices, tiles):
            for axis in ("u", "v"):
                seam, inner = seam_contrast(tile_a, tile_b, axis)
                if seam - inner > worst[0] - worst[1] or not worst[2]:
                    worst = (seam, inner, "_%d|_%d eje %s" % (a, b, axis))
                if seam > inner * SEAM_FACTOR + SEAM_TOLERANCE:
                    failed.append("_%d|_%d eje %s (costura %.2f, interior %.2f)" % (a, b, axis, seam, inner))
    report.check(label, not failed,
                 "sin costura medible en las %d parejas × 2 ejes (peor: %s costura %.2f, interior %.2f)%s"
                 % (len(indices) ** 2, worst[2], worst[0], worst[1], "; " + ", ".join(failed[:4]) if failed else ""))
    worst = (0.0, 0.0, "")
    failed = []
    for a, tile_a in zip(indices, tiles):
        for b, tile_b in zip(indices, tiles):
            for axis in ("u", "v"):
                for width in JUMP_WIDTHS:
                    seam, inner = seam_jump(tile_a, tile_b, axis, width)
                    if seam - inner > worst[0] - worst[1] or not worst[2]:
                        worst = (seam, inner, "_%d|_%d eje %s, bandas de %d" % (a, b, axis, width))
                    if seam > inner * SEAM_FACTOR + JUMP_TOLERANCE:
                        failed.append("_%d|_%d eje %s bandas de %d (salto %.2f, interior %.2f)"
                                      % (a, b, axis, width, seam, inner))
    report.check(label, not failed,
                 "sin salto de color al cruzar la costura (el dibujo se repite): peor %s salto %.2f, interior %.2f%s"
                 % (worst[2], worst[0], worst[1], "; " + ", ".join(failed[:4]) if failed else ""))
    lums = [float(_lum(t[mask][:, :3]).mean()) for t in tiles]
    spread = max(lums) - min(lums)
    report.check(label, spread <= BRIGHTNESS_TOLERANCE,
                 "mismo brillo medio: diferencia %.3f (tolerancia %.2f; %s)"
                 % (spread, BRIGHTNESS_TOLERANCE, " ".join("%.2f" % v for v in lums)))
    channels = np.array([t[mask][:, :3].mean(axis=0) for t in tiles])
    channel_spread = float((channels.max(axis=0) - channels.min(axis=0)).max())
    report.check(label, channel_spread <= CHANNEL_TOLERANCE,
                 "mismo color medio por canal: diferencia %.3f (tolerancia %.2f)" % (channel_spread, CHANNEL_TOLERANCE))


# ---------------------------------------------------------------------- muebles y demás

def _ground_coords(height, width, origin):
    ys, xs = np.mgrid[0:height, 0:width]
    rx = xs + 0.5 - origin[0]
    ry = ys + 0.5 - origin[1]
    return (ry / 32.0 + rx / 64.0) / 2.0, (ry / 32.0 - rx / 64.0) / 2.0


def check_flat_faces(report, name, arr, entry):
    faces = entry.get("flat_faces") or []
    opaque = arr[..., 3] == 255
    rgb = arr[..., :3]
    for face in faces:
        expected = pal.face_colors(face["base"])
        labels = {"top": "base", "left": "−25 %", "right": "−40 %"}
        declared_faces = face.get("faces") if face.get("declared") else None
        if declared_faces:
            # Rampa de STYLE.md con lado y sombra propios (palette.style_ramp(side=, shadow=)): se
            # exigen los tonos que declara el manifiesto en vez del −25 / −40 calculado, siempre
            # que la luz siga arriba a la izquierda (brillo de arriba > izquierda ≥ derecha).
            expected = dict((k, pal.hex_to_rgb(v)) for k, v in declared_faces.items())
            labels = {"top": "base declarada", "left": "lado declarado", "right": "sombra declarada"}
            report.check(name, pal.hex_to_rgb(declared_faces["top"]) == pal.hex_to_rgb(face["base"])
                         and pal.light_order_ok(declared_faces),
                         "caras declaradas de %s con la luz arriba a la izquierda (brillo arriba > izquierda ≥ "
                         "derecha): %s / %s / %s" % (face["base"], declared_faces["top"], declared_faces["left"],
                                                     declared_faces["right"]))
        for side in ("top", "left", "right"):
            label = labels[side]
            declared = int(face.get(side, 0))
            if declared <= 0:
                continue
            color = np.array(expected[side], dtype=np.uint8)
            found = int((opaque & (rgb == color).all(axis=2)).sum())
            report.check(name, found >= declared,
                         "cara %s de %s en su tono exacto %s (%s): %d px de %d declarados"
                         % (side, face["base"], pal.rgb_to_hex(expected[side]), label, found, declared))
        for side in ("top", "left", "right"):
            label = labels[side]
            total = int(face.get(side + "_total", 0))
            if total < MIN_FACE_PIXELS:
                continue
            share = int(face.get(side + "_plain", 0)) / float(total)
            report.check(name, share >= MIN_FLAT_SHARE,
                         "cara %s de %s lisa: la textura deja %d %% de sus %d px en el tono exacto %s (mínimo %d %%; "
                         "el detalle va encima del tono de la cara, no en su lugar; una pieza que no es lisa a "
                         "propósito lleva flat=False)"
                         % (side, face["base"], int(share * 100), total, label, int(MIN_FLAT_SHARE * 100)))


def check_furniture(report, name, arr, entry, kind):
    height, width = arr.shape[:2]
    opaque = arr[..., 3] == 255
    footprint = entry.get("footprint")
    if not footprint:
        report.warn(name, "sin planta en el manifiesto: no se comprueba lienzo ni apoyo")
        return
    w, d = footprint
    if kind == "furniture" and entry.get("height") is not None:
        flat = entry.get("flat", False)
        expected = iso.canvas_size((w, d), entry["height"], flat)
        report.check(name, (width, height) == tuple(expected),
                     "lienzo %dx%d según la guía para planta %sx%s y alto %s (es %dx%d)"
                     % (expected[0], expected[1], w, d, entry["height"], width, height))
    elif kind == "on_desk":
        report.check(name, (width, height) == (128, 128), "lienzo 128×128 (es %dx%d)" % (width, height))
    origin = (d * 64.0, height - (w + d) * 32.0)
    anchor = entry.get("anchor")
    if anchor is not None:
        report.check(name, abs(anchor[0] - origin[0]) < 0.01 and abs(anchor[1] - (origin[1] + 32.0)) < 0.01,
                     "apoyo en el centro del rombo de la casilla de anclaje (%g, %g); es (%g, %g)"
                     % (origin[0], origin[1] + 32.0, anchor[0], anchor[1]))
    gu, gv = _ground_coords(height, width, origin)
    below = opaque & ((gu >= w) | (gv >= d))
    report.check(name, not below.any(), "nada por debajo ni por delante de la planta (%d px)" % int(below.sum()))
    if entry.get("flat", False):
        inside = (gu >= 0) & (gu < w) & (gv >= 0) & (gv < d)
        report.check(name, bool(np.array_equal(opaque, inside)),
                     "pieza plana: llena exactamente el rombo de su planta (%d px de diferencia)" % int((opaque ^ inside).sum()))
    if kind == "furniture" and entry.get("min_z") is not None:
        report.check(name, entry["min_z"] <= 1.0, "la pieza se apoya en el piso (su punto más bajo está a z = %s)" % entry["min_z"])
    if kind == "furniture":
        rows = np.nonzero(opaque.any(axis=1))[0]
        lowest = int(rows.max()) if len(rows) else -1
        report.check(name, lowest >= origin[1], "la pieza llega al rombo de la planta (fila más baja %d, el rombo empieza en %d)"
                     % (lowest, int(origin[1])))
    check_flat_faces(report, name, arr, entry)
    if "off_grid" not in entry and not entry.get("curved", False):
        # Sin el dato de la rejilla que anota el motor (cajas en múltiplos de 1/64: aristas 2:1
        # seguras) solo queda medir la silueta del PNG.
        bad = bottom_runs(opaque)
        bad_top = bottom_runs(opaque, top=True)
        if bad or bad_top:
            report.warn(name, "la silueta tiene tramos que no son de 2 px (escalera 2:1): %d abajo, %d arriba"
                        % (bad, bad_top))


def wall_info(name, entry):
    stem = name[:-4]
    match = re.search(r"_(tall|low)_(x|y)$", stem)
    axis = (entry or {}).get("axis") or (match.group(2) if match else None)
    tall = (entry or {}).get("tall")
    if tall is None and match:
        tall = match.group(1) == "tall"
    piece = stem
    if match:
        piece = stem[:match.start()]
    return axis, tall, piece


def wall_origin(axis, height):
    half = iso.WALL_THICKNESS / 2.0
    if axis == "x":
        return (iso.WALL_CANVAS_W - half * 64.0, height - (1.0 + half) * 32.0)
    return (half * 64.0, height - (1.0 + half) * 32.0)


def wall_top_mask(axis, height, z):
    """Pixeles de la cara de arriba de un tramo de pared de alto z (px de sprite)."""
    half = iso.WALL_THICKNESS / 2.0
    gu, gv = _ground_coords(height, iso.WALL_CANVAS_W, wall_origin(axis, height))
    u = gu + z / 64.0
    v = gv + z / 64.0
    if axis == "x":
        return (u >= -half) & (u < half) & (v >= 0) & (v < 1)
    return (u >= 0) & (u < 1) & (v >= -half) & (v < half)


def check_wall(report, name, arr, entry):
    height, width = arr.shape[:2]
    axis, tall, _piece = wall_info(name, entry)
    if axis not in ("x", "y") or tall is None:
        report.warn(name, "no se sabe el eje o el alto de la pared (nombre *_tall_x / *_low_y o manifiesto)")
        return False
    expected = (iso.WALL_CANVAS_W, iso.WALL_CANVAS_TALL if tall else iso.WALL_CANVAS_LOW)
    if not report.check(name, (width, height) == expected,
                        "lienzo de pared %dx%d (es %dx%d)" % (expected[0], expected[1], width, height)):
        return False
    if entry is not None and entry.get("anchor") is not None:
        anchor = entry["anchor"]
        report.check(name, abs(anchor[0] - 36.0) < 0.01 and abs(anchor[1] - (height - 18.0)) < 0.01,
                     "apoyo en el punto medio del borde (36, %d); es (%g, %g)" % (height - 18, anchor[0], anchor[1]))
    opaque = arr[..., 3] == 255
    half = iso.WALL_THICKNESS / 2.0
    gu, gv = _ground_coords(height, width, wall_origin(axis, height))
    if axis == "x":
        below = opaque & ((gu >= half) | (gv >= 1.0))
    else:
        below = opaque & ((gu >= 1.0) | (gv >= half))
    report.check(name, not below.any(), "nada por debajo de la planta del tramo (%d px)" % int(below.sum()))
    # Alto: la tabla de la sección 8 (el del manifiesto, en px del mundo, o el de la pieza por su nombre).
    world = (entry or {}).get("height")
    if world is None:
        world = WALL_HEIGHTS.get(_piece)
    expected = iso.WALL_LOW_HEIGHT if not tall else (world * iso.WORLD_SCALE if world is not None else None)
    rows = np.nonzero(opaque.any(axis=1))[0]
    if expected is not None and len(rows):
        # La punta de arriba de la cara de arriba cae 2 px sobre el borde, a `expected` px del piso.
        top_row = int(np.ceil(wall_origin(axis, height)[1] - half * 32.0 - expected - 0.5))
        measured = int(rows.min())
        message = ("alto de %d px de sprite (su fila más alta debería ser la %d y es la %d)"
                   % (expected, top_row, measured))
        if _piece.startswith("wall") or _piece in WALL_HEIGHTS:
            report.check(name, abs(measured - top_row) <= WALL_HEIGHT_TOLERANCE, message)
        elif abs(measured - top_row) > WALL_HEIGHT_TOLERANCE:
            report.warn(name, "no tiene el " + message)
    if entry is not None:
        check_flat_faces(report, name, arr, entry)
    return True


def _wall_composite(arr_a, arr_b, axis):
    """Tramo A y el tramo B que le sigue hacia adelante (B tapa el canto de A). Devuelve la
    imagen compuesta, la posición de A y de B en ella y la columna donde empieza la cara larga
    del tramo de la derecha."""
    height = arr_a.shape[0]
    canvas = np.zeros((height + 32, 72 + 64, 4), dtype=np.float64)
    if axis == "x":
        pos_a, pos_b, seam = (64, 0), (0, 32), 64 + 8
    else:
        pos_a, pos_b, seam = (0, 0), (64, 32), 64
    for tile, (px, py) in ((arr_a, pos_a), (arr_b, pos_b)):
        region = canvas[py:py + height, px:px + 72]
        m = tile[..., 3] == 255
        region[m] = tile[m]
    return canvas, pos_a, pos_b, seam


def wall_join(arr_a, arr_b, axis, top_z=None):
    """Mide la unión de A con el tramo B que le sigue. Devuelve (hay hueco, desvío junto a la
    unión, mayor desvío interior). Se mide el contraste (diferencia media, 0–255) entre columnas
    vecinas de las caras largas y, si se conoce el alto (top_z en px de sprite), entre líneas
    vecinas de la cara de arriba; el desvío es cuánto se aparta ese contraste del típico de la
    pieza. Una línea, un corte en el contorno o un brillo en la unión dan un desvío mayor que el
    de cualquier parte interior."""
    canvas, pos_a, pos_b, seam = _wall_composite(arr_a, arr_b, axis)
    opaque = canvas[..., 3] == 255
    # Hueco: una fila con pixeles a los dos lados de la unión y transparente justo en ella.
    left_any = opaque[:, seam - 8:seam - 1].any(axis=1)
    right_any = opaque[:, seam + 1:seam + 8].any(axis=1)
    gap = bool((left_any & right_any & ~(opaque[:, seam - 1] & opaque[:, seam])).any())

    def column_contrast(x):
        valid = opaque[:, x] & opaque[:, x + 1]
        if valid.sum() < 4:
            return 0.0
        return float(np.abs(canvas[valid, x, :3] - canvas[valid, x + 1, :3]).mean())

    def deviation(near, inner):
        """Cuánto se aparta lo de junto a la unión, y lo interior, del contraste típico."""
        typical = float(np.median(inner))
        return (max(abs(v - typical) for v in near), max(abs(v - typical) for v in inner))

    near = [column_contrast(x) for x in range(seam - 5, seam + 4)]
    if axis == "x":
        inner_cols = list(range(8, seam - 12)) + list(range(seam + 10, 64 + 72 - 8))
    else:
        inner_cols = list(range(6, seam - 12)) + list(range(seam + 10, 64 + 64 - 6))
    join, inside = deviation(near, [column_contrast(x) for x in inner_cols])
    if top_z is not None:
        height = arr_a.shape[0]
        origin = wall_origin(axis, height)
        gu, gv = _ground_coords(canvas.shape[0], canvas.shape[1], (origin[0] + pos_a[0], origin[1] + pos_a[1]))
        half = iso.WALL_THICKNESS / 2.0
        u = gu + top_z / 64.0
        v = gv + top_z / 64.0
        along, across = (v, u) if axis == "x" else (u, v)
        top = (along >= 0) & (along < 2) & (across >= -half) & (across < half) & opaque
        line = np.floor(along * 64.0).astype(np.int64)
        valid = top[1:] & top[:-1]
        diff = np.abs(canvas[1:, :, :3] - canvas[:-1, :, :3]).mean(axis=2)
        sums = np.bincount(line[1:][valid], weights=diff[valid], minlength=130)
        counts = np.bincount(line[1:][valid], minlength=130)
        means = np.where(counts > 0, sums / np.maximum(counts, 1), 0.0)
        top_join, top_inside = deviation(list(means[60:69]), list(means[8:56]) + list(means[72:120]))
        if top_join - top_inside * SEAM_FACTOR > join - inside * SEAM_FACTOR:
            join, inside = top_join, top_inside
    return gap, join, inside


def check_wall_groups(report, walls):
    """walls: nombre -> (arr, entry). Empalmes entre tramos y zócalo."""
    by_key = {}
    for name, (arr, entry) in walls.items():
        axis, tall, piece = wall_info(name, entry)
        if axis in ("x", "y") and tall is not None:
            by_key[(piece, axis, bool(tall))] = (name, arr, entry)
    # Un tramo solo empalma con tramos de su mismo color de pared (wall_color en el manifiesto).
    color_of = dict((key, (value[2] or {}).get("wall_color")) for key, value in by_key.items())
    for (piece, axis, tall), (name, arr, entry) in sorted(by_key.items()):
        joins = (entry or {}).get("joins")
        if joins is None:
            joins = piece.startswith("wall") or piece.startswith("window")
        piece_height = (entry or {}).get("height")
        if piece_height is None:
            piece_height = WALL_HEIGHTS.get(piece)
        top_z = iso.WALL_LOW_HEIGHT if not tall else (piece_height * iso.WORLD_SCALE if piece_height else None)
        if joins:
            partners = [(name, arr)]
            for other_piece in sorted(set(k[0] for k in by_key)):
                if other_piece != piece and other_piece.startswith("wall") and (other_piece, axis, tall) in by_key \
                        and color_of[(other_piece, axis, tall)] == color_of[(piece, axis, tall)]:
                    partners.append(by_key[(other_piece, axis, tall)][:2])
            for other_name, other_arr in partners:
                for first, second, label in ((arr, other_arr, "%s seguido de %s" % (name, other_name)),
                                             (other_arr, arr, "%s seguido de %s" % (other_name, name))):
                    gap, join, inner = wall_join(first, second, axis, top_z)
                    report.check(name, not gap and join <= inner * SEAM_FACTOR + SEAM_TOLERANCE,
                                 "empalme %s: %s, desvío del contraste en la unión %.2f (interior %.2f)"
                                 % (label, "CON hueco" if gap else "sin hueco", join, inner))
                    if other_name == name:
                        break
        if not tall and (piece, axis, True) in by_key:
            tall_name, tall_arr, tall_entry = by_key[(piece, axis, True)]
            tall_height = (tall_entry or {}).get("height")
            if tall_height is None:
                tall_height = WALL_HEIGHTS.get(piece)
            low_colors = set(map(tuple, arr[arr[..., 3] == 255][:, :3].tolist()))
            tall_colors = set(map(tuple, tall_arr[tall_arr[..., 3] == 255][:, :3].tolist()))
            if not low_colors <= tall_colors:
                report.warn(name, "usa %d colores que no están en %s (la baja es el zócalo de la alta)"
                            % (len(low_colors - tall_colors), tall_name))
            if tall_height is not None:
                low_top = wall_top_mask(axis, arr.shape[0], iso.WALL_LOW_HEIGHT)
                tall_top = wall_top_mask(axis, tall_arr.shape[0], tall_height * iso.WORLD_SCALE)
                same = (low_top.sum() == tall_top.sum()
                        and np.array_equal(arr[low_top][:, :3], tall_arr[tall_top][:, :3])
                        and bool((arr[low_top][:, 3] == 255).all()))
                message = "misma cara de arriba que %s" % tall_name
                if piece.startswith("wall"):
                    report.check(name, same, message)
                elif not same:
                    report.warn(name, "no tiene la " + message)


# Cuadros de animación de una pieza de pared (puerta que se abre, persiana): parte de la pared que
# tiene que quedar igual que en la pieza cerrada.
FRAME_SAME_MIN = 0.35


def check_wall_frames(report, frames, directory, manifest):
    """frames: nombre -> (arr, entry) de los cuadros (kind 'wall_frame'). Cada cuadro lleva base (la
    pieza cerrada), base_offset (dónde cae el lienzo de la pieza dentro del cuadro) y anchor."""
    sets = {}
    for name, (arr, entry) in sorted(frames.items()):
        base = (entry or {}).get("base")
        offset = (entry or {}).get("base_offset")
        if not base or offset is None:
            report.check(name, False, "cuadro de animación con base y base_offset en el manifiesto")
            continue
        sets.setdefault(base, []).append((name, arr, entry))
        path = os.path.join(directory, base)
        if not os.path.isfile(path):
            report.check(name, False, "existe la pieza cerrada %s" % base)
            continue
        base_arr = np.array(Image.open(path).convert("RGBA"))
        bh, bw = base_arr.shape[:2]
        ox, oy = int(offset[0]), int(offset[1])
        inside = 0 <= ox and 0 <= oy and ox + bw <= arr.shape[1] and oy + bh <= arr.shape[0]
        report.check(name, inside, "el lienzo de %s cabe en el cuadro (corrido %d, %d)" % (base, ox, oy))
        if not inside:
            continue
        region = arr[oy:oy + bh, ox:ox + bw]
        opaque = base_arr[..., 3] == 255
        same = (region[opaque] == base_arr[opaque]).all(axis=1).mean() if opaque.any() else 0.0
        report.check(name, same >= FRAME_SAME_MIN, "la pared alrededor queda como en %s (%.0f %% igual)"
                     % (base, same * 100))
        base_anchor = (manifest.get(base) or {}).get("anchor")
        anchor = entry.get("anchor")
        if base_anchor and anchor:
            report.check(name, abs(anchor[0] - base_anchor[0] - ox) < 0.01 and abs(anchor[1] - base_anchor[1] - oy) < 0.01,
                         "apoyo = el de %s + base_offset" % base)
    for base, items in sorted(sets.items()):
        shapes = set(arr.shape for _n, arr, _e in items)
        anchors = set(tuple(e.get("anchor") or ()) for _n, _a, e in items)
        report.check(base, len(shapes) == 1 and len(anchors) == 1,
                     "sus %d cuadros tienen el mismo lienzo y el mismo apoyo" % len(items))
        steps = sorted(int(e.get("frame", 0)) for _n, _a, e in items)
        expected = int(items[0][2].get("frames", len(items)))
        report.check(base, steps == list(range(1, expected + 1)), "cuadros 1 a %d completos (hay %s)" % (expected, steps))


def check_item_frames(report, frames, directory):
    """frames: nombre -> (arr, entry) de los cuadros de un objeto de pared (kind 'wall_item_frame'). Cada
    cuadro tiene el lienzo, el apoyo y la silueta de su pieza (solo cambia lo de adentro)."""
    sets = {}
    for name, (arr, entry) in sorted(frames.items()):
        base = (entry or {}).get("base")
        if not base:
            report.check(name, False, "cuadro de objeto de pared con base en el manifiesto")
            continue
        sets.setdefault(base, []).append((name, arr, entry))
        path = os.path.join(directory, base)
        if not os.path.isfile(path):
            report.check(name, False, "existe la pieza %s" % base)
            continue
        base_arr = np.array(Image.open(path).convert("RGBA"))
        report.check(name, base_arr.shape == arr.shape, "mismo lienzo que %s" % base)
        if base_arr.shape != arr.shape:
            continue
        report.check(name, ((base_arr[..., 3] == 255) == (arr[..., 3] == 255)).all(),
                     "misma silueta que %s (solo cambia lo de adentro)" % base)
    for base, items in sorted(sets.items()):
        steps = sorted(int(e.get("frame", 0)) for _n, _a, e in items)
        expected = int(items[0][2].get("frames", len(items)))
        report.check(base, steps == list(range(1, expected + 1)), "cuadros 1 a %d completos (hay %s)" % (expected, steps))
        anchors = set(tuple(e.get("anchor") or ()) for _n, _a, e in items)
        report.check(base, len(anchors) == 1, "sus %d cuadros tienen el mismo apoyo" % len(items))


def check_tree_frames(report, frames, directory):
    """frames: nombre -> (arr, entry) de los cuadros de un árbol (kind 'tree_frame', hojas que caen). Cada
    cuadro tiene el lienzo y el apoyo de su árbol, lo tapa entero (solo se agregan hojas encima) y cumple
    las reglas del árbol."""
    sets = {}
    for name, (arr, entry) in sorted(frames.items()):
        check_other(report, name, arr, None, "tree")
        base = (entry or {}).get("base")
        if not base:
            report.check(name, False, "cuadro de árbol con base en el manifiesto")
            continue
        sets.setdefault(base, []).append((name, arr, entry))
        path = os.path.join(directory, base)
        if not os.path.isfile(path):
            report.check(name, False, "existe el árbol %s" % base)
            continue
        base_arr = np.array(Image.open(path).convert("RGBA"))
        report.check(name, base_arr.shape == arr.shape, "mismo lienzo que %s" % base)
        if base_arr.shape != arr.shape:
            continue
        lost = (base_arr[..., 3] == 255) & (arr[..., 3] != 255)
        report.check(name, not lost.any(), "conserva todo el árbol %s (%d px perdidos)" % (base, int(lost.sum())))
    for base, items in sorted(sets.items()):
        steps = sorted(int(e.get("frame", 0)) for _n, _a, e in items)
        expected = int(items[0][2].get("frames", len(items)))
        report.check(base, steps == list(range(1, expected + 1)), "cuadros 1 a %d completos (hay %s)" % (expected, steps))
        anchors = set(tuple(e.get("anchor") or ()) for _n, _a, e in items)
        report.check(base, anchors == {(64, 224)}, "sus %d cuadros tienen el apoyo del árbol" % len(items))


def check_other(report, name, arr, entry, kind):
    height, width = arr.shape[:2]
    opaque = arr[..., 3] == 255
    rows = np.nonzero(opaque.any(axis=1))[0]
    lowest = int(rows.max()) if len(rows) else -1
    if kind == "wall_item":
        # 64×128 (sección 7) o 128×192 para el que ocupa dos bordes y sube hasta cerca del techo (el televisor).
        report.check(name, (width, height) in ((64, 128), (128, 192)),
                     "lienzo de objeto de pared 64×128 o 128×192 (es %dx%d)" % (width, height))
        if entry is not None and entry.get("anchor") is not None:
            expected = [width / 2.0, float(height - width / 4)]
            report.check(name, [float(v) for v in entry["anchor"]] == expected,
                         "apoyo del objeto de pared en (%g, %g), el punto medio del borde en el piso"
                         % tuple(expected))
    elif kind == "character":
        report.check(name, (width, height) == (128, 128), "lienzo de personaje 128×128 (es %dx%d)" % (width, height))
        if not (104 <= lowest <= 119):
            report.warn(name, "los pies deberían quedar hacia la fila 112 (la más baja es %d)" % lowest)
    elif kind == "tree":
        report.check(name, (width, height) == (128, 256), "lienzo de árbol 128×256 (es %dx%d)" % (width, height))
        report.check(name, lowest >= 192, "el árbol llega al rombo de abajo (fila más baja %d)" % lowest)
        gu, gv = _ground_coords(height, width, (64.0, 192.0))
        below = opaque & ((gu >= 1.0) | (gv >= 1.0))
        report.check(name, not below.any(), "nada por debajo de la planta (%d px)" % int(below.sum()))
    elif kind == "bush":
        # Arbustos y setos: lienzo de mueble según su planta (1×1, 2×1 o 2×2) y apoyados en el piso.
        report.check(name, (width, height) in ((128, 128), (128, 160), (192, 128), (192, 160), (192, 192), (256, 192), (256, 224)),
                     "lienzo de arbusto de planta 1×1, 2×1 o 2×2 (es %dx%d)" % (width, height))
        report.check(name, lowest >= height - 48, "el arbusto llega al piso (fila más baja %d)" % lowest)
    elif kind == "overlay":
        report.check(name, (width, height) == (128, 128), "lienzo 128×128 (es %dx%d)" % (width, height))
        if (width, height) == (128, 128):
            outside = opaque & ~iso.rhombus_mask(128, 128)
            report.check(name, not outside.any(), "solo dentro del rombo (%d px fuera)" % int(outside.sum()))
    elif kind == "shadow":
        colors = len(np.unique(arr[opaque][:, :3], axis=0)) if opaque.any() else 0
        report.check(name, colors <= 1, "sombra de un solo tono (tiene %d)" % colors)
        footprint = (entry or {}).get("footprint")
        if footprint:
            w, d = footprint
            origin = (d * 64.0, height - (w + d) * 32.0)
            gu, gv = _ground_coords(height, width, origin)
            outside = opaque & ~((gu >= 0) & (gu < w) & (gv >= 0) & (gv < d))
            report.check(name, not outside.any(), "sombra dentro del rombo de la planta (%d px fuera)" % int(outside.sum()))
    if entry is not None and kind in ("wall_item", "character", "tree"):
        check_flat_faces(report, name, arr, entry)


# ---------------------------------------------------------------------- principal

def run(directory, verbose=False, groups=None):
    """Revisa la carpeta. groups = lista de grupos (los de generate.py): solo se revisan los
    archivos de sus manifiestos, para no mezclar con lo que otro esté generando en la misma carpeta."""
    report = Report(verbose)
    manifest = load_manifests(directory)
    paths = sorted(glob.glob(os.path.join(directory, "*.png")))
    paths = [p for p in paths if not os.path.basename(p).startswith(SKIP_PREFIXES)]
    if groups is not None:
        wanted = load_manifests(directory, set(groups))
        manifest = wanted
        paths = [p for p in paths if os.path.basename(p) in wanted]
    if not paths:
        print("No hay PNG para revisar en %s" % directory)
        print("RESULTADO: OK")
        return 0
    floors = {}
    walls = {}
    frames = {}
    item_frames = {}
    tree_frames = {}
    for path in paths:
        name = os.path.basename(path)
        image = Image.open(path)
        entry = manifest.get(name)
        kind = (entry or {}).get("kind") or guess_kind(name)
        if image.mode != "RGBA":
            report.check(name, False, "PNG RGBA de 8 bits (modo %s)" % image.mode)
            continue
        arr = np.array(image)
        check_common(report, name, image, arr, entry, kind)
        if kind == "floor":
            if check_floor(report, name, arr):
                match = re.match(r"^(.*)_(\d+)\.png$", name)
                if match:
                    floors.setdefault(match.group(1), {})[int(match.group(2))] = arr
                else:
                    report.warn(name, "piso sin número de variante (_0 a _3)")
        elif kind == "wall":
            if check_wall(report, name, arr, entry):
                walls[name] = (arr, entry)
        elif kind in ("furniture", "on_desk"):
            if entry is None:
                report.warn(name, "mueble sin manifiesto: no se comprueba lienzo, apoyo ni caras")
            else:
                check_furniture(report, name, arr, entry, kind)
        elif kind == "wall_frame":
            frames[name] = (arr, entry)
        elif kind == "wall_item_frame":
            item_frames[name] = (arr, entry)
        elif kind == "tree_frame":
            tree_frames[name] = (arr, entry)
        elif kind in ("wall_item", "character", "tree", "bush", "overlay", "shadow"):
            check_other(report, name, arr, entry, kind)
        else:
            report.warn(name, "tipo %s: solo se revisó formato, alfa y recorte"
                        % ("'%s'" % kind if kind else "desconocido (sin manifiesto ni nombre de la guía)"))
    for material in sorted(floors):
        check_floor_group(report, material, floors[material].keys(), floors[material])
    check_wall_groups(report, walls)
    check_wall_frames(report, frames, directory, manifest)
    check_item_frames(report, item_frames, directory)
    check_tree_frames(report, tree_frames, directory)
    missing = sorted(set(manifest) - set(os.path.basename(p) for p in paths))
    for name in missing:
        report.warn(name, "está en el manifiesto pero no hay PNG")
    print("%d PNG, %d comprobaciones bien, %d fallos, %d avisos"
          % (len(paths), report.passed, len(report.failures), len(report.warnings)))
    if report.failures:
        print("RESULTADO: FALLA")
        for failure in report.failures:
            print("  - " + failure)
        return 1
    print("RESULTADO: OK")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Verifica los sprites de una carpeta contra docs/sprites_128.md.")
    parser.add_argument("directory", help="carpeta con los PNG (y los manifest*.json)")
    parser.add_argument("--verbose", action="store_true", help="muestra también lo que pasa")
    parser.add_argument("--group", default="", help="solo los archivos de estos grupos (separados por coma)")
    args = parser.parse_args()
    groups = [g.strip() for g in args.group.split(",") if g.strip()]
    return run(args.directory, args.verbose, groups or None)


if __name__ == "__main__":
    sys.exit(main())
