#!/usr/bin/env python3
"""Self-test for tools/build_growth_surface.py (IMPLEMENTATION.md AR-MESH-20.3, AR-MESH-20.11).

Run from the project root:
    python3 tools/test_build_growth_surface.py

Exit code 0 when every test passes, 1 otherwise. Standard library only. One synthetic
fixture per rule (1 to 10), per hard failure, the growth_surface config block, and
idempotence (the tool run on its own output gives a byte-identical GLB).

Fixture frame: the structure's footprint centre is (0, 0) in glTF x/z, y up. The main wall is
the sheet x = -2 facing -x (outward), so its rule-2 slab is x in [-2, -1.55] with wall_t 0.45.
"""

from __future__ import annotations

import json
import math
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

import bake_mesh_sdf as baker  # noqa: E402
import build_growth_surface as bgs  # noqa: E402

S = "t"  # fixture structure id
CENTRE = (0.0, 0.0)
WALL_T = 0.45


# ------------------------------------------------------------------------------------------------
# Fixture geometry
# ------------------------------------------------------------------------------------------------


def box(lo, hi):
    return bgs.box_mesh(lo, hi)


def flipped(mesh):
    v, t = mesh
    return list(v), [(a, c, b) for a, b, c in t]


def merge(*meshes):
    verts, tris = [], []
    for v, t in meshes:
        base = len(verts)
        verts += list(v)
        tris += [(a + base, b + base, c + base) for a, b, c in t]
    return verts, tris


def drop_faces(mesh, axis, value):
    """Remove the triangles of `mesh` whose vertices all have coordinate `axis` == value."""
    v, t = mesh
    keep = [tri for tri in t if not all(abs(v[i][axis] - value) < 1e-9 for i in tri)]
    return list(v), keep


def wall_sheet(x=-2.0, z0=-1.0, z1=1.0, y0=0.0, y1=3.0, facing=-1.0):
    """Planar quad in the plane x = const, normal (facing, 0, 0)."""
    v = [(x, y0, z0), (x, y0, z1), (x, y1, z1), (x, y1, z0)]
    t = [(0, 1, 2), (0, 2, 3)]
    if facing > 0:
        t = [(a, c, b) for a, b, c in t]
    return v, t


def wall_sheet_with_hole(x=-2.0, z0=-1.0, z1=1.0, y0=0.0, y1=3.0, hole=(-0.4, 0.4, 1.0, 2.0)):
    """Sheet x = const facing -x with a rectangular hole (hz0, hz1, hy0, hy1)."""
    hz0, hz1, hy0, hy1 = hole
    outer = [(z0, y0), (z1, y0), (z1, y1), (z0, y1)]
    inner = [(hz0, hy0), (hz1, hy0), (hz1, hy1), (hz0, hy1)]
    v = [(x, y, z) for z, y in outer] + [(x, y, z) for z, y in inner]
    # Ring of quads between outer k and inner k; winding gives normal -x (see wall_sheet).
    t = []
    for k in range(4):
        a, b = k, (k + 1) % 4
        ia, ib = 4 + k, 4 + (k + 1) % 4
        t += [(a, b, ib), (a, ib, ia)]
    return v, t


def tube_x(x0, x1, y0, y1, z0, z1):
    """Box along x with both x end faces missing (open timber tube)."""
    m = drop_faces(box((x0, y0, z0), (x1, y1, z1)), 0, x0)
    return drop_faces(m, 0, x1)


def u_tube_z(z0, z1):
    """Tube along z with a U-shaped (non-convex, not star-shaped from its centroid) section."""
    sec = [(0.0, 0.0), (0.6, 0.0), (0.6, 0.6), (0.45, 0.6), (0.45, 0.15), (0.15, 0.15), (0.15, 0.6), (0.0, 0.6)]
    sec = [(-3.0 + x, 1.0 + y) for x, y in sec]
    v = [(x, y, z0) for x, y in sec] + [(x, y, z1) for x, y in sec]
    n = len(sec)
    t = []
    for k in range(n):
        a, b = k, (k + 1) % n
        t += [(a, b, b + n), (a, b + n, a + n)]  # section is counter-clockwise: faces point outward
    return v, t


def arch_brace(x_front=-2.1, x_back=-1.98, cy=1.5, cz=0.0, r0=0.4, r1=0.55, segments=12):
    """Semi-annulus brace lying on the wall x = -2: front face at x_front, back sunk to x_back.

    Open at the back and at both ends, so its single boundary loop is far from planar (rule 4b).
    """
    ring_in = [(cy + r0 * math.sin(math.pi * k / segments), cz + r0 * math.cos(math.pi * k / segments)) for k in range(segments + 1)]
    ring_out = [(cy + r1 * math.sin(math.pi * k / segments), cz + r1 * math.cos(math.pi * k / segments)) for k in range(segments + 1)]
    v = []
    for y, z in ring_in:
        v.append((x_front, y, z))
    for y, z in ring_out:
        v.append((x_front, y, z))
    for y, z in ring_in:
        v.append((x_back, y, z))
    for y, z in ring_out:
        v.append((x_back, y, z))
    m = segments + 1
    fi, fo, bi, bo = 0, m, 2 * m, 3 * m
    t = []
    for k in range(segments):
        t += [(fi + k, fo + k, fo + k + 1), (fi + k, fo + k + 1, fi + k + 1)]  # front face
        t += [(fo + k, bo + k, bo + k + 1), (fo + k, bo + k + 1, fo + k + 1)]  # outer side
        t += [(bi + k, fi + k, fi + k + 1), (bi + k, fi + k + 1, bi + k + 1)]  # inner side
    mesh = (v, t)
    # Wind so the front face points -x (outward, like the wall sheet).
    fn = bgs.area_normal(v, t[:2])[0]
    if fn[0] > 0.0:
        mesh = flipped(mesh)
    return mesh


