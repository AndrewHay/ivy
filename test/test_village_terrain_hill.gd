## ivy-82zn.14.10 — village on a hill: the hero stands on a crest and the ground falls at least one
## cottage (tallest ridge 6.84 m) to the outermost cottage. Two-layer heightfield (hill P + detail),
## option A datum (local rim datum 0, crest = hero_datum_y; World lowers the village by it), and
## the seam fixes for the dark contour-like lines (path corridor blend, relief fade floor) and the
## pond bank shards (bank draped on the rendered lawn surface). Architect plan: ivy-82zn.14.9.
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainKnobSpec = preload("res://src/playground/village_terrain_knob_spec.gd")
const VillagePondSite = preload("res://src/world/village_pond_site.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

## Tallest cottage ridge: WALL_TOP 3.125 + Roof_RoundTiles_4x6 / 4x8 glTF max y 3.718.
const RIDGE_M := 3.125 + 3.7178683280944824
const _FALLBACK_SEED := 19


static func _wide(p: VillageTerrainParams) -> VillageTerrainParams:
	## The human's "wide knobs" repro set (ivy-82zn.14.9): amplitude 6, caps 8 / 6.
	p.base_amplitude_m = 6.0
	p.max_rise_m = 8.0
	p.max_depression_m = 6.0
	return p


static func _fades_zero(p: VillageTerrainParams) -> VillageTerrainParams:
	p.hero_relief_fade_m = 0.0
	p.plaza_relief_fade_m = 0.0
	p.pond_relief_fade_m = 0.0
	p.open_lawn_pad_fade_m = 0.0
	return p


static func _outermost_cottage_centre(layout: VillageLayout) -> Vector2:
	var best := Vector2.ZERO
	var best_d := -1.0
	for spec: Dictionary in layout.cottages:
		var c := spec["centre"] as Vector2
		var d := c.distance_to(VillageLayout.HERO_DOOR_STOOP)
		if d > best_d:
			best_d = d
			best = c
	return best


static func _h(xz: Vector2, layout: VillageLayout, p: VillageTerrainParams, t_seed: int) -> float:
	return VillageTerrain.sample_y(xz, layout, p, t_seed)


## Height discontinuity (C0 step) across a line: the height difference over 1 cm straddling the
## line midway between p_in and p_out. A continuous surface contributes slope × 1 cm (< 0.6 cm at
## 30°), so anything over 2 cm is a real step — the kind the 2 m lawn mesh drew as a dark band. The
## literal 0.1 m difference also contains the hill's own slope (up to ~28°: 5 cm); it is logged.
static func _step_across(
		p_in: Vector2, p_out: Vector2, layout: VillageLayout, p: VillageTerrainParams,
		t_seed: int) -> float:
	var n := (p_out - p_in).normalized()
	var mid := p_in.lerp(p_out, 0.5)
	return absf(_h(mid + n * 0.005, layout, p, t_seed) - _h(mid - n * 0.005, layout, p, t_seed))


static func _raw_across(
		p_in: Vector2, p_out: Vector2, layout: VillageLayout, p: VillageTerrainParams,
		t_seed: int) -> float:
	return absf(_h(p_out, layout, p, t_seed) - _h(p_in, layout, p, t_seed))


# ── Knobs (AC 3) ──────────────────────────────────────────────────────────────

func test_hill_knob_defaults() -> void:
	var p := VillageTerrainParams.production()
	assert_almost_eq(p.hill_rise_m, 8.5, 1e-6)
	assert_almost_eq(p.hill_shoulder, 0.3, 1e-6)
	assert_almost_eq(p.hill_falloff_pow, 1.0, 1e-6)
	assert_almost_eq(p.hill_centre_shift, 0.0, 1e-6)
	assert_almost_eq(p.hill_crest_extra_m, 0.0, 1e-6)
	assert_almost_eq(p.hill_end_margin_m, 2.0, 1e-6)
	assert_almost_eq(p.plaza_hill_follow, 1.0, 1e-6)
	assert_almost_eq(p.hill_bank_max_deg, 30.0, 1e-6)
	assert_almost_eq(p.max_path_slope_deg, 18.0, 1e-6)


func test_hill_knob_rows_and_ranges() -> void:
	var want := {
		"hill_rise_m": [0.0, 17.0], "hill_shoulder": [0.0, 1.0], "hill_falloff_pow": [0.5, 3.0],
		"hill_centre_shift": [0.0, 0.6], "hill_crest_extra_m": [0.0, 15.0],
		"hill_end_margin_m": [-10.0, 20.0], "plaza_hill_follow": [0.0, 1.0],
		"hill_bank_max_deg": [10.0, 45.0],
	}
	var rows := {}
	for row: Dictionary in VillageTerrainKnobSpec.all_knobs():
		rows[row["name"]] = row
	for name: String in want:
		assert_true(rows.has(name), "knob row %s" % name)
		if not rows.has(name):
			continue
		var r: Dictionary = rows[name]
		assert_eq(String(r["group"]), "Village hill", "%s in the Village hill group" % name)
		assert_almost_eq(float(r["min"]), float(want[name][0]), 1e-6, "%s min" % name)
		assert_almost_eq(float(r["max"]), float(want[name][1]), 1e-6, "%s max" % name)
	assert_gte(float(rows["hill_rise_m"]["max"]), 2.0 * VillageTerrainParams.production().hill_rise_m,
		"hill_rise_m slider reaches at least 2x the default")


func test_no_hill_preset() -> void:
	var p := VillageTerrainParams.production()
	p.apply_preset(VillageTerrainParams.PRESET_NO_HILL)
	assert_eq(p.variant, 0)
	assert_almost_eq(p.hill_rise_m, 0.0, 1e-6, "No hill (A/B) = production with hill_rise_m 0")
	assert_eq(VillageTerrainParams.detect_preset_name(p), VillageTerrainParams.PRESET_NO_HILL)
	assert_eq(VillageTerrainParams.detect_preset_name(VillageTerrainParams.production()),
		VillageTerrainParams.PRESET_PRODUCTION, "production (with hill) is still Production")


func test_relief_fade_knobs_floored_at_one_metre() -> void:
	for name in ["hero_relief_fade_m", "plaza_relief_fade_m", "pond_relief_fade_m", "open_lawn_pad_fade_m"]:
		for row: Dictionary in VillageTerrainKnobSpec.all_knobs():
			if row["name"] == name:
				assert_almost_eq(float(row["min"]), VillageTerrain.RELIEF_FADE_FLOOR_M, 1e-6,
					"%s slider min is the 1 m floor" % name)
	# The sampler treats anything below the floor as the floor (a 0 knob no longer makes a cliff).
	var layout := VillageLayout.generate(7)
	var zero := _fades_zero(VillageTerrainParams.production())
	var floor_p := VillageTerrainParams.production()
	floor_p.hero_relief_fade_m = 1.0
	floor_p.plaza_relief_fade_m = 1.0
	floor_p.pond_relief_fade_m = 1.0
	floor_p.open_lawn_pad_fade_m = 1.0
	VillageTerrain.clear_knoll_centres_cache()
	var t_seed := VillageTerrain.terrain_seed(layout, zero)
	var pts: Array[Vector2] = [layout.plaza_rect.get_center() + Vector2(layout.plaza_rect.size.x * 0.5 + 0.4, 0.0),
		layout.pond_center + Vector2(6.0, 0.0), VillageLayout.HERO_DOOR_STOOP + Vector2(0.0, -7.5)]
	for xz in pts:
		assert_almost_eq(VillageTerrain.detail_y(xz, layout, zero, t_seed),
			VillageTerrain.detail_y(xz, layout, floor_p, t_seed), 1e-5, "fade 0 == fade 1 m at %s" % xz)
	VillageTerrain.clear_knoll_centres_cache()


# ── Hill profile P (AC 2) ─────────────────────────────────────────────────────

func test_hill_rise_zero_makes_hill_layer_exactly_zero() -> void:
	var layout := VillageLayout.generate(7)
	var p := VillageTerrainParams.production()
	p.hill_rise_m = 0.0
	assert_eq(VillageTerrain.hero_datum_y(layout, p), 0.0, "no hill: hero datum 0")
	var g := layout.hamlet_centre_xz
	for ix in range(-12, 13):
		for iz in range(-12, 13):
			var xz := g + Vector2(ix, iz) * 4.5
			assert_eq(VillageTerrain.hill_y(xz, layout, p), 0.0, "hill_y == 0 at %s" % xz)


func test_hill_crest_flat_and_monotone_along_rays() -> void:
	for seed: int in [1, 7, 25]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var p := VillageTerrainParams.production()
		var c := VillageTerrain.hill_centre(layout, p)
		var r_c := VillageTerrain.hill_crest_r(p)
		for i in range(24):
			var a := TAU * float(i) / 24.0
			var dir := Vector2(sin(a), cos(a))
			var prev := INF
			var d := 0.0
			while d < 90.0:
				var xz := c + dir * d
				if xz.distance_to(layout.hamlet_centre_xz) >= layout.lawn_radius:
					break
				var hv := VillageTerrain.hill_y(xz, layout, p)
				if d <= r_c:
					assert_almost_eq(hv, p.hill_rise_m, 1e-5, "seed %d crest flat at d=%.1f" % [seed, d])
				assert_lte(hv, prev + 1e-6, "seed %d hill non-increasing along ray %d at d=%.1f" % [seed, i, d])
				prev = hv
				d += 0.5


func test_hill_is_zero_in_the_rim_band() -> void:
	for seed: int in [3, 7, 12, 25]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var p := VillageTerrainParams.production()
		var g := layout.hamlet_centre_xz
		for i in range(72):
			var a := TAU * float(i) / 72.0
			for r in [layout.lawn_radius - p.rim_blend_m, layout.lawn_radius - 2.0, layout.lawn_radius - 0.1]:
				var xz: Vector2 = g + Vector2(sin(a), cos(a)) * float(r)
				assert_eq(VillageTerrain.hill_y(xz, layout, p), 0.0, "seed %d hill 0 in rim band at %s" % [seed, xz])


# ── Datum and fall (AC 1, 2) ──────────────────────────────────────────────────

func test_hero_datum_and_flat_hero_disc_seed7() -> void:
	var layout := VillageLayout.generate(7)
	var p := VillageTerrainParams.production()
	VillageTerrain.clear_knoll_centres_cache()
	var t_seed := VillageTerrain.terrain_seed(layout, p)
	var datum := VillageTerrain.hero_datum_y(layout, p)
	assert_almost_eq(datum, p.hill_rise_m, 1e-5, "hero datum = crest = hill_rise_m (hill centred on the hero)")
	var stoop := VillageLayout.HERO_DOOR_STOOP
	for i in range(16):
		var a := TAU * float(i) / 16.0
		for r in [0.0, 2.0, 4.5, p.hero_flat_r_m - 0.05]:
			var xz: Vector2 = stoop + Vector2(sin(a), cos(a)) * float(r)
			assert_almost_eq(_h(xz, layout, p, t_seed), datum, 0.02, "hero disc at datum (%s)" % xz)
	VillageTerrain.clear_knoll_centres_cache()


func test_variant1_and_classic_have_no_datum_offset() -> void:
	var layout := VillageLayout.generate(7)
	var flat := VillageTerrainParams.production()
	flat.variant = 1
	assert_eq(VillageTerrain.hero_datum_y(layout, flat), 0.0, "variant 1: datum 0")
	assert_eq(VillageTerrain.hill_y(layout.hamlet_centre_xz, layout, flat), 0.0, "variant 1: no hill")
	var classic := VillageLayout.authored()
	assert_eq(VillageTerrain.hero_datum_y(classic, VillageTerrainParams.production()), 0.0, "classic: datum 0")


func test_fall_to_outermost_cottage_every_seed() -> void:
	## AC 2: the hero stands >= one cottage (6.84 m ridge) above the outermost cottage centre.
	var worst := INF
	var worst_seed := -1
	var checked := 0
	for seed in range(1, 31):
		if seed == _FALLBACK_SEED:
			continue
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var p := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, p)
		var fall := _h(VillageLayout.HERO_DOOR_STOOP, layout, p, t_seed) \
			- _h(_outermost_cottage_centre(layout), layout, p, t_seed)
		gut.p("seed %d fall to outermost cottage %.2f m" % [seed, fall])
		if fall < worst:
			worst = fall
			worst_seed = seed
		checked += 1
	VillageTerrain.clear_knoll_centres_cache()
	assert_gt(checked, 25, "29 seeds checked")
	assert_gte(worst, RIDGE_M, "worst fall %.2f m (seed %d) >= ridge %.2f m" % [worst, worst_seed, RIDGE_M])


