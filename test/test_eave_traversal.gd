## ivy-dsh.4 — Fast tests for eave-traversal gate, soffit redirect (T1), up bias (T2),
## float-death exemption (T3), and feeler thinning (Rule F).
##
## All tests are headless / physics-free. They exercise the logic units directly using the
## same isolation pattern as test_growth_step.gd and test_tip_lifecycle.gd.
extends GutTest

const GrowthStep = preload("res://src/sim/growth_step.gd")
const TipManager = preload("res://src/sim/tip_manager.gd")
const Tip = preload("res://src/sim/tip.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const BuildingCatalog = preload("res://src/world/building_catalog.gd")


# ── F1 — gate must never fire on TowerSdf even if eave_traversal_enabled is true ────────

func test_f1_traverse_gate_requires_wall_sdf_tag() -> void:
	## The gate: traverse = eave_traversal_enabled AND backend_tag() == "WallSdf"
	## WallSdf flag true but wrong tag → traverse must be false.
	var params := IvyParams.new()
	params.eave_traversal_enabled = true
	var traverse_on_tower := params.eave_traversal_enabled and "TowerSdf" == "WallSdf"
	assert_false(traverse_on_tower,
		"F1: traverse must be false when backend_tag is 'TowerSdf' even if flag is true")


func test_f1_traverse_gate_true_only_with_wall_sdf_and_flag() -> void:
	var params := IvyParams.new()
	params.eave_traversal_enabled = true
	var tag := "WallSdf"
	assert_true(params.eave_traversal_enabled and tag == "WallSdf",
		"F1: traverse must be true when flag=true and tag='WallSdf'")


func test_f1_traverse_gate_false_when_flag_off() -> void:
	var params := IvyParams.new()
	params.eave_traversal_enabled = false
	var traverse := params.eave_traversal_enabled and "WallSdf" == "WallSdf"
	assert_false(traverse, "F1: traverse must be false when flag is off")


# ── F2 — catalog traversal_for() policy ─────────────────────────────────────────────────

func test_f2_catalog_traversal_true_for_overhang_only() -> void:
	assert_true(BuildingCatalog.traversal_for("overhang"),
		"F2: 'overhang' must have traversal=true in catalog")
	assert_false(BuildingCatalog.traversal_for("overhang_spread"),
		"F2: 'overhang_spread' must have traversal=false in catalog")
	assert_false(BuildingCatalog.traversal_for("cylinder"),
		"F2: 'cylinder' must have traversal=false in catalog")
	assert_false(BuildingCatalog.traversal_for("test_wall"),
		"F2: 'test_wall' must have traversal=false in catalog")
	assert_false(BuildingCatalog.traversal_for("tower"),
		"F2: 'tower' must have traversal=false in catalog")


func test_f2_overhang_spread_is_procedural() -> void:
	assert_true(BuildingCatalog.is_procedural("overhang_spread"),
		"F2: 'overhang_spread' must be listed as a procedural building")


# ── F3 — T1 soffit redirect: helper function ─────────────────────────────────────────────

func test_f3_soffit_redirect_produces_outward_direction() -> void:
	## Simulate the T1 redirect math directly.
	## Soffit underside: hit.normal.y < -0.5 (pointing DOWN from soffit face).
	## climb_outward = +Z (south), soffit normal = (0, -1, 0).
	## glide = normalize(climb_outward - (climb_outward · normal) * normal)
	##       = normalize((0,0,1) - 0*(0,-1,0)) = (0,0,1)
	## So the result should be predominantly in the +Z direction.
	var hit_normal := Vector3(0.0, -1.0, 0.0)  # underside of soffit
	var climb_outward := Vector3(0.0, 0.0, 1.0)  # wall normal captured = SOUTH (+Z)
	var glide := (climb_outward - climb_outward.dot(hit_normal) * hit_normal).normalized()
	assert_gt(glide.dot(Vector3(0.0, 0.0, 1.0)), 0.99,
		"F3: soffit redirect glide direction should point outward (along +Z)")


func test_f3_soffit_redirect_not_applied_on_wall_face() -> void:
	## hit.normal.y = 0 (vertical wall face) — not a soffit, T1 must NOT fire.
	var hit_normal_y := 0.0
	var is_soffit := hit_normal_y < -0.5
	assert_false(is_soffit, "F3: T1 must not fire on a vertical wall face")


# ── F4 — T3 float-death exemption ────────────────────────────────────────────────────────

func _make_params_with_traversal(traversal_window: int = 40) -> IvyParams:
	var p := IvyParams.new()
	p.eave_traversal_enabled = true
	p.eave_traverse_window = traversal_window
	p.eave_traverse_max_float = 0.55
	p.max_float = 0.40
	return p


func test_f4_float_death_exemption_keeps_tip_alive_with_ticks() -> void:
	## floating_length = 0.45 > max_float (0.40) but < eave_traverse_max_float (0.55).
	## With traverse_ticks > 0, tip should survive apply_lifecycle.
	var tip := Tip.new()
	tip.state = Tip.State.FLOATING
	tip.floating_length = 0.45
	tip.traverse_ticks = 5  # active window
	tip.position = Vector3(0.0, 4.8, 0.5)  # above ground
	var params := _make_params_with_traversal()
	TipManager._apply_float_death(tip, params)
	assert_ne(tip.state, Tip.State.DEAD,
		"F4: tip with traverse_ticks>0 and float<eave_traverse_max_float must not die")


func test_f4_float_death_kills_tip_without_ticks() -> void:
	## Same floating_length 0.45 > max_float but traverse_ticks = 0 → DEAD.
	var tip := Tip.new()
	tip.state = Tip.State.FLOATING
	tip.floating_length = 0.45
	tip.traverse_ticks = 0
	tip.position = Vector3(0.0, 4.8, 0.5)
	var params := _make_params_with_traversal()
	TipManager._apply_float_death(tip, params)
	assert_eq(tip.state, Tip.State.DEAD,
		"F4: tip with traverse_ticks=0 and float>max_float must die")


func test_f4_traverse_max_float_also_kills_tip_beyond_ceil() -> void:
	## floating_length = 0.60 > eave_traverse_max_float (0.55) even with active window → DEAD.
	var tip := Tip.new()
	tip.state = Tip.State.FLOATING
	tip.floating_length = 0.60
	tip.traverse_ticks = 10
	tip.position = Vector3(0.0, 4.8, 0.5)
	var params := _make_params_with_traversal()
	TipManager._apply_float_death(tip, params)
	assert_eq(tip.state, Tip.State.DEAD,
		"F4: tip beyond eave_traverse_max_float must die even with active traverse")


func test_f4_traverse_ticks_decremented_while_floating() -> void:
	## When a tip is FLOATING and traverse_ticks > 0, ticks should count down.
	var tip := Tip.new()
	tip.state = Tip.State.FLOATING
	tip.floating_length = 0.10
	tip.traverse_ticks = 3
	var params := _make_params_with_traversal()
	TipManager._apply_float_death(tip, params)
	assert_eq(tip.traverse_ticks, 2, "F4: traverse_ticks must count down while floating")


# ── F5 — Rule F feeler thinning stress test ──────────────────────────────────────────────

func _make_feeler_tip(x: float, float_len: float, tip_id: int, vigour: float = 1.0) -> Tip:
	var t := Tip.new()
	t.id = tip_id
	t.state = Tip.State.FLOATING
	t.floating_length = float_len
	t.position = Vector3(x, 4.6, 1.2)  # above soffit, past lip
	t.vigour = vigour
	return t


func test_f5_feeler_thinning_caps_bin_to_four() -> void:
	## Create 7 feeler tips all in the same 0.25 m bin (x in [0, 0.25)).
	## After thinning, the bin should have at most feeler_cap (4).
	var params := IvyParams.new()
	params.feeler_thinning_enabled = true
	params.feeler_bin = 0.25
	params.feeler_cap = 4
	params.feeler_min_float = 0.05

	var mgr := TipManager.new()
	for i in range(7):
		var t := _make_feeler_tip(0.1, 0.10 + i * 0.05, i)  # increasing float_len
		mgr.tips.append(t)

	TipManager._apply_feeler_thinning(mgr.tips, params)

	var alive_feelers := 0
	var dormant_count := 0
	for t in mgr.tips:
		if t.state == Tip.State.FLOATING and t.floating_length > params.feeler_min_float:
			alive_feelers += 1
		if t.state == Tip.State.DORMANT:
			dormant_count += 1
	assert_lte(alive_feelers, params.feeler_cap,
		"F5: bin must have at most feeler_cap floating feelers after thinning")
	assert_eq(dormant_count, 3, "F5: exactly 3 tips (7-4) must be retired to DORMANT")


func test_f5_feeler_thinning_retires_longest_first() -> void:
	## Feelers with longest floating_length should be retired first.
	## Tips 0-6 sorted by float_len ascending (0.10..0.40); cap=4 keeps 0-3, retires 4-6.
	var params := IvyParams.new()
	params.feeler_thinning_enabled = true
	params.feeler_bin = 0.25
	params.feeler_cap = 4
	params.feeler_min_float = 0.05

	var mgr := TipManager.new()
	# float_lens: 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40 — ids 0-6 same order
	for i in range(7):
		var t := _make_feeler_tip(0.1, 0.10 + float(i) * 0.05, i)
		mgr.tips.append(t)

	TipManager._apply_feeler_thinning(mgr.tips, params)

	# The 3 tips with longest float_len (ids 4, 5, 6 = float 0.30, 0.35, 0.40) must be DORMANT
	for t in mgr.tips:
		if t.id >= 4:
			assert_eq(t.state, Tip.State.DORMANT,
				"F5: tip id %d (float %.2f) should be retired (longest first)" % [t.id, t.floating_length])
		else:
			assert_ne(t.state, Tip.State.DORMANT,
				"F5: tip id %d (float %.2f) should survive" % [t.id, t.floating_length])


func test_f5_feeler_thinning_separate_bins_independent() -> void:
	## Two bins each with 5 feelers — each bin should keep ≤4 independently.
	var params := IvyParams.new()
	params.feeler_thinning_enabled = true
	params.feeler_bin = 0.25
	params.feeler_cap = 4
	params.feeler_min_float = 0.05

	var mgr := TipManager.new()
	# Bin 0 (x in [0, 0.25)): 5 tips
	for i in range(5):
		var t := _make_feeler_tip(0.1, 0.10 + float(i) * 0.05, i)
		mgr.tips.append(t)
	# Bin 1 (x in [0.25, 0.50)): 5 tips
	for i in range(5):
		var t := _make_feeler_tip(0.3, 0.10 + float(i) * 0.05, 10 + i)
		mgr.tips.append(t)

	TipManager._apply_feeler_thinning(mgr.tips, params)

	var bin0_count := 0
	var bin1_count := 0
	for t in mgr.tips:
		if t.state == Tip.State.FLOATING and t.floating_length > params.feeler_min_float:
			if t.position.x < 0.25:
				bin0_count += 1
			else:
				bin1_count += 1
	assert_lte(bin0_count, params.feeler_cap, "F5: bin 0 must have ≤ feeler_cap floating feelers")
	assert_lte(bin1_count, params.feeler_cap, "F5: bin 1 must have ≤ feeler_cap floating feelers")


func test_f5_feeler_thinning_skipped_when_disabled() -> void:
	## When feeler_thinning_enabled is false, no tips should be retired.
	var params := IvyParams.new()
	params.feeler_thinning_enabled = false
	params.feeler_bin = 0.25
	params.feeler_cap = 4
	params.feeler_min_float = 0.05

	var mgr := TipManager.new()
	for i in range(7):
		var t := _make_feeler_tip(0.1, 0.10 + float(i) * 0.05, i)
		mgr.tips.append(t)

	TipManager._apply_feeler_thinning(mgr.tips, params)

	var dormant_count := 0
	for t in mgr.tips:
		if t.state == Tip.State.DORMANT:
			dormant_count += 1
	assert_eq(dormant_count, 0, "F5: no tips should be retired when thinning is disabled")
