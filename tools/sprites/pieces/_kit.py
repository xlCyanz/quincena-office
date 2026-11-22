# Ayudas compartidas por office_extra.py, break_room.py y services.py (con "_" generate.py no lo carga).
import os

import numpy as np

import iso
import sheet
from pieces import _shadow


def g(v):
    """Redondea a 1/64 de casilla para que las aristas de las cajas salgan 2:1."""
    return round(v * 64.0) / 64.0


def plain(ctx):
    return np.asarray(ctx.base).copy() if np.ndim(ctx.base) else np.full(np.shape(ctx.a), ctx.base)


def grid(ctx):
    """(a, b, ancho, alto) de la cara en px enteros; a, b desde abajo a la izquierda."""
    return np.floor(ctx.a), np.floor(ctx.b), np.floor(ctx.w), np.floor(ctx.h)


def inside(a, b, a0, a1, b0, b1):
    return (a >= a0) & (a < a1) & (b >= b0) & (b < b1)


def frame(a, b, a0, a1, b0, b1):
    """Borde de 1 px del rectángulo [a0, a1) × [b0, b1)."""
    return inside(a, b, a0, a1, b0, b1) & ~inside(a, b, a0 + 1, a1 - 1, b0 + 1, b1 - 1)


def sunken(index, a, b, a0, a1, b0, b1, dark, lit):
    """Tablero hundido: línea oscura arriba y a la izquierda, canto claro abajo y a la derecha."""
    box = inside(a, b, a0, a1, b0, b1)
    d = box & ((b == b1 - 1) | (a == a0))
    l = box & ((b == b0) | (a == a1 - 1)) & ~d
    index = np.where(d, dark, index)
    return np.where(l, lit, index)


def drawers(count, line, handle, margin=1, foot=2, handle_w=0.4, label=None):
    """Textura de cajonera: `count` cajones con rendija `line`, tirador `handle`, etiqueta opcional y zócalo."""
    def tex(ctx):
        a, b, w, h = grid(ctx)
        index = plain(ctx)
        step = (h - foot) / float(count)
        for k in range(count):
            b0 = np.floor(foot + k * step)
            b1 = np.floor(foot + (k + 1) * step)
            index = np.where(frame(a, b, margin, w - margin, b0, b1 + 1), line, index)
            mid = np.floor((b0 + b1) / 2.0) + 1
            hw = np.floor(w * handle_w / 2.0)
            index = np.where(inside(a, b, np.floor(w / 2.0) - hw, np.floor(w / 2.0) + hw, mid, mid + 2), handle,
                             index)
            if label is not None:
                index = np.where(inside(a, b, np.floor(w / 2.0) - 3, np.floor(w / 2.0) + 3, mid + 3, mid + 5) &
                                 (b < b1 - 1), label, index)
        return np.where(b < foot, line, index)
    return tex


class Saver:
    """Guarda cada mueble con su sombra y junta una hoja de contacto."""

    def __init__(self, out_dir):
        self.out_dir = out_dir
        self.files = []
        self.items = []

    def keep(self, c, name, shapes, **meta):
        c.finish()
        self.files.append(iso.save(c, self.out_dir, name, **meta))
        self.files.append(_shadow.save_shadow(c, self.out_dir, name + "_shadow", shapes))
        self.items.append((name, sheet.on_background(c.image, scale=1)))

    def rotations(self, fn, name, shapes, **meta):
        for rotation in range(4):
            self.keep(fn(rotation), "%s_r%d" % (name, rotation), shapes, **meta)

    def sheet(self, name, columns=4):
        folder = os.path.join(self.out_dir, "_sheets")
        if not os.path.isdir(folder):
            os.makedirs(folder)
        sheet.contact_sheet(self.items, columns=columns, scale=3).save(os.path.join(folder, name + ".png"))
        return self.files
