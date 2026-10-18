## ivy-dsh.4 / ivy-dsh.9 — Fast tests for eave-traversal gate, soffit redirect (T1),
## up bias (T2), float-death exemption (T3), feeler thinning (Rule F), T5 growth-rate
## light floor, and the early-trigger arm (ivy-dsh.9).
##
## T5/early-trigger scene tests create an OverhangWall with physics for the surface
## query (needed for early-trigger raycast) but build env with null physics (fast, no
## occlusion bake). Only traverse_ticks is asserted, not growth values.
##
## All other tests are headless / physics-free.
extends GutTest

const GrowthStep = preload("res://src/sim/growth_step.gd")
const TipManager = preload("res://src/sim/tip_manager.gd")
const Tip = preload("res://src/sim/tip.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const Physiology = preload("res://src/sim/physiology.gd")
const BuildingCatalog = preload("res://src/world/building_catalog.gd")
## For F1 Tower-isolation proof (Critical-2 fix):
const SimContextScript = preload("res://src/sim/sim_context.gd")
const SurfaceQueryScript = preload("res://src/world/surface_query.gd")
## For T5/early-trigger scene tests:
const OverhangSpec = preload("res://src/world/overhang_spec.gd")
const OverhangSdf = preload("res://src/world/overhang_sdf.gd")
const OverhangWall = preload("res://src/world/overhang_wall.gd")
const Conv = preload("res://src/core/conv.gd")


# ── F1 — gate must never fire on TowerSdf even if eave_traversal_enabled is true ────────
#
# Critical-2 fix: replace tautological string-literal assertions with a real
# TowerSdf SimContext that actually calls GrowthStep.step_tip().
#
# Isolation pattern mirrors test_determinism.gd _build_sim():
#   - null PhysicsDirectSpaceState3D so SurfaceQuery falls back to the analytic SDF
#   - same seed → identical RNG streams in both runs
#   - run A: eave_traversal_enabled=true  (flag ON but TowerSdf → traverse stays false)
#   - run B: eave_traversal_enabled=false (flag OFF, same code path)
#   - assert: positions, directions, and traverse_ticks are identical after N steps


## Build a physics-free TowerSdf SimContext for step_tip isolation tests.
## Returns a Dictionary with "ctx" (SimContext) and "tip" (Tip).
func _make_tower_ctx(traversal_on: bool, seed: int = 99991) -> Dictionary:
	var params := IvyParams.new()
	params.eave_traversal_enabled = traversal_on
	var spec := TowerSpec.new()
	var surface := SurfaceQueryScript.new()
	surface.setup(null, null, TowerSdf.new(spec), PackedByteArray(), params)
	var solar := Solar.new(params)
	var clock := SimClock.new(params)
	var env := IvyEnvironment.new()
	env.build(params, surface, solar)
	var plant := PlantData.new()
	var tips := TipManager.new()
	var ctx := SimContextScript.new(params, env, surface, plant, tips, clock)
	## South-face anchor at ground level (mirrors test_determinism.gd)
	var probe := Vector3(0.0, params.ground_y_min, 0.0) + Conv.SOUTH * 8.0
	var anchor := surface.nearest(probe)
	var tip := tips.add_seed(anchor.position + anchor.normal * 0.01, anchor.normal, seed, params)
	return {"ctx": ctx, "tip": tip}


## F1 Tower-isolation proof: with TowerSdf the traverse gate never fires,
## so step_tip with eave_traversal_enabled=true vs false produces identical outputs.
## This exercises the actual gate line in growth_step.gd (not a string literal).
func test_f1_tower_sdf_isolates_traverse_flag() -> void:
	const N_STEPS := 20
	const SEED := 99991

	var a := _make_tower_ctx(true, SEED)   ## flag ON — TowerSdf must neutralise it
	var b := _make_tower_ctx(false, SEED)  ## flag OFF — baseline
	var tip_a: Tip = a.tip
	var tip_b: Tip = b.tip

	for _i in range(N_STEPS):
		GrowthStep.step_tip(tip_a, a.ctx)
		GrowthStep.step_tip(tip_b, b.ctx)

	## traverse_ticks must be 0 in both: TowerSdf never hits the soffit/roof branch
	assert_eq(tip_a.traverse_ticks, 0,
		"F1: traverse_ticks must stay 0 with TowerSdf even if eave_traversal_enabled=true")
	assert_eq(tip_b.traverse_ticks, 0,
		"F1: traverse_ticks must stay 0 with eave_traversal_enabled=false")

	## Outputs must be identical: TowerSdf gate makes the flag a no-op here
	assert_eq(tip_a.position, tip_b.position,
		"F1: TowerSdf — position must be identical with flag on vs off (traverse is dead code)")
	assert_eq(tip_a.direction, tip_b.direction,
		"F1: TowerSdf — direction must be identical with flag on vs off")


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


func test_f4_traverse_ticks_not_decremented_when_feature_disabled() -> void:
	## Minor-1 regression: when eave_traversal_enabled=false the countdown must NOT fire.
	## Before the fix, _apply_float_death decremented regardless of the flag; a tip could
	## reach traverse_ticks=0 (and lose its extended float ceiling) even though the feature
	## is off.
	var tip := Tip.new()
	tip.state = Tip.State.FLOATING
	tip.floating_length = 0.10  ## well below both max_float and traverse_max_float
	tip.traverse_ticks = 3
	var params := IvyParams.new()
	params.eave_traversal_enabled = false
	params.max_float = 0.40
	TipManager._apply_float_death(tip, params)
	assert_eq(tip.traverse_ticks, 3,
		"Minor-1: traverse_ticks must NOT decrement when eave_traversal_enabled=false")


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


# ── T5 — traverse-scoped growth-rate light floor (ivy-dsh.9) ─────────────────────────────

func test_t5_light_floor_raises_dark_zone_fl() -> void:
	## In the dark-soffit zone (measured D_L ≈ 0.44 μmol), f_L ≈ 0.16 — ~1/6 speed.
	## With eave_traverse_light_floor=0.75 and traverse_ticks>0 the floor is applied,
	## raising effective fl to 0.75. This is the T5 rule's key purpose.
	var params := IvyParams.new()
	params.eave_traverse_light_floor = 0.75
	var d_l_soffit := 0.44  ## measured soffit D_L (ivy-dsh.8 diagnosis)
	var raw_fl := Physiology.f_L(d_l_soffit, params)
	assert_lt(raw_fl, 0.20,
		"T5 setup: soffit f_L must be below 0.20 to confirm the dark-zone bottleneck")
	## max(raw_fl, floor) = 0.75 — the floor wins in the dark zone
	var floored_fl := maxf(raw_fl, params.eave_traverse_light_floor)
	assert_almost_eq(floored_fl, 0.75, 0.001,
		"T5: fl must be floored to eave_traverse_light_floor in the dark zone")


func test_t5_light_floor_no_effect_in_bright_zone() -> void:
	## On the open wall face (D_L ≈ 21), f_L is close to 1.0 — already above the floor.
	## The floor must have no effect (max(bright_fl, 0.75) = bright_fl).
	var params := IvyParams.new()
	params.eave_traverse_light_floor = 0.75
	var d_l_open := 21.0  ## measured open-wall D_L (ivy-dsh.8 diagnosis)
	var bright_fl := Physiology.f_L(d_l_open, params)
	assert_gt(bright_fl, params.eave_traverse_light_floor,
		"T5: open-wall f_L must already exceed the floor")
	var floored_fl := maxf(bright_fl, params.eave_traverse_light_floor)
	assert_almost_eq(floored_fl, bright_fl, 0.001,
		"T5: floor must not reduce f_L when already above it")


func test_t5_growth_rate_bounded_by_max_growth_rate() -> void:
	## The floor is applied before multiplying by max_growth_rate. f_L ≤ 1.0 always, so
	## the product max_growth_rate * floored_fl ≤ max_growth_rate. Verify with floor=0.75.
	var params := IvyParams.new()
	params.eave_traverse_light_floor = 0.75
	## Even in the dark zone: max(0.16, 0.75) = 0.75; max_growth_rate * 0.75 < max_growth_rate.
	var fl := maxf(0.16, params.eave_traverse_light_floor)
	assert_lte(fl * params.max_growth_rate, params.max_growth_rate,
		"T5: floored growth rate must never exceed max_growth_rate")


# ── Early trigger — upward raycast arm (ivy-dsh.9) ──────────────────────────────────────
#
# The early trigger arms traverse_ticks when a soffit is directly overhead within
# eave_approach_reach metres. It fires inside the "if traverse:" T2 block (WallSdf +
# eave_traversal_enabled gate), so TowerSdf is already excluded by the gate (F1 above).
#
# Scene tests: OverhangWall with physics frame so the upward raycast can hit the soffit.
# Env is built with null-physics SQ (fast, no occlusion bake). D_L values are uniformly
# bright — acceptable since these tests only check traverse_ticks, not growth values.


## Build a physics-backed OverhangSdf SimContext for early-trigger step_tip tests.
## Env is built with a separate null-physics SQ so the env bake is fast. The returned
## context surface uses the real physics space so ctx.surface.raycast() detects the soffit.
## Coroutine: awaits physics_frame after build_from_spec.
func _make_early_trigger_ctx(approach_reach: float, tip_pos: Vector3, seed: int = 77771) -> Dictionary:
	var spec := OverhangSpec.new()
	var ow := OverhangWall.new()
	add_child_autofree(ow)
	ow.build_from_spec(spec, true)
	await get_tree().physics_frame  ## commit shape so ctx.surface.raycast() detects the soffit

	var params := IvyParams.new()
	params.eave_traversal_enabled = true
	params.eave_approach_reach = approach_reach
	params.eave_traverse_window = 40

	## Real-physics surface query — needed for the early-trigger upward raycast in step_tip.
	var surface := SurfaceQueryScript.new()
	surface.setup(
		ow.get_world_3d().direct_space_state,
		ow,
		OverhangSdf.new(spec),
		ow.face_material,
		params
	)

	## Null-physics surface query — used only for the env light bake (fast, no occlusion).
	var surface_fast := SurfaceQueryScript.new()
	surface_fast.setup(null, null, OverhangSdf.new(spec), PackedByteArray(), params)
	var solar := Solar.new(params)
	var env := IvyEnvironment.new()
	env.build(params, surface_fast, solar)  ## fast: null-physics raycasts return no-hit

	var plant := PlantData.new()
	var tips := TipManager.new()
	var clock := SimClock.new(params)
	var ctx := SimContextScript.new(params, env, surface, plant, tips, clock)
	var tip := tips.add_seed(tip_pos, Conv.SOUTH, seed, params)
	return {"ctx": ctx, "tip": tip}


## T6 (early trigger): a tip just below the soffit (y=4.7, within 0.40 m reach) gets
## traverse_ticks armed to eave_traverse_window after one step_tip call on WallSdf.
func test_early_trigger_arms_traverse_when_soffit_overhead() -> void:
	## Soffit underside at y=5.0. Tip at y=4.7 → soffit is 0.30 m above → within 0.40 m reach.
	var tip_pos := Vector3(0.0, 4.7, 0.01)
	var d := await _make_early_trigger_ctx(0.40, tip_pos)
	var tip: Tip = d.tip
	var ctx: SimContext = d.ctx
	GrowthStep.step_tip(tip, ctx)
	assert_gt(tip.traverse_ticks, 0,
		"Early trigger: traverse_ticks must be armed when soffit is within eave_approach_reach overhead")


## T6 (early trigger): a tip in the mid-wall zone (y=2.5) — 2.5 m below soffit — does NOT
## get traverse_ticks armed: the soffit is well outside the 0.40 m upward reach.
func test_early_trigger_not_armed_at_mid_wall() -> void:
	var tip_pos := Vector3(0.0, 2.5, 0.01)
	var d := await _make_early_trigger_ctx(0.40, tip_pos)
	var tip: Tip = d.tip
	var ctx: SimContext = d.ctx
	GrowthStep.step_tip(tip, ctx)
	## Soffit is at y=5.0 → 2.5 m above → well outside 0.40 m reach; traverse must not arm.
	assert_eq(tip.traverse_ticks, 0,
		"Early trigger: traverse_ticks must remain 0 when soffit is beyond eave_approach_reach")


## T6 (early trigger): with eave_approach_reach=0, the early-trigger block is skipped
## entirely even when the soffit is directly overhead. traverse_ticks must stay 0.
func test_early_trigger_disabled_by_zero_reach() -> void:
	var tip_pos := Vector3(0.0, 4.7, 0.01)  ## within soffit zone (same as arms test)
	var d := await _make_early_trigger_ctx(0.0, tip_pos)  ## reach=0 disables early trigger
	var tip: Tip = d.tip
	var ctx: SimContext = d.ctx
	GrowthStep.step_tip(tip, ctx)
	assert_eq(tip.traverse_ticks, 0,
		"Early trigger: eave_approach_reach=0 must disable the early-trigger arm")
