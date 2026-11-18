## ivy-82zn.14.14 (WP1) / ivy-82zn.14.16 (WP2) — cottage pad and hero fit (SD-VILLAGE-TERRAIN-19,
## AC-LT-PAD / AC-LT-RING). WP2: sites are rejected in the plot sampler (site slope, measured ring
## with neighbour replay), the widths are stored (spec.ring_w, layout.landform.hero_ring_w) and the
## field uses them, so AC-LT-RING is asserted with 0 exceptions.
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

const _SEEDS: Array[int] = [1, 7, 12]
## AC-LT-RING sampling grid (SD-23: ≤ 0.5 m grid over 0 < sdf < w).
const _RING_GRID_M := 0.5


func _covered_by_later(f, site: Dictionary, xz: Vector2) -> bool:
	var after := false
	for s: Dictionary in f.sites:
		if s == site:
			after = true
			continue
		if after and f.site_sdf(s, xz) < float(s["w"]):
			return true
	return false


func test_pad_targets_are_core_means_of_the_capped_field() -> void:
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var layout := VillageLayout.generate(seed)
		var f = VillageTerrain.field(layout, p)
		var n := 0
		for s: Dictionary in f.sites:
			if s["kind"] != "cottage":
				continue
			n += 1
			var rect: Rect2 = s["rect"]
			var spec: Dictionary = layout.cottages[int(s["index"])]
			assert_eq(rect, VillageBackdrop.cottage_exterior_rect(spec).grow(p.pad_margin_m),
				"core = exterior rect grown by pad_margin")
			var sum := 0.0
			var k := 0
			for ix in range(11):
				for iz in range(11):
					sum += f.sample_unfit_y(rect.position + rect.size * Vector2(ix / 10.0, iz / 10.0))
					k += 1
			assert_almost_eq(float(s["target"]), sum / k, 0.05, "seed %d pad %d target = core mean" % [seed, s["index"]])
			assert_between(float(s["w"]), p.pad_ring_min_m, p.pad_ring_max_m, "ring width in range")
		assert_eq(n, layout.cottages.size(), "one site per cottage")


func test_field_uses_the_stored_ring_widths() -> void:
	## SD-19 step 6: one decision, stored. The field reads spec.ring_w and landform.hero_ring_w.
	for seed in _SEEDS:
		var layout := VillageLayout.generate(seed)
		var f = VillageTerrain.field(layout, VillageTerrainParams.production())
		for s: Dictionary in f.sites:
			if s["kind"] == "cottage":
				var spec: Dictionary = layout.cottages[int(s["index"])]
				assert_true(spec.has("ring_w"), "seed %d cottage %d spec.ring_w stored" % [seed, s["index"]])
				assert_eq(float(s["w"]), float(spec["ring_w"]), "field w = spec.ring_w")
			elif s["kind"] == "hero":
				assert_eq(float(s["w"]), float(layout.landform["hero_ring_w"]), "field hero w = stored")


func test_sampler_target_agrees_with_field_target_seeds_1_20() -> void:
	## Review 2 F2 / AR-LF-GAP-5: the plot sampler's T_i (bilinear 1 m lattice, VillageSiteTerrain)
	## and the field's T_i (exact sample_unfit_y) agree within 0.02 m for every cottage. The sampler
	## value is stored on the spec as pad_target. Also records how many seeds kept a moved pond.
	var p := VillageTerrainParams.production()
	var worst := 0.0
	var worst_at := ""
	var n := 0
	var moved := PackedStringArray()
	for seed in range(1, 21):
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		if bool(layout.terrain_diag.get("pond_moved", false)):
			moved.append(str(seed))
		var f = VillageTerrain.field(layout, p)
		for s: Dictionary in f.sites:
			if s["kind"] != "cottage":
				continue
			var spec: Dictionary = layout.cottages[int(s["index"])]
			assert_true(spec.has("pad_target"), "seed %d cottage %d spec.pad_target stored" % [seed, s["index"]])
			if not spec.has("pad_target"):
				continue
			n += 1
			var d := absf(float(spec["pad_target"]) - float(s["target"]))
			if d > worst:
				worst = d
				worst_at = "%d/%d" % [seed, s["index"]]
	gut.p("T_i sampler vs field: %d pads, worst %.4f m at %s; pond_moved kept on seeds [%s]" % [
		n, worst, worst_at, ", ".join(moved)])
	assert_gt(n, 0, "pads compared")
	assert_lte(worst, 0.02, "sampler T_i vs field T_i worst %.4f m at %s (AR-LF-GAP-5)" % [worst, worst_at])


func _site_for(layout: VillageLayout, p: VillageTerrainParams) -> VillageSiteTerrain:
	return VillageSiteTerrain.for_landform(layout.generation_seed, p, layout.landform)


