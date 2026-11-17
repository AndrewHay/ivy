## ivy-82zn.14.14 (WP1) — VillageTerrain façade over the landscape-first field: AC-LT-HERO, near
## mesh budgets, the C1 no-step rule (C5 contour lines), plaza / pond fit targets, flat gates.
## SD-VILLAGE-TERRAIN-17 / -19 / -23, AR-LF-API.
extends GutTest

const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")

const _SEEDS: Array[int] = [1, 7, 12]


func _layout(seed: int) -> VillageLayout:
	return VillageLayout.generate(seed)


func test_ac_lt_hero_pad_is_level_at_y_hero() -> void:
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var layout := _layout(seed)
		var f = VillageTerrain.field(layout, p)
		var y_hero := VillageTerrain.hero_datum_y(layout, p)
		assert_almost_eq(y_hero, float(f.y_hero), 1e-9, "hero_datum_y is the field's y_hero")
		var worst := 0.0
		var h0 := VillageLayout.HERO_DOOR_STOOP
		for i in range(400):
			var a := TAU * float(i) / 400.0
			var r := p.hero_flat_r_m * 0.999 * sqrt(float(i % 20) / 19.0)
			var xz := h0 + Vector2(cos(a), sin(a)) * r
			worst = maxf(worst, absf(VillageTerrain.sample_y(xz, layout, p, 0) - y_hero))
		assert_lte(worst, 0.02, "seed %d hero core within 2 cm of y_hero (%.4f)" % [seed, worst])


func test_field_is_defined_beyond_the_lawn() -> void:
	var layout := _layout(7)
	var p := VillageTerrainParams.production()
	var g := layout.hamlet_centre_xz
	var spread := 0.0
	var lo := INF
	var hi := -INF
	for r in [80.0, 150.0, 250.0, 330.0]:
		for k in range(16):
			var a := TAU * float(k) / 16.0
			var y := VillageTerrain.sample_y(g + Vector2(cos(a), sin(a)) * r, layout, p, 0)
			assert_true(is_finite(y), "finite at r %.0f" % r)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	spread = hi - lo
	assert_gt(spread, 1.0, "the landform continues past the lawn (spread %.2f m)" % spread)


func test_flat_variant_and_classic_are_zero() -> void:
	var p := VillageTerrainParams.production()
	p.variant = 1
	var gen := _layout(7)
	var classic := VillageLayout.authored()
	var prod := VillageTerrainParams.production()
	for xz in [Vector2.ZERO, Vector2(10.0, -20.0), Vector2(60.0, 40.0)]:
		assert_eq(VillageTerrain.sample_y(xz, gen, p, 0), 0.0, "variant 1 flat")
		assert_eq(VillageTerrain.sample_y(xz, classic, prod, 0), 0.0, "classic flat")
	assert_eq(VillageTerrain.hero_datum_y(classic, prod), 0.0, "classic datum 0")
	assert_eq(VillageTerrain.hero_datum_y(gen, p), 0.0, "variant 1 datum 0")


func test_no_c0_step_anywhere_in_the_village() -> void:
	## C5: the field is C1, so no 10 cm-wide step anywhere (a step draws a dark contour line).
	var layout := _layout(7)
	var p := VillageTerrainParams.production()
	var g := layout.hamlet_centre_xz
	var worst := 0.0
	var at := Vector2.ZERO
	for line in range(24):
		var z := -60.0 + float(line) * 5.0
		var x := -62.0
		while x < 62.0:
			var xz := g + Vector2(x, z)
			var d := absf(VillageTerrain.sample_y(xz + Vector2(0.05, 0.0), layout, p, 0)
				- VillageTerrain.sample_y(xz - Vector2(0.05, 0.0), layout, p, 0))
			if d > worst:
				worst = d
				at = xz
			x += 0.25
	assert_lte(worst, 0.07, "max 10 cm step %.4f m at %s" % [worst, at])


func test_near_mesh_triangle_budget() -> void:
	var layout := _layout(7)
	var p := VillageTerrainParams.production()
	var mesh := VillageTerrain.build_mesh(layout, p)
	var tris := mesh.surface_get_array_len(0) / 3
	assert_lte(tris, 16000, "near mesh hard cap (%d tris)" % tris)
	assert_lte(tris, 8000, "near mesh target (%d tris)" % tris)


