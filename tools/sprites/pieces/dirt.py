# Manchas de suciedad (DirtOverlay): se dibujan encima del piso de una casilla sucia.
#
#   dirt_0           barro: huellas y manchones irregulares en tres marrones grises
#   dirt_1           café derramado: charco con canto oscuro, brillo claro y gotas sueltas
#   dirt_2           migas y papeles: migas de 2×1 px y dos papelitos arrugados
#   _sheets/dirt.png
#
# Lienzo 128×128 con el rombo abajo, como un piso; alfa 0/255 solo dentro del rombo.
# Se dibuja en coordenadas del piso (u, v de 0 a 1): todo sale plano y 2:1.
import os

import numpy as np
from PIL import Image

import iso
import sheet

SIZE = 128
ORIGIN = (64.0, 64.0)  # esquina de arriba del rombo


def rgb(hexa):
    return np.array([int(hexa[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.uint8)


def ground():
    ys, xs = np.mgrid[0:SIZE, 0:SIZE]
    rx = xs + 0.5 - ORIGIN[0]
    ry = ys + 0.5 - ORIGIN[1]
    return (ry / 32.0 + rx / 64.0) / 2.0, (ry / 32.0 - rx / 64.0) / 2.0


def value_noise(u, v, cells, seed):
    """Ruido suave de 0 a 1 en una rejilla de cells × cells sobre la casilla."""
    rng = np.random.RandomState(seed)
    table = rng.rand(cells + 2, cells + 2)
    fu, fv = u * cells, v * cells
    iu, iv = np.floor(fu).astype(int), np.floor(fv).astype(int)
    tu, tv = fu - iu, fv - iv
    tu, tv = tu * tu * (3 - 2 * tu), tv * tv * (3 - 2 * tv)
    iu = np.clip(iu, 0, cells)
    iv = np.clip(iv, 0, cells)
    a = table[iu, iv] * (1 - tu) + table[iu + 1, iv] * tu
    b = table[iu, iv + 1] * (1 - tu) + table[iu + 1, iv + 1] * tu
    return a * (1 - tv) + b * tv


def blob(u, v, cu, cv, ru, rv, wobble, seed):
    """Elipse en el piso deformada por ruido; devuelve la distancia normalizada (< 1 adentro)."""
    d = np.sqrt(((u - cu) / ru) ** 2 + ((v - cv) / rv) ** 2)
    return d - wobble * (value_noise(u, v, 6, seed) - 0.5)


def finish(rgb_arr, mask, inside):
    mask = mask & inside
    out = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    out[..., :3] = rgb_arr
    out[..., 3] = np.where(mask, 255, 0)
    return Image.fromarray(out)


def paint(arr, mask, color):
    arr[mask] = rgb(color)


def dirt_mud(u, v, inside):
    arr = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    mask = np.zeros((SIZE, SIZE), dtype=bool)
    spots = ((0.38, 0.42, 0.2, 0.13, 11), (0.62, 0.6, 0.13, 0.1, 12), (0.3, 0.7, 0.08, 0.06, 13),
             (0.7, 0.3, 0.07, 0.09, 14))
    for cu, cv, ru, rv, seed in spots:
        d = blob(u, v, cu, cv, ru, rv, 0.7, seed)
        m = d < 1.0
        paint(arr, m & ~mask, "6b5640")
        paint(arr, m & (d < 0.55), "584631")
        paint(arr, m & (d > 0.85), "4c3c2a")
        mask |= m
    # Huellas: pares de suelas cortas a lo largo de u.
    for k, (cu, cv) in enumerate(((0.2, 0.25), (0.34, 0.18), (0.5, 0.28), (0.66, 0.2), (0.8, 0.3))):
        d = np.sqrt(((u - cu) / 0.05) ** 2 + ((v - cv) / 0.025) ** 2)
        m = d < 1.0
        paint(arr, m, "54432f" if k % 2 else "5f4c37")
        mask |= m
    return finish(arr, mask, inside)


def dirt_coffee(u, v, inside):
    arr = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    d = blob(u, v, 0.48, 0.5, 0.24, 0.17, 0.5, 21)
    mask = d < 1.0
    paint(arr, mask, "5a3a22")
    paint(arr, mask & (d > 0.82), "3e2614")  # canto oscuro
    shine = mask & (np.abs(d - 0.5) < 0.07) & (u < 0.46) & (v < 0.5)
    paint(arr, shine, "8a6040")
    rng = np.random.RandomState(5)
    for _ in range(7):
        ang = rng.uniform(0, 2 * np.pi)
        dist = rng.uniform(0.3, 0.38)
        cu, cv = 0.48 + dist * np.cos(ang), 0.5 + dist * np.sin(ang) * 0.75
        r = rng.uniform(0.018, 0.032)
        m = ((u - cu) ** 2 + (v - cv) ** 2) < r * r
        paint(arr, m, "4a2e1a")
        mask |= m
    return finish(arr, mask, inside)


def dirt_crumbs(u, v, inside):
    arr = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    mask = np.zeros((SIZE, SIZE), dtype=bool)
    rng = np.random.RandomState(9)
    ys, xs = np.mgrid[0:SIZE, 0:SIZE]
    for _ in range(44):
        x = int(rng.uniform(30, 96)) // 2 * 2
        y = int(rng.uniform(76, 110))
        m = (ys == y) & ((xs == x) | (xs == x + 1))
        paint(arr, m, "b08550" if rng.rand() < 0.6 else "7a5630")
        mask |= m
    # Papelitos arrugados: rombos chicos en el piso con un canto gris y un pliegue.
    for cu, cv, s in ((0.3, 0.58, 0.11), (0.66, 0.38, 0.09)):
        d = np.abs(u - cu) + np.abs(v - cv) * 1.3 - 0.4 * s * (value_noise(u, v, 12, int(cu * 100)) - 0.5)
        m = d < s
        paint(arr, m, "efece4")
        paint(arr, m & (d > s * 0.78), "8f8b80")
        paint(arr, m & (np.abs((u - cu) - (v - cv)) < 0.008), "cfcbbf")
        mask |= m
    return finish(arr, mask, inside)


VARIANTS = (("dirt_0", dirt_mud), ("dirt_1", dirt_coffee), ("dirt_2", dirt_crumbs))


def build(out_dir):
    u, v = ground()
    inside = iso.rhombus_mask(SIZE, SIZE)
    files = []
    items = []
    for name, fn in VARIANTS:
        image = fn(u, v, inside)
        files.append(iso.save(image, out_dir, name, kind="overlay"))
        tile = sheet.plain_tile()
        tile.alpha_composite(image)
        items.append((name, tile))
    folder = os.path.join(out_dir, "_sheets")
    if not os.path.isdir(folder):
        os.makedirs(folder)
    sheet.contact_sheet(items, columns=3, scale=4).save(os.path.join(folder, "dirt.png"))
    return files
