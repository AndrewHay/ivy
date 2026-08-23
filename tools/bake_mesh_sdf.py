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
import struct
import sys
from pathlib import Path

MAGIC = b"IVYSDF1"
BAKER_VERSION = 1


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
    base = 0
    for node in nodes:
        if "mesh" not in node:
            continue
        mesh = meshes[node["mesh"]]
        xform = node_matrix(node)
        for prim in mesh["primitives"]:
            positions = read_accessor(prim["attributes"]["POSITION"])
            indices = read_accessor(prim["indices"]) if "indices" in prim else None
            local = [xform(p) for p in positions]
            if indices:
                flat = [i[0] for i in indices]
                for i in range(0, len(flat), 3):
                    all_tris.append((base + flat[i], base + flat[i + 1], base + flat[i + 2]))
            else:
                for i in range(0, len(local), 3):
                    all_tris.append((base + i, base + i + 1, base + i + 2))
            base += len(local)
            all_verts.extend(local)
    if not all_verts:
        raise SystemExit(f"no mesh geometry in {path}")
    return all_verts, all_tris


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
    denom = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2]
    if denom < 1e-20:
        return ((p[0] - v0[0]) ** 2 + (p[1] - v0[1]) ** 2 + (p[2] - v0[2]) ** 2) ** 0.5
    inv = 1.0 / denom
    v = (d1 * d4 - d3 * d2) * inv
    w = (d5 * d2 - d1 * d6) * inv
    q = (v0[0] + v * ab[0] + w * ac[0], v0[1] + v * ab[1] + w * ac[1], v0[2] + v * ab[2] + w * ac[2])
    return ((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2) ** 0.5


def ray_inside(p, tris, verts):
    # Cast +X ray; odd crossings => inside.
    px, py, pz = p
    count = 0
    for i0, i1, i2 in tris:
        v0, v1, v2 = verts[i0], verts[i1], verts[i2]
        y0, y1 = v0[1], v1[1]
        y2 = v2[1]
        if (y0 > py) == (y1 > py) and (y0 > py) == (y2 > py):
            continue
        z0, z1, z2 = v0[2], v1[2], v2[2]
        if (z0 > pz) == (z1 > pz) and (z0 > pz) == (z2 > pz):
            continue
        # Möller–Trumbore-ish slab for +X
        e1 = (v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2])
        e2 = (v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2])
        h = (0.0, pz - v0[2], py - v0[1])
        a = e1[1] * e2[2] - e1[2] * e2[1]
        if abs(a) < 1e-12:
            continue
        f = 1.0 / a
        u = (h[1] * e2[2] - h[2] * e2[1]) * f
        if u < 0.0 or u > 1.0:
            continue
        q = (h[2] * e1[1] - h[1] * e1[2], h[0] * e1[2] - h[2] * e1[0], h[1] * e1[0] - h[0] * e1[1])
        v = (px - v0[0]) * q[0] + (py - v0[1]) * q[1] + (pz - v0[2]) * q[2]
        v *= f
        if v < 0.0 or u + v > 1.0:
            continue
        t = e2[0] * q[0] + e2[1] * q[1] + e2[2] * q[2]
        t *= f
        if t > 1e-6:
            count += 1
    return count % 2 == 1


def bake(verts, tris, cell: float, band: float):
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

    # Seed cells near each triangle
    for i0, i1, i2 in tris:
        v0, v1, v2 = verts[i0], verts[i1], verts[i2]
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

    out = []
    for iz in range(dims[2]):
        for iy in range(dims[1]):
            for ix in range(dims[0]):
                j = idx(ix, iy, iz)
                d = dist[j]
                if d > band:
                    out.append(band)
                    continue
                p = (
                    origin[0] + (ix + 0.5) * cell,
                    origin[1] + (iy + 0.5) * cell,
                    origin[2] + (iz + 0.5) * cell,
                )
                inside = ray_inside(p, tris, verts)
                out.append(-d if inside else d)
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
    verts, tris = load_glb_mesh(src)
    print(f"loaded {src.name}: {len(verts)} verts, {len(tris)} tris")
    origin, dims, mesh_aabb, values = bake(verts, tris, cell, band)
    prov = provenance_hash(src, cell, band)
    dst.parent.mkdir(parents=True, exist_ok=True)
    write_sdf(dst, origin, dims, mesh_aabb, values, cell, band, prov)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
