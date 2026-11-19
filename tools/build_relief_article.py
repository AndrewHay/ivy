#!/usr/bin/env python3
"""Relief test article for SG-9(d): hero GLB and the growth-surface variants (ivy-b1e.6).

IMPLEMENTATION.md SD-MESH-19.5 (the article) and AR-MESH-20.4 / 20.9 (the variants). The article
is a synthetic wall built from boxes, so every distance the probe reports can be checked against
exact geometry. It is a test structure, not a player-facing building.

Usage (project root):
  python3 tools/build_relief_article.py hero <out_dir>
      writes <out_dir>/relief_article_hero.glb      the hero: sharp edges, slot S1, plaque U1
             <out_dir>/relief_article_bbox_sim.glb  bounding-box proxy, z -0.45 .. 0.10 (D6)
  python3 tools/build_relief_article.py fillets <relief_article_sim.glb> <out_dir>
      writes <out_dir>/relief_article_r025_sim.glb  the sharp variant + 0.025 m inside-corner fillets
             <out_dir>/relief_article_r050_sim.glb  the sharp variant + 0.050 m inside-corner fillets

The sharp variant itself is NOT written here: it is tools/build_growth_surface.py output from the
hero (the pipeline's first customer), with S1 closed by the filler declared in
tools/relief_article_config.json and U1 left to the tool:

  python3 tools/build_growth_surface.py assets/structures/relief_article_hero.glb \\
      assets/structures/relief_article_hero.glb assets/structures/relief_article_sim.glb \\
      --structure relief_article --config tools/relief_article_config.json

(the hero is passed as its own scaffold: it has no scaffold nodes, so nothing is copied from it).
The fillet variants exist only for the owner's feel read (AR-MESH-20.4, G7); the chosen pipeline
keeps collision sharp and lets the SDF carry the fillet.

Frame: glTF = Godot axes, x right, y up, metres; the front face is z = 0 facing +z; ground y = 0.
Every solid is a closed box, one glTF node each; solids that meet overlap by 1 mm and never share
a face wider than that (AR-MESH-20.3 rule 8). Output bytes are deterministic.

Standard library only. Self-test: tools/test_build_relief_article.py.
"""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import build_growth_surface as bgs  # noqa: E402

STRUCTURE = "relief_article"
CONFIG_PATH = TOOLS_DIR / "relief_article_config.json"
GENERATOR = "ivy tools/build_relief_article.py v1"

# --- SD-MESH-19.5 table ---------------------------------------------------------------------------
WALL_X = (-1.80, 1.80)
WALL_Y = (0.0, 3.00)
WALL_BACK_Z = -0.45
RIB_CENTRES = (-1.575, -1.125, -0.675, -0.225)  # R1 .. R4
RIB_HALF = 0.075
PROUD = 0.10  # ribs and rail stand this far out of z = 0
RAIL_X = (-1.65, -0.15)
RAIL_Y = (1.425, 1.575)
# Recesses: (id, x0, x1, y0, y1, depth)
N1 = ("N1", 0.30, 0.90, 0.60, 1.50, 0.20)
M1 = ("M1", 1.20, 1.36, 0.60, 0.90, 0.06)
S1 = ("S1", 1.50, 1.54, 1.50, 2.50, 0.10)
RECESSES = (N1, M1, S1)
U1 = (0.30, 0.90, 2.00, 2.60, 0.02)  # plaque x0, x1, y0, y1, proud

OVERLAP = 0.001  # AR-MESH-20.3 rule 8
EMBED = 0.01  # proud parts reach this far into the body
FILLET_CHORDS = 3  # chords per quarter turn
FILLET_APEX_INSET = 0.002  # wedge apex pushed into the solid so it overlaps the corner


# ------------------------------------------------------------------------------------------------
# Hero
# ------------------------------------------------------------------------------------------------


def _bays():
    """Clear x ranges between neighbouring ribs (the three bays)."""
    out = []
    for k in range(len(RIB_CENTRES) - 1):
        out.append((RIB_CENTRES[k] + RIB_HALF, RIB_CENTRES[k + 1] - RIB_HALF))
    return out


