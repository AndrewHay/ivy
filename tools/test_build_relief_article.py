#!/usr/bin/env python3
"""Self-test for tools/build_relief_article.py (ivy-b1e.6, SD-MESH-19.5).

Usage (project root): python3 tools/test_build_relief_article.py

Checks the article hero against the SD-MESH-19.5 table by point classification (ray parity on
the written solids, not on the table the builder was written from), the AR-MESH-20.3 rule 8
overlap between solids, that tools/build_growth_surface.py accepts the hero with the declared S1
filler and rejects it without, the fillet wedges of the r025 / r050 variants, the bounding-box
variant, and the CLI.
"""

from __future__ import annotations

import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

import build_growth_surface as bgs  # noqa: E402
import build_relief_article as bra  # noqa: E402


# ------------------------------------------------------------------------------------------------
# helpers: point-in-solid by ray parity over a set of closed meshes
# ------------------------------------------------------------------------------------------------


def _ray_tri(o, d, a, b, c):
    e1 = bgs.sub(b, a)
    e2 = bgs.sub(c, a)
    p = bgs.cross(d, e2)
    det = bgs.dot(e1, p)
    if abs(det) < 1e-14:
        return None
    inv = 1.0 / det
    s = bgs.sub(o, a)
    u = bgs.dot(s, p) * inv
    if u < 0.0 or u > 1.0:
        return None
    q = bgs.cross(s, e1)
    v = bgs.dot(d, q) * inv
    if v < 0.0 or u + v > 1.0:
        return None
    t = bgs.dot(e2, q) * inv
    return t if t > 1e-12 else None


# An irrational-ish direction so the ray never runs along a box edge or face.
_DIR = bgs.norm((0.5773, 0.4123, 0.7071))


def inside_mesh(p, verts, tris):
    hits = 0
    for a, b, c in tris:
        if _ray_tri(p, _DIR, verts[a], verts[b], verts[c]) is not None:
            hits += 1
    return hits % 2 == 1


def inside_any(p, meshes):
    return any(inside_mesh(p, v, t) for _n, v, t in meshes)


def _bounds(meshes):
    lo = [math.inf] * 3
    hi = [-math.inf] * 3
    for _n, verts, _t in meshes:
        for v in verts:
            for k in range(3):
                lo[k] = min(lo[k], v[k])
                hi[k] = max(hi[k], v[k])
    return lo, hi


# Points inside the article solid / in the air, from the SD-MESH-19.5 table (glTF = Godot axes).
SOLID_POINTS = {
    "wall flat zone": (0.0, 1.0, -0.01),
    "wall back": (0.0, 1.0, -0.44),
    "behind N1 floor": (0.60, 1.0, -0.21),
    "behind M1 floor": (1.28, 0.75, -0.07),
    "behind S1 floor": (1.52, 2.0, -0.11),
    "rib R1": (-1.575, 1.0, 0.05),
    "rib R4": (-0.225, 2.5, 0.09),
    "rail H1 mid bay": (-0.90, 1.50, 0.05),
    "plaque U1": (0.60, 2.30, 0.01),
    "left of S1": (1.49, 2.0, -0.05),
    "right of S1": (1.55, 2.0, -0.05),
}
AIR_POINTS = {
    "in front of flat zone": (0.0, 1.0, 0.01),
    "N1 interior": (0.60, 1.0, -0.10),
    "N1 just above floor": (0.60, 1.0, -0.195),
    "M1 interior": (1.28, 0.75, -0.03),
    "S1 interior": (1.52, 2.0, -0.05),
    "panel in middle bay": (-0.90, 1.0, 0.05),
    "panel above rail": (-0.90, 2.0, 0.05),
    "in front of rib": (-1.575, 1.0, 0.11),
    "in front of plaque": (0.60, 2.30, 0.03),
    "beyond the end": (1.81, 1.0, -0.2),
    "above the top": (0.0, 3.01, -0.2),
}


