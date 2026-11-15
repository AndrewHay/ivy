#!/usr/bin/env python3
"""The ivy cottage's growth-surface `fill` list, computed from its hero GLB (ivy-b1e.7).

Each entry bridges a gap narrower than 0.10 m between two hero pieces that
tools/build_growth_surface.py's slot check reports (AR-MESH-20.4: a slot is closed with a fill,
never left for ivy to wedge into):

  SillGap{L,F}      the 1.2 mm gap between each window's sill board and its nose
  ShutterSill{L,F}  the closed shutters standing 8 mm above the sill board (2.8 cm above the nose)
  BandSill{L,F}     the 6 cm groove between the wall's lower band and the sill board
  HeadPost{L,F}     the 9 cm gap between the window head and the corner post
  Notch{W,E}{S,N}k  the 7 mm clearance round the lowest gable purlins in each barge board's notch
                    (a convex `points` fill: the purlins are rotated to the roof pitch)
  Web{W,E}{S,N}     the 9 cm gap between the middle purlins' top face and the roof underside,
                    between the two barge boards

Usage (project root):
  python3 tools/cottage_growth_fills.py [assets/structures/ivy_hero.glb]          # print the list
  python3 tools/cottage_growth_fills.py --check [assets/structures/ivy_hero.glb]  # exit 1 if stale

Paste a printed list into the `fill` of `ivy`'s `growth_surface` block in
tools/structure_configs.json whenever the hero changes, then re-run the builder.
`tools/test_build_growth_surface.py` fails while the committed list is stale.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import build_growth_surface as g  # noqa: E402

E = 0.001  # each fill reaches 1 mm into the pieces it bridges; faces stay 1 mm inside them
NOTCH_DIAG = 0.0141  # a notch fill's corners move this far out: ~1 cm on every side of a square section
WEB_OVERLAP = 0.01  # a web reaches this far past the roof underside
WALL_FACE_X = -10.0  # the cottage's left (window) wall plaster face, glTF x
WALL_FACE_Z = -2.0  # its front wall plaster face, glTF z


def _node(hero, tail):
    for name, verts, tris in hero:
        if name.endswith(tail):
            v, t = g.weld(verts, tris)
            return [g.compact(v, isl) for isl in g.islands(len(v), t)]
    raise ValueError("no hero node ending in " + tail)


def _bounds(v):
    return [min(p[k] for p in v) for k in range(3)], [max(p[k] for p in v) for k in range(3)]


def _r(x):
    return round(x, 4)


def _box(name, lo, hi):
    return {"name": name, "min": [_r(x) for x in lo], "max": [_r(x) for x in hi]}


def _window_fills(hero):
    out = []
    for side, axis, face in (("left_0", 0, WALL_FACE_X), ("front_0", 2, WALL_FACE_Z)):
        tag = "L" if side == "left_0" else "F"
        along = 2 if axis == 0 else 0
        boxes = [_bounds(v) for v, t in _node(hero, "Window_Wide_Flat1_" + side) if g.is_closed(t)]
        low = [b for b in boxes if b[1][1] < 1.2]
        sill = max(low, key=lambda b: b[1][axis] - b[0][axis])  # the board, deepest
        nose = min(low, key=lambda b: b[0][axis])  # the most proud piece
        head = max(boxes, key=lambda b: b[1][1])
        sh_lo, sh_hi = _bounds([p for v, _t in _node(hero, "WindowShutters_Wide_Flat_Closed_" + side) for p in v])
        band = [b for b in (_bounds(v) for v, _t in _node(hero, "Wall_Plaster_Window_Wide_Flat_" + side))
                if b[1][1] < 1.0 and b[0][1] > 0.3][0]
        post = _bounds(_node(hero, "CornerPost_BL" if side == "left_0" else "CornerPost_FL")[0][0])

        lo, hi = [0.0] * 3, [0.0] * 3
        lo[axis], hi[axis] = nose[1][axis] - 2 * E, sill[0][axis] + 2 * E
        lo[1], hi[1] = nose[0][1] + E, nose[1][1] - E
        lo[along], hi[along] = sill[0][along] + E, sill[1][along] - E
        out.append(_box("SillGap" + tag, lo, hi))

        lo, hi = [0.0] * 3, [0.0] * 3
        lo[axis], hi[axis] = sh_lo[axis] + E, face + E
        lo[1], hi[1] = nose[1][1] - E, sh_lo[1] + E
        lo[along], hi[along] = sh_lo[along] + E, sh_hi[along] - E
        out.append(_box("ShutterSill" + tag, lo, hi))

        lo, hi = [0.0] * 3, [0.0] * 3
        lo[axis], hi[axis] = band[0][axis] + E, band[1][axis] - E
        lo[1], hi[1] = band[1][1] - E, sill[0][1] + E
        lo[along], hi[along] = sill[0][along] + E, sill[1][along] - E
        out.append(_box("BandSill" + tag, lo, hi))

        lo, hi = [0.0] * 3, [0.0] * 3
        if side == "left_0":
            lo[along], hi[along] = head[1][along] - E, post[0][along] + E
        else:
            lo[along], hi[along] = post[1][along] - E, head[0][along] + E
        lo[axis], hi[axis] = post[0][axis] + E, face + E
        lo[1], hi[1] = head[0][1] + E, head[1][1] - E
        out.append(_box("HeadPost" + tag, lo, hi))
    return out


def _purlin_fills(hero):
    out = []
    roof = _node(hero, "Roof_RoundTiles_4x6")
    boards = sorted((_bounds(v) for v, t in roof if g.is_closed(t) and max(p[1] for p in v) < 6.5),
                    key=lambda b: b[0][0])
    planes = []
    for v, t in roof:
        if not g.is_closed(t) and g.area_normal(v, t)[0][1] < -0.3:
            n, _a, c, _ = g.area_normal(v, t)
            planes.append((n, g.dot(n, c)))
    for gable, tag in (("Roof_Front_Brick4_-1", "W"), ("Roof_Front_Brick4_1", "E")):
        purlins = [(v, t) for v, t in _node(hero, gable) if len(t) == 10]
        xs = _bounds([p for v, _t in purlins for p in v])
        pair = sorted((b for b in boards if b[1][0] > xs[0][0] - 0.05 and b[0][0] < xs[1][0] + 0.05),
                      key=lambda b: b[0][0])
        between = (pair[0][1][0] - E, pair[1][0][0] + E)
        ordered = sorted(purlins, key=lambda it: (_bounds(it[0])[0][2] > 0, _bounds(it[0])[0][1]))
        for k, (v, _t) in enumerate(ordered):
            sec = g._hull_2d(sorted({(round(p[1], 4), round(p[2], 4)) for p in v}))
            cy = sum(q[0] for q in sec) / len(sec)
            cz = sum(q[1] for q in sec) / len(sec)
            zside = "S" if _bounds(v)[0][2] < 0 else "N"
            if k % 3 == 0:  # the lowest purlin of this slope: its barge-board notches
                big = []
                for qy, qz in sec:
                    dy, dz = qy - cy, qz - cz
                    ln = (dy * dy + dz * dz) ** 0.5
                    big.append((qy + dy / ln * NOTCH_DIAG, qz + dz / ln * NOTCH_DIAG))
                for j, b in enumerate(pair):
                    pts = [[_r(x), _r(qy), _r(qz)] for x in (b[0][0] - E, b[1][0] + E) for qy, qz in big]
                    out.append({"name": "Notch%s%s%d" % (tag, zside, j), "points": pts})
            elif k % 3 == 1:  # the middle purlin: the gap above it, between the boards
                want = 1.0 if zside == "S" else -1.0  # this slope's underside faces down and toward +-z
                n_u, off = min(planes, key=lambda pl: abs(pl[0][2] - want))
                up = g.mul(n_u, -1.0)
                top = sorted(sec, key=lambda q: -(q[0] * up[1] + q[1] * up[2]))[:2]
                pts = []
                for x in between:
                    for qy, qz in top:
                        p = (x, qy, qz)
                        q = g.add(p, g.mul(up, g.dot(n_u, p) - off + WEB_OVERLAP))
                        pts.append([_r(x), _r(qy), _r(qz)])
                        pts.append([_r(q[0]), _r(q[1]), _r(q[2])])
                out.append({"name": "Web%s%s" % (tag, zside), "points": pts})
    return out


CORNER_MARGIN = 0.01  # an eave-corner fill reaches this far past the slot the builder reports
CORNER_ROUNDS = 4


def _eave_corner_fills(hero, fills):
    """At the four eave corners the inner barge boards' lower ends stand 8-9 cm from the inward
    face of rule 11's eave lip (a slot under 0.10 m). Build with the other fills and bridge each
    such slot the builder reports with a box over the slot's sampled extent (its lo/hi hold sample
    points on both walls) grown CORNER_MARGIN; repeat while slots remain."""
    centre, settings = g.load_structure(TOOLS / "structure_configs.json", "ivy")
    scaffold = g.read_glb(TOOLS.parent / "assets" / "structures" / "ivy_sim.glb")
    out = []
    for _round in range(CORNER_ROUNDS):
        settings = dict(settings)
        settings["fill"] = fills + out
        _meshes, report = g.build(hero, scaffold, "ivy", centre, settings, fail_on_slots=False)
        corner = [s for s in report["slots"]
                  if all("Roof_RoundTiles" in n or "Fill_EaveCorner" in n for n in s["between"])
                  and s["position"][1] < 3.2]
        if not corner:
            return out
        for s in corner:
            tag = ("W" if s["position"][0] < -7.0 else "E") + ("S" if s["position"][2] < 0 else "N")
            name = "EaveCorner%s%d" % (tag, sum(1 for f in out if f["name"].startswith("EaveCorner" + tag)))
            out.append(_box(name, [x - CORNER_MARGIN for x in s["lo"]], [x + CORNER_MARGIN for x in s["hi"]]))
    raise ValueError("eave-corner slots remain after %d rounds of fills" % CORNER_ROUNDS)


def cottage_fills(hero):
    """The `fill` list for the cottage, in the order committed to structure_configs.json."""
    fills = _window_fills(hero) + _purlin_fills(hero)
    return fills + _eave_corner_fills(hero, fills)


def main(argv):
    check = "--check" in argv
    rest = [a for a in argv if a != "--check"]
    hero_path = Path(rest[0]) if rest else TOOLS.parent / "assets" / "structures" / "ivy_hero.glb"
    fills = cottage_fills(g.read_glb(hero_path))
    if check:
        raw = json.loads((TOOLS / "structure_configs.json").read_text())
        same = raw["ivy"].get("growth_surface", {}).get("fill") == fills
        print("ivy fills up to date" if same else "ivy fills STALE: regenerate and paste")
        return 0 if same else 1
    print(json.dumps(fills, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
