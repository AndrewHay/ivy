#!/usr/bin/env python3
"""Per-GLB-node hero/proxy deviation breakdown for SD-OPEN-22 diagnosis.

Reports max/median |Φ| at hero-mesh vertices grouped by glTF node name,
so the exact kit-piece category causing outliers can be identified.

Usage (from project root):
  python3 tools/diagnose_hero_deviation.py
  python3 tools/diagnose_hero_deviation.py square tower
"""

from __future__ import annotations

import json
import struct
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from measure_structure_gates import load_sdf, read_trilinear  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent
STRUCTURES = PROJECT / "assets" / "structures"
DEVIATION_CEILING = 0.05

# ---------------------------------------------------------------------------
# GLB loader that preserves per-node vertex assignments
# ---------------------------------------------------------------------------

def load_glb_nodes(path: Path):
    """Return list of (node_name, [(x,y,z), ...]) — one entry per glTF node."""
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise SystemExit(f"not a GLB: {path}")
    off = 12
    json_chunk = None
    bin_chunk = b""
    while off + 8 <= len(data):
        ln, tp = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off : off + ln]
        off += ln
        if tp == 0x4E4F534A:
            json_chunk = json.loads(chunk.decode("utf-8"))
        elif tp == 0x004E4942:
            bin_chunk = chunk
    if json_chunk is None:
        raise SystemExit(f"GLB missing JSON chunk: {path}")

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

    def apply_transform(node, v):
        t = node.get("translation", [0, 0, 0])
        r = node.get("rotation", [0, 0, 0, 1])
        s = node.get("scale", [1, 1, 1])
        px, py, pz = v[0] * s[0], v[1] * s[1], v[2] * s[2]
        rx, ry, rz = quat_rotate(r, (px, py, pz))
        return (rx + t[0], ry + t[1], rz + t[2])

    result = []
    for node in nodes:
        if "mesh" not in node:
            continue
        node_name = node.get("name", f"node_{node['mesh']}")
        mesh = meshes[node["mesh"]]
        node_verts = []
        for prim in mesh["primitives"]:
            positions = read_accessor(prim["attributes"]["POSITION"])
            for p in positions:
                node_verts.append(apply_transform(node, p))
        if node_verts:
            result.append((node_name, node_verts))
    return result


def classify_node(name: str) -> str:
    """Return a human-readable category for a glTF node name."""
    n = name.lower()
    if "cornerexteriorwide" in n or "corner_exteriorwide" in n or "exteriorwide" in n:
        return "corner_trim_wide"
    if "cornerexterior" in n or "corner_exterior" in n:
        return "corner_trim_block"
    if "cornercolumn" in n or "corner_column" in n or "cornerblock" in n:
        return "corner_sim_column"
    if "door_2_round" in n or "door2round" in n:
        return "door_leaf"
    if "doorframe_round" in n or "doorframe" in n:
        return "door_frame"
    if "roofcap" in n or "roof_cap" in n:
        return "roof_cap"
    if "midfloor" in n or "mid_floor" in n:
        return "mid_floor_slab"
    if "floorslab" in n or "floor_slab" in n:
        return "floor_slab"
    if "panel_" in n or "_panel_" in n:
        return "aperture_panel"
    if "seal_" in n or "_seal_" in n:
        return "aperture_seal"
    if "wall_unevenbrick_door" in n:
        return "wall_door_bay"
    if "wall_unevenbrick_window" in n:
        return "wall_window_bay"
    if "wall_unevenbrick_straight" in n:
        return "wall_straight"
    if "wall_" in n:
        return "wall_other"
    return "other"


def analyze_structure(name: str):
    hero_path = STRUCTURES / f"{name}_hero.glb"
    sdf_path = STRUCTURES / f"{name}_sim.sdf"

    print(f"\n{'=' * 70}")
    print(f"Structure: {name}")
    print(f"{'=' * 70}")

    nodes = load_glb_nodes(hero_path)
    sdf = load_sdf(sdf_path)

    total_verts = sum(len(vs) for _, vs in nodes)
    print(f"glTF nodes: {len(nodes)}   total hero verts: {total_verts}\n")

    # Accumulate per-category stats
    cat_data: dict[str, list[float]] = defaultdict(list)
    node_data: dict[str, list[float]] = defaultdict(list)

    for node_name, verts in nodes:
        cat = classify_node(node_name)
        for v in verts:
            phi = abs(read_trilinear(sdf, v))
            cat_data[cat].append(phi)
            node_data[node_name].append(phi)

    def stats(vals):
        if not vals:
            return {}
        s = sorted(vals)
        n = len(s)
        return {
            "n": n,
            "median": s[n // 2],
            "p90": s[int(0.9 * n)],
            "max": s[-1],
            "over_50mm": sum(1 for v in s if v > DEVIATION_CEILING),
        }

    # Per-category table
    print(f"{'Category':<26} {'N':>6}  {'Median':>8}  {'P90':>8}  {'Max':>8}  {'>50mm':>6}")
    print("-" * 70)
    cat_rows = sorted(cat_data.items(), key=lambda kv: -max(kv[1]))
    for cat, vals in cat_rows:
        st = stats(vals)
        print(f"  {cat:<24} {st['n']:>6}  {st['median']:>8.4f}  {st['p90']:>8.4f}  {st['max']:>8.4f}  {st['over_50mm']:>6}")

    # Top-10 individual worst nodes
    node_rows = sorted(node_data.items(), key=lambda kv: -max(kv[1]))[:15]
    print(f"\nTop 15 nodes by max |Φ|:")
    print(f"  {'Node name':<60} {'Max':>8}  {'N':>6}")
    print("  " + "-" * 78)
    for nn, vals in node_rows:
        st = stats(vals)
        print(f"  {nn:<60} {st['max']:>8.4f}  {st['n']:>6}")

    # Per-category, print the worst vertex location for the top offender
    print(f"\nWorst vertex per category (world coords):")
    for cat, vals in cat_rows[:6]:
        worst_phi = -1.0
        worst_v = None
        worst_node = None
        for node_name, verts in nodes:
            if classify_node(node_name) != cat:
                continue
            for v in verts:
                phi = abs(read_trilinear(sdf, v))
                if phi > worst_phi:
                    worst_phi = phi
                    worst_v = v
                    worst_node = node_name
        if worst_v:
            print(f"  {cat:<26}  max={worst_phi:.4f} m  "
                  f"at ({worst_v[0]:.2f}, {worst_v[1]:.2f}, {worst_v[2]:.2f})  "
                  f"node={worst_node}")

    return cat_data, node_data


def main(argv):
    names = argv[1:] if len(argv) > 1 else ["square", "tower"]
    for name in names:
        analyze_structure(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
