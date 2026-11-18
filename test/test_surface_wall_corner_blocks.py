#!/usr/bin/env python3
"""Each surface_wall hero corner block turns with its corner (ivy-b1e.36).

IMPLEMENTATION.md AR-MESH-20.13: in tools/build_structures.py, place_corner_trim turns each wide
corner trim to face its corner (yaw 0, 90, 180, 270), but hero_corner_block set no rotation, so
CornerBlock_<storey>_<i> all sat at yaw 0 and at corners 2 and 3 the block and the trim read as two
separate pillars. CornerBlock_<storey>_<i> stands at corner_centers[i], the corner of
corner_locs[90*i], so it now takes yaw 90*i and every corner looks like corner 0 (+x +z in glTF).

The hero is symmetric under a quarter turn about the structure's vertical axis (scene_offset is
zero for surface_wall), so in glTF (y up) every vertex of CornerBlock_0_i must equal the matching
vertex of CornerBlock_0_0 turned 90*i degrees about +y, within 1 mm.

Every other hero node must be unchanged within 1e-5 m. The reference is
test/fixtures/surface_wall_hero_pre_b1e36.json: per-node signatures (vertex count, world bounds,
mean and mean square of the world vertices) recorded from the hero as committed before this bead
(commit 32ce5ee). It is a fixed record rather than "the committed hero", so the check keeps its
meaning after the rebuilt hero is installed. CornerBlock_0_0 is in that reference too: corner 0
must not move.

The test reads a GLB, so it needs no Blender. Run with:
    python3 -m unittest discover -s test -p "test_surface_wall_corner_blocks.py"
or point it at another hero (a scratch build):
    python3 test/test_surface_wall_corner_blocks.py path/to/surface_wall_hero.glb
Re-record the reference (only when the other hero nodes are meant to change):
    python3 test/test_surface_wall_corner_blocks.py --write-reference path/to/surface_wall_hero.glb
"""

from __future__ import annotations

import json
import math
import sys
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO / "tools"))

import build_growth_surface as bgs  # noqa: E402

HERO = _REPO / "assets" / "structures" / "surface_wall_hero.glb"
REFERENCE = _REPO / "test" / "fixtures" / "surface_wall_hero_pre_b1e36.json"
PREFIX = "surface_wall_hero_CornerBlock_0_"
TURN_TOL = 1e-3
SAME_TOL = 1e-5


def _turn_y(v, deg):
    """Turn a glTF point about +y by deg (right hand: +x goes towards -z)."""
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    x, y, z = v
    return (x * c + z * s, y, -x * s + z * c)


def node_signature(verts):
    n = len(verts)
    return {
        "count": n,
        "min": [min(v[k] for v in verts) for k in range(3)],
        "max": [max(v[k] for v in verts) for k in range(3)],
        "mean": [sum(v[k] for v in verts) / n for k in range(3)],
        "mean_sq": [sum(v[k] * v[k] for v in verts) / n for k in range(3)],
    }


def hero_signatures(path):
    return {name: node_signature(verts) for name, verts, _tris in bgs.read_glb(path) if verts}


def _hero_ok():
    return HERO.is_file() and HERO.read_bytes()[:4] == b"glTF"


@unittest.skipUnless(_hero_ok(), "surface_wall_hero.glb not materialised")
class SurfaceWallCornerBlocksTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.nodes = {name: verts for name, verts, _tris in bgs.read_glb(HERO)}
        cls.reference = json.loads(REFERENCE.read_text())

    def _block(self, i):
        name = f"{PREFIX}{i}"
        self.assertIn(name, self.nodes, f"no {name}; corner nodes: {sorted(n for n in self.nodes if 'Corner' in n)}")
        return self.nodes[name]

    def test_each_corner_block_is_corner_0_turned_with_its_corner(self):
        v0 = self._block(0)
        report = []
        for i in (1, 2, 3):
            vi = self._block(i)
            self.assertEqual(len(vi), len(v0), f"CornerBlock_0_{i} vertex count differs from CornerBlock_0_0")
            worst = max(
                max(abs(a - b) for a, b in zip(_turn_y(p, 90.0 * i), q)) for p, q in zip(v0, vi)
            )
            if worst > TURN_TOL:
                report.append((i, round(worst, 4)))
        self.assertEqual(report, [], f"(corner, worst vertex error m) not equal to corner 0 turned 90*i about +y: {report}")

    def test_every_other_hero_node_is_unchanged(self):
        turned = {f"{PREFIX}{i}" for i in (1, 2, 3)}
        ref_names = set(self.reference) - turned
        got = hero_signatures(HERO)
        got_names = set(got) - turned
        self.assertEqual(sorted(got_names ^ ref_names), [], "hero node set differs from the pre-bead hero")
        moved = []
        for name in sorted(ref_names):
            ref, sig = self.reference[name], got[name]
            if ref["count"] != sig["count"]:
                moved.append((name, "count", ref["count"], sig["count"]))
                continue
            for key in ("min", "max", "mean", "mean_sq"):
                err = max(abs(a - b) for a, b in zip(ref[key], sig[key]))
                if err > SAME_TOL:
                    moved.append((name, key, round(err, 6)))
        self.maxDiff = None
        self.assertEqual(moved, [], f"hero nodes that changed: {moved}")


def _write_reference(path):
    sigs = hero_signatures(path)
    REFERENCE.parent.mkdir(parents=True, exist_ok=True)
    rounded = {
        n: {k: (v if k == "count" else [round(x, 7) for x in v]) for k, v in s.items()}
        for n, s in sorted(sigs.items())
    }
    REFERENCE.write_text(json.dumps(rounded, indent=1) + "\n")
    print(f"wrote {len(rounded)} node signatures from {path} to {REFERENCE}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--write-reference":
        _write_reference(Path(args[1]) if len(args) > 1 else HERO)
        sys.exit(0)
    if args and not args[0].startswith("-"):
        HERO = Path(args.pop(0)).resolve()
    unittest.main(argv=[sys.argv[0]] + args)
