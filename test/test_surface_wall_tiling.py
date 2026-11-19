#!/usr/bin/env python3
"""Every surface_wall hero wall piece sits in its own slot; the openings are open (ivy-b1e.41).

The kit wall pieces are 2 m wide (MODULE). surface_wall used to place 5 pieces per 6 m side at
module_offsets [-2, -1, 0, 1, 2], so neighbours overlapped by 1 m and the Straight pieces either
side of the south window and the two doors covered the openings with solid brick. The hero now
tiles each side with whole pieces that touch but do not overlap -- the shape the dynamic structure
builder will assemble from pieces -- and keeps the south wide window, the south door and the open
east door.

Checks, from tools/structure_configs.json and from the hero GLB (no Blender needed):
  * config: consecutive module offsets are at least one module apart and the pieces span the side;
  * config: the south side has the wide window and a door, the east side a door, and the east door's
    aperture id is the one in open_apertures;
  * hero: on each side, no two Wall_UnevenBrick nodes overlap along the wall by more than 1 mm;
  * hero: rays through each opening (a grid inset 0.10 m from the aperture rectangle), run along the
    wall normal through the whole wall band, meet no wall piece other than the opening's own.

Run with:
    python3 -m unittest discover -s test -p "test_surface_wall_tiling.py"
or point it at another hero (a scratch build):
    python3 test/test_surface_wall_tiling.py path/to/surface_wall_hero.glb
"""

from __future__ import annotations

import json
import math
import re
import sys
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO / "tools"))

import build_growth_surface as bgs  # noqa: E402
import kit_openings  # noqa: E402

HERO = _REPO / "assets" / "structures" / "surface_wall_hero.glb"
CONFIGS = _REPO / "tools" / "structure_configs.json"
MODULE = 2.0  # kit wall piece width (tools/build_structures.py MODULE)
OVERLAP_TOL = 1e-3
INSET = 0.10
# Aperture rectangles in wall-local (along, height), from tools/build_structures.py APERTURE_SPECS.
APERTURE_SPECS = {
    "door": (-0.625, 0.625, 0.0, 2.475),
    "wide_win": (-0.35, 0.55, 1.05, 2.725),
    "thin_win": (-0.30, 0.30, 1.05, 2.525),
}
SIDE_OF_YAW = {0.0: "S", 90.0: "E", 180.0: "N", 270.0: "W"}
WALL_NODE = re.compile(r"_hero_(Wall_UnevenBrick_\w+?)_(\d+)_(\d+)$")


def _cfg():
    return json.loads(CONFIGS.read_text())["surface_wall"]


def _side_vectors(yaw):
    """Outward normal and along-wall tangent, in glTF (y up), for a Blender wall yaw."""
    r = math.radians(yaw)
    nb, tb = (math.sin(r), -math.cos(r)), (math.cos(r), math.sin(r))
    # Blender (x, y, z) -> glTF (x, z, -y)
    return (nb[0], 0.0, -nb[1]), (tb[0], 0.0, -tb[1])


def _kind(piece):
    if "Door" in piece:
        return "door"
    if "Window" in piece:
        return "thin_win" if "Thin" in piece else "wide_win"
    return None


def _apertures(cfg):
    out = []
    for si, sides in enumerate(cfg["storey_sides"]):
        tag = "ground" if si == 0 else "upper"
        for yaw, names in sides:
            for i, nm in enumerate(names):
                kind = _kind(nm)
                if kind:
                    out.append({
                        "id": f"{cfg['name']}_{tag}_{kind}_{SIDE_OF_YAW[yaw]}_{i}",
                        "yaw": yaw, "index": i, "kind": kind, "piece": nm,
                        "offset": cfg["module_offsets"][i], "z_base": si * 3.12,
                    })
    return out


def _hero_ok():
    return HERO.is_file() and HERO.read_bytes()[:4] == b"glTF"


