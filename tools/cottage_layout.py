"""Cottage (village backdrop) layout math — shared with build_structures.

House-local frame matches ``VillageBackdrop`` (ivy-2or): ridge along +X,
footprint x ∈ [-bays, bays], y ∈ [-depth_half, depth_half] in Blender XY
(Z up).  Wall kit pieces show their exterior (local -Y) outward after the
``cottage_facing_angle`` rotation; local +Y points into the house.
"""

from __future__ import annotations

import json
import math
import os
from typing import Dict, List, Tuple

# Godot village_backdrop constants
COTTAGE_DEPTH_HALF = 2.0  # two 2 m bays deep
WALL_TOP = 3.125
DOOR_LEAF_KIT_OFFSET_X = -0.51267

PIECE_WALL = "Wall_Plaster_Straight"
PIECE_WALL_WINDOW = "Wall_Plaster_Window_Wide_Flat"
PIECE_WALL_DOOR = "Wall_Plaster_Door_Flat"
PIECE_WALL_BRICK = "Wall_UnevenBrick_Straight"
PIECE_DOOR_LEAF = "Door_1_Flat"
PIECE_SHUTTER = "WindowShutters_Wide_Flat_Closed"
PIECE_GABLE = "Roof_Front_Brick4"
PIECE_CHIMNEY = "Prop_Chimney2"
ROOF_BY_BAYS = {3: "Roof_RoundTiles_4x6", 4: "Roof_RoundTiles_4x8"}


def cottage_slot(side: str, bay: int, bays: int, depth_half: float = COTTAGE_DEPTH_HALF):
    """Wall grid slot → (house-local position Vector, outward yaw deg)."""
    half_len = float(bays)
    if side == "front":
        pos = (-half_len + 1.0 + 2.0 * bay, depth_half, 0.0)
        yaw = 180.0
    elif side == "back":
        pos = (-half_len + 1.0 + 2.0 * bay, -depth_half, 0.0)
        yaw = 0.0
    elif side == "left":
        pos = (-half_len, -1.0 + 2.0 * bay, 0.0)
        yaw = 270.0
    else:  # right
        pos = (half_len, -1.0 + 2.0 * bay, 0.0)
        yaw = 90.0
    return pos, yaw


# Kit wall pieces carry their 0.09 m timber trim (exterior) on local -Y and
# their plaster / top beam (0.31 m, interior) on local +Y.
KIT_EXTERIOR_LOCAL = (0.0, -1.0)


def cottage_outward_normal(yaw_deg: float) -> Tuple[float, float]:
    """House-local outward wall normal for a ``cottage_slot`` yaw."""
    yr = math.radians(yaw_deg)
    return (math.sin(yr), -math.cos(yr))


def cottage_facing_angle(nx: float, ny: float) -> float:
    """Z rotation (radians) that turns kit-local -Y (exterior) onto (nx, ny).

    Kit-local +Y then points into the house, matching the aperture frame
    used by ``wall_world_matrix`` (y into the room).
    """
    return math.atan2(nx, -ny)


# ── ivy-b1e.17: detail pieces, measured kit geometry, design variants ──────────
# All kit numbers are kit-local Blender (glTF (x, y, z) -> Blender (x, -z, y)):
# exterior on -Y, the wall's exterior plaster face at y = 0, timber trim to -0.0924.
PIECE_CORNER_POST = "Corner_Exterior_Wood"
PIECE_WINDOW_INSERT = "Window_Wide_Flat1"
PIECE_DOOR_FRAME = "DoorFrame_Flat_WoodDark"
# Node stem for the corner posts. Not "Corner_Exterior_*": diagnose_hero_deviation's
# classify_node files those as hero-only trim and drops them from the gate-3 measure.
CORNER_POST_NODE = "CornerPost"

KIT_TRIM_DEPTH = 0.0924   # wall timber trim proud of the plaster face
KIT_TRIM_TOP_Z = 3.1227   # top of the wall pieces' top plate
CORNER_POST_NATIVE_HALF = (0.1051, 0.1198)  # Corner_Exterior_Wood x / y half extents
CORNER_POST_NATIVE_H = 3.0
CORNER_LABELS = (("FL", -1, 1), ("FR", 1, 1), ("BL", -1, -1), ("BR", 1, -1))

# Door leaf (Door_1_Flat) native bounds; hinge origin, not centred.
DOOR_LEAF_BOUNDS = ((-0.0463, -0.0631, 0.0352), (1.0716, 0.0576, 2.1349))
# Where the leaf goes, per door style. y_outer is the kit-local y of the leaf's
# outer face. "frame": inside DoorFrame_Flat_WoodDark's opening at its native depth.
# "stretch": no frame; fill Wall_Plaster_Door_Flat's bare doorway, 1 cm behind the plaster.
DOOR_OPENINGS = {
    "frame": {"x0": -0.558, "x1": 0.558, "z0": 0.0, "z1": 2.141, "y_outer": -0.0631},
    "stretch": {"x0": -0.648, "x1": 0.648, "z0": 0.0, "z1": 2.151, "y_outer": 0.01},
}
DOOR_LEAF_OVERLAP = 0.01  # tuck behind the frame / plaster at the sides and top

