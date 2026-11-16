#!/usr/bin/env python3
"""ivy-b1e.19: sim seals cover the kit wall pieces' real openings.

Run with:
    python3 -m unittest discover -s test -p "test_kit_openings.py"
"""

from __future__ import annotations

import ast
import json
import os
import struct
import sys
import unittest
from collections import Counter
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO / "tools"))

import cottage_layout as cl  # noqa: E402
import kit_openings as ko  # noqa: E402

_KIT = Path(os.environ.get(
    "IVY_MEGAKIT_GLTF",
    "/Users/andrewhay/github/ivy/assets/_local/medieval_village_megakit/glTF",
))


def _aperture_specs():
    """APERTURE_SPECS literal from build_structures.py, without importing bpy."""
    tree = ast.parse((_REPO / "tools" / "build_structures.py").read_text())
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == "APERTURE_SPECS" for t in node.targets
        ):
            return ast.literal_eval(node.value)
    raise AssertionError("APERTURE_SPECS not found")


def _aperture_pieces():
    """Every door / window wall piece a structure config or the cottage can place."""
    cfgs = json.loads((_REPO / "tools" / "structure_configs.json").read_text())
    pieces = set()
    for cfg in cfgs.values():
        if cfg.get("layout") == "cottage":
            pieces |= {p for p in cl.cottage_kit_piece_names(cfg) if p.startswith("Wall_")}
            continue
        for sides in cfg.get("storey_sides", []):
            for _yaw, run in sides:
                pieces.update(run)
    return {p for p in pieces if "Door" in p or "Window" in p}


def _covers(outer, inner):
    return (outer["x0"] <= inner["x0"] and outer["x1"] >= inner["x1"]
            and outer["z0"] <= inner["z0"] and outer["z1"] >= inner["z1"])


class SealSpecTest(unittest.TestCase):
    def test_every_aperture_piece_has_a_measured_hole(self):
        pieces = _aperture_pieces()
        self.assertTrue(pieces)
        for piece in pieces:
            self.assertIn(piece, ko.KIT_HOLES, piece)

    def test_seal_covers_hole_with_tuck_on_every_edge(self):
        for piece, hole in ko.KIT_HOLES.items():
            seal = ko.seal_spec(piece)
            self.assertAlmostEqual(hole["x0"] - seal["x0"], ko.SEAL_TUCK, places=9, msg=piece)
            self.assertAlmostEqual(seal["x1"] - hole["x1"], ko.SEAL_TUCK, places=9, msg=piece)
            self.assertAlmostEqual(hole["z0"] - seal["z0"], ko.SEAL_TUCK, places=9, msg=piece)
            self.assertAlmostEqual(seal["z1"] - hole["z1"], ko.SEAL_TUCK, places=9, msg=piece)

    def test_unmeasured_piece_raises(self):
        with self.assertRaises(KeyError):
            ko.seal_spec("Wall_Plaster_Window_Wide_Round")

    def test_old_aperture_specs_left_strips_open(self):
        # The bug: the shared hero specs used to size the sim panels too.
        specs = _aperture_specs()
        kind = {"Door": "door", "Thin": "thin_win", "Wide": "wide_win"}
        for piece, hole in ko.KIT_HOLES.items():
            k = next(v for key, v in kind.items() if key in piece)
            self.assertFalse(_covers(specs[k], hole), f"{piece}: {specs[k]} vs {hole}")

    def test_edge_probes_would_have_caught_the_old_panels(self):
        # Probe points the old (APERTURE_SPECS-sized) panel does not cover: the build's
        # edge-coverage check reports these as LEAK FAIL; the old centre probe passed.
        specs = _aperture_specs()
        kind = {"Door": "door", "Thin": "thin_win", "Wide": "wide_win"}
        for piece in ko.KIT_HOLES:
            old = specs[next(v for key, v in kind.items() if key in piece)]
            outside = [
                (x, z) for x, z in ko.coverage_probe_points(piece)
                if not (old["x0"] <= x <= old["x1"] and old["z0"] <= z <= old["z1"])
            ]
            self.assertTrue(outside, piece)
            seal = ko.seal_spec(piece)
            for x, z in ko.coverage_probe_points(piece):
                self.assertTrue(seal["x0"] <= x <= seal["x1"] and seal["z0"] <= z <= seal["z1"], piece)

    def test_probe_points_lie_inside_the_hole(self):
        for piece, hole in ko.KIT_HOLES.items():
            pts = ko.coverage_probe_points(piece)
            self.assertEqual(len(pts), 9)
            for x, z in pts:
                self.assertTrue(hole["x0"] < x < hole["x1"], piece)
                self.assertTrue(hole["z0"] < z < hole["z1"], piece)


