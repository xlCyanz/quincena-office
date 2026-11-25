"""Rampas y lienzo de los personajes (lo que usa _figure.py; no depende del motor viejo ``tools/sprites/iso.py``).

* Rampas de 8 tonos (OUTLINE … SHINE) como las de STYLE.md: caras exactas (base, −25 %, −40 %) y los demás
  tonos con corrimiento de color.
* ``FigureCanvas``: lienzo 128×128 con los pies en (64, 112), z-buffer por software y formas libres por campo
  de distancia (``sdf``, marcha de rayos). Sin acabado automático: el modelo pinta cada pixel y ``finish`` solo
  pasa índices de rampa a colores.
"""

import colorsys

import numpy as np
from PIL import Image

# ---------------------------------------------------------------------- proyección

HALF_W = 64  # media casilla en px: 2:1
HALF_H = 32
Z_METRIC = 78.4  # px de pantalla por casilla a lo largo del rayo de la cámara
RAY_SPEED = (2.0 * Z_METRIC * Z_METRIC + 64.0 * 64.0) ** 0.5
_LIGHT = np.array([-0.30, 0.45, 0.85])
LIGHT_DIR = _LIGHT / np.linalg.norm(_LIGHT)
PAD = 32  # margen del lienzo interno: lo que cae ahí queda recortado
_DEPTH_EMPTY = -1.0e9
SIDE_CURVED = 4

# ---------------------------------------------------------------------- rampas

OUTLINE = 0  # contorno: tono oscuro del mismo color, nunca negro puro
DEEP = 1  # sombra profunda
RIGHT = 2  # base −40 %
LEFT = 3  # base −25 %
SOFT = 4  # base −12 %
BASE = 5  # color base exacto
LIGHT = 6  # brillo
SHINE = 7  # reflejo
STEP_COUNT = 8
LEFT_DARKEN = 0.25
RIGHT_DARKEN = 0.40
SOFT_DARKEN = 0.12
MIN_OUTLINE_VALUE = 12
COOL_HUE = 250.0 / 360.0
WARM_HUE = 50.0 / 360.0
# Bandas de luz por defecto de una forma libre: (umbral mínimo de n·luz, tono), de más a menos luz.
LIGHT_BANDS = ((0.955, LIGHT), (0.66, BASE), (0.52, SOFT), (0.10, LEFT), (-0.44, RIGHT), (-9.0, DEEP))


def hex_to_rgb(value):
    """'c9b48a', '#c9b48a' o una terna -> (r, g, b) con enteros de 0 a 255."""
    if isinstance(value, (tuple, list, np.ndarray)):
        return (int(value[0]), int(value[1]), int(value[2]))
    text = str(value).strip().lstrip("#")
    if len(text) != 6:
        raise ValueError("color hex inválido: %r" % (value,))
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))


def rgb_to_hex(color):
    r, g, b = hex_to_rgb(color)
    return "%02x%02x%02x" % (r, g, b)


def _round_channel(value):
    return int(min(255, max(0, int(value + 0.5))))


def darken(color, amount):
    """Como Color.darkened(amount) de Godot: canal × (1 − amount), redondeado."""
    r, g, b = hex_to_rgb(color)
    factor = 1.0 - float(amount)
    return (_round_channel(r * factor), _round_channel(g * factor), _round_channel(b * factor))


def lighten(color, amount):
    """Como Color.lightened(amount): canal + (255 − canal) × amount."""
    r, g, b = hex_to_rgb(color)
    amount = float(amount)
    return (_round_channel(r + (255 - r) * amount), _round_channel(g + (255 - g) * amount),
            _round_channel(b + (255 - b) * amount))


def adjust(color, value=1.0, saturation=1.0, hue_toward=None, hue_amount=0.0, tint=0.0):
    """En HSV: brillo × value, saturación × saturation y tono corrido hue_amount hacia hue_toward (0–1);
    tint = saturación mínima que se le da a un gris para que el tono se note."""
    r, g, b = [c / 255.0 for c in hex_to_rgb(color)]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if hue_toward is not None:
        if s < 0.04:
            h = hue_toward
            s = max(s, tint)
        else:
            delta = ((hue_toward - h + 0.5) % 1.0) - 0.5
            h = (h + delta * hue_amount) % 1.0
    s = min(1.0, max(0.0, s * saturation))
    v = min(1.0, max(0.0, v * value))
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return (_round_channel(r * 255.0), _round_channel(g * 255.0), _round_channel(b * 255.0))


