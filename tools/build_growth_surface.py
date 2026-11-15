#!/usr/bin/env python3
"""Growth-surface builder: hero GLB -> closed, relief-exact sim solids (IMPLEMENTATION.md AR-MESH-20).

Usage (project root):
  python3 tools/build_growth_surface.py <hero.glb> <scaffold_sim.glb> <out_sim.glb>
      [--structure <id>] [--report <report.json>] [--config <structure_configs.json>]

Runs between the Blender export and the SDF bake:

  Blender (owner-run) -> {id}_hero.glb + {id}_sim.glb (scaffold)
  this tool           -> final {id}_sim.glb
  tools/bake_mesh_sdf.py -> {id}_sim.sdf

Every hero node is turned into closed solids in world space by the rules of AR-MESH-20.3
(numbers below are the rule numbers used in the report):

  1   closed island                          kept (wound outward)
  2   planar sheet facing away from interior extruded wall_t toward the interior (holes -> reveals)
  3   planar sheet facing the interior       dropped
  4a  open island, boundary loop planar      loop capped (ear clipping, never a centroid fan)
  4b  open island, boundary loop not planar  skirt to the backing sheet's plane, 2 mm inside the slab,
                                             capped there; no backing sheet -> build failure
  5   solid wholly inside a rule-2 slab      dropped
  6   node listed under `envelope`           its oriented box, extended back to 2 mm inside the wall
  7   `_Seal_` node, seals = hero            its box, wall_t deep, named {id}_sim_Panel_<aperture>
  8   solids that meet                       overlap >= 1 mm: rule-2 sheets grow 1 mm at their outer
                                             edge; a 4a cap lying on another solid is pushed 2 mm in
  9   scaffold FloorSlab / RoofCap           vertices pulled 0.10 m inside the hero wall faces
  10  node listed under `exempt`             skipped
  11  node listed under `tile_field`         a tiled roof (ivy-b1e.7): the islands rule 4 cannot close
                                             are split at the ridge; each slope is extruded along its
                                             inward normal, exact on the tiles, down to the node's own
                                             underside (its down-facing islands) or, where none lies
                                             below, TILE_EDGE_DEPTH under the lowest tile point within
                                             FOLD_REACH (never through a fold); ridge caps are kept
                                             (rule 1) with a convex filling and a support

Scaffold nodes (FloorSlab, MidFloorSlab, RoofCap, RoofCone, CornerColumn_, Interior_, and Panel_
unless seals is hero) are copied from the scaffold GLB; every other scaffold node is discarded.
`fill` boxes from the config are added. Output: one glTF node per solid, named
{id}_sim_{hero tail}_iNN, no node transforms. Running the tool on its own output (as the
scaffold) gives a byte-identical file.

The build FAILS (exit 1, nothing written) instead of substituting a box when: an island fits no
rule; a capped or extruded result is not closed; a boundary loop more than 5 mm out of plane has
no backing sheet; a hero node that is not exempt produced no solid; an envelope has no wall
behind it; a config entry matches no hero node; or the proxy has an ivy-reachable slot narrower
than 0.10 m (the report lists position and width). Exit 2 is a usage or input error.

Settings come from the optional `growth_surface` block of the structure in
tools/structure_configs.json (validated by validate_growth_surface): wall_t (>= 0.24, default
0.45), envelope, exempt and tile_field (lists of substrings of the hero node tail), seals ("hero"
or "scaffold", default "scaffold"), fill (list of {"name", "min", "max"} glTF world boxes, or
{"name", "points"}: the convex hull of >= 4 points). The interior is the structure's footprint
centre, from its scene_offset.

Standard library only (like tools/bake_mesh_sdf.py). Self-test: tools/test_build_growth_surface.py.
"""

from __future__ import annotations

import json
import math
import re
import struct
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
DEFAULT_CONFIG = TOOLS_DIR / "structure_configs.json"

WELD_TOL = 1e-4  # 0.1 mm
SHEET_PLANAR_TOL = 1e-3  # rule 2/3: every vertex within 1 mm of the sheet's plane
SHEET_ALIGN_MIN = 0.99  # ... and every triangle facing the same way
LOOP_PLANAR_TOL = 5e-3  # rule 4a/4b split
CAP_INSET = 2e-3  # rule 4b / rule 8: caps sit 2 mm inside the slab
SLAB_GROW = 1e-3  # rule 8: sheets grow 1 mm at their outer boundary
CONTACT_TOL = 1e-3  # a cap within 1 mm of another solid "lands" on it
SLOT_MIN = 0.10  # narrowest allowed ivy-reachable slot
SLOT_PARALLEL_MIN = math.cos(math.radians(25.0))  # a slot's two walls face each other within 25 degrees
SCAFFOLD_PULL = 0.10  # rule 9
DEFAULT_WALL_T = 0.45
WALL_T_MIN = 0.24  # SD-MESH-17 solid-thickness floor
BACKING_REACH = 0.5  # a backing sheet lies at most this far behind the island centroid
BACKING_MARGIN = 0.10  # in-plane slack round a backing sheet's extent
BACKING_ALIGN_MIN = 0.5
ENVELOPE_REACH = 1.0  # an envelope extends at most this far to meet a wall
FACING_MIN = 0.2  # a sheet needs this much horizontal normal for the outward test
SCAFFOLD_TOKENS = ("FloorSlab", "MidFloorSlab", "RoofCap", "RoofCone", "CornerColumn_", "Interior_", "Panel_")
SEAL_TOKEN = "_Seal_"
GROWTH_SURFACE_KEYS = ("wall_t", "envelope", "exempt", "seals", "fill", "tile_field")
NAME_LIST_KEYS = ("envelope", "exempt", "tile_field")
HULL_EPS = 1e-7  # rule 11: a point within 0.1 um of a hull face is on it
TILE_EDGE_DEPTH = 0.05  # rule 11: thickness of a tile field where no hero underside lies below it.
# Thinner than SG-9 (c)'s 0.10 m inside probe; on the cottage 0.15 and 0.25 both leave slots under
# 0.10 m against the gutter beams and barge boards at the eave corners (ivy-b1e.7).
UNDERSIDE_ALIGN = 0.9  # rule 11: an underside faces within ~25 degrees of straight away from its slope
FOLD_REACH = 0.05  # rule 11: an overhang bottom lies under every tile point this close across the slope
RIDGE_END_KEEP = 0.10  # rule 11: a ridge cap's free end keeps this much of its hollow unsupported
RIDGE_SUPPORT_SHARE = 0.6  # rule 11: a cap's support spans the middle 60 % of its width
FILL_KEYS = ("name", "min", "max")
FILL_HULL_KEYS = ("name", "points")  # a fill as the convex hull of its points (a rotated box, say)
_GENERATED = re.compile(r"_i\d{2,}$")
_FILL_NAME = re.compile(r"^[A-Za-z0-9_]+$")
GENERATOR = "ivy tools/build_growth_surface.py v1"


class BuildError(Exception):
    """Hard build failure. `failures` lists every reason; `report` is the partial report."""

    def __init__(self, failures, report=None):
        self.failures = list(failures)
        self.report = report if report is not None else {}
        super().__init__("; ".join(self.failures))


class CapError(Exception):
    """A loop could not be triangulated as a simple polygon."""


class LoopError(Exception):
    """Boundary edges that do not form closed loops (non-manifold island)."""


# ------------------------------------------------------------------------------------------------
# Vector helpers
# ------------------------------------------------------------------------------------------------


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def length(a):
    return math.sqrt(dot(a, a))


def norm(a):
    ln = length(a)
    return (a[0] / ln, a[1] / ln, a[2] / ln) if ln > 1e-15 else (0.0, 0.0, 0.0)


def _f32(x):
    return struct.unpack("<f", struct.pack("<f", x))[0]


# ------------------------------------------------------------------------------------------------
# GLB read / write
# ------------------------------------------------------------------------------------------------


def _mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def _node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]  # column-major
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    tx, ty, tz = node.get("translation", (0.0, 0.0, 0.0))
    qx, qy, qz, qw = node.get("rotation", (0.0, 0.0, 0.0, 1.0))
    sx, sy, sz = node.get("scale", (1.0, 1.0, 1.0))
    r = [
        [1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw)],
        [2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw)],
        [2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)],
    ]
    s = (sx, sy, sz)
    t = (tx, ty, tz)
    return [[r[i][0] * s[0], r[i][1] * s[1], r[i][2] * s[2], t[i]] for i in range(3)] + [[0.0, 0.0, 0.0, 1.0]]


def read_glb(path):
    """Mesh nodes of a GLB as [(name, world verts, tris)] in glTF coordinates (y up)."""
    data = Path(path).read_bytes()
    if data[:4] != b"glTF":
        raise ValueError(f"not a GLB: {path}")
    off, doc, blob = 12, None, b""
    while off + 8 <= len(data):
        ln, tp = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + ln]
        off += ln
        if tp == 0x4E4F534A:
            doc = json.loads(chunk.decode("utf-8"))
        elif tp == 0x004E4942:
            blob = chunk
    if doc is None:
        raise ValueError(f"GLB without a JSON chunk: {path}")

    def accessor(i):
        a = doc["accessors"][i]
        bv = doc["bufferViews"][a["bufferView"]]
        start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        comp = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[a["componentType"]]
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        stride = bv.get("byteStride", n * struct.calcsize(comp))
        return [struct.unpack_from("<" + comp * n, blob, start + k * stride) for k in range(a["count"])]

    nodes = doc.get("nodes", [])
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    out = []
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        m = _node_matrix(n)
        j = parent.get(i)
        while j is not None:
            m = _mat_mul(_node_matrix(nodes[j]), m)
            j = parent.get(j)
        verts, tris = [], []
        for prim in doc["meshes"][n["mesh"]]["primitives"]:
            if prim.get("mode", 4) != 4:
                raise ValueError(f"{path}: node {n.get('name')} has a non-triangle primitive")
            base = len(verts)
            for p in accessor(prim["attributes"]["POSITION"]):
                verts.append(tuple(m[r][0] * p[0] + m[r][1] * p[1] + m[r][2] * p[2] + m[r][3] for r in range(3)))
            idx = [k[0] for k in accessor(prim["indices"])] if "indices" in prim else list(range(len(verts) - base))
            for k in range(0, len(idx) - 2, 3):
                tris.append((base + idx[k], base + idx[k + 1], base + idx[k + 2]))
        out.append((n.get("name", "node%d" % i), verts, tris))
    return out