def _hole_outline(name):
    """Bounding box of the hole outline on the exterior (y=0) and interior (y=0.2)
    plaster planes: boundary edges of the plane's triangles not on the piece's outer
    rectangle. Blender-local (x, -z_gltf, y_gltf)."""
    g = json.loads((_KIT / f"{name}.gltf").read_text())
    bins, tris = {}, []
    for mesh in g["meshes"]:
        for prim in mesh["primitives"]:
            acc = g["accessors"][prim["attributes"]["POSITION"]]
            bv = g["bufferViews"][acc["bufferView"]]
            uri = g["buffers"][bv["buffer"]]["uri"]
            if uri not in bins:
                bins[uri] = (_KIT / uri).read_bytes()
            buf = bins[uri]
            off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            stride = bv.get("byteStride", 12)
            pts = [struct.unpack_from("<3f", buf, off + i * stride) for i in range(acc["count"])]
            pts = [(x, -z, y) for x, y, z in pts]
            ia = g["accessors"][prim["indices"]]
            ibv = g["bufferViews"][ia["bufferView"]]
            ioff = ibv.get("byteOffset", 0) + ia.get("byteOffset", 0)
            fmt = {5121: "B", 5123: "H", 5125: "I"}[ia["componentType"]]
            size = struct.calcsize(fmt)
            idx = [struct.unpack_from("<" + fmt, buf, ioff + i * size)[0] for i in range(ia["count"])]
            tris += [tuple(pts[i] for i in idx[t:t + 3]) for t in range(0, len(idx), 3)]
    xs, zs = [], []
    for plane in (0.0, 0.2):
        edges = Counter()
        for t in tris:
            if not all(abs(v[1] - plane) < 1e-3 for v in t):
                continue
            for i in range(3):
                a = tuple(round(c, 4) for c in t[i])
                b = tuple(round(c, 4) for c in t[(i + 1) % 3])
                edges[tuple(sorted((a, b)))] += 1
        for (a, b), count in edges.items():
            if count != 1:
                continue
            if all(abs(abs(p[0]) - 1.0) < 1e-3 for p in (a, b)):
                continue
            if all(p[2] < 1e-3 for p in (a, b)) or all(p[2] > 2.99 for p in (a, b)):
                continue
            for p in (a, b):
                if abs(p[0]) < 0.99 and p[2] < 2.99:
                    xs.append(p[0])
                    zs.append(p[2])
    return {"x0": min(xs), "x1": max(xs), "z0": min(zs), "z1": max(zs)}


@unittest.skipUnless((_KIT / "Wall_Plaster_Door_Flat.gltf").exists(), "megakit not present")
class KitHolesMatchGltfTest(unittest.TestCase):
    def test_stored_holes_contain_the_measured_outline(self):
        # Stored holes are symmetric in x (the aperture frame may mirror kit x on some
        # walls) and rounded outward, so they may exceed the outline by a few mm.
        for piece, hole in ko.KIT_HOLES.items():
            got = _hole_outline(piece)
            self.assertTrue(_covers(hole, got), f"{piece}: stored {hole} vs kit {got}")
            self.assertAlmostEqual(hole["x0"], -hole["x1"], places=9, msg=piece)
            for k in ("x0", "x1", "z0", "z1"):
                self.assertLess(abs(hole[k] - got[k]), 0.01, f"{piece} {k}: {hole[k]} vs {got[k]}")


if __name__ == "__main__":
    unittest.main()