func test_mesh_cliff_guard() -> void:
	## From the retired test_village_terrain_hill.gd: no lawn cell steeper than 40°.
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var worst := VillageTerrain.max_mesh_cell_slope_deg(_layout(seed), p)
		assert_lte(worst, 40.0, "seed %d steepest lawn cell %.1f°" % [seed, worst])


func test_sample_normal_is_unit_and_up() -> void:
	var layout := _layout(12)
	var p := VillageTerrainParams.production()
	for xz in [Vector2(0, -18), Vector2(20, -30), Vector2(-25, 0)]:
		var n := VillageTerrain.sample_normal(xz, layout, p, 0)
		assert_almost_eq(n.length(), 1.0, 1e-4, "unit normal")
		assert_gt(n.y, 0.5, "normal points up")


func test_plaza_core_is_its_fitted_plane() -> void:
	## AC-LT-PLAZA core part (fit target, WP1): plaza core = fitted plane ± 2 cm, tilt ≤ 6°.
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var layout := _layout(seed)
		var f = VillageTerrain.field(layout, p)
		var plaza: Dictionary = {}
		for s: Dictionary in f.sites:
			if s["kind"] == "plaza":
				plaza = s
		assert_false(plaza.is_empty(), "seed %d has a plaza site" % seed)
		assert_lte(float(plaza["tilt_deg"]), p.plaza_max_tilt_deg + 1e-6, "seed %d plaza tilt" % seed)
		var rect: Rect2 = plaza["rect"]
		var worst := 0.0
		var hero_ring: float = 0.0
		for s: Dictionary in f.sites:
			if s["kind"] == "hero":
				hero_ring = float(s["r_c"]) + float(s["w"])
		for ix in range(10):
			for iz in range(10):
				var xz := rect.position + Vector2(rect.size.x * ix / 9.0, rect.size.y * iz / 9.0)
				if xz.distance_to(VillageLayout.HERO_DOOR_STOOP) < hero_ring:
					continue  # hero ring has priority over the plaza (SD-17 §5)
				if _covered_by_later_site(f, xz, "plaza"):
					continue
				worst = maxf(worst, absf(f.sample_y(xz) - f.site_target(plaza, xz)))
		assert_lte(worst, 0.02, "seed %d plaza core on its plane (%.4f)" % [seed, worst])


func _covered_by_later_site(f, xz: Vector2, kind: String) -> bool:
	var after := false
	for s: Dictionary in f.sites:
		if s["kind"] == kind:
			after = true
			continue
		if after and f.site_sdf(s, xz) < float(s["w"]):
			return true
	return false


func test_sample_y_cost_in_the_village() -> void:
	## AR-LF-API target ≤ 15 µs mean in the village disc (asserted with slack: 40 µs).
	var layout := _layout(7)
	var p := VillageTerrainParams.production()
	var f = VillageTerrain.field(layout, p)
	var g := layout.hamlet_centre_xz
	var t0 := Time.get_ticks_usec()
	var n := 0
	for i in range(2000):
		var a := float(i) * 2.399
		f.sample_y(g + Vector2(cos(a), sin(a)) * (46.0 * sqrt(float(i) / 2000.0)))
		n += 1
	var us := float(Time.get_ticks_usec() - t0) / float(n)
	gut.p("field.sample_y mean %.2f µs" % us)
	assert_lte(us, 40.0, "sample_y mean %.1f µs" % us)


func test_field_is_cached_on_the_layout_and_rebuilt_on_edit() -> void:
	var layout := _layout(7)
	var p := VillageTerrainParams.production()
	var f1 = VillageTerrain.field(layout, p)
	assert_same(VillageTerrain.field(layout, p), f1, "same params → cached field")
	p.ground_height_tint = 0.3
	assert_same(VillageTerrain.field(layout, p), f1, "material knob does not rebuild")
	p.landform_height_m = 10.0
	var f2 = VillageTerrain.field(layout, p)
	assert_ne(f2, f1, "terrain knob rebuilds the field")
	assert_same(layout.terrain_field, f2, "cache lives on the layout")