class Ramp(object):
    """Colores de un material, de oscuro a claro (índices OUTLINE … SHINE)."""

    def __init__(self, colors, base_hex=None, name=None):
        self.colors = [hex_to_rgb(c) for c in colors]
        self.base_hex = base_hex
        self.name = name or base_hex or "ramp"

    def __len__(self):
        return len(self.colors)

    def table(self):
        """Arreglo uint8 (n, 3) para pintar con índices."""
        return np.array(self.colors, dtype=np.uint8)


def ramp(base, outline=None, deep=None, soft=None, light=None, shine=None, name=None, shift=1.0):
    """Rampa de 8 tonos desde el hex base: RIGHT, LEFT y BASE exactos; los demás con un leve corrimiento de tono
    (shift, 0 = nada) o fijados a mano."""
    base_rgb = hex_to_rgb(base)
    colors = [None] * STEP_COUNT
    colors[BASE] = base_rgb
    colors[LEFT] = darken(base_rgb, LEFT_DARKEN)
    colors[RIGHT] = darken(base_rgb, RIGHT_DARKEN)
    colors[OUTLINE] = hex_to_rgb(outline) if outline is not None else adjust(
        base_rgb, 0.40, 1.0 + 0.25 * shift, COOL_HUE, 0.10 * shift, 0.10 * shift)
    colors[DEEP] = hex_to_rgb(deep) if deep is not None else adjust(
        base_rgb, 0.50, 1.0 + 0.15 * shift, COOL_HUE, 0.06 * shift, 0.06 * shift)
    colors[SOFT] = hex_to_rgb(soft) if soft is not None else darken(base_rgb, SOFT_DARKEN)
    if light is not None:
        colors[LIGHT] = hex_to_rgb(light)
    else:
        colors[LIGHT] = adjust(lighten(base_rgb, 0.20), 1.0, 1.0 - 0.12 * shift, WARM_HUE, 0.08 * shift, 0.05 * shift)
    if shine is not None:
        colors[SHINE] = hex_to_rgb(shine)
    else:
        colors[SHINE] = adjust(lighten(base_rgb, 0.48), 1.0, 1.0 - 0.25 * shift, WARM_HUE, 0.12 * shift, 0.04 * shift)
    if max(colors[OUTLINE]) < MIN_OUTLINE_VALUE:
        colors[OUTLINE] = (MIN_OUTLINE_VALUE - 4, MIN_OUTLINE_VALUE - 4, MIN_OUTLINE_VALUE)
    return Ramp(colors, base_hex=rgb_to_hex(base_rgb), name=name)


def palette(colors, name=None):
    """Paleta libre a partir de una lista de hex o ternas, en el orden dado."""
    return Ramp(colors, base_hex=None, name=name)


# ---------------------------------------------------------------------- lienzo


def _bands(value, bands):
    """Índices de rampa por bandas (umbral mínimo, índice) de mayor a menor."""
    out = np.full(value.shape, bands[-1][1], dtype=np.int16)
    for limit, index in reversed(bands):
        out = np.where(value >= limit, index, out)
    return out


class FaceContext(object):
    """Lo que recibe una textura tex(ctx) -> índices de rampa (o None): base (índice por bandas de luz), a y b
    (px en la forma), x, y, z (punto del modelo), sx, sy (pixel), light (n·luz) y la normal nx, ny, nz."""

    def __init__(self):
        self.base = None
        self.a = None
        self.b = None
        self.w = 0.0
        self.h = 0.0
        self.x = None
        self.y = None
        self.z = None
        self.sx = None
        self.sy = None
        self.light = None
        self.nx = None
        self.ny = None
        self.nz = None


