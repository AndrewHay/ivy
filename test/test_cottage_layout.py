#!/usr/bin/env python3
"""Cottage wall facing: kit exterior (local -Y) must face outward on every side.

Run with:
    python3 -m unittest test.test_cottage_layout
"""

from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import cottage_layout as cl  # noqa: E402


def _rotate(vec, ang):
    c, s = math.cos(ang), math.sin(ang)
    return (c * vec[0] - s * vec[1], s * vec[0] + c * vec[1])


class CottageFacingTest(unittest.TestCase):
    BAYS = 3

    def _slots(self):
        return cl.all_wall_slots(self.BAYS)

    def test_outward_normal_points_away_from_house_centre(self):
        for side, bay in self._slots():
            pos, yaw = cl.cottage_slot(side, bay, self.BAYS)
            nx, ny = cl.cottage_outward_normal(yaw)
            self.assertGreater(nx * pos[0] + ny * pos[1], 0.0, f"{side}:{bay}")

    def test_kit_exterior_minus_y_faces_outward_on_every_side(self):
        for side, bay in self._slots():
            _, yaw = cl.cottage_slot(side, bay, self.BAYS)
            n = cl.cottage_outward_normal(yaw)
            ext = _rotate(cl.KIT_EXTERIOR_LOCAL, cl.cottage_facing_angle(*n))
            self.assertAlmostEqual(ext[0], n[0], places=9, msg=f"{side}:{bay}")
            self.assertAlmostEqual(ext[1], n[1], places=9, msg=f"{side}:{bay}")

    def test_side_walls_and_gables_keep_their_previous_rotation(self):
        # Left/right walls and the gables already showed their trim outward.
        for nx in (-1.0, 1.0):
            old = math.atan2(nx, 0.0)
            new = cl.cottage_facing_angle(nx, 0.0)
            self.assertAlmostEqual(math.cos(new - old), 1.0, places=9)

    def test_front_and_back_walls_turn_half_a_turn(self):
        for ny in (-1.0, 1.0):
            old = math.atan2(0.0, ny)
            new = cl.cottage_facing_angle(0.0, ny)
            self.assertAlmostEqual(math.cos(new - old), -1.0, places=9)


if __name__ == "__main__":
    unittest.main()
