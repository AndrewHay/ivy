class_name IvyParams
extends Resource

@export_group("Spec30")
@export var segment_length: float = 0.03
@export var max_growth_rate: float = 0.12
@export var light_memory: float = 3.0
@export var light_K: float = 3.0
@export var reference_DLI: float = 12.0
@export var persistence_base: float = 0.50
@export var random_base: float = 0.20
@export var random_new_mix: float = 0.25
@export var light_seek_min: float = 0.03
@export var light_seek_max: float = 0.23
@export var adhesion_base: float = 0.10
@export var adhesion_range: float = 0.15
@export var max_float: float = 0.40
@export var gravity_exponent: float = 0.70
@export var crowding_base: float = 0.15
@export var crowding_decay: float = 0.80
@export var branch_rate: float = 1.7
@export var branch_light_exponent: float = 1.30
@export var branch_crowd_exponent: float = 1.50
@export var direction_memory: float = 0.50
@export var light_gradient_scale: float = 4.0
@export var crowding_gradient_scale: float = 2.0

@export_group("Time")
@export var sim_tick: float = 1.0 / 24.0
@export var speed_watch: float = 60.0
@export var speed_fast: float = 6.0
@export var speed_grow: float = 1.2
@export var render_sun_blend_lo: float = 10.0
@export var render_sun_blend_hi: float = 30.0
@export var latitude: float = 51.5
@export var longitude: float = 0.0
@export var day_of_year: int = 105
@export var start_hour: float = 6.0
@export var light_warmup_days: float = 12.0
@export var diel_night_floor: float = 0.05
@export var diel_exponent: float = 0.35
@export var diel_gate_enabled: bool = true

@export_group("Light")
## Spec section 5 calibration values, in micromol m^-2 s^-1.
@export var light_p_max: float = 1600.0
@export var light_p_sky: float = 180.0
## Weather multipliers W and W_sky. Pinned to 1.0 by INV-9: present, not implemented.
@export var weather_direct: float = 1.0
@export var weather_sky: float = 1.0
@export var light_elevation_exponent_direct: float = 0.65
@export var light_elevation_exponent_diffuse: float = 0.50

@export_group("Field")
@export var field_cell: float = 0.06
@export var field_sample_jitter_ratio: float = 0.35
@export var gradient_epsilon_ratio: float = 1.5
@export var field_shell_halfwidth: float = 0.09
## Coarse grid for the raycast-bound bake products, per AR-FIELD-6.
@export var vis_cell: float = 0.12
@export var svf_rays: int = 64
@export var bake_ray_length: float = 12.0
@export var bake_ray_offset: float = 0.02

@export_group("Geometry")
@export var contact_distance: float = 0.02
@export var max_segments_per_tick: int = 8
@export var branch_angle_min: float = 45.0
@export var branch_angle_max: float = 75.0
@export var branch_offset: float = 0.005
@export var ground_y_min: float = 0.02

@export_group("Tips")
@export var tip_cap_soft: int = 96
@export var tip_cap_hard: int = 160
@export var retire_margin: float = 1.25
## SD-TIP-3 (W-045): floor for branch_probability_scale — keeps SD-TIP-4 retirement swap
## reachable at saturation while eliminating the 64× discontinuity at the hard cap.
@export var branch_scale_floor: float = 0.02
@export var stall_rate: float = 0.01
@export var stall_days: int = 3
@export var tip_cap_m1: int = 64
## SD-TIP-6 (W-038): fraction of tower height above which tips are protected from
## retirement when the silhouette count is below silhouette_min_tips.
@export var silhouette_height_frac: float = 0.8
@export var silhouette_min_tips: int = 3

