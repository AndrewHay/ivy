"""Blender: hero + simulation buildings from Quaternius kit pieces.

This is the tracked source of every committed structure asset
(``assets/structures/{square,tower}_{hero,sim}.glb``). Per-structure geometry
is data, not code: the structures are described in ``structure_configs.json``
next to this file, and adding a structure means adding one config block there
and touching no engine code. The config schema is validated at load
(``validate_config``), so a misspelled or mistyped key fails immediately with a
clear message rather than being silently ignored.

Invocation
----------
  blender --background --python tools/build_structures.py -- \\
      <glTF dir> <out dir> [thickness] [--no-render] [--omit-seal <aperture_id>] [structure ...]

Positional / flag arguments (after the ``--`` separator Blender requires):
  <glTF dir>   Directory of the Quaternius kit glTF pieces. For a fresh clone,
               download the kit (see ``assets/ASSET_LIBRARIES.md`` for URL, tier
               and checksum), extract it, and point here at its ``glTF/``
               subdirectory, e.g.
               ``assets/_local/medieval_village_megakit/glTF``.
  <out dir>    Output directory for the exported GLBs and render PNGs. Pass
               ``assets/structures`` to write the in-game assets directly, or a
               scratch dir to review before promoting.
  [thickness]  Optional positional float overriding the 0.45 m sim wall target
               (``TARGET_T``). Omit for the ratified 0.45 m.
  --no-render  Skip the Cycles review renders (much faster; GLB output is
               identical either way — renders never mutate the exported meshes).
  --omit-seal <id>  Build with one aperture seal panel omitted, for the
               falsifiability check (that panel then reads UNSEALED).
  [structure]  One or more structure names to build (``square`` / ``tower``);
               default is every structure in ``structure_configs.json``.

After building, re-bake the SDFs and re-measure the Director gates:
  python3 tools/bake_mesh_sdf.py assets/structures/square_sim.glb assets/structures/square_sim.sdf
  python3 tools/bake_mesh_sdf.py assets/structures/tower_sim.glb  assets/structures/tower_sim.sdf
  python3 tools/measure_structure_gates.py square tower

Verified against Blender 4.2.1 LTS (macOS, ``/Applications/Blender.app``). Hero
renders run before sim clay assignment (assign_material clears kit slots in
Cycles). All kit pieces are pre-solidified / pre-imported before assembly so the
sim build never runs bmesh bridging after Cycles renders.
"""

import json
import math
import os
import sys
from collections import defaultdict
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
KIT = argv[0]
OUT_DIR = argv[1]
TARGET_T = 0.45
structures = ["square", "tower"]
NO_RENDER = False
OMIT_SEAL = None
if len(argv) > 2:
    rest = []
    i = 0
    while i < len(argv[2:]):
        a = argv[2 + i]
        if a == "--no-render":
            NO_RENDER = True
        elif a == "--omit-seal" and i + 1 < len(argv[2:]):
            OMIT_SEAL = argv[3 + i]
            i += 1
        else:
            rest.append(a)
        i += 1
    if rest and rest[0].replace(".", "", 1).isdigit():
        TARGET_T = float(rest[0])
        rest = rest[1:]
    if rest:
        structures = rest

NATIVE_T = 0.20
EXT_OFFSET = 0.09
BEAM_Y = 0.21
SHIFT = TARGET_T - NATIVE_T
WALL_H = 3.12
MODULE = 2.0
CAP = 0.30
END_OVERLAP = TARGET_T
HERO_CORNER_PIECES = ("Corner_ExteriorWide_Brick", "Corner_Exterior_Brick")
HERO_SEAL_PIECES = ("Door_2_Round", "DoorFrame_Round_Brick")
GLASS_T = 0.02

APERTURE_SPECS = {
    "door": {"x0": -0.625, "x1": 0.625, "z0": 0.0, "z1": 2.475},
    "thin_win": {"x0": -0.30, "x1": 0.30, "z0": 1.05, "z1": 2.525},
    "wide_win": {"x0": -0.35, "x1": 0.55, "z0": 1.05, "z1": 2.725},
}

# ── Structure config schema ─────────────────────────────────────────────────
# Per-structure geometry lives in structure_configs.json (data, not code).
# The schema is enforced at load so a typo fails immediately: unknown keys are
# rejected (a mistyped "intermediate_flor" no longer silently disables the
# floor), required keys must be present, and every value is type-checked.
CONFIGS_PATH = Path(__file__).resolve().parent / "structure_configs.json"

# key -> accepted python types. Optional keys carry the same defaults the engine
# already assumed via cfg.get(): roof_half -> derived envelope_half,
# intermediate_floor -> absent/False, hero_end_overlap -> False.
_REQUIRED_KEYS = {
    "name": (str,),
    "half": (int, float),
    "storeys": (int,),
    "module_offsets": (list,),
    "storey_sides": (list,),
    "scene_offset": (list,),
}
_OPTIONAL_KEYS = {
    "roof_half": (int, float),
    "intermediate_floor": (bool,),
    "hero_end_overlap": (bool,),
    "corner_chamfer": (int, float),
}


def validate_config(name, cfg):
    """Raise ValueError on any schema violation, so bad config fails at load."""
    where = f"structure config '{name}'"
    if not isinstance(cfg, dict):
        raise ValueError(f"{where}: must be a JSON object, got {type(cfg).__name__}")
    allowed = set(_REQUIRED_KEYS) | set(_OPTIONAL_KEYS)
    unknown = set(cfg) - allowed
    if unknown:
        raise ValueError(
            f"{where}: unknown key(s) {sorted(unknown)} — likely a typo. "
            f"Allowed keys: {sorted(allowed)}"
        )
    for key, types in _REQUIRED_KEYS.items():
        if key not in cfg:
            raise ValueError(f"{where}: missing required key '{key}'")
        # bool is a subclass of int; guard so a stray True/False is caught.
        if isinstance(cfg[key], bool) or not isinstance(cfg[key], types):
            raise ValueError(
                f"{where}: key '{key}' must be {', '.join(t.__name__ for t in types)}, "
                f"got {type(cfg[key]).__name__}"
            )
    for key, types in _OPTIONAL_KEYS.items():
        if key in cfg and not isinstance(cfg[key], types):
            raise ValueError(
                f"{where}: key '{key}' must be {', '.join(t.__name__ for t in types)}, "
                f"got {type(cfg[key]).__name__}"
            )
    if cfg["name"] != name:
        raise ValueError(f"{where}: 'name' is '{cfg['name']}', expected '{name}'")
    if cfg["storeys"] < 1:
        raise ValueError(f"{where}: 'storeys' must be >= 1")
    if len(cfg["storey_sides"]) != cfg["storeys"]:
        raise ValueError(
            f"{where}: 'storey_sides' has {len(cfg['storey_sides'])} storeys "
            f"but 'storeys' is {cfg['storeys']}"
        )
    if len(cfg["scene_offset"]) != 3 or not all(
        isinstance(v, (int, float)) and not isinstance(v, bool) for v in cfg["scene_offset"]
    ):
        raise ValueError(f"{where}: 'scene_offset' must be [x, y, z] numbers")
    if not cfg["module_offsets"] or not all(
        isinstance(v, (int, float)) and not isinstance(v, bool) for v in cfg["module_offsets"]
    ):
        raise ValueError(f"{where}: 'module_offsets' must be a non-empty list of numbers")
    for si, sides in enumerate(cfg["storey_sides"]):
        if not isinstance(sides, list):
            raise ValueError(f"{where}: storey {si} must be a list of [yaw, [pieces]] entries")
        for entry in sides:
            if (not isinstance(entry, list) or len(entry) != 2
                    or not isinstance(entry[0], (int, float)) or isinstance(entry[0], bool)
                    or not isinstance(entry[1], list)
                    or not all(isinstance(p, str) for p in entry[1])):
                raise ValueError(
                    f"{where}: storey {si} entry {entry!r} must be [yaw:number, [piece_name:str, ...]]"
                )
            if len(entry[1]) != len(cfg["module_offsets"]):
                raise ValueError(
                    f"{where}: storey {si} side at yaw {entry[0]} has {len(entry[1])} pieces "
                    f"but 'module_offsets' defines {len(cfg['module_offsets'])} bays"
                )


