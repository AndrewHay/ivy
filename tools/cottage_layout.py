"""Cottage (village backdrop) layout math — shared with build_structures.

House-local frame matches ``VillageBackdrop`` (ivy-2or): ridge along +X,
footprint x ∈ [-bays, bays], y ∈ [-depth_half, depth_half] in Blender XY
(Z up).  Wall kit pieces face local +Y after ``_facing`` rotation.
"""

from __future__ import annotations

import math
from typing import List, Tuple

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
    if slot == door:
        return PIECE_WALL_DOOR
    if slot in windows:
        return PIECE_WALL_WINDOW
    side = slot.split(":")[0]
    if side == brick_side:
        return PIECE_WALL_BRICK
    return PIECE_WALL


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