def glb_bytes(meshes, root_name):
    """Deterministic GLB: one node per mesh, positions float32, indices uint32, no transforms."""
    blob = bytearray()
    views, accessors, gl_meshes, nodes = [], [], [], []
    for name, verts, tris in meshes:
        pos_off = len(blob)
        f32 = [tuple(_f32(c) for c in v) for v in verts]
        for v in f32:
            blob += struct.pack("<fff", *v)
        idx_off = len(blob)
        for t in tris:
            blob += struct.pack("<III", *t)
        lo = [min(v[k] for v in f32) for k in range(3)]
        hi = [max(v[k] for v in f32) for k in range(3)]
        views.append({"buffer": 0, "byteOffset": pos_off, "byteLength": idx_off - pos_off, "target": 34962})
        views.append({"buffer": 0, "byteOffset": idx_off, "byteLength": len(blob) - idx_off, "target": 34963})
        accessors.append({"bufferView": len(views) - 2, "componentType": 5126, "count": len(verts),
                          "type": "VEC3", "min": lo, "max": hi})
        accessors.append({"bufferView": len(views) - 1, "componentType": 5125, "count": len(tris) * 3,
                          "type": "SCALAR"})
        gl_meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": len(accessors) - 2},
                                                        "indices": len(accessors) - 1}]})
        nodes.append({"name": name, "mesh": len(gl_meshes) - 1})
    nodes.append({"name": root_name, "children": list(range(len(nodes)))})
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
    blob += b"\0" * (-len(blob) % 4)
    total = 12 + 8 + len(js) + 8 + len(blob)
    return (b"glTF" + struct.pack("<II", 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js
            + struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


# ------------------------------------------------------------------------------------------------
# Mesh helpers
# ------------------------------------------------------------------------------------------------


def box_mesh(lo, hi):
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
         (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    t = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4),
         (3, 7, 6), (3, 6, 2), (0, 4, 7), (0, 7, 3), (1, 2, 6), (1, 6, 5)]
    return v, t


def weld(verts, tris, tol=WELD_TOL):
    """Merge vertices closer than `tol` (neighbouring buckets checked); drop degenerate triangles."""
    buckets, out, remap = {}, [], []
    for p in verts:
        key = (math.floor(p[0] / tol), math.floor(p[1] / tol), math.floor(p[2] / tol))
        found = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for j in buckets.get((key[0] + dx, key[1] + dy, key[2] + dz), ()):
                        q = out[j]
                        if abs(q[0] - p[0]) <= tol and abs(q[1] - p[1]) <= tol and abs(q[2] - p[2]) <= tol:
                            found = j
                            break
                    if found is not None:
                        break
                if found is not None:
                    break
            if found is not None:
                break
        if found is None:
            found = len(out)
            out.append(tuple(p))
            buckets.setdefault(key, []).append(found)
        remap.append(found)
    nt = []
    for a, b, c in tris:
        a, b, c = remap[a], remap[b], remap[c]
        if a != b and b != c and a != c:
            nt.append((a, b, c))
    return out, nt


def islands(nverts, tris):
    """Vertex-connected triangle groups, in order of their first triangle."""
    parent = list(range(nverts))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b, c in tris:
        ra, rb, rc = find(a), find(b), find(c)
        parent[rb] = ra
        parent[find(rc)] = ra
    groups, order = {}, []
    for t in tris:
        r = find(t[0])
        if r not in groups:
            groups[r] = []
            order.append(r)
        groups[r].append(t)
    return [groups[r] for r in order]


def compact(verts, tris):
    remap, out, nt = {}, [], []
    for t in tris:
        ids = []
        for i in t:
            if i not in remap:
                remap[i] = len(out)
                out.append(verts[i])
            ids.append(remap[i])
        nt.append(tuple(ids))
    return out, nt


def directed_edge_counts(tris):
    counts = {}
    for a, b, c in tris:
        for e in ((a, b), (b, c), (c, a)):
            counts[e] = counts.get(e, 0) + 1
    return counts


def is_closed(tris):
    """Closed, edge-manifold and consistently wound: every directed edge once, its reverse once."""
    if not tris:
        return False
    counts = directed_edge_counts(tris)
    return all(n == 1 and counts.get((e[1], e[0])) == 1 for e, n in counts.items())


def boundary_loops(tris):
    """Directed boundary loops (vertex id lists) following the winding of the adjacent triangles."""
    counts = directed_edge_counts(tris)
    nxt, order = {}, []
    for a, b, c in tris:
        for e in ((a, b), (b, c), (c, a)):
            if (e[1], e[0]) not in counts and e not in nxt.get(e[0], ()):
                nxt.setdefault(e[0], []).append(e[1])
                order.append(e)
    used = set()
    loops = []
    for start_edge in order:
        if start_edge in used:
            continue
        loop = [start_edge[0]]
        used.add(start_edge)
        cur = start_edge[1]
        while cur != loop[0]:
            outs = [b for b in nxt.get(cur, ()) if (cur, b) not in used]
            if not outs:
                raise LoopError("boundary edges do not close into a loop at a vertex")
            loop.append(cur)
            used.add((cur, outs[0]))
            cur = outs[0]
            if len(loop) > len(order) + 1:
                raise LoopError("boundary walk did not terminate")
        loops.append(loop)
    return loops


def signed_volume(verts, tris):
    vol = 0.0
    for a, b, c in tris:
        vol += dot(verts[a], cross(verts[b], verts[c]))
    return vol / 6.0


def area_normal(verts, tris):
    """(unit area-weighted normal, total area, area-weighted centroid)."""
    acc = (0.0, 0.0, 0.0)
    area = 0.0
    cen = (0.0, 0.0, 0.0)
    for a, b, c in tris:
        n = cross(sub(verts[b], verts[a]), sub(verts[c], verts[a]))
        ar = 0.5 * length(n)
        acc = add(acc, n)
        area += ar
        cen = add(cen, mul(add(add(verts[a], verts[b]), verts[c]), ar / 3.0))
    return norm(acc), area, (mul(cen, 1.0 / area) if area > 0.0 else verts[tris[0][0]]), 0.5 * length(acc)


def newell(points):
    n = (0.0, 0.0, 0.0)
    m = len(points)
    for k in range(m):
        a, b = points[k], points[(k + 1) % m]
        n = add(n, ((a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])))
    return n


def plane_basis(n):
    a = (1.0, 0.0, 0.0) if abs(n[0]) < 0.9 else (0.0, 1.0, 0.0)
    u = norm(cross(n, a))
    return u, cross(n, u)


def _seg_intersect(p1, p2, q1, q2):
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    d1, d2 = orient(q1, q2, p1), orient(q1, q2, p2)
    d3, d4 = orient(p1, p2, q1), orient(p1, p2, q2)
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0)) and d1 != 0 and d2 != 0 and d3 != 0 and d4 != 0


