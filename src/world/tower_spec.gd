class_name TowerSpec
extends Resource

@export var height: float = 3.50
@export var radius_outer: float = 2.00
@export var wall_thickness: float = 0.35
@export var lip_overhang: float = 0.18
@export var lip_thickness: float = 0.15
@export var door_azimuth: float = 0.0
@export var door_width: float = 0.90
@export var door_height: float = 2.00
@export var window_azimuth: float = 90.0
@export var window_size: float = 0.60
@export var window_depth: float = 0.12
@export var window_sill: float = 1.60
@export var ring_segments: int = 96
# Physical patch size of the brick material in metres (width × height).
# Bricks094: dimensionX=180 cm, dimensionY=90 cm (ambientcg.com/api/v2/full_json?id=Bricks094).
# Horizontal UV repeats are derived from .x; vertical scale from .y.
# Update this when swapping to a different material to avoid aspect distortion.
@export var brick_physical_size: Vector2 = Vector2(1.80, 0.90)


func radius_inner() -> float:
	return radius_outer - wall_thickness


func lip_radius() -> float:
	return radius_outer + lip_overhang