def hero(*nodes):
    """[(tail, mesh)] -> hero mesh list with names t_hero_<tail>."""
    return [("%s_hero_%s" % (S, tail), list(m[0]), list(m[1])) for tail, m in nodes]


def scaffold(*nodes):
    return [("%s_sim_%s" % (S, tail), list(m[0]), list(m[1])) for tail, m in nodes]


def settings(**kw):
    block = dict(kw)
    return bgs.growth_settings(block)


def run(hero_meshes, scaffold_meshes=(), **kw):
    return bgs.build(hero_meshes, list(scaffold_meshes), S, CENTRE, settings(**kw))


def by_name(meshes):
    return {name: (v, t) for name, v, t in meshes}


def bounds(mesh):
    v = mesh[0]
    return [min(p[k] for p in v) for k in range(3)], [max(p[k] for p in v) for k in range(3)]


def inside(mesh, p):
    v, t = mesh
    return baker._ray_inside_shell_majority(p, t, v)


def volume(mesh):
    return bgs.signed_volume(mesh[0], mesh[1])


# ------------------------------------------------------------------------------------------------
# Tests
# ------------------------------------------------------------------------------------------------


class TestMeshPrimitives(unittest.TestCase):
    def test_box_is_closed_and_outward(self):
        b = box((0, 0, 0), (1, 2, 3))
        self.assertTrue(bgs.is_closed(b[1]))
        self.assertAlmostEqual(volume(b), 6.0)

    def test_weld_merges_vertices_across_a_quantisation_boundary(self):
        v = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.99999996, 0.00004999, 0.0), (1.0, 1.0, 0.0)]
        wv, wt = bgs.weld(v, [(0, 1, 2), (3, 4, 2)])
        self.assertEqual(len(wv), 4)
        self.assertEqual(wt[1][0], wt[0][1])

    def test_triangulate_u_polygon_keeps_orientation_and_area(self):
        pts = [(0, 0, 0), (3, 0, 0), (3, 3, 0), (2, 3, 0), (2, 1, 0), (1, 1, 0), (1, 3, 0), (0, 3, 0)]
        tris = bgs.triangulate_loop(pts, (0.0, 0.0, 1.0))
        self.assertEqual(len(tris), 6)
        area = 0.0
        for a, b, c in tris:
            n = bgs.cross(bgs.sub(pts[b], pts[a]), bgs.sub(pts[c], pts[a]))
            self.assertGreater(n[2], 0.0, "every ear keeps the polygon's orientation (no folded fan)")
            area += 0.5 * n[2]
        self.assertAlmostEqual(area, 7.0)

    def test_triangulate_self_intersecting_loop_raises(self):
        pts = [(0, 0, 0), (1, 1, 0), (1, 0, 0), (0, 1, 0)]
        with self.assertRaises(bgs.CapError):
            bgs.triangulate_loop(pts, (0.0, 0.0, 1.0))


class TestGlbIo(unittest.TestCase):
    def test_round_trip_preserves_names_and_geometry(self):
        b = box((-1, 0, 0), (0.5, 2, 0.25))
        data = bgs.glb_bytes([("a_sim_X_i00", b[0], b[1])], "Sim_a")
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "x.glb"
            p.write_bytes(data)
            back = bgs.read_glb(p)
        self.assertEqual([m[0] for m in back], ["a_sim_X_i00"])
        self.assertEqual(back[0][2], b[1])
        for p0, p1 in zip(back[0][1], b[0]):
            for k in range(3):
                self.assertAlmostEqual(p0[k], p1[k], places=6)

    def test_read_applies_node_transforms(self):
        b = box((0, 0, 0), (1, 1, 1))
        data = bgs.glb_bytes([("n", b[0], b[1])], "root")
        data = _patch_node(data, 0, {"translation": [10.0, 0.0, 0.0], "rotation": [0.0, math.sin(math.pi / 4), 0.0, math.cos(math.pi / 4)]})
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "x.glb"
            p.write_bytes(data)
            (name, v, _t), = bgs.read_glb(p)
        lo, hi = bounds((v, None))
        # 90 degrees about +y maps x -> -z: the unit box spans x [10, 11], z [-1, 0].
        self.assertAlmostEqual(lo[0], 10.0, places=5)
        self.assertAlmostEqual(hi[0], 11.0, places=5)
        self.assertAlmostEqual(lo[2], -1.0, places=5)
        self.assertAlmostEqual(hi[2], 0.0, places=5)

    def test_output_nodes_carry_no_transforms(self):
        out, _r = run(hero(("Post", box((-3, 0, 0), (-2.5, 1, 0.5)))))
        doc = _glb_json(bgs.glb_bytes(out, "Sim_t"))
        for node in doc["nodes"]:
            for key in ("translation", "rotation", "scale", "matrix"):
                self.assertNotIn(key, node)


