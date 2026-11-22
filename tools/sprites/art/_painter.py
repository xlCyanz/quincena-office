"""Documento Moana de un PNG ya dibujado, en orden de pintor (lo usan los kits de art/).

Moana limita los nodos de un documento (unos 2000 rectángulos), así que una pieza con mucha textura no
cabe con un rectángulo por tramo de cada color. Aquí cada color pinta tramos que cubren también a los que
se pintan después (que lo tapan) y los tramos iguales de filas seguidas van juntos.
"""

from __future__ import annotations

import numpy as np


def document(doc_id: str, rgba: np.ndarray) -> dict[str, object]:
    """Documento Moana en orden de pintor: una capa por color (del más usado al menos, o de oscuro a claro:
    el orden que dé menos rectángulos). Cada capa
    pinta tramos horizontales que cubren su color y los que se pintan después (que lo tapan), así salen
    muchos menos rectángulos; tramos iguales en filas seguidas van en un solo rectángulo."""
    h, w = rgba.shape[:2]
    alpha = rgba[..., 3] == 255
    flat = rgba[..., :3].reshape(-1, 3)
    keys = (flat[:, 0].astype(np.int64) << 16) | (flat[:, 1].astype(np.int64) << 8) | flat[:, 2]
    keys = np.where(alpha.ravel(), keys, -1).reshape(h, w)
    values, counts = np.unique(keys[alpha], return_counts=True)
    by_count = [int(v) for v in values[np.argsort(-counts, kind="stable")]]
    luma = [((v >> 16) & 255) * 3 + ((v >> 8) & 255) * 6 + (v & 255) for v in by_count]
    by_light = [v for _, v in sorted(zip(luma, by_count))]  # tonos anidados: lo claro suele ir adentro
    order, layers = min(((o, _layers(keys, o)) for o in (by_count, by_light)),
                        key=lambda t: sum(len(layer["operations"]) for layer in t[1]))
    return {
        "schema_version": "1.0",
        "id": doc_id,
        "revision": 0,
        "seed": 0,
        "canvas": {"width": w, "height": h, "profile": "strict"},
        "palette": {"id": f"palette_{doc_id}", "ramps": [],
                    "colors": [{"id": f"c{k}", "rgba": "#%06XFF" % v} for k, v in enumerate(order)]},
        "masks": [],
        "layers": layers,
    }


def _layers(keys: np.ndarray, order: list[int]) -> list[dict[str, object]]:
    """Capas del documento pintando los colores en ese orden."""
    h, w = keys.shape
    rank = np.full((h, w), -1)
    for k, v in enumerate(order):
        rank[keys == v] = k
    layers = []
    for k, v in enumerate(order):
        cover = rank >= k
        spans: dict[tuple[int, int], int] = {}  # (x0, x1) abierto -> fila de arriba
        boxes = []
        for y in range(h + 1):
            row: list[tuple[int, int]] = []
            if y < h:
                x = 0
                while x < w:
                    if cover[y, x]:
                        start = x
                        while x < w and cover[y, x]:
                            x += 1
                        if (rank[y, start:x] == k).any():
                            row.append((start, x))
                    else:
                        x += 1
            for span in list(spans):
                if span not in row:
                    boxes.append((span[0], spans.pop(span), span[1], y))
            for span in row:
                spans.setdefault(span, y)
        ops = [{"id": f"c{k}_{y0}_{x0}", "type": "pixel", "at": [x0, y0], "color": f"c{k}"}
               if (x1 - x0, y1 - y0) == (1, 1) else  # pesa menos en el documento (Moana cuenta nodos)
               {"id": f"c{k}_{y0}_{x0}", "type": "rect", "box": [x0, y0, x1, y1], "color": f"c{k}"}
               for x0, y0, x1, y1 in sorted(boxes, key=lambda b: (b[1], b[0]))]
        layers.append({"id": f"tone{k}", "name": f"Tono {k}", "operations": ops})
    return layers