class TestHero(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.hero = bra.hero_meshes()

    def test_every_hero_solid_is_closed_and_wound_outward(self):
        self.assertGreater(len(self.hero), 7)
        for name, verts, tris in self.hero:
            wv, wt = bgs.weld(verts, tris)
            self.assertTrue(bgs.is_closed(wt), name)
            self.assertGreater(bgs.signed_volume(wv, wt), 0.0, name)
            self.assertTrue(name.startswith("relief_article_hero_"), name)

    def test_named_parts_of_the_table_exist(self):
        names = [n for n, _v, _t in self.hero]
        for part in ("Rib_R1", "Rib_R2", "Rib_R3", "Rib_R4", "Rail_H1", "Plaque_U1"):
            self.assertEqual(sum(1 for n in names if n.endswith(part)), 1, part)
        self.assertTrue(any("Wall_Body" in n for n in names))

    def test_bounds_are_the_table_bounds(self):
        lo, hi = _bounds(self.hero)
        for k, (a, b) in enumerate(((-1.80, 1.80), (0.0, 3.0), (-0.45, 0.10))):
            self.assertAlmostEqual(lo[k], a, places=6)
            self.assertAlmostEqual(hi[k], b, places=6)

    def test_solid_points_are_inside(self):
        for label, p in SOLID_POINTS.items():
            self.assertTrue(inside_any(p, self.hero), label)

    def test_air_points_are_outside(self):
        for label, p in AIR_POINTS.items():
            self.assertFalse(inside_any(p, self.hero), label)

    def test_recess_floors_and_proud_faces_are_where_the_table_puts_them(self):
        # One step either side of each defining plane.
        eps = 0.002
        planes = [
            ((0.60, 1.0), -0.20, "N1 floor"),
            ((1.28, 0.75), -0.06, "M1 floor"),
            ((1.52, 2.0), -0.10, "S1 floor"),
            ((-0.90, 1.0), 0.0, "panel floor"),
            ((-1.575, 1.0), 0.10, "rib face"),
            ((-0.90, 1.50), 0.10, "rail face"),
            ((0.60, 2.30), 0.02, "plaque face"),
        ]
        for (x, y), z, label in planes:
            self.assertTrue(inside_any((x, y, z - eps), self.hero), label + " solid below")
            self.assertFalse(inside_any((x, y, z + eps), self.hero), label + " air above")

    def test_solids_that_meet_overlap_by_at_least_1mm(self):
        # AR-MESH-20.3 rule 8: no two solids share a face patch wider than 1 mm both ways.
        boxes = bra.hero_boxes()
        for i in range(len(boxes)):
            for j in range(i + 1, len(boxes)):
                ni, lo_i, hi_i = boxes[i]
                nj, lo_j, hi_j = boxes[j]
                ext = [min(hi_i[k], hi_j[k]) - max(lo_i[k], lo_j[k]) for k in range(3)]
                if any(e < -1e-9 for e in ext):
                    continue  # apart
                zero = [k for k in range(3) if abs(ext[k]) <= 1e-9]
                if len(zero) != 1:
                    continue  # overlapping volume, or edge / point contact
                others = [ext[k] for k in range(3) if k != zero[0]]
                self.assertLessEqual(min(others), 0.001 + 1e-9,
                                     f"{ni} and {nj} share a face {others[0]:.4f} x {others[1]:.4f} m")
            for k in range(3):
                self.assertLess(boxes[i][1][k], boxes[i][2][k])


class TestGrowthSurfaceBuild(unittest.TestCase):
    """The sharp variant is tools/build_growth_surface.py output: S1 closed by the declared fill."""

    @classmethod
    def setUpClass(cls):
        cls.centre, cls.settings = bgs.load_structure(bra.CONFIG_PATH, bra.STRUCTURE)
        cls.hero = bra.hero_meshes()

    def test_config_declares_the_s1_filler_only(self):
        fills = self.settings["fill"]
        self.assertEqual([f["name"] for f in fills], ["S1"])
        lo, hi = fills[0]["min"], fills[0]["max"]
        self.assertLessEqual(lo[0], 1.50 - 0.001)
        self.assertGreaterEqual(hi[0], 1.54 + 0.001)
        self.assertLessEqual(lo[1], 1.50 - 0.001)
        self.assertGreaterEqual(hi[1], 2.50 + 0.001)
        self.assertLessEqual(lo[2], -0.10 - 0.001)
        self.assertAlmostEqual(hi[2], 0.0, places=9)
        self.assertEqual(self.settings["envelope"], [])
        self.assertEqual(self.settings["exempt"], [])

    def test_tool_builds_the_hero_with_no_slot(self):
        meshes, report = bgs.build(self.hero, [], bra.STRUCTURE, self.centre, self.settings)
        self.assertEqual(report["slots"], [])
        self.assertEqual(report["failures"], [])
        self.assertEqual(report["rules"]["1_closed"], len(self.hero))
        self.assertEqual(report["rules"]["fill"], 1)
        names = [n for n, _v, _t in meshes]
        self.assertIn("relief_article_sim_Fill_S1_i00", names)
        self.assertIn("relief_article_sim_Plaque_U1_i00", names, "U1 is left to the tool, which keeps it")
        # The proxy is the hero plus the filler: S1 is solid, everything else is unchanged.
        self.assertTrue(inside_any(AIR_POINTS["S1 interior"], meshes))
        for label in ("N1 interior", "M1 interior", "panel in middle bay"):
            self.assertFalse(inside_any(AIR_POINTS[label], meshes), label)

    def test_tool_rejects_the_hero_without_the_filler(self):
        st = dict(self.settings)
        st["fill"] = []
        with self.assertRaises(bgs.BuildError) as ctx:
            bgs.build(self.hero, [], bra.STRUCTURE, self.centre, st)
        slots = ctx.exception.report["slots"]
        self.assertTrue(slots, "the slot check must find S1")
        for s in slots:
            x, y, z = s["position"]
            self.assertTrue(1.49 <= x <= 1.55 and 1.49 <= y <= 2.51 and -0.11 <= z <= 0.0, s)
            self.assertAlmostEqual(s["width"], 0.04, places=3)


class TestFilletVariants(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        centre, settings = bgs.load_structure(bra.CONFIG_PATH, bra.STRUCTURE)
        cls.sharp, _r = bgs.build(bra.hero_meshes(), [], bra.STRUCTURE, centre, settings)

    def test_inside_corner_lines_cover_ribs_rail_and_recesses(self):
        lines = bra.inside_corner_lines()
        # 8 rib-to-wall lines split at the rail on the six bay-facing sides (2 + 6 x 2 = 14),
        # 6 rail-to-wall bay segments, 12 rib-to-rail verticals, 2 x (4 floor + 4 vertical) recess lines.
        self.assertEqual(len(lines), 14 + 6 + 12 + 16)
        for a, b, e1, e2 in lines:
            self.assertAlmostEqual(bgs.dot(e1, e2), 0.0, places=9)
            self.assertAlmostEqual(bgs.dot(bgs.sub(b, a), e1), 0.0, places=9)
            self.assertAlmostEqual(bgs.dot(bgs.sub(b, a), e2), 0.0, places=9)
            # The corner is concave: one step along both face directions is air.
            mid = bgs.mul(bgs.add(a, b), 0.5)
            probe = bgs.add(mid, bgs.mul(bgs.add(e1, e2), 0.01))
            self.assertFalse(inside_any(probe, self.sharp), (a, b))

    def test_wedges_are_closed_and_fill_the_corner_to_the_radius(self):
        for r in (0.025, 0.05):
            wedges = bra.fillet_meshes(r)
            self.assertEqual(len(wedges), len(bra.inside_corner_lines()) * bra.FILLET_CHORDS)
            for name, verts, tris in wedges:
                self.assertTrue(name.startswith("relief_article_sim_Fillet_"), name)
                wv, wt = bgs.weld(verts, tris)
                self.assertTrue(bgs.is_closed(wt), name)
                self.assertGreater(bgs.signed_volume(wv, wt), 0.0, name)
        # Bay floor beside rib R2's right face (x = -1.05), below the rail: 1 cm out, 1 cm up.
        p = (-1.05 + 0.01, 1.0, 0.01)
        self.assertTrue(inside_any(p, bra.fillet_meshes(0.05)), "inside the 0.05 m fillet")
        self.assertFalse(inside_any(p, bra.fillet_meshes(0.025)), "outside the 0.025 m fillet")
        # Fillets never reach past their radius.
        q = (-1.05 + 0.03, 1.0, 0.03)
        self.assertFalse(inside_any(q, bra.fillet_meshes(0.05)))

    def test_bbox_variant_is_one_box_over_the_article(self):
        meshes = bra.bbox_meshes()
        self.assertEqual(len(meshes), 1)
        lo, hi = _bounds(meshes)
        for k, (a, b) in enumerate(((-1.80, 1.80), (0.0, 3.0), (-0.45, 0.10))):
            self.assertAlmostEqual(lo[k], a, places=6)
            self.assertAlmostEqual(hi[k], b, places=6)


class TestCli(unittest.TestCase):
    def test_hero_then_fillets_writes_every_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            r = subprocess.run([sys.executable, str(TOOLS / "build_relief_article.py"), "hero", str(out)],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            hero = bgs.read_glb(out / "relief_article_hero.glb")
            self.assertEqual(len(hero), len(bra.hero_boxes()))
            self.assertEqual(len(bgs.read_glb(out / "relief_article_bbox_sim.glb")), 1)
            sharp = out / "relief_article_sim.glb"
            r = subprocess.run([sys.executable, str(TOOLS / "build_growth_surface.py"),
                                str(out / "relief_article_hero.glb"), str(out / "relief_article_hero.glb"),
                                str(sharp), "--structure", "relief_article", "--config", str(bra.CONFIG_PATH)],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            r = subprocess.run([sys.executable, str(TOOLS / "build_relief_article.py"), "fillets", str(sharp),
                                str(out)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            n_sharp = len(bgs.read_glb(sharp))
            n_wedges = len(bra.inside_corner_lines()) * bra.FILLET_CHORDS
            for tag in ("r025", "r050"):
                self.assertEqual(len(bgs.read_glb(out / f"relief_article_{tag}_sim.glb")), n_sharp + n_wedges)
            # Deterministic: a second run writes the same bytes.
            first = (out / "relief_article_hero.glb").read_bytes()
            subprocess.run([sys.executable, str(TOOLS / "build_relief_article.py"), "hero", str(out)], check=True,
                           capture_output=True)
            self.assertEqual((out / "relief_article_hero.glb").read_bytes(), first)

    def test_usage_errors_exit_2(self):
        r = subprocess.run([sys.executable, str(TOOLS / "build_relief_article.py")], capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main(verbosity=1)