def load_structure_configs(path=CONFIGS_PATH):
    """Load, validate, and normalise the structure config data file."""
    with open(path, "r") as fh:
        raw = json.load(fh)
    if not isinstance(raw, dict) or not raw:
        raise ValueError(f"{path}: expected a non-empty object of named structure configs")
    configs = {}
    for name, cfg in raw.items():
        validate_config(name, cfg)
        cfg = dict(cfg)
        # JSON has no tuple/Vector; the engine treats scene_offset as a Vector
        # and unpacks each storey-side entry as (yaw, names).
        cfg["scene_offset"] = Vector(tuple(float(v) for v in cfg["scene_offset"]))
        configs[name] = cfg
    return configs


CONFIGS = load_structure_configs()
RENDER_DIR = os.path.join(OUT_DIR, "renders")
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(RENDER_DIR, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)

scene = bpy.context.scene
scene.render.resolution_x = 1100
scene.render.resolution_y = 760
scene.view_settings.view_transform = "AgX"
_cycles_ready = False


def ensure_cycles():
    global _cycles_ready
    if _cycles_ready:
        return
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    _cycles_ready = True

world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.30, 0.42, 0.62, 1.0)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.4

sun_data = bpy.data.lights.new("Sun", type="SUN")
sun_data.energy, sun_data.angle = 4.0, math.radians(1.5)
sun = bpy.data.objects.new("Sun", sun_data)
bpy.context.collection.objects.link(sun)
sun.rotation_euler = (math.radians(52.0), 0.0, math.radians(35.0))

