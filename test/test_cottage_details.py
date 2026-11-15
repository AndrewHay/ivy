#!/usr/bin/env python3
"""ivy-b1e.17: cottage hero detail placement (door leaf, corner posts, shutters, glass).

Pure placement math from tools/cottage_layout.py, plus a check that the measured kit
constants still match the megakit glTFs when the (gitignored) kit is present.

Run with:
    python3 -m unittest discover -s test -p "test_cottage_details.py"
"""

from __future__ import annotations

import json
import math
import os
import struct
import sys
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO / "tools"))

import cottage_layout as cl  # noqa: E402

_KIT = Path(os.environ.get(
    "IVY_MEGAKIT_GLTF",
    "/Users/andrewhay/github/ivy/assets/_local/medieval_village_megakit/glTF",
))
_SHUTTER_Y = (-0.2882, -0.1525)  # WindowShutters_Wide_Flat_Closed native, Blender-local
_SHUTTER_Z = (1.0932, 2.5173)


def _rot(v, a):
    c, s = math.cos(a), math.sin(a)
    return (c * v[0] - s * v[1], s * v[0] + c * v[1])


class CottageStyleTest(unittest.TestCase):
    def test_default_is_production(self):
        self.assertEqual(cl.cottage_style({}), cl.COTTAGE_STYLE_DEFAULT)

    def test_override(self):
        style = cl.cottage_style({"IVY_COTTAGE_STYLE": '{"window": "flush", "door": "stretch"}'})
        self.assertEqual(style, {**cl.COTTAGE_STYLE_DEFAULT, "window": "flush", "door": "stretch"})

    def test_style_pieces_are_measured(self):
        # Every selectable window wall has a measured hole, so its seal can be sized.
        import kit_openings as ko
        for piece in cl.WINDOW_WALL_PIECES.values():
            self.assertIn(piece, ko.KIT_HOLES, piece)

    def test_cli_style_parses_and_overrides(self):
        self.assertEqual(cl.parse_cottage_style("window=frame, sill=shallow"),
                         {"window": "frame", "sill": "shallow"})
        self.assertEqual(cl.parse_cottage_style(""), {})
        for bad in ("sill", "sill=deep", "roof=frame", "window=frame,door"):
            with self.assertRaises(ValueError, msg=bad):
                cl.parse_cottage_style(bad)
        try:
            cl.set_cottage_style("door=stretch")
            self.assertEqual(cl.cottage_style({})["door"], "stretch")
        finally:
            cl.set_cottage_style("")
        self.assertEqual(cl.cottage_style({}), cl.COTTAGE_STYLE_DEFAULT)

    def test_plinth_covers_every_plain_bay_on_all_sides(self):
        door, windows = "front:1", ["front:0", "left:0"]
        try:
            cl.set_cottage_style("plinth=all_lr,window_wall=flat2")
            for side, bay in cl.all_wall_slots(3):
                slot = f"{side}:{bay}"
                piece = cl.piece_for_slot(slot, door, windows, "")
                if slot == door:
                    self.assertEqual(piece, cl.PIECE_WALL_DOOR)
                elif slot in windows:
                    self.assertEqual(piece, "Wall_Plaster_Window_Wide_Flat2")
                else:
                    self.assertEqual(piece, cl.PLINTH_L if bay % 2 == 0 else cl.PLINTH_R, slot)
            cl.set_cottage_style("plinth=all_l")
            self.assertEqual(cl.piece_for_slot("back:1", door, windows, ""), cl.PLINTH_L)
            cl.set_cottage_style("plinth=none")
            self.assertEqual(cl.piece_for_slot("back:1", door, windows, ""), cl.PIECE_WALL)
            # Production default: alternating plinth bays (owner's pick, ivy-b1e.17.5).
            cl.set_cottage_style("")
            self.assertEqual(cl.piece_for_slot("back:1", door, windows, ""), cl.PLINTH_R)
        finally:
            cl.set_cottage_style("")

    def test_bad_value_rejected(self):
        with self.assertRaises(ValueError):
            cl.cottage_style({"IVY_COTTAGE_STYLE": '{"window": "round"}'})
        with self.assertRaises(ValueError):
            cl.cottage_style({"IVY_COTTAGE_STYLE": '{"roof": "frame"}'})