@export_group("Leaf")
@export var internode_base: float = 0.040
@export var internode_shade_gain: float = 0.9
@export var internode_jitter: float = 0.25
@export var leaf_tip_suppress: float = 0.06
@export var phyllotaxy_divergence: float = 137.5
@export var phyllotaxy_flatten: float = 0.65
@export var leaf_out_of_plane: float = 0.35
@export var leaf_photo_cant: float = 0.45
@export var droop_base: float = 12.0
@export var droop_shade_gain: float = 18.0
@export var leaf_jitter_tilt: float = 22.0
@export var leaf_jitter_roll: float = 15.0
@export var leaf_jitter_yaw: float = 8.0
@export var leaf_offset_base: float = 0.004
@export var leaf_offset_step: float = 0.0015
@export var leaf_offset_ladder: int = 5
@export var leaf_width_base: float = 0.075
@export var leaf_order_falloff: float = 0.18
@export var leaf_expand_distance: float = 0.12
@export var leaf_light_scale_base: float = 0.80
@export var leaf_light_scale_gain: float = 0.30
@export var leaf_size_sigma: float = 0.16
@export var leaf_healthy_base: float = 0.25
@export var leaf_healthy_gain: float = 0.65
## SD-LEAF-7 sun/shade tint (W-060). Interpolated by f_L; kept deliberately modest
## so the plant reads as one species in two light conditions (SD-LEAF-7 constraint).
@export var leaf_shade_tint: Color = Color(0.78, 0.86, 0.74)
@export var leaf_sun_tint: Color = Color(1.06, 1.04, 0.86)
@export var leaf_crowd_suppress: float = 0.70
@export var leaf_crowd_floor: float = 0.30
## SD-LEAF-8: deposit scale for the crowding channel. Deposit per node = k * leaf_area / cell_area.
## W-048 raised this to 0.85 and it was reverted: `deposit_crowding` clamps C to [0, 1], so a
## higher k cannot deepen suppression where the plant is already dense, it only makes sparse
## regions saturate sooner. On this tower that is the shaded half, and raising it cost 23 points
## of shaded coverage for 4% of the volume overshoot. See W-050 before changing.
@export var leaf_crowd_k: float = 0.5
@export var leaf_cap: int = 20000

@export_group("Stem")
@export var stem_radius_base: float = 0.006
@export var stem_order_falloff: float = 0.25
@export var stem_tip_taper: float = 0.15

@export_group("Flags")
@export var dev_build: bool = true


func field_sample_jitter() -> float:
	return field_sample_jitter_ratio * field_cell


func gradient_epsilon() -> float:
	return gradient_epsilon_ratio * field_cell


func light_ewma_alpha(dt_sim: float) -> float:
	return exp(-dt_sim / light_memory)


func content_hash() -> String:
	var names: PackedStringArray = [
		"segment_length", "max_growth_rate", "light_memory", "light_K", "reference_DLI",
		"persistence_base", "random_base", "random_new_mix", "light_seek_min", "light_seek_max",
		"adhesion_base", "adhesion_range", "max_float", "gravity_exponent", "crowding_base",
		"crowding_decay", "branch_rate", "branch_light_exponent", "branch_crowd_exponent",
		"direction_memory", "light_gradient_scale", "crowding_gradient_scale", "sim_tick", "speed_watch", "speed_fast",
		"speed_grow", "render_sun_blend_lo", "render_sun_blend_hi", "latitude", "longitude",
		"day_of_year", "start_hour", "light_warmup_days", "diel_night_floor", "diel_exponent",
		"light_p_max", "light_p_sky", "weather_direct", "weather_sky",
		"light_elevation_exponent_direct", "light_elevation_exponent_diffuse",
		"field_cell", "field_sample_jitter_ratio", "gradient_epsilon_ratio", "field_shell_halfwidth",
		"vis_cell", "svf_rays", "bake_ray_length", "bake_ray_offset",
		"contact_distance", "max_segments_per_tick", "branch_angle_min", "branch_angle_max",
		"branch_offset", "ground_y_min", "tip_cap_soft", "tip_cap_hard", "retire_margin",
		"branch_scale_floor", "silhouette_height_frac", "silhouette_min_tips",
		"stall_rate", "stall_days", "tip_cap_m1", "internode_base", "internode_shade_gain",
		"internode_jitter", "leaf_tip_suppress", "phyllotaxy_divergence", "phyllotaxy_flatten",
		"leaf_out_of_plane", "leaf_photo_cant", "droop_base", "droop_shade_gain",
		"leaf_jitter_tilt", "leaf_jitter_roll", "leaf_jitter_yaw", "leaf_offset_base",
		"leaf_offset_step", "leaf_offset_ladder", "leaf_width_base", "leaf_order_falloff",
		"leaf_expand_distance", "leaf_light_scale_base", "leaf_light_scale_gain", "leaf_size_sigma",
		"leaf_healthy_base", "leaf_healthy_gain", "leaf_shade_tint", "leaf_sun_tint",
		"leaf_crowd_suppress", "leaf_crowd_floor",
		"leaf_crowd_k", "leaf_cap", "stem_radius_base", "stem_order_falloff", "stem_tip_taper",
		"diel_gate_enabled", "dev_build",
	]
	var parts: PackedStringArray = []
	for n in names:
		parts.append("%s=%s" % [n, _format_value(get(n))])
	var sorted := parts.duplicate()
	sorted.sort()
	return "|".join(sorted).md5_text()


func _format_value(v: Variant) -> String:
	match typeof(v):
		TYPE_FLOAT:
			return "%.9f" % v
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_COLOR:
			var c: Color = v
			return "%.6f,%.6f,%.6f,%.6f" % [c.r, c.g, c.b, c.a]
		_:
			return str(v)
