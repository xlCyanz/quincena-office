"""Personajes de Quincena Office con Moana: cada cuadro de cada conjunto de ropa (``<estilo>/``), lo que la silla le
tapa al sentarse (``<cuadro>_<silla>``) y la sombra de los pies (``shadow/``). El modelo está en ``_figure.py``.

Cada cuadro se dibuja con ``_figure.build_one``, se revisa con ``_figure.verify`` y se guarda como documento Moana
(``.moana.json``), que tiene que dar los mismos pixeles. Las paletas ``_v1`` y ``_v2`` las cambia
``export_game.py``; aquí solo se comprueba que son un cambio de paleta. Desde el repositorio de Moana:

    sh scripts/uv.sh run python RUTA/tools/sprites/art/characters/build.py [--out DIR] [--only TEXTO]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from typing import Iterator

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # _figure
sys.path.insert(0, str(HERE.parent / "furniture"))  # _chair_kit
sys.path.insert(0, str(HERE.parent))  # _painter
sys.path.insert(0, str(HERE.parents[1]))  # tools/sprites: sheet

import _figure as fg  # noqa: E402
import sheet  # noqa: E402
from _chair_kit import moana_render  # noqa: E402
from _painter import document as painter_document  # noqa: E402

# Defectos conocidos que el dibujo todavía tiene (se avisan sin fallar): nombre -> problema.
KNOWN: dict[str, str] = {}
COMMENT = "Apoyo (px del sprite) y datos de cada PNG de esta carpeta; lo escribe build.py y export_game.py lo pasa al juego."

# ---------------------------------------------------------------------- qué cuadros hay


def jobs() -> Iterator[tuple[str, str, int, str, int]]:
    """(carpeta, estilo, rotación, pose, cuadro) de cada sprite; cuadro 0 = pose quieta sin número."""
    for style in fg.STYLES:
        for pose in (fg.STAND, fg.SIT):
            for rotation in range(4):
                yield style.name, style.name, rotation, pose.name, 0
        kinds = list(fg.ANIMATIONS)
        if style.outfit in fg.CLEANING_STYLES:
            kinds += list(fg.TOOL_ANIMATIONS)
        for kind, make in kinds:
            for rotation in range(4):
                for index in range(len(make())):
                    yield style.name, style.name, rotation, kind, index + 1


def pose_of(kind: str, frame: int) -> object:
    if frame == 0:
        return {"stand": fg.STAND, "sit": fg.SIT}[kind]
    return dict(list(fg.ANIMATIONS) + list(fg.TOOL_ANIMATIONS))[kind]()[frame - 1]


def frame_name(style: fg.Style, kind: str, rotation: int, frame: int) -> str:
    name = "character_%s%s_r%d" % (style.prefix, kind, rotation)
    return name + ("_%d" % frame if frame else "")


# ---------------------------------------------------------------------- dibujo


def draw(job: tuple[str, str, int, str, int]) -> list[tuple[str, str, np.ndarray, dict, list[str]]]:
    """Dibuja un cuadro y, sentado, lo que cada silla le tapa: [(carpeta, nombre, rgba, entrada, problemas)]."""
    folder, style_name, rotation, kind, frame = job
    style = fg.STYLE_BY_NAME[style_name]
    pose = pose_of(kind, frame)
    fig = fg.build_one(rotation, fg.LOOKS[style.name][""], pose, style=style)
    name = frame_name(style, kind, rotation, frame)
    entry = dict(fig.c.meta())
    entry.update({"pose": kind, "style": style.name})
    if frame:
        entry.update({"frame": frame, "frames": len(dict(list(fg.ANIMATIONS) + list(fg.TOOL_ANIMATIONS))[kind]())})
    if pose.sit:
        entry["seat_z"] = fg.SIT_SEAT_Z
    out = [(folder, name, np.array(fig.c.image), entry, fg.verify(fig, name))]
    if pose.sit:
        for chair, rgba in chair_overlays(fig, rotation).items():
            out.append((folder, "%s_%s" % (name, chair), rgba,
                        {"kind": "character_chair", "canvas": [128, 128], "anchor": list(map(float, fg.FEET)),
                         "chair": chair, "rotation": rotation}, []))
    return out


def chair_overlays(fig: fg.Figure, rotation: int) -> dict[str, np.ndarray]:
    """Por silla, la parte que queda delante de la persona sentada (misma casilla, se comparan profundidades)."""
    person = np.array(fig.c.image)
    person_depth = np.array(fig.c.crop(fig.c.depth), dtype=np.float64)
    seen = person[..., 3] > 0
    result = {}
    for spec in fg.CHAIRS:
        chair, chair_depth = chair_arrays(spec, rotation)
        over = seen & (chair[..., 3] > 0) & (chair_depth > person_depth + fg.CHAIR_BIAS)
        image = np.zeros_like(chair)
        image[over] = chair[over]
        result[spec] = image
    return result


_chairs: dict[tuple[str, int], tuple[np.ndarray, np.ndarray]] = {}


def chair_arrays(chair: str, rotation: int) -> tuple[np.ndarray, np.ndarray]:
    """(imagen, profundidad) de una silla de ``art/furniture`` corrida al lienzo del personaje."""
    key = (chair, rotation)
    if key not in _chairs:
        path, _entry = sheet.art_sprites()["%s_r%d.png" % key]
        image = np.array(Image.open(path).convert("RGBA"))
        raw = np.array(Image.open(path[:-len(".png")] + "_depth.png"), dtype=np.float64)
        depth = np.where(raw > 0, raw / fg.DEPTH_SCALE - fg.DEPTH_OFFSET, -1.0e9)
        depth[image[..., 3] == 0] = -1.0e9
        if image[-fg.CHAIR_SHIFT:, :, 3].any():
            raise AssertionError("%s_r%d no cabe en el lienzo del personaje" % key)
        moved_image = np.zeros_like(image)
        moved_depth = np.full(depth.shape, -1.0e9)
        moved_image[fg.CHAIR_SHIFT:] = image[:-fg.CHAIR_SHIFT]
        moved_depth[fg.CHAIR_SHIFT:] = depth[:-fg.CHAIR_SHIFT]
        _chairs[key] = (moved_image, moved_depth)
    return _chairs[key]


def palette_problems() -> list[str]:
    """``_v1`` y ``_v2`` de cada estilo tienen que ser solo otra paleta sobre los mismos tonos."""
    problems = []
    for style in fg.STYLES:
        looks = fg.LOOKS[style.name]
        base = fg.build_one(1, looks[""], style=style)
        for suffix in ("_v1", "_v2"):
            fig = fg.build_one(1, looks[suffix], style=style)
            name = "character_%sstand_r1%s" % (style.prefix, suffix)
            if not (np.array_equal(fig.c.final_shade, base.c.final_shade)
                    and np.array_equal(fig.c.ramp_id, base.c.ramp_id)):
                problems.append("%s: no es solo un cambio de paleta" % name)
            problems += fg.verify(fig, name)
    return problems


def save(out: Path, name: str, rgba: np.ndarray) -> list[str]:
    """PNG y documento Moana; avisa si Moana no da los mismos pixeles."""
    doc = painter_document(name, rgba)
    (out / f"{name}.moana.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
    drawn = moana_render(doc)
    Image.fromarray(drawn, "RGBA").save(out / f"{name}.png")
    return [] if np.array_equal(drawn, rgba) else [f"{name}: Moana no da los mismos pixeles que el dibujo"]


def save_job(job: tuple[str, str, int, str, int], root: str) -> list[tuple[str, str, dict, list[str]]]:
    done = []
    for folder, name, rgba, entry, problems in draw(job):
        out = Path(root) / folder
        out.mkdir(parents=True, exist_ok=True)
        done.append((folder, name, entry, problems + save(out, name, rgba)))
    return done


def main() -> int:
    parser = argparse.ArgumentParser(description="Genera los personajes con Moana.")
    parser.add_argument("--out", type=Path, default=HERE, help="carpeta de salida (por defecto, la del build.py)")
    parser.add_argument("--only", default="", help="solo los estilos que contengan esto (no escribe manifiestos)")
    args = parser.parse_args()
    out: Path = args.out
    todo = [j for j in jobs() if not args.only or args.only in j[1]]
    problems: list[str] = []
    entries: dict[str, dict[str, dict]] = {}
    with ProcessPoolExecutor() as pool:
        for done in pool.map(save_job, todo, [str(out)] * len(todo), chunksize=8):
            for folder, name, entry, found in done:
                entries.setdefault(folder, {})[f"{name}.png"] = entry
                problems += found
    shadow_dir = out / "shadow"
    shadow_dir.mkdir(parents=True, exist_ok=True)
    shadow = np.array(fg.foot_shadow().convert("RGBA"))
    if not shadow[fg.FEET[1], fg.FEET[0], 3]:
        problems.append("character_stand_shadow: no pasa por los pies")
    problems += save(shadow_dir, "character_stand_shadow", shadow)
    entries["shadow"] = {"character_stand_shadow.png": {"kind": "shadow", "canvas": [128, 128], "footprint": [1, 1],
                                                        "anchor": list(map(float, fg.FEET))}}
    problems += palette_problems()
    if not args.only:
        for folder, sprites in entries.items():
            manifest = {"_comentario": COMMENT, "sprites": dict(sorted(sprites.items()))}
            (out / folder / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n",
                                                        encoding="utf-8")
    known = [p for p in problems if any(p.startswith(n + ": " + what) for n, what in KNOWN.items())]
    problems = [p for p in problems if p not in known]
    for line in known:
        print("aviso:", line)
    for line in problems:
        print("FALLO:", line)
    print(f"{sum(len(s) for s in entries.values())} sprites")
    print("RESULTADO:", "OK" if not problems else f"{len(problems)} fallos")
    return 1 if problems else 0


if __name__ == "__main__":
    os.environ.setdefault("PYTHONDONTWRITEBYTECODE", "1")
    sys.exit(main())