def hero_boxes():
    """[(name, lo, hi)] world boxes of the hero, in a fixed order."""
    xs = sorted({*WALL_X, *[r[1] for r in RECESSES], *[r[2] for r in RECESSES]})
    ys = sorted({*WALL_Y, *[r[3] for r in RECESSES], *[r[4] for r in RECESSES]})
    nx, ny = len(xs) - 1, len(ys) - 1

    def top(i, j):
        cx = 0.5 * (xs[i] + xs[i + 1])
        cy = 0.5 * (ys[j] + ys[j + 1])
        for _rid, x0, x1, y0, y1, depth in RECESSES:
            if x0 < cx < x1 and y0 < cy < y1:
                return -depth
        return 0.0

    out = []
    for i in range(nx):
        for j in range(ny):
            t = top(i, j)
            lo = [xs[i], ys[j], WALL_BACK_Z]
            hi = [xs[i + 1], ys[j + 1], t]
            # Grow 1 mm into every neighbour at least as tall: the grown strip is buried in it,
            # and of any two neighbours at least one grows into the other (rule 8).
            if i > 0 and top(i - 1, j) >= t:
                lo[0] -= OVERLAP
            if i < nx - 1 and top(i + 1, j) >= t:
                hi[0] += OVERLAP
            if j > 0 and top(i, j - 1) >= t:
                lo[1] -= OVERLAP
            if j < ny - 1 and top(i, j + 1) >= t:
                hi[1] += OVERLAP
            out.append((f"{STRUCTURE}_hero_Wall_Body_{i}_{j}", tuple(lo), tuple(hi)))
    for k, c in enumerate(RIB_CENTRES):
        out.append((f"{STRUCTURE}_hero_Rib_R{k + 1}", (c - RIB_HALF, WALL_Y[0], -EMBED),
                    (c + RIB_HALF, WALL_Y[1], PROUD)))
    # The rail's ends sit 1 mm inside R1 and R4, flush with their outer faces as a union.
    out.append((f"{STRUCTURE}_hero_Rail_H1", (RAIL_X[0] + OVERLAP, RAIL_Y[0], -EMBED),
                (RAIL_X[1] - OVERLAP, RAIL_Y[1], PROUD)))
    out.append((f"{STRUCTURE}_hero_Plaque_U1", (U1[0], U1[2], -EMBED), (U1[1], U1[3], U1[4])))
    return out


def hero_meshes():
    """[(name, verts, tris)] of the hero (shared-vertex boxes, wound outward)."""
    out = []
    for name, lo, hi in hero_boxes():
        v, t = bgs.box_mesh(lo, hi)
        out.append((name, v, t))
    return out


_FACES = (  # (axis, side, corner order wound counter-clockwise seen from outside)
    (0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1),
)


def _box_faces_with_normals(lo, hi):
    """24 vertices (4 per face) with flat normals and metre-scale box-mapped UVs."""
    pos, nrm, uv, tris = [], [], [], []
    for axis, side in _FACES:
        a1, a2 = (axis + 1) % 3, (axis + 2) % 3
        n = [0.0, 0.0, 0.0]
        n[axis] = 1.0 if side else -1.0
        quad = []
        for u, w in ((0, 0), (1, 0), (1, 1), (0, 1)):
            p = [0.0, 0.0, 0.0]
            p[axis] = hi[axis] if side else lo[axis]
            p[a1] = hi[a1] if u else lo[a1]
            p[a2] = hi[a2] if w else lo[a2]
            quad.append(tuple(p))
        base = len(pos)
        for p in quad:
            pos.append(p)
            nrm.append(tuple(n))
            uv.append((p[a1], -p[a2]))
        # (a1, a2, axis) is right-handed, so the quad above runs counter-clockwise seen from +axis.
        if side:
            tris += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
        else:
            tris += [(base, base + 2, base + 1), (base, base + 3, base + 2)]
    return pos, nrm, uv, tris