class TestRule1Closed(unittest.TestCase):
    def test_closed_island_kept_unchanged(self):
        post = box((-3, 0, 0), (-2.5, 1, 0.5))
        out, report = run(hero(("Post", post)))
        m = by_name(out)["t_sim_Post_i00"]
        self.assertEqual(sorted(m[0]), sorted(post[0]))
        self.assertAlmostEqual(volume(m), volume(post))
        self.assertEqual(report["rules"]["1_closed"], 1)

    def test_inside_out_closed_island_is_wound_outward(self):
        out, _r = run(hero(("Post", flipped(box((-3, 0, 0), (-2.5, 1, 0.5))))))
        self.assertGreater(volume(by_name(out)["t_sim_Post_i00"]), 0.0)

    def test_double_sided_sheet_fits_no_rule(self):
        sheet = wall_sheet()
        both = merge(sheet, flipped(sheet))
        with self.assertRaises(bgs.BuildError) as ctx:
            run(hero(("Card", both)))
        self.assertIn("Card", str(ctx.exception))
        self.assertIn("no rule", str(ctx.exception))


class TestRule2And3Sheets(unittest.TestCase):
    def test_outward_sheet_extruded_wall_t_toward_interior(self):
        out, report = run(hero(("Wall", wall_sheet())))
        m = by_name(out)["t_sim_Wall_i00"]
        self.assertTrue(bgs.is_closed(m[1]))
        lo, hi = bounds(m)
        self.assertAlmostEqual(lo[0], -2.0, places=6)
        self.assertAlmostEqual(hi[0], -2.0 + WALL_T, places=6)
        self.assertGreater(volume(m), 0.0)
        self.assertEqual(report["rules"]["2_extruded"], 1)

    def test_wall_t_from_settings(self):
        out, _r = run(hero(("Wall", wall_sheet())), wall_t=0.30)
        _lo, hi = bounds(by_name(out)["t_sim_Wall_i00"])
        self.assertAlmostEqual(hi[0], -1.70, places=6)

    def test_hole_extrudes_into_a_reveal(self):
        out, _r = run(hero(("Wall", wall_sheet_with_hole())))
        m = by_name(out)["t_sim_Wall_i00"]
        self.assertTrue(bgs.is_closed(m[1]))
        self.assertFalse(inside(m, (-1.8, 1.5, 0.0)), "the window opening stays open through the slab")
        self.assertTrue(inside(m, (-1.8, 0.5, 0.0)))
        expected = (2.002 * 3.002 - 0.8 * 1.0) * WALL_T
        self.assertAlmostEqual(volume(m), expected, places=4)

    def test_inward_sheet_dropped(self):
        node = merge(wall_sheet(), wall_sheet(x=-1.8, facing=1.0))
        out, report = run(hero(("Wall", node)))
        self.assertEqual([n for n, _v, _t in out], ["t_sim_Wall_i00"])
        self.assertEqual(report["rules"]["3_dropped"], 1)

    def test_near_horizontal_sheet_fits_no_rule(self):
        deck = ([(-3, 1, -1), (-2, 1, -1), (-2, 1, 1), (-3, 1, 1)], [(0, 2, 1), (0, 3, 2)])
        with self.assertRaises(bgs.BuildError) as ctx:
            run(hero(("Deck", deck)))
        self.assertIn("Deck", str(ctx.exception))
        self.assertIn("no rule", str(ctx.exception))


class TestRule4aCap(unittest.TestCase):
    def test_tube_with_planar_loops_is_capped_closed(self):
        tube = tube_x(-2.6, -2.3, 1.0, 1.2, -0.1, 0.1)
        out, report = run(hero(("Beam", tube)))
        m = by_name(out)["t_sim_Beam_i00"]
        self.assertTrue(bgs.is_closed(m[1]))
        self.assertAlmostEqual(volume(m), 0.3 * 0.2 * 0.2, places=9)
        self.assertEqual(report["rules"]["4a_capped_loops"], 2)

    def test_non_convex_loop_capped_without_a_folded_fan(self):
        out, _r = run(hero(("Trim", u_tube_z(-0.5, 0.5))))
        m = by_name(out)["t_sim_Trim_i00"]
        self.assertTrue(bgs.is_closed(m[1]))
        # The U's notch is outside the solid; a fan from the centroid would fold over it.
        self.assertFalse(inside(m, (-2.7, 1.5, 0.0)))
        self.assertTrue(inside(m, (-2.95, 1.3, 0.0)))
        self.assertAlmostEqual(volume(m), (0.36 - 0.3 * 0.45) * 1.0, places=9)