# ── Dark lines (AC 5) ─────────────────────────────────────────────────────────

func test_path_quiet_is_quieter_beside_paths_ivy_sx7x() -> void:
	## ivy-sx7x: the path-quiet multiplier was inverted (full noise beside paths, quiet floor on
	## open lawn). Base noise must be quieter on a path than 5 m away from it.
	var p := VillageTerrainParams.production()
	assert_lt(VillageTerrain.path_quiet_gain(0.0, p), 0.6, "on the path: quiet floor")
	assert_almost_eq(VillageTerrain.path_quiet_gain(VillageTerrain.PATH_CORRIDOR_OUTER_M, p), 1.0, 1e-6,
		"5 m from the path: full base noise")
	assert_almost_eq(VillageTerrain.path_quiet_gain(30.0, p), 1.0, 1e-6, "open lawn: full base noise")


func test_no_step_at_path_corridor_line() -> void:
	## AC 5: the 5 m corridor edge used to switch from the graded path spine to the field (C0
	## step), which the 2 m lawn mesh turned into a dark band beside every path.
	var layout := VillageLayout.generate(7)
	for wide in [false, true]:
		var p := VillageTerrainParams.production()
		if wide:
			_wide(p)
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, p)
		var worst := 0.0
		var worst_raw := 0.0
		var n := 0
		for polyline: Variant in layout.path_polylines():
			var pts: Array = polyline as Array
			for i in range(pts.size() - 1):
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				if a.distance_to(b) < 0.2:
					continue
				var mid := a.lerp(b, 0.5)
				var nrm := (b - a).normalized().orthogonal()
				for s: float in [-1.0, 1.0]:
					var pin: Vector2 = mid + nrm * s * 4.95
					var pout: Vector2 = mid + nrm * s * 5.05
					if VillageTerrain._min_dist_to_paths(pin, layout) < 4.9:
						continue
					if VillageTerrain._min_dist_to_paths(pout, layout) < 5.0:
						continue
					if pin.distance_to(layout.hamlet_centre_xz) > layout.lawn_radius - 1.0:
						continue
					worst = maxf(worst, _step_across(pin, pout, layout, p, t_seed))
					worst_raw = maxf(worst_raw, _raw_across(pin, pout, layout, p, t_seed))
					n += 1
		gut.p("corridor line wide=%s samples=%d worst step %.4f m (raw 0.1 m difference incl. slope %.4f m)" % [
			wide, n, worst, worst_raw])
		assert_gt(n, 10, "corridor line sampled")
		assert_lte(worst, 0.02, "wide=%s: step across the 5 m corridor line %.4f m <= 0.02 m" % [wide, worst])
	VillageTerrain.clear_knoll_centres_cache()