func test_pond_recheck_without_a_move_passes_the_stored_widths() -> void:
	## Review 2 F1: the re-check measures the STORED width with the sampler's helper and grid, so on
	## an unmoved pond every stored pad passes (same decision the sampler made).
	var p := VillageTerrainParams.production()
	for seed in [7, 12]:
		var layout := VillageLayout.generate(seed)
		assert_false(bool(layout.terrain_diag.get("pond_moved", false)), "seed %d keeps its stage-1 pond" % seed)
		var site := _site_for(layout, p)
		site.set_pond(layout.pond_center)
		var r := site.recheck_pads_on_pond(layout, layout.pond_center)
		gut.p("seed %d unmoved re-check: %d pads, peak %.1f°" % [seed, r["rechecked"], r["peak_deg"]])
		assert_true(bool(r["ok"]), "seed %d stored pad rings pass on their own pond (failed %d)" % [seed, r["failed"]])


func test_forced_pond_move_onto_a_pad_fails_the_recheck() -> void:
	## Review 2 F1 repro: move the pond after selection (as resolve_after_paths can) right beside a
	## pad. The re-check must run on that pad with the FINAL pond and reject the stored ring.
	var p := VillageTerrainParams.production()
	var layout := VillageLayout.generate(7)
	var site := _site_for(layout, p)
	var old_c := layout.pond_center
	site.set_pond(old_c)
	var spec: Dictionary = layout.cottages[0]
	var core := site.pad_core(spec)
	var far := Vector2(1e4, 1e4)
	# A far-away pond reaches no pad: nothing to re-check.
	layout.pond_center = far
	var site_far := _site_for(layout, p)
	site_far.set_pond(far)
	var r_far := site_far.recheck_pads_on_pond(layout, far)
	assert_eq(int(r_far["rechecked"]), 0, "pond reaching no pad: no re-check")
	# The pond pressed against the pad's core edge.
	layout.pond_center = Vector2(core.end.x + VillagePondSite.BANK_OUTER_M * 0.5, core.get_center().y)
	var r := site.recheck_pads_on_pond(layout, old_c)
	gut.p("forced move to %s: rechecked %d, failed %d, peak %.1f°" % [str(layout.pond_center), r["rechecked"],
		r["failed"], r["peak_deg"]])
	assert_gt(int(r["rechecked"]), 0, "the re-check ran on the pads the moved pond reaches")
	assert_false(bool(r["ok"]), "a pond basin pressed against a pad breaks its stored ring")
	assert_eq(site.pond["centre"], layout.pond_center, "the site now replays the FINAL pond")


func test_moved_pond_decision_rejects_steep_moves_unless_no_flat_site() -> void:
	## Review 2 F1: a moved pond over pond_max_site_slope_deg fails the attempt (terrain:pond_moved)
	## when stage 1 found a flat site; when stage 1 had none (pond_steep) the move is kept, flagged.
	var p := VillageTerrainParams.production()
	var steep_u := func(xz: Vector2) -> float: return xz.x * 0.3  # ≈ 16.7° plane
	var site := VillageSiteTerrain.from_fn(steep_u, p)
	var layout := VillageLayout.new()
	layout.is_generated = true
	layout.cottages = []
	layout.pond_placed = true
	layout.pond_center = Vector2(10.0, -20.0)
	var td := {}
	var reason := VillageGeneratorV3._check_moved_pond(site, layout, Vector2(0.0, -20.0), p, false, td)
	assert_eq(reason, "terrain:pond_moved", "steep moved pond with a flat stage-1 site fails the attempt")
	assert_true(bool(td.get("pond_moved", false)), "pond_moved flagged")
	var td2 := {}
	var reason2 := VillageGeneratorV3._check_moved_pond(site, layout, Vector2(0.0, -20.0), p, true, td2)
	assert_eq(reason2, "", "no flat alternative: kept")
	assert_true(bool(td2.get("pond_steep", false)), "kept steep move is flagged pond_steep")
	var flat_site := VillageSiteTerrain.from_fn(func(_xz: Vector2) -> float: return 0.0, p)
	var td3 := {}
	assert_eq(VillageGeneratorV3._check_moved_pond(flat_site, layout, Vector2(0.0, -20.0), p, false, td3), "",
		"flat moved pond, no pads: ok")
	assert_eq(int(td3.get("pond_moved_rechecked", -1)), 0, "re-check ran (0 pads reached)")


