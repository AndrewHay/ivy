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
## Negative gravitropism: constant upward bias while attached (ivy-fhh / SD-CONV-6).
@export var upward_base: float = 0.20

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
## W-096: aperture-driven ambient for enclosed cells (SVF≈0). Scales with horizon escape
## fraction, not a global floor — shaded exterior walls keep SVF≈0.5 and get no leak term.
@export var light_p_leak: float = 36.0
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
## SD-TIP-6 (W-038): fraction of tower height above which tips are protected from
## retirement when the silhouette count is below silhouette_min_tips.
@export var silhouette_height_frac: float = 0.8
@export var silhouette_min_tips: int = 3

@export_group("Leaf")
@export var internode_base: float = 0.030
@export var internode_shade_gain: float = 0.85
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
@export var leaf_width_base: float = 0.092
@export var leaf_order_falloff: float = 0.18
@export var leaf_expand_distance: float = 0.10
@export var leaf_light_scale_base: float = 0.80
@export var leaf_light_scale_gain: float = 0.30
@export var leaf_size_sigma: float = 0.16
@export var leaf_healthy_base: float = 0.18
@export var leaf_healthy_gain: float = 0.77
## SD-LEAF-7 sun/shade tint (W-060). Interpolated by f_L; kept deliberately modest
## so the plant reads as one species in two light conditions (SD-LEAF-7 constraint).
@export var leaf_shade_tint: Color = Color(0.78, 0.86, 0.74)
@export var leaf_sun_tint: Color = Color(1.06, 1.04, 0.86)
## W-080: multiplicative tint on weathered-tier atlas rects — cools/desaturates the
## reddish CC0 weathered variants so they read as summer chlorosis, not autumn speckle.
@export var leaf_weathered_tint: Color = Color(0.82, 0.98, 0.86)
## SD-LEAF-7 age lightening (render-only; not in content_hash). Applied in leaf.gdshader
## when LeafRenderer passes s_age in instance COLOR.a.
@export var leaf_young_tint: Color = Color(1.10, 1.08, 0.92)
@export var leaf_crowd_suppress: float = 0.70
@export var leaf_crowd_floor: float = 0.30
## SD-LEAF-8b (W-015): experienced-light floor for sun-saturated dense nodes only.
@export var leaf_crowd_floor_sun: float = 0.22
## Extra suppress (× sun_dense) when both C and f_L exceed the dense thresholds below.
@export var leaf_crowd_sun_suppress_gain: float = 0.10
@export var leaf_crowd_sun_dense_c: float = 0.85
@export var leaf_crowd_sun_dense_f_l: float = 0.85
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

@export_group("Eave traversal")
## Enable soffit-crawl + lip-rounding on WallSdf buildings. Set deterministically by World
## per building id — 'overhang' only. Default false so non-overhang paths are bit-identical.
@export var eave_traversal_enabled: bool = false
## Upward bias added to the direction blend while traverse_ticks > 0 (T2 rule). Scoped to
## active traversals only — not the general wall climb — so stem length is preserved.
@export var eave_up_bias: float = 0.25
## Along-soffit push component added while a tip is on the underside face (T2 rule).
@export var eave_soffit_glide: float = 0.6
## Maximum segments a tip may float before the traversal window expires (T3 rule).
@export var eave_traverse_window: int = 40
## Extended max_float ceiling while a traversal is active (T3 rule). Bounded by window above.
@export var eave_traverse_max_float: float = 0.55
## T5 (ivy-dsh.9): growth-rate f_L floor while traverse_ticks > 0 (WallSdf only).
## Lets the dark-soffit crawl run near open-wall speed (f_L≈0.16 → floored to 0.75).
## Floors ONLY the growth f_L; f_C, f_S, and g_hat are untouched. Double-gated.
@export var eave_traverse_light_floor: float = 0.75
## Early traverse arm (ivy-dsh.9): metres above tip to look for a soffit overhead.
## One upward raycast per live tip-step on the overhang path; 0.0 disables. Double-gated.
@export var eave_approach_reach: float = 0.40
## Min dot(start_normal, snap_candidate.normal) for WallSdf post-placement snap (ivy-a4n).
## Lower = allow sharper corners; higher = stay on the same wall face.
@export var eave_snap_face_cos: float = 0.5
## Enable local feeler-thinning density cap (Rule F). Set alongside eave_traversal_enabled.
@export var feeler_thinning_enabled: bool = false
## Bin width along x for feeler-density counting (Rule F).
@export var feeler_bin: float = 0.25
## Maximum concurrent floating tips (floating_length > feeler_min_float) per bin (Rule F).
@export var feeler_cap: int = 4
## Minimum floating_length for a tip to count as a feeler in Rule F.
@export var feeler_min_float: float = 0.05

