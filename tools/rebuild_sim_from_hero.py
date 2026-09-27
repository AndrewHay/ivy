#!/usr/bin/env python3
"""Rebuild Sim_{name} from Hero_{name} transforms, export GLBs, save blend.

Thin wrapper around ``build_structures.py --rebuild-sim-from-blend``.

Usage (from project root)::

  python3 tools/rebuild_sim_from_hero.py assets/structures/tower.blend assets/structures tower

After this, re-bake SDF and run gate measurements::

  python3 tools/bake_mesh_sdf.py assets/structures/tower_sim.glb assets/structures/tower_sim.sdf
  python3 tools/measure_structure_gates.py tower
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BLENDER = "/Applications/Blender.app/Contents/MacOS/Blender"
BUILD = ROOT / "tools" / "build_structures.py"
DEFAULT_KIT = ROOT / "assets" / "_local" / "medieval_village_megakit" / "glTF"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("blend", type=Path, help="Canonical structure .blend path (updated in place)")
    parser.add_argument("out_dir", type=Path, help="Directory for exported {name}_{hero,sim}.glb")
    parser.add_argument("structure", help="Structure id (e.g. tower, square)")
    parser.add_argument(
        "--kit",
        type=Path,
        default=DEFAULT_KIT,
        help="Quaternius kit glTF directory (required argv for build_structures)",
    )
    args = parser.parse_args()

    blend = args.blend if args.blend.is_absolute() else ROOT / args.blend
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    kit = args.kit if args.kit.is_absolute() else ROOT / args.kit

    if not blend.is_file():
        print(f"blend not found: {blend}", file=sys.stderr)
        return 2
    if not kit.is_dir():
        print(f"kit glTF dir not found: {kit}", file=sys.stderr)
        return 2

    cmd = [
        BLENDER,
        "--background",
        "--python",
        str(BUILD),
        "--",
        str(kit),
        str(out_dir),
        "--rebuild-sim-from-blend",
        str(blend),
        args.structure,
    ]
    print("running:", " ".join(cmd), flush=True)
    return subprocess.call(cmd)


if __name__ == "__main__":
    raise SystemExit(main())