func test_generated_moved_ponds_were_rechecked_seeds_1_20() -> void:
	## Review 2 F1: every generated village that kept a moved pond passed the re-check on its final
	## pond (terrain_diag.pond_moved_rechecked), and re-running it here agrees.
	var p := VillageTerrainParams.production()
	var kept := PackedStringArray()
	var failed_attempts := PackedStringArray()
	for seed in range(1, 21):
		var layout := VillageLayout.generate(seed)
		for a: Dictionary in VillageGeneratorV3.last_diag.get("attempts", []):
			if str(a["fail_reason"]) == "terrain:pond_moved":
				failed_attempts.append("%d(%d.%d)" % [seed, a["rank"], a["attempt"]])
		if layout.fallback or not bool(layout.terrain_diag.get("pond_moved", false)):
			continue
		var td := layout.terrain_diag
		kept.append("%d:%d pads" % [seed, int(td.get("pond_moved_rechecked", -1))])
		assert_true(td.has("pond_moved_rechecked"), "seed %d moved pond was re-checked" % seed)
		assert_true(td.has("pond_center_before_move"), "seed %d records the pre-move centre" % seed)
		if not td.has("pond_center_before_move"):
			continue
		var site := _site_for(layout, p)
		site.set_pond(td["pond_center_before_move"])
		var r := site.recheck_pads_on_pond(layout, td["pond_center_before_move"])
		assert_true(bool(r["ok"]), "seed %d kept moved pond passes the re-check" % seed)
		assert_eq(int(r["rechecked"]), int(td["pond_moved_rechecked"]), "seed %d same pads re-checked" % seed)
		if float(td.get("pond_site_slope_deg", 0.0)) > p.pond_max_site_slope_deg:
			assert_true(bool(td.get("pond_steep", false)), "seed %d kept steep moved pond is flagged" % seed)
	gut.p("kept moved ponds: [%s]; attempts failed terrain:pond_moved: [%s]" % [", ".join(kept),
		", ".join(failed_attempts)])


func test_field_measures_missing_widths_with_the_shared_helper() -> void:
	## Hand-built layouts (no stored widths) get the measured ring, not the superseded formula.
	var p := VillageTerrainParams.production()
	var src := VillageLayout.generate(1)
	var layout := VillageLayout.generate(1)
	for spec: Dictionary in layout.cottages:
		spec.erase("ring_w")
	layout.landform.erase("hero_ring_w")
	var f = VillageTerrain.field(layout, p)
	var hr := VillageLandform.hero_ring(1, p, src.landform["offset"])
	for s: Dictionary in f.sites:
		if s["kind"] == "hero":
			assert_almost_eq(float(s["w"]), float(hr["w"]), 1e-6, "hero w measured (= search helper)")
		elif s["kind"] == "cottage":
			assert_between(float(s["w"]), p.pad_ring_min_m, p.pad_ring_max_m, "pad w measured in its clamp")
			assert_almost_eq(fmod(float(s["w"]) - p.pad_ring_min_m, 0.5), 0.0, 1e-6, "on the ladder")


func test_ac_lt_pad_cores_level_and_sites_not_steep() -> void:
	## AC-LT-PAD: |y − T_i| ≤ 0.02 m over every core (where no later ring reaches), site plane slope
	## ≤ max_site_slope_deg (no rejected site used).
	var p := VillageTerrainParams.production()
	var overlapped := PackedStringArray()
	for seed in _SEEDS:
		var layout := VillageLayout.generate(seed)
		var f = VillageTerrain.field(layout, p)
		for s: Dictionary in f.sites:
			if s["kind"] != "cottage":
				continue
			assert_lte(float(s["s_deg"]), p.max_site_slope_deg, "seed %d pad %d site slope %.2f°" % [seed, s["index"], s["s_deg"]])
			var rect: Rect2 = s["rect"]
			var worst := 0.0
			var touched := false
			for ix in range(9):
				for iz in range(9):
					var xz: Vector2 = rect.position + rect.size * Vector2(ix / 8.0, iz / 8.0)
					if _covered_by_later(f, s, xz):
						touched = true
						continue
					worst = maxf(worst, absf(f.sample_y(xz) - float(s["target"])))
			assert_lte(worst, 0.02, "seed %d pad %d core level (%.4f m)" % [seed, s["index"], worst])
			if touched:
				overlapped.append("%d/%d" % [seed, s["index"]])
	if not overlapped.is_empty():
		gut.p("cores reached by a later ring: %s" % ", ".join(overlapped))


func test_ac_vt6_cottage_seats_on_its_pad() -> void:
	## AC-VT6 vs T_i: the backdrop seats each cottage at sample_y(centre); where no later ring
	## reaches the centre that is the pad target.
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var layout := VillageLayout.generate(seed)
		var f = VillageTerrain.field(layout, p)
		for s: Dictionary in f.sites:
			if s["kind"] != "cottage":
				continue
			var c: Vector2 = (layout.cottages[int(s["index"])] as Dictionary)["centre"]
			if _covered_by_later(f, s, c):
				continue
			assert_almost_eq(VillageTerrain.sample_y(c, layout, p, 0), float(s["target"]), 0.02,
				"seed %d cottage %d seat = T_i" % [seed, s["index"]])


