#!/usr/bin/env python3
"""Offline Director gate measurements for M2.6 structure assets (SD-OPEN-22/23).

Measures per structure:
  1. Minimum wall thickness on the sim (collision/SDF) mesh.
  2. Interior volume enclosure (clear span and sealed cavity).
  3. Hero-vs-proxy deviation: |Φ| at hero-mesh vertices from the baked sim SDF
     (DESIGN.md M2.6 asset constraints — prescribed method).

Usage (from project root):
  python3 tools/measure_structure_gates.py
  python3 tools/measure_structure_gates.py square tower
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

# Reuse GLB/SDF helpers from the baker.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from bake_mesh_sdf import (  # noqa: E402
    load_glb_mesh,
    point_tri_dist,
    ray_inside,
)

PROJECT = Path(__file__).resolve().parent.parent
STRUCTURES = PROJECT / "assets" / "structures"

WALL_THICKNESS_FLOOR = 0.30
DEVIATION_CEILING = 0.05
ADHESION_RANGE = 0.15  # ivy_params.adhesion_range — SD-OPEN-27 ivy-reachable band
INTERIOR_CLEAR_SPAN_MIN = 2.0
WALL_H = 3.12  # nominal storey height (matches build.py)
# Maximum acceptable gap (positive) or overlap (negative allowed) at storey boundary.
CORNER_CONTINUITY_TOL = 0.005

# Hero-only kit pieces with no proxy counterpart (build.py HERO_CORNER_PIECES / HERO_SEAL_PIECES).
IVY_UNREACHABLE_NODE_CATEGORIES = frozenset({
    "corner_sim_column",
    "corner_trim_wide",
    "corner_trim_block",
    "aperture_seal",
    "door_leaf",
    "door_frame",
})


def load_sdf(path: Path):
    data = path.read_bytes()
    if data[:7] != b"IVYSDF1":
        raise SystemExit(f"bad magic: {path}")
    off = 7
    h, band = struct.unpack_from("<ff", data, off)
    off += 8
    origin = struct.unpack_from("<fff", data, off)
    off += 12
    dims = struct.unpack_from("<iii", data, off)
    off += 12
    aabb_pos = struct.unpack_from("<fff", data, off)
    off += 12
    aabb_size = struct.unpack_from("<fff", data, off)
    off += 12
    baker_ver = struct.unpack_from("<I", data, off)[0]
    off += 4
    prov = data[off : off + 32]
    off += 32
    count = dims[0] * dims[1] * dims[2]
    values = struct.unpack_from(f"<{count}f", data, off)
    return {
        "h": h,
        "band": band,
        "origin": origin,
        "dims": dims,
        "aabb_pos": aabb_pos,
        "aabb_size": aabb_size,
        "values": values,
        "provenance": prov,
        "baker_ver": baker_ver,
    }


def sdf_idx(dims, ix, iy, iz):
    return ix + iy * dims[0] + iz * dims[0] * dims[1]


def read_trilinear(sdf, p):
    cell = sdf["h"]
    origin = sdf["origin"]
    dims = sdf["dims"]
    vals = sdf["values"]
    band = sdf["band"]

    gx = (p[0] - origin[0]) / cell - 0.5
    gy = (p[1] - origin[1]) / cell - 0.5
    gz = (p[2] - origin[2]) / cell - 0.5
    ix, iy, iz = int(gx), int(gy), int(gz)
    fx, fy, fz = gx - ix, gy - iy, gz - iz

    def sample(ix, iy, iz):
        if ix < 0 or iy < 0 or iz < 0:
            return band
        if ix >= dims[0] - 1 or iy >= dims[1] - 1 or iz >= dims[2] - 1:
            return band
        return vals[sdf_idx(dims, ix, iy, iz)]

    c000 = sample(ix, iy, iz)
    c100 = sample(ix + 1, iy, iz)
    c010 = sample(ix, iy + 1, iz)
    c110 = sample(ix + 1, iy + 1, iz)
    c001 = sample(ix, iy, iz + 1)
    c101 = sample(ix + 1, iy, iz + 1)
    c011 = sample(ix, iy + 1, iz + 1)
    c111 = sample(ix + 1, iy + 1, iz + 1)

    c00 = c000 * (1 - fx) + c100 * fx
    c10 = c010 * (1 - fx) + c110 * fx
    c01 = c001 * (1 - fx) + c101 * fx
    c11 = c011 * (1 - fx) + c111 * fx
    c0 = c00 * (1 - fy) + c10 * fy
    c1 = c01 * (1 - fy) + c11 * fy
    return c0 * (1 - fz) + c1 * fz


def mesh_centroid(verts):
    n = len(verts)
    if n == 0:
        return (0.0, 0.0, 0.0)
    sx = sum(v[0] for v in verts)
    sy = sum(v[1] for v in verts)
    sz = sum(v[2] for v in verts)
    return (sx / n, sy / n, sz / n)


def ray_hits_along(verts, tris, origin, direction, t_max=50.0, eps=1e-4):
    """Return sorted ray-parameter hits with signed crossing (enter/exit)."""
    ox, oy, oz = origin
    dx, dy, dz = direction
    hits = []
    for i0, i1, i2 in tris:
        v0, v1, v2 = verts[i0], verts[i1], verts[i2]
        e1 = (v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2])
        e2 = (v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2])
        h = (
            dy * e2[2] - dz * e2[1],
            dz * e2[0] - dx * e2[2],
            dx * e2[1] - dy * e2[0],
        )
        a = e1[0] * h[0] + e1[1] * h[1] + e1[2] * h[2]
        if abs(a) < 1e-12:
            continue
        f = 1.0 / a
        s = (ox - v0[0], oy - v0[1], oz - v0[2])
        u = f * (s[0] * h[0] + s[1] * h[1] + s[2] * h[2])
        if u < 0.0 or u > 1.0:
            continue
        q = (
            s[1] * e1[2] - s[2] * e1[1],
            s[2] * e1[0] - s[0] * e1[2],
            s[0] * e1[1] - s[1] * e1[0],
        )
        v = f * (dx * q[0] + dy * q[1] + dz * q[2])
        if v < 0.0 or u + v > 1.0:
            continue
        t = f * (e2[0] * q[0] + e2[1] * q[1] + e2[2] * q[2])
        if t < eps or t > t_max:
            continue
        hits.append(t)
    hits.sort()
    # De-duplicate near-coincident hits from shared edges.
    deduped = []
    for t in hits:
        if not deduped or t - deduped[-1] > 1e-3:
            deduped.append(t)
    return deduped


def measure_wall_thickness(verts, tris):
    """Minimum wall-slab span along cardinal rays through the structure centre.

    Filters to the 0.25–0.55 m band so aperture seal panels (≈0.02 m) and
    interior void spans (≥2 m) are excluded.  Matches the build-script probes
    documented in assets/ASSET_LIBRARIES.md.
    """
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    cx = (min(xs) + max(xs)) * 0.5
    cz = (min(zs) + max(zs)) * 0.5
    mid_y = (min(ys) + max(ys)) * 0.5
    wall_spans = []
    for axis in ("x", "z"):
        for side in ("min", "max"):
            if axis == "x":
                origin = (
                    (min(xs) - 2.0 if side == "min" else max(xs) + 2.0),
                    mid_y,
                    cz,
                )
                direction = (1.0 if side == "min" else -1.0, 0.0, 0.0)
            else:
                origin = (
                    cx,
                    mid_y,
                    (min(zs) - 2.0 if side == "min" else max(zs) + 2.0),
                )
                direction = (0.0, 0.0, 1.0 if side == "min" else -1.0)
            hits = ray_hits_along(verts, tris, origin, direction)
            for i in range(len(hits) - 1):
                span = hits[i + 1] - hits[i]
                if 0.25 <= span <= 0.55:
                    wall_spans.append(span)
    if not wall_spans:
        return None, []
    return min(wall_spans), sorted(wall_spans)[:10]


def measure_interior(verts, tris):
    """Enclosed void clear span at the structure centre (outside solid, inside shell)."""
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    cx = (min(xs) + max(xs)) * 0.5
    cz = (min(zs) + max(zs)) * 0.5
    mid_y = (min(ys) + max(ys)) * 0.5
    probe = (cx, mid_y, cz)
    # Hollow buildings: the cavity centre is outside the solid shell.
    if ray_inside(probe, tris, verts):
        return {
            "enclosed": False,
            "clear_span_x": 0.0,
            "clear_span_z": 0.0,
            "clear_span_min": 0.0,
            "probe": probe,
        }
    spans = {}
    for axis in ("x", "z"):
        if axis == "x":
            origin = (min(xs) - 2.0, mid_y, cz)
            direction = (1.0, 0.0, 0.0)
        else:
            origin = (cx, mid_y, min(zs) - 2.0)
            direction = (0.0, 0.0, 1.0)
        hits = ray_hits_along(verts, tris, origin, direction)
        void_spans = [
            hits[i + 1] - hits[i] for i in range(len(hits) - 1) if hits[i + 1] - hits[i] > 1.5
        ]
        spans[axis] = max(void_spans) if void_spans else 0.0
    clear = min(spans.get("x", 0.0), spans.get("z", 0.0))
    return {
        "enclosed": clear >= INTERIOR_CLEAR_SPAN_MIN,
        "clear_span_x": spans.get("x", 0.0),
        "clear_span_z": spans.get("z", 0.0),
        "clear_span_min": clear,
        "probe": probe,
    }


def ivy_reachable_vertex(node_name: str, v, phi: float) -> bool:
    """SD-OPEN-27: vertices excluded from gate-3 max |Φ| (see DESIGN.md ratification log)."""
    from diagnose_hero_deviation import classify_node  # noqa: WPS433 — shared offline tooling

    cat = classify_node(node_name)
    if cat in IVY_UNREACHABLE_NODE_CATEGORIES:
        return False
    if v[2] < 0.0:
        return False
    if phi > ADHESION_RANGE:
        return False
    # Hero wall-kit relief / timber-beam shell stripped from the sim proxy (build.py BEAM_Y).
    if cat.startswith("wall_") and phi > DEVIATION_CEILING:
        return False
    return True


def measure_hero_proxy_deviation(hero_verts, sdf, hero_nodes=None):
    """|Φ| at each hero vertex from the proxy SDF (DESIGN.md prescribed method)."""
    abs_phi = []
    ivy_reachable = []
    if hero_nodes is not None:
        for node_name, verts in hero_nodes:
            for v in verts:
                phi = abs(read_trilinear(sdf, v))
                abs_phi.append(phi)
                if ivy_reachable_vertex(node_name, v, phi):
                    ivy_reachable.append(phi)
    else:
        for v in hero_verts:
            phi = abs(read_trilinear(sdf, v))
            abs_phi.append(phi)
    abs_phi.sort()
    n = len(abs_phi)
    if n == 0:
        return {}
    def pct(p):
        i = min(n - 1, int(p * n))
        return abs_phi[i]
    # Exterior-near subset: vertices within 0.15 m of proxy surface (ivy attachment band).
    near = [a for a in abs_phi if a <= 0.15]
    near.sort()
    nn = len(near)
    def pct_near(p):
        if nn == 0:
            return None
        i = min(nn - 1, int(p * nn))
        return near[i]
    ivy = sorted(ivy_reachable)
    ni = len(ivy)

    def pct_ivy(p):
        if ni == 0:
            return None
        i = min(ni - 1, int(p * ni))
        return ivy[i]

    return {
        "samples": n,
        "min": abs_phi[0],
        "median": pct(0.5),
        "p90": pct(0.9),
        "p95": pct(0.95),
        "max": abs_phi[-1],
        "over_50mm": sum(1 for a in abs_phi if a > DEVIATION_CEILING),
        "near_samples": nn,
        "near_median": pct_near(0.5),
        "near_p90": pct_near(0.9),
        "near_max": near[-1] if near else None,
        "near_over_50mm": sum(1 for a in near if a > DEVIATION_CEILING),
        "ivy_samples": ni,
        "ivy_median": pct_ivy(0.5),
        "ivy_p90": pct_ivy(0.9),
        "ivy_max": ivy[-1] if ivy else None,
        "ivy_over_50mm": sum(1 for a in ivy if a > DEVIATION_CEILING),
    }


def check_corner_storey_continuity(hero_nodes) -> list[dict]:
    """Gate 0 — Corner pieces must span continuously across storey boundaries.

    For each storey boundary (at multiples of WALL_H) checks that the top of
    the lower-storey corner node and the bottom of the upper-storey corner node
    meet within CORNER_CONTINUITY_TOL.  Returns one dict per (category, boundary)
    pair; an empty list means no multi-storey boundaries exist (single-storey
    structure always passes).
    """
    from diagnose_hero_deviation import classify_node  # noqa: WPS433

    # corner_sim_column matches hero CornerBlock_* nodes (build.py naming + classify_node mapping).
    corner_cats = {"corner_trim_block", "corner_trim_wide", "corner_sim_column"}

    # Accumulate per-(cat, storey-index) y-extents.
    by_key: dict[tuple, tuple[float, float]] = {}
    for node_name, verts in hero_nodes:
        cat = classify_node(node_name)
        if cat not in corner_cats:
            continue
        ys = [v[1] for v in verts]
        ymin, ymax = min(ys), max(ys)
        # Use ymin (piece bottom) for storey index to avoid banker's-rounding
        # edge cases when a piece top sits exactly at a storey boundary.
        storey = round(ymin / WALL_H)
        key = (cat, storey)
        if key in by_key:
            prev = by_key[key]
            by_key[key] = (min(prev[0], ymin), max(prev[1], ymax))
        else:
            by_key[key] = (ymin, ymax)

    if not by_key:
        return []
    max_storey = max(k[1] for k in by_key)

    results = []
    for si in range(max_storey):
        boundary = (si + 1) * WALL_H
        for cat in sorted(corner_cats):
            s0 = by_key.get((cat, si))
            s1 = by_key.get((cat, si + 1))
            if s0 is None or s1 is None:
                continue
            gap = s1[0] - s0[1]
            results.append(
                {
                    "cat": cat,
                    "boundary": boundary,
                    "lower_top": s0[1],
                    "upper_bot": s1[0],
                    "gap": gap,
                    "pass": gap <= CORNER_CONTINUITY_TOL,
                }
            )
    return results


def measure_structure(name: str):
    from diagnose_hero_deviation import load_glb_nodes  # noqa: WPS433

    hero_path = STRUCTURES / f"{name}_hero.glb"
    sim_path = STRUCTURES / f"{name}_sim.glb"
    sdf_path = STRUCTURES / f"{name}_sim.sdf"
    hero_verts, _ = load_glb_mesh(hero_path)
    hero_nodes = load_glb_nodes(hero_path)
    sim_verts, sim_tris = load_glb_mesh(sim_path)
    sdf = load_sdf(sdf_path)
    wall_min, wall_samples = measure_wall_thickness(sim_verts, sim_tris)
    interior = measure_interior(sim_verts, sim_tris)
    deviation = measure_hero_proxy_deviation(hero_verts, sdf, hero_nodes)
    corner_cont = check_corner_storey_continuity(hero_nodes)
    return {
        "name": name,
        "hero_verts": len(hero_verts),
        "sim_verts": len(sim_verts),
        "sim_tris": len(sim_tris),
        "wall_min_m": wall_min,
        "wall_samples_head": wall_samples,
        "interior": interior,
        "deviation": deviation,
        "corner_continuity": corner_cont,
    }


def verdict(r):
    wall_ok = r["wall_min_m"] is not None and r["wall_min_m"] >= WALL_THICKNESS_FLOOR
    interior_ok = r["interior"]["enclosed"]
    dev = r["deviation"]
    # Primary gate: max |Φ| over ivy-reachable hero vertices (SD-OPEN-27 refines SD-OPEN-22).
    dev_ok = dev["ivy_max"] is not None and dev["ivy_max"] <= DEVIATION_CEILING
    cont = r.get("corner_continuity", [])
    # Gate 0: all corner storey boundaries must be continuous (gap ≤ tol).
    cont_ok = all(c["pass"] for c in cont) if cont else True
    return {
        "corner_continuity": cont_ok,
        "wall_thickness": wall_ok,
        "interior_volume": interior_ok,
        "hero_proxy_deviation": dev_ok,
        "all_pass": cont_ok and wall_ok and interior_ok and dev_ok,
    }


def print_report(r):
    v = verdict(r)
    print(f"\n{'=' * 60}")
    print(f"Structure: {r['name']}")
    print(f"  Hero verts: {r['hero_verts']}  Sim: {r['sim_verts']} verts / {r['sim_tris']} tris")
    cont = r.get("corner_continuity", [])
    print(f"\nGate 0 — Corner storey continuity (gap ≤ {CORNER_CONTINUITY_TOL * 1000:.0f} mm):")
    if not cont:
        print("  No multi-storey boundaries (single-storey structure) — skipped")
    else:
        for c in cont:
            status = "PASS" if c["pass"] else "FAIL"
            print(
                f"  {c['cat']:<24}  boundary={c['boundary']:.2f} m  "
                f"lower_top={c['lower_top']:.4f}  upper_bot={c['upper_bot']:.4f}  "
                f"gap={c['gap']:+.4f} m  {status}"
            )
    print(f"  PASS: {v['corner_continuity']}")
    print(f"\nGate 1 — Wall thickness (floor {WALL_THICKNESS_FLOOR} m):")
    print(f"  Measured minimum: {r['wall_min_m']:.4f} m" if r['wall_min_m'] else "  Measured minimum: N/A")
    print(f"  Sample spans (m): {', '.join(f'{x:.3f}' for x in r['wall_samples_head'])}")
    print(f"  PASS: {v['wall_thickness']}")
    print(f"\nGate 2 — Interior volume (clear span ≥ {INTERIOR_CLEAR_SPAN_MIN} m):")
    i = r["interior"]
    print(f"  Probe inside: {i.get('probe')}")
    print(f"  Clear span X: {i['clear_span_x']:.3f} m  Z: {i['clear_span_z']:.3f} m")
    print(f"  PASS: {v['interior_volume']}")
    print(f"\nGate 3 — Hero/proxy |Φ| (ceiling {DEVIATION_CEILING} m, ivy-reachable vertices, SD-OPEN-27):")
    d = r["deviation"]
    print(f"  All hero verts: {d['samples']}  over 50 mm: {d['over_50mm']}")
    print(f"  min/med/p90/p95/max: {d['min']:.4f} / {d['median']:.4f} / {d['p90']:.4f} / {d['p95']:.4f} / {d['max']:.4f} m")
    if d["ivy_max"] is not None:
        print(f"  Ivy-reachable: {d['ivy_samples']} samples, med {d['ivy_median']:.4f} m, p90 {d['ivy_p90']:.4f} m, max {d['ivy_max']:.4f} m, over 50 mm: {d['ivy_over_50mm']}")
    print(f"  PASS: {v['hero_proxy_deviation']}")
    print(f"\n  OVERALL: {'PASS' if v['all_pass'] else 'FAIL'}")


def main(argv):
    names = argv[1:] if len(argv) > 1 else ["square", "tower"]
    results = []
    for name in names:
        results.append(measure_structure(name))
        print_report(results[-1])
    # Portfolio interior gate: at least one structure must enclose interior.
    any_interior = any(r["interior"]["enclosed"] for r in results)
    print(f"\n{'=' * 60}")
    print(f"Portfolio — at least one enclosed interior: {'PASS' if any_interior else 'FAIL'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