@export_group("Flags")
@export var dev_build: bool = true

## W-086 / W-013: declared in IvyParams but not read by simulation — overlay shows
## these as inert (disabled) so tuning sessions are not misled. Empty after W-086
## (tip_cap_m1 deleted; the ten §30 presentation knobs are wired).
const OVERLAY_INERT: Array[String] = ["speed_watch", "speed_fast", "speed_grow"]

## Parameters the *coarse* light bake's output depends on (ivy-9xp). `LightBakeCache` keys on
## these, so a cached bake is only reused when every one of them matches.
##
## Under-listing a parameter here is the stale-read failure: the cache would hand back ray
## products computed under different inputs and every test would still pass. Over-listing only
## costs an unnecessary re-bake. So when a new parameter is genuinely ambiguous, put it here.
## `test_light_bake_cache_conformance.gd` fails until every exported parameter is classified,
## which is what stops this list from silently falling behind the declarations.
##
## What the coarse bake actually computes, per cell: SVF, the 24-bit direct-sun visibility
## mask, the horizon-escape leak fraction, and the surface normal. Hence:
##
## - shell/grid extent decides which cells are baked at all: `field_cell`,
##   `field_shell_halfwidth`, `vis_cell`
## - the rays themselves: `svf_rays`, `bake_ray_length`, `bake_ray_offset`
## - the sun path feeding the visibility mask, via `Solar`: `latitude`, `longitude`,
##   `day_of_year`. These were missing from the pre-ivy-9xp hand-written hash, so moving the
##   site or the date silently reused another location's shadows.
## - `light_elevation_exponent_direct`, because `LightBake._precompute_sun_path` gates the mask
##   on `pow(sin_elevation, exponent) > 0` and at exponent 0 that flips every hour on.
##
## Deliberately absent: everything that only scales the *fine* P(cell, hour) table computed in
## `fill_field` — `light_p_max`, `light_p_sky`, `weather_*`, `light_elevation_exponent_diffuse`,
## `light_p_leak`. ivy-k99 gave the fine grid its own cache, keyed by `FINE_BAKE_AFFECTING`
## below, deliberately *not* merged into this list: a light-tuning change to `light_p_max`
## must invalidate the fine cache (the result changed) but has no reason to force the coarse
## ray bake to re-run (12–24s on the measured buildings) since it provably cannot move a
## single SVF, visibility-mask, or leak value. Merging the lists would cost every tuning
## session the full ray-trace it does not need.
##
## `light_p_leak` needs the same care in the other direction as everything else here:
## `horizon_escape_factor` (the coarse leak *geometry*) never reads it, so it stays out of
## this list; but `p_leak()` (fed by the fine fill) does read it, so it lives in
## `FINE_BAKE_AFFECTING` instead. If the bake ever skips its leak rays when
## `light_p_leak == 0`, as an optimisation would, `horizon_escape_factor` itself becomes
## dependent on the value and it must move to *this* list too.
const BAKE_AFFECTING: Array[String] = [
	"bake_ray_length",
	"bake_ray_offset",
	"day_of_year",
	"field_cell",
	"field_shell_halfwidth",
	"latitude",
	"light_elevation_exponent_direct",
	"longitude",
	"svf_rays",
	"vis_cell",
]