class TestRule4bSkirt(unittest.TestCase):
    def test_brace_skirted_to_its_backing_sheet_2mm_inside_the_slab(self):
        node = merge(wall_sheet(), arch_brace())
        out, report = run(hero(("Wall", node)))
        names = by_name(out)
        brace = [m for n, m in names.items() if n != "t_sim_Wall_i00"]
        self.assertEqual(len(brace), 1)
        m = brace[0]
        self.assertTrue(bgs.is_closed(m[1]))
        lo, hi = bounds(m)
        self.assertAlmostEqual(lo[0], -2.1, places=6)
        self.assertAlmostEqual(hi[0], -1.978, places=6, msg="cap 2 mm behind the deepest loop vertex")
        self.assertGreater(report["rules"]["4b_skirted_loops"], 0)
        # Inside the arch's opening is outside the brace; the arch body is inside.
        self.assertFalse(inside(m, (-2.05, 1.5, 0.0)))
        self.assertTrue(inside(m, (-2.05, 1.5 + 0.475, 0.0)))
        area = 6.0 * math.sin(math.pi / 12) * (0.55 ** 2 - 0.4 ** 2)  # 12-segment polygonal semi-annulus
        self.assertAlmostEqual(volume(m), area * 0.122, places=6)

    def test_backing_may_be_the_inward_sheet(self):
        """A trim on the room side of a wall skirts to the wall's inward sheet.

        wall_t 0.30 puts the slab's back at x = -1.70, so the trim (front at -1.65) is not
        wholly inside the slab and rule 5 keeps it, like the cottage's interior top beams.
        """
        trim = arch_brace(x_front=-1.65, x_back=-1.805)
        trim = flipped(trim)  # front faces +x, into the room
        node = merge(wall_sheet(), wall_sheet(x=-1.8, facing=1.0), trim)
        out, _r = run(hero(("Wall", node)), wall_t=0.30)
        others = [m for n, m in by_name(out).items() if n != "t_sim_Wall_i00"]
        self.assertEqual(len(others), 1)
        lo, hi = bounds(others[0])
        self.assertAlmostEqual(lo[0], -1.807, places=6)
        self.assertAlmostEqual(hi[0], -1.65, places=6)

    def test_non_planar_loop_without_backing_sheet_fails(self):
        with self.assertRaises(bgs.BuildError) as ctx:
            run(hero(("Brace", arch_brace())))
        msg = str(ctx.exception)
        self.assertIn("Brace", msg)
        self.assertIn("no backing sheet", msg)
        self.assertIn("skipped", ctx.exception.report["slot_check"])


class TestRule5InsideSlab(unittest.TestCase):
    def test_solid_wholly_inside_a_slab_is_dropped(self):
        beam = box((-1.9, 1.0, -0.5), (-1.7, 1.2, 0.5))
        out, report = run(hero(("Wall", merge(wall_sheet(), beam))))
        self.assertEqual([n for n, _v, _t in out], ["t_sim_Wall_i00"])
        self.assertEqual(report["rules"]["5_dropped"], 1)

    def test_solid_reaching_out_of_the_slab_is_kept(self):
        beam = box((-1.9, 2.9, -0.5), (-1.7, 3.1, 0.5))
        out, _r = run(hero(("Wall", merge(wall_sheet(), beam))))
        self.assertEqual(len(out), 2)

    def test_slabs_of_other_nodes_count(self):
        beam = box((-1.9, 1.0, -0.5), (-1.7, 1.2, 0.5))
        out, _r = run(hero(("Wall", wall_sheet()), ("Beam", beam)))
        self.assertNotIn("t_sim_Beam_i00", by_name(out))


def shutter_boards(x0=-2.15, x1=-2.12, gap=0.02):
    boards = []
    z = -0.5
    for _k in range(4):
        boards.append(box((x0, 1.0, z), (x1, 2.0, z + 0.2)))
        z += 0.2 + gap
    return merge(*boards)


class TestRule6Envelope(unittest.TestCase):
    def test_envelope_node_becomes_one_box_extended_to_the_wall(self):
        out, report = run(hero(("Wall", wall_sheet()), ("Shutter_L", shutter_boards())), envelope=["Shutter"])
        m = by_name(out)["t_sim_Shutter_L_i00"]
        self.assertEqual(len(m[1]), 12)
        lo, hi = bounds(m)
        self.assertAlmostEqual(lo[0], -2.15, places=6)
        self.assertAlmostEqual(hi[0], -1.998, places=6)
        self.assertAlmostEqual(lo[2], -0.5, places=6)
        self.assertAlmostEqual(hi[2], -0.5 + 4 * 0.2 + 3 * 0.02, places=6)
        self.assertEqual(report["rules"]["6_envelope"], 1)
        entry = [n for n in report["nodes"] if n["hero"] == "t_hero_Shutter_L"][0]
        self.assertEqual(entry["solids"], ["t_sim_Shutter_L_i00"])
        self.assertEqual(report["slot_check"], "run")

    def test_envelope_already_in_the_wall_is_not_extended(self):
        out, _r = run(hero(("Wall", wall_sheet()), ("Shutter_L", shutter_boards(-2.05, -1.95))), envelope=["Shutter"])
        _lo, hi = bounds(by_name(out)["t_sim_Shutter_L_i00"])
        self.assertAlmostEqual(hi[0], -1.95, places=6)

    def test_rotated_envelope_uses_its_oriented_box(self):
        boards = shutter_boards()
        c, s = math.cos(math.radians(30)), math.sin(math.radians(30))
        pts = [(-3 + c * (x + 2.15) - s * z, y, s * (x + 2.15) + c * z) for x, y, z in boards[0]]
        box_m = bgs.oriented_box_mesh(bgs.oriented_box(pts))
        self.assertTrue(bgs.is_closed(box_m[1]))
        self.assertAlmostEqual(volume(box_m), 0.03 * 1.0 * 0.86, places=6)

    def test_envelope_with_no_wall_behind_fails(self):
        with self.assertRaises(bgs.BuildError) as ctx:
            run(hero(("Shutter_L", shutter_boards())), envelope=["Shutter"])
        self.assertIn("Shutter_L", str(ctx.exception))
        self.assertIn("no wall behind", str(ctx.exception))

    def test_config_entry_matching_no_node_fails(self):
        with self.assertRaises(bgs.BuildError) as ctx:
            run(hero(("Wall", wall_sheet())), envelope=["Shuter"])
        self.assertIn("Shuter", str(ctx.exception))