class SurfaceWallTilingConfigTest(unittest.TestCase):
    def test_pieces_do_not_overlap_and_span_the_side(self):
        cfg = _cfg()
        offs = sorted(cfg["module_offsets"])
        gaps = [round(b - a, 6) for a, b in zip(offs, offs[1:])]
        self.assertTrue(all(g >= MODULE - 1e-6 for g in gaps),
                        f"module_offsets {offs}: neighbours closer than one {MODULE} m module: {gaps}")
        self.assertAlmostEqual(offs[0] - MODULE / 2.0, -cfg["half"], delta=1e-6, msg="first piece starts at the corner")
        self.assertAlmostEqual(offs[-1] + MODULE / 2.0, cfg["half"], delta=1e-6, msg="last piece ends at the corner")

    def test_openings_kept(self):
        cfg = _cfg()
        sides = {SIDE_OF_YAW[yaw]: names for yaw, names in cfg["storey_sides"][0]}
        self.assertIn("Wall_UnevenBrick_Window_Wide_Round", sides["S"])
        self.assertIn("Wall_UnevenBrick_Door_Round", sides["S"])
        self.assertIn("Wall_UnevenBrick_Door_Round", sides["E"])
        east_doors = [a["id"] for a in _apertures(cfg) if a["yaw"] == 90.0 and a["kind"] == "door"]
        self.assertEqual(len(east_doors), 1)
        self.assertEqual(cfg.get("open_apertures"), east_doors, "the east door is the open aperture")


