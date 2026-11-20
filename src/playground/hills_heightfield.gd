class_name HillsHeightfield
extends RefCounted

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsNoise = preload("res://src/playground/hills_noise.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

const W_MAX := 1.45
## AR-LANDSCAPE-FIRST (AR-LF-D3 / -D6): for generated layouts with landscape terrain (terrain
## variant 0) sample_y and build_mesh delegate to the one VillageTerrain field; the ridge core
## (ridge_core) is the far-ridge term Rg inside that field. No toe, no rim pin, no base lift.
## Classic layouts, HillsParams variant 1 and terrain variant 1 keep the flat legacy paths (INV-15).

static var _prod_terrain: Resource = null


static func _terrain_params_of(layout: VillageLayout) -> Resource:
	if layout.terrain_params != null:
		return layout.terrain_params
	if _prod_terrain == null:
		_prod_terrain = (load("res://src/playground/village_terrain_params.gd") as GDScript).call("production")
	return _prod_terrain


static func delegates_to_village_terrain(layout: VillageLayout, params: HillsParams) -> bool:
	## True when this layout's hills are the VillageTerrain field (generated, both variants != 1).
	if not layout.is_generated or params.variant == 1:
		return false
	return int(_terrain_params_of(layout).get("variant")) != 1


static func terrain_seed(layout: VillageLayout, params: HillsParams) -> int:
	var norm := layout.generation_seed if layout.generation_seed > 0 else params.layout_seed
	return VillageLayout._derive(norm, VillageLayout.HILLS_TERRAIN_SALT)


static func forest_lcg_seed(layout: VillageLayout, params: HillsParams) -> int:
	if params.lcg_seed >= 0:
		return params.lcg_seed
	var norm := layout.generation_seed if layout.generation_seed > 0 else params.layout_seed
	return VillageLayout._derive(norm, VillageLayout.HILLS_FOREST_SALT)


## Signed shortest-path difference b − a, wrapped to (−PI, PI].
static func _angle_difference(a: float, b: float) -> float:
	var diff := fmod(b - a, TAU)
	if diff > PI:
		diff -= TAU
	elif diff < -PI:
		diff += TAU
	return diff


## Returns [0, 1] weight for the azimuth wedge at xz relative to hamlet centre g.
## 1.0 inside the wedge, 0.0 outside, smooth taper over azimuth_fade_width_deg.
## Convention: azimuth_centre_deg 0 = north = −Z, 90 = east = +X (matches project compass).
static func azimuth_weight(xz: Vector2, g: Vector2, params: HillsParams) -> float:
	if params.azimuth_half_width_deg >= 180.0:
		return 1.0
	var dx := xz.x - g.x
	var dz := xz.y - g.y
	if dx * dx + dz * dz < 0.01:
		return 1.0
	# phi = atan2(dx, dz): phi=0 → +Z (south), phi=PI → −Z (north).
	var phi := atan2(dx, dz)
	# Convert compass azimuth (0=north, 90=east) to phi.
	# azimuth 0° (north) → phi=PI; azimuth 90° (east) → phi=PI/2.
	var north_phi := PI - deg_to_rad(params.azimuth_centre_deg)
	var diff := absf(_angle_difference(phi, north_phi))
	var hw := deg_to_rad(params.azimuth_half_width_deg)
	var fw := maxf(deg_to_rad(params.azimuth_fade_width_deg), 0.001)
	var inner_edge := maxf(hw - fw, 0.0)
	if diff <= inner_edge:
		return 1.0
	if diff >= hw:
		return 0.0
	return 1.0 - smoothstep(inner_edge, hw, diff)


static func sample_y(xz: Vector2, layout: VillageLayout, params: HillsParams, _t_seed: int = 0) -> float:
	## Generated landscape: VillageTerrain.field(...).sample_y exactly (AC-LT-SEAM). Otherwise
	## the flat legacy ramp (classic, HillsParams variant 1, terrain variant 1).
	if delegates_to_village_terrain(layout, params):
		return VillageTerrain.field(layout, _terrain_params_of(layout), params).sample_y(xz)
	return _sample_y_flat_legacy(xz, layout, VillageBackdrop.LAWN_GROUND_Y_OFFSET)


static func sample_slope_deg(
		xz: Vector2, layout: VillageLayout, params: HillsParams, t_seed: int, eps_m := 0.4) -> float:
	var y0 := sample_y(xz, layout, params, t_seed)
	var yx := sample_y(xz + Vector2(eps_m, 0.0), layout, params, t_seed)
	var yz := sample_y(xz + Vector2(0.0, eps_m), layout, params, t_seed)
	var dx := (yx - y0) / eps_m
	var dz := (yz - y0) / eps_m
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))