func test_no_step_at_feature_rings_with_fades_zero() -> void:
	## AC 5: with every relief fade at 0 the hero ring, plaza edge and pond ring used to be cliffs.
	var layout := VillageLayout.generate(7)
	var p := _fades_zero(VillageTerrainParams.production())
	VillageTerrain.clear_knoll_centres_cache()
	var t_seed := VillageTerrain.terrain_seed(layout, p)
	var worst := {"hero": 0.0, "plaza": 0.0, "pond": 0.0}
	var stoop := VillageLayout.HERO_DOOR_STOOP
	var r_rim := VillagePondSite.BANK_OUTER_M + p.pond_rim_extra_m
	for i in range(48):
		var a := TAU * float(i) / 48.0
		var dir := Vector2(sin(a), cos(a))
		var hr := p.hero_flat_r_m
		worst["hero"] = maxf(worst["hero"], _step_across(
			stoop + dir * (hr - 0.05), stoop + dir * (hr + 0.05), layout, p, t_seed))
		var pr := r_rim * 0.85
		worst["pond"] = maxf(worst["pond"], _step_across(
			layout.pond_center + dir * (pr - 0.05), layout.pond_center + dir * (pr + 0.05), layout, p, t_seed))
	var rect := layout.plaza_rect
	for i in range(24):
		var t := (float(i) + 0.5) / 24.0
		var top := Vector2(lerpf(rect.position.x, rect.end.x, t), rect.position.y)
		var bottom := Vector2(lerpf(rect.position.x, rect.end.x, t), rect.end.y)
		var left := Vector2(rect.position.x, lerpf(rect.position.y, rect.end.y, t))
		var right := Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, t))
		for e: Array in [[top, Vector2(0, -1)], [bottom, Vector2(0, 1)], [left, Vector2(-1, 0)], [right, Vector2(1, 0)]]:
			var q: Vector2 = e[0]
			var nn: Vector2 = e[1]
			worst["plaza"] = maxf(worst["plaza"], _step_across(q - nn * 0.05, q + nn * 0.05, layout, p, t_seed))
	gut.p("fades 0: worst step hero %.4f plaza %.4f pond %.4f" % [worst["hero"], worst["plaza"], worst["pond"]])
	for k: String in worst:
		assert_lte(worst[k], 0.05, "fades 0: step at the %s ring %.4f m <= 0.05 m" % [k, worst[k]])
	VillageTerrain.clear_knoll_centres_cache()