@unittest.skipUnless(_hero_ok(), "surface_wall_hero.glb not materialised")
class SurfaceWallTilingHeroTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.walls = {}
        for name, verts, tris in bgs.read_glb(HERO):
            m = WALL_NODE.search(name)
            if m and verts:
                cls.walls[name] = (float(m.group(2)), int(m.group(3)), m.group(1), verts, tris)

    def test_no_two_wall_pieces_on_a_side_overlap(self):
        by_side = {}
        for name, (yaw, _i, _p, verts, _t) in self.walls.items():
            _n, t = _side_vectors(yaw)
            along = [v[0] * t[0] + v[2] * t[2] for v in verts]
            by_side.setdefault(yaw, []).append((min(along), max(along), name))
        self.assertEqual(sorted(by_side), [0.0, 90.0, 180.0, 270.0])
        report = []
        for yaw, spans in sorted(by_side.items()):
            spans.sort()
            for a, b in zip(spans, spans[1:]):
                over = a[1] - b[0]
                if over > OVERLAP_TOL:
                    report.append((SIDE_OF_YAW[yaw], a[2], b[2], round(over, 4)))
        self.assertEqual(report, [], f"(side, piece, next piece, overlap m): {report}")

    def test_openings_have_no_other_wall_piece_in_front_or_behind(self):
        cfg = _cfg()
        r_wall = cfg["half"] - 0.09
        report = []
        for ap in _apertures(cfg):
            n, t = _side_vectors(ap["yaw"])
            x0, x1, z0, z1 = APERTURE_SPECS[ap["kind"]]
            own = f"{ap['piece']}_{int(ap['yaw'])}_{ap['index']}"
            for fa in (0.0, 0.5, 1.0):
                for fz in (0.0, 0.5, 1.0):
                    a = ap["offset"] + (x0 + INSET) + fa * ((x1 - x0) - 2 * INSET)
                    h = ap["z_base"] + (z0 + INSET) + fz * ((z1 - z0) - 2 * INSET)
                    o = (n[0] * (r_wall + 0.5) + t[0] * a, h, n[2] * (r_wall + 0.5) + t[2] * a)
                    d = (-n[0], 0.0, -n[2])
                    for name, (_y, _i, _p, verts, tris) in self.walls.items():
                        if name.endswith(own):
                            continue
                        hit = bgs.ray_first_hit(o, d, verts, tris, reach=1.2)
                        if hit is not None:
                            report.append((ap["id"], round(a, 3), round(h, 3), name))
        hits = {}
        for aid, _a, _h, name in report:
            hits.setdefault((aid, name), 0)
            hits[(aid, name)] += 1
        self.assertEqual(hits, {}, f"(aperture, wall piece in the opening): rays hit {hits}")

    def test_window_glass_covers_the_whole_kit_hole(self):
        """With the window piece in its own slot its hole is really open. The kit hole
        (tools/kit_openings.py KIT_HOLES, 1.20 m wide) is wider than the APERTURE_SPECS glass
        (0.90 m), which left unglazed strips; in slot -2 the west one looks straight into the room
        corner. A ray from outside through any point of the kit hole must meet the glass first."""
        cfg = _cfg()
        nodes = [(n, v, t) for n, v, t in bgs.read_glb(HERO) if v]
        r_out = cfg["half"] - 0.09 + 0.3
        report = []
        for ap in _apertures(cfg):
            if ap["kind"] == "door":
                continue
            n, t = _side_vectors(ap["yaw"])
            glass = f"_hero_Seal_{ap['id']}_glass"
            for x, z in kit_openings.coverage_probe_points(ap["piece"], inset=0.02):
                a = ap["offset"] + x
                o = (n[0] * r_out + t[0] * a, ap["z_base"] + z, n[2] * r_out + t[2] * a)
                d = (-n[0], 0.0, -n[2])
                best = None
                for name, verts, tris in nodes:
                    hit = bgs.ray_first_hit(o, d, verts, tris, reach=1.0)
                    if hit is not None and (best is None or hit < best[0]):
                        best = (hit, name)
                # The hole is stored as its bounding rectangle; at the arch's top corners the
                # window piece itself (the spandrel) is met first, which is solid brick.
                own = f"_hero_{ap['piece']}_{int(ap['yaw'])}_{ap['index']}"
                if best is None or not (best[1].endswith(glass) or best[1].endswith(own)):
                    report.append((ap["id"], round(x, 3), round(z, 3), None if best is None else best[1]))
        self.assertEqual(report, [], f"(window, x, z, first node met): {report}")

    def test_window_glass_sits_between_the_wall_sheets(self):
        """Glass set inside the room past the 0.20 m kit wall (the old TARGET_T / 2 = 0.225 m)
        leaves a sliver between it and the inner sheet that looks into the room; it must sit
        between the outer (2.91) and inner (2.71) sheets, reaching past the hole on every edge."""
        cfg = _cfg()
        outer = cfg["half"] - 0.09
        glasses = {n: v for n, v, _t in bgs.read_glb(HERO) if n.endswith("_glass")}
        for ap in _apertures(cfg):
            if ap["kind"] == "door":
                continue
            name = next((n for n in glasses if n.endswith(f"_hero_Seal_{ap['id']}_glass")), None)
            self.assertIsNotNone(name, f"no glass for {ap['id']}: {sorted(glasses)}")
            n, t = _side_vectors(ap["yaw"])
            verts = glasses[name]
            radial = [v[0] * n[0] + v[2] * n[2] for v in verts]
            along = [v[0] * t[0] + v[2] * t[2] - ap["offset"] for v in verts]
            self.assertGreater(min(radial), outer - 0.20 + 1e-3, f"{name} reaches the inner sheet")
            self.assertLess(max(radial), outer - 1e-3, f"{name} reaches the outer sheet")
            hole = kit_openings.KIT_HOLES[ap["piece"]]
            self.assertLess(min(along), hole["x0"] - 0.01, f"{name} short of the hole's edge")
            self.assertGreater(max(along), hole["x1"] + 0.01, f"{name} short of the hole's edge")

    def test_open_door_floor_stands_on_the_ground_inside_the_room(self):
        """With the east door really open, ivy reaches the room: the reveal floor must not leave a
        slot under 0.10 m against the ground (proxy FloorSlab top, y 0) or the door jambs."""
        cfg = _cfg()
        floors = {n: v for n, v, _t in bgs.read_glb(HERO)
                  if any(n.endswith(f"_hero_Reveal_{aid}_floor") for aid in cfg["open_apertures"])}
        self.assertEqual(len(floors), len(cfg["open_apertures"]), f"reveal floors: {sorted(floors)}")
        inner = cfg["half"] - 0.09 - 0.45  # sim wall inner face (wall_exterior - TARGET_T)
        for name, verts in floors.items():
            self.assertAlmostEqual(min(v[1] for v in verts), 0.0, delta=1e-4, msg=f"{name} bottom")
            reach = max(max(abs(v[0]), abs(v[2])) for v in verts)
            self.assertLessEqual(reach, inner + 1e-4, f"{name} reaches into the wall ({reach:.4f})")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and not args[0].startswith("-"):
        HERO = Path(args.pop(0)).resolve()
    unittest.main(argv=[sys.argv[0]] + args)
