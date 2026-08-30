#!/usr/bin/env python3
"""Unit tests for tools/build_structures.py validate_config (TDD).

Run with:
    python3 -m unittest test.test_build_structures_validate
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
_CONFIGS_PATH = _REPO / "tools" / "structure_configs.json"


def _load_validate_config():
    """Import validate_config without pulling in Blender (bpy)."""
    source = (_REPO / "tools" / "build_structures.py").read_text().splitlines()
    # Schema constants + validate_config only (no bpy-dependent load path).
    chunk = "\n".join(source[111:204])
    ns: dict = {"Path": Path}
    exec(chunk, ns)  # noqa: S102 — intentional isolated exec for bpy-free import
    return ns["validate_config"]


validate_config = _load_validate_config()


def _minimal_tower_cfg(**overrides):
    cfg = {
        "name": "tower",
        "half": 1.6,
        "storeys": 2,
        "module_offsets": [-1.0, 0.0, 1.0],
        "storey_sides": [
            [
                [0.0, ["Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Door_Round", "Wall_UnevenBrick_Straight"]],
                [90.0, ["Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Window_Thin_Round", "Wall_UnevenBrick_Straight"]],
                [180.0, ["Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Straight"]],
                [270.0, ["Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Straight"]],
            ],
            [
                [0.0, ["Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Straight"]],
                [90.0, ["Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Window_Wide_Round", "Wall_UnevenBrick_Straight"]],
                [180.0, ["Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Window_Thin_Round", "Wall_UnevenBrick_Straight"]],
                [270.0, ["Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Straight"]],
            ],
        ],
        "scene_offset": [7.0, 0.0, 0.0],
        "intermediate_floor": True,
        "corner_chamfer": 0.15,
    }
    cfg.update(overrides)
    return cfg


class TestValidateConfigCornerChamfer(unittest.TestCase):
    def test_negative_corner_chamfer_raises(self):
        cfg = _minimal_tower_cfg(corner_chamfer=-0.1)
        with self.assertRaises(ValueError) as ctx:
            validate_config("tower", cfg)
        self.assertIn("corner_chamfer", str(ctx.exception))

    def test_zero_corner_chamfer_allowed(self):
        cfg = _minimal_tower_cfg(corner_chamfer=0.0)
        validate_config("tower", cfg)

    def test_bool_corner_chamfer_rejected(self):
        cfg = _minimal_tower_cfg(corner_chamfer=True)
        with self.assertRaises(ValueError) as ctx:
            validate_config("tower", cfg)
        self.assertIn("corner_chamfer", str(ctx.exception))


class TestValidateConfigOptionalBoolGuard(unittest.TestCase):
    def test_bool_roof_half_rejected(self):
        cfg = _minimal_tower_cfg()
        cfg.pop("corner_chamfer", None)
        cfg["roof_half"] = True
        with self.assertRaises(ValueError) as ctx:
            validate_config("tower", cfg)
        self.assertIn("roof_half", str(ctx.exception))

    def test_bool_intermediate_floor_still_allowed(self):
        cfg = _minimal_tower_cfg(intermediate_floor=True)
        validate_config("tower", cfg)


class TestValidateConfigCommittedConfigs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(_CONFIGS_PATH, "r") as fh:
            cls.configs = json.load(fh)

    def test_square_config_validates(self):
        validate_config("square", self.configs["square"])

    def test_tower_config_validates(self):
        validate_config("tower", self.configs["tower"])


if __name__ == "__main__":
    unittest.main()
