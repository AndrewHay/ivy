class_name HillsForestPlacement
extends RefCounted

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsNoise = preload("res://src/playground/hills_noise.gd")
const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestPlacement = preload("res://src/playground/forest_placement.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
const ForestCamRef = preload("res://src/world/forest_cam_ref.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

const W_MAX := 1.45
const NEAR_BAND_R_LO := 110.0   # rework5: matches new forest_r_min_m = 110 m
const NEAR_BAND_R_HI := 190.0   # rework5: matches new layer_dist_1 = 190 m
const AZIMUTH_SECTORS := 6
const NEAR_SECTOR_FLOOR := 10


static func hill_forest_transforms(
		layout: VillageLayout,
		params: HillsParams,
		terrain_seed: int,
		backdrop_trees_xz: Array[Vector2]) -> Array[Transform3D]:
	var g := layout.hamlet_centre_xz
	var target := params.tree_count
	var forest_st := HillsHeightfield.forest_lcg_seed(layout, params)
	var accepted: Array[Vector2] = []
	var attempts := 0
	var max_attempts := target * 240
	var fparams := ForestParams.production()
	var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	while accepted.size() < target and attempts < max_attempts:
		attempts += 1
		forest_st = VillageScatterPositions.lcg_step(forest_st)
		var r := lerpf(params.forest_r_min_m, params.forest_r_max_m,
			VillageScatterPositions.lcg_f01(forest_st))
		forest_st = VillageScatterPositions.lcg_step(forest_st)
		var phi := lerpf(-PI, PI, VillageScatterPositions.lcg_f01(forest_st))
		var p := g + Vector2(sin(phi) * r, cos(phi) * r)
		# Early azimuth wedge reject — skip strictly out-of-wedge points immediately.
		var az_w := HillsHeightfield.azimuth_weight(p, g, params)
		## Use 0.001 threshold to match test definition of "strictly outside"; avoids
		## floating-point fringe cases where a point just past the wedge edge gets w≈1e-15.
		if az_w <= 0.001:
			continue
		var copse := HillsNoise.copse_density_01(p, terrain_seed + 501, params.copse_scale_m)
		var w := hemisphere_weight(phi, params) * slope_weight(p, layout, params, terrain_seed)
		w *= edge_falloff(r, params)
		w *= valley_weight(p, layout, params, terrain_seed, y_lawn)
		w *= az_w
		if copse >= params.copse_threshold:
			var t := (copse - params.copse_threshold) / maxf(1.0 - params.copse_threshold, 0.01)
			w *= 0.55 + t * 1.35
		else:
			forest_st = VillageScatterPositions.lcg_step(forest_st)
			if VillageScatterPositions.lcg_f01(forest_st) > params.lone_tree_rate:
				continue
			w *= _crest_lone_weight(p, layout, params, terrain_seed, y_lawn)
		if w <= 0.0:
			continue
		forest_st = VillageScatterPositions.lcg_step(forest_st)
		if VillageScatterPositions.lcg_f01(forest_st) > w / W_MAX:
			continue
		if not site_ok_hill(p, layout, params, backdrop_trees_xz):
			continue
		var ok_sep := true
		for other: Vector2 in accepted:
			if p.distance_to(other) < params.min_sep_m:
				ok_sep = false
				break
		if not ok_sep:
			continue
		accepted.append(p)
	if accepted.size() < target:
		_top_up(accepted, target, layout, params, terrain_seed, backdrop_trees_xz, forest_st)
	forest_st = _floor_near_band_sectors(
		accepted, layout, params, terrain_seed, backdrop_trees_xz, forest_st)
	return _transforms_from_xz(accepted, layout, params, terrain_seed, forest_st)


static func site_ok_hill(
		p: Vector2, layout: VillageLayout, params: HillsParams,
		backdrop_trees_xz: Array[Vector2]) -> bool:
	if VillageLayout.inside_cottages(layout.cottages, p, 0.45):
		return false
	if VillageScatterPositions.blocks_scatter_at(p):
		return false
	if VillageScatterPositions.min_xz_dist_to_path_segments(p, layout.path_polylines()) < 0.55:
		return false
	var fparams := ForestParams.production()
	if ForestPlacement.forest_blocks_camsun_view(p, fparams):
		return false
	var g := layout.hamlet_centre_xz
	if p.distance_to(g) < layout.lawn_radius + 0.01:
		return false
	if p.distance_to(VillageLayout.HERO_DOOR_STOOP) < 9.0:
		return false
	for q: Vector2 in backdrop_trees_xz:
		if p.distance_to(q) < params.backdrop_exclusion_m:
			return false
	var cd := _camsun_cam_horizontal_dist(p, fparams)
	if cd >= fparams.backdrop_cam_dist_lo_m and cd <= fparams.backdrop_cam_dist_hi_m:
		return false
	var terrain_seed := HillsHeightfield.terrain_seed(layout, params)
	if HillsHeightfield.sample_slope_deg(p, layout, params, terrain_seed) > params.slope_max_deg:
		return false
	return true


static func valley_weight(
		p: Vector2, layout: VillageLayout, params: HillsParams, terrain_seed: int,
		y_lawn: float) -> float:
	var y := HillsHeightfield.sample_y(p, layout, params, terrain_seed)
	var rel := y - y_lawn
	var g := layout.hamlet_centre_xz
	var r := p.distance_to(g)
	var expect := rel / maxf(params.height_scale_m, 1.0)
	var low := clampf(1.0 - expect, 0.35, 1.45)
	if r > 105.0:
		low *= 0.92
	return low


static func _crest_lone_weight(
		p: Vector2, layout: VillageLayout, params: HillsParams, terrain_seed: int,
		y_lawn: float) -> float:
	var y := HillsHeightfield.sample_y(p, layout, params, terrain_seed)
	var yx := HillsHeightfield.sample_y(p + Vector2(2.5, 0.0), layout, params, terrain_seed)
	var yz := HillsHeightfield.sample_y(p + Vector2(0.0, 2.5), layout, params, terrain_seed)
	if y <= yx + 0.4 and y <= yz + 0.4:
		return 0.65
	return 0.0


static func hemisphere_weight(phi: float, hp: HillsParams) -> float:
	var fwd := atan2(
		ForestPlaygroundCamera.camsun_forward().x, ForestPlaygroundCamera.camsun_forward().z)
	var dphi := absf(angle_difference(phi, fwd))
	if dphi <= hp.hemisphere_boost_phi:
		return hp.hemisphere_boost
	return hp.hemisphere_lo


static func slope_weight(
		p: Vector2, layout: VillageLayout, params: HillsParams, terrain_seed: int) -> float:
	var slope := HillsHeightfield.sample_slope_deg(p, layout, params, terrain_seed)
	if slope > params.slope_max_deg:
		return 0.0
	var d := (slope - params.slope_prefer_deg) / 14.0
	return exp(-0.5 * d * d)


static func edge_falloff(r: float, params: HillsParams) -> float:
	var t0 := smoothstep(params.forest_r_min_m, params.forest_r_min_m + 6.0, r)
	var t1 := 1.0 - smoothstep(params.forest_r_max_m - 8.0, params.forest_r_max_m, r)
	return t0 * t1


static func _camsun_cam_horizontal_dist(layout_pt: Vector2, params: ForestParams) -> float:
	var pivot := ForestCamRef.resolve_orbit_pivot(params)
	var off := ForestCamRef.backdrop_origin(pivot)
	var wp := Vector2(layout_pt.x + off.x, layout_pt.y + off.z)
	var cam := ForestCamRef.camsun_eye(pivot, ForestCamRef.resolve_rig_scale(params))
	return Vector2(wp.x - cam.x, wp.y - cam.z).length()


static func angle_difference(a: float, b: float) -> float:
	var diff := fmod(b - a, TAU)
	if diff > PI:
		diff -= TAU
	elif diff < -PI:
		diff += TAU
	return diff


static func _near_sector_counts(accepted: Array[Vector2], layout: VillageLayout) -> PackedInt32Array:
	var g := layout.hamlet_centre_xz
	var counts := PackedInt32Array()
	counts.resize(AZIMUTH_SECTORS)
	for p: Vector2 in accepted:
		var rg := p.distance_to(g)
		if rg < NEAR_BAND_R_LO or rg > NEAR_BAND_R_HI:
			continue
		var phi := atan2(p.x - g.x, p.y - g.y)
		var sec := int(floor((phi + PI) / TAU * AZIMUTH_SECTORS)) % AZIMUTH_SECTORS
		counts[sec] += 1
	return counts


static func _floor_near_band_sectors(
		accepted: Array[Vector2], layout: VillageLayout, params: HillsParams,
		terrain_seed: int, backdrop_trees_xz: Array[Vector2], forest_st: int) -> int:
	var counts := _near_sector_counts(accepted, layout)
	var g := layout.hamlet_centre_xz
	var attempts := 0
	var cap := params.tree_count * 50
	for sec in range(AZIMUTH_SECTORS):
		# Skip sectors whose centre falls outside the azimuth wedge.
		var phi_mid := -PI + (float(sec) + 0.5) / float(AZIMUTH_SECTORS) * TAU
		var mid_xz := g + Vector2(sin(phi_mid), cos(phi_mid)) * (NEAR_BAND_R_LO + NEAR_BAND_R_HI) * 0.5
		if HillsHeightfield.azimuth_weight(mid_xz, g, params) <= 0.001:
			continue
		while counts[sec] < NEAR_SECTOR_FLOOR and attempts < cap:
			attempts += 1
			forest_st = VillageScatterPositions.lcg_step(forest_st)
			var phi_lo := -PI + float(sec) / float(AZIMUTH_SECTORS) * TAU
			var phi_hi := -PI + float(sec + 1) / float(AZIMUTH_SECTORS) * TAU
			var phi := lerpf(phi_lo, phi_hi, VillageScatterPositions.lcg_f01(forest_st))
			forest_st = VillageScatterPositions.lcg_step(forest_st)
			var r := lerpf(NEAR_BAND_R_LO, NEAR_BAND_R_HI, VillageScatterPositions.lcg_f01(forest_st))
			var p := g + Vector2(sin(phi) * r, cos(phi) * r)
			if HillsHeightfield.azimuth_weight(p, g, params) <= 0.001:
				continue
			var w := slope_weight(p, layout, params, terrain_seed) * edge_falloff(r, params)
			w *= 0.9
			if w <= 0.0 or not site_ok_hill(p, layout, params, backdrop_trees_xz):
				continue
			var ok_sep := true
			for other: Vector2 in accepted:
				if p.distance_to(other) < params.min_sep_m * 0.85:
					ok_sep = false
					break
			if not ok_sep:
				continue
			if accepted.size() >= params.tree_count:
				_drop_farthest_hill_tree(accepted, layout)
			accepted.append(p)
			counts[sec] += 1
	return forest_st


static func _drop_farthest_hill_tree(accepted: Array[Vector2], layout: VillageLayout) -> void:
	var g := layout.hamlet_centre_xz
	var far_i := 0
	var far_r := -1.0
	for i in range(accepted.size()):
		var r := accepted[i].distance_to(g)
		if r > far_r:
			far_r = r
			far_i = i
	accepted.remove_at(far_i)


static func _top_up(
		accepted: Array[Vector2], target: int, layout: VillageLayout, params: HillsParams,
		terrain_seed: int, backdrop_trees_xz: Array[Vector2], forest_st: int) -> void:
	var g := layout.hamlet_centre_xz
	var attempts := 0
	while accepted.size() < target and attempts < target * 100:
		attempts += 1
		forest_st = VillageScatterPositions.lcg_step(forest_st)
		var r := lerpf(params.forest_r_min_m, params.forest_r_max_m,
			VillageScatterPositions.lcg_f01(forest_st))
		forest_st = VillageScatterPositions.lcg_step(forest_st)
		var phi := lerpf(-PI, PI, VillageScatterPositions.lcg_f01(forest_st))
		var p := g + Vector2(sin(phi) * r, cos(phi) * r)
		if HillsHeightfield.azimuth_weight(p, g, params) <= 0.001:
			continue
		var copse := HillsNoise.copse_density_01(p, terrain_seed + 501, params.copse_scale_m)
		var w := slope_weight(p, layout, params, terrain_seed) * 1.15
		if copse > params.copse_threshold * 0.85:
			w *= 1.2
		if w <= 0.0 or not site_ok_hill(p, layout, params, backdrop_trees_xz):
			continue
		for other: Vector2 in accepted:
			if p.distance_to(other) < params.min_sep_m:
				w = 0.0
				break
		if w <= 0.0:
			continue
		accepted.append(p)


static func _transforms_from_xz(
		accepted: Array[Vector2], layout: VillageLayout, params: HillsParams,
		terrain_seed: int, forest_st: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var st := forest_st
	for p in accepted:
		st = VillageScatterPositions.lcg_step(st)
		var s := lerpf(params.scale_min, params.scale_max, VillageScatterPositions.lcg_f01(st))
		st = VillageScatterPositions.lcg_step(st)
		var rot := VillageScatterPositions.lcg_f01(st) * TAU
		var y := HillsHeightfield.sample_y(p, layout, params, terrain_seed)
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(p.x, y, p.y)))
	return out
