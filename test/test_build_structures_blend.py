#!/usr/bin/env python3
"""Regression tests for build_structures blend export/rebuild fixes.

Run with:
    python3 -m unittest test.test_build_structures_blend
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

_REPO = Path(__file__).resolve().parent.parent
_BUILD_PATH = _REPO / "tools" / "build_structures.py"
_SQUARE_BLEND = _REPO / "assets" / "structures" / "square.blend"
_CONFIGS_PATH = _REPO / "tools" / "structure_configs.json"


def _load_blend_helpers():
    source = _BUILD_PATH.read_text().splitlines()
    ns: dict = {"os": os, "Path": Path, "DRAFT": False, "FORCE": False}
    start = next(i for i, line in enumerate(source) if line.startswith("def restore_export_hierarchy"))
    end = next(i for i, line in enumerate(source[start:], start) if line.startswith("def clear_collection_objects"))
    exec("\n".join(source[start:end]), ns)  # noqa: S102
    return ns


def _load_wall_sync_helpers():
    source = _BUILD_PATH.read_text().splitlines()
    layout_start = next(i for i, line in enumerate(source) if line.startswith("def cfg_derived"))
    layout_end = next(i for i, line in enumerate(source[layout_start:], layout_start) if line.startswith("def apply_transform"))
    sync_start = next(i for i, line in enumerate(source) if line.startswith("def _hero_has_baked_geometry"))
    sync_end = next(
        i for i, line in enumerate(source[sync_start:], sync_start) if line.startswith("def export_collection")
    )
    ns: dict = {
        "math": __import__("math"),
        "Vector": _FakeVector3,
        "Matrix": _FakeMatrix,
        "re": __import__("re"),
        "WALL_H": 3.12,
        "EXT_OFFSET": 0.09,
        "MODULE": 2.0,
        "END_OVERLAP": 0.1,
        "TARGET_T": 0.45,
        "CAP": 0.12,
    }
    exec("\n".join(source[layout_start:layout_end]), ns)  # noqa: S102
    exec("\n".join(source[sync_start:sync_end]), ns)  # noqa: S102
    return ns


class _FakeVector3:
    def __init__(self, xyz=(0.0, 0.0, 0.0)):
        if isinstance(xyz, _FakeVector3):
            self.x, self.y, self.z = xyz.x, xyz.y, xyz.z
        elif hasattr(xyz, "__iter__") and not isinstance(xyz, str):
            self.x, self.y, self.z = xyz
        else:
            self.x = self.y = self.z = float(xyz)

    def __getitem__(self, i):
        return (self.x, self.y, self.z)[i]

    def __add__(self, other):
        return _FakeVector3((self.x + other.x, self.y + other.y, self.z + other.z))

    def __sub__(self, other):
        return _FakeVector3((self.x - other.x, self.y - other.y, self.z - other.z))

    def __mul__(self, other):
        return _FakeVector3((self.x * other, self.y * other, self.z * other))

    def __rmul__(self, other):
        return self.__mul__(other)

    def __truediv__(self, other):
        return _FakeVector3((self.x / other, self.y / other, self.z / other))

    def copy(self):
        return _FakeVector3((self.x, self.y, self.z))

    @property
    def length(self):
        return (self.x ** 2 + self.y ** 2 + self.z ** 2) ** 0.5

    def dot(self, other):
        return self.x * other.x + self.y * other.y + self.z * other.z


class _FakeQuat:
    angle = 0.0


class _FakeMatrix:
    def __init__(self, translation=None):
        self._translation = translation or _FakeVector3()

    @staticmethod
    def Translation(vec):
        return _FakeMatrix(vec.copy())

    @staticmethod
    def Rotation(angle, _size, axis):
        del angle, axis
        return _FakeMatrix()

    @staticmethod
    def Scale(factor, _size, axis):
        del factor, axis
        return _FakeMatrix()

    def __matmul__(self, other):
        if isinstance(other, _FakeMatrix):
            return _FakeMatrix(self._translation.copy())
        return self

    def copy(self):
        return _FakeMatrix(self._translation.copy())

    def decompose(self):
        return self._translation.copy(), _FakeQuat(), _FakeVector3((1.0, 1.0, 1.0))

    @property
    def translation(self):
        return self._translation


_blend = _load_blend_helpers()
canonical_blend_stomp_error = _blend["canonical_blend_stomp_error"]
restore_export_hierarchy = _blend["restore_export_hierarchy"]
orphan_export_empty_names = _blend["orphan_export_empty_names"]


class TestCanonicalBlendStompGuard(unittest.TestCase):
    def setUp(self):
        self._draft = _blend["DRAFT"]
        self._force = _blend["FORCE"]

    def tearDown(self):
        _blend["DRAFT"] = self._draft
        _blend["FORCE"] = self._force

    def test_refuses_overwrite_without_force_or_draft(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "square.blend")
            Path(path).write_bytes(b"fake")
            _blend["DRAFT"] = False
            _blend["FORCE"] = False
            err = canonical_blend_stomp_error(path)
            self.assertIsNotNone(err)
            self.assertIn("refusing to overwrite", err)
            self.assertIn("square.blend", err)

    def test_allows_overwrite_with_force(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "square.blend")
            Path(path).write_bytes(b"fake")
            _blend["DRAFT"] = False
            _blend["FORCE"] = True
            self.assertIsNone(canonical_blend_stomp_error(path))

    def test_draft_redirect_skips_stomp_check(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "square.blend")
            Path(path).write_bytes(b"fake")
            _blend["DRAFT"] = True
            _blend["FORCE"] = False
            self.assertIsNone(canonical_blend_stomp_error(path))


class _FakeObj:
    def __init__(self, name, parent=None):
        self.name = name
        self.parent = parent


class TestExportHierarchyRestore(unittest.TestCase):
    def test_restore_export_hierarchy_reparents_and_removes_empty(self):
        wall_a = _FakeObj("square_hero_Wall_0")
        wall_b = _FakeObj("square_hero_Wall_1")
        empty = _FakeObj("Hero_square")
        wall_a.parent = empty
        wall_b.parent = empty
        original = {wall_a: None, wall_b: None}
        removed = []

        def remove(obj, do_unlink=True):
            removed.append((obj, do_unlink))

        fake_bpy = mock.Mock()
        fake_bpy.data.objects.remove = remove
        _blend["bpy"] = fake_bpy

        restore_export_hierarchy([wall_a, wall_b], original, empty)

        self.assertIsNone(wall_a.parent)
        self.assertIsNone(wall_b.parent)
        self.assertEqual(removed, [(empty, True)])

    def test_orphan_export_empty_names_match_hero_and_sim(self):
        names = orphan_export_empty_names("square")
        self.assertEqual(names, {"Hero_square", "Sim_square"})


class TestMeshStatsReadOnly(unittest.TestCase):
    def test_mesh_stats_does_not_call_apply_transform(self):
        source = _BUILD_PATH.read_text()
        mesh_stats_block = source.split("def mesh_stats(objects, label):")[1].split("\ndef ")[0]
        self.assertNotIn("apply_transform(", mesh_stats_block)
        self.assertIn("matrix_world", mesh_stats_block)


class _FakeVert:
    def __init__(self, xyz):
        self.co = _FakeVector3(xyz)


class _FakeMesh:
    def __init__(self, vertices):
        self.vertices = [_FakeVert(v) for v in vertices]


class _FakeHeroObj:
    def __init__(self, vertices, translation=(0.0, 0.0, 0.0)):
        self.type = "MESH"
        self.data = _FakeMesh(vertices)
        self.matrix_world = _FakeMatrix(_FakeVector3(translation))


class TestBakedHeroWallSync(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._helpers = _load_wall_sync_helpers()

    def test_detects_baked_geometry_at_origin(self):
        hero = _FakeHeroObj([_FakeVector3((-7.0, -3.0, 0.0))])
        self.assertTrue(self._helpers["_hero_has_baked_geometry"](hero))

    def test_live_transform_not_treated_as_baked(self):
        hero = _FakeHeroObj([_FakeVector3((0.0, 0.0, 0.0))], translation=(0.05, 0.0, 0.0))
        self.assertFalse(self._helpers["_hero_has_baked_geometry"](hero))

    def test_wall_placement_matrix_uses_scene_offset(self):
        cfg = json.loads(_CONFIGS_PATH.read_text())["square"]
        d = self._helpers["cfg_derived"](cfg)
        wo = _FakeVector3(cfg["scene_offset"])
        mat = self._helpers["wall_placement_matrix"](cfg, d, wo, 0.0, 1)
        self.assertAlmostEqual(mat.translation.x, -7.0)
        self.assertAlmostEqual(mat.translation.y, -2.91, places=2)


class TestExportCollectionMeshRestore(unittest.TestCase):
    def test_export_collection_restores_mesh_backup(self):
        source = _BUILD_PATH.read_text()
        block = source.split("def export_collection(objects, path, root_name):")[1].split("\ndef ")[0]
        self.assertIn("mesh_backups[obj] = obj.data.copy()", block)
        self.assertIn("obj.data = mesh_backups[obj]", block)
        self.assertIn("obj.matrix_world = matrix_backups[obj]", block)


@unittest.skipUnless(
    _SQUARE_BLEND.is_file() and os.environ.get("IVY_BLEND_INTEGRATION") == "1",
    "set IVY_BLEND_INTEGRATION=1 to run blend round-trip gate test",
)
class TestSquareBlendRoundTrip(unittest.TestCase):
    def test_rebuild_export_measure_passes_gates(self):
        cmds = [
            [sys.executable, "tools/rebuild_sim_from_hero.py", str(_SQUARE_BLEND), "assets/structures", "square"],
            [sys.executable, "tools/export_structures.py", str(_SQUARE_BLEND), "assets/structures", "square"],
            [sys.executable, "tools/bake_mesh_sdf.py", "assets/structures/square_sim.glb", "assets/structures/square_sim.sdf"],
            [sys.executable, "tools/measure_structure_gates.py", "square"],
        ]
        for cmd in cmds:
            proc = subprocess.run(cmd, cwd=_REPO, capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertIn("OVERALL: PASS", proc.stdout)


if __name__ == "__main__":
    unittest.main()
