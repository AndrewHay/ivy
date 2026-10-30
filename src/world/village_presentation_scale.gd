## Per-mode scale for cameras and fauna rings (ivy-0ka / AR-VG-DECIDE §3).
## Classic village keeps unity; generated mode dolly-back and wider garden/LOD bands.
class_name VillagePresentationScale
extends RefCounted

const GameModes = preload("res://src/world/game_modes.gd")

## Uniform CameraRig scale in generated mode (~1.3–1.5× framing for outer ring).
const GENERATED_CAMERA_RIG_SCALE := 1.35
## Fauna ring / LOD multiplier — matches generated lawn 36 m vs classic 30 m (INV-20).
const GENERATED_FAUNA_WORLD_SCALE := 1.2

## Classic pivot spawn filter baseline (m); scaled in generated mode.
const CLASSIC_SPAWN_NEAR_PIVOT_M := 8.0

## Runtime fauna ring scale (1.0 classic). Set by World on mode change.
static var fauna_world_scale: float = 1.0


static func set_fauna_world_scale_for_mode(mode_id: String) -> void:
	fauna_world_scale = GENERATED_FAUNA_WORLD_SCALE if GameModes.by_id(mode_id).is_generated else 1.0


static func camera_rig_scale_for_mode(mode_id: String) -> float:
	return GENERATED_CAMERA_RIG_SCALE if GameModes.by_id(mode_id).is_generated else 1.0


static func spawn_near_pivot_max_m() -> float:
	return CLASSIC_SPAWN_NEAR_PIVOT_M * fauna_world_scale


static func scaled_garden_outer_m() -> float:
	return FaunaConstants.GARDEN_RING_OUTER_M * fauna_world_scale


static func scaled_clover_outer_m() -> float:
	return FaunaConstants.CLOVER_RING_OUTER_M * fauna_world_scale


static func scaled_lod_despawn_m() -> float:
	return FaunaConstants.LOD_DESPAWN_M * fauna_world_scale


static func scaled_lod_spawn_forbid_m() -> float:
	return FaunaConstants.LOD_SPAWN_FORBID_M * fauna_world_scale


static func scaled_butterfly_lifetime_min() -> float:
	return 18.0 * fauna_world_scale


static func scaled_butterfly_lifetime_max() -> float:
	return 28.0 * fauna_world_scale
