class_name WorldFogParams
extends Resource

## Shared production + playground knobs (ivy-jnee). One implementation for both.

enum Falloff { LINEAR, SMOOTH, EXPONENTIAL }

const DEFAULT_CLEAR_RADIUS_M := 20.0
const DEFAULT_THICK_RADIUS_M := 80.0
const DEFAULT_MAX_DENSITY := 0.14
const DEFAULT_SKY_AFFECT_CAP := 0.22
const DEFAULT_VOLUME_SIZE := Vector3(900.0, 160.0, 900.0)

@export var clear_radius_m: float = DEFAULT_CLEAR_RADIUS_M
@export var thick_radius_m: float = DEFAULT_THICK_RADIUS_M
@export var max_density: float = DEFAULT_MAX_DENSITY
@export var falloff: Falloff = Falloff.SMOOTH
@export var sky_affect_cap: float = DEFAULT_SKY_AFFECT_CAP
@export var ray_steps: int = 12
@export var max_ray_distance_m: float = 200.0


static func production():
	return load("res://src/world/world_fog_params.gd").new()


func duplicate_params() -> WorldFogParams:
	return duplicate(true) as WorldFogParams