class DoorLeafFitTest(unittest.TestCase):
    def _box(self, opening):
        off, (sx, sz) = cl.door_leaf_fit(opening)
        lo, hi = cl.DOOR_LEAF_BOUNDS
        s = (sx, 1.0, sz)
        return [off[a] + lo[a] * s[a] for a in range(3)], [off[a] + hi[a] * s[a] for a in range(3)], (sx, sz)

    def test_leaf_centred_and_covering_for_every_style(self):
        for style, op in cl.DOOR_OPENINGS.items():
            lo, hi, _ = self._box(op)
            self.assertAlmostEqual((lo[0] + hi[0]) / 2, (op["x0"] + op["x1"]) / 2, delta=0.02, msg=style)
            self.assertLessEqual(lo[0], op["x0"], style)
            self.assertGreaterEqual(hi[0], op["x1"], style)
            self.assertAlmostEqual(lo[2], op["z0"], places=6, msg=style)
            self.assertGreaterEqual(hi[2], op["z1"], style)
            self.assertAlmostEqual(lo[1], op["y_outer"], places=6, msg=style)

    def test_leaf_never_proud_of_the_wall_trim(self):
        for style, op in cl.DOOR_OPENINGS.items():
            lo, _hi, _ = self._box(op)
            self.assertGreaterEqual(lo[1], -cl.KIT_TRIM_DEPTH, style)

    def test_frame_style_keeps_kit_proportions(self):
        _lo, _hi, (sx, sz) = self._box(cl.DOOR_OPENINGS["frame"])
        self.assertLess(abs(sx - 1.0), 0.03)
        self.assertLess(abs(sz - 1.0), 0.03)

    def test_stretch_fills_the_bare_doorway_behind_the_plaster(self):
        lo, _hi, _ = self._box(cl.DOOR_OPENINGS["stretch"])
        self.assertGreaterEqual(lo[1], 0.0)


class CornerPostTest(unittest.TestCase):
    BAYS = 3

    def setUp(self):
        self.posts = cl.cottage_corner_posts(self.BAYS)

    def test_one_post_per_outer_corner_where_two_wall_ends_meet(self):
        ends = []
        for side, bay in cl.all_wall_slots(self.BAYS):
            pos, yaw = cl.cottage_slot(side, bay, self.BAYS)
            nx, ny = cl.cottage_outward_normal(yaw)
            for k in (-1.0, 1.0):
                ends.append((round(pos[0] - k * ny, 6), round(pos[1] + k * nx, 6)))
        self.assertEqual(len({p[0] for p in self.posts}), 4)
        for label, (cx, cy), _yaw, _s in self.posts:
            self.assertEqual(ends.count((round(cx, 6), round(cy, 6))), 2, label)

    def test_kit_minus_x_minus_y_faces_point_outward(self):
        for label, (cx, cy), yaw, _s in self.posts:
            d = _rot((-1.0, -1.0), yaw)
            self.assertAlmostEqual(d[0], math.copysign(1, cx), places=9, msg=label)
            self.assertAlmostEqual(d[1], math.copysign(1, cy), places=9, msg=label)

    def test_post_closes_the_trim_gap_and_is_barely_proud(self):
        hx, hy = cl.CORNER_POST_NATIVE_HALF
        for label, _xy, yaw, (ax, ay, _az) in self.posts:
            c, s = abs(math.cos(yaw)), abs(math.sin(yaw))
            ex = c * hx * ax + s * hy * ay
            ey = s * hx * ax + c * hy * ay
            self.assertAlmostEqual(ex, ey, places=6, msg=label)
            self.assertGreaterEqual(ex, cl.KIT_TRIM_DEPTH, label)
            self.assertLessEqual(ex - cl.KIT_TRIM_DEPTH, 0.02, label)

    def test_post_reaches_the_top_plate(self):
        for label, _xy, _yaw, (_ax, _ay, az) in self.posts:
            self.assertAlmostEqual(cl.CORNER_POST_NATIVE_H * az, cl.KIT_TRIM_TOP_Z, places=6, msg=label)


class ShutterFlushFitTest(unittest.TestCase):
    def setUp(self):
        self.s, self.dy, self.dz = cl.cottage_shutter_fit(_SHUTTER_Y, _SHUTTER_Z, cl.KIT_TRIM_DEPTH)

    def test_back_face_on_plaster(self):
        inner = self.s * _SHUTTER_Y[1] + self.dy
        self.assertLessEqual(inner, 0.0)
        self.assertLessEqual(abs(inner), 0.01)

    def test_front_face_within_the_trim(self):
        outer = self.s * _SHUTTER_Y[0] + self.dy
        self.assertGreaterEqual(outer, -cl.KIT_TRIM_DEPTH - 1e-9)

    def test_covers_the_hole_height(self):
        self.assertLess(_SHUTTER_Z[0] + self.dz, cl.COTTAGE_WINDOW_HOLE["z0"])
        self.assertGreater(_SHUTTER_Z[1] + self.dz, cl.COTTAGE_WINDOW_HOLE["z1"])