SEAL = "Seal_t_ground_door_S_1_door"


def seal_fixture():
    leaf = box((-2.05, 0.0, -0.5), (-2.0, 2.0, 0.5))
    h = hero(("Wall", wall_sheet()), (SEAL, leaf))
    sc = scaffold(("Panel_t_ground_door_S_1", box((-2.0, 0.0, -0.5), (-1.55, 2.0, 0.5))),
                  ("Panel_t_ground_win_W_0", box((-2.0, 1.0, 0.6), (-1.55, 2.0, 0.9))))
    return h, sc


class TestRule7Seals(unittest.TestCase):
    def test_hero_seal_becomes_the_aperture_panel(self):
        h, sc = seal_fixture()
        out, report = run(h, sc, seals="hero")
        names = by_name(out)
        self.assertIn("t_sim_Panel_t_ground_door_S_1_i00", names)
        lo, hi = bounds(names["t_sim_Panel_t_ground_door_S_1_i00"])
        self.assertAlmostEqual(lo[0], -2.05, places=6)
        self.assertAlmostEqual(hi[0], -2.05 + WALL_T, places=6)
        self.assertIn("t_sim_Panel_t_ground_win_W_0_i00", names, "other apertures keep their scaffold panel")
        self.assertEqual(sum(1 for n in names if "door_S_1" in n), 1, "the scaffold door panel is dropped")
        self.assertEqual(report["rules"]["7_seal"], 1)

    def test_scaffold_seals_keep_scaffold_panels_and_skip_hero_seals(self):
        h, sc = seal_fixture()
        out, _r = run(h, sc, seals="scaffold")
        names = by_name(out)
        self.assertIn("t_sim_Panel_t_ground_door_S_1_i00", names)
        _lo, hi = bounds(names["t_sim_Panel_t_ground_door_S_1_i00"])
        self.assertAlmostEqual(hi[0], -1.55, places=6)
        self.assertFalse(any(SEAL in n for n in names))


class TestRule8Overlap(unittest.TestCase):
    def test_abutting_slabs_overlap_by_at_least_1mm(self):
        out, _r = run(hero(("WallA", wall_sheet(z0=-1.0, z1=0.0)), ("WallB", wall_sheet(z0=0.0, z1=1.0))))
        names = by_name(out)
        _lo_a, hi_a = bounds(names["t_sim_WallA_i00"])
        lo_b, _hi_b = bounds(names["t_sim_WallB_i00"])
        self.assertGreaterEqual(hi_a[2] - lo_b[2], 0.001 - 1e-9)

    def test_cap_on_a_slab_face_is_pushed_2mm_into_the_slab(self):
        beam = tube_x(-2.3, -2.0, 1.0, 1.2, -0.1, 0.1)
        out, report = run(hero(("Wall", wall_sheet()), ("Beam", beam)))
        names = by_name(out)
        lo, hi = bounds(names["t_sim_Beam_i00"])
        self.assertAlmostEqual(lo[0], -2.3, places=6, msg="the free end stays where the hero has it")
        self.assertAlmostEqual(hi[0], -1.998, places=6)
        self.assertEqual(report["rules"]["8_pushed_caps"], 1)
        # Baked together, no surface of the beam is left inside the slab (no false interior surface).
        shells = [names["t_sim_Wall_i00"], names["t_sim_Beam_i00"]]
        for tri in baker.exposed_triangles([(list(v), list(t)) for v, t in shells]):
            cx = sum(p[0] for p in tri) / 3.0
            cy = sum(p[1] for p in tri) / 3.0
            cz = sum(p[2] for p in tri) / 3.0
            buried = -1.9995 < cx < -1.5505 and 0.0005 < cy < 2.9995 and -0.9995 < cz < 0.9995
            self.assertFalse(buried, "exposed triangle inside the slab at (%.4f, %.4f, %.4f)" % (cx, cy, cz))