# ── Pond (AC 6) ───────────────────────────────────────────────────────────────

func _check_bank_drape(p: VillageTerrainParams, label: String) -> void:
	var layout := VillageLayout.generate(7)
	VillageTerrain.clear_knoll_centres_cache()
	var shape := VillagePondShape.at(layout.pond_center)
	VillagePondShape.set_active(shape)
	var lut := VillageTerrain.mesh_surface_lut(layout, p)
	var y_fn := func(xz: Vector2) -> float:
		return VillageTerrain.mesh_surface_y_from_lut(xz, layout, p, lut) + VillageBackdrop.POND_BANK_DRAPE_M
	var mesh := VillageBackdrop.build_pond_ring_mesh(
		VillagePondShape.water_render_outline_xz(), VillagePondShape.bank_outer_outline_xz(),
		0.0, y_fn, VillageBackdrop.pond_bank_max_edge_m(p), VillageBackdrop.POND_BANK_REFINE_TOL_M)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := -INF
	var bary := [Vector3(1, 1, 1) / 3.0, Vector3(0.5, 0.5, 0), Vector3(0, 0.5, 0.5), Vector3(0.5, 0, 0.5),
		Vector3(1, 0, 0), Vector3(0.7, 0.2, 0.1)]
	for t in range(0, verts.size(), 3):
		for bw: Vector3 in bary:
			var v: Vector3 = verts[t] * bw.x + verts[t + 1] * bw.y + verts[t + 2] * bw.z
			var d := v.y - VillageTerrain.mesh_surface_y_from_lut(Vector2(v.x, v.z), layout, p, lut)
			lo = minf(lo, d)
			hi = maxf(hi, d)
	gut.p("%s: bank minus lawn %.4f .. %.4f m over %d tris" % [label, lo, hi, verts.size() / 3])
	assert_gte(lo, -0.0005, "%s: bank never below the rendered lawn (min %.4f)" % [label, lo])
	assert_lte(hi, 0.05, "%s: bank at most 5 cm above the rendered lawn (max %.4f)" % [label, hi])
	VillageTerrain.clear_knoll_centres_cache()


