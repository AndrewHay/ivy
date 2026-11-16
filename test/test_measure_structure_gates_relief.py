#!/usr/bin/env python3
"""Gate 3's SD-OPEN-27(d) relief exemption applies only to Blender-built proxies (ivy-b1e.7), and
the gates probe the cottage where its walls are (ivy-b1e.20).

The exemption skipped wall-kit vertices more than 0.05 m off the proxy because the Blender sim
proxies stripped wall relief. A structure whose sim GLB is tools/build_growth_surface.py output
(it has a `growth_surface` block in tools/structure_configs.json) keeps the relief, so gate 3
judges every ivy-reachable wall vertex that stands proud of the growth surface. Hero vertices
buried in a growth-surface solid are counted and reported, not judged: this tool has no
visibility test, and SG-9 (a) (tools/audit_growth_surface.tscn) judges them with one.

Run with:
    python3 -m unittest discover -s test -p "test_measure_structure_gates_relief.py"
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO / "tools"))

import measure_structure_gates as gates  # noqa: E402

WALL = "ivy_hero_Wall_Plaster_Straight_left_1"


class ReliefExemptionTest(unittest.TestCase):
    def test_wall_vertex_off_the_proxy_counts_without_the_exemption(self):
        v = (-10.0, 1.0, 1.0)  # glTF coordinates: y is height, 1 m above ground
        self.assertFalse(gates.ivy_reachable_vertex(WALL, v, 0.08))
        self.assertTrue(gates.ivy_reachable_vertex(WALL, v, 0.08, relief_exempt=False))

    def test_exemption_off_for_growth_surface_structures_only(self):
        self.assertFalse(gates.relief_exempt_for("ivy"))
        # ivy-b1e.8: the tower's sim is builder output with a growth_surface block (its fills).
        self.assertFalse(gates.relief_exempt_for("tower"))
        # The square's sim is builder output too, but defaults fit: no block, so still exempt.
        self.assertTrue(gates.relief_exempt_for("square"))


class GroundTestUsesHeightTest(unittest.TestCase):
    """load_glb_nodes returns glTF coordinates (y up); the ground test read z, which dropped every
    vertex on the z < 0 half of a structure (the cottage's whole front) from gate 3."""

    def test_vertex_on_the_negative_z_side_above_ground_is_judged(self):
        self.assertTrue(gates.ivy_reachable_vertex(WALL, (-10.0, 1.0, -1.5), 0.02))

    def test_vertex_below_ground_is_not_judged(self):
        self.assertFalse(gates.ivy_reachable_vertex(WALL, (-10.0, -0.1, 1.5), 0.02))


class Gate3DeviationTest(unittest.TestCase):
    def test_blender_built_proxy_is_judged_on_both_sides(self):
        self.assertAlmostEqual(gates.gate3_deviation(0.08, True), 0.08)
        self.assertAlmostEqual(gates.gate3_deviation(-0.08, True), 0.08)

    def test_growth_surface_is_judged_on_the_proud_side_only(self):
        self.assertAlmostEqual(gates.gate3_deviation(0.08, False), 0.08)
        self.assertAlmostEqual(gates.gate3_deviation(-0.08, False), 0.0)


class CottageProbesTest(unittest.TestCase):
    def test_cottage_is_probed_at_half_its_wall_height(self):
        from cottage_layout import WALL_TOP  # noqa: WPS433

        ys = [-0.3, 6.838]  # cottage sim bounds: the middle is in the roof
        self.assertAlmostEqual(gates.probe_height("ivy", ys), WALL_TOP * 0.5)
        self.assertAlmostEqual(gates.probe_height("tower", [0.0, 7.14]), 3.57)

    def test_cottage_passes_gates_one_to_three(self):
        r = gates.measure_structure("ivy")
        v = gates.verdict(r)
        self.assertTrue(v["wall_thickness"], "gate 1: %s" % r["wall_min_m"])
        self.assertTrue(v["interior_volume"], "gate 2: %s" % r["interior"])
        self.assertTrue(v["hero_proxy_deviation"], "gate 3: %s" % r["deviation"].get("ivy_max"))
        self.assertGreater(r["deviation"]["buried_over_50mm"], 0, "buried vertices are reported")


if __name__ == "__main__":
    unittest.main()