gm = bpy.data.materials.new("Ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.22, 0.24, 0.17, 1.0)
bpy.ops.mesh.primitive_plane_add(size=80.0, location=(0, 0, 0))
bpy.context.active_object.data.materials.append(gm)

cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
bpy.context.collection.objects.link(cam)
scene.camera = cam
_shot = [0]


def render(name, loc, target, lens=35.0, ortho_scale=None):
    ensure_cycles()
    cam_data.lens = lens
    if ortho_scale is not None:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho_scale
    else:
        cam_data.type = "PERSP"
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    _shot[0] += 1
    scene.render.filepath = os.path.join(RENDER_DIR, f"{_shot[0]:02d}_{name}.png")
    bpy.ops.render.render(write_still=True)
    print(f"RENDER {scene.render.filepath}")


def parts_bounds(parts):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for obj in parts:
        eval_obj = obj.evaluated_get(depsgraph)
        for corner in eval_obj.bound_box:
            wc = eval_obj.matrix_world @ Vector(corner)
            mins = Vector((min(mins[i], wc[i]) for i in range(3)))
            maxs = Vector((max(maxs[i], wc[i]) for i in range(3)))
    return mins, maxs


def exterior_probe_t(objects, origin, direction, reach=20.0):
    best_t, best_loc = None, None
    o = Vector(origin)
    d = Vector(direction).normalized()
    for obj in objects:
        hit, loc, _, _ = ray_cast_world(obj, o, d, distance=reach)
        if hit:
            t = (loc - o).length
            if best_t is None or t < best_t:
                best_t, best_loc = t, loc
    return best_t, best_loc


def frame_exterior(parts, d, wo, view=(1.0, -1.0, 0.65), margin=1.35, lens=35.0):
    """Return (camera_loc, look_target) framing parts with margin."""
    mins, maxs = parts_bounds(parts)
    dims = maxs - mins
    if min(dims.x, dims.y, dims.z) < 0.5:
        total_h = d["total_h"] + CAP
        center = wo + Vector((0, 0, total_h * 0.5))
        extent = max(2 * d["envelope_half"], total_h)
    else:
        center = (mins + maxs) / 2.0
        extent = max(dims.x, dims.y, dims.z)
    sensor = 36.0
    fov = 2.0 * math.atan(sensor / (2.0 * lens))
    dist = (extent * 0.5 * margin) / math.tan(fov / 2.0)
    v = Vector(view).normalized()
    return center + v * dist, center


def frame_plan(parts, d, wo, margin=1.20):
    mins, maxs = parts_bounds(parts)
    dims = maxs - mins
    if min(dims.x, dims.y) < 0.5:
        span = 2 * d["envelope_half"] * margin
        center = wo + Vector((0, 0, d["total_h"] * 0.5))
    else:
        center = (mins + maxs) / 2.0
        span = max(dims.x, dims.y) * margin
    return center + Vector((0, 0, max(span, d["total_h"]) + 3.0)), center, span


def frame_interior(parts, z_floor, look_yaw_deg, inset=0.55, lens=24.0):
    """Camera inside upper storey looking toward a window on look_yaw_deg side."""
    mins, maxs = parts_bounds(parts)
    center = (mins + maxs) / 2.0
    n, _tang = side_vectors(look_yaw_deg)
    eye = center - n * inset
    eye.z = z_floor + 1.55
    target = eye + n * 4.0
    target.z = eye.z
    return eye, target, lens


def cfg_derived(cfg):
    half = cfg["half"]
    corner_xy = half - EXT_OFFSET + END_OVERLAP / 2.0
    corner_size = END_OVERLAP + TARGET_T
    envelope_half = corner_xy + corner_size / 2.0
    wall_exterior = half - EXT_OFFSET
    interior_half = wall_exterior - TARGET_T + 0.02
    roof_half = cfg.get("roof_half", envelope_half)
    storeys = cfg["storeys"]
    return {
        "half": half,
        "corner_xy": corner_xy,
        "corner_size": corner_size,
        "envelope_half": envelope_half,
        "interior_half": interior_half,
        "roof_half": roof_half,
        "wall_exterior": wall_exterior,
        "total_h": storeys * WALL_H,
        "storeys": storeys,
        "corner_locs": {
            0.0: Vector((half, -half, 0.0)),
            90.0: Vector((half, half, 0.0)),
            180.0: Vector((-half, half, 0.0)),
            270.0: Vector((-half, -half, 0.0)),
        },
        "corner_centers": [
            (corner_xy, -corner_xy),
            (corner_xy, corner_xy),
            (-corner_xy, corner_xy),
            (-corner_xy, -corner_xy),
        ],
    }


def side_vectors(yaw_deg):
    yr = math.radians(yaw_deg)
    return Vector((math.sin(yr), -math.cos(yr), 0.0)), Vector((math.cos(yr), math.sin(yr), 0.0))


def apply_transform(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def ray_cast_world(obj, origin, direction, distance=20.0):
    matrix_inv = obj.matrix_world.inverted()
    origin_local = matrix_inv @ Vector(origin)
    direction_local = (matrix_inv.to_3x3() @ Vector(direction)).normalized()
    hit, loc, normal, index = obj.ray_cast(origin_local, direction_local, distance=distance)
    if hit:
        loc = obj.matrix_world @ loc
    return hit, loc, normal, index


def import_kit(name):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=f"{KIT}/{name}.gltf")
    new = [o for o in bpy.context.scene.objects if o not in before and o.type == "MESH"]
    if len(new) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for o in new:
            o.select_set(True)
        bpy.context.view_layer.objects.active = new[0]
        bpy.ops.object.join()
        new = [bpy.context.view_layer.objects.active]
    return new[0]


_solid = {}
_hero_data = {}


def loops_of(bm):
    bnd = [e for e in bm.edges if len(e.link_faces) == 1]
    by_vert = defaultdict(list)
    for e in bnd:
        for v in e.verts:
            by_vert[v].append(e)
    seen, groups = set(), []
    for e in bnd:
        if e in seen:
            continue
        stack, comp = [e], []
        seen.add(e)
        while stack:
            cur = stack.pop()
            comp.append(cur)
            for v in cur.verts:
                for nxt in by_vert[v]:
                    if nxt not in seen:
                        seen.add(nxt)
                        stack.append(nxt)
        groups.append(comp)
    return groups


def loop_box(comp):
    vs = {v for e in comp for v in e.verts}
    ys = [v.co.y for v in vs]
    return (sum(ys) / len(ys),
            (min(v.co.x for v in vs), max(v.co.x for v in vs),
             min(v.co.z for v in vs), max(v.co.z for v in vs)))


def solid_data(name):
    if name in _solid:
        return _solid[name]
    src = import_kit(name)
    bm = bmesh.new()
    bm.from_mesh(src.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    beam = [f for f in bm.faces if any(v.co.y > BEAM_Y for v in f.verts)]
    if beam:
        bmesh.ops.delete(bm, geom=beam, context="FACES")
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    for v in bm.verts:
        if v.co.y > NATIVE_T - 1e-3:
            v.co.y += SHIFT
    outer, inner = [], []
    for g in loops_of(bm):
        y, box = loop_box(g)
        (outer if y < NATIVE_T * 0.5 else inner).append((box, g))
    used, bridged = set(), 0
    for box, og in outer:
        best, bd = None, 1e9
        for j, (ibox, ig) in enumerate(inner):
            if j in used:
                continue
            d0 = sum(abs(a - b) for a, b in zip(box, ibox))
            if d0 < bd:
                best, bd = j, d0
        if best is not None and bd < 0.10:
            used.add(best)
            bmesh.ops.bridge_loops(bm, edges=og + inner[best][1])
            bridged += 1
    left = [e for e in bm.edges if len(e.link_faces) == 1]
    if left:
        bmesh.ops.holes_fill(bm, edges=left, sides=0)
    left = [e for e in bm.edges if len(e.link_faces) == 1]
    nm = [e for e in bm.edges if len(e.link_faces) > 2]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    print(f"  {name:38s} bridged {bridged}  boundary {len(left):3d}  nonmanifold {len(nm):3d}  "
          f"faces {len(bm.faces):4d}  {'CLOSED' if not left and not nm else 'OPEN'}")
    bm.to_mesh(src.data)
    src.data.update()
    bm.free()
    _solid[name] = src.data
    bpy.data.objects.remove(src, do_unlink=True)
    return _solid[name]


def hero_data(name):
    if name not in _hero_data:
        src = import_kit(name)
        _hero_data[name] = src.data
        bpy.data.objects.remove(src, do_unlink=True)
    return _hero_data[name]


def assign_material(obj, material):
    mesh = obj.data
    mesh.materials.clear()
    mesh.materials.append(material)
    for poly in mesh.polygons:
        poly.material_index = 0


def set_collection(col):
    layer = bpy.context.view_layer.layer_collection
    for c in col.name.split("_"):
        pass
    bpy.context.view_layer.active_layer_collection = (
        bpy.context.view_layer.layer_collection
        .children["Hero" if col.name.startswith("Hero") else "Simulation"]
        .children[col.name]
    )


def place_wall_run(names, yaw_deg, collection, data_fn, prefix, cfg, d, z_base=0.0,
                   end_overlap=True, world_offset=Vector((0, 0, 0))):
    n, tang = side_vectors(yaw_deg)
    yr = math.radians(yaw_deg)
    half = d["half"]
    placed = []
    offsets = cfg["module_offsets"]
    ext_scale = (MODULE + END_OVERLAP) / MODULE
    for i, nm in enumerate(names):
        obj = bpy.data.objects.new(f"{prefix}{nm}_{int(yaw_deg)}_{i}", data_fn(nm).copy())
        collection.objects.link(obj)
        obj.rotation_euler = (0.0, 0.0, yr)
        loc = n * (half - EXT_OFFSET) + tang * offsets[i]
        loc.z = z_base
        sx = 1.0
        straight = "Straight" in nm
        if end_overlap and straight and i == 0:
            sx = ext_scale
            loc -= tang * (END_OVERLAP / 2.0)
        elif end_overlap and straight and i == len(names) - 1:
            sx = ext_scale
            loc += tang * (END_OVERLAP / 2.0)
        if sx != 1.0:
            obj.scale = (sx, 1.0, 1.0)
        obj.location = loc + world_offset
        placed.append(obj)
    return placed


def place_corner_trim(yaw_deg, collection, d, prefix, z_base=0.0, world_offset=Vector((0, 0, 0))):
    nm = "Corner_ExteriorWide_Brick"
    obj = bpy.data.objects.new(f"{prefix}{nm}_{int(yaw_deg)}_{int(z_base)}", hero_data(nm).copy())
    collection.objects.link(obj)
    obj.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    zmin, zmax = piece_zextent(nm)
    piece_h = zmax - zmin
    sz = WALL_H / piece_h
    loc = d["corner_locs"][yaw_deg].copy()
    # Shift so the piece's native bottom sits exactly at z_base.
    loc.z = z_base - zmin * sz
    obj.location = loc + world_offset
    obj.scale = (1.0, 1.0, sz)
    return obj


def hero_corner_block(name, xy, collection, d, z_base=0.0, world_offset=Vector((0, 0, 0))):
    cx, cy = xy
    sx = d["corner_size"] / 0.55
    zmin, zmax = piece_zextent("Corner_Exterior_Brick")
    piece_h = zmax - zmin
    sz = WALL_H / piece_h
    obj = bpy.data.objects.new(name, hero_data("Corner_Exterior_Brick").copy())
    collection.objects.link(obj)
    # Shift so the piece's native bottom sits exactly at z_base.
    obj.location = Vector((cx, cy, z_base - zmin * sz)) + world_offset
    obj.scale = (sx, sx, sz)
    return obj


def corner_column(name, xy, collection, d, z0, z1, material=None, world_offset=Vector((0, 0, 0)), chamfer=0.0):
    cx, cy = xy
    s = d["corner_size"] / 2.0
    root = collection.name.split("_")[0]
    parent_name = "Hero" if root == "Hero" else "Simulation"
    layer = bpy.context.view_layer.active_layer_collection
    bpy.context.view_layer.active_layer_collection = (
        bpy.context.view_layer.layer_collection.children[parent_name].children[collection.name]
    )

    if chamfer > 0.0:
        c = min(chamfer, s - 1e-4)
        verts_2d = [
            ( s,      s - c),
            ( s - c,  s),
            (-s + c,  s),
            (-s,      s - c),
            (-s,     -s + c),
            (-s + c, -s),
            ( s - c, -s),
            ( s,     -s + c),
        ]
        wx = cx + world_offset.x
        wy = cy + world_offset.y
        mesh_data = bpy.data.meshes.new(name + "_mesh")
        bm = bmesh.new()
        bot = [bm.verts.new((wx + x, wy + y, z0)) for x, y in verts_2d]
        top = [bm.verts.new((wx + x, wy + y, z1)) for x, y in verts_2d]
        n = len(verts_2d)
        bm.faces.new(list(reversed(bot)))
        bm.faces.new(top)
        for i in range(n):
            bm.faces.new([bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh_data)
        bm.free()
        o = bpy.data.objects.new(name, mesh_data)
        collection.objects.link(o)
    else:
        h = z1 - z0
        cz = (z0 + z1) / 2.0
        bpy.ops.mesh.primitive_cube_add(
            size=1.0,
            location=(cx + world_offset.x, cy + world_offset.y, cz + world_offset.z),
        )
        o = bpy.context.active_object
        o.name = name
        o.scale = (d["corner_size"], d["corner_size"], h)

    bpy.context.view_layer.active_layer_collection = layer
    if material is not None:
        assign_material(o, material)
    return o


def solid_box(name, z0, z1, half, collection, material=None, world_offset=Vector((0, 0, 0))):
    root = collection.name.split("_")[0]
    parent_name = "Hero" if root == "Hero" else "Simulation"
    layer = bpy.context.view_layer.active_layer_collection
    bpy.context.view_layer.active_layer_collection = (
        bpy.context.view_layer.layer_collection.children[parent_name].children[collection.name]
    )
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(world_offset.x, world_offset.y, (z0 + z1) / 2.0 + world_offset.z))
    bpy.context.view_layer.active_layer_collection = layer
    o = bpy.context.active_object
    o.name = name
    o.scale = (2 * half, 2 * half, z1 - z0)
    apply_transform(o)
    if material is not None:
        assign_material(o, material)
    return o


def wall_world_matrix(yaw_deg, wall_loc, world_offset, z_base=0.0):
    yr = math.radians(yaw_deg)
    loc = wall_loc.copy()
    loc.z = z_base
    return Matrix.Translation(loc + world_offset) @ Matrix.Rotation(yr, 4, "Z")


_piece_centre = {}


def piece_zextent(name):
    """Return (zmin, zmax) of the native kit piece in local space."""
    key = f"kit:{name}:zextent"
    if key not in _piece_centre:
        data = hero_data(name)
        zs = [v.co.z for v in data.vertices]
        _piece_centre[key] = (min(zs), max(zs))
    return _piece_centre[key]


def piece_centre(name):
    key = f"kit:{name}"
    if key not in _piece_centre:
        data = hero_data(name)
        mins = Vector((1e9, 1e9, 1e9))
        maxs = Vector((-1e9, -1e9, -1e9))
        for vert in data.vertices:
            v = vert.co
            mins = Vector((min(mins[i], v[i]) for i in range(3)))
            maxs = Vector((max(maxs[i], v[i]) for i in range(3)))
        _piece_centre[key] = (mins + maxs) / 2.0
    return _piece_centre[key]


def opening_center_local(ap):
    spec = ap["spec"]
    return Vector((
        (spec["x0"] + spec["x1"]) / 2.0,
        0.0,
        (spec["z0"] + spec["z1"]) / 2.0,
    ))


def enumerate_apertures(cfg, d):
    apertures = []
    offsets = cfg["module_offsets"]
    wall_r = d["wall_exterior"]
    for si, sides in enumerate(cfg["storey_sides"]):
        z_base = si * WALL_H
        tag = "ground" if si == 0 else "upper"
        for yaw, names in sides:
            n, tang = side_vectors(yaw)
            side = {0.0: "S", 90.0: "E", 180.0: "N", 270.0: "W"}[yaw]
            for i, nm in enumerate(names):
                if "Door" in nm:
                    kind = "door"
                elif "Window" in nm:
                    kind = "thin_win" if "Thin" in nm else "wide_win"
                else:
                    continue
                aid = f"{cfg['name']}_{tag}_{kind}_{side}"
                apertures.append({
                    "id": aid,
                    "kind": kind,
                    "tag": tag,
                    "side": side,
                    "yaw": yaw,
                    "wall_loc": n * wall_r + tang * offsets[i],
                    "z_base": z_base,
                    "spec": APERTURE_SPECS[kind],
                    "label": f"{tag} {'door' if kind == 'door' else 'win'} {side}",
                })
    return apertures


def place_kit_seal(ap, collection, prefix, world_offset, name, suffix, local_off, material=None):
    obj = bpy.data.objects.new(f"{prefix}Seal_{ap['id']}_{suffix}", hero_data(name).copy())
    collection.objects.link(obj)
    obj.matrix_world = wall_world_matrix(ap["yaw"], ap["wall_loc"], world_offset, ap["z_base"]) @ Matrix.Translation(local_off)
    if material is not None:
        assign_material(obj, material)
    return obj


def piece_y_min(name):
    key = f"kit:{name}:ymin"
    if key not in _piece_centre:
        data = hero_data(name)
        _piece_centre[key] = min(v.co.y for v in data.vertices)
    return _piece_centre[key]


def place_hero_seals(ap, hero_col, prefix, world_offset, glass_mat):
    oc = opening_center_local(ap)
    parts = []
    if ap["kind"] == "door":
        fc = piece_centre("DoorFrame_Round_Brick")
        dc = piece_centre("Door_2_Round")
        frame_off = Vector((oc.x - fc.x, -piece_y_min("DoorFrame_Round_Brick"), oc.z - fc.z))
        door_off = Vector((oc.x - dc.x, -piece_y_min("Door_2_Round"), oc.z - dc.z))
        parts.append(place_kit_seal(ap, hero_col, prefix, world_offset,
                                    "DoorFrame_Round_Brick", "frame", frame_off))
        parts.append(place_kit_seal(ap, hero_col, prefix, world_offset,
                                    "Door_2_Round", "door", door_off))
    else:
        spec = ap["spec"]
        width = spec["x1"] - spec["x0"]
        height = spec["z1"] - spec["z0"]
        glass_off = Vector((
            (spec["x0"] + spec["x1"]) / 2.0,
            GLASS_T / 2.0,
            (spec["z0"] + spec["z1"]) / 2.0,
        ))
        root = hero_col.name.split("_")[0]
        parent_name = "Hero" if root == "Hero" else "Simulation"
        layer = bpy.context.view_layer.active_layer_collection
        bpy.context.view_layer.active_layer_collection = (
            bpy.context.view_layer.layer_collection.children[parent_name].children[hero_col.name]
        )
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        bpy.context.view_layer.active_layer_collection = layer
        obj = bpy.context.active_object
        obj.name = f"{prefix}Seal_{ap['id']}_glass"
        obj.scale = (width, GLASS_T, height)
        apply_transform(obj)
        obj.matrix_world = wall_world_matrix(ap["yaw"], ap["wall_loc"], world_offset, ap["z_base"]) @ Matrix.Translation(glass_off)
        assign_material(obj, glass_mat)
        parts.append(obj)
    return parts


def place_sim_panel(ap, sim_col, prefix, world_offset, clay, omit=False):
    if omit:
        return None
    spec = ap["spec"]
    width = spec["x1"] - spec["x0"]
    height = spec["z1"] - spec["z0"]
    centre_local = Vector((
        (spec["x0"] + spec["x1"]) / 2.0,
        TARGET_T / 2.0,
        (spec["z0"] + spec["z1"]) / 2.0,
    ))
    root = sim_col.name.split("_")[0]
    parent_name = "Hero" if root == "Hero" else "Simulation"
    layer = bpy.context.view_layer.active_layer_collection
    bpy.context.view_layer.active_layer_collection = (
        bpy.context.view_layer.layer_collection.children[parent_name].children[sim_col.name]
    )
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    bpy.context.view_layer.active_layer_collection = layer
    obj = bpy.context.active_object
    obj.name = f"{prefix}Panel_{ap['id']}"
    obj.scale = (width, TARGET_T, height)
    apply_transform(obj)
    obj.matrix_world = wall_world_matrix(ap["yaw"], ap["wall_loc"], world_offset, ap["z_base"]) @ Matrix.Translation(centre_local)
    assign_material(obj, clay)
    return obj


def assemble_hero(cfg, hero_col, hero_roof_mat, glass_mat, world_offset):
    d = cfg_derived(cfg)
    name = cfg["name"]
    prefix = f"{name}_hero_"
    parts = []
    for si, sides in enumerate(cfg["storey_sides"]):
        z_base = si * WALL_H
        for yaw, names in sides:
            parts += place_wall_run(
                names, yaw, hero_col, hero_data, prefix, cfg, d, z_base=z_base,
                end_overlap=cfg.get("hero_end_overlap", False), world_offset=world_offset,
            )
    for si in range(cfg["storeys"]):
        z_base = si * WALL_H
        for yaw in (0.0, 90.0, 180.0, 270.0):
            parts.append(place_corner_trim(yaw, hero_col, d, prefix, z_base, world_offset))
        for i, xy in enumerate(d["corner_centers"]):
            parts.append(hero_corner_block(f"{prefix}CornerBlock_{si}_{i}", xy, hero_col, d, z_base, world_offset))
    total_h = d["total_h"]
    parts.append(solid_box(f"{prefix}RoofCap", total_h - 0.05, total_h + CAP, d["roof_half"],
                           hero_col, hero_roof_mat, world_offset))
    if cfg.get("intermediate_floor"):
        parts.append(solid_box(f"{prefix}MidFloorSlab", WALL_H - 0.10, WALL_H + 0.02,
                               d["interior_half"], hero_col, hero_roof_mat, world_offset))
    apertures = enumerate_apertures(cfg, d)
    for ap in apertures:
        parts += place_hero_seals(ap, hero_col, prefix, world_offset, glass_mat)
    return parts, d, apertures


def assemble_sim(cfg, sim_col, clay, world_offset, omit_seal=None):
    d = cfg_derived(cfg)
    name = cfg["name"]
    prefix = f"{name}_sim_"
    print(f"\n[{name}] assembling simulation mesh", flush=True)
    parts = []
    for si, sides in enumerate(cfg["storey_sides"]):
        z_base = si * WALL_H
        for yaw, names in sides:
            parts += place_wall_run(
                names, yaw, sim_col, solid_data, prefix, cfg, d, z_base=z_base,
                end_overlap=False, world_offset=world_offset,
            )
    for obj in parts:
        assign_material(obj, clay)
    chamfer = cfg.get("corner_chamfer", 0.0)
    for i, xy in enumerate(d["corner_centers"]):
        parts.append(corner_column(f"{prefix}CornerColumn_{i}", xy, sim_col, d, 0.0, d["total_h"], clay, world_offset, chamfer=chamfer))
    parts.append(solid_box(f"{prefix}FloorSlab", -CAP, 0.05, d["envelope_half"], sim_col, clay, world_offset))
    if cfg.get("intermediate_floor"):
        parts.append(solid_box(f"{prefix}MidFloorSlab", WALL_H - 0.10, WALL_H + 0.02,
                               d["interior_half"], sim_col, clay, world_offset))
    parts.append(solid_box(f"{prefix}RoofCap", d["total_h"] - 0.05, d["total_h"] + CAP,
                           d["roof_half"], sim_col, clay, world_offset))
    apertures = enumerate_apertures(cfg, d)
    for ap in apertures:
        panel = place_sim_panel(ap, sim_col, prefix, world_offset, clay, omit=(ap["id"] == omit_seal))
        if panel is not None:
            parts.append(panel)
    return parts, d, apertures


def shell_objects(parts):
    """Every surface ivy can meet: walls plus the door leaves and glazing that seal them.

    Excluding the seals let rays pass through a sealed doorway and pair against the far
    wall's interior face, reporting a deviation on a route the geometry no longer has.
    """
    return [
        o for o in parts
        if "Wall_UnevenBrick" in o.name or "_Seal_" in o.name or "_Panel_" in o.name
    ]


def mesh_stats(objects, label):
    total_tris = total_bnd = total_nmf = 0
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for obj in objects:
        apply_transform(obj)
        for corner in obj.bound_box:
            wc = obj.matrix_world @ Vector(corner)
            mins = Vector((min(mins[i], wc[i]) for i in range(3)))
            maxs = Vector((max(maxs[i], wc[i]) for i in range(3)))
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        total_tris += len(bm.faces)
        total_bnd += sum(1 for e in bm.edges if len(e.link_faces) == 1)
        total_nmf += sum(1 for e in bm.edges if len(e.link_faces) > 2)
        bm.free()
    dims = maxs - mins
    print(f"{label:22s} objs {len(objects):2d}  tris {total_tris:6d}  boundary {total_bnd:5d}  "
          f"nonmanifold {total_nmf:5d}  bbox {dims.x:5.2f} x {dims.y:5.2f} x {dims.z:5.2f}")
    return mins, maxs


def ray_crossings(objects, origin, direction, reach=20.0, max_hits=24):
    """March ray through sim/hero solids; return hit locations."""
    hits = []
    o = Vector(origin)
    d = Vector(direction).normalized()
    t = 0.0
    eps = 1e-4
    while t < reach and len(hits) < max_hits:
        best_t = None
        for obj in objects:
            hit, loc, _, _ = ray_cast_world(obj, o + d * (t + eps), d, distance=reach - t)
            if hit:
                dist = (loc - (o + d * (t + eps))).length + eps
                if best_t is None or dist < best_t:
                    best_t = dist
        if best_t is None:
            break
        t += best_t
        hits.append(o + d * t)
    return hits


def exterior_probe(objects, origin, direction, reach=20.0):
    best = None
    for obj in objects:
        hit, loc, _, _ = ray_cast_world(obj, Vector(origin), Vector(direction), distance=reach)
        if hit and (best is None or (loc - Vector(origin)).length < (best - Vector(origin)).length):
            best = loc
    return best


def hit_on_structure(loc, wo, d, tol_xy=0.35, tol_z=0.25):
    """True when loc is on the structure under test (not ground / neighbour)."""
    if loc.z < tol_z:
        return False
    lx, ly = loc.x - wo.x, loc.y - wo.y
    if abs(lx) > d["envelope_half"] + tol_xy or abs(ly) > d["envelope_half"] + tol_xy:
        return False
    return True


def percentile(values, pct):
    if not values:
        return None
    s = sorted(values)
    k = (len(s) - 1) * pct / 100.0
    lo, hi = math.floor(k), math.ceil(k)
    if lo == hi:
        return s[lo]
    return s[lo] * (hi - k) + s[hi] * (k - lo)


def report_deviation_stats(label, devs):
    """Print distribution for a list of (dev, x, z, h, s) tuples."""
    if not devs:
        print(f"  {label}: no paired samples")
        return
    vals = [r[0] for r in devs]
    vals.sort()
    top = max(devs, key=lambda r: r[0])
    print(f"  {label}: count {len(vals)}  median {percentile(vals, 50):.4f} m  "
          f"p90 {percentile(vals, 90):.4f} m  max {top[0]:.4f} m")
    print(f"    worst at sample x={top[1]:.2f} z={top[2]:.2f}")
    print(f"    hero {tuple(round(v, 3) for v in top[3])}  sim {tuple(round(v, 3) for v in top[4])}")
    print(f"    >50 mm: {sum(1 for v in vals if v > 0.05)}")


def envelope_deviation(hero_parts, sim_parts, d, wo, samples=11):
    """Pair hero/sim first exterior hits per ray; report unf filtered deviation."""
    devs = []
    eh = d["envelope_half"]
    lo, hi = -eh, eh
    corner_x = eh - d["corner_size"] * 0.5
    zs = [0.8, 1.6, 2.4]
    if d["storeys"] > 1:
        zs += [WALL_H + 0.8, WALL_H + 1.6, WALL_H + 2.4]
    hero_walls = shell_objects(hero_parts)
    sim_walls = shell_objects(sim_parts)
    for z in zs:
        for i in range(samples):
            x = lo + (hi - lo) * i / (samples - 1)
            is_corner = abs(x) >= corner_x - 0.05
            for axis, sign in (("y", -1), ("y", 1), ("x", -1), ("x", 1)):
                if axis == "y":
                    origin = Vector((wo.x + x, wo.y + sign * 15, wo.z + z))
                    direc = Vector((0, -sign, 0))
                else:
                    origin = Vector((wo.x + sign * 15, wo.y + x, wo.z + z))
                    direc = Vector((-sign, 0, 0))
                h_t, h = exterior_probe_t(hero_walls, origin, direc)
                s_t, s = exterior_probe_t(sim_walls, origin, direc)
                if h is None or s is None or h_t is None or s_t is None:
                    continue
                if not hit_on_structure(h, wo, d) or not hit_on_structure(s, wo, d):
                    continue
                dev = (h - s).length
                devs.append((dev, x, z, h, s, is_corner))
    if not devs:
        print("  envelope deviation: no paired hits")
        return None
    corner = [(r[0], r[1], r[2], r[3], r[4]) for r in devs if r[5]]
    mid = [(r[0], r[1], r[2], r[3], r[4]) for r in devs if not r[5]]
    print("  envelope deviation (hero vs sim first hit per ray, 3D separation):")
    report_deviation_stats("all", [(r[0], r[1], r[2], r[3], r[4]) for r in devs])
    report_deviation_stats("mid-wall", mid)
    report_deviation_stats("near-corner", corner)
    return max(r[0] for r in devs)


def verify_corner_fill(name, sim_parts, d, wo):
    """Diagonal rays through exterior corners — gaps read OPEN."""
    print(f"\n--- [{name}] corner diagonal probes ---")
    for i, (cx, cy) in enumerate(d["corner_centers"]):
        diag = Vector((cx, cy, 0.0))
        if diag.length < 1e-6:
            continue
        outward = diag.normalized()
        origin = wo + outward * (diag.length + 4.0) + Vector((0, 0, 2.0))
        hits = ray_crossings(sim_parts, origin, -outward, reach=12)
        state = "FILLED" if len(hits) >= 2 else f"GAP FAIL n={len(hits)}"
        print(f"  corner {i} ({cx:+.2f},{cy:+.2f})  n={len(hits)}  {state}")


def layout_aperture_probes(cfg, wo, d):
    """Derive aperture / solid probe rays from storey layout and bay centres."""
    probes = []
    offsets = cfg["module_offsets"]
    wall_r = d["wall_exterior"]
    for si, sides in enumerate(cfg["storey_sides"]):
        z_base = si * WALL_H
        tag = "ground" if si == 0 else "upper"
        for yaw, names in sides:
            n, tang = side_vectors(yaw)
            for i, nm in enumerate(names):
                bay = tang * offsets[i] + n * wall_r
                if "Door" in nm or "Window" in nm:
                    kind = "door" if "Door" in nm else "win"
                    side = {0.0: "S", 90.0: "E", 180.0: "N", 270.0: "W"}[yaw]
                    z_probe = z_base + (1.20 if "Door" in nm else 1.80)
                    origin = wo + bay + n * 12.0
                    origin.z = wo.z + z_probe
                    probes.append((f"{tag} {kind} {side}", origin, -n, "sealed"))
                elif "Straight" in nm and tag == "ground" and yaw == 180.0 and i == 0:
                    side = "N"
                    origin = wo + bay + n * 12.0
                    origin.z = wo.z + z_base + 1.20
                    probes.append((f"solid {side} ground", origin, -n, "sealed"))
    return probes


def aperture_probe_ray(ap, wo):
    n, _tang = side_vectors(ap["yaw"])
    z_probe = ap["z_base"] + (1.20 if ap["kind"] == "door" else 1.80)
    origin = wo + ap["wall_loc"] + n * 12.0
    origin.z = wo.z + z_probe
    return origin, -n


def probe_aperture_state(label, origin, direc, sim_parts, expect, panel_id=None):
    targets = sim_parts
    if panel_id is not None:
        targets = [p for p in sim_parts if f"Panel_{panel_id}" in p.name]
    hits = ray_crossings(targets, origin, direc, reach=30)
    if expect == "sealed":
        state = "SEALED" if len(hits) >= 2 else f"UNSEALED FAIL n={len(hits)}"
    else:
        state = "blocked" if len(hits) >= 2 else "OPEN FAIL"
    return len(hits), state


def verify_apertures(name, sim_parts, cfg, wo, d, apertures):
    results = []
    for ap in apertures:
        origin, direc = aperture_probe_ray(ap, wo)
        n_hits, state = probe_aperture_state(
            ap["label"], origin, direc, sim_parts, "sealed", panel_id=ap["id"])
        print(f"  {ap['label']:18s} n={n_hits}  {state}")
        results.append((ap["label"], state))
    for label, origin, direc, expect in layout_aperture_probes(cfg, wo, d):
        if not label.startswith("solid "):
            continue
        n_hits, state = probe_aperture_state(label, origin, direc, sim_parts, expect)
        print(f"  {label:18s} n={n_hits}  {state}")
        results.append((label, state))
    return results


def measure_aperture_separations(apertures, hero_parts, sim_parts, wo):
    print(f"\n--- per-aperture hero/sim panel separation ---")
    rows = []
    for ap in apertures:
        aid = ap["id"]
        hero_objs = [o for o in hero_parts if f"Seal_{aid}" in o.name]
        sim_objs = [o for o in sim_parts if f"Panel_{aid}" in o.name]
        if not hero_objs or not sim_objs:
            print(f"  {ap['label']:22s}  MISSING hero={len(hero_objs)} sim={len(sim_objs)}")
            continue
        n, _tang = side_vectors(ap["yaw"])
        spec = ap["spec"]
        z_mid = (spec["z0"] + spec["z1"]) / 2.0
        devs = []
        for i in range(9):
            t = i / 8.0
            lx = spec["x0"] + (spec["x1"] - spec["x0"]) * t
            local = Vector((lx, 0.0, z_mid))
            world_pt = wall_world_matrix(ap["yaw"], ap["wall_loc"], wo, ap["z_base"]) @ local
            origin = world_pt + n * 8.0
            _, h = exterior_probe_t(hero_objs, origin, -n)
            _, s = exterior_probe_t(sim_objs, origin, -n)
            if h is not None and s is not None:
                devs.append(((h - s).length, h, s))
        if not devs:
            print(f"  {ap['label']:22s}  no paired hits")
            continue
        vals = [r[0] for r in devs]
        worst = max(devs, key=lambda r: r[0])
        med = percentile(vals, 50)
        mx = max(vals)
        print(f"  {ap['label']:22s}  samples {len(vals)}  median {med:.4f} m  max {mx:.4f} m")
        print(f"    worst hero {tuple(round(v, 3) for v in worst[1])}  sim {tuple(round(v, 3) for v in worst[2])}")
        rows.append((ap["label"], med, mx))
    return rows


def verify_structure(name, sim_parts, hero_parts, d, wo, cfg, apertures):
    print(f"\n=== {name.upper()} SIMULATION (per piece) ===")
    for obj in sim_parts:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bnd = sum(1 for e in bm.edges if len(e.link_faces) == 1)
        nmf = sum(1 for e in bm.edges if len(e.link_faces) > 2)
        print(f"  {obj.name:44s} boundary {bnd:3d}  nonmanifold {nmf:3d}  "
              f"{'CLOSED' if bnd == 0 and nmf == 0 else 'OPEN'}")
        bm.free()

    xs = list(cfg["module_offsets"])
    storey_zs = [2.60]
    if d["storeys"] > 1:
        storey_zs.append(WALL_H + 2.60)

    print(f"\n--- [{name}] wall spans (+Y ray) ---")
    spans = []
    for z_probe in storey_zs:
        tag = "ground" if z_probe < WALL_H else "upper"
        print(f"  storey {tag} z={z_probe:.2f}")
        for x in xs:
            hits = ray_crossings(sim_parts, Vector((wo.x + x, wo.y - 12, wo.z + z_probe)), Vector((0, 1, 0)))
            ys = [h.y for h in hits]
            gaps = [ys[i + 1] - ys[i] for i in range(len(ys) - 1)]
            thin = [g for g in gaps if g < 1.0]
            spans += thin
            print(f"    x={x:5.1f}  n={len(ys)}  y=" + " ".join(f"{v - wo.y:+.2f}" for v in ys[:8]) +
                  "   spans " + " ".join(f"{g:.3f}" for g in gaps[:5]))
    if spans:
        tmin = min(spans)
        print(f"  thinnest wall span {tmin:.3f} m -> "
              f"{'PASSES' if tmin >= TARGET_T - 0.01 else 'FAILS'} (target {TARGET_T:.2f})")

    print(f"\n--- [{name}] apertures (expect SEALED) ---")
    verify_apertures(name, sim_parts, cfg, wo, d, apertures)

    if cfg.get("intermediate_floor"):
        print(f"\n--- [{name}] intermediate floor (+Z ray centre) ---")
        hz = ray_crossings(sim_parts, Vector((wo.x, wo.y, wo.z + 0.01)), Vector((0, 0, 1)), reach=12)
        zs = [h.z - wo.z for h in hz]
        print(f"  z hits: " + " ".join(f"{v:.2f}" for v in zs[:10]))
        mid = [z for z in zs if WALL_H - 0.15 <= z <= WALL_H + 0.15]
        print(f"  crossings near z={WALL_H:.2f}: {len(mid)} -> "
              f"{'SEPARATES' if mid else 'MISSING FAIL'}")

    verify_corner_fill(name, sim_parts, d, wo)

    measure_aperture_separations(apertures, hero_parts, sim_parts, wo)

    print(f"\n--- [{name}] envelope half={d['envelope_half']:.3f} total_h={d['total_h']:.2f} ---")
    envelope_deviation(hero_parts, sim_parts, d, wo)
    mesh_stats(list(hero_parts), f"{name} hero")
    mesh_stats(list(sim_parts), f"{name} sim")


def export_collection(objects, path, root_name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    empty = bpy.data.objects.new(root_name, None)
    bpy.context.collection.objects.link(empty)
    for o in objects:
        o.parent = empty
    empty.select_set(True)
    bpy.context.view_layer.objects.active = empty
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    print(f"exported {path}")


def hide_collection(col, hide):
    for obj in list(col.all_objects):
        obj.hide_render = hide


# ---------------------------------------------------------------- main
hero_root = bpy.data.collections.new("Hero")
sim_root = bpy.data.collections.new("Simulation")
bpy.context.scene.collection.children.link(hero_root)
bpy.context.scene.collection.children.link(sim_root)

_hero_roof = bpy.data.materials.new("HeroRoofCap")
_hero_roof.use_nodes = True
_hero_roof.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.52, 0.44, 0.36, 1.0)
_hero_roof.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85

_clay = bpy.data.materials.new("SimClay")
_clay.use_nodes = True
_bsdf = _clay.node_tree.nodes["Principled BSDF"]
_bsdf.inputs["Base Color"].default_value = (0.62, 0.58, 0.52, 1.0)
_bsdf.inputs["Roughness"].default_value = 0.92
_bsdf.inputs["Specular IOR Level"].default_value = 0.15

_glass = bpy.data.materials.new("HeroGlass")
_glass.use_nodes = True
_gbsdf = _glass.node_tree.nodes["Principled BSDF"]
_gbsdf.inputs["Base Color"].default_value = (0.72, 0.82, 0.88, 1.0)
_gbsdf.inputs["Roughness"].default_value = 0.05
_gbsdf.inputs["Specular IOR Level"].default_value = 0.8
_gbsdf.inputs["Transmission Weight"].default_value = 0.65


def hide_roof_caps(parts, hide):
    for obj in parts:
        if "RoofCap" in obj.name:
            obj.hide_render = hide


def kit_piece_names(cfg):
    names = set(HERO_CORNER_PIECES) | set(HERO_SEAL_PIECES)
    for sides in cfg["storey_sides"]:
        for _yaw, run in sides:
            names.update(run)
    return names


built = {}
for sname in structures:
    if sname not in CONFIGS:
        continue
    cfg = CONFIGS[sname]
    wo = cfg["scene_offset"]
    hcol = bpy.data.collections.new(f"Hero_{sname}")
    scol = bpy.data.collections.new(f"Sim_{sname}")
    hero_root.children.link(hcol)
    sim_root.children.link(scol)
    built[sname] = {"wo": wo, "cfg": cfg, "hero_col": hcol, "sim_col": scol, "d": cfg_derived(cfg)}

needed = set()
for sname in structures:
    if sname in CONFIGS:
        needed |= kit_piece_names(CONFIGS[sname])
print(f"\npre-conditioning {len(needed)} kit pieces at {TARGET_T:.2f} m", flush=True)
for nm in sorted(needed):
    hero_data(nm)
    if nm not in HERO_SEAL_PIECES and nm not in HERO_CORNER_PIECES:
        solid_data(nm)

all_apertures = []
for sname in structures:
    if sname not in built:
        continue
    hp, d, aps = assemble_hero(built[sname]["cfg"], built[sname]["hero_col"], _hero_roof, _glass, built[sname]["wo"])
    built[sname]["hero"] = hp
    built[sname]["d"] = d
    built[sname]["apertures"] = aps
    all_apertures += aps

for sname in structures:
    if sname not in built:
        continue
    sp, d, aps = assemble_sim(built[sname]["cfg"], built[sname]["sim_col"], _clay, built[sname]["wo"], omit_seal=OMIT_SEAL)
    built[sname]["sim"] = sp
    built[sname]["d"] = d
    built[sname]["apertures"] = aps

if not NO_RENDER:
    hide_collection(sim_root, True)
    if "square" in built:
        sd, wo = built["square"]["d"], built["square"]["wo"]
        sh = built["square"]["hero"]
        loc, tgt = frame_exterior(sh, sd, wo)
        render("square_hero_exterior", loc, tgt)
    if "tower" in built:
        td, wo = built["tower"]["d"], built["tower"]["wo"]
        th = built["tower"]["hero"]
        loc, tgt = frame_exterior(th, td, wo)
        render("tower_hero_exterior", loc, tgt)
    if "square" in built and "tower" in built:
        both = built["square"]["hero"] + built["tower"]["hero"]
        mins, maxs = parts_bounds(both)
        center = (mins + maxs) / 2.0
        span = max(maxs.x - mins.x, maxs.y - mins.y, maxs.z - mins.z)
        loc = center + Vector((0, -span * 1.05, span * 0.42))
        render("both_hero_wide", loc, center, lens=28.0)
    hide_collection(sim_root, False)

    hide_collection(hero_root, True)
    if "tower" in built:
        td, wo = built["tower"]["d"], built["tower"]["wo"]
        ts = built["tower"]["sim"]
        hide_roof_caps(ts, True)
        loc, tgt, ortho = frame_plan(ts, td, wo, margin=1.45)
        render("tower_sim_plan", loc, tgt, ortho_scale=ortho * 1.08)
        hide_roof_caps(ts, False)
    if "square" in built:
        sd, wo = built["square"]["d"], built["square"]["wo"]
        ss = built["square"]["sim"]
        hide_roof_caps(ss, True)
        loc, tgt, ortho = frame_plan(ss, sd, wo, margin=1.45)
        render("square_sim_plan", loc, tgt, ortho_scale=ortho * 1.08)
        hide_roof_caps(ss, False)
    hide_collection(hero_root, False)

for sname, data in built.items():
    verify_structure(sname, data["sim"], data["hero"], data["d"], data["wo"], data["cfg"], data["apertures"])
    export_collection(data["hero"], os.path.join(OUT_DIR, f"{sname}_hero.glb"), f"Hero_{sname}")
    export_collection(data["sim"], os.path.join(OUT_DIR, f"{sname}_sim.glb"), f"Sim_{sname}")

if all_apertures:
    falsify = all_apertures[0]
    print(f"\n=== FALSIFIABILITY: omit sim panel '{falsify['id']}' ===")
    for sname, data in built.items():
        if not falsify["id"].startswith(sname + "_"):
            continue
        sim_without = [p for p in data["sim"] if falsify["id"] not in p.name or "Panel_" not in p.name]
        origin, direc = aperture_probe_ray(falsify, data["wo"])
        n_hits, state = probe_aperture_state(
            falsify["label"], origin, direc, sim_without, "sealed", panel_id=falsify["id"])
        print(f"  without panel: {falsify['label']:18s} n={n_hits}  {state}")
        break

print(f"\nstructures built: {list(built.keys())}")
for sname, data in built.items():
    d = data["d"]
    print(f"  {sname}: half={d['half']} envelope={2*d['envelope_half']:.2f} m  "
          f"height={d['total_h'] + CAP:.2f} m  storeys={d['storeys']}")
