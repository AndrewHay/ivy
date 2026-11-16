#!/usr/bin/env python3
"""The tower hero closes the top of its wall hollow with a wall-top cap (ivy-b1e.33).

IMPLEMENTATION.md SD-MESH-19.4.2, "The tower's two samples": the tower's walls are two kit skins
about 0.20 m apart with open tops, and RoofCone covers only the circle inscribed in the outer
faces, so the hollow between the skins was open to the sky along each wall and at the four
corners. tools/build_structures.py now adds ``tower_hero_WallTopCap``: one closed solid, square in
plan on the tower axis, outer half-width ``roof_half`` (flush with the outer skins), inner edge
inside the inner skins' faces by at least 1 mm, top at ``total_h`` (the cone's base), at least
0.02 m thick. This test reads the committed hero GLB, so it needs no Blender.

Run with:
    python3 -m unittest discover -s test -p "test_tower_wall_top_cap.py"
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO / "tools"))

import build_growth_surface as bgs  # noqa: E402

_HERO = _REPO / "assets" / "structures" / "tower_hero.glb"
_CAP = "tower_hero_WallTopCap"
_CONE = "tower_hero_RoofCone"
WALL_H = 3.12  # tools/build_structures.py
OVERLAP_MIN = 0.001  # the growth-surface builder's overlap rule
THICK_MIN = 0.02
TOL = 1e-3


def _tower_cfg():
    return json.loads((_REPO / "tools" / "structure_configs.json").read_text())["tower"]


def _bounds(verts):
    return ([min(v[k] for v in verts) for k in range(3)], [max(v[k] for v in verts) for k in range(3)])


@unittest.skipUnless(_HERO.is_file() and _HERO.read_bytes()[:4] == b"glTF", "tower_hero.glb not materialised")
class TowerWallTopCapTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.nodes = {name: (verts, tris) for name, verts, tris in bgs.read_glb(_HERO)}
        cfg = _tower_cfg()
        # scene_offset is Blender (x, y, z-up); the GLB is glTF (x, z-up -> y, -y -> z).
        bx, by, bz = (float(v) for v in cfg["scene_offset"])
        cls.cx, cls.cz = bx, -by
        cls.roof_half = float(cfg["roof_half"])
        cls.total_h = cfg["storeys"] * WALL_H + bz

    def _cap(self):
        self.assertTrue(_CAP in self.nodes, f"no wall-top cap node; hero nodes: {sorted(self.nodes)}")
        return self.nodes[_CAP]

    def test_cap_is_one_closed_solid(self):
        verts, tris = self._cap()
        wv, wt = bgs.weld(verts, tris)
        self.assertTrue(bgs.is_closed(wt), "wall-top cap is not closed")
        self.assertEqual(len(bgs.islands(len(wv), wt)), 1, "wall-top cap is not one solid")
        self.assertGreater(bgs.signed_volume(wv, wt), 0.0, "wall-top cap is wound inside out")

    def test_cap_outer_bounds_square_on_axis_flush_with_outer_skins(self):
        lo, hi = _bounds(self._cap()[0])
        r = self.roof_half
        self.assertAlmostEqual(lo[0], self.cx - r, delta=TOL)
        self.assertAlmostEqual(hi[0], self.cx + r, delta=TOL)
        self.assertAlmostEqual(lo[2], self.cz - r, delta=TOL)
        self.assertAlmostEqual(hi[2], self.cz + r, delta=TOL)

    def test_cap_top_at_wall_top_touching_cone_base_and_thick_enough(self):
        lo, hi = _bounds(self._cap()[0])
        self.assertAlmostEqual(hi[1], self.total_h, delta=TOL)
        cone_lo, _ = _bounds(self.nodes[_CONE][0])
        self.assertLessEqual(hi[1], cone_lo[1] + TOL, "cap rises above the cone's base")
        self.assertGreaterEqual(hi[1] - lo[1], THICK_MIN - 1e-6)

    def _inner_skin_face(self):
        """Largest distance from the axis of the inner skin, over the top storey's wall pieces, at
        the cap's height: the hollow-side edge the cap must overlap (measured, not assumed)."""
        lo, hi = _bounds(self._cap()[0])
        worst = 0.0
        for name, (verts, _tris) in self.nodes.items():
            if "_Wall_UnevenBrick_" not in name:
                continue
            wlo, whi = _bounds(verts)
            if whi[1] < self.total_h - 0.5:
                continue  # lower storey
            # The wall's thickness runs along its thin plan axis (x for the 90/270 walls).
            axis = 0 if whi[0] - wlo[0] < whi[2] - wlo[2] else 2
            centre = self.cx if axis == 0 else self.cz
            for v in verts:
                if not (lo[1] - TOL <= v[1] <= hi[1] + TOL):
                    continue
                d = abs(v[axis] - centre)
                if d < self.roof_half - 0.10:  # inner skin (the outer skin sits at roof_half)
                    worst = max(worst, d)
        self.assertGreater(worst, 1.4, "inner skin not found")
        return worst

    def test_cap_inner_edge_overlaps_inner_skins(self):
        verts, _ = self._cap()
        inner = self._inner_skin_face()
        # Inner hole half-width: the largest |d| of the cap's vertices strictly inside the outer edge.
        hole = max(
            max(abs(v[0] - self.cx), abs(v[2] - self.cz))
            for v in verts
            if max(abs(v[0] - self.cx), abs(v[2] - self.cz)) < self.roof_half - 0.05
        )
        self.assertLessEqual(hole, inner - OVERLAP_MIN,
                             f"cap inner edge {hole:.4f} does not overlap the inner skin face {inner:.4f} by 1 mm")

    def _first_hit_down(self, x, z, y0=None):
        y0 = self.total_h + 3.0 if y0 is None else y0
        origin, direc = (x, y0, z), (0.0, -1.0, 0.0)
        best, best_name = None, None
        for name, (verts, tris) in self.nodes.items():
            lo, hi = _bounds(verts)
            if not (lo[0] - TOL <= x <= hi[0] + TOL and lo[2] - TOL <= z <= hi[2] + TOL):
                continue
            hit = bgs.ray_first_hit(origin, direc, verts, tris)
            if hit is not None and (best is None or hit < best):
                best, best_name = hit, name
        return best_name, best

    def test_spec_down_casts_over_the_former_samples_hit_the_cap(self):
        # SD-MESH-19.4.2 done-when: casts down from 3 m above at x 5.26-5.41, z +-1.45 (west
        # wall, over the two former samples) hit the cap. z +-1.45 lies over the north and south
        # walls' inner top beam, whose top stands up to 2.7 mm above total_h in places (kit
        # geometry, y 6.2427), so a cast may graze that beam first; nothing below the wall top
        # may come before the cap.
        y0 = self.total_h + 3.0
        cap_v, cap_t = self._cap()
        misses = []
        for x in (5.26, 5.30, 5.35, 5.41):
            for z in (1.45, -1.45):
                t_cap = bgs.ray_first_hit((x, y0, z), (0.0, -1.0, 0.0), cap_v, cap_t)
                name, t = self._first_hit_down(x, z)
                if t_cap is None or y0 - t < self.total_h - TOL:
                    misses.append(((x, z), name, None if t is None else round(y0 - t, 4), t_cap))
        self.maxDiff = None
        self.assertEqual(misses, [], f"down-casts that do not hit the cap first: {misses}")

    def test_no_part_of_the_hollow_is_open_to_the_sky(self):
        # Across the hollow of all four walls, corners included, a down-cast meets the cap (or
        # the cone where the cone stands above it) at the wall top, never the hollow. Hero that
        # stands at the wall top within 1 cm (the kit's top beams) also counts as closed.
        y0 = self.total_h + 3.0
        offs = [1.59, 1.64, 1.69, 1.74]  # across the hollow, from the axis (outer skin at 1.76)
        along = [k * 0.25 for k in range(-7, 8)] + [-1.74, -1.66, -1.59, 1.59, 1.66, 1.74]
        open_ = []
        for a in offs:
            for s in along:
                for x, z in ((self.cx - a, self.cz + s), (self.cx + a, self.cz + s),
                             (self.cx + s, self.cz - a), (self.cx + s, self.cz + a)):
                    name, t = self._first_hit_down(x, z)
                    if name is None or y0 - t < self.total_h - 0.01:
                        open_.append(((round(x, 3), round(z, 3)), name, None if t is None else round(y0 - t, 4)))
        self.maxDiff = None
        self.assertEqual(open_, [], f"down-casts into the open hollow: {open_}")


if __name__ == "__main__":
    unittest.main()
