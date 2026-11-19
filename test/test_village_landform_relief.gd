## ivy-82zn.14.14 (WP1) — AC-LT-RELIEF and AC-LT-SLOPE on the fitted field (SD-VILLAGE-TERRAIN-23).
extends GutTest

const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")

const _SEEDS: Array[int] = [1, 7, 12]
const _VILLAGE_R := 46.0


func _field(seed: int):
	var layout := VillageLayout.generate(seed)
	var p := VillageTerrainParams.production()
	return VillageTerrain.field(layout, p)


func _in_pond_basin(f, xz: Vector2) -> bool:
	var p: VillageTerrainParams = f.params
	var r := VillagePondSite.BANK_OUTER_M + p.pond_rim_extra_m + p.pond_skirt_m
	return xz.distance_to(f.layout.pond_center) <= r


func _in_fit_ring(f, xz: Vector2) -> bool:
	## Inside a hero / pad core or ring (AC-LT-SLOPE excludes them).
	for s: Dictionary in f.sites:
		var kind: String = s["kind"]
		if kind != "hero" and kind != "cottage":
			continue
		if f.site_sdf(s, xz) <= float(s["w"]):
			return true
	return false


func _relief(seed: int) -> Dictionary:
	var f = _field(seed)
	var g: Vector2 = f.layout.hamlet_centre_xz
	var lo := INF
	var hi := -INF
	var x := -_VILLAGE_R
	while x <= _VILLAGE_R:
		var z := -_VILLAGE_R
		while z <= _VILLAGE_R:
			var xz := g + Vector2(x, z)
			if Vector2(x, z).length() <= _VILLAGE_R and not _in_pond_basin(f, xz):
				var y: float = f.sample_y(xz)
				lo = minf(lo, y)
				hi = maxf(hi, y)
			z += 2.0
		x += 2.0
	var storey := 0.0
	for s: Dictionary in f.sites:
		if s["kind"] == "cottage":
			storey = maxf(storey, absf(float(s["target"]) - float(f.y_hero)))
	return {"span": hi - lo, "storey": storey}


## The storey half of AC-LT-RELIEF (max |T_i − y_hero| ≥ 3 m) was pending until WP3's spacing and
## reach (ivy-82zn.14.18, 16 m / 46 m since 2026-11-18). Asserted from WP3 on; never weakened.


func test_ac_lt_relief_probe_seeds() -> void:
	for seed in _SEEDS:
		var r := _relief(seed)
		gut.p("AC-LT-RELIEF seed %d: span %.2f m, storey max |T_i - y_hero| %.2f m" % [seed, r["span"], r["storey"]])
		assert_between(float(r["span"]), 5.0, 9.0, "seed %d fitted village span %.2f m" % [seed, r["span"]])
		assert_gte(float(r["storey"]), 3.0, "seed %d storey %.2f m" % [seed, r["storey"]])


func test_ac_lt_relief_sweep() -> void:
	## Span over the 20-seed sweep (≥ 18 / 20 of the generated layouts; generator fallbacks such as
	## seed 19 are not terrain and are skipped).
	var ok := 0
	var n := 0
	var notes := PackedStringArray()
	var storey_ok := 0
	var soft := 0
	for seed in range(1, 21):
		var layout := VillageLayout.generate(seed)
		if layout.fallback or not layout.is_generated:
			continue
		n += 1
		var r := _relief(seed)
		if float(r["span"]) >= 5.0 and float(r["span"]) <= 9.0:
			ok += 1
		else:
			notes.append("%d: span %.2f" % [seed, r["span"]])
		if bool(layout.terrain_diag.get("storey_soft", false)):
			soft += 1
		if float(r["storey"]) >= 3.0:
			storey_ok += 1
		else:
			notes.append("%d: storey %.2f" % [seed, r["storey"]])
	gut.p("AC-LT-RELIEF sweep: span %d / %d, storey %d / %d (%s)" % [ok, n, storey_ok, n, ", ".join(notes)])
	assert_gte(ok, mini(18, n - 2), "AC-LT-RELIEF span sweep %d / %d (fails: %s)" % [ok, n, ", ".join(notes)])
	## Storey floor restated 2026-11-18 to >= 17 / 20 (SD-VILLAGE-TERRAIN-28 §2: the sampler cannot
	## reach the remaining storey ground; site-first placement is out of scope).
	assert_eq(n, 20, "all 20 seeds generated")
	assert_gte(storey_ok, 17, "AC-LT-RELIEF storey >= 3 m sweep %d / %d (SD-28)" % [storey_ok, n])
	gut.p("AC-LT-RELIEF storey_soft on %d / %d seeds" % [soft, n])
	assert_lte(soft, 3, "storey_soft on <= 3 / 20 seeds (SD-23 restated)")


func test_ac_lt_slope_outside_rings() -> void:
	for seed in _SEEDS:
		var f = _field(seed)
		var g: Vector2 = f.layout.hamlet_centre_xz
		var slopes: Array[float] = []
		var x := -_VILLAGE_R
		while x <= _VILLAGE_R:
			var z := -_VILLAGE_R
			while z <= _VILLAGE_R:
				var xz := g + Vector2(x, z)
				if Vector2(x, z).length() <= _VILLAGE_R and not _in_pond_basin(f, xz) \
						and not _in_fit_ring(f, xz):
					slopes.append(VillageTerrain.sample_slope_deg(xz, f.layout, f.params, 0))
				z += 2.0
			x += 2.0
		slopes.sort()
		var p95: float = slopes[int(slopes.size() * 0.95)]
		var mx: float = slopes[slopes.size() - 1]
		gut.p("AC-LT-SLOPE seed %d: open-land p95 %.2f°, max %.1f°" % [seed, p95, mx])
		## Human decision 2026-11-18 (option A, stopgap; proper fix ivy-82zn.14.29): p95 limit 14.0 ->
		## 14.1° to accept seed 7's measured 14.06° on its SD-28 storey offset. Max 24° unchanged.
		assert_lte(p95, 14.1, "seed %d open-land slope p95 %.2f°" % [seed, p95])
		assert_lte(mx, 24.0, "seed %d open-land slope max %.1f°" % [seed, mx])