func test_pond_bank_draped_on_rendered_lawn_defaults() -> void:
	_check_bank_drape(VillageTerrainParams.production(), "defaults")


func test_pond_bank_draped_on_rendered_lawn_wide() -> void:
	_check_bank_drape(_fades_zero(_wide(VillageTerrainParams.production())), "wide")


func _check_water(p: VillageTerrainParams, label: String) -> void:
	var layout := VillageLayout.generate(7)
	VillageTerrain.clear_knoll_centres_cache()
	var t_seed := VillageTerrain.terrain_seed(layout, p)
	var water := VillageTerrain.pond_water_y(layout, p, t_seed)
	var outline := VillagePondShape.at(layout.pond_center).bank_outer_outline_world_xz()
	var lo := INF
	for xz in outline:
		lo = minf(lo, _h(xz, layout, p, t_seed))
	var floor_y := _h(layout.pond_center, layout, p, t_seed)
	gut.p("%s: water %.3f  bank outline min %.3f  basin floor %.3f" % [label, water, lo, floor_y])
	assert_lte(water, lo - 0.02 + 1e-4, "%s: water at least 2 cm below the lowest bank outline point" % label)
	assert_gt(water, floor_y, "%s: water above the basin floor" % label)
	VillageTerrain.clear_knoll_centres_cache()