class WindowGlassTest(unittest.TestCase):
    def test_glass_overlaps_the_hole_on_every_edge(self):
        g, h = cl.COTTAGE_WINDOW_GLASS, cl.COTTAGE_WINDOW_HOLE
        self.assertLess(g["x0"], h["x0"])
        self.assertGreater(g["x1"], h["x1"])
        self.assertLess(g["z0"], h["z0"])
        self.assertGreater(g["z1"], h["z1"])

    def test_glass_and_hole_symmetric_in_x(self):
        # Front/back walls are a half turn from the side walls, which mirrors x.
        for spec in (cl.COTTAGE_WINDOW_GLASS, cl.COTTAGE_WINDOW_HOLE):
            self.assertAlmostEqual(spec["x0"], -spec["x1"], places=9)


def _gltf_bounds(name):
    """Per-material Blender-local (x, -z, y) bounds of a kit glTF."""
    path = _KIT / f"{name}.gltf"
    g = json.loads(path.read_text())
    bins, out = {}, {}
    for mesh in g["meshes"]:
        for prim in mesh["primitives"]:
            acc = g["accessors"][prim["attributes"]["POSITION"]]
            bv = g["bufferViews"][acc["bufferView"]]
            uri = g["buffers"][bv["buffer"]]["uri"]
            if uri not in bins:
                bins[uri] = (_KIT / uri).read_bytes()
            off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            stride = bv.get("byteStride", 12)
            pts = [struct.unpack_from("<3f", bins[uri], off + i * stride) for i in range(acc["count"])]
            pts = [(x, -z, y) for x, y, z in pts]
            mat = g["materials"][prim["material"]]["name"]
            prev = out.get(mat, [])
            out[mat] = prev + pts
    return {
        m: ([min(p[i] for p in v) for i in range(3)], [max(p[i] for p in v) for i in range(3)])
        for m, v in out.items()
    }


@unittest.skipUnless((_KIT / f"{cl.PIECE_CORNER_POST}.gltf").exists(), "megakit not present")
class KitConstantsMatchGltfTest(unittest.TestCase):
    def test_corner_post(self):
        lo, hi = _gltf_bounds(cl.PIECE_CORNER_POST)["MI_WoodTrim"]
        self.assertAlmostEqual(hi[0], cl.CORNER_POST_NATIVE_HALF[0], delta=1e-3)
        self.assertAlmostEqual(hi[1], cl.CORNER_POST_NATIVE_HALF[1], delta=1e-3)
        self.assertAlmostEqual(hi[2] - lo[2], cl.CORNER_POST_NATIVE_H, delta=1e-3)

    def test_wall_trim(self):
        lo, hi = _gltf_bounds(cl.PIECE_WALL)["MI_WoodTrim"]
        self.assertAlmostEqual(-lo[1], cl.KIT_TRIM_DEPTH, delta=1e-3)
        self.assertAlmostEqual(hi[2], cl.KIT_TRIM_TOP_Z, delta=1e-3)

    def test_door_leaf(self):
        b = _gltf_bounds(cl.PIECE_DOOR_LEAF)
        lo = [min(v[0][i] for v in b.values()) for i in range(3)]
        hi = [max(v[1][i] for v in b.values()) for i in range(3)]
        for got, want in zip(lo + hi, list(cl.DOOR_LEAF_BOUNDS[0]) + list(cl.DOOR_LEAF_BOUNDS[1])):
            self.assertAlmostEqual(got, want, delta=1e-3)

    def test_shutter(self):
        lo, hi = _gltf_bounds(cl.PIECE_SHUTTER)["MI_WoodTrim_Wear"]
        self.assertAlmostEqual(lo[1], _SHUTTER_Y[0], delta=1e-3)
        self.assertAlmostEqual(hi[1], _SHUTTER_Y[1], delta=1e-3)
        self.assertAlmostEqual(lo[2], _SHUTTER_Z[0], delta=1e-3)

    def test_detail_pieces_exist(self):
        for piece in (cl.PIECE_WINDOW_INSERT, cl.PIECE_DOOR_FRAME):
            self.assertTrue((_KIT / f"{piece}.gltf").exists(), piece)
        self.assertIn("MI_WindowGlass", _gltf_bounds(cl.PIECE_WINDOW_INSERT))


if __name__ == "__main__":
    unittest.main()