class TestRule9ScaffoldSlabs(unittest.TestCase):
    def test_floor_slab_pulled_inside_the_wall_face(self):
        sc = scaffold(("FloorSlab", box((-2.09, -0.3, -0.9), (2.0, 0.05, 0.9))))
        out, report = run(hero(("Wall", wall_sheet())), sc)
        lo, hi = bounds(by_name(out)["t_sim_FloorSlab_i00"])
        self.assertAlmostEqual(lo[0], -2.0 + 0.10, places=6)
        self.assertAlmostEqual(hi[0], 2.0, places=6, msg="no wall on the +x side: unchanged")
        self.assertGreater(report["rules"]["9_pulled_vertices"], 0)

    def test_other_scaffold_nodes_copied_and_legacy_walls_discarded(self):
        sc = scaffold(("CornerColumn_NW", box((-2.2, 0, -1.2), (-1.9, 3, -0.9))),
                      ("Interior_W", box((-1.56, 0, -0.5), (-1.50, 2, 0.5))),
                      ("MidFloorSlab", box((-2.5, 1.5, -1), (2, 1.6, 1))),
                      ("RoofCone", box((-1, 3, -1), (1, 4, 1))),
                      ("Wall_Legacy_0", box((-2.1, 0, -1), (-1.5, 3, 1))))
        out, report = run(hero(("Wall", wall_sheet())), sc)
        names = by_name(out)
        for tail in ("CornerColumn_NW", "Interior_W", "MidFloorSlab", "RoofCone"):
            self.assertIn("t_sim_%s_i00" % tail, names)
        lo, _hi = bounds(names["t_sim_MidFloorSlab_i00"])
        self.assertAlmostEqual(lo[0], -2.5, places=6, msg="only FloorSlab and RoofCap are pulled")
        self.assertFalse(any("Legacy" in n for n in names))
        self.assertEqual(report["rules"]["scaffold_copied"], 4)


class TestRule10ExemptAndFill(unittest.TestCase):
    def test_exempt_node_skipped(self):
        out, report = run(hero(("Wall", wall_sheet()), ("CornerTrim", arch_brace())), exempt=["CornerTrim"])
        self.assertEqual([n for n, _v, _t in out], ["t_sim_Wall_i00"])
        self.assertEqual(report["rules"]["10_exempt"], 1)

    def test_fill_boxes_added(self):
        out, report = run(hero(("Wall", wall_sheet())),
                          fill=[{"name": "Slot", "min": [-2.3, 0.0, 1.0], "max": [-2.0, 3.0, 1.2]}])
        lo, hi = bounds(by_name(out)["t_sim_Fill_Slot_i00"])
        self.assertEqual([round(x, 6) for x in lo + hi], [-2.3, 0.0, 1.0, -2.0, 3.0, 1.2])
        self.assertEqual(report["rules"]["fill"], 1)


class TestHardFailures(unittest.TestCase):
    def test_result_not_closed_fails(self):
        b = box((-3, 0, 0), (-2.5, 1, 0.5))
        v = list(b[0]) + [(-3.5, 0.5, 0.0)]
        fin = (v, list(b[1]) + [(0, 1, 8)])  # a fin on the box edge 0-1: non-manifold
        with self.assertRaises(bgs.BuildError) as ctx:
            run(hero(("Fin", fin)))
        self.assertIn("Fin", str(ctx.exception))
        self.assertIn("not closed", str(ctx.exception))

    def test_node_that_produced_no_solid_fails(self):
        with self.assertRaises(bgs.BuildError) as ctx:
            run(hero(("Wall", wall_sheet()), ("Lining", wall_sheet(x=-1.8, facing=1.0))))
        self.assertIn("Lining", str(ctx.exception))
        self.assertIn("produced no solid", str(ctx.exception))

    def test_slot_narrower_than_10cm_fails_and_report_lists_it(self):
        with self.assertRaises(bgs.BuildError) as ctx:
            run(hero(("Wall", wall_sheet()), ("Shutter_L", shutter_boards())))
        self.assertIn("slot", str(ctx.exception))
        slots = ctx.exception.report["slots"]
        self.assertGreaterEqual(len(slots), 3)
        for s in slots:
            self.assertAlmostEqual(s["width"], 0.02, places=4)
            self.assertEqual(len(s["position"]), 3)
            self.assertTrue(-2.15 <= s["position"][0] <= -2.12)
            # The gap's extent, so a fill box can be written from the report.
            for k in range(3):
                self.assertLessEqual(s["lo"][k], s["position"][k])
                self.assertGreaterEqual(s["hi"][k], s["position"][k])
            self.assertAlmostEqual(s["hi"][2] - s["lo"][2], 0.02, places=4)

    def test_gap_of_10cm_or_more_is_not_a_slot(self):
        a = box((-3.0, 0, -0.5), (-2.8, 1, 0.5))
        b = box((-3.0, 0, 0.61), (-2.8, 1, 1.5))
        out, report = run(hero(("A", a), ("B", b)))
        self.assertEqual(report["slots"], [])

    def test_acute_wedge_between_solids_is_not_a_slot(self):
        """A brace meeting a beam at 30 degrees leaves a V, not a parallel-walled slot."""
        beam = box((-3.0, 1.0, -1.0), (-2.8, 1.2, 1.0))
        c, s = math.cos(math.radians(30)), math.sin(math.radians(30))
        # A plank whose top face rises at 30 degrees and touches the beam's underside at z = 0.
        plank = ([(-3.0, 1.0 - 0.6 * s, -0.6 * c), (-2.8, 1.0 - 0.6 * s, -0.6 * c), (-2.8, 1.0, 0.0), (-3.0, 1.0, 0.0),
                  (-3.0, 1.0 - 0.6 * s - 0.1, -0.6 * c), (-2.8, 1.0 - 0.6 * s - 0.1, -0.6 * c), (-2.8, 0.9, 0.0), (-3.0, 0.9, 0.0)],
                 [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4),
                  (3, 7, 6), (3, 6, 2), (0, 4, 7), (0, 7, 3), (1, 2, 6), (1, 6, 5)])
        if volume(plank) < 0:
            plank = flipped(plank)
        out, report = run(hero(("Beam", beam), ("Plank", plank)))
        self.assertEqual(report["slots"], [])

    def test_enclosed_cavity_is_not_a_slot(self):
        lid = [box((-3.0, 0.0, -1.0), (-2.0, 0.2, 1.0)),  # floor
               box((-3.0, 0.25, -1.0), (-2.0, 0.45, 1.0)),  # ceiling, 5 cm cavity below it
               box((-3.2, 0.0, -1.2), (-1.8, 0.45, -1.0)),  # four walls round the cavity
               box((-3.2, 0.0, 1.0), (-1.8, 0.45, 1.2)),
               box((-3.2, 0.0, -1.0), (-3.0, 0.45, 1.0)),
               box((-2.0, 0.0, -1.0), (-1.8, 0.45, 1.0))]
        out, report = run(hero(*[("Part%d" % k, m) for k, m in enumerate(lid)]))
        self.assertEqual(report["slots"], [])
        self.assertGreater(report["enclosed_gap_samples"], 0)