func test_pond_water_level_rules_defaults() -> void:
	_check_water(VillageTerrainParams.production(), "defaults")


func test_pond_water_level_rules_wide() -> void:
	_check_water(_fades_zero(_wide(VillageTerrainParams.production())), "wide")


# ── Slope limits (AC 4) ───────────────────────────────────────────────────────

func test_hero_ring_slope_with_hill() -> void:
	## Hero ring (hero_flat_r_m .. + hero_skirt_m) stays <= 8° (the crest is flat to r_c).
	for seed: int in [7, 8, 15, 17, 25, 27]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var p := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, p)
		var stoop := VillageLayout.HERO_DOOR_STOOP
		var worst := 0.0
		var worst_xz := Vector2.ZERO
		for i in range(64):
			var a := TAU * float(i) / 64.0
			var r := p.hero_flat_r_m + 0.3
			## Slope stencil (±0.545 m) inside the ring; the flank starts at the crest edge (10 m).
			while r <= p.hero_flat_r_m + p.hero_skirt_m - 0.55:
				var xz := stoop + Vector2(sin(a), cos(a)) * r
				r += 0.5
				if VillageTerrain.in_any_pad_terrace(xz, layout, p, t_seed):
					continue
				var s := VillageTerrain.sample_slope_deg(xz, layout, p, t_seed)
				if s > worst:
					worst = s
					worst_xz = xz
		assert_lte(worst, 8.0, "seed %d hero ring slope %.2f° at %s <= 8°" % [seed, worst, worst_xz])
	VillageTerrain.clear_knoll_centres_cache()


func test_rim_band_slope_and_seam_seed7() -> void:
	## Rim band (r >= lawn_radius - rim_blend_m) stays <= 8° and the hill is 0 there (AC-VT8 seam).
	for seed: int in [7, 25]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var p := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, p)
		var g := layout.hamlet_centre_xz
		var worst := 0.0
		for i in range(96):
			var a := TAU * float(i) / 96.0
			var r := layout.lawn_radius - p.rim_blend_m + 0.25
			while r <= layout.lawn_radius - 0.6:
				var xz := g + Vector2(sin(a), cos(a)) * r
				r += 0.75
				if VillageTerrain.in_any_pad_terrace(xz, layout, p, t_seed):
					continue
				worst = maxf(worst, VillageTerrain.sample_slope_deg(xz, layout, p, t_seed))
		assert_lte(worst, 8.0, "seed %d rim band slope %.2f° <= 8°" % [seed, worst])
	VillageTerrain.clear_knoll_centres_cache()


