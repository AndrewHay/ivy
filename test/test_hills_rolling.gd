extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")

const _PARITY_SEEDS: Array[int] = [1, 7, 12]
const _BEARINGS := 8
## rework4: hills are north-only (±55°). 3 of 8 equal-spacing bearings fall inside (NE/N/NW).
const _MIN_GOOD_BEARINGS := 3
const _MIN_ELEV_DEG := 8.0
const _RING_SAMPLE_R := 175.0   # rework5: between ridge 0 (155m) and ridge 1 (190m)
const _RING_AZ_MIN_STD := 1.8


static func _edge_out_pose(layout: VillageLayout) -> Dictionary:
	# rework5: place origin on the NORTH lawn edge (away-from-hero, toward hills).
	# Pure bearing rays (no to_g pull) so NE/N/NW all stay within ±55° wedge.
	var g := layout.hamlet_centre_xz
	var hero := VillageLayout.HERO_DOOR_STOOP
	var centre := g
	var lawn_r := layout.lawn_radius
	var margin := 2.0
	var allowed := maxf(lawn_r - margin, 2.0)
	# dir_out = away from hero (typically northward for south-placed hero).
	var dir_out := (hero - centre).normalized() if hero.distance_to(centre) > 0.1 else Vector2(0, -1)
	dir_out = -dir_out
	var origin := Vector3(centre.x + dir_out.x * allowed, 5.0, centre.y + dir_out.y * allowed)
	return {"edge": origin, "g": g, "eye_y": origin.y, "dir_out": dir_out}


static func _max_elev_deg_along_ray(
		layout: VillageLayout, params: HillsParams, t_seed: int,
		origin: Vector3, dir_xz: Vector2, eye_y: float) -> float:
	var max_ang := 0.0
	for dist in range(80, 290, 5):  # rework5: hills at 155-260 m
		var p := Vector2(origin.x + dir_xz.x * float(dist), origin.z + dir_xz.y * float(dist))
		var y := HillsHeightfield.sample_y(p, layout, params, t_seed)
		var dy := y - eye_y
		max_ang = maxf(max_ang, rad_to_deg(atan2(dy, float(dist))))
	return max_ang


func test_crest_elevation_angle_bearings_seeds() -> void:
	for seed in _PARITY_SEEDS:
		var layout := VillageLayout.generate(seed)
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		if layout.fallback:
			continue
		var params := HillsParams.production()
		var t_seed := HillsHeightfield.terrain_seed(layout, params)
		var pose := _edge_out_pose(layout)
		var origin: Vector3 = pose["edge"]
		var g: Vector2 = pose["g"]
		var eye_y: float = pose["eye_y"]
		var good := 0
		for b in range(_BEARINGS):
			var phi := (float(b) / float(_BEARINGS)) * TAU
			# Pure radial bearings: no to_g pull so NE/N/NW stay within ±55° north wedge.
			var ray_dir := Vector2(sin(phi), cos(phi))
			var ang := _max_elev_deg_along_ray(layout, params, t_seed, origin, ray_dir, eye_y)
			if ang >= _MIN_ELEV_DEG:
				good += 1
		assert_gte(
			good, _MIN_GOOD_BEARINGS,
			"seed %d only %d/%d bearings >= %.1f deg" % [seed, good, _BEARINGS, _MIN_ELEV_DEG])


func test_height_azimuth_not_ring_symmetric() -> void:
	for seed in [7, 12]:
		var layout := VillageLayout.generate(seed)
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		if layout.fallback:
			continue
		var params := HillsParams.production()
		var t_seed := HillsHeightfield.terrain_seed(layout, params)
		var g := layout.hamlet_centre_xz
		var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
		var heights: PackedFloat32Array = []
		for b in range(32):
			var phi := (float(b) / 32.0) * TAU
			var p := g + Vector2(sin(phi), cos(phi)) * _RING_SAMPLE_R
			heights.append(HillsHeightfield.sample_y(p, layout, params, t_seed) - y_lawn)
		var mean := 0.0
		for h in heights:
			mean += h
		mean /= float(heights.size())
		var varsum := 0.0
		for h in heights:
			varsum += (h - mean) * (h - mean)
		var std := sqrt(varsum / float(heights.size()))
		assert_gt(
			std, _RING_AZ_MIN_STD,
			"seed %d azimuth height std %.2f m too low (ring-like)" % [seed, std])


func test_production_peak_height_in_target_band() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	# rework5: rolling hills at 155-260 m; sample north wedge (±55°).
	var peak := y_lawn
	for r in range(140, 280, 5):
		for b in range(24):
			# Sample north wedge (phi near PI = north = −Z direction, ±55°)
			var phi := PI + (float(b) / 24.0 - 0.5) * (55.0 / 90.0) * PI
			var p := g + Vector2(sin(phi), cos(phi)) * float(r)
			peak = maxf(peak, HillsHeightfield.sample_y(p, layout, params, t_seed))
	var crest := peak - y_lawn
	assert_gte(crest, 14.0, "crest lift %.1f m (rework5: rolling hills)" % crest)
	assert_lte(crest, 50.0, "crest lift %.1f m (rework5: not mountains)" % crest)