# Wall_Plaster_Window_Wide_Flat's hole, and the hero glass sized to it plus a 2 cm tuck.
COTTAGE_WINDOW_HOLE = {"x0": -0.60, "x1": 0.60, "z0": 1.040, "z1": 2.318}
COTTAGE_WINDOW_GLASS = {"x0": -0.62, "x1": 0.62, "z0": 1.020, "z1": 2.338}
# Closed shutter, "flush" style: back face this far in front of the plaster, bottom this
# far below the hole. ("frame" style keeps the kit's native placement on the frame lip.)
SHUTTER_WALL_GAP = 0.002
SHUTTER_OPENING_OVERLAP = 0.01

# Design variants for the human A/B (ivy-b1e.17). Production defaults below; a build
# overrides them with build_structures.py --cottage-style window=flush,door=stretch.
COTTAGE_STYLE_CHOICES = {
    "window": ("frame", "flush"),
    "door": ("frame", "stretch"),
    # ivy-b1e.17.6: depth of the kit window insert (and its shutters) about the plaster face.
    "sill": ("native", "shallow"),
    # ivy-b1e.17.5: window wall piece, and a stone plinth under every plain (non-door/window)
    # bay on all four sides so the house stands on a continuous stone base:
    # none = braced plaster to the ground; all_l = Straight_L everywhere (braces all lean
    # one way); all_lr = Straight_L / Straight_R alternating by bay; all_base = no brace.
    "window_wall": ("flat", "flat2"),
    "plinth": ("none", "all_l", "all_lr", "all_base"),
}
COTTAGE_STYLE_DEFAULT = {
    "window": "frame",
    "door": "frame",
    "sill": "shallow",  # owner's pick 2026-11-15 (ivy-b1e.17.6)
    "window_wall": "flat",
    "plinth": "all_lr",  # owner's pick 2026-11-15 (ivy-b1e.17.5): house stands on a stone base
}
SILL_DEPTH_SCALE = {"native": 1.0, "shallow": 0.6}
WINDOW_WALL_PIECES = {
    "flat": "Wall_Plaster_Window_Wide_Flat",
    "flat2": "Wall_Plaster_Window_Wide_Flat2",
}
PLINTH_L = "Wall_Plaster_Straight_L"
PLINTH_R = "Wall_Plaster_Straight_R"
PLINTH_BASE = "Wall_Plaster_Straight_Base"


def plinth_piece(style: str, bay: int) -> str:
    """Plain-bay wall piece for a ``plinth`` style choice (see COTTAGE_STYLE_CHOICES)."""
    if style == "all_l":
        return PLINTH_L
    if style == "all_lr":
        return PLINTH_L if bay % 2 == 0 else PLINTH_R
    if style == "all_base":
        return PLINTH_BASE
    return PIECE_WALL


# Set from build_structures.py's --cottage-style argument (see parse_cottage_style).
_STYLE_OVERRIDE: Dict[str, str] = {}


def parse_cottage_style(spec: str) -> Dict[str, str]:
    """Parse a ``--cottage-style`` value such as ``window=frame,sill=shallow`` (validated)."""
    out: Dict[str, str] = {}
    for item in filter(None, (s.strip() for s in spec.split(","))):
        key, sep, val = item.partition("=")
        key, val = key.strip(), val.strip()
        if not sep or key not in COTTAGE_STYLE_CHOICES or val not in COTTAGE_STYLE_CHOICES[key]:
            raise ValueError(f"--cottage-style: bad {item!r}; choices {COTTAGE_STYLE_CHOICES}")
        out[key] = val
    return out


def set_cottage_style(spec: str) -> None:
    """Install a ``--cottage-style`` override for this build."""
    _STYLE_OVERRIDE.clear()
    _STYLE_OVERRIDE.update(parse_cottage_style(spec))


def cottage_style(env: Dict[str, str] | None = None) -> Dict[str, str]:
    """Production style, then the IVY_COTTAGE_STYLE JSON env var (legacy fallback), then
    the ``--cottage-style`` command-line override, each validated."""
    raw = (os.environ if env is None else env).get("IVY_COTTAGE_STYLE") or "{}"
    style = dict(COTTAGE_STYLE_DEFAULT)
    for key, val in list(json.loads(raw).items()) + list(_STYLE_OVERRIDE.items()):
        if key not in COTTAGE_STYLE_CHOICES or val not in COTTAGE_STYLE_CHOICES[key]:
            raise ValueError(f"cottage style: bad {key}={val!r}; choices {COTTAGE_STYLE_CHOICES}")
        style[key] = val
    return style


def cottage_corner_posts(bays: int, depth_half: float = COTTAGE_DEPTH_HALF):
    """Outer-corner posts -> [(label, (x, y), yaw_rad, (sx, sy, sz))], base at z = 0.

    Origin is the plaster corner where both walls' grid lines meet. The kit post is
    scaled to a square (x half-width on both axes) reaching the top plate; yaw turns
    kit-local (-1, -1) onto the outward diagonal, so its -X / -Y faces are exterior.
    """
    hx, hy = CORNER_POST_NATIVE_HALF
    scale = (1.0, hx / hy, KIT_TRIM_TOP_Z / CORNER_POST_NATIVE_H)
    return [
        (label, (sx * float(bays), sy * float(depth_half)),
         math.atan2(sy, sx) + math.radians(135.0), scale)
        for label, sx, sy in CORNER_LABELS
    ]


