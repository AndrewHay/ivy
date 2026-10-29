#!/usr/bin/env python3
"""Unit tests for tools/bake_mesh_sdf.py (ivy-uaq).

Run with:
    python3 -m unittest test.test_bake_mesh_sdf
"""

from __future__ import annotations

import importlib.util
import math
import random
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("bake_mesh_sdf", _REPO / "tools" / "bake_mesh_sdf.py")
bake_mesh_sdf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bake_mesh_sdf)

_A = (0.0, 0.0, 0.0)
_B = (2.0, 0.0, 0.0)
_C = (0.0, 2.0, 0.0)


def _axis_box_shell(minx, miny, minz, maxx, maxy, maxz):
    verts = [
        (minx, miny, minz),
        (maxx, miny, minz),
        (maxx, maxy, minz),
        (minx, maxy, minz),
        (minx, miny, maxz),
        (maxx, miny, maxz),
        (maxx, maxy, maxz),
        (minx, maxy, maxz),
    ]
    quads = [
        (0, 1, 2, 3),
        (4, 6, 5, 7),
        (0, 4, 5, 1),
        (2, 3, 7, 6),
        (0, 2, 6, 4),
        (1, 5, 7, 3),
    ]
    tris = []
    for a, b, c, d in quads:
        tris += [(a, b, c), (a, c, d)]
    return verts, tris


def _merge_shells(shells):
    verts = []
    tris = []
    base = 0
    for sv, st in shells:
        verts.extend(sv)
        tris.extend((a + base, b + base, c + base) for a, b, c in st)
        base += len(sv)
    return verts, tris


def _brute_dist(p, a, b, c, steps=400):
    """Dense barycentric sampling — slow, independent of the Ericson branches."""
    best = math.inf
    for i in range(steps + 1):
        for j in range(steps + 1 - i):
            u, v = i / steps, j / steps
            q = tuple(a[k] + u * (b[k] - a[k]) + v * (c[k] - a[k]) for k in range(3))
            best = min(best, math.dist(p, q))
    return best


class PointTriDistTest(unittest.TestCase):
    def test_face_region_is_perpendicular_distance(self):
        for p in [(0.5, 0.5, 0.1), (0.5, 0.5, -0.3), (0.2, 1.0, 0.05), (1.0, 0.5, 0.0)]:
            self.assertAlmostEqual(bake_mesh_sdf.point_tri_dist(p, _A, _B, _C), abs(p[2]), places=6, msg=p)

    def test_edge_regions(self):
        # Beyond the hypotenuse, beyond edge AB, beyond edge AC.
        self.assertAlmostEqual(
            bake_mesh_sdf.point_tri_dist((1.5, 1.5, 0.0), _A, _B, _C), math.sqrt(0.5), places=6)
        self.assertAlmostEqual(bake_mesh_sdf.point_tri_dist((1.0, -0.4, 0.3), _A, _B, _C), 0.5, places=6)
        self.assertAlmostEqual(bake_mesh_sdf.point_tri_dist((-0.4, 1.0, 0.3), _A, _B, _C), 0.5, places=6)

    def test_vertex_regions(self):
        self.assertAlmostEqual(bake_mesh_sdf.point_tri_dist((-1.0, -1.0, 0.0), _A, _B, _C), math.sqrt(2.0), places=6)
        self.assertAlmostEqual(bake_mesh_sdf.point_tri_dist((3.0, -1.0, 0.0), _A, _B, _C), math.sqrt(2.0), places=6)
        self.assertAlmostEqual(bake_mesh_sdf.point_tri_dist((-1.0, 3.0, 0.0), _A, _B, _C), math.sqrt(2.0), places=6)

    def test_matches_brute_force_on_random_points(self):
        rng = random.Random(7)
        tri = ((0.3, -0.2, 0.1), (1.7, 0.4, -0.5), (-0.4, 1.3, 0.8))
        for _ in range(12):
            p = tuple(rng.uniform(-1.5, 2.5) for _ in range(3))
            exact = bake_mesh_sdf.point_tri_dist(p, *tri)
            self.assertAlmostEqual(exact, _brute_dist(p, *tri), delta=0.01, msg=p)


class RayInsideTest(unittest.TestCase):
    def test_overlapping_closed_boxes_union_is_inside(self):
        # Two scene-graph nodes with identical closed meshes (double-counted +X parity).
        shell_a = _axis_box_shell(0.0, 0.0, 0.0, 2.0, 2.0, 1.0)
        shell_b = _axis_box_shell(0.0, 0.0, 0.0, 2.0, 2.0, 1.0)
        probe = (1.0, 1.0, 0.5)
        self.assertTrue(bake_mesh_sdf.ray_inside(probe, [shell_a, shell_b]))
        merged_verts, merged_tris = _merge_shells([shell_a, shell_b])
        self.assertFalse(bake_mesh_sdf.ray_inside_shell(probe, merged_tris, merged_verts))

    def test_baked_overlap_region_is_negative_phi(self):
        shell_a = _axis_box_shell(0.0, 0.0, 0.0, 2.0, 2.0, 1.0)
        shell_b = _axis_box_shell(1.0, 0.0, 0.0, 3.0, 2.0, 1.0)
        verts, tris = _merge_shells([shell_a, shell_b])
        cell, band = 0.1, 0.35
        origin, dims, _aabb, values = bake_mesh_sdf.bake(
            verts, tris, cell, band, shells=[shell_a, shell_b]
        )
        p = (1.5, 1.0, 0.5)
        idx = [int((p[k] - origin[k]) / cell) for k in range(3)]
        j = idx[0] + idx[1] * dims[0] + idx[2] * dims[0] * dims[1]
        self.assertLess(values[j], 0.0)


class BakeTest(unittest.TestCase):
    def test_baked_slab_reads_true_distance_near_face(self):
        # 2x2x0.4 closed slab tilted 30° about X so its big top face is not axis-aligned.
        ang = math.radians(30.0)
        ca, sa = math.cos(ang), math.sin(ang)

        def rot(p):
            return (p[0], p[1] * ca - p[2] * sa, p[1] * sa + p[2] * ca)

        verts = [rot((x, y, z)) for x in (0.0, 2.0) for y in (0.0, 2.0) for z in (0.0, 0.4)]
        quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        tris = []
        for a, b, c, d in quads:
            tris += [(a, b, c), (a, c, d)]
        cell, band = 0.1, 0.35
        origin, dims, _aabb, values = bake_mesh_sdf.bake(verts, tris, cell, band)
        top_point, top_normal = rot((0.0, 0.0, 0.4)), rot((0.0, 0.0, 1.0))
        for off in (0.05, 0.15, 0.25):
            p = rot((1.0, 1.0, 0.4 + off))
            idx = [int((p[k] - origin[k]) / cell) for k in range(3)]
            centre = tuple(origin[k] + (idx[k] + 0.5) * cell for k in range(3))
            expected = sum((centre[k] - top_point[k]) * top_normal[k] for k in range(3))
            v = values[idx[0] + idx[1] * dims[0] + idx[2] * dims[0] * dims[1]]
            self.assertAlmostEqual(v, expected, delta=1e-4, msg=off)


if __name__ == "__main__":
    unittest.main()