static func ring_report(layout: VillageLayout, p: VillageTerrainParams) -> Dictionary:
	## AC-LT-RING metric: field.sample_slope_deg (eps 0.4) on a 0.5 m grid over 0 < sdf < w of every
	## hero / pad ring, overlap nodes included. {worst_hero, worst_pad, over: [..], width_errors: [..]}.
	var f = VillageTerrain.field(layout, p)
	var out := {"worst_hero": 0.0, "worst_pad": 0.0, "over": PackedStringArray(), "width_errors": PackedStringArray()}
	for s: Dictionary in f.sites:
		var kind := String(s["kind"])
		if kind != "hero" and kind != "cottage" and kind != "plaza":
			continue
		var hero := kind == "hero"
		var w := float(s["w"])
		var tag := kind if kind != "cottage" else "pad%d" % int(s["index"])
		var lo_w: float
		var hi_w: float
		var stored: float
		match kind:
			"hero":
				lo_w = p.hero_ring_min_m
				hi_w = p.hero_ring_max_m
				stored = float(layout.landform.get("hero_ring_w", NAN))
			"plaza":
				lo_w = p.plaza_ring_m
				hi_w = p.plaza_ring_max_m
				stored = float(layout.landform.get("plaza_ring_w", NAN))
			_:
				lo_w = p.pad_ring_min_m
				hi_w = p.pad_ring_max_m
				stored = float((layout.cottages[int(s["index"])] as Dictionary).get("ring_w", NAN))
		if w < lo_w or w > hi_w or w != stored:
			out["width_errors"].append("%s w %.2f stored %.2f" % [tag, w, stored])
		var box: Rect2
		if hero:
			var hc: Vector2 = s["centre"]
			var hh := float(s["r_c"]) + w
			box = Rect2(hc - Vector2(hh, hh), Vector2(2.0 * hh, 2.0 * hh))
		else:
			box = (s["rect"] as Rect2).grow(w)
		var worst := 0.0
		var at := Vector2.ZERO
		var x := box.position.x
		while x <= box.end.x:
			var z := box.position.y
			while z <= box.end.y:
				var xz := Vector2(x, z)
				var d: float = f.site_sdf(s, xz)
				if d > 0.0 and d < w:
					var sl: float = f.sample_slope_deg(xz)
					if sl > worst:
						worst = sl
						at = xz
				z += _RING_GRID_M
			x += _RING_GRID_M
		var key := "worst_hero" if hero else ("worst_plaza" if kind == "plaza" else "worst_pad")
		out[key] = maxf(float(out.get(key, 0.0)), worst)
		if worst > p.ring_max_slope_deg + VillageLandform.RING_OVERLAP_TOL_DEG:
			out["over"].append("%s %.1f° at %s" % [tag, worst, str(at)])
	return out


func test_ac_lt_ring_seeds_1_7_12() -> void:
	## AC-LT-RING (restated 2026-11-17): hero and pads ≤ 25° measured on the full field, overlaps
	## included; widths within their clamps and equal to the stored values; 0 exceptions.
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var layout := VillageLayout.generate(seed)
		assert_false(layout.fallback, "seed %d generated" % seed)
		var r := ring_report(layout, p)
		gut.p("seed %d ring worst hero %.1f° pad %.1f° plaza %.1f°" % [seed, r["worst_hero"], r["worst_pad"],
			r.get("worst_plaza", 0.0)])
		assert_eq((r["over"] as PackedStringArray).size(), 0, "seed %d rings over 25°: %s" % [seed, ", ".join(r["over"])])
		assert_eq((r["width_errors"] as PackedStringArray).size(), 0,
			"seed %d widths: %s" % [seed, ", ".join(r["width_errors"])])


func test_ac_lt_ring_sweep_seeds_1_20() -> void:
	## AC-LT-RING sweep (restated ivy-82zn.14.23): 0 exceptions on seeds 1–20 (generated seeds).
	var p := VillageTerrainParams.production()
	var over := PackedStringArray()
	var worst := {"hero": 0.0, "pad": 0.0, "plaza": 0.0}
	for seed in range(1, 21):
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var r := ring_report(layout, p)
		worst["hero"] = maxf(float(worst["hero"]), float(r["worst_hero"]))
		worst["pad"] = maxf(float(worst["pad"]), float(r["worst_pad"]))
		worst["plaza"] = maxf(float(worst["plaza"]), float(r.get("worst_plaza", 0.0)))
		for e in r["over"]:
			over.append("%d:%s" % [seed, e])
		for e2 in r["width_errors"]:
			over.append("%d:%s" % [seed, e2])
	gut.p("sweep worst hero %.1f° pad %.1f° plaza %.1f°" % [worst["hero"], worst["pad"], worst["plaza"]])
	assert_eq(over.size(), 0, "sweep exceptions: %s" % ", ".join(over))