class TestNamingAndOutput(unittest.TestCase):
    def test_every_solid_one_node_named_by_hero_tail(self):
        node = merge(wall_sheet(), tube_x(-2.6, -1.99, 1.0, 1.2, -0.1, 0.1), tube_x(-2.6, -1.99, 2.0, 2.2, -0.1, 0.1))
        out, _r = run(hero(("Wall_A", node)))
        self.assertEqual([n for n, _v, _t in out], ["t_sim_Wall_A_i00", "t_sim_Wall_A_i01", "t_sim_Wall_A_i02"])
        for _n, v, t in out:
            self.assertTrue(bgs.is_closed(t))
            self.assertGreater(bgs.signed_volume(v, t), 0.0)


def house_fixture(tmp: Path):
    """Hero + scaffold GLBs and a config for the CLI tests (one wall, a shutter, a seal, slabs)."""
    h = hero(("Wall_W", wall_sheet_with_hole(hole=(-0.4, 0.4, 1.0, 2.0))),
             ("Beam_W", tube_x(-2.3, -2.0, 0.5, 0.7, -0.6, 0.6)),
             ("Brace_W", merge(wall_sheet(z0=1.0, z1=3.0), arch_brace(cz=2.0))),
             ("Shutter_W", shutter_boards()),
             ("Seal_t_ground_win_W_0_glass", box((-2.02, 1.0, -0.4), (-2.0, 2.0, 0.4))))
    sc = scaffold(("FloorSlab", box((-2.09, -0.3, -0.9), (2.0, 0.05, 2.9))),
                  ("RoofCap", box((-2.09, 3.0, -0.9), (2.0, 3.3, 2.9))),
                  ("Panel_t_ground_win_W_0", box((-2.0, 1.0, -0.4), (-1.55, 2.0, 0.4))),
                  ("Wall_W", box((-2.1, 0.0, -1.0), (-1.5, 3.0, 1.0))))
    hero_path, sc_path = tmp / "t_hero.glb", tmp / "t_sim.glb"
    hero_path.write_bytes(bgs.glb_bytes(h, "Hero_t"))
    sc_path.write_bytes(bgs.glb_bytes(sc, "Sim_t"))
    cfg = {"t": {"name": "t", "layout": "cottage", "scene_offset": [0.0, 0.0, 0.0],
                 "growth_surface": {"wall_t": 0.45, "envelope": ["Shutter"], "seals": "hero",
                                    "fill": [{"name": "Eave", "min": [-2.5, 2.9, -1.0], "max": [-2.0, 3.0, 3.0]}]}}}
    cfg_path = tmp / "configs.json"
    cfg_path.write_text(json.dumps(cfg))
    return hero_path, sc_path, cfg_path


def cli(*args):
    return subprocess.run([sys.executable, str(TOOLS / "build_growth_surface.py"), *map(str, args)],
                          capture_output=True, text=True)


