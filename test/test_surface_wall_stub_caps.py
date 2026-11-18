#!/usr/bin/env python3
"""The surface_wall hero caps its 8 open wall-end stubs (ivy-b1e.39).

IMPLEMENTATION.md SD-MESH-19.4.3 item C (ratified by the owner 2026-11-18): each wall run of the
surface_wall hero overshoots the perpendicular wall by the 0.09 m kit overshoot. The stub is two
zero-thickness sheets 0.20 m apart (|across| 2.71 and 2.91) running from the neighbour's outer face
(|run| 2.91) to 3.000, open at the end, so the neighbour's outer face is the back of a
0.20 x 0.09 m pocket. tools/build_structures.py now adds ``surface_wall_hero_WallEndCap_<yaw>_<end>``:
a closed plate in the stub's end plane (|run| 2.99 to 3.00), spanning the two sheets with at least
1 mm overlap of each, y 0 to the top of the open sheet end (3.0).

Rays along -x/+x at (+-3.05, 1.0, +-2.81) and along -z/+z at (+-2.81, 1.0, +-3.05) run down the
middle of a stub. On the hero as committed before this bead four of them meet the neighbour's outer
face at 2.910 and four meet a corner block's stone that reaches into the pocket at 2.9532 (the
corner block turned with its corner, ivy-b1e.36). With the caps all eight meet the cap at 3.000.

Every other hero node must be unchanged within 1e-5 m against
test/fixtures/surface_wall_hero_pre_b1e39.json (per-node signatures recorded from the hero as
committed at f733788, the same signature as test_surface_wall_corner_blocks.py).

The test reads a GLB, so it needs no Blender. Run with:
    python3 -m unittest discover -s test -p "test_surface_wall_stub_caps.py"
or point it at another hero (a scratch build):
    python3 test/test_surface_wall_stub_caps.py path/to/surface_wall_hero.glb
Re-record the reference (only when the other hero nodes are meant to change):
    python3 test/test_surface_wall_stub_caps.py --write-reference path/to/surface_wall_hero.glb
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO / "tools"))

import build_growth_surface as bgs  # noqa: E402

HERO = _REPO / "assets" / "structures" / "surface_wall_hero.glb"
REFERENCE = _REPO / "test" / "fixtures" / "surface_wall_hero_pre_b1e39.json"
CAP_TOKEN = "_WallEndCap_"
STUB_END = 3.000
CAP_INNER = 2.99
HIT_TOL = 1e-3
OVERLAP_MIN = 0.001
SAME_TOL = 1e-5
CAP_TOP = 3.0


def _bounds(verts):
    return ([min(v[k] for v in verts) for k in range(3)], [max(v[k] for v in verts) for k in range(3)])


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


def _stubs():
    """(run axis index, end sign, across sign) for the 8 stubs: 0 = x, 2 = z (glTF)."""
    return [(run, end, side) for run in (0, 2) for end in (1, -1) for side in (1, -1)]


def _hero_ok():
    return HERO.is_file() and HERO.read_bytes()[:4] == b"glTF"


@unittest.skipUnless(_hero_ok(), "surface_wall_hero.glb not materialised")
class SurfaceWallStubCapsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.nodes = {name: (verts, tris) for name, verts, tris in bgs.read_glb(HERO)}
        cls.reference = json.loads(REFERENCE.read_text())

    def _first_hit(self, origin, direc):
        best = None
        for name, (verts, tris) in self.nodes.items():
            h = bgs.ray_first_hit(origin, direc, verts, tris)
            if h is not None and (best is None or h < best[0]):
                best = (h, name)
        return best

    def _cast(self, run, end, side, y, across):
        o = [0.0, y, 0.0]
        o[run] = end * (STUB_END + 0.05)
        o[2 - run] = side * across
        d = [0.0, 0.0, 0.0]
        d[run] = -float(end)
        hit = self._first_hit(tuple(o), tuple(d))
        if hit is None:
            return None, None
        return abs(o[run] + d[run] * hit[0]), hit[1]

    def _sheets(self, run, end, side):
        """Measured across-axis faces of the stub's two sheets: the bottom edge of the run's end."""
        across = 2 - run
        vals = set()
        for name, (verts, _t) in self.nodes.items():
            if "_Wall_UnevenBrick_" not in name:
                continue
            for v in verts:
                if end * v[run] > STUB_END - 1e-4 and side * v[across] > 2.5 and abs(v[1]) < 1e-4:
                    vals.add(round(abs(v[across]), 5))
        self.assertEqual(len(vals), 2, f"stub run {run} end {end} side {side}: sheet bottom points {sorted(vals)}")
        return min(vals), max(vals)

    def test_acceptance_rays_meet_the_hero_at_the_stub_end(self):
        report = []
        for run, end, side in _stubs():
            at, name = self._cast(run, end, side, 1.0, 2.81)
            if at is None or abs(at - STUB_END) > HIT_TOL:
                report.append(("xz"[run // 2], end, side, None if at is None else round(at, 4), name))
        self.assertEqual(report, [], f"(run axis, end, side, |hit|, node) not meeting the hero at {STUB_END}: {report}")

    def test_no_ray_down_a_stub_reaches_into_the_pocket(self):
        report = []
        for run, end, side in _stubs():
            lo, hi = self._sheets(run, end, side)
            for y in (0.02, 0.25, 0.5, 0.88, 1.0, 1.5, 2.0, 2.5, 2.8, 2.95):
                for across in (lo + 0.003, (lo + hi) / 2.0, hi - 0.003):
                    at, name = self._cast(run, end, side, y, across)
                    if at is None or at < STUB_END - HIT_TOL:
                        report.append(("xz"[run // 2], end, side, y, round(across, 3), None if at is None else round(at, 4), name))
        self.assertEqual(report, [], f"rays reaching past the stub end plane: {report}")

    def test_eight_closed_caps_span_the_sheets_in_the_end_plane(self):
        caps = {n: vt for n, vt in self.nodes.items() if CAP_TOKEN in n}
        self.assertEqual(len(caps), 8, f"cap nodes: {sorted(caps)}")
        seen = set()
        for run, end, side in _stubs():
            lo_s, hi_s = self._sheets(run, end, side)
            across = 2 - run
            match = []
            for name, (verts, tris) in caps.items():
                lo, hi = _bounds(verts)
                r_lo, r_hi = (lo[run], hi[run]) if end > 0 else (-hi[run], -lo[run])
                a_lo, a_hi = (lo[across], hi[across]) if side > 0 else (-hi[across], -lo[across])
                if r_lo > 2.9 and a_lo > 2.5:
                    match.append((name, verts, tris, r_lo, r_hi, a_lo, a_hi, lo[1], hi[1]))
            self.assertEqual(len(match), 1, f"stub run {run} end {end} side {side}: caps {[m[0] for m in match]}")
            name, verts, tris, r_lo, r_hi, a_lo, a_hi, y_lo, y_hi = match[0]
            seen.add(name)
            wv, wt = bgs.weld(verts, tris)
            self.assertTrue(bgs.is_closed(wt), f"{name} is not closed")
            self.assertEqual(len(bgs.islands(len(wv), wt)), 1, f"{name} is not one solid")
            self.assertGreater(bgs.signed_volume(wv, wt), 0.0, f"{name} is wound inside out")
            self.assertAlmostEqual(r_hi, STUB_END, delta=1e-4, msg=f"{name} outer face")
            self.assertAlmostEqual(r_lo, CAP_INNER, delta=1e-4, msg=f"{name} inner face")
            self.assertLessEqual(a_lo, lo_s - OVERLAP_MIN + 1e-6, f"{name} does not overlap the inner sheet {lo_s} by 1 mm")
            self.assertGreaterEqual(a_hi, hi_s + OVERLAP_MIN - 1e-6, f"{name} does not overlap the outer sheet {hi_s} by 1 mm")
            self.assertLess(a_hi - a_lo, (hi_s - lo_s) + 0.01, f"{name} reaches past the sheets")
            self.assertAlmostEqual(y_lo, 0.0, delta=1e-4, msg=f"{name} bottom")
            self.assertAlmostEqual(y_hi, CAP_TOP, delta=1e-4, msg=f"{name} top")
        self.assertEqual(len(seen), 8)

    def test_every_other_hero_node_is_unchanged(self):
        got = hero_signatures(HERO)
        got_names = {n for n in got if CAP_TOKEN not in n}
        ref_names = set(self.reference)
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
