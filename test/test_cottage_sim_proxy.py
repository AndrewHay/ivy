#!/usr/bin/env python3
"""The committed cottage sim proxy must contain the cottage's wall solids.

Regression for the ivy-b1e.15 commit: tools/rebuild_sim_from_hero.py ran the
ring-building rebuild path on the cottage and exported an ivy_sim.glb with only a
floor slab, roof cap and three panels, leaving ivy no walls to climb.

Run with:
    python3 -m unittest discover -s test -p "test_cottage_sim_proxy.py"
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO / "tools"))

import cottage_layout as cl  # noqa: E402

_SIM = _REPO / "assets" / "structures" / "ivy_sim.glb"


def _ivy_cfg():
    return json.loads((_REPO / "tools" / "structure_configs.json").read_text())["ivy"]


@unittest.skipUnless(_SIM.is_file() and _SIM.read_bytes()[:4] == b"glTF", "ivy_sim.glb not materialised")
class CottageSimProxyTest(unittest.TestCase):
    def setUp(self):
        from diagnose_hero_deviation import load_glb_nodes  # noqa: WPS433

        self.names = [n for n, _ in load_glb_nodes(_SIM)]

    def test_every_wall_slot_has_a_sim_solid(self):
        bays = int(_ivy_cfg()["bays"])
        for side, bay in cl.all_wall_slots(bays):
            suffix = f"_{side}_{bay}"
            hits = [n for n in self.names if n.startswith("ivy_sim_Wall_") and n.endswith(suffix)]
            self.assertEqual(len(hits), 1, f"{side}:{bay} sim wall missing; nodes={self.names}")

    def test_roof_and_gables_present(self):
        self.assertTrue(any(n.startswith("ivy_sim_Roof_RoundTiles") for n in self.names), self.names)
        self.assertGreaterEqual(sum(n.startswith("ivy_sim_Roof_Front_Brick4") for n in self.names), 2, self.names)


if __name__ == "__main__":
    unittest.main()