def door_leaf_fit(opening: Dict[str, float], leaf=DOOR_LEAF_BOUNDS, overlap=DOOR_LEAF_OVERLAP):
    """Kit-local offset and (sx, sz) that fill ``opening`` with the door leaf.

    Scale applies about the leaf's mesh origin, so offset = target_lo - leaf_lo * scale.
    The bottom sits on the threshold; y is not scaled.
    """
    lo, hi = leaf
    w = (opening["x1"] - opening["x0"]) + 2.0 * overlap
    h = (opening["z1"] - opening["z0"]) + overlap
    sx = w / (hi[0] - lo[0])
    sz = h / (hi[2] - lo[2])
    off = (
        opening["x0"] - overlap - lo[0] * sx,
        opening["y_outer"] - lo[1],
        opening["z0"] - lo[2] * sz,
    )
    return off, (sx, sz)


def cottage_shutter_fit(
    y_extent: Tuple[float, float],
    z_extent: Tuple[float, float],
    max_proud: float,
) -> Tuple[float, float, float]:
    """(scale_y, dy, dz) seating a closed shutter flat on the window wall's plaster.

    After v -> (x, scale_y * y + dy, z + dz): back face SHUTTER_WALL_GAP in front of
    the plaster (y = 0), front face at most ``max_proud`` out, bottom
    SHUTTER_OPENING_OVERLAP below the hole's sill.
    """
    ymin, ymax = y_extent
    depth = ymax - ymin
    scale_y = min(1.0, (max_proud - SHUTTER_WALL_GAP) / depth) if depth > 1e-9 else 1.0
    dy = -SHUTTER_WALL_GAP - scale_y * ymax
    dz = min(0.0, COTTAGE_WINDOW_HOLE["z0"] - SHUTTER_OPENING_OVERLAP - z_extent[0])
    return scale_y, dy, dz


def all_wall_slots(bays: int) -> List[Tuple[str, int]]:
    slots: List[Tuple[str, int]] = []
    for side in ("front", "back"):
        for i in range(bays):
            slots.append((side, i))
    for side in ("left", "right"):
        for j in range(2):
            slots.append((side, j))
    return slots


def piece_for_slot(
    slot: str,
    door: str,
    windows: List[str],
    brick_side: str,
) -> str:
    style = cottage_style()
    if slot == door:
        return PIECE_WALL_DOOR
    if slot in windows:
        return WINDOW_WALL_PIECES[style["window_wall"]]
    side, bay = slot.split(":")
    if side == brick_side:
        return PIECE_WALL_BRICK
    return plinth_piece(style["plinth"], int(bay))


def cottage_kit_piece_names(cfg: dict) -> set:
    bays = int(cfg["bays"])
    door = str(cfg["door"])
    windows = [str(w) for w in cfg.get("windows", [])]
    brick_side = str(cfg.get("brick_side", ""))
    names = {
        PIECE_DOOR_LEAF,
        PIECE_SHUTTER,
        PIECE_GABLE,
        PIECE_CHIMNEY,
        PIECE_WALL_BRICK,
        ROOF_BY_BAYS[bays],
    }
    # PIECE_CORNER_POST / PIECE_WINDOW_INSERT / PIECE_DOOR_FRAME are hero-only: they
    # load on demand via hero_data and must not go through the solid_data pre-pass.
    for side, bay in all_wall_slots(bays):
        slot = f"{side}:{bay}"
        names.add(piece_for_slot(slot, door, windows, brick_side))
    return names


def cottage_derived(cfg: dict, ext_offset: float, target_t: float, wall_h: float) -> dict:
    """Envelope / probe fields analogous to cfg_derived for ring buildings."""
    bays = int(cfg["bays"])
    depth_half = float(cfg.get("depth_half", COTTAGE_DEPTH_HALF))
    half_len = float(bays)
    wall_x = half_len + ext_offset
    wall_y = depth_half + ext_offset
    envelope_half = max(wall_x, wall_y) + target_t * 0.5
    interior_x = half_len - target_t + 0.02
    interior_y = depth_half - target_t + 0.02
    interior_half = min(interior_x, interior_y)
    corner_centers = [
        (wall_x, wall_y),
        (wall_x, -wall_y),
        (-wall_x, wall_y),
        (-wall_x, -wall_y),
    ]
    return {
        "bays": bays,
        "depth_half": depth_half,
        "half": max(half_len, depth_half),
        "wall_exterior": max(wall_x, wall_y),
        "wall_x": wall_x,
        "wall_y": wall_y,
        "envelope_half": envelope_half,
        "interior_half": interior_half,
        "roof_half": envelope_half,
        "total_h": wall_h,
        "storeys": 1,
        "corner_centers": corner_centers,
        "corner_size": target_t,
        "corner_xy": envelope_half,
    }
