#!/usr/bin/env python3
"""Offline narrow-band SDF baker for MeshSdf (SD-MESH-9, SD-MESH-10).

Usage:
  python3 tools/bake_mesh_sdf.py <input.glb> <output.sdf> [--cell 0.05] [--band 0.55]

Reads the first mesh primitive from a glTF binary, builds a dense padded volume,
and writes the IVYSDF1 binary format consumed by mesh_sdf.gd.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
import sys
from pathlib import Path

MAGIC = b"IVYSDF1"
BAKER_VERSION = 5


def load_glb_mesh(path: Path):
    import struct as st

    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise SystemExit(f"not a GLB: {path}")
    off = 12
    json_chunk = None
    bin_chunk = b""
    while off + 8 <= len(data):
        ln, tp = st.unpack_from("<II", data, off)
        off += 8
        chunk = data[off : off + ln]
        off += ln
        if tp == 0x4E4F534A:
            json_chunk = json.loads(chunk.decode("utf-8"))
        elif tp == 0x004E4942:
            bin_chunk = chunk
    if json_chunk is None:
        raise SystemExit("GLB missing JSON chunk")

    accessors = json_chunk["accessors"]
    buffer_views = json_chunk["bufferViews"]
    meshes = json_chunk["meshes"]
    nodes = json_chunk.get("nodes", [])

    def read_accessor(acc_idx):
        acc = accessors[acc_idx]
        bv = buffer_views[acc["bufferView"]]
        start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        count = acc["count"]
        ctype = acc["componentType"]
        atype = acc["type"]
        comp = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[ctype]
        ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[atype]
        fmt = "<" + comp * ncomp
        stride = bv.get("byteStride", ncomp * struct.calcsize(comp))
        out = []
        for i in range(count):
            base = start + i * stride
            out.append(struct.unpack_from(fmt, bin_chunk, base))
        return out

    def quat_rotate(q, v):
        x, y, z, w = q
        vx, vy, vz = v
        ix = w * vx + y * vz - z * vy
        iy = w * vy + z * vx - x * vz
        iz = w * vz + x * vy - y * vx
        iw = -x * vx - y * vy - z * vz
        return (
            ix * w + iw * -x + iy * -z - iz * -y,
            iy * w + iw * -y + iz * -x - ix * -z,
            iz * w + iw * -z + ix * -y - iy * -x,
        )

    def node_matrix(node):
        t = node.get("translation", [0, 0, 0])
        r = node.get("rotation", [0, 0, 0, 1])
        s = node.get("scale", [1, 1, 1])

        def apply(v):
            px, py, pz = v[0] * s[0], v[1] * s[1], v[2] * s[2]
            rx, ry, rz = quat_rotate(r, (px, py, pz))
            return (rx + t[0], ry + t[1], rz + t[2])

        return apply

    all_verts = []
    all_tris = []
    shells = []
    global_base = 0
    for node in nodes:
        if "mesh" not in node:
            continue
        mesh = meshes[node["mesh"]]
        xform = node_matrix(node)
        node_verts = []
        node_tris = []
        node_base = 0
        for prim in mesh["primitives"]:
            positions = read_accessor(prim["attributes"]["POSITION"])
            indices = read_accessor(prim["indices"]) if "indices" in prim else None
            local = [xform(p) for p in positions]
            if indices:
                flat = [i[0] for i in indices]
                for i in range(0, len(flat), 3):
                    tri = (node_base + flat[i], node_base + flat[i + 1], node_base + flat[i + 2])
                    node_tris.append(tri)
            else:
                for i in range(0, len(local), 3):
                    node_tris.append((node_base + i, node_base + i + 1, node_base + i + 2))
            node_base += len(local)
            node_verts.extend(local)
        if not node_verts:
            continue
        shells.append((node_verts, node_tris))
        for t in node_tris:
            all_tris.append((t[0] + global_base, t[1] + global_base, t[2] + global_base))
        all_verts.extend(node_verts)
        global_base += len(node_verts)
    if not all_verts:
        raise SystemExit(f"no mesh geometry in {path}")
    return all_verts, all_tris, shells


def tri_bounds(v0, v1, v2):
    xs = [v0[0], v1[0], v2[0]]
    ys = [v0[1], v1[1], v2[1]]
    zs = [v0[2], v1[2], v2[2]]
    return (
        min(xs),
        min(ys),
        min(zs),
        max(xs),
        max(ys),
        max(zs),
    )


def point_tri_dist(p, v0, v1, v2):
    # Ericson, Real-Time Collision Detection
    ab = (v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2])
    ac = (v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2])
    ap = (p[0] - v0[0], p[1] - v0[1], p[2] - v0[2])
    d1 = ab[0] * ap[0] + ab[1] * ap[1] + ab[2] * ap[2]
    d2 = ac[0] * ap[0] + ac[1] * ap[1] + ac[2] * ap[2]
    if d1 <= 0.0 and d2 <= 0.0:
        return ((p[0] - v0[0]) ** 2 + (p[1] - v0[1]) ** 2 + (p[2] - v0[2]) ** 2) ** 0.5
    bp = (p[0] - v1[0], p[1] - v1[1], p[2] - v1[2])
    d3 = ab[0] * bp[0] + ab[1] * bp[1] + ab[2] * bp[2]
    d4 = ac[0] * bp[0] + ac[1] * bp[1] + ac[2] * bp[2]
    if d3 >= 0.0 and d4 <= d3:
        return ((p[0] - v1[0]) ** 2 + (p[1] - v1[1]) ** 2 + (p[2] - v1[2]) ** 2) ** 0.5
    vc = d1 * d4 - d3 * d2
    if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
        v = d1 / (d1 - d3)
        q = (v0[0] + v * ab[0], v0[1] + v * ab[1], v0[2] + v * ab[2])
        return ((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2) ** 0.5
    cp = (p[0] - v2[0], p[1] - v2[1], p[2] - v2[2])
    d5 = ab[0] * cp[0] + ab[1] * cp[1] + ab[2] * cp[2]
    d6 = ac[0] * cp[0] + ac[1] * cp[1] + ac[2] * cp[2]
    if d6 >= 0.0 and d5 <= d6:
        return ((p[0] - v2[0]) ** 2 + (p[1] - v2[1]) ** 2 + (p[2] - v2[2]) ** 2) ** 0.5
    vb = d5 * d2 - d1 * d6
    if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
        w = d2 / (d2 - d6)
        q = (v0[0] + w * ac[0], v0[1] + w * ac[1], v0[2] + w * ac[2])
        return ((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2) ** 0.5
    va = d3 * d6 - d5 * d4
    if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
        w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        q = (
            v1[0] + w * (v2[0] - v1[0]),
            v1[1] + w * (v2[1] - v1[1]),
            v1[2] + w * (v2[2] - v1[2]),
        )
        return ((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2) ** 0.5
    denom = va + vb + vc
    if abs(denom) < 1e-20:
        return ((p[0] - v0[0]) ** 2 + (p[1] - v0[1]) ** 2 + (p[2] - v0[2]) ** 2) ** 0.5
    inv = 1.0 / denom
    v = vb * inv
    w = vc * inv
    q = (v0[0] + v * ab[0] + w * ac[0], v0[1] + v * ab[1] + w * ac[1], v0[2] + v * ab[2] + w * ac[2])
    return ((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2) ** 0.5


def _permute_xyz(v, axis: int):
    """Cycle (x,y,z) so ``axis`` becomes +X for ray casting (ivy-7p0)."""
    if axis == 0:
        return v
    if axis == 1:
        return (v[1], v[2], v[0])
    return (v[2], v[0], v[1])


# Micrometre offsets applied to the two coordinates perpendicular to a parity ray.
# Cell centres and kit vertices both sit on round decimals, so an unperturbed ray
# regularly runs exactly along a shared triangle edge and is counted 0 or 2 times.
_RAY_JITTER_B = 3.1e-6
_RAY_JITTER_C = 7.3e-6


def _ray_crossings_plus_x(p, tris, verts) -> int:
    """Count triangles hit by the +X ray from ``p`` (odd => inside a closed shell).

    Projects each triangle onto the YZ plane, tests the (jittered) ray origin with
    three edge functions, then compares the hit's X against ``p`` (ivy-b1e.3: the
    previous Moller-Trumbore variant returned 0 crossings for ordinary kit boxes,
    so baked interiors were unsigned).
    """
    px = p[0]
    py = p[1] + _RAY_JITTER_B
    pz = p[2] + _RAY_JITTER_C
    count = 0
    for i0, i1, i2 in tris:
        v0, v1, v2 = verts[i0], verts[i1], verts[i2]
        y0 = v0[1] - py
        y1 = v1[1] - py
        y2 = v2[1] - py
        if (y0 > 0.0) == (y1 > 0.0) and (y0 > 0.0) == (y2 > 0.0):
            continue
        z0 = v0[2] - pz
        z1 = v1[2] - pz
        z2 = v2[2] - pz
        if (z0 > 0.0) == (z1 > 0.0) and (z0 > 0.0) == (z2 > 0.0):
            continue
        d0 = y0 * z1 - y1 * z0
        d1 = y1 * z2 - y2 * z1
        d2 = y2 * z0 - y0 * z2
        if not ((d0 > 0.0 and d1 > 0.0 and d2 > 0.0) or (d0 < 0.0 and d1 < 0.0 and d2 < 0.0)):
            continue
        x = (d1 * v0[0] + d2 * v1[0] + d0 * v2[0]) / (d0 + d1 + d2)
        if x > px:
            count += 1
    return count


def ray_inside_shell(p, tris, verts):
    """+X parity for a single closed shell."""
    return _ray_crossings_plus_x(p, tris, verts) % 2 == 1


def _ray_inside_shell_majority(p, tris, verts) -> bool:
    """Parity along each axis, majority vote (ivy-7p0).

    A closed shell agrees on all three axes; the vote only matters for kit pieces
    with open boundaries, where a single axis can leak through the hole.
    """
    votes = 0
    for axis in (0, 1, 2):
        pp = _permute_xyz(p, axis)
        vperm = [_permute_xyz(v, axis) for v in verts]
        if _ray_crossings_plus_x(pp, tris, vperm) % 2 == 1:
            votes += 1
    return votes >= 2


def shell_is_closed(verts, tris) -> bool:
    """True when every welded edge is shared by an even number of triangles."""
    weld = {}
    edges = {}
    for tri in tris:
        ids = [weld.setdefault(tuple(round(c, 5) for c in verts[i]), len(weld)) for i in tri]
        for e in ((ids[0], ids[1]), (ids[1], ids[2]), (ids[2], ids[0])):
            if e[0] == e[1]:
                continue
            key = e if e[0] < e[1] else (e[1], e[0])
            edges[key] = edges.get(key, 0) + 1
    return all(n % 2 == 0 for n in edges.values())


def _winding_number(p, tri_points) -> float:
    """Generalised winding number of ``p`` (Van Oosterom & Strackee solid angles)."""
    px, py, pz = p
    total = 0.0
    for v0, v1, v2 in tri_points:
        ax, ay, az = v0[0] - px, v0[1] - py, v0[2] - pz
        bx, by, bz = v1[0] - px, v1[1] - py, v1[2] - pz
        cx, cy, cz = v2[0] - px, v2[1] - py, v2[2] - pz
        la = math.sqrt(ax * ax + ay * ay + az * az)
        lb = math.sqrt(bx * bx + by * by + bz * bz)
        lc = math.sqrt(cx * cx + cy * cy + cz * cz)
        num = (
            ax * (by * cz - bz * cy)
            - ay * (bx * cz - bz * cx)
            + az * (bx * cy - by * cx)
        )
        den = (
            la * lb * lc
            + (ax * bx + ay * by + az * bz) * lc
            + (ax * cx + ay * cy + az * cz) * lb
            + (bx * cx + by * cy + bz * cz) * la
        )
        total += 2.0 * math.atan2(num, den)
    return total / (4.0 * math.pi)


def _inside_open_shell(p, tri_points) -> bool:
    """Open kit pieces have no parity. With glTF's outward (counter-clockwise)
    winding the number is ~1 well inside, ~0 outside and 0.5 across a missing face,
    so a box that lost one side still signs correctly. A single-sided sheet never
    reaches 0.5 and stays unsigned: that is a proxy defect, not something to guess."""
    return _winding_number(p, tri_points) > 0.5


def _tri_points(verts, tris):
    return [(verts[i0], verts[i1], verts[i2]) for i0, i1, i2 in tris]


def _inside_shell(p, tris, verts) -> bool:
    if shell_is_closed(verts, tris):
        return _ray_inside_shell_majority(p, tris, verts)
    return _inside_open_shell(p, _tri_points(verts, tris))


def ray_inside(p, shells):
    """Inside the union of the glTF node meshes (ivy-7p0).

    Each node is its own shell: overlapping closed pieces would cancel under a
    single merged parity count, so the test is taken per shell and then unioned.
    Closed shells use three-axis parity, open ones the winding number.
    """
    return any(_inside_shell(p, tris, verts) for verts, tris in shells)


def _open_shell_mask(verts, tris, origin, dims, cell: float) -> int:
    """Winding-number inside mask for one open shell, as a little-endian bit-per-byte int."""
    nx, ny, nz = dims
    pts = _tri_points(verts, tris)
    lo = [min(v[k] for v in verts) for k in range(3)]
    hi = [max(v[k] for v in verts) for k in range(3)]
    rng = []
    for k in range(3):
        i_lo = max(0, int((lo[k] - origin[k]) / cell - 0.5))
        i_hi = min(dims[k] - 1, int((hi[k] - origin[k]) / cell - 0.5) + 1)
        rng.append((i_lo, i_hi))
    mask = bytearray(nx * ny * nz)
    for iz in range(rng[2][0], rng[2][1] + 1):
        pz = origin[2] + (iz + 0.5) * cell
        for iy in range(rng[1][0], rng[1][1] + 1):
            py = origin[1] + (iy + 0.5) * cell
            row = iy * nx + iz * nx * ny
            for ix in range(rng[0][0], rng[0][1] + 1):
                if _inside_open_shell((origin[0] + (ix + 0.5) * cell, py, pz), pts):
                    mask[row + ix] = 1
    return int.from_bytes(mask, "little")


def inside_grid(shells, origin, dims, cell: float) -> bytearray:
    """``ray_inside`` for every cell centre of the bake grid, as a 0/1 bytearray.

    Same rule as ``ray_inside`` (per shell, then union). Closed shells cast one ray
    per grid column instead of one per cell, which is what makes signing the whole
    volume affordable in pure Python; open shells fall back to the winding number
    over their own bounding box.
    """
    nx, ny, nz = dims
    total = nx * ny * nz
    strides = (1, nx, nx * ny)
    union = 0
    for verts, tris in shells:
        if not shell_is_closed(verts, tris):
            union |= _open_shell_mask(verts, tris, origin, dims, cell)
            continue
        per_axis = []
        for a, b, c in ((0, 1, 2), (1, 2, 0), (2, 0, 1)):
            na, nb, nc = dims[a], dims[b], dims[c]
            sa, sb, sc = strides[a], strides[b], strides[c]
            oa, ob, oc = origin[a], origin[b], origin[c]
            columns = {}
            for i0, i1, i2 in tris:
                v0, v1, v2 = verts[i0], verts[i1], verts[i2]
                b0, b1, b2 = v0[b], v1[b], v2[b]
                c0, c1, c2 = v0[c], v1[c], v2[c]
                ib_lo = max(0, int((min(b0, b1, b2) - ob) / cell - 0.5) - 1)
                ib_hi = min(nb - 1, int((max(b0, b1, b2) - ob) / cell - 0.5) + 1)
                ic_lo = max(0, int((min(c0, c1, c2) - oc) / cell - 0.5) - 1)
                ic_hi = min(nc - 1, int((max(c0, c1, c2) - oc) / cell - 0.5) + 1)
                for ic in range(ic_lo, ic_hi + 1):
                    pc = oc + (ic + 0.5) * cell + _RAY_JITTER_C
                    z0, z1, z2 = c0 - pc, c1 - pc, c2 - pc
                    if (z0 > 0.0) == (z1 > 0.0) and (z0 > 0.0) == (z2 > 0.0):
                        continue
                    for ib in range(ib_lo, ib_hi + 1):
                        pb = ob + (ib + 0.5) * cell + _RAY_JITTER_B
                        y0, y1, y2 = b0 - pb, b1 - pb, b2 - pb
                        d0 = y0 * z1 - y1 * z0
                        d1 = y1 * z2 - y2 * z1
                        d2 = y2 * z0 - y0 * z2
                        if not (
                            (d0 > 0.0 and d1 > 0.0 and d2 > 0.0)
                            or (d0 < 0.0 and d1 < 0.0 and d2 < 0.0)
                        ):
                            continue
                        hit = (d1 * v0[a] + d2 * v1[a] + d0 * v2[a]) / (d0 + d1 + d2)
                        columns.setdefault(ib * sb + ic * sc, []).append(hit)
            mask = bytearray(total)
            for base, hits in columns.items():
                hits.sort()
                n = len(hits)
                # A centre between hits[j] and hits[j+1] has n-1-j hits ahead of it.
                for j in range(-1, n - 1):
                    if (n - 1 - j) % 2 == 0:
                        continue
                    lo = 0 if j < 0 else int((hits[j] - oa) / cell - 0.5) + 1
                    if j >= 0 and oa + (lo - 0.5) * cell > hits[j]:
                        lo -= 1
                    hi = int((hits[j + 1] - oa) / cell - 0.5)
                    if oa + (hi + 0.5) * cell >= hits[j + 1]:
                        hi -= 1
                    lo = max(lo, 0)
                    hi = min(hi, na - 1)
                    if hi < lo:
                        continue
                    count = hi - lo + 1
                    start = base + lo * sa
                    mask[start : start + count * sa : sa] = b"\x01" * count
            per_axis.append(int.from_bytes(mask, "little"))
        m0, m1, m2 = per_axis
        union |= (m0 & m1) | (m0 & m2) | (m1 & m2)
    return bytearray(union.to_bytes(total, "little"))


_CLIP_EPS = 1e-4  # 0.1 mm: faces lying on a neighbour's surface count as exposed


def _convex_planes(verts, tris):
    """Outward face planes ``(nx, ny, nz, d)`` of a convex shell, else ``None``."""
    planes = {}
    for i0, i1, i2 in tris:
        v0, v1, v2 = verts[i0], verts[i1], verts[i2]
        e1 = (v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2])
        e2 = (v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2])
        n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        ln = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
        if ln < 1e-12:
            continue
        n = (n[0] / ln, n[1] / ln, n[2] / ln)
        d = n[0] * v0[0] + n[1] * v0[1] + n[2] * v0[2]
        side = [n[0] * v[0] + n[1] * v[1] + n[2] * v[2] - d for v in verts]
        if max(side) <= _CLIP_EPS:
            pass
        elif min(side) >= -_CLIP_EPS:
            n, d = (-n[0], -n[1], -n[2]), -d
        else:
            return None
        planes[tuple(round(c, 6) for c in (*n, d))] = (*n, d)
    return list(planes.values()) if len(planes) >= 4 else None


def _split_polygon(poly, plane, offset):
    """Split a convex polygon by ``n.x = d + offset`` into (front, back) parts."""
    nx, ny, nz, d = plane
    d += offset
    dist = [nx * p[0] + ny * p[1] + nz * p[2] - d for p in poly]
    front, back = [], []
    count = len(poly)
    for i in range(count):
        p, sp = poly[i], dist[i]
        q, sq = poly[(i + 1) % count], dist[(i + 1) % count]
        if sp >= 0.0:
            front.append(p)
        else:
            back.append(p)
        if (sp >= 0.0) != (sq >= 0.0):
            t = sp / (sp - sq)
            x = (p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1]), p[2] + t * (q[2] - p[2]))
            front.append(x)
            back.append(x)
    return front, back


def _polygon_area(poly) -> float:
    ax = ay = az = 0.0
    p0 = poly[0]
    for i in range(1, len(poly) - 1):
        e1 = (poly[i][0] - p0[0], poly[i][1] - p0[1], poly[i][2] - p0[2])
        e2 = (poly[i + 1][0] - p0[0], poly[i + 1][1] - p0[1], poly[i + 1][2] - p0[2])
        ax += e1[1] * e2[2] - e1[2] * e2[1]
        ay += e1[2] * e2[0] - e1[0] * e2[2]
        az += e1[0] * e2[1] - e1[1] * e2[0]
    return 0.5 * math.sqrt(ax * ax + ay * ay + az * az)


def exposed_triangles(shells):
    """Triangles of the union's surface, as vertex-coordinate triples.

    Where kit pieces overlap, one piece's faces run through the inside of another.
    Left in, they pull the interior distance towards zero and drag the zero set up
    to a couple of centimetres inward along every junction (ivy-b1e.3). Each
    triangle is clipped against every *other* convex shell and only the part
    outside is kept. Faces buried in a non-convex piece are left as they are.
    """
    convex = []
    for verts, tris in shells:
        planes = _convex_planes(verts, tris) if shell_is_closed(verts, tris) else None
        if planes is None:
            convex.append(None)
            continue
        lo = tuple(min(v[k] for v in verts) for k in range(3))
        hi = tuple(max(v[k] for v in verts) for k in range(3))
        convex.append((planes, lo, hi))
    out = []
    for si, (verts, tris) in enumerate(shells):
        for i0, i1, i2 in tris:
            pieces = [[verts[i0], verts[i1], verts[i2]]]
            for sj, clip in enumerate(convex):
                if sj == si or clip is None:
                    continue
                planes, lo, hi = clip
                next_pieces = []
                for poly in pieces:
                    if any(
                        max(p[k] for p in poly) <= lo[k] or min(p[k] for p in poly) >= hi[k]
                        for k in range(3)
                    ):
                        next_pieces.append(poly)
                        continue
                    rest = poly
                    for plane in planes:
                        front, rest = _split_polygon(rest, plane, -_CLIP_EPS)
                        if len(front) >= 3:
                            next_pieces.append(front)
                        if len(rest) < 3:
                            break
                pieces = next_pieces
                if not pieces:
                    break
            for poly in pieces:
                for k in range(1, len(poly) - 1):
                    tri = (poly[0], poly[k], poly[k + 1])
                    # A cut through a vertex leaves zero-area fan triangles.
                    if _polygon_area(tri) > 1e-12:
                        out.append(tri)
    return out


def bake(verts, tris, cell: float, band: float, shells=None):
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    mesh_aabb = (min(xs), min(ys), min(zs), max(xs), max(ys), max(zs))
    pad = band
    lo = (mesh_aabb[0] - pad, mesh_aabb[1] - pad, mesh_aabb[2] - pad)
    hi = (mesh_aabb[3] + pad, mesh_aabb[4] + pad, mesh_aabb[5] + pad)
    origin = (
        cell * (lo[0] // cell if lo[0] >= 0 else (lo[0] - cell + 1) // cell * cell),
        cell * (lo[1] // cell if lo[1] >= 0 else (lo[1] - cell + 1) // cell * cell),
        cell * (lo[2] // cell if lo[2] >= 0 else (lo[2] - cell + 1) // cell * cell),
    )
    # snap down
    origin = (
        int(lo[0] / cell) * cell,
        int(lo[1] / cell) * cell,
        int(lo[2] / cell) * cell,
    )
    dims = (
        int((hi[0] - origin[0]) / cell) + 1,
        int((hi[1] - origin[1]) / cell) + 1,
        int((hi[2] - origin[2]) / cell) + 1,
    )
    total = dims[0] * dims[1] * dims[2]
    if total > 32_000_000:
        raise SystemExit(f"grid too large: {dims} = {total} cells")

    dist = [band + 1.0] * total

    def idx(ix, iy, iz):
        return ix + iy * dims[0] + iz * dims[0] * dims[1]

    if shells is not None and len(shells) > 1:
        dist_tris = exposed_triangles(shells)
    else:
        dist_tris = _tri_points(verts, tris)

    # Seed cells near each triangle
    for v0, v1, v2 in dist_tris:
        bx0, by0, bz0, bx1, by1, bz1 = tri_bounds(v0, v1, v2)
        bx0 -= band
        by0 -= band
        bz0 -= band
        bx1 += band
        by1 += band
        bz1 += band
        ix0 = max(0, int((bx0 - origin[0]) / cell))
        iy0 = max(0, int((by0 - origin[1]) / cell))
        iz0 = max(0, int((bz0 - origin[2]) / cell))
        ix1 = min(dims[0] - 1, int((bx1 - origin[0]) / cell))
        iy1 = min(dims[1] - 1, int((by1 - origin[1]) / cell))
        iz1 = min(dims[2] - 1, int((bz1 - origin[2]) / cell))
        for iz in range(iz0, iz1 + 1):
            for iy in range(iy0, iy1 + 1):
                for ix in range(ix0, ix1 + 1):
                    p = (
                        origin[0] + (ix + 0.5) * cell,
                        origin[1] + (iy + 0.5) * cell,
                        origin[2] + (iz + 0.5) * cell,
                    )
                    d = point_tri_dist(p, v0, v1, v2)
                    j = idx(ix, iy, iz)
                    if d < dist[j]:
                        dist[j] = d

    # Sign every cell, including those beyond the band: deep interior clamps to
    # -band, so a point far inside a solid never reads as open air.
    sign_shells = shells if shells is not None else [(verts, tris)]
    inside = inside_grid(sign_shells, origin, dims, cell)
    out = []
    for j in range(total):
        d = dist[j]
        if d > band:
            d = band
        out.append(-d if inside[j] else d)
    return origin, dims, mesh_aabb, out


def provenance_hash(mesh_path: Path, cell: float, band: float) -> bytes:
    h = hashlib.sha256()
    h.update(mesh_path.read_bytes())
    h.update(struct.pack("<ffI", cell, band, BAKER_VERSION))
    return h.digest()


def write_sdf(path: Path, origin, dims, mesh_aabb, values, cell, band, prov):
    with path.open("wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<ff", cell, band))
        f.write(struct.pack("<fff", *origin))
        f.write(struct.pack("<iii", *dims))
        f.write(struct.pack("<fff", mesh_aabb[0], mesh_aabb[1], mesh_aabb[2]))
        f.write(
            struct.pack(
                "<fff",
                mesh_aabb[3] - mesh_aabb[0],
                mesh_aabb[4] - mesh_aabb[1],
                mesh_aabb[5] - mesh_aabb[2],
            )
        )
        f.write(struct.pack("<I", BAKER_VERSION))
        f.write(prov)
        f.write(struct.pack("<%df" % len(values), *values))
    print(f"wrote {path}  dims={dims}  cells={len(values)}  cell={cell}  band={band}")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    src = Path(argv[1])
    dst = Path(argv[2])
    cell = 0.05
    band = 0.55
    i = 3
    while i < len(argv):
        if argv[i] == "--cell" and i + 1 < len(argv):
            cell = float(argv[i + 1])
            i += 2
        elif argv[i] == "--band" and i + 1 < len(argv):
            band = float(argv[i + 1])
            i += 2
        else:
            raise SystemExit(f"unknown arg: {argv[i]}")
    verts, tris, shells = load_glb_mesh(src)
    print(f"loaded {src.name}: {len(verts)} verts, {len(tris)} tris, {len(shells)} shells")
    for i, (sv, st) in enumerate(shells):
        if not shell_is_closed(sv, st):
            print(
                f"warning: shell {i} ({len(st)} tris) is not a closed mesh; "
                "its interior is signed by winding number and may read as outside"
            )
    origin, dims, mesh_aabb, values = bake(verts, tris, cell, band, shells)
    prov = provenance_hash(src, cell, band)
    dst.parent.mkdir(parents=True, exist_ok=True)
    write_sdf(dst, origin, dims, mesh_aabb, values, cell, band, prov)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
