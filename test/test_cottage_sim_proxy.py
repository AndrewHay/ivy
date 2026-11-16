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
        # ivy-b1e.7: the growth-surface builder names its solids {id}_sim_{hero tail}_iNN, one or
        # more per hero wall piece (the wall slab and its bands), so a slot has at least one.
        bays = int(_ivy_cfg()["bays"])
        for side, bay in cl.all_wall_slots(bays):
            infix = f"_{side}_{bay}_i"
            hits = [n for n in self.names if n.startswith("ivy_sim_Wall_") and infix in n]
            self.assertGreaterEqual(len(hits), 1, f"{side}:{bay} sim wall missing; nodes={self.names}")

    def test_frame_pieces_have_per_part_sim_solids(self):
        # ivy-b1e.17.7: the production style is window=frame / door=frame; every hero
        # frame piece gets one sim box per wooden part (glass skipped).
        cfg = _ivy_cfg()
        style = cl.cottage_style({})
        if style["window"] == "frame":
            for slot in cfg.get("windows", []):
                side, bay = slot.split(":")
                stem = f"ivy_sim_{cl.PIECE_WINDOW_INSERT}_{side}_{bay}_"
                n = sum(name.startswith(stem) for name in self.names)
                self.assertEqual(n, 14, f"{slot}: {n} window-frame parts; nodes={self.names}")
        if style["door"] == "frame":
            side, bay = str(cfg["door"]).split(":")
            stem = f"ivy_sim_{cl.PIECE_DOOR_FRAME}_{side}_{bay}_"
            n = sum(name.startswith(stem) for name in self.names)
            self.assertEqual(n, 4, f"door frame: {n} parts; nodes={self.names}")

    def test_roof_and_gables_present(self):
        self.assertTrue(any(n.startswith("ivy_sim_Roof_RoundTiles") for n in self.names), self.names)
        self.assertGreaterEqual(sum(n.startswith("ivy_sim_Roof_Front_Brick4") for n in self.names), 2, self.names)

    def test_sim_is_the_growth_surface_builder_output_and_a_fixed_point(self):
        # ivy-b1e.7: the shipped ivy_sim.glb is tools/build_growth_surface.py's output (hero +
        # scaffold), and running the tool on it again gives the same bytes.
        import build_growth_surface as bgs  # noqa: WPS433

        hero = bgs.read_glb(_REPO / "assets" / "structures" / "ivy_hero.glb")
        centre, settings = bgs.load_structure(_REPO / "tools" / "structure_configs.json", "ivy")
        meshes, _report = bgs.build(hero, bgs.read_glb(_SIM), "ivy", centre, settings)
        self.assertEqual(bgs.glb_bytes(meshes, "Sim_ivy"), _SIM.read_bytes())


if __name__ == "__main__":
    unittest.main()