class TestCliAndIdempotence(unittest.TestCase):
    def test_idempotent_on_its_own_output(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            hero_path, sc_path, cfg_path = house_fixture(tmp)
            out1, out2 = tmp / "out1.glb", tmp / "out2.glb"
            r1 = cli(hero_path, sc_path, out1, "--structure", "t", "--config", cfg_path, "--report", tmp / "r1.json")
            self.assertEqual(r1.returncode, 0, r1.stderr)
            r2 = cli(hero_path, out1, out2, "--structure", "t", "--config", cfg_path)
            self.assertEqual(r2.returncode, 0, r2.stderr)
            self.assertEqual(out1.read_bytes(), out2.read_bytes())
            report = json.loads((tmp / "r1.json").read_text())
            self.assertEqual(report["failures"], [])
            names = [m[0] for m in bgs.read_glb(out1)]
            self.assertIn("t_sim_Fill_Eave_i00", names)
            self.assertIn("t_sim_Panel_t_ground_win_W_0_i00", names)

    def test_structure_defaults_from_the_hero_file_name(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            hero_path, sc_path, cfg_path = house_fixture(tmp)
            r = cli(hero_path, sc_path, tmp / "o.glb", "--config", cfg_path)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_build_failure_exits_1_writes_report_and_no_output(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            hero_path = tmp / "t_hero.glb"
            hero_path.write_bytes(bgs.glb_bytes(hero(("Brace", arch_brace())), "Hero_t"))
            sc_path = tmp / "t_sim.glb"
            sc_path.write_bytes(bgs.glb_bytes(scaffold(("FloorSlab", box((-1, -0.3, -1), (1, 0, 1)))), "Sim_t"))
            cfg_path = tmp / "c.json"
            cfg_path.write_text(json.dumps({"t": {"name": "t", "scene_offset": [0, 0, 0]}}))
            r = cli(hero_path, sc_path, tmp / "o.glb", "--config", cfg_path, "--report", tmp / "r.json")
            self.assertEqual(r.returncode, 1)
            self.assertIn("no backing sheet", r.stderr)
            self.assertFalse((tmp / "o.glb").exists())
            self.assertTrue(json.loads((tmp / "r.json").read_text())["failures"])

    def test_usage_errors_exit_2(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            hero_path, sc_path, cfg_path = house_fixture(tmp)
            self.assertEqual(cli(hero_path).returncode, 2)
            self.assertEqual(cli(hero_path, sc_path, tmp / "o.glb", "--bogus").returncode, 2)
            self.assertEqual(cli(hero_path, sc_path, tmp / "o.glb", "--config", cfg_path, "--structure", "nope").returncode, 2)
            self.assertEqual(cli(hero_path, sc_path, hero_path, "--config", cfg_path).returncode, 2)


class TestGrowthSurfaceConfig(unittest.TestCase):
    def ok(self, block):
        bgs.validate_growth_surface("cfg", block)

    def bad(self, block, needle):
        with self.assertRaises(ValueError) as ctx:
            bgs.validate_growth_surface("cfg", block)
        self.assertIn(needle, str(ctx.exception))

    def test_accepts_empty_and_full_blocks(self):
        self.ok({})
        self.ok({"wall_t": 0.45, "envelope": ["WindowShutters"], "exempt": ["Corner"], "seals": "hero",
                 "fill": [{"name": "S1", "min": [0, 0, 0], "max": [1, 1, 1]}]})
        self.ok({"wall_t": 1})

    def test_defaults(self):
        st = bgs.growth_settings(None)
        self.assertEqual(st["wall_t"], 0.45)
        self.assertEqual(st["envelope"], [])
        self.assertEqual(st["exempt"], [])
        self.assertEqual(st["seals"], "scaffold")
        self.assertEqual(st["fill"], [])

    def test_rejects_bad_blocks(self):
        self.bad([], "object")
        self.bad({"wal_t": 0.45}, "wal_t")
        self.bad({"wall_t": 0.2}, "wall_t")
        self.bad({"wall_t": True}, "wall_t")
        self.bad({"wall_t": "0.45"}, "wall_t")
        self.bad({"seals": "maybe"}, "seals")
        self.bad({"envelope": "Shutter"}, "envelope")
        self.bad({"envelope": [""]}, "envelope")
        self.bad({"exempt": [3]}, "exempt")
        self.bad({"fill": {"name": "x"}}, "fill")
        self.bad({"fill": [{"name": "x", "min": [0, 0, 0]}]}, "fill")
        self.bad({"fill": [{"name": "x", "min": [0, 0], "max": [1, 1, 1]}]}, "fill")
        self.bad({"fill": [{"name": "x", "min": [0, 0, 0], "max": [1, 0, 1]}]}, "fill")
        self.bad({"fill": [{"name": "x y", "min": [0, 0, 0], "max": [1, 1, 1]}]}, "fill")
        self.bad({"fill": [{"name": "x", "min": [0, 0, 0], "max": [1, 1, 1], "pad": 1}]}, "fill")

    def test_committed_configs_load(self):
        raw = json.loads((TOOLS / "structure_configs.json").read_text())
        for structure in raw:
            centre, st = bgs.load_structure(TOOLS / "structure_configs.json", structure)
            self.assertEqual(len(centre), 2)
            self.assertGreaterEqual(st["wall_t"], 0.24)

    def test_scene_offset_maps_from_blender_to_gltf(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "c.json"
            p.write_text(json.dumps({"q": {"name": "q", "scene_offset": [-7.0, 3.0, 1.0]}}))
            centre, _st = bgs.load_structure(p, "q")
        self.assertEqual(centre, (-7.0, -3.0))


# ------------------------------------------------------------------------------------------------
# GLB helpers for the transform test
# ------------------------------------------------------------------------------------------------


def _glb_json(data: bytes) -> dict:
    ln, _tp = struct.unpack_from("<II", data, 12)
    return json.loads(data[20:20 + ln].decode("utf-8"))


def _patch_node(data: bytes, index: int, fields: dict) -> bytes:
    doc = _glb_json(data)
    ln, _tp = struct.unpack_from("<II", data, 12)
    rest = data[20 + ln:]
    doc["nodes"][index].update(fields)
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    total = 12 + 8 + len(js) + len(rest)
    return b"glTF" + struct.pack("<II", 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js + rest


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=1).result
    sys.exit(0 if result.wasSuccessful() else 1)
