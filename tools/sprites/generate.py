#!/usr/bin/env python3
# Genera los sprites: corre cada pieces/<grupo>.py (build(out_dir), guarda con iso.save; los "_" no se corren)
# y escribe sus PNG y manifest_<grupo>.json, que usa check.py (--check lo corre al final).
#   python3 tools/sprites/generate.py --out DIR [--only grupo[,grupo…]] [--check] [--list]
import argparse
import importlib
import os
import sys
import time
import traceback

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import check  # noqa: E402
import iso  # noqa: E402


def discover():
    """Nombres de los grupos (módulos de pieces/ que no empiezan con '_'), en orden."""
    folder = os.path.join(HERE, "pieces")
    if not os.path.isdir(folder):
        return []
    names = []
    for entry in sorted(os.listdir(folder)):
        if entry.endswith(".py") and not entry.startswith("_"):
            names.append(entry[:-3])
    return names


def run_group(name, out_dir):
    """Corre un grupo. Devuelve (archivos escritos, error o None)."""
    iso.reset_registry()
    try:
        module = importlib.import_module("pieces." + name)
        if not hasattr(module, "build"):
            return [], "pieces/%s.py no tiene build(out_dir)" % name
        files = module.build(out_dir)
    except Exception:  # una pieza rota no debe frenar a las demás
        return [], traceback.format_exc()
    files = list(files or [])
    saved = set(os.path.join(out_dir, entry["file"]) for entry in iso.registry())
    extra = [f for f in files if os.path.abspath(f) not in set(os.path.abspath(s) for s in saved)]
    iso.write_manifest(out_dir, name)
    note = None
    if extra:
        note = "aviso: %d archivos devueltos no se guardaron con iso.save (sin manifiesto): %s" % (
            len(extra), ", ".join(os.path.basename(f) for f in extra[:5]))
    return files, note


def main():
    parser = argparse.ArgumentParser(description="Genera los sprites de tools/sprites/pieces/.")
    parser.add_argument("--out", default=None, help="carpeta donde se escriben los PNG (obligatoria salvo con --list)")
    parser.add_argument("--only", default="", help="grupos a generar, separados por coma (nombre del módulo)")
    parser.add_argument("--check", action="store_true", help="corre check.py sobre la carpeta al terminar")
    parser.add_argument("--list", action="store_true", help="solo lista los grupos que hay")
    args = parser.parse_args()
    groups = discover()
    if args.list:
        for name in groups:
            print(name)
        return 0
    if not args.out:
        parser.error("falta --out DIR (los PNG no se escriben en el repositorio)")
    wanted = [g.strip() for g in args.only.split(",") if g.strip()]
    unknown = [g for g in wanted if g not in groups]
    if unknown:
        print("No existe el grupo: %s (hay: %s)" % (", ".join(unknown), ", ".join(groups) or "ninguno"))
        return 1
    if wanted:
        groups = [g for g in groups if g in wanted]
    out_dir = os.path.abspath(args.out)
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    failed = False
    total = 0
    for name in groups:
        start = time.time()
        files, problem = run_group(name, out_dir)
        if problem and not files:
            failed = True
            print("ERROR  %s:\n%s" % (name, problem))
            continue
        total += len(files)
        print("%-20s %3d archivos  %.1f s" % (name, len(files), time.time() - start))
        if problem:
            print("  " + problem)
    print("%d archivos en %s (%d grupos)" % (total, out_dir, len(groups)))
    status = 1 if failed else 0
    if args.check:
        # Con --only, solo esos grupos: otro puede estar generando en la misma carpeta.
        status = max(status, check.run(out_dir, groups=groups if wanted else None))
    return status


if __name__ == "__main__":
    sys.exit(main())