class FigureCanvas(object):
    """Lienzo 128×128 de un personaje parado en (0.5, 0.5) de su casilla, girado rotation cuartos de vuelta.
    Búferes internos (alto+2·PAD × ancho+2·PAD): alpha, depth, part, face, fid, side, shade, ramp_id, u, v, z, a, b."""

    def __init__(self, rotation=0):
        self.width = 128
        self.height = 128
        self.origin = (64.0, 80.0)
        self.anchor = (64.0, 112.0)
        self.kind = "character"
        self.rotation = int(rotation) % 4
        self.pad = PAD
        self._setup_transform()
        hh = self.height + 2 * self.pad
        ww = self.width + 2 * self.pad
        ys, xs = np.mgrid[0:hh, 0:ww]
        self.X = xs - self.pad
        self.Y = ys - self.pad
        rx = self.X + 0.5 - self.origin[0]
        ry = self.Y + 0.5 - self.origin[1]
        # Punto del piso (z = 0) que cae en cada pixel; a la altura z es (gu + z/64, gv + z/64).
        self._gu = (ry / HALF_H + rx / HALF_W) / 2.0
        self._gv = (ry / HALF_H - rx / HALF_W) / 2.0
        shape = (hh, ww)
        self.alpha = np.zeros(shape, dtype=bool)
        self.depth = np.full(shape, _DEPTH_EMPTY, dtype=np.float64)
        self.part = np.full(shape, -1, dtype=np.int32)
        self.face = np.full(shape, -1, dtype=np.int16)
        self.fid = np.full(shape, -1, dtype=np.int32)
        self.side = np.zeros(shape, dtype=np.int8)
        self.shade = np.zeros(shape, dtype=np.int16)
        self.ramp_id = np.full(shape, -1, dtype=np.int16)
        self.u = np.zeros(shape, dtype=np.float64)
        self.v = np.zeros(shape, dtype=np.float64)
        self.z = np.zeros(shape, dtype=np.float64)
        self.a = np.zeros(shape, dtype=np.float64)
        self.b = np.zeros(shape, dtype=np.float64)
        self.min_z = None
        self.ramps = []
        self.parts = []
        self._names = {}
        self.clipped = False
        self.result = None
        self.final_shade = None
        self.final_alpha = None

    def _setup_transform(self):
        r = self.rotation
        if r == 0:
            m, t = np.array([[1.0, 0.0], [0.0, 1.0]]), np.array([0.0, 0.0])
        elif r == 1:
            m, t = np.array([[0.0, -1.0], [1.0, 0.0]]), np.array([1.0, 0.0])
        elif r == 2:
            m, t = np.array([[-1.0, 0.0], [0.0, -1.0]]), np.array([1.0, 1.0])
        else:
            m, t = np.array([[0.0, 1.0], [-1.0, 0.0]]), np.array([0.0, 1.0])
        self._m = m
        self._t = t

    def to_world(self, x, y):
        """Punto del modelo (casillas) -> punto del mundo ya girado (u, v)."""
        m, t = self._m, self._t
        return (m[0, 0] * x + m[0, 1] * y + t[0], m[1, 0] * x + m[1, 1] * y + t[1])

    def to_model(self, u, v):
        """Punto del mundo (u, v) -> punto del modelo (x, y). Acepta arreglos."""
        m, t = self._m, self._t
        du = u - t[0]
        dv = v - t[1]
        return (m[0, 0] * du + m[1, 0] * dv, m[0, 1] * du + m[1, 1] * dv)

    def project(self, x, y, z=0.0):
        """Pixel del lienzo final (con decimales) donde cae el punto (x, y, z) del modelo."""
        u, v = self.to_world(x, y)
        return (self.origin[0] + (u - v) * HALF_W, self.origin[1] + (u + v) * HALF_H - z)

    def crop(self, arr):
        """Recorta un búfer interno al tamaño del lienzo final."""
        p = self.pad
        return arr[p:p + self.height, p:p + self.width]

    # ------------------------------------------------------------------ piezas

    def _ramp_id(self, ramp_):
        for index, known in enumerate(self.ramps):
            if known is ramp_:
                return index
        self.ramps.append(ramp_)
        return len(self.ramps) - 1

    def _part_ids(self, part):
        """Ids de pieza desde un id, un nombre (todas las que lo llevan) o una lista."""
        if isinstance(part, str):
            if part not in self._names:
                raise KeyError("no hay ninguna pieza llamada %r" % part)
            return list(self._names[part])
        if isinstance(part, (list, tuple, set)):
            ids = []
            for item in part:
                ids.extend(self._part_ids(item))
            return ids
        return [int(part)]

    def _new_part(self, name):
        self.parts.append({"name": name})
        pid = len(self.parts) - 1
        if name:
            self._names.setdefault(name, []).append(pid)
        return pid

    def select(self, part):
        """Pixeles visibles de una pieza (id, nombre o lista)."""
        return self.alpha & np.isin(self.part, self._part_ids(part))

    def paint(self, mask, index, ramp_=None):
        """Cambia el índice (y la rampa) de los pixeles visibles de mask."""
        m = mask & self.alpha
        self.shade[m] = np.broadcast_to(np.asarray(index, dtype=np.int16), m.shape)[m]
        if ramp_ is not None:
            self.ramp_id[m] = self._ramp_id(ramp_)
        self.result = None
        return m

    def _put(self, mask, depth, shade, pid, rid, u, v, z, a, b):
        m = mask & (depth >= self.depth - 1.0e-7)
        if not m.any():
            return m
        lowest = float(np.min(np.broadcast_to(z, m.shape)[mask]))
        self.min_z = lowest if self.min_z is None else min(self.min_z, lowest)
        self.depth[m] = depth[m]
        self.alpha[m] = True
        self.part[m] = pid
        self.face[m] = 7  # superficie libre
        self.fid[m] = pid * 8 + 7
        self.side[m] = SIDE_CURVED
        self.shade[m] = np.broadcast_to(shade, m.shape)[m]
        self.ramp_id[m] = rid
        self.u[m] = np.broadcast_to(u, m.shape)[m]
        self.v[m] = np.broadcast_to(v, m.shape)[m]
        self.z[m] = np.broadcast_to(z, m.shape)[m]
        self.a[m] = np.broadcast_to(a, m.shape)[m]
        self.b[m] = np.broadcast_to(b, m.shape)[m]
        self.result = None
        return m

    # ------------------------------------------------------------------ forma libre

    def sdf(self, fn, bounds, ramp_, tex=None, bands=None, name=None, steps=96):
        """Forma dada por fn(x, y, z) -> distancia con signo en px (negativa adentro), cortada a
        bounds = (x0, x1, y0, y1, z0, z1). Índice por bandas de luz o por tex(ctx). Devuelve el id de la pieza."""
        pid = self._new_part(name)
        rid = self._ramp_id(ramp_)
        x0, x1, y0, y1, z0, z1 = bounds
        ua, va = self.to_world(x0, y0)
        ub, vb = self.to_world(x1, y1)
        u0, u1 = min(ua, ub), max(ua, ub)
        v0, v1 = min(va, vb), max(va, vb)
        gu, gv = self._gu.ravel(), self._gv.ravel()
        t_in_u = u1 - gu
        t_in_v = v1 - gv
        t_in_z = np.full(gu.shape, z1 / 64.0)
        t_in = np.minimum(np.minimum(t_in_u, t_in_v), t_in_z)
        t_out = np.maximum(np.maximum(u0 - gu, v0 - gv), z0 / 64.0)
        active_idx = np.nonzero(t_in > t_out + 1.0e-9)[0]
        if active_idx.size == 0:
            return pid
        gua, gva = gu[active_idx], gv[active_idx]
        t = t_in[active_idx].copy()
        t_end = t_out[active_idx]
        entry = np.where(t_in_z[active_idx] <= np.minimum(t_in_u[active_idx], t_in_v[active_idx]), 2,
                         np.where(t_in_u[active_idx] <= t_in_v[active_idx], 0, 1))

        def field(tt, uu, vv):
            x, y = self.to_model(uu + tt, vv + tt)
            return fn(x, y, 64.0 * tt)

        alive = np.ones(t.shape, dtype=bool)
        hit = np.zeros(t.shape, dtype=bool)
        first = np.zeros(t.shape, dtype=bool)
        for step in range(int(steps)):
            if not alive.any():
                break
            d = field(t, gua, gva)
            close = alive & (d < 0.04)
            if step == 0:
                first = close.copy()
            hit |= close
            alive &= ~close
            t = np.where(alive, t - np.maximum(d, 0.02) / RAY_SPEED, t)
            alive &= t > t_end
        if not hit.any():
            return pid
        sel = np.nonzero(hit)[0]
        th, uh, vh = t[sel], gua[sel], gva[sel]
        eps = 0.6

        def grad(du, dv, dz):
            return (field(th + dz / 64.0, uh + du - dz / 64.0, vh + dv - dz / 64.0)
                    - field(th - dz / 64.0, uh - du + dz / 64.0, vh - dv + dz / 64.0))

        nu = grad(eps / Z_METRIC, 0.0, 0.0)
        nv = grad(0.0, eps / Z_METRIC, 0.0)
        nz = grad(0.0, 0.0, eps)
        # Donde el rayo entra ya adentro, la forma está cortada por bounds: normal de esa cara.
        ent = entry[sel]
        cut = first[sel]
        nu = np.where(cut, (ent == 0) * 1.0, nu)
        nv = np.where(cut, (ent == 1) * 1.0, nv)
        nz = np.where(cut, (ent == 2) * 1.0, nz)
        length = np.sqrt(nu ** 2 + nv ** 2 + nz ** 2)
        length = np.where(length > 1.0e-12, length, 1.0)
        nu, nv, nz = nu / length, nv / length, nz / length
        shape = self.alpha.shape

        def full(values, fill=0.0):
            out = np.full(gu.shape, fill, dtype=np.float64)
            out[active_idx[sel]] = values
            return out.reshape(shape)

        ok = np.zeros(gu.shape, dtype=bool)
        ok[active_idx[sel]] = True
        ok = ok.reshape(shape)
        t_full = full(th)
        u = self._gu + t_full
        v = self._gv + t_full
        z = 64.0 * t_full
        nu_f, nv_f, nz_f = full(nu), full(nv), full(nz, 1.0)
        light = nu_f * LIGHT_DIR[0] + nv_f * LIGHT_DIR[1] + nz_f * LIGHT_DIR[2]
        if not ok.any():
            return pid
        x, y = self.to_model(u, v)
        ctx = FaceContext()
        ctx.base = np.broadcast_to(_bands(light, bands or LIGHT_BANDS), shape)
        ctx.a = (x - min(x0, x1)) * 64.0
        ctx.b = z - z0
        ctx.w = abs(x1 - x0) * 64.0
        ctx.h = float(z1 - z0)
        ctx.x = x
        ctx.y = y
        ctx.z = np.broadcast_to(z, shape)
        ctx.sx = self.X
        ctx.sy = self.Y
        inv = self._m.T
        ctx.nx = inv[0, 0] * nu_f + inv[0, 1] * nv_f
        ctx.ny = inv[1, 0] * nu_f + inv[1, 1] * nv_f
        ctx.nz = nz_f
        ctx.light = light
        index = None if tex is None else tex(ctx)
        index = ctx.base if index is None else np.broadcast_to(np.asarray(index).astype(np.int16), shape)
        self._put(ok, np.where(ok, u + v + z / 64.0, _DEPTH_EMPTY), index, pid, rid, u, v, z, ctx.a, ctx.b)
        return pid

    # ------------------------------------------------------------------ salida

    def finish(self):
        """Pasa los índices de rampa a colores (sin acabado: el modelo ya pintó cada pixel)."""
        a = self.alpha
        rgba = np.zeros(a.shape + (4,), dtype=np.uint8)
        for rid, ramp_ in enumerate(self.ramps):
            table = ramp_.table()
            m = a & (self.ramp_id == rid)
            if m.any():
                rgba[m, :3] = table[np.clip(self.shade[m], 0, len(table) - 1)]
        rgba[..., 3] = np.where(a, 255, 0)
        p = self.pad
        inner = np.zeros(a.shape, dtype=bool)
        inner[p:p + self.height, p:p + self.width] = True
        if (a & ~inner).any():
            self.clipped = True
        self.final_shade = self.shade.copy()
        self.final_alpha = a.copy()
        self.result = Image.fromarray(rgba[p:p + self.height, p:p + self.width], "RGBA")
        return self.result

    @property
    def image(self):
        """La imagen terminada (llama a finish() si hace falta)."""
        if self.result is None:
            self.finish()
        return self.result

    def meta(self):
        """Datos del sprite para el manifiesto."""
        arr = np.array(self.image)
        opaque = arr[..., 3] > 0
        data = {"kind": self.kind, "canvas": [self.width, self.height], "anchor": [self.anchor[0], self.anchor[1]],
                "footprint": [1.0, 1.0], "rotation": self.rotation, "clipped": bool(self.clipped), "curved": True,
                "off_grid": [], "flat_faces": []}
        if self.min_z is not None:
            data["min_z"] = round(self.min_z, 2)
        data["colors"] = int(len(np.unique(arr[opaque][:, :3], axis=0))) if opaque.any() else 0
        return data