def hero_glb_bytes():
    """Deterministic hero GLB: one node per box, POSITION + NORMAL + TEXCOORD_0, no transforms."""
    blob = bytearray()
    views, accessors, gl_meshes, nodes = [], [], [], []

    def add_view(data, target):
        off = len(blob)
        blob.extend(data)
        blob.extend(b"\0" * (-len(blob) % 4))
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        return len(views) - 1

    for name, lo, hi in hero_boxes():
        pos, nrm, uv, tris = _box_faces_with_normals(lo, hi)
        f32 = [tuple(bgs._f32(c) for c in p) for p in pos]
        pv = add_view(b"".join(struct.pack("<fff", *p) for p in f32), 34962)
        accessors.append({"bufferView": pv, "componentType": 5126, "count": len(f32), "type": "VEC3",
                          "min": [min(p[k] for p in f32) for k in range(3)],
                          "max": [max(p[k] for p in f32) for k in range(3)]})
        pa = len(accessors) - 1
        nv = add_view(b"".join(struct.pack("<fff", *n) for n in nrm), 34962)
        accessors.append({"bufferView": nv, "componentType": 5126, "count": len(nrm), "type": "VEC3"})
        na = len(accessors) - 1
        tv = add_view(b"".join(struct.pack("<ff", *t) for t in uv), 34962)
        accessors.append({"bufferView": tv, "componentType": 5126, "count": len(uv), "type": "VEC2"})
        ta = len(accessors) - 1
        iv = add_view(b"".join(struct.pack("<III", *t) for t in tris), 34963)
        accessors.append({"bufferView": iv, "componentType": 5125, "count": len(tris) * 3, "type": "SCALAR"})
        ia = len(accessors) - 1
        gl_meshes.append({"name": name, "primitives": [{
            "attributes": {"POSITION": pa, "NORMAL": na, "TEXCOORD_0": ta}, "indices": ia}]})
        nodes.append({"name": name, "mesh": len(gl_meshes) - 1})
    nodes.append({"name": f"Hero_{STRUCTURE}", "children": list(range(len(nodes)))})
    doc = {
        "asset": {"version": "2.0", "generator": GENERATOR},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": gl_meshes,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(blob)
    return (b"glTF" + struct.pack("<II", 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js
            + struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


# ------------------------------------------------------------------------------------------------
# Growth-surface variants written here: bounding box (D6) and modelled fillets (owner's read)
# ------------------------------------------------------------------------------------------------


def bbox_meshes():
    v, t = bgs.box_mesh((WALL_X[0], WALL_Y[0], WALL_BACK_Z), (WALL_X[1], WALL_Y[1], PROUD))
    return [(f"{STRUCTURE}_sim_Box_i00", v, t)]


def inside_corner_lines():
    """[(a, b, e1, e2)]: every concave edge of the growth surface the probe crosses.

    a -> b runs along the corner; e1 and e2 are unit vectors from the corner line along each of
    the two faces that meet there, into the air. U1 (0.02 m, under the radius) and S1 (filled)
    have none."""
    lines = []
    x, y, z = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)
    mx, my = (-1.0, 0.0, 0.0), (0.0, -1.0, 0.0)
    y0, y1 = WALL_Y
    r_lo, r_hi = RAIL_Y
    # Ribs meeting the wall face. Bay-facing sides stop at the rail, which covers that corner.
    first, last = RIB_CENTRES[0] - RIB_HALF, RIB_CENTRES[-1] + RIB_HALF
    lines.append(((first, y0, 0.0), (first, y1, 0.0), mx, z))
    lines.append(((last, y0, 0.0), (last, y1, 0.0), x, z))
    for lo, hi in _bays():
        for xc, e in ((lo, x), (hi, mx)):
            lines.append(((xc, y0, 0.0), (xc, r_lo, 0.0), e, z))
            lines.append(((xc, r_hi, 0.0), (xc, y1, 0.0), e, z))
    # Rail meeting the wall face, one segment per bay, above and below.
    for lo, hi in _bays():
        lines.append(((lo, r_hi, 0.0), (hi, r_hi, 0.0), y, z))
        lines.append(((lo, r_lo, 0.0), (hi, r_lo, 0.0), my, z))
    # Rail meeting the ribs' side faces (vertical, out of the wall).
    for lo, hi in _bays():
        for xc, ex in ((lo, x), (hi, mx)):
            for yr, ey in ((r_hi, y), (r_lo, my)):
                lines.append(((xc, yr, 0.0), (xc, yr, PROUD), ex, ey))
    # Recess floors meeting their walls, and the recesses' vertical inside corners.
    for _rid, x0, x1, ra, rb, depth in (N1, M1):
        zf = -depth
        lines.append(((x0, ra, zf), (x0, rb, zf), x, z))
        lines.append(((x1, ra, zf), (x1, rb, zf), mx, z))
        lines.append(((x0, ra, zf), (x1, ra, zf), y, z))
        lines.append(((x0, rb, zf), (x1, rb, zf), my, z))
        for cx, ex in ((x0, x), (x1, mx)):
            for cy, ey in ((ra, y), (rb, my)):
                lines.append(((cx, cy, zf), (cx, cy, 0.0), ex, ey))
    return lines


def _prism(p0, p1, p2, axis_vec):
    """Closed prism over triangle p0 p1 p2 extruded by axis_vec, wound outward."""
    v = [p0, p1, p2, bgs.add(p0, axis_vec), bgs.add(p1, axis_vec), bgs.add(p2, axis_vec)]
    t = [(0, 2, 1), (3, 4, 5), (0, 1, 4), (0, 4, 3), (1, 2, 5), (1, 5, 4), (2, 0, 3), (2, 3, 5)]
    if bgs.signed_volume(v, t) < 0.0:
        t = [(a, c, b) for a, b, c in t]
    return v, t


def fillet_meshes(radius):
    """Fillet wedges of `radius` along every inside_corner_lines() line: per line a fan of
    FILLET_CHORDS convex prisms from an apex just inside the corner to the chords of the quarter
    circle. Chord ends run 1 mm past their arc points so neighbouring prisms overlap (rule 8)."""
    out = []
    tag = "r%03d" % int(round(radius * 1000))
    for li, (a, b, e1, e2) in enumerate(inside_corner_lines()):
        axis = bgs.sub(b, a)
        apex = bgs.sub(a, bgs.mul(bgs.add(e1, e2), FILLET_APEX_INSET))
        arc = []
        for s in range(FILLET_CHORDS + 1):
            th = 0.5 * math.pi * s / FILLET_CHORDS
            arc.append(bgs.add(a, bgs.add(bgs.mul(e1, radius * (1.0 - math.sin(th))),
                                          bgs.mul(e2, radius * (1.0 - math.cos(th))))))
        for s in range(FILLET_CHORDS):
            d = bgs.norm(bgs.sub(arc[s + 1], arc[s]))
            q0 = bgs.sub(arc[s], bgs.mul(d, OVERLAP))
            q1 = bgs.add(arc[s + 1], bgs.mul(d, OVERLAP))
            v, t = _prism(apex, q0, q1, axis)
            out.append((f"{STRUCTURE}_sim_Fillet_{tag}_{li:02d}_{s}", v, t))
    return out


# ------------------------------------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------------------------------------

USAGE = ("usage: python3 tools/build_relief_article.py hero <out_dir>\n"
         "       python3 tools/build_relief_article.py fillets <relief_article_sim.glb> <out_dir>")


def main(argv):
    if len(argv) == 2 and argv[0] == "hero":
        out = Path(argv[1])
        out.mkdir(parents=True, exist_ok=True)
        (out / f"{STRUCTURE}_hero.glb").write_bytes(hero_glb_bytes())
        (out / f"{STRUCTURE}_bbox_sim.glb").write_bytes(bgs.glb_bytes(bbox_meshes(), f"Sim_{STRUCTURE}"))
        print(f"wrote {out / (STRUCTURE + '_hero.glb')} ({len(hero_boxes())} solids) and "
              f"{out / (STRUCTURE + '_bbox_sim.glb')}")
        return 0
    if len(argv) == 3 and argv[0] == "fillets":
        sharp_path, out = Path(argv[1]), Path(argv[2])
        try:
            sharp = bgs.read_glb(sharp_path)
        except (OSError, ValueError) as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
        out.mkdir(parents=True, exist_ok=True)
        for radius in (0.025, 0.05):
            tag = "r%03d" % int(round(radius * 1000))
            wedges = fillet_meshes(radius)
            path = out / f"{STRUCTURE}_{tag}_sim.glb"
            path.write_bytes(bgs.glb_bytes(sharp + wedges, f"Sim_{STRUCTURE}"))
            print(f"wrote {path}: {len(sharp)} sharp solids + {len(wedges)} fillet wedges "
                  f"({len(inside_corner_lines())} inside-corner lines, r = {radius} m)")
        return 0
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
