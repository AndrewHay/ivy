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
    # One quad per face, wound so every normal points outward. (The previous table
    # listed two diagonal planes and a bow-tie, so the "box" was not closed — ivy-b1e.3.)
    quads = [
        (0, 3, 2, 1),  # z = min
        (4, 5, 6, 7),  # z = max
        (0, 1, 5, 4),  # y = min
        (2, 3, 7, 6),  # y = max
        (0, 4, 7, 3),  # x = min
        (1, 2, 6, 5),  # x = max
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


class InsideSignTest(unittest.TestCase):
    """ivy-b1e.3: the parity ray must see ordinary boxes, whatever their winding."""

    def _box(self, flip):
        verts, tris = _axis_box_shell(-3.585, 3.07, -3.585, 3.585, 3.42, 3.585)
        if flip:
            tris = [(a, c, b) for a, b, c in tris]
        return verts, tris

    def test_box_interior_is_inside_for_either_winding(self):
        for flip in (False, True):
            verts, tris = self._box(flip)
            for probe in [(0.527789, 3.32, 0.716958), (3.485, 3.25, 0.42), (0.0, 3.245, 0.0)]:
                self.assertEqual(bake_mesh_sdf._ray_crossings_plus_x(probe, tris, verts), 1, (flip, probe))
                self.assertTrue(bake_mesh_sdf.ray_inside(probe, [(verts, tris)]), (flip, probe))
            for probe in [(0.5, 3.5, 0.7), (3.7, 3.25, 0.4), (0.5, 3.0, 0.7), (-4.0, 3.2, 0.0)]:
                self.assertFalse(bake_mesh_sdf.ray_inside(probe, [(verts, tris)]), (flip, probe))

    def test_probe_on_a_face_diagonal_is_counted_once(self):
        # The +X ray from (.., y, z) with y == z runs along the quad diagonal of the
        # x = max face; an unperturbed test counts it zero or two times.
        verts, tris = _axis_box_shell(0.0, 0.0, 0.0, 1.0, 1.0, 1.0)
        for t in (0.25, 0.5, 0.75):
            self.assertTrue(bake_mesh_sdf.ray_inside((0.5, t, t), [(verts, tris)]), t)
            self.assertTrue(bake_mesh_sdf.ray_inside((0.5, t, 1.0 - t), [(verts, tris)]), t)

    def test_inside_grid_matches_per_point_test(self):
        ang = math.radians(25.0)
        ca, sa = math.cos(ang), math.sin(ang)
        box_v, box_t = _axis_box_shell(0.2, 0.1, 0.3, 1.4, 0.9, 0.8)
        tilted = ([(x * ca - y * sa, x * sa + y * ca, z) for x, y, z in box_v], box_t)
        shells = [tilted, _axis_box_shell(0.5, 0.5, 0.0, 1.0, 1.5, 1.0)]
        origin, dims, cell = (-0.6, -0.3, -0.3), (24, 22, 16), 0.1
        grid = bake_mesh_sdf.inside_grid(shells, origin, dims, cell)
        inside_cells = 0
        for iz in range(dims[2]):
            for iy in range(dims[1]):
                for ix in range(dims[0]):
                    p = tuple(origin[k] + (i + 0.5) * cell for k, i in enumerate((ix, iy, iz)))
                    want = bake_mesh_sdf.ray_inside(p, shells)
                    got = bool(grid[ix + iy * dims[0] + iz * dims[0] * dims[1]])
                    self.assertEqual(got, want, p)
                    inside_cells += got
        self.assertGreater(inside_cells, 500)

    def test_baked_box_is_negative_throughout_including_beyond_band(self):
        verts, tris = _axis_box_shell(0.0, 0.0, 0.0, 2.0, 2.0, 2.0)
        cell, band = 0.1, 0.35
        origin, dims, _aabb, values = bake_mesh_sdf.bake(verts, tris, cell, band)

        def at(p):
            idx = [int((p[k] - origin[k]) / cell) for k in range(3)]
            return values[idx[0] + idx[1] * dims[0] + idx[2] * dims[0] * dims[1]]

        self.assertAlmostEqual(at((1.05, 1.05, 0.15)), -0.15, delta=1e-6)
        self.assertAlmostEqual(at((1.05, 1.05, -0.15)), 0.15, delta=1e-6)
        self.assertAlmostEqual(at((1.05, 1.05, 1.05)), -band, delta=1e-6)  # deep interior
        self.assertAlmostEqual(at((1.05, 1.05, 2.25)), 0.25, delta=1e-6)


class UnionSurfaceTest(unittest.TestCase):
    """ivy-b1e.3: faces buried inside a neighbouring piece must not shape the field."""

    def test_buried_faces_are_clipped_away(self):
        a = _axis_box_shell(0.0, 0.0, 0.0, 2.0, 2.0, 1.0)
        b = _axis_box_shell(1.0, 0.5, 0.25, 3.0, 1.5, 0.75)  # pokes out through a's x = 2 face
        tris = bake_mesh_sdf.exposed_triangles([a, b])
        area = sum(bake_mesh_sdf._polygon_area(list(t)) for t in tris)
        # a keeps everything but the 1 x 0.5 hole b punches; b keeps its x > 2 half.
        self.assertAlmostEqual(area, (16.0 - 0.5) + (0.5 + 3.0), places=2)
        for tri in tris:
            centroid = tuple(sum(v[k] for v in tri) / 3.0 for k in range(3))
            self.assertFalse(1.01 < centroid[0] < 1.99 and 0.51 < centroid[1] < 1.49 and 0.26 < centroid[2] < 0.74, centroid)

    def test_identical_and_flush_boxes_keep_their_surface(self):
        a = _axis_box_shell(0.0, 0.0, 0.0, 2.0, 2.0, 1.0)
        area = lambda shells: sum(
            bake_mesh_sdf._polygon_area(list(t)) for t in bake_mesh_sdf.exposed_triangles(shells))
        self.assertAlmostEqual(area([a, a]), 2 * 16.0, places=6)  # coincident faces count as exposed
        flush = _axis_box_shell(2.0, 0.0, 0.0, 3.0, 2.0, 1.0)  # touches a's x = 2 face
        self.assertAlmostEqual(area([a, flush]), 16.0 + 10.0, places=6)

    def test_overlap_interior_reads_union_distance(self):
        a = _axis_box_shell(0.0, 0.0, 0.0, 2.0, 2.0, 1.0)
        b = _axis_box_shell(1.0, 0.0, 0.0, 3.0, 2.0, 1.0)
        verts, tris = _merge_shells([a, b])
        cell, band = 0.1, 0.55
        origin, dims, _aabb, values = bake_mesh_sdf.bake(verts, tris, cell, band, shells=[a, b])
        # Cell centre (1.05, 1.05, 0.55) sits 5 cm from b's buried x = 1 face, but the
        # nearest face of the union is z = 1 (or z = 0), 0.45 m away.
        p = (1.05, 1.05, 0.55)
        idx = [int((p[k] - origin[k]) / cell) for k in range(3)]
        v = values[idx[0] + idx[1] * dims[0] + idx[2] * dims[0] * dims[1]]
        self.assertAlmostEqual(v, -0.45, delta=1e-6)


class OpenShellTest(unittest.TestCase):
    """A kit piece with a missing face has no parity; sign it by winding number."""

    def _open_box(self):
        verts, tris = _axis_box_shell(0.0, 0.0, 0.0, 2.0, 2.0, 0.4)
        return verts, tris[2:]  # drop the z = min face

    def test_closedness(self):
        self.assertTrue(bake_mesh_sdf.shell_is_closed(*_axis_box_shell(0, 0, 0, 1, 1, 1)))
        self.assertFalse(bake_mesh_sdf.shell_is_closed(*self._open_box()))

    def test_open_shell_interior_is_inside(self):
        shell = self._open_box()
        self.assertTrue(bake_mesh_sdf.ray_inside((1.0, 1.0, 0.3), [shell]))
        self.assertTrue(bake_mesh_sdf.ray_inside((0.3, 1.6, 0.2), [shell]))
        self.assertFalse(bake_mesh_sdf.ray_inside((1.0, 1.0, 0.6), [shell]))
        self.assertFalse(bake_mesh_sdf.ray_inside((1.0, 1.0, -0.3), [shell]))
        self.assertFalse(bake_mesh_sdf.ray_inside((2.3, 1.0, 0.2), [shell]))

    def test_grid_matches_per_point_test_for_open_shell(self):
        shell = self._open_box()
        origin, dims, cell = (-0.3, -0.3, -0.3), (26, 26, 10), 0.1
        grid = bake_mesh_sdf.inside_grid([shell], origin, dims, cell)
        for iz in range(dims[2]):
            for iy in range(0, dims[1], 3):
                for ix in range(0, dims[0], 3):
                    p = tuple(origin[k] + (i + 0.5) * cell for k, i in enumerate((ix, iy, iz)))
                    self.assertEqual(
                        bool(grid[ix + iy * dims[0] + iz * dims[0] * dims[1]]),
                        bake_mesh_sdf.ray_inside(p, [shell]), p)


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