static func build_mesh(layout: VillageLayout, params: HillsParams) -> ArrayMesh:
	## Generated landscape: the polar far mesh stitched to the lawn on the join loop (AR-LF-D6).
	if delegates_to_village_terrain(layout, params):
		return VillageTerrain.build_far_mesh(layout, _terrain_params_of(layout), params)
	return build_flat_legacy_mesh(layout, params)


static func build_flat_legacy_mesh(layout: VillageLayout, params: HillsParams) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 64
	var c := layout.hamlet_centre_xz if layout.is_generated else Vector2.ZERO
	var inner_r := layout.hill_inner if not layout.is_generated else params.r_inner_m
	var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	_annulus_ramp(st, segs, inner_r, 140.0, y_lawn, y_lawn + 7.5, c)
	st.generate_normals()
	return st.commit()


static func _sample_y_flat_legacy(xz: Vector2, layout: VillageLayout, y_lawn: float) -> float:
	var c := layout.hamlet_centre_xz if layout.is_generated else Vector2.ZERO
	## WP3 (GENERATED_HILL_INNER retired): generated ramps start 2 m outside the lawn (was 58 = 56 + 2).
	var inner_r := layout.hill_inner if not layout.is_generated else layout.lawn_radius + 2.0
	var r := xz.distance_to(c)
	if r < inner_r:
		return y_lawn
	if r > 140.0:
		return y_lawn
	var t := (r - inner_r) / maxf(140.0 - inner_r, 0.01)
	return lerpf(y_lawn, y_lawn + 7.5, t)


static func _polar(g: Vector2, r: float, a: float) -> Vector2:
	return g + Vector2(sin(a) * r, cos(a) * r)


static func ridge_core(
		xz: Vector2, r: float, _layout: VillageLayout, params: HillsParams, t_seed: int) -> float:
	## The north ridge core (layers 155–260 m) without a radial rise gate: VillageTerrainField
	## applies the far_ridge_start/full gate and azimuth_weight (SD-VILLAGE-TERRAIN-17 §3). ≥ 0.
	var n01 := HillsNoise.fbm_height_01(
		xz, t_seed, params.base_feature_m, params.noise_octaves,
		params.noise_persistence, params.warp_strength)
	var layer_gain := _radial_layer_gain(r, params)
	var u := (r - params.r_inner_m) / maxf(params.r_outer_m - params.r_inner_m, 0.01)
	var fade_out := 1.0 - pow(clampf(u, 0.0, 1.0), params.radial_bias_power)
	var h := n01 * params.height_scale_m * layer_gain * fade_out
	var bump := HillsNoise.fbm_height_01(
		xz * 0.55 + Vector2(40.0, -17.0), t_seed + 9001, params.base_feature_m * 0.65,
		2, params.noise_persistence * 0.85, params.warp_strength * 0.5)
	h += (bump - 0.45) * params.height_scale_m * 0.22 * layer_gain
	return maxf(h, 0.0)


static func _radial_layer_gain(r: float, params: HillsParams) -> float:
	var gain := 0.0
	for i in range(params.layer_count):
		var centre := params.layer_dist_at(i)
		var width := params.layer_width_at(i)
		var amp := params.layer_amp_scale_at(i)
		var d := (r - centre) / maxf(width, 0.01)
		gain += amp * exp(-0.5 * d * d)
	return clampf(gain, 0.12, 1.35)


static func _annulus_ramp(
		st: SurfaceTool, segs: int, inner_r: float, outer_r: float, inner_y: float, outer_y: float,
		centre_xz: Vector2) -> void:
	for i in range(segs):
		var a0 := (float(i) / segs) * TAU
		var a1 := (float(i + 1) / segs) * TAU
		var v0 := Vector3(
			centre_xz.x + cos(a0) * inner_r, inner_y, centre_xz.y + sin(a0) * inner_r)
		var v1 := Vector3(
			centre_xz.x + cos(a1) * inner_r, inner_y, centre_xz.y + sin(a1) * inner_r)
		var v2 := Vector3(
			centre_xz.x + cos(a0) * outer_r, outer_y, centre_xz.y + sin(a0) * outer_r)
		var v3 := Vector3(
			centre_xz.x + cos(a1) * outer_r, outer_y, centre_xz.y + sin(a1) * outer_r)
		st.add_vertex(v0)
		st.add_vertex(v2)
		st.add_vertex(v1)
		st.add_vertex(v1)
		st.add_vertex(v2)
		st.add_vertex(v3)
