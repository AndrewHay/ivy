## ivy-82zn.14.16 (WP2) — plaza fit (SD-VILLAGE-TERRAIN-19 plaza row, AC-LT-PLAZA) and the ivy-35zj
## re-check under the landscape-first plaza fields (plaza_max_tilt_deg / plaza_ring_m).
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

const _SEEDS: Array[int] = [1, 7, 12]


func _plaza(f) -> Dictionary:
	for s: Dictionary in f.sites:
		if s["kind"] == "plaza":
			return s
	return {}


func _covered_by_later(f, site: Dictionary, xz: Vector2) -> bool:
	var after := false
	for s: Dictionary in f.sites:
		if s == site:
			after = true
			continue
		if after and f.site_sdf(s, xz) < float(s["w"]):
			return true
	return false


func test_ac_lt_plaza_core_on_its_plane_and_tilt_capped() -> void:
	## AC-LT-PLAZA: the plaza core matches its fitted plane within 0.02 m (where no later site's ring
	## reaches), plane tilt ≤ plaza_max_tilt_deg; the raw tilt passes the search's 10° hard rule.
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var layout := VillageLayout.generate(seed)
		var f = VillageTerrain.field(layout, p)
		var s := _plaza(f)
		assert_false(s.is_empty(), "seed %d plaza site" % seed)
		assert_lte(float(s["tilt_deg"]), p.plaza_max_tilt_deg + 1e-6, "seed %d plaza tilt" % seed)
		assert_lte(float(s["raw_tilt_deg"]), VillageLandform.PLAZA_RAW_TILT_MAX_DEG, "seed %d raw tilt ≤ 10°" % seed)
		assert_false(bool(f.diag.get("plaza_steep", false)), "seed %d plaza_steep unset" % seed)
		var rect: Rect2 = s["rect"]
		var worst := 0.0
		var n := 0
		for ix in range(19):
			for iz in range(19):
				var xz: Vector2 = rect.position + rect.size * Vector2(ix / 18.0, iz / 18.0)
				if _covered_by_later(f, s, xz):
					continue
				n += 1
				worst = maxf(worst, absf(f.sample_y(xz) - f.site_target(s, xz)))
		assert_gt(n, 100, "seed %d enough uncovered plaza samples (%d)" % [seed, n])
		assert_lte(worst, 0.02, "seed %d plaza core on its plane (%.4f m)" % [seed, worst])


func test_plaza_plane_is_the_shared_helper() -> void:
	## SD-19 step 2: one implementation — the field's plaza site equals the static helper on U.
	var p := VillageTerrainParams.production()
	var layout := VillageLayout.generate(7)
	var f = VillageTerrain.field(layout, p)
	var s := _plaza(f)
	var h := VillageTerrainField.plaza_site(Callable(f, "sample_unfit_y"), layout.plaza_rect, p, float(s["w"]))
	for k in ["a", "b", "c", "tilt_deg", "raw_tilt_deg"]:
		assert_eq(float(s[k]), float(h[k]), "plaza %s" % k)


func _pond_floor(layout: VillageLayout, p: VillageTerrainParams) -> float:
	## Fresh field (no cache) with the plaza ring re-measured under p (the stored width would hide
	## plaza_ring_m), so only the plaza knobs differ between calls.
	var lay := layout
	lay.landform.erase("plaza_ring_w")
	var f := VillageTerrainField.build(lay, p, VillageTerrain.production_hills())
	return f.sample_y(lay.pond_center)


func test_ivy_35zj_plaza_knobs_do_not_move_the_pond_floor() -> void:
	## ivy-35zj (restated for the landscape-first fields): with pond_depth_m fixed, changing
	## plaza_max_tilt_deg across 0..10 and plaza_ring_m across 2..8 moves the seed 7 pond floor by
	## ≤ 0.1 m; default params unchanged.
	var p0 := VillageTerrainParams.production()
	var layout := VillageLayout.generate(7)
	var stored_floor: float = VillageTerrain.field(layout, p0).sample_y(layout.pond_center)
	var base := _pond_floor(layout, p0)
	assert_almost_eq(base, stored_floor, 1e-4, "default params: same floor as the production field")
	var worst := 0.0
	var notes := PackedStringArray()
	for tilt in [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]:
		var p := VillageTerrainParams.production()
		p.plaza_max_tilt_deg = tilt
		var d := absf(_pond_floor(layout, p) - base)
		worst = maxf(worst, d)
		notes.append("tilt %.0f: %.4f" % [tilt, d])
	for ring in [2.0, 3.5, 5.0, 6.5, 8.0]:
		var p2 := VillageTerrainParams.production()
		p2.plaza_ring_m = ring
		var d2 := absf(_pond_floor(layout, p2) - base)
		worst = maxf(worst, d2)
		notes.append("ring %.1f: %.4f" % [ring, d2])
	gut.p("ivy-35zj seed 7 pond floor %.3f m; moves: %s" % [base, ", ".join(notes)])
	assert_lte(worst, 0.1, "seed 7 pond floor moves ≤ 0.1 m (worst %.4f m)" % worst)