def triangulate_loop(points, normal):
    """Ear-clip a (near-)planar polygon; triangles keep the input order's orientation.

    Raises CapError for a self-intersecting or degenerate polygon. Returns index triples.
    """
    u, v = plane_basis(norm(normal))
    pts = [(dot(p, u), dot(p, v)) for p in points]
    n = len(pts)
    if n < 3:
        raise CapError("loop with fewer than 3 distinct vertices")
    for i in range(n):
        for j in range(i + 1, n):
            if pts[i] == pts[j]:
                raise CapError("loop visits the same point twice")
    for i in range(n):
        a1, a2 = pts[i], pts[(i + 1) % n]
        for j in range(i + 2, n):
            if (j + 1) % n == i:
                continue
            if _seg_intersect(a1, a2, pts[j], pts[(j + 1) % n]):
                raise CapError("loop is not simple")
    area2 = sum(pts[k][0] * pts[(k + 1) % n][1] - pts[(k + 1) % n][0] * pts[k][1] for k in range(n))
    scale = max(max(abs(p[0]), abs(p[1])) for p in pts) or 1.0
    if abs(area2) < 1e-14 * scale * scale:
        raise CapError("loop has no area")
    s = 1.0 if area2 > 0 else -1.0
    eps = 1e-14 * scale * scale

    def cr(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    idx = list(range(n))
    out = []
    while len(idx) > 3:
        m = len(idx)
        found = False
        for k in range(m):
            ia, ib, ic = idx[k - 1], idx[k], idx[(k + 1) % m]
            a, b, c = pts[ia], pts[ib], pts[ic]
            if s * cr(a, b, c) <= eps:
                continue
            ear = True
            for j in idx:
                if j in (ia, ib, ic):
                    continue
                p = pts[j]
                if s * cr(a, b, p) >= -eps and s * cr(b, c, p) >= -eps and s * cr(c, a, p) >= -eps:
                    ear = False
                    break
            if ear:
                out.append((ia, ib, ic))
                idx.pop(k)
                found = True
                break
        if not found:
            raise CapError("no ear found (degenerate polygon)")
    out.append((idx[0], idx[1], idx[2]))
    return out


# ------------------------------------------------------------------------------------------------
# Oriented boxes (rules 6 and 7)
# ------------------------------------------------------------------------------------------------


def _hull_2d(points):
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts

    def cr(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cr(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cr(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def oriented_box(points):
    """Box with a vertical axis and the yaw of least footprint: {"axes": (a, y, b), "lo", "hi"}."""
    hull = _hull_2d([(p[0], p[2]) for p in points])
    angles = {0.0}
    for k in range(len(hull)):
        dx = hull[(k + 1) % len(hull)][0] - hull[k][0]
        dz = hull[(k + 1) % len(hull)][1] - hull[k][1]
        if dx * dx + dz * dz < 1e-16:
            continue
        th = math.atan2(dz, dx) % (math.pi / 2.0)
        if th < 1e-6 or th > math.pi / 2.0 - 1e-6:
            th = 0.0
        angles.add(round(th, 9))
    best = None
    for th in sorted(angles):
        c, s = (1.0, 0.0) if th == 0.0 else (math.cos(th), math.sin(th))
        ea = [p[0] * c + p[1] * s for p in hull]
        eb = [-p[0] * s + p[1] * c for p in hull]
        area = (max(ea) - min(ea)) * (max(eb) - min(eb))
        if best is None or area < best[0] - 1e-12:
            best = (area, c, s)
    _area, c, s = best
    axes = ((c, 0.0, s), (0.0, 1.0, 0.0), (-s, 0.0, c))
    lo = [min(dot(p, ax) for p in points) for ax in axes]
    hi = [max(dot(p, ax) for p in points) for ax in axes]
    return {"axes": axes, "lo": lo, "hi": hi}


def oriented_box_mesh(ob):
    axes, lo, hi = ob["axes"], ob["lo"], ob["hi"]
    v, t = box_mesh(lo, hi)

    def world(p):
        return add(add(mul(axes[0], p[0]), mul(axes[1], p[1])), mul(axes[2], p[2]))

    return [world(p) for p in v], t


def convex_hull(points, eps=HULL_EPS):
    """Closed, outward-wound convex hull (verts, tris) of 3D points (rule 11). Incremental, in
    input order, so the result is deterministic; a point within `eps` of a face is on it.
    Raises CapError when the points span no volume."""
    pts = []
    seen = set()
    for p in points:
        key = tuple(round(c, 6) for c in p)  # weld to 1 um: near-duplicates make sliver faces
        if key not in seen:
            seen.add(key)
            pts.append(tuple(float(c) for c in p))
    if len(pts) < 4:
        raise CapError("fewer than 4 distinct points")
    i0 = min(range(len(pts)), key=lambda i: pts[i])
    i1 = max(range(len(pts)), key=lambda i: length(sub(pts[i], pts[i0])))
    d01 = norm(sub(pts[i1], pts[i0]))
    i2 = max(range(len(pts)), key=lambda i: length(cross(d01, sub(pts[i], pts[i0]))))
    n012 = cross(sub(pts[i1], pts[i0]), sub(pts[i2], pts[i0]))
    if length(n012) < 1e-12:
        raise CapError("points are collinear")
    n012 = norm(n012)
    i3 = max(range(len(pts)), key=lambda i: abs(dot(n012, sub(pts[i], pts[i0]))))
    if abs(dot(n012, sub(pts[i3], pts[i0]))) <= 1e3 * eps:
        raise CapError("points are coplanar: no volume to hull")
    inner = mul(add(add(pts[i0], pts[i1]), add(pts[i2], pts[i3])), 0.25)

    def plane(a, b, c):
        n = cross(sub(pts[b], pts[a]), sub(pts[c], pts[a]))
        ln = length(n)
        if ln < 1e-15:
            return (0.0, 0.0, 0.0), 0.0
        n = mul(n, 1.0 / ln)
        return n, dot(n, pts[a])

    faces = {}
    edge_face = {}  # directed edge -> the face that has it
    next_id = [0]

    def put(a, b, c, n, d):
        fid = next_id[0]
        next_id[0] += 1
        faces[fid] = (a, b, c, n, d)
        for e in ((a, b), (b, c), (c, a)):
            edge_face[e] = fid

    def add_face(a, b, c):
        n, d = plane(a, b, c)
        if dot(n, inner) - d > 0.0:  # the interior must lie behind every face
            a, b = b, a
            n, d = plane(a, b, c)
        put(a, b, c, n, d)

    for a, b, c in ((i0, i1, i2), (i0, i1, i3), (i0, i2, i3), (i1, i2, i3)):
        add_face(a, b, c)
    for pi in range(len(pts)):
        if pi in (i0, i1, i2, i3):
            continue
        p = pts[pi]
        dist = {fid: dot(f[3], p) - f[4] for fid, f in faces.items()}
        start = max(dist, key=lambda fid: (dist[fid], -fid))
        if dist[start] <= eps:
            continue
        # The visible region grown across edges from the most visible face, so it is one disc and
        # its boundary one horizon loop even when far faces are within eps of seeing the point.
        visible = {start}
        stack = [start]
        while stack:
            a, b, c = faces[stack.pop()][:3]
            for e in ((b, a), (c, b), (a, c)):
                nb = edge_face.get(e)
                if nb is not None and nb not in visible and dist[nb] > eps:
                    visible.add(nb)
                    stack.append(nb)
        horizon = []
        for fid in sorted(visible):
            a, b, c = faces[fid][:3]
            for e in ((a, b), (b, c), (c, a)):
                if edge_face.get((e[1], e[0])) not in visible:
                    horizon.append(e)
        for fid in visible:
            a, b, c = faces.pop(fid)[:3]
            for e in ((a, b), (b, c), (c, a)):
                if edge_face.get(e) == fid:
                    del edge_face[e]
        for a, b in horizon:  # keep each horizon edge's direction: the new face stays outward
            n, d = plane(a, b, pi)
            put(a, b, pi, n, d)
    used = sorted({i for f in faces.values() for i in f[:3]})
    remap = {old: k for k, old in enumerate(used)}
    verts = [pts[i] for i in used]
    tris = [(remap[f[0]], remap[f[1]], remap[f[2]]) for _fid, f in sorted(faces.items())]
    return verts, tris


# ------------------------------------------------------------------------------------------------
# Sheets and slabs
# ------------------------------------------------------------------------------------------------


class Sheet:
    """A planar island: its plane, in-plane triangles and boundary, and (rule 2) its slab."""

    def __init__(self, node, verts, tris, normal, centroid):
        self.node = node
        self.verts = verts
        self.tris = tris
        self.n = normal
        self.p0 = centroid
        self.u, self.v = plane_basis(normal)
        self.q = [self.to2d(p) for p in verts]
        self.lo2 = (min(q[0] for q in self.q), min(q[1] for q in self.q))
        self.hi2 = (max(q[0] for q in self.q), max(q[1] for q in self.q))
        self.edges2 = []
        for loop in boundary_loops(tris):
            for k in range(len(loop)):
                self.edges2.append((self.q[loop[k]], self.q[loop[(k + 1) % len(loop)]]))
        self.depth = None  # set for rule-2 slabs

    def to2d(self, p):
        d = sub(p, self.p0)
        return (dot(d, self.u), dot(d, self.v))

    def height(self, p):
        return dot(sub(p, self.p0), self.n)

    def in_bbox2d(self, q, margin):
        return (self.lo2[0] - margin <= q[0] <= self.hi2[0] + margin
                and self.lo2[1] - margin <= q[1] <= self.hi2[1] + margin)

    def contains2d(self, q, tol):
        """q inside the sheet's polygon; tol > 0 allows that much outside, tol < 0 needs that margin in."""
        if not self.in_bbox2d(q, max(tol, 0.0)):
            return False
        inside = False
        for a, b, c in self.tris:
            pa, pb, pc = self.q[a], self.q[b], self.q[c]
            d1 = (pb[0] - pa[0]) * (q[1] - pa[1]) - (pb[1] - pa[1]) * (q[0] - pa[0])
            d2 = (pc[0] - pb[0]) * (q[1] - pb[1]) - (pc[1] - pb[1]) * (q[0] - pb[0])
            d3 = (pa[0] - pc[0]) * (q[1] - pc[1]) - (pa[1] - pc[1]) * (q[0] - pc[0])
            if (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0):
                inside = True
                break
        if inside and tol >= 0.0:
            return True
        d = min(_seg_dist2d(q, a, b) for a, b in self.edges2)
        return d >= -tol if inside else d <= tol

    def slab_contains(self, p, tol):
        h = self.height(p)
        if h > tol or h < -(self.depth + tol):
            return False
        if tol < 0.0 and (h > tol or h < -(self.depth + tol)):
            return False
        return self.contains2d(self.to2d(p), tol)


def _seg_dist2d(p, a, b):
    abx, aby = b[0] - a[0], b[1] - a[1]
    l2 = abx * abx + aby * aby
    t = 0.0 if l2 <= 0.0 else max(0.0, min(1.0, ((p[0] - a[0]) * abx + (p[1] - a[1]) * aby) / l2))
    dx, dy = a[0] + t * abx - p[0], a[1] + t * aby - p[1]
    return math.sqrt(dx * dx + dy * dy)


def grow_outer_loop(verts, tris, normal, amount):
    """Move the vertices of the sheet's outer boundary loop `amount` outward in the sheet's plane."""
    loops = boundary_loops(tris)
    if not loops:
        return list(verts)
    u, v = plane_basis(normal)

    def area(loop):
        q = [(dot(verts[i], u), dot(verts[i], v)) for i in loop]
        return abs(sum(q[k][0] * q[(k + 1) % len(q)][1] - q[(k + 1) % len(q)][0] * q[k][1] for k in range(len(q))))

    outer = max(loops, key=area)
    out = list(verts)
    seen = {}
    for i in outer:
        seen[i] = seen.get(i, 0) + 1
    m = len(outer)
    for k in range(m):
        i = outer[k]
        if seen[i] > 1:
            continue
        a, b, c = verts[outer[k - 1]], verts[i], verts[outer[(k + 1) % m]]
        o1 = norm(cross(norm(sub(b, a)), normal))
        o2 = norm(cross(norm(sub(c, b)), normal))
        mid = add(o1, o2)
        if length(mid) < 1e-9:
            off = mul(o1, amount)
        else:
            mid = norm(mid)
            cosv = max(dot(mid, o1), 1.0 / 3.0)
            off = mul(mid, amount / cosv)
        out[i] = add(b, off)
    return out


def extrude_sheet(verts, tris, normal, depth):
    """Closed solid: the sheet, a reversed copy `depth` behind it, side walls along every loop.
    `depth` is one number or one per vertex (rule 11: a tile field reaching down to its underside)."""
    n = len(verts)
    depths = depth if isinstance(depth, (list, tuple)) else [depth] * n
    return extrude_to(verts, tris, [add(p, mul(normal, -d)) for p, d in zip(verts, depths)])


def extrude_to(verts, tris, bottoms):
    """Closed solid: the sheet, a reversed copy whose vertex k sits at bottoms[k], side walls
    along every boundary loop."""
    n = len(verts)
    v2 = list(verts) + list(bottoms)
    t2 = list(tris) + [(a + n, c + n, b + n) for a, b, c in tris]
    for loop in boundary_loops(tris):
        m = len(loop)
        for k in range(m):
            a, b = loop[k], loop[(k + 1) % m]
            t2.append((b, a, a + n))
            t2.append((b, a + n, b + n))
    return v2, t2


# ------------------------------------------------------------------------------------------------
# Closing open islands (rules 4a, 4b and the rule 8 cap push)
# ------------------------------------------------------------------------------------------------


def close_island(verts, tris, plans):
    """Cap every boundary loop. plans[k] is None (cap the loop in place) or (axis, origin, hc):
    project the loop along `axis` onto the plane dot(p - origin, axis) == hc, skirt down to it
    and cap there. Returns (verts, tris, caps) with caps[k] the cap's triangle index range."""
    v = list(verts)
    t = list(tris)
    loops = boundary_loops(tris)
    caps = []
    for k, loop in enumerate(loops):
        plan = plans[k] if k < len(plans) else None
        if plan is None:
            pts = [v[i] for i in reversed(loop)]
            ids = list(reversed(loop))
            nrm = newell(pts)
        else:
            axis, origin, hc = plan
            proj = []
            for i in loop:
                p = v[i]
                proj.append(sub(p, mul(axis, dot(sub(p, origin), axis) - hc)))
            m = len(loop)
            start = None
            for s0 in range(m):
                if length(sub(proj[s0], proj[s0 - 1])) >= WELD_TOL:
                    start = s0
                    break
            if start is None:
                raise CapError("projected loop collapses to a point")
            order = [(start + j) % m for j in range(m)]
            new_id = {}
            prev = None
            for j in order:
                if prev is not None and length(sub(proj[j], v[new_id[prev]])) < WELD_TOL:
                    new_id[j] = new_id[prev]
                else:
                    new_id[j] = len(v)
                    v.append(proj[j])
                prev = j
            for j in order:
                a, b = loop[j], loop[(j + 1) % m]
                pa, pb = new_id[j], new_id[(j + 1) % m]
                if pa == pb:
                    t.append((b, a, pa))
                else:
                    t.append((b, a, pa))
                    t.append((b, pa, pb))
            ring = []
            for j in order:
                if not ring or ring[-1] != new_id[j]:
                    ring.append(new_id[j])
            if len(ring) > 1 and ring[0] == ring[-1]:
                ring.pop()
            ids = list(reversed(ring))
            pts = [v[i] for i in ids]
            nrm = newell(pts)
        first = len(t)
        for a, b, c in triangulate_loop(pts, nrm):
            t.append((ids[a], ids[b], ids[c]))
        caps.append((first, len(t)))
    return v, t, caps


def loop_plane(points):
    n = norm(newell(points))
    c = mul(add_all(points), 1.0 / len(points))
    dev = max(abs(dot(sub(p, c), n)) for p in points)
    return n, c, dev


def add_all(points):
    s = (0.0, 0.0, 0.0)
    for p in points:
        s = add(s, p)
    return s


# ------------------------------------------------------------------------------------------------
# Triangle grid (rule 8 contacts, slot check)
# ------------------------------------------------------------------------------------------------


class TriGrid:
    def __init__(self, tris, cell=0.25):
        """tris: [(p0, p1, p2, owner)]."""
        self.tris = tris
        self.cell = cell
        self.normals = [norm(cross(sub(b, a), sub(c, a))) for a, b, c, _o in tris]
        self.cells = {}
        if not tris:
            self.lo = self.hi = (0.0, 0.0, 0.0)
            return
        self.lo = tuple(min(min(t[0][k], t[1][k], t[2][k]) for t in tris) - 1e-6 for k in range(3))
        self.hi = tuple(max(max(t[0][k], t[1][k], t[2][k]) for t in tris) + 1e-6 for k in range(3))
        for i, (a, b, c, _o) in enumerate(tris):
            i0 = [self._ci(min(a[k], b[k], c[k]), k) for k in range(3)]
            i1 = [self._ci(max(a[k], b[k], c[k]), k) for k in range(3)]
            for x in range(i0[0], i1[0] + 1):
                for y in range(i0[1], i1[1] + 1):
                    for z in range(i0[2], i1[2] + 1):
                        self.cells.setdefault((x, y, z), []).append(i)

    def _ci(self, x, k):
        return int(math.floor((x - self.lo[k]) / self.cell))

    def near(self, p, r):
        i0 = [self._ci(p[k] - r, k) for k in range(3)]
        i1 = [self._ci(p[k] + r, k) for k in range(3)]
        seen = set()
        for x in range(i0[0], i1[0] + 1):
            for y in range(i0[1], i1[1] + 1):
                for z in range(i0[2], i1[2] + 1):
                    for i in self.cells.get((x, y, z), ()):
                        if i not in seen:
                            seen.add(i)
                            yield i

    def _hit(self, i, o, d, tmin):
        a, b, c, _o = self.tris[i]
        e1, e2 = sub(b, a), sub(c, a)
        pv = cross(d, e2)
        det = dot(e1, pv)
        if abs(det) < 1e-14:
            return None
        inv = 1.0 / det
        tv = sub(o, a)
        uu = dot(tv, pv) * inv
        if uu < -1e-9 or uu > 1.0 + 1e-9:
            return None
        qv = cross(tv, e1)
        vv = dot(d, qv) * inv
        if vv < -1e-9 or uu + vv > 1.0 + 1e-9:
            return None
        t = dot(e2, qv) * inv
        return t if t > tmin else None

    def ray(self, o, d, tmax, tmin=1e-7):
        """First hit (t, tri index) of the ray o + t d (|d| = 1) with tmin < t <= tmax, else None."""
        if not self.tris:
            return None
        # Clip to the grid box.
        t0, t1 = 0.0, tmax
        for k in range(3):
            if abs(d[k]) < 1e-15:
                if o[k] < self.lo[k] or o[k] > self.hi[k]:
                    return None
                continue
            ta = (self.lo[k] - o[k]) / d[k]
            tb = (self.hi[k] - o[k]) / d[k]
            if ta > tb:
                ta, tb = tb, ta
            t0, t1 = max(t0, ta), min(t1, tb)
            if t0 > t1:
                return None
        p = add(o, mul(d, t0))
        idx = [min(max(self._ci(p[k], k), 0), self._ci(self.hi[k], k)) for k in range(3)]
        step, tnext, tdelta = [0] * 3, [math.inf] * 3, [math.inf] * 3
        for k in range(3):
            if d[k] > 0:
                step[k] = 1
                tnext[k] = (self.lo[k] + (idx[k] + 1) * self.cell - o[k]) / d[k]
                tdelta[k] = self.cell / d[k]
            elif d[k] < 0:
                step[k] = -1
                tnext[k] = (self.lo[k] + idx[k] * self.cell - o[k]) / d[k]
                tdelta[k] = -self.cell / d[k]
        best = None
        tested = set()
        while True:
            for i in self.cells.get(tuple(idx), ()):
                if i in tested:
                    continue
                tested.add(i)
                t = self._hit(i, o, d, tmin)
                if t is not None and t <= tmax and (best is None or t < best[0]):
                    best = (t, i)
            k = min(range(3), key=lambda j: tnext[j])
            if best is not None and best[0] <= tnext[k]:
                return best
            if tnext[k] > t1:
                return best
            idx[k] += step[k]
            tnext[k] += tdelta[k]


def _point_tri_dist(p, a, b, c):
    # Ericson, Real-Time Collision Detection 5.1.5.
    ab, ac, ap = sub(b, a), sub(c, a), sub(p, a)
    d1, d2 = dot(ab, ap), dot(ac, ap)
    if d1 <= 0 and d2 <= 0:
        return length(ap)
    bp = sub(p, b)
    d3, d4 = dot(ab, bp), dot(ac, bp)
    if d3 >= 0 and d4 <= d3:
        return length(bp)
    vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0:
        return length(sub(p, add(a, mul(ab, d1 / (d1 - d3)))))
    cp = sub(p, c)
    d5, d6 = dot(ab, cp), dot(ac, cp)
    if d6 >= 0 and d5 <= d6:
        return length(cp)
    vb = d5 * d2 - d1 * d6
    if vb <= 0 and d2 >= 0 and d6 <= 0:
        return length(sub(p, add(a, mul(ac, d2 / (d2 - d6)))))
    va = d3 * d6 - d5 * d4
    if va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
        w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return length(sub(p, add(b, mul(sub(c, b), w))))
    den = 1.0 / (va + vb + vc)
    v = vb * den
    w = vc * den
    return length(sub(p, add(a, add(mul(ab, v), mul(ac, w)))))


# ------------------------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------------------------


def _is_number(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def validate_growth_surface(where, block):
    """Raise ValueError when a structure's growth_surface block is malformed (AR-MESH-20.3)."""
    w = f"{where}: growth_surface"
    if not isinstance(block, dict):
        raise ValueError(f"{w} must be a JSON object, got {type(block).__name__}")
    unknown = sorted(set(block) - set(GROWTH_SURFACE_KEYS))
    if unknown:
        raise ValueError(f"{w}: unknown key(s) {unknown}; allowed {list(GROWTH_SURFACE_KEYS)}")
    if "wall_t" in block:
        if not _is_number(block["wall_t"]) or block["wall_t"] < WALL_T_MIN:
            raise ValueError(f"{w}: 'wall_t' must be a number >= {WALL_T_MIN}, got {block['wall_t']!r}")
    for key in NAME_LIST_KEYS:
        if key in block:
            val = block[key]
            if not isinstance(val, list) or not all(isinstance(s, str) and s for s in val):
                raise ValueError(f"{w}: '{key}' must be a list of non-empty strings, got {val!r}")
    if "seals" in block and block["seals"] not in ("hero", "scaffold"):
        raise ValueError(f"{w}: 'seals' must be 'hero' or 'scaffold', got {block['seals']!r}")
    if "fill" in block:
        fill = block["fill"]
        if not isinstance(fill, list):
            raise ValueError(f"{w}: 'fill' must be a list of {{name, min, max}} boxes or {{name, points}} hulls")
        names = set()
        for k, f in enumerate(fill):
            fw = f"{w}: fill[{k}]"
            hull_form = isinstance(f, dict) and sorted(f) == sorted(FILL_HULL_KEYS)
            if not isinstance(f, dict) or (sorted(f) != sorted(FILL_KEYS) and not hull_form):
                raise ValueError(f"{fw} must have exactly the keys {list(FILL_KEYS)} or {list(FILL_HULL_KEYS)}, got {f!r}")
            if not isinstance(f["name"], str) or not _FILL_NAME.match(f["name"]) or f["name"] in names:
                raise ValueError(f"{fw}: 'name' must be a unique [A-Za-z0-9_] string, got {f['name']!r}")
            names.add(f["name"])
            if hull_form:
                pts = f["points"]
                if (not isinstance(pts, list) or len(pts) < 4
                        or not all(isinstance(p, list) and len(p) == 3 and all(_is_number(x) for x in p) for p in pts)):
                    raise ValueError(f"{fw}: 'points' must be a list of at least 4 [x, y, z] numbers, got {pts!r}")
                continue
            for key in ("min", "max"):
                if not isinstance(f[key], list) or len(f[key]) != 3 or not all(_is_number(x) for x in f[key]):
                    raise ValueError(f"{fw}: '{key}' must be [x, y, z] numbers, got {f[key]!r}")
            if not all(f["min"][i] < f["max"][i] for i in range(3)):
                raise ValueError(f"{fw}: 'min' must be below 'max' on every axis")


def growth_settings(block):
    """Validated settings with defaults filled in."""
    block = {} if block is None else block
    validate_growth_surface("growth_surface", block)
    return {
        "wall_t": float(block.get("wall_t", DEFAULT_WALL_T)),
        "envelope": list(block.get("envelope", [])),
        "exempt": list(block.get("exempt", [])),
        "seals": block.get("seals", "scaffold"),
        "fill": [dict(f) for f in block.get("fill", [])],
        "tile_field": list(block.get("tile_field", [])),
    }


def load_structure(config_path, structure):
    """(footprint centre (x, z) in glTF, settings) for one structure of structure_configs.json."""
    raw = json.loads(Path(config_path).read_text())
    if not isinstance(raw, dict) or structure not in raw:
        raise ValueError(f"{config_path}: no structure '{structure}'")
    cfg = raw[structure]
    off = cfg.get("scene_offset") if isinstance(cfg, dict) else None
    if not isinstance(off, list) or len(off) != 3 or not all(_is_number(x) for x in off):
        raise ValueError(f"{config_path}: structure '{structure}' needs scene_offset [x, y, z]")
    validate_growth_surface(f"structure config '{structure}'", cfg.get("growth_surface", {}))
    # Blender (x, y, z) z-up exports to glTF (x, z, -y): the footprint centre is (x, -y).
    return (float(off[0]), -float(off[1])), growth_settings(cfg.get("growth_surface"))


# ------------------------------------------------------------------------------------------------
# The build
# ------------------------------------------------------------------------------------------------


def _tail(name, structure, kind):
    prefix = f"{structure}_{kind}_"
    return name[len(prefix):] if name.startswith(prefix) else name


def _matches(tail, entries):
    return [e for e in entries if e in tail]


def _orient_outward(verts, tris):
    if signed_volume(verts, tris) < 0.0:
        return [(a, c, b) for a, b, c in tris], True
    return list(tris), False


def _aperture_id(seal_tail, scaffold_panels):
    rest = seal_tail.split(SEAL_TOKEN.strip("_") + "_", 1)[-1]
    for aid in sorted(scaffold_panels, key=len, reverse=True):
        if rest == aid or rest.startswith(aid + "_"):
            return aid
    return rest.rsplit("_", 1)[0] if "_" in rest else rest


class _Solid:
    def __init__(self, node, rule, verts, tris, name=None):
        self.node = node
        self.rule = rule
        self.verts = verts
        self.tris = tris
        self.name = name
        self.island = None  # (verts, tris, loops, plans, caps) for rule-4 solids


def build(hero, scaffold, structure, centre_xz, settings, fail_on_slots=True):
    """Build the growth-surface solids. Returns (meshes, report); raises BuildError. With
    fail_on_slots False, slots are still listed in the report but are not a failure (for tools
    that compute fills, such as tools/cottage_growth_fills.py; never for a shipped surface)."""
    st = settings
    wall_t = st["wall_t"]
    cx, cz = centre_xz
    failures = []
    rules = {k: 0 for k in ("1_closed", "2_extruded", "3_dropped", "4a_capped_loops", "4b_skirted_loops",
                            "5_dropped", "6_envelope", "7_seal", "8_pushed_caps", "9_pulled_vertices",
                            "10_exempt", "11_tile_field", "fill", "scaffold_copied", "flipped_to_outward")}
    report = {"tool": GENERATOR, "structure": structure, "centre_xz": [cx, cz], "settings": st,
              "rules": rules, "nodes": [], "slots": [], "enclosed_gap_samples": 0, "contacts": [],
              "warnings": [], "failures": failures}

    def fail(msg):
        failures.append(msg)

    # -- classify hero nodes ------------------------------------------------------------------
    used_entries = set()
    regular, envelopes, seals = [], [], []
    for name, verts, tris in hero:
        tail = _tail(name, structure, "hero")
        ex = _matches(tail, st["exempt"])
        en = _matches(tail, st["envelope"])
        tf = _matches(tail, st["tile_field"])
        used_entries.update(("exempt", e) for e in ex)
        used_entries.update(("envelope", e) for e in en)
        used_entries.update(("tile_field", e) for e in tf)
        if ex:
            rules["10_exempt"] += 1
            report["nodes"].append({"hero": name, "rule": "10_exempt", "solids": []})
        elif SEAL_TOKEN in name or tail.startswith(SEAL_TOKEN.strip("_") + "_"):
            seals.append((name, tail, verts, tris))
        elif en:
            envelopes.append((name, tail, verts, tris))
        else:
            regular.append((name, tail, verts, tris))
    for key in ("exempt", "envelope", "tile_field"):
        for e in st[key]:
            if (key, e) not in used_entries:
                fail(f"growth_surface {key} entry '{e}' matches no hero node")

    # -- pass 1: islands; rule 2 slabs from every node ----------------------------------------
    per_node = []
    slabs = []
    for name, tail, verts, tris in regular:
        v, t = weld(verts, tris)
        entries = []
        node_sheets = []
        for isl in islands(len(v), t):
            iv, it = compact(v, isl)
            e = {"verts": iv, "tris": it}
            if is_closed(it):
                e["kind"] = "closed"
            else:
                n, area, cen, net = area_normal(iv, it)
                dev = max(abs(dot(sub(p, cen), n)) for p in iv) if net > 0 else math.inf
                tn = [cross(sub(iv[b], iv[a]), sub(iv[c], iv[a])) for a, b, c in it]
                align = min((dot(n, norm(x)) for x in tn if length(x) > 1e-12), default=0.0)
                if dev <= SHEET_PLANAR_TOL and align >= SHEET_ALIGN_MIN and net > 0.5 * area:
                    try:
                        sheet = Sheet(name, iv, it, n, cen)
                    except LoopError as exc:
                        e["kind"] = "nofit"
                        e["why"] = f"planar sheet with a broken boundary ({exc})"
                    else:
                        node_sheets.append(sheet)
                        horiz = math.hypot(n[0], n[2])
                        facing = n[0] * (cen[0] - cx) + n[2] * (cen[2] - cz)
                        if horiz < FACING_MIN or abs(facing) < 1e-6:
                            e["kind"] = "nofit"
                            e["why"] = "planar sheet that faces neither away from nor toward the interior"
                        else:
                            e["kind"] = "sheet_out" if facing > 0.0 else "sheet_in"
                            e["sheet"] = sheet
                else:
                    e["kind"] = "open"
            entries.append(e)
        is_field = bool(_matches(tail, st["tile_field"]))
        for e in entries:
            if is_field and e["kind"] != "closed" and area_normal(e["verts"], e["tris"])[0][1] < -0.3:
                e["kind"] = "underside"  # rule 11: the bottom of this node's tile field
            if e["kind"] == "sheet_out":
                sheet = e["sheet"]
                sheet.depth = wall_t
                slabs.append(sheet)
        per_node.append((name, tail, entries, node_sheets))

    def inside_some_slab(points):
        for s in slabs:
            if all(s.slab_contains(p, CONTACT_TOL) for p in points):
                return True
        return False

    # -- pass 2: solids per node ----------------------------------------------------------------
    solids = []
    node_reports = {}
    tile_pools = {}  # rule 11: node -> [(verts, tris)] of the islands rule 4 cannot close
    ridge_candidates = {}  # rule 11: node -> closed islands, decided once the ridge is known
    undersides = {}  # rule 11: node -> its down-facing open islands (the bottom of the roof)
    for name, tail, entries, node_sheets in per_node:
        made = 0
        dropped5 = 0
        is_tile_field = bool(_matches(tail, st["tile_field"]))
        info = {"hero": name, "rule": "islands", "islands": [], "solids": []}
        node_reports[name] = info
        report["nodes"].append(info)
        for k, e in enumerate(entries):
            kind = e["kind"]
            iv, it = e["verts"], e["tris"]
            info["islands"].append(kind)
            if kind == "underside":
                undersides.setdefault(name, []).append((iv, it))
                continue
            if kind == "nofit":
                fail(f"{name}: island {k} fits no rule ({e['why']})")
                continue
            if kind == "sheet_in":
                rules["3_dropped"] += 1
                continue
            if kind == "sheet_out":
                sheet = e["sheet"]
                gv = grow_outer_loop(iv, it, sheet.n, SLAB_GROW)
                sv, stris = extrude_sheet(gv, it, sheet.n, wall_t)
                stris, flipped = _orient_outward(sv, stris)
                if not is_closed(stris):
                    fail(f"{name}: island {k} extruded slab is not closed")
                    continue
                rules["2_extruded"] += 1
                solids.append(_Solid(name, "2", sv, stris))
                made += 1
                continue
            if inside_some_slab(iv):
                rules["5_dropped"] += 1
                dropped5 += 1
                continue
            if kind == "closed" and is_tile_field:
                ridge_candidates.setdefault(name, []).append((iv, it))
                continue
            if kind == "closed":
                ct, flipped = _orient_outward(iv, it)
                if abs(signed_volume(iv, ct)) < 1e-12:
                    fail(f"{name}: island {k} fits no rule (closed but encloses no volume: a double-sided sheet)")
                    continue
                rules["flipped_to_outward"] += int(flipped)
                rules["1_closed"] += 1
                solids.append(_Solid(name, "1", iv, ct))
                made += 1
                continue
            # open, not a planar sheet: rule 4
            try:
                loops = boundary_loops(it)
            except LoopError as exc:
                fail(f"{name}: island {k} result is not closed ({exc})")
                continue
            if not loops:
                fail(f"{name}: island {k} fits no rule (open but without a boundary: overlapping or double-sided faces)")
                continue
            plans = []
            ok = True
            backing = None
            for loop in loops:
                pts = [iv[i] for i in loop]
                _n, _c, dev = loop_plane(pts)
                if dev <= LOOP_PLANAR_TOL:
                    plans.append(None)
                    continue
                if backing is None:
                    backing = _find_backing(iv, it, node_sheets)
                if backing is None:
                    if is_tile_field:
                        tile_pools.setdefault(name, []).append((iv, it))
                    else:
                        fail(f"{name}: island {k} has a boundary loop {dev * 1000:.1f} mm out of plane and no backing sheet")
                    ok = False
                    break
                hmin = min(backing.height(p) for p in pts)
                plans.append((backing.n, backing.p0, min(-CAP_INSET, hmin - CAP_INSET)))
            if not ok:
                continue
            try:
                cv, ctris, caps = close_island(iv, it, plans)
            except (CapError, LoopError) as exc:
                fail(f"{name}: island {k} result is not closed ({exc})")
                continue
            ctris, flipped = _orient_outward(cv, ctris)
            if not is_closed(ctris):
                fail(f"{name}: island {k} result is not closed")
                continue
            rules["flipped_to_outward"] += int(flipped)
            rules["4a_capped_loops"] += sum(1 for p in plans if p is None)
            rules["4b_skirted_loops"] += sum(1 for p in plans if p is not None)
            sol = _Solid(name, "4", cv, ctris)
            sol.island = (iv, it, loops, plans, caps, flipped)
            solids.append(sol)
            made += 1
        if made == 0 and dropped5 == 0 and not any(name in d for d in (tile_pools, ridge_candidates, undersides)):
            fail(f"{name}: hero node produced no solid")
        info["count"] = made

    # -- rule 11: tile fields ---------------------------------------------------------------------
    for name in sorted(set(tile_pools) | set(ridge_candidates) | set(undersides)):
        field = None
        if name in tile_pools:
            try:
                field = _tile_field_solids(tile_pools[name], undersides.get(name, []))
            except (CapError, LoopError) as exc:
                fail(f"{name}: tile field solid failed ({exc})")
                continue
        elif name in undersides:
            fail(f"{name}: down-facing islands of a tile_field node but no tile field above them")
            continue
        made = []
        ridge = []
        for iv, it in ridge_candidates.get(name, []):
            if field is not None and _is_ridge_piece(iv, field):
                ridge.append(iv)
            ct, flipped = _orient_outward(iv, it)
            if abs(signed_volume(iv, ct)) < 1e-12:
                fail(f"{name}: a closed island fits no rule (closed but encloses no volume: a double-sided sheet)")
                continue
            rules["flipped_to_outward"] += int(flipped)
            made.append(("1", (iv, ct)))
        if field is not None:
            made += [("11", part) for part in field["parts"]]
        if ridge:
            try:
                made += [("11", part) for part in _ridge_supports(ridge, field)]
            except CapError as exc:
                fail(f"{name}: ridge piece support failed ({exc})")
        for rule, (hv, ht) in made:
            if rule == "11":
                ht, _flipped = _orient_outward(hv, ht)
                if not is_closed(ht):
                    fail(f"{name}: tile field hull is not closed")
                    continue
                rules["11_tile_field"] += 1
            else:
                rules["1_closed"] += 1
            solids.append(_Solid(name, rule, hv, ht))
            node_reports[name]["count"] = node_reports[name].get("count", 0) + 1

    # -- rule 6: envelopes ------------------------------------------------------------------------
    for name, tail, verts, tris in envelopes:
        ob = oriented_box(verts)
        msg = _extend_to_wall(ob, slabs, cx, cz)
        node_reports[name] = {"hero": name, "rule": "6_envelope", "solids": []}
        report["nodes"].append(node_reports[name])
        if msg:
            fail(f"{name}: envelope has {msg}")
            continue
        bv, bt = oriented_box_mesh(ob)
        rules["6_envelope"] += 1
        solids.append(_Solid(name, "6", bv, bt))

    # -- scaffold ---------------------------------------------------------------------------------
    hero_bases = {f"{structure}_sim_{_tail(n, structure, 'hero')}" for n, _v, _t in hero}
    scaffold_panels = {}
    copies = []
    for name, verts, tris in scaffold:
        base = _GENERATED.sub("", name)
        if not any(tok in base for tok in SCAFFOLD_TOKENS) or base in hero_bases:
            continue
        if "Fill_" in _tail(base, structure, "sim"):
            continue
        aid = base.split("Panel_", 1)[1] if "Panel_" in base else None
        if aid is not None:
            scaffold_panels[aid] = (base, verts, tris)
        copies.append((base, verts, tris, aid))

    # -- rule 7: seals ----------------------------------------------------------------------------
    seal_aids = set()
    for name, tail, verts, tris in seals:
        if st["seals"] != "hero":
            report["nodes"].append({"hero": name, "rule": "7_seal_from_scaffold", "solids": []})
            continue
        aid = _aperture_id(tail, scaffold_panels)
        ob = oriented_box(verts)
        thin = 0 if (ob["hi"][0] - ob["lo"][0]) <= (ob["hi"][2] - ob["lo"][2]) else 2
        axis = ob["axes"][thin]
        mid = mul(add(add(mul(ob["axes"][0], 0.5 * (ob["lo"][0] + ob["hi"][0])),
                          mul(ob["axes"][1], 0.5 * (ob["lo"][1] + ob["hi"][1]))),
                      mul(ob["axes"][2], 0.5 * (ob["lo"][2] + ob["hi"][2]))), 1.0)
        toward = axis[0] * (cx - mid[0]) + axis[2] * (cz - mid[2])
        if toward >= 0.0:
            ob["hi"][thin] = ob["lo"][thin] + wall_t
        else:
            ob["lo"][thin] = ob["hi"][thin] - wall_t
        bv, bt = oriented_box_mesh(ob)
        rules["7_seal"] += 1
        seal_aids.add(aid)
        solids.append(_Solid(name, "7", bv, bt, name=f"{structure}_sim_Panel_{aid}_i00"))
        report["nodes"].append({"hero": name, "rule": "7_seal", "solids": [f"{structure}_sim_Panel_{aid}_i00"]})

    # -- rule 9 and scaffold copies ---------------------------------------------------------------
    walls = [s for s in slabs if abs(s.n[1]) < 0.3]
    for base, verts, tris, aid in copies:
        if aid is not None and aid in seal_aids:
            continue  # rule 7: the hero seal replaces this aperture's scaffold panel
        tail = _tail(base, structure, "sim")
        if ("FloorSlab" in tail and "MidFloorSlab" not in tail) or "RoofCap" in tail:
            verts, moved = _pull_inside_walls(verts, walls)
            rules["9_pulled_vertices"] += moved
            if "FloorSlab" in tail and "MidFloorSlab" not in tail:
                # Its top stood above the ground and buried the hero's wall bases (ivy-b1e.7).
                lowered = [(p[0], min(p[1], 0.0), p[2]) for p in verts]
                rules["9_pulled_vertices"] += sum(1 for a, b in zip(verts, lowered) if a != b)
                verts = lowered
        if not is_closed(tris):
            report["warnings"].append(f"scaffold node {base} is not closed (copied as is)")
        rules["scaffold_copied"] += 1
        solids.append(_Solid(base, "scaffold", list(verts), list(tris), name=base + "_i00"))

    # -- fill -------------------------------------------------------------------------------------
    for f in st["fill"]:
        if "points" in f:
            try:
                fv, ft = convex_hull([tuple(float(x) for x in p) for p in f["points"]])
            except CapError as exc:
                fail(f"fill '{f['name']}': its points span no volume ({exc})")
                continue
            ft, _flipped = _orient_outward(fv, ft)
        else:
            fv, ft = box_mesh(tuple(f["min"]), tuple(f["max"]))
        rules["fill"] += 1
        solids.append(_Solid("fill", "fill", fv, ft, name=f"{structure}_sim_Fill_{f['name']}_i00"))

    # -- rule 8: caps that land on another solid are pushed 2 mm in ---------------------------------
    _push_caps(solids, rules, failures)

    # -- names --------------------------------------------------------------------------------------
    counters = {}
    for s in solids:
        if s.name is None:
            k = counters.get(s.node, 0)
            counters[s.node] = k + 1
            s.name = f"{structure}_sim_{_tail(s.node, structure, 'hero')}_i{k:02d}"
            if s.node in node_reports:
                node_reports[s.node]["solids"].append(s.name)
    names = [s.name for s in solids]
    dup = sorted({n for n in names if names.count(n) > 1})
    if dup:
        fail(f"duplicate output node names {dup}")

    # -- slot check ---------------------------------------------------------------------------------
    report["slot_check"] = "skipped (earlier failures)"
    if not failures:
        report["slot_check"] = "run"
        _slot_check(solids, report)
        if report["slots"] and fail_on_slots:
            worst = sorted(report["slots"], key=lambda s: s["width"])[:10]
            listed = ", ".join("%.3f m at (%.3f, %.3f, %.3f)" % (s["width"], *s["position"]) for s in worst)
            fail(f"proxy has {len(report['slots'])} slot(s) narrower than {SLOT_MIN:.2f} m: {listed}")

    report["output"] = {"nodes": len(solids), "triangles": sum(len(s.tris) for s in solids)}
    if failures:
        raise BuildError(failures, report)
    return [(s.name, s.verts, s.tris) for s in solids], report


def cut_by_plane(verts, tris, m, d, tol=1e-9):
    """Split every triangle that crosses the plane dot(m, p) == d. Edge cuts are shared between
    neighbours, so a closed or open manifold stays one; winding is kept."""
    v = list(verts)
    side = [dot(m, p) - d for p in v]
    cache = {}

    def cut(i, j):
        key = (min(i, j), max(i, j))
        if key not in cache:
            f = side[i] / (side[i] - side[j])
            cache[key] = len(v)
            v.append(add(v[i], mul(sub(v[j], v[i]), f)))
            side.append(0.0)
        return cache[key]

    out = []
    for tri in tris:
        s = [side[i] for i in tri]
        sg = [0 if abs(x) <= tol else (1 if x > 0 else -1) for x in s]
        if not (1 in sg and -1 in sg):
            out.append(tri)
            continue
        # rotate so the lone vertex (the one on its own side, or on the plane) comes first
        for r in range(3):
            a, b, c = tri[r], tri[(r + 1) % 3], tri[(r + 2) % 3]
            ga, gb, gc = sg[r], sg[(r + 1) % 3], sg[(r + 2) % 3]
            if ga == 0 and gb == -gc:
                x = cut(b, c)
                out += [(a, b, x), (a, x, c)]
                break
            if ga != 0 and gb == gc == -ga:
                x, y = cut(a, b), cut(a, c)
                out += [(a, x, y), (x, b, c), (x, c, y)]
                break
            if ga != 0 and gb == -ga and gc == 0:
                x = cut(a, b)
                out += [(a, x, c), (x, b, c)]
                break
            if ga != 0 and gc == -ga and gb == 0:
                x = cut(c, a)
                out += [(a, b, x), (x, b, c)]
                break
    return v, out


def _underside_plane(verts, tris):
    """(outward unit normal, offset, basis u, basis v, outer boundary in (u, v)) of a roof underside."""
    n, _area, cen, _net = area_normal(verts, tris)
    u, w = plane_basis(n)
    loops = boundary_loops(tris)

    def flat(loop):
        return [(dot(verts[i], u), dot(verts[i], w)) for i in loop]

    def area2(q):
        return abs(sum(q[k][0] * q[(k + 1) % len(q)][1] - q[(k + 1) % len(q)][0] * q[k][1] for k in range(len(q))))

    outer = max((flat(loop) for loop in loops), key=area2)
    hull = _hull_2d(outer)  # counter-clockwise
    return n, dot(n, cen), u, w, hull


def _in_convex(q, hull, tol):
    """q inside the counter-clockwise convex polygon `hull`, or within `tol` of it."""
    m = len(hull)
    for k in range(m):
        a, b = hull[k], hull[(k + 1) % m]
        ex, ey = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(ex, ey)
        if ln < 1e-12:
            continue
        if (ex * (q[1] - a[1]) - ey * (q[0] - a[0])) / ln < -tol:
            return False
    return True


def _cut_at_footprint(verts, tris, slope_n, plane):
    """Cut a tile half along every edge of an underside's (convex) footprint, at the edge and 2 mm
    outside it, with planes containing the slope normal: the step from the underside up to the
    thin overhang then lies in a 2 mm band at the underside's edge instead of across a tile row."""
    un, off, u, w, hull = plane
    cx = sum(p[0] for p in hull) / len(hull)
    cy = sum(p[1] for p in hull) / len(hull)

    def to3(q):
        return add(mul(un, off), add(mul(u, q[0]), mul(w, q[1])))

    c3 = to3((cx, cy))
    m_ = len(hull)
    for k in range(m_):
        a, b = to3(hull[k]), to3(hull[(k + 1) % m_])
        e = sub(b, a)
        if length(e) < 1e-6:
            continue
        mn = cross(e, slope_n)
        if length(mn) < 1e-9:
            continue
        mn = norm(mn)
        d = dot(mn, a)
        if dot(mn, c3) - d > 0.0:
            mn, d = mul(mn, -1.0), -d
        for extra in (0.0, 2.0 * SLAB_GROW):
            verts, tris = cut_by_plane(verts, tris, mn, d + extra)
    return verts, tris


def ray_first_hit(origin, direction, verts, tris, reach=math.inf):
    """Distance along `direction` to the first triangle crossed (either side), or None."""
    best = None
    for a, b, c in tris:
        pa = verts[a]
        e1, e2 = sub(verts[b], pa), sub(verts[c], pa)
        pv = cross(direction, e2)
        det = dot(e1, pv)
        if abs(det) < 1e-14:
            continue
        inv = 1.0 / det
        tv = sub(origin, pa)
        u = dot(tv, pv) * inv
        if u < 0.0 or u > 1.0:
            continue
        qv = cross(tv, e1)
        w = dot(direction, qv) * inv
        if w < 0.0 or u + w > 1.0:
            continue
        s = dot(e2, qv) * inv
        if 1e-9 < s <= reach and (best is None or s < best):
            best = s
    return best


def _tile_field_solids(pool, undersides):
    """Rule 11: the solids of a tiled roof field, exact on the tiles.

    `pool` holds the islands of one node that rule 4 cannot close (the tiles); `undersides` its
    down-facing islands (the roof's underside, if modelled). The tile triangles are split at the
    ridge: the vertical plane along the world axis (x or z) on which the highest pooled vertices
    (within 1 cm of the top) spread most, through their mean position. Each side is extruded
    along its own inward slope normal with a per-vertex depth: down to the plane of the underside
    that faces away from it, where that underside lies below the vertex, and TILE_EDGE_DEPTH where
    nothing lies below (eave and verge overhangs). The top of the solid is the tile surface itself,
    troughs and lips included; side walls close every boundary loop (eaves, verges, the ridge seam,
    holes such as the chimney's). The two sides' walls at the ridge cross below the seam, so the
    two solids overlap there (rule 8). A field with triangles on one side only is one solid."""
    verts, tris = [], []
    for iv, it in pool:
        base = len(verts)
        verts += iv
        tris += [(a + base, b + base, c + base) for a, b, c in it]
    top = max(p[1] for p in verts)
    high = [p for p in verts if p[1] >= top - 0.01]
    spread = [max(p[k] for p in high) - min(p[k] for p in high) for k in (0, 2)]
    s = 2 if spread[0] >= spread[1] else 0  # the ridge runs along the axis the highest points spread on
    ridge = sum(p[s] for p in high) / len(high)
    sides = ([], [])
    for tri in tris:
        cs = sum(verts[i][s] for i in tri) / 3.0
        sides[0 if cs < ridge else 1].append(tri)
    planes = [_underside_plane(uv, ut) for uv, ut in undersides]
    seam = {i for tri in sides[0] for i in tri} & {i for tri in sides[1] for i in tri}
    out = []
    for k, side in enumerate(sides):
        if not side:
            continue
        used = sorted({i for tri in side for i in tri})
        remap = {old: j for j, old in enumerate(used)}
        sv = [verts[i] for i in used]
        st_ = [(remap[a], remap[b], remap[c]) for a, b, c in side]
        n = area_normal(sv, st_)[0]
        mine = [pl for pl in planes if dot(pl[0], n) < -UNDERSIDE_ALIGN]
        seam_pts = {tuple(verts[i]) for i in used if i in seam}
        for pl in mine:
            sv, st_ = _cut_at_footprint(sv, st_, n, pl)
        toward = 1.0 if k == 0 else -1.0
        plan = []
        for p in sv:
            # Seam vertices go straight down (so the two sides' walls do not cross under the ridge),
            # nudged SLAB_GROW past the seam so the sides overlap; the rest along -n.
            on_seam = tuple(p) in seam_pts
            axis = (0.0, 1.0, 0.0) if on_seam else n
            d = None
            for un, off, u, w, hull in mine:
                t = (dot(un, p) - off) / dot(un, axis)  # move along -axis this far to reach the plane
                if t <= SLAB_GROW:
                    continue
                q = sub(p, mul(axis, t))
                if _in_convex((dot(q, u), dot(q, w)), hull, SLAB_GROW):
                    d = t if d is None else max(d, t)  # exactly down to the underside, however shallow
            plan.append((p, on_seam, axis, d))
        # Nothing below (eave and verge overhangs): a uniform offset along n folds through tile ends
        # and lips, which are not single-valued along n (inward-wound slivers, SD-MESH-19.4.1). Each
        # overhang vertex's bottom goes TILE_EDGE_DEPTH below the LOWEST overhang tile point within
        # FOLD_REACH of it across the slope, so it lies under every fold near it (ivy-b1e.7).
        floors = _local_floors([p for p, _seam, _axis, d in plan if d is None], n)
        bottoms = []
        for p, on_seam, axis, d in plan:
            if d is None:
                d = (dot(p, n) - floors[tuple(p)] + TILE_EDGE_DEPTH) / dot(n, axis)
            b = list(sub(p, mul(axis, d)))
            if on_seam:
                b[s] += toward * SLAB_GROW
            bottoms.append(tuple(b))
        out.append(extrude_to(sv, st_, bottoms))
    return {"parts": out, "axis": s, "ridge": ridge, "top": top}


def _local_floors(points, n):
    """For each point, the lowest height along n of any point within FOLD_REACH of it measured in
    the plane across n (a grid hash keeps it linear)."""
    if not points:
        return {}
    u, w = plane_basis(n)
    cell = FOLD_REACH
    grid = {}
    flat = []
    for p in points:
        a, b = dot(p, u), dot(p, w)
        flat.append((a, b, dot(p, n)))
        grid.setdefault((math.floor(a / cell), math.floor(b / cell)), []).append(len(flat) - 1)
    out = {}
    for p, (a, b, _h) in zip(points, flat):
        ga, gb = math.floor(a / cell), math.floor(b / cell)
        low = math.inf
        for i in range(ga - 1, ga + 2):
            for j in range(gb - 1, gb + 2):
                for k in grid.get((i, j), ()):
                    qa, qb, qh = flat[k]
                    if (qa - a) ** 2 + (qb - b) ** 2 <= cell * cell:
                        low = min(low, qh)
        out[tuple(p)] = low
    return out


def _is_ridge_piece(verts, field):
    """A closed island of a tile field that straddles the ridge and rises above the tiles (a ridge
    cap). It is kept exact on top but sunk into the slopes (see _sunk_hull)."""
    s = field["axis"]
    return (min(p[s] for p in verts) < field["ridge"] < max(p[s] for p in verts)
            and max(p[1] for p in verts) > field["top"])


def _sunk_hull(verts, field_top=None):
    """The convex hull of a ridge piece and of its copy lowered by its own height (plus however far
    the piece's bottom stands above the field's top, so the result always reaches the tiles)."""
    lo = min(p[1] for p in verts)
    h = max(p[1] for p in verts) - lo
    drop = h + (max(0.0, lo - field_top) if field_top is not None else 0.0)
    return convex_hull(list(verts) + [(p[0], p[1] - drop, p[2]) for p in verts])


def _clip_convex(verts, tris, axis, value, keep_above):
    """A convex solid cut by the plane p[axis] == value, keeping the side above (or below) it."""
    side = [(p[axis] - value) * (1.0 if keep_above else -1.0) for p in verts]
    pts = [p for p, d in zip(verts, side) if d >= 0.0]
    for a, b, c in tris:
        for i, j in ((a, b), (b, c), (c, a)):
            if (side[i] > 0.0) != (side[j] > 0.0) and side[i] != side[j]:
                f = side[i] / (side[i] - side[j])
                pts.append(add(verts[i], mul(sub(verts[j], verts[i]), f)))
    return convex_hull(pts)


def _ridge_supports(pieces, field):
    """Rule 11: two convex solids under each ridge piece (which is kept exactly, rule 1), both
    lowered CAP_INSET so they never share a face with it:

    - the filling: the piece's convex hull, which buries its inner (hollow) faces and closes the
      lap joint under the next piece; its bottom is the chord across the piece's rims;
    - the support: the piece sunk down into the tiles (_sunk_hull), cut to the middle
      RIDGE_SUPPORT_SHARE of the piece's width, so the gap under its crown is filled while the
      pockets under its rims, which the player sees, stay open.

    Both are cut RIDGE_END_KEEP short at an end no other piece overlaps, so that end keeps the
    hollow the player sees into."""
    s = field["axis"]
    ra = 0 if s == 2 else 2  # along the ridge
    spans = [(min(p[ra] for p in v), max(p[ra] for p in v)) for v in pieces]
    out = []
    for k, v in enumerate(pieces):
        lo, hi = spans[k]
        others = [sp for j, sp in enumerate(spans) if j != k]
        low = [(p[0], p[1] - CAP_INSET, p[2]) for p in v]
        w_lo, w_hi = min(p[s] for p in v), max(p[s] for p in v)
        mid, half = 0.5 * (w_lo + w_hi), 0.5 * (w_hi - w_lo) * RIDGE_SUPPORT_SHARE
        sv, sts = _sunk_hull(low, field["top"])
        sv, sts = _clip_convex(sv, sts, s, mid - half, True)
        sv, sts = _clip_convex(sv, sts, s, mid + half, False)
        for hv, ht in (convex_hull(low), (sv, sts)):
            if not any(a < lo < b for a, b in others):
                hv, ht = _clip_convex(hv, ht, ra, lo + RIDGE_END_KEEP, True)
            if not any(a < hi < b for a, b in others):
                hv, ht = _clip_convex(hv, ht, ra, hi - RIDGE_END_KEEP, False)
            out.append((hv, ht))
    return out


def _find_backing(iv, it, node_sheets):
    n_isl, area, cen, net = area_normal(iv, it)
    if net < 0.2 * area:
        return None
    best = None
    for s in node_sheets:
        if dot(s.n, n_isl) < BACKING_ALIGN_MIN:
            continue
        h = s.height(cen)
        if h < -CONTACT_TOL or h > BACKING_REACH:
            continue
        if not s.in_bbox2d(s.to2d(cen), BACKING_MARGIN):
            continue
        if best is None or h < best[0]:
            best = (h, s)
    return best[1] if best else None


def _extend_to_wall(ob, slabs, cx, cz):
    """Rule 6: extend the box's interior-side face to 2 mm inside the wall. Returns an error or ''."""
    axes, lo, hi = ob["axes"], ob["lo"], ob["hi"]
    thin = 0 if (hi[0] - lo[0]) <= (hi[2] - lo[2]) else 2
    other = [k for k in range(3) if k != thin]
    mid = [0.5 * (lo[k] + hi[k]) for k in range(3)]
    centre_w = add(add(mul(axes[0], mid[0]), mul(axes[1], mid[1])), mul(axes[2], mid[2]))
    toward = axes[thin][0] * (cx - centre_w[0]) + axes[thin][2] * (cz - centre_w[2])
    sign = 1.0 if toward >= 0.0 else -1.0
    u = mul(axes[thin], sign)

    def world(c):
        return add(add(mul(axes[0], c[0]), mul(axes[1], c[1])), mul(axes[2], c[2]))

    grid = [0.01, 0.25, 0.5, 0.75, 0.99]
    # Already overlapping a wall slab by >= 1 mm: leave it.
    for fa in grid:
        for fb in grid:
            for fd in grid:
                c = [0.0, 0.0, 0.0]
                c[other[0]] = lo[other[0]] + fa * (hi[other[0]] - lo[other[0]])
                c[other[1]] = lo[other[1]] + fb * (hi[other[1]] - lo[other[1]])
                c[thin] = lo[thin] + fd * (hi[thin] - lo[thin])
                p = world(c)
                if any(s.slab_contains(p, -CONTACT_TOL) for s in slabs):
                    return ""
    back = hi[thin] if sign > 0 else lo[thin]
    need = None
    for fa in grid:
        for fb in grid:
            c = [0.0, 0.0, 0.0]
            c[other[0]] = lo[other[0]] + fa * (hi[other[0]] - lo[other[0]])
            c[other[1]] = lo[other[1]] + fb * (hi[other[1]] - lo[other[1]])
            c[thin] = back
            p = world(c)
            tbest = None
            for s in slabs:
                dn = dot(s.n, u)
                if dn > -0.5:
                    continue
                t = -s.height(p) / dn
                if t <= 0.0 or t > ENVELOPE_REACH:
                    continue
                q = add(p, mul(u, t))
                if s.contains2d(s.to2d(q), 0.0) and (tbest is None or t < tbest):
                    tbest = t
            if tbest is not None:
                need = tbest if need is None else max(need, tbest)
    if need is None:
        return f"no wall behind it within {ENVELOPE_REACH:.1f} m"
    if sign > 0:
        hi[thin] += need + CAP_INSET
    else:
        lo[thin] -= need + CAP_INSET
    return ""


def _pull_inside_walls(verts, walls):
    """Rule 9: every vertex at least SCAFFOLD_PULL inside each hero wall face it sits against."""
    out = []
    moved = 0
    reach = DEFAULT_WALL_T + SCAFFOLD_PULL
    for p in verts:
        q = p
        for s in walls:
            h = s.height(q)
            if h <= -SCAFFOLD_PULL + 1e-6 or h > 1.0:
                continue
            if not s.in_bbox2d(s.to2d(q), reach):
                continue
            q = sub(q, mul(s.n, h + SCAFFOLD_PULL))
        if q != p:
            moved += 1
        out.append(q)
    return out, moved


def _push_caps(solids, rules, failures):
    """Rule 8: a 4a cap within 1 mm of another solid's surface is rebuilt 2 mm further out."""
    tris = []
    for si, s in enumerate(solids):
        for a, b, c in s.tris:
            tris.append((s.verts[a], s.verts[b], s.verts[c], si))
    grid = TriGrid(tris, 0.25)
    for si, s in enumerate(solids):
        if s.island is None:
            continue
        iv, it, loops, plans, caps, flipped = s.island
        new_plans = list(plans)
        pushed = 0
        for k, (first, last) in enumerate(caps):
            if plans[k] is not None:
                continue
            samples = []
            for ti in range(first, last):
                a, b, c = s.verts[s.tris[ti][0]], s.verts[s.tris[ti][1]], s.verts[s.tris[ti][2]]
                samples.append(mul(add(add(a, b), c), 1.0 / 3.0))
            if not samples:
                continue
            touching = 0
            for p in samples:
                for i in grid.near(p, CONTACT_TOL):
                    a, b, c, owner = grid.tris[i]
                    if owner != si and _point_tri_dist(p, a, b, c) <= CONTACT_TOL:
                        touching += 1
                        break
            if touching * 2 < len(samples):
                continue
            pts = [iv[i] for i in loops[k]]
            n_loop, c_loop, dev = loop_plane(pts)
            # The cap faces opposite the loop's Newell normal; push along the cap's outward normal.
            cap_out = mul(n_loop, -1.0) if not flipped else n_loop
            axis = mul(cap_out, -1.0)
            hmin = min(dot(sub(p, c_loop), axis) for p in pts)
            new_plans[k] = (axis, c_loop, hmin - CAP_INSET)
            pushed += 1
        if pushed:
            try:
                cv, ctris, _caps = close_island(iv, it, new_plans)
            except (CapError, LoopError) as exc:
                failures.append(f"{s.node}: pushed cap result is not closed ({exc})")
                continue
            ctris, _f = _orient_outward(cv, ctris)
            if not is_closed(ctris):
                failures.append(f"{s.node}: pushed cap result is not closed")
                continue
            s.verts, s.tris = cv, ctris
            rules["8_pushed_caps"] += pushed


def _slot_check(solids, report):
    """Ivy-reachable gaps narrower than SLOT_MIN between proxy faces (AR-MESH-20.4)."""
    tris = []
    for si, s in enumerate(solids):
        for a, b, c in s.tris:
            tris.append((s.verts[a], s.verts[b], s.verts[c], si))
    grid = TriGrid(tris, 0.25)
    diag = length(sub(grid.hi, grid.lo)) + 1.0
    clusters = {}
    contacts = {}
    enclosed = 0
    for ti, (a, b, c, owner) in enumerate(tris):
        n = grid.normals[ti]
        if n == (0.0, 0.0, 0.0):
            continue
        area = 0.5 * length(cross(sub(b, a), sub(c, a)))
        k = max(1, int(math.ceil(math.sqrt(2.0 * area) / 0.10)))
        for i in range(k):
            for j in range(k - i):
                wa = (i + 1.0 / 3.0) / k
                wb = (j + 1.0 / 3.0) / k
                p = add(add(mul(a, 1.0 - wa - wb), mul(b, wa)), mul(c, wb))
                hit = grid.ray(p, n, SLOT_MIN, tmin=1e-6)
                if hit is None:
                    continue
                t, hi_ = hit
                if t >= SLOT_MIN:
                    continue
                if dot(grid.normals[hi_], n) >= 0.0:
                    continue  # this face is buried in another solid
                if t < 5e-4:
                    if grid.tris[hi_][3] != owner:
                        key = (solids[owner].name, solids[grid.tris[hi_][3]].name)
                        contacts[key] = contacts.get(key, 0) + 1
                    continue
                if dot(grid.normals[hi_], n) > -SLOT_PARALLEL_MIN:
                    continue  # a V between faces meeting at an angle, not a parallel-walled slot
                m = add(p, mul(n, 0.5 * t))
                if not _escapes(grid, m, n, diag):
                    enclosed += 1
                    continue
                ax = max(range(3), key=lambda q: abs(n[q]))
                key = (round(m[0] / 0.25), round(m[1] / 0.25), round(m[2] / 0.25), ax)
                cl = clusters.setdefault(key, {"sum": (0.0, 0.0, 0.0), "n": 0, "width": t, "axis": ax,
                                               "lo": list(p), "hi": list(p),
                                               "between": sorted({solids[owner].name, solids[grid.tris[hi_][3]].name})})
                cl["sum"] = add(cl["sum"], m)
                cl["n"] += 1
                cl["width"] = min(cl["width"], t)
                for q in (p, add(p, mul(n, t))):
                    for ax3 in range(3):
                        cl["lo"][ax3] = min(cl["lo"][ax3], q[ax3])
                        cl["hi"][ax3] = max(cl["hi"][ax3], q[ax3])
    for key in sorted(clusters):
        cl = clusters[key]
        pos = mul(cl["sum"], 1.0 / cl["n"])
        report["slots"].append({"position": [round(x, 4) for x in pos], "width": round(cl["width"], 4),
                                "axis": "xyz"[cl["axis"]], "samples": cl["n"], "between": cl["between"],
                                "lo": [round(x, 4) for x in cl["lo"]], "hi": [round(x, 4) for x in cl["hi"]]})
    report["enclosed_gap_samples"] = enclosed
    report["contacts"] = [{"between": list(k), "samples": v} for k, v in sorted(contacts.items())]


def _escapes(grid, m, n, reach):
    u, v = plane_basis(n)
    for k in range(16):
        a = 2.0 * math.pi * (k + 0.5) / 16.0
        d = norm(add(mul(u, math.cos(a)), mul(v, math.sin(a))))
        if grid.ray(m, d, reach, tmin=1e-6) is None:
            return True
    return False


# ------------------------------------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------------------------------------


USAGE = ("usage: python3 tools/build_growth_surface.py <hero.glb> <scaffold_sim.glb> <out_sim.glb> "
         "[--structure <id>] [--report <json>] [--config <structure_configs.json>]")


def main(argv):
    pos, opts = [], {"--structure": None, "--report": None, "--config": str(DEFAULT_CONFIG)}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in opts:
            if i + 1 >= len(argv):
                print(f"{a} needs a value\n{USAGE}", file=sys.stderr)
                return 2
            opts[a] = argv[i + 1]
            i += 2
            continue
        if a.startswith("--"):
            print(f"unknown option {a}\n{USAGE}", file=sys.stderr)
            return 2
        pos.append(a)
        i += 1
    if len(pos) != 3:
        print(USAGE, file=sys.stderr)
        return 2
    hero_path, sc_path, out_path = (Path(p) for p in pos)
    if out_path.resolve() == hero_path.resolve():
        print("refusing to overwrite the hero GLB", file=sys.stderr)
        return 2
    structure = opts["--structure"]
    if structure is None:
        stem = hero_path.stem
        if not stem.endswith("_hero"):
            print(f"--structure not given and {hero_path.name} is not named <id>_hero.glb", file=sys.stderr)
            return 2
        structure = stem[: -len("_hero")]
    try:
        centre, st = load_structure(opts["--config"], structure)
        hero = read_glb(hero_path)
        scaffold = read_glb(sc_path)
    except (OSError, ValueError, KeyError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    try:
        meshes, report = build(hero, scaffold, structure, centre, st)
        code = 0
    except BuildError as exc:
        meshes, report, code = None, exc.report, 1
        for f in exc.failures:
            print(f"FAIL: {f}", file=sys.stderr)
    if opts["--report"]:
        Path(opts["--report"]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if code:
        print(f"build failed: {len(report.get('failures', []))} failure(s); nothing written", file=sys.stderr)
        return code
    out_path.write_bytes(glb_bytes(meshes, f"Sim_{structure}"))
    r = report["rules"]
    print(f"wrote {out_path}: {report['output']['nodes']} nodes, {report['output']['triangles']} triangles; "
          f"rules {json.dumps(r, sort_keys=True)}; slots 0; contacts {len(report['contacts'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