func test_open_lawn_flank_and_cliff_guard() -> void:
	## Open-lawn hill flank <= 30° (sample_slope_deg, pads / paths / pond masked) and no rendered
	## lawn cell (mesh-step LUT, the cells the 2 m mesh draws) steeper than 40° anywhere.
	for seed: int in [3, 7, 25]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var p := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, p)
		var g := layout.hamlet_centre_xz
		var flank := 0.0
		var flank_xz := Vector2.ZERO
		var x := -layout.lawn_radius
		while x <= layout.lawn_radius:
			var z := -layout.lawn_radius
			while z <= layout.lawn_radius:
				var xz := g + Vector2(x, z)
				z += 2.0
				if xz.distance_to(g) > layout.lawn_radius - 0.6:
					continue
				if VillageTerrain.in_any_pad_terrace(xz, layout, p, t_seed):
					continue
				if VillageTerrain._min_dist_to_paths(xz, layout) < 5.0:
					continue
				if xz.distance_to(layout.pond_center) < VillageTerrain.pond_terrace_outer_m(layout, p, t_seed):
					continue
				var s := VillageTerrain.sample_slope_deg(xz, layout, p, t_seed)
				if s > flank:
					flank = s
					flank_xz = xz
			x += 2.0
		var cell := VillageTerrain.max_mesh_cell_slope_deg(layout, p)
		gut.p("seed %d open-lawn flank %.1f° at %s, steepest lawn cell %.1f°" % [seed, flank, flank_xz, cell])
		assert_lte(flank, 30.0, "seed %d open-lawn flank %.2f° at %s <= 30°" % [seed, flank, flank_xz])
		assert_lte(cell, 40.0, "seed %d steepest rendered lawn cell %.2f° <= 40°" % [seed, cell])
	VillageTerrain.clear_knoll_centres_cache()


func test_lane_path_slope_with_hill() -> void:
	## Lane polylines outside pad terraces stay <= max_path_slope_deg (18°), 0.5 m chords.
	for seed: int in [1, 7, 12, 25]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var p := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, p)
		var cap := tan(deg_to_rad(p.max_path_slope_deg))
		var worst := 0.0
		var worst_xz := Vector2.ZERO
		for polyline: Variant in layout.path_polylines():
			var pts: Array = polyline as Array
			for i in range(pts.size() - 1):
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				var nseg := maxi(int(a.distance_to(b) / 0.5), 1)
				for k in range(nseg):
					var p0 := a.lerp(b, float(k) / nseg)
					var p1 := a.lerp(b, float(k + 1) / nseg)
					var l := p0.distance_to(p1)
					if l < 0.05:
						continue
					if VillageTerrain.in_any_pad_terrace(p0, layout, p, t_seed) \
							or VillageTerrain.in_any_pad_terrace(p1, layout, p, t_seed):
						continue
					var gr := absf(_h(p1, layout, p, t_seed) - _h(p0, layout, p, t_seed)) / l
					if gr > worst:
						worst = gr
						worst_xz = p0
		assert_lte(worst, cap + 0.005, "seed %d lane grade %.1f° at %s <= %.0f°" % [
			seed, rad_to_deg(atan(worst)), worst_xz, p.max_path_slope_deg])
	VillageTerrain.clear_knoll_centres_cache()


func test_total_pad_bank_le_35_deg() -> void:
	## Cut + fill around each terraced cottage pad: total grade walking out of the pad <= 35°.
	for seed: int in [1, 7, 12, 22, 25]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var p := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, p)
		var cap := tan(deg_to_rad(35.0))
		var worst := 0.0
		var worst_xz := Vector2.ZERO
		for spec: Dictionary in layout.cottages:
			var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(p.pad_margin_m)
			var reach := VillageTerrain.pad_terrace_reach_m(layout, p, t_seed)
			for i in range(16):
				var a := TAU * float(i) / 16.0
				var dir := Vector2(sin(a), cos(a))
				var q := rect.get_center()
				while VillageTerrain._rect_sdf(q, rect) < 0.0:
					q += dir * 0.25
				var prev := _h(q, layout, p, t_seed)
				var walked := 0.0
				while walked < reach:
					var nq := q + dir * 0.5
					var hn := _h(nq, layout, p, t_seed)
					var gr := absf(hn - prev) / 0.5
					if gr > worst and VillageTerrain._min_dist_to_paths(nq, layout) > 1.5:
						worst = gr
						worst_xz = nq
					prev = hn
					q = nq
					walked += 0.5
		assert_lte(worst, cap, "seed %d total pad bank %.1f° at %s <= 35°" % [seed, rad_to_deg(atan(worst)), worst_xz])
	VillageTerrain.clear_knoll_centres_cache()