## Parameters that additionally affect the *fine* `P(cell, hour)` table (ivy-k99), beyond
## everything already in `BAKE_AFFECTING` — `field_cell`/`field_shell_halfwidth` govern which
## fine cells exist and are shared with the coarse list rather than duplicated here. Kept as a
## second list rather than folded into `BAKE_AFFECTING` for the reason explained there: this
## set changes what a light-tuning session pays to re-run, not just what a cache invalidates.
const FINE_BAKE_AFFECTING: Array[String] = [
	"light_elevation_exponent_diffuse",
	"light_p_leak",
	"light_p_max",
	"light_p_sky",
	"weather_direct",
	"weather_sky",
]


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
		"direction_memory", "light_gradient_scale", "crowding_gradient_scale", "upward_base", "sim_tick", "speed_watch", "speed_fast",
		"speed_grow", "render_sun_blend_lo", "render_sun_blend_hi", "latitude", "longitude",
		"day_of_year", "start_hour", "light_warmup_days", "diel_night_floor", "diel_exponent",
		"light_p_max", "light_p_sky", "light_p_leak", "weather_direct", "weather_sky",
		"light_elevation_exponent_direct", "light_elevation_exponent_diffuse",
		"field_cell", "field_sample_jitter_ratio", "gradient_epsilon_ratio", "field_shell_halfwidth",
		"vis_cell", "svf_rays", "bake_ray_length", "bake_ray_offset",
		"contact_distance", "max_segments_per_tick", "branch_angle_min", "branch_angle_max",
		"branch_offset", "ground_y_min", "tip_cap_soft", "tip_cap_hard", "retire_margin",
		"branch_scale_floor", "silhouette_height_frac", "silhouette_min_tips",
		"stall_rate", "stall_days", "internode_base", "internode_shade_gain",
		"internode_jitter", "leaf_tip_suppress", "phyllotaxy_divergence", "phyllotaxy_flatten",
		"leaf_out_of_plane", "leaf_photo_cant", "droop_base", "droop_shade_gain",
		"leaf_jitter_tilt", "leaf_jitter_roll", "leaf_jitter_yaw", "leaf_offset_base",
		"leaf_offset_step", "leaf_offset_ladder", "leaf_width_base", "leaf_order_falloff",
		"leaf_expand_distance", "leaf_light_scale_base", "leaf_light_scale_gain", "leaf_size_sigma",
		"leaf_healthy_base", "leaf_healthy_gain", "leaf_shade_tint", "leaf_sun_tint",
		"leaf_weathered_tint",
		"leaf_crowd_suppress", "leaf_crowd_floor", "leaf_crowd_floor_sun",
		"leaf_crowd_sun_suppress_gain", "leaf_crowd_sun_dense_c", "leaf_crowd_sun_dense_f_l",
		"leaf_crowd_k", "leaf_cap", "stem_radius_base", "stem_order_falloff", "stem_tip_taper",
		"diel_gate_enabled", "dev_build",
		"eave_traversal_enabled", "eave_up_bias", "eave_soffit_glide", "eave_traverse_window",
		"eave_traverse_max_float", "eave_traverse_light_floor", "eave_approach_reach",
		"eave_snap_face_cos",
		"feeler_thinning_enabled", "feeler_bin", "feeler_cap",
		"feeler_min_float",
	]
	var parts: PackedStringArray = []
	for n in names:
		parts.append("%s=%s" % [n, _format_value(get(n))])
	var sorted := parts.duplicate()
	sorted.sort()
	return "|".join(sorted).md5_text()


## Checks constraints that couple two parameters, which no per-field `@export_range` can
## express. Returns the violations rather than asserting: `assert` is compiled out of release
## builds, and a guardrail that disappears in the configuration people actually run is not a
## guardrail. Called once from `SimRoot.setup`, so the cost is irrelevant.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = []

	# SD-LEAF-6. P(healthy) = base + gain·f_L is compared unclamped against a hash draw in
	# [0, 1), so base + gain > 1 makes the comparison always true at high light and the
	# weathered tier silently stops appearing. Nothing else catches it: the LG-2′ layer (a)
	# tier tests assert the shape of the probability function, not the drawn outcome, so they
	# stay green while half the leaf atlas goes unused.
	var healthy_max := leaf_healthy_base + leaf_healthy_gain
	if healthy_max > 1.0:
		errors.append(
			"leaf_healthy_base + leaf_healthy_gain = %.4f > 1.0: at full light every tier draw"
			% healthy_max
			+ " returns healthy and the weathered leaf variants are never placed (SD-LEAF-6)")

	return errors


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
