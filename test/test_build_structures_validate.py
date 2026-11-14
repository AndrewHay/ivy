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


_CONST_LINES = (130, 144)  # NATIVE_T … DOOR_HERO_OUTSET (0-based slice indices)
_VALIDATE_LINES = (160, 283)
_LAYOUT_LINES = (434, 548)


def _exec_build_constants(ns: dict) -> None:
    source = (_REPO / "tools" / "build_structures.py").read_text().splitlines()
    ns.setdefault("TARGET_T", 0.45)
    exec("\n".join(source[_CONST_LINES[0]:_CONST_LINES[1]]), ns)  # noqa: S102


def _load_validate_config():
    """Import validate_config without pulling in Blender (bpy)."""
    import sys

    sys.path.insert(0, str(_REPO / "tools"))  # validate_config imports build_growth_surface
    source = (_REPO / "tools" / "build_structures.py").read_text().splitlines()
    ns: dict = {"Path": Path}
    _exec_build_constants(ns)
    exec("\n".join(source[_VALIDATE_LINES[0]:_VALIDATE_LINES[1]]), ns)  # noqa: S102
    return ns["validate_config"]


class _FakeVector:
    def __init__(self, xyz):
        self.x, self.y, self.z = xyz

    def __getitem__(self, i):
        return (self.x, self.y, self.z)[i]


def _load_build_helpers():
    """Import schema + layout helpers without pulling in Blender (bpy)."""
    import sys

    sys.path.insert(0, str(_REPO / "tools"))
    from cottage_layout import cottage_derived  # noqa: WPS433

    source = (_REPO / "tools" / "build_structures.py").read_text().splitlines()
    ns: dict = {"math": __import__("math"), "Vector": _FakeVector, "cottage_derived": cottage_derived}
    _exec_build_constants(ns)
    exec("\n".join(source[_LAYOUT_LINES[0]:_LAYOUT_LINES[1]]), ns)  # noqa: S102
    return ns


validate_config = _load_validate_config()
_build = _load_build_helpers()
cfg_derived = _build["cfg_derived"]
resolve_wall_placements = _build["resolve_wall_placements"]
face_tangential_span = _build["face_tangential_span"]
MODULE = _build["MODULE"]


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

    def test_square_has_merge_straight_runs(self):
        self.assertTrue(self.configs["square"].get("merge_straight_runs"))

    def test_ivy_cottage_config_validates(self):
        validate_config("ivy", self.configs["ivy"])
        self.assertEqual(self.configs["ivy"].get("layout"), "cottage")
        self.assertEqual(self.configs["ivy"]["door"], "front:1")

    def test_tower_has_merge_straight_runs(self):
        self.assertTrue(self.configs["tower"].get("merge_straight_runs"))


class TestValidateConfigGrowthSurface(unittest.TestCase):
    """Optional growth_surface block (IMPLEMENTATION.md AR-MESH-20.3, ivy-b1e.14)."""

    @classmethod
    def setUpClass(cls):
        with open(_CONFIGS_PATH, "r") as fh:
            cls.configs = json.load(fh)

    def _ivy(self, block):
        cfg = dict(self.configs["ivy"])
        cfg["growth_surface"] = block
        return cfg

    def test_cottage_block_accepted(self):
        validate_config("ivy", self._ivy({"envelope": ["WindowShutters"], "seals": "hero", "wall_t": 0.45}))

    def test_ring_block_accepted(self):
        validate_config("tower", _minimal_tower_cfg(growth_surface={"exempt": ["Corner"], "fill": []}))

    def test_unknown_key_in_block_rejected(self):
        with self.assertRaises(ValueError) as ctx:
            validate_config("ivy", self._ivy({"envelop": ["WindowShutters"]}))
        self.assertIn("growth_surface", str(ctx.exception))
        self.assertIn("envelop", str(ctx.exception))

    def test_bad_values_rejected(self):
        for block, needle in (({"wall_t": 0.1}, "wall_t"), ({"seals": "glass"}, "seals"),
                              ({"fill": [{"name": "a", "min": [0, 0, 0], "max": [0, 1, 1]}]}, "fill")):
            with self.assertRaises(ValueError) as ctx:
                validate_config("ivy", self._ivy(block))
            self.assertIn(needle, str(ctx.exception))

    def test_block_must_be_an_object(self):
        with self.assertRaises(ValueError) as ctx:
            validate_config("tower", _minimal_tower_cfg(growth_surface=["Corner"]))
        self.assertIn("growth_surface", str(ctx.exception))


class TestResolveWallPlacements(unittest.TestCase):
    def test_solid_face_collapses_to_one_scaled_piece(self):
        cfg = _minimal_tower_cfg(merge_straight_runs=True, half=1.85)
        d = cfg_derived(cfg)
        names = [
            "Wall_UnevenBrick_Straight",
            "Wall_UnevenBrick_Straight",
            "Wall_UnevenBrick_Straight",
        ]
        placements = resolve_wall_placements(cfg, d, names)
        self.assertEqual(len(placements), 1)
        _nm, off, sx = placements[0]
        self.assertAlmostEqual(off, 0.0)
        self.assertAlmostEqual(sx, face_tangential_span(d, cfg) / MODULE)

    def test_mixed_face_keeps_aperture_and_sizes_flanks(self):
        cfg = _minimal_tower_cfg(merge_straight_runs=True, half=1.85)
        d = cfg_derived(cfg)
        names = [
            "Wall_UnevenBrick_Straight",
            "Wall_UnevenBrick_Door_Round",
            "Wall_UnevenBrick_Straight",
        ]
        placements = resolve_wall_placements(cfg, d, names)
        self.assertEqual(len(placements), 3)
        span = face_tangential_span(d, cfg)
        expected_flank = (span / 2.0 - MODULE / 2.0) / MODULE
        self.assertAlmostEqual(placements[0][2], expected_flank)
        self.assertAlmostEqual(placements[1][1], 0.0)
        self.assertAlmostEqual(placements[1][2], 1.0)
        self.assertAlmostEqual(placements[2][2], expected_flank)

    def test_legacy_layout_unchanged_without_merge_flag(self):
        cfg = _minimal_tower_cfg(merge_straight_runs=False)
        d = cfg_derived(cfg)
        names = [
            "Wall_UnevenBrick_Straight",
            "Wall_UnevenBrick_Straight",
            "Wall_UnevenBrick_Straight",
        ]
        placements = resolve_wall_placements(cfg, d, names)
        self.assertEqual([p[1] for p in placements], [-1.0, 0.0, 1.0])
        self.assertEqual([p[2] for p in placements], [1.0, 1.0, 1.0])

    def test_omit_hero_corners_uses_exterior_ring_span(self):
        cfg = _minimal_tower_cfg(merge_straight_runs=True, hero_corner_pieces=False, half=1.85)
        d = cfg_derived(cfg)
        inner = 2.0 * d["corner_xy"] - d["corner_size"]
        outer = 2.0 * d["wall_exterior"]
        self.assertGreater(outer, inner)
        self.assertAlmostEqual(face_tangential_span(d, cfg), outer)


if __name__ == "__main__":
    unittest.main()
