## Regression tests for SD-TIP-2/3/4: soft/hard cap taper and vigour-based retirement.
extends GutTest

const TipManager = preload("res://src/sim/tip_manager.gd")
const Tip = preload("res://src/sim/tip.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const RngStream = preload("res://src/core/rng_stream.gd")


func _fill_manager_with_growing_tips(mgr: TipManager, count: int, vigour: float = 1.0) -> void:
	for i in range(count):
		var t := Tip.new()
		t.id = i
		t.state = Tip.State.GROWING
		t.vigour = vigour
		t.stream = RngStream.from_seed(i)
		mgr.tips.append(t)


func _make_parent(id: int, vig: float) -> Tip:
	var t := Tip.new()
	t.id = id
	t.state = Tip.State.GROWING
	t.vigour = vig
	t.stream = RngStream.from_seed(id + 10000)
	return t


func test_below_soft_cap_branch_scale_is_one() -> void:
	var params := IvyParams.new()
	var mgr := TipManager.new()
	_fill_manager_with_growing_tips(mgr, params.tip_cap_soft - 1)
	var q: float = mgr.branch_probability_scale(params)
	assert_almost_eq(q, 1.0, 1e-6)


func test_above_soft_cap_scale_is_less_than_one() -> void:
	# SD-TIP-3: taper begins just above the soft cap. At n = soft+1, q < 1.
	var params := IvyParams.new()
	var mgr := TipManager.new()
	_fill_manager_with_growing_tips(mgr, params.tip_cap_soft + 1)
	var q: float = mgr.branch_probability_scale(params)
	assert_lt(q, 1.0, "scale must be below 1 above soft cap")
	assert_gt(q, 0.0, "scale must still be positive just above soft cap")


func test_midway_between_soft_and_hard_scale_is_midpoint() -> void:
	# SD-TIP-3 (W-045): at the midpoint ramp = 0.5, so q = floor + (1-floor)*0.5.
	var params := IvyParams.new()
	var mgr := TipManager.new()
	var mid := (params.tip_cap_soft + params.tip_cap_hard) / 2
	_fill_manager_with_growing_tips(mgr, mid)
	var q: float = mgr.branch_probability_scale(params)
	var ramp := float(params.tip_cap_hard - mid) / float(params.tip_cap_hard - params.tip_cap_soft)
	var expected := params.branch_scale_floor + (1.0 - params.branch_scale_floor) * ramp
	assert_almost_eq(q, expected, 1e-4)


func test_branch_scale_at_hard_cap_is_full_for_sd_tip4() -> void:
	# SD-TIP-3/4 (W-045): at the hard cap q = branch_scale_floor > 0 — not 1.0.
	# The floor keeps the branch draw alive (throttled to ~2% of unthrottled rate) so
	# queue_branch can attempt the SD-TIP-4 retirement swap. 1.0 was the pre-W-045 value
	# and introduced a 64× pop at a single tip; branch_scale_floor fixes both at once.
	var params := IvyParams.new()
	var mgr := TipManager.new()
	_fill_manager_with_growing_tips(mgr, params.tip_cap_hard)
	var q := mgr.branch_probability_scale(params)
	assert_almost_eq(q, params.branch_scale_floor, 1e-6,
		"branch scale must equal branch_scale_floor at the hard cap (SD-TIP-3, W-045)")
	assert_gt(q, 0.0,
		"branch scale must be positive at the hard cap so SD-TIP-4 swap remains reachable")


func test_can_branch_true_below_hard_cap() -> void:
	var params := IvyParams.new()
	var mgr := TipManager.new()
	# The hard cap is tip_cap_hard = 160; one below should still allow branching.
	_fill_manager_with_growing_tips(mgr, params.tip_cap_hard - 1)
	assert_true(mgr.can_branch(params), "can_branch must be true one below the hard cap")


func test_can_branch_true_at_hard_cap() -> void:
	# SD-TIP-4: the gate must stay open at the hard cap so growth_step can call
	# queue_branch and attempt the retirement swap. can_branch() always returns true
	# (fixed by W-037; before that it returned false, making the swap unreachable).
	# W-045 does not change this — throttling happens via branch_scale_floor in
	# branch_probability_scale(), not by blocking at can_branch().
	var params := IvyParams.new()
	var mgr := TipManager.new()
	_fill_manager_with_growing_tips(mgr, params.tip_cap_hard)
	assert_true(mgr.can_branch(params), "can_branch must be true at the hard cap for SD-TIP-4 to be reachable")


func test_queue_branch_at_hard_cap_retires_weak_tip() -> void:
	# SD-TIP-4: full production path — can_branch must be true at the cap (this assertion
	# would have FAILED before W-037, because can_branch returned false and growth_step
	# never called queue_branch at the hard cap), then queue_branch must retire a weak tip.
	var params := IvyParams.new()
	var mgr := TipManager.new()
	_fill_manager_with_growing_tips(mgr, params.tip_cap_hard, 0.1)  # 160 weak tips

	# Production-path gate: growth_step only calls queue_branch when can_branch() is true.
	# This assertion pins the fix — it would have failed before W-037.
	assert_true(mgr.can_branch(params), "can_branch must be true at hard cap (production gate must be open)")

	var parent := _make_parent(params.tip_cap_hard, 1.0)  # much stronger than retirees
	mgr.tips.append(parent)
	var pre_size := mgr.tips.size()  # should be tip_cap_hard + 1

	mgr.queue_branch(parent, Vector3.ZERO, Vector3.UP, Vector3.BACK, 0, params)

	# A new child was created (tip array grows)
	assert_eq(mgr.tips.size(), pre_size + 1, "one child tip must be added")
	# One weak tip was retired to DORMANT
	var dormant := 0
	for t in mgr.tips:
		if t.state == Tip.State.DORMANT:
			dormant += 1
	assert_eq(dormant, 1, "exactly one tip must be retired to DORMANT")


func test_queue_branch_at_hard_cap_no_branch_when_parent_too_weak() -> void:
	# SD-TIP-4: the swap only happens if parent.vigour > retiree.vigour * retire_margin.
	# With all tips at vigour = 1.0 and parent at vigour = 1.0, the margin (1.25) is not met.
	var params := IvyParams.new()
	var mgr := TipManager.new()
	_fill_manager_with_growing_tips(mgr, params.tip_cap_hard, 1.0)

	var parent := _make_parent(params.tip_cap_hard, 1.0)
	mgr.tips.append(parent)
	var pre_size := mgr.tips.size()

	mgr.queue_branch(parent, Vector3.ZERO, Vector3.UP, Vector3.BACK, 0, params)

	assert_eq(mgr.tips.size(), pre_size, "no child should be added when parent is not vigorous enough")
	for t in mgr.tips:
		assert_ne(t.state, Tip.State.DORMANT, "no tip should be retired when margin not met")


## W-045 regression — the property that would have caught the original defect.
func test_branch_scale_continuity_no_pop() -> void:
	# SD-TIP-3: the largest step between adjacent tip counts must equal exactly
	# (1 - branch_scale_floor) / (tip_cap_hard - tip_cap_soft) — no discontinuity.
	# The old code stepped from ~0.016 to 1.0 at the hard cap (a 64× pop); the new
	# formula is monotone with uniform step size throughout the taper.
	var params := IvyParams.new()
	var expected_step := (1.0 - params.branch_scale_floor) / float(params.tip_cap_hard - params.tip_cap_soft)
	var max_step := 0.0
	# Scan a range that includes below-soft (flat at 1.0), the taper, and above-hard (flat at floor).
	for n in range(0, params.tip_cap_hard + 4):
		var mgr_a := TipManager.new()
		var mgr_b := TipManager.new()
		_fill_manager_with_growing_tips(mgr_a, n)
		_fill_manager_with_growing_tips(mgr_b, n + 1)
		var step := absf(mgr_b.branch_probability_scale(params) - mgr_a.branch_probability_scale(params))
		if step > max_step:
			max_step = step
	assert_almost_eq(max_step, expected_step, 1e-6,
		"max step between adjacent N must equal (1-floor)/(hard-soft) — no pop allowed (SD-TIP-3, W-045)")


## W-038 regression — SD-TIP-6 silhouette exemption.
func test_silhouette_tips_exempt_from_retirement_when_count_below_min() -> void:
	# SD-TIP-6: if fewer than silhouette_min_tips live tips are above
	# silhouette_height_frac * tower_height, those tips must never be retired.
	var params := IvyParams.new()
	var mgr := TipManager.new()
	mgr.tower_height = 3.5
	var threshold := mgr.tower_height * params.silhouette_height_frac  # 2.8 m

	# Fill to hard cap - 1 with mid-vigour tips below the threshold.
	for i in range(params.tip_cap_hard - 1):
		var t := Tip.new()
		t.id = i
		t.state = Tip.State.GROWING
		t.vigour = 0.5
		t.position = Vector3(0.0, threshold - 0.1, 0.0)
		t.stream = RngStream.from_seed(i)
		mgr.tips.append(t)

	# Add silhouette_min_tips - 1 tips above the threshold with very low vigour.
	# These would be chosen as the retirement candidate if not for the SD-TIP-6 exemption.
	var n_above := params.silhouette_min_tips - 1  # below the minimum → exempt
	for i in range(n_above):
		var t := Tip.new()
		t.id = params.tip_cap_hard + i
		t.state = Tip.State.GROWING
		t.vigour = 0.001
		t.position = Vector3(0.0, threshold + 0.1, 0.0)
		t.stream = RngStream.from_seed(params.tip_cap_hard + i)
		mgr.tips.append(t)

	var parent := _make_parent(99999, 100.0)
	mgr.tips.append(parent)

	mgr.queue_branch(parent, Vector3.ZERO, Vector3.UP, Vector3.BACK, 0, params)

	# No above-threshold tip may have been retired.
	for t in mgr.tips:
		if t.position.y >= threshold:
			assert_ne(t.state, Tip.State.DORMANT,
				"SD-TIP-6: tip above threshold must not be retired when count < silhouette_min_tips")


func test_silhouette_tips_eligible_when_count_meets_minimum() -> void:
	# SD-TIP-6 exemption lifts when above_count >= silhouette_min_tips.
	# The weakest above-threshold tip must then be chosen over any below-threshold tip.
	var params := IvyParams.new()
	var mgr := TipManager.new()
	mgr.tower_height = 3.5
	var threshold := mgr.tower_height * params.silhouette_height_frac  # 2.8 m

	# Fill to hard cap - 1 with strong tips below threshold.
	for i in range(params.tip_cap_hard - 1):
		var t := Tip.new()
		t.id = i
		t.state = Tip.State.GROWING
		t.vigour = 1.0
		t.position = Vector3(0.0, threshold - 0.1, 0.0)
		t.stream = RngStream.from_seed(i)
		mgr.tips.append(t)

	# Add exactly silhouette_min_tips weak tips above threshold — count meets the minimum,
	# so the exemption does NOT apply and the weakest one should be the retirement candidate.
	for i in range(params.silhouette_min_tips):
		var t := Tip.new()
		t.id = params.tip_cap_hard + i
		t.state = Tip.State.GROWING
		t.vigour = 0.01  # weaker than below-threshold tips
		t.position = Vector3(0.0, threshold + 0.1, 0.0)
		t.stream = RngStream.from_seed(params.tip_cap_hard + i)
		mgr.tips.append(t)

	var parent := _make_parent(99999, 100.0)
	mgr.tips.append(parent)

	mgr.queue_branch(parent, Vector3.ZERO, Vector3.UP, Vector3.BACK, 0, params)

	# Exactly one above-threshold tip must have been retired.
	var retired_above := 0
	for t in mgr.tips:
		if t.position.y >= threshold and t.state == Tip.State.DORMANT:
			retired_above += 1
	assert_eq(retired_above, 1,
		"SD-TIP-6: one above-threshold tip must be retired when count >= silhouette_min_tips")


## W-040 regression — stall rule: GROWING → DORMANT on persistent low elongation.
## Tests call TipManager._check_stall() directly (the static helper also called from
## apply_lifecycle) so they don't need a full SimContext.

func _make_growing_tip_with_shoot(shoot: float) -> Tip:
	var t := Tip.new()
	t.state = Tip.State.GROWING
	t.shoot_length = shoot
	t.stream = RngStream.from_seed(7)
	return t


func test_stall_rule_tip_below_rate_goes_dormant_after_stall_days() -> void:
	# SD-TIP (W-040): GROWING → DORMANT when daily elongation < stall_rate for
	# stall_days consecutive game-days.  Drive the stall check through 4 day
	# boundaries with only a tiny elongation each day.
	var params := IvyParams.new()
	# stall_rate = 0.01 m/day, stall_days = 3
	var tpd: int = roundi(1.0 / params.sim_tick)  # 24 ticks per day at defaults

	var tip := _make_growing_tip_with_shoot(0.0)

	# Day 0 — initialise (tick 0, first encounter).
	TipManager._check_stall(tip, params, 0)
	assert_eq(tip.stall_day_last, 0, "stall_day_last must be set on first encounter")
	assert_eq(tip.state, Tip.State.GROWING, "must still be GROWING after initialisation")

	# Day 0 → 1: 0.001 m grown (< 0.01 stall_rate) → stall count = 1.
	tip.shoot_length = 0.001
	TipManager._check_stall(tip, params, tpd)
	assert_eq(tip.stall_consecutive_days, 1, "stall count must be 1 after first stall day")
	assert_eq(tip.state, Tip.State.GROWING, "must still be GROWING after 1 stall day (need 3)")

	# Day 1 → 2: 0.001 m more → stall count = 2.
	tip.shoot_length = 0.002
	TipManager._check_stall(tip, params, 2 * tpd)
	assert_eq(tip.stall_consecutive_days, 2, "stall count must be 2 after second stall day")
	assert_eq(tip.state, Tip.State.GROWING, "must still be GROWING after 2 stall days")

	# Day 2 → 3: 0.001 m more → stall count = 3 → DORMANT.
	tip.shoot_length = 0.003
	TipManager._check_stall(tip, params, 3 * tpd)
	assert_eq(tip.stall_consecutive_days, 3, "stall count must reach stall_days (3)")
	assert_eq(tip.state, Tip.State.DORMANT,
		"SD-TIP (W-040): tip below stall_rate for stall_days days must become DORMANT")


func test_stall_rule_tip_above_rate_stays_growing() -> void:
	# A tip growing faster than stall_rate must not go dormant.
	var params := IvyParams.new()
	var tpd: int = roundi(1.0 / params.sim_tick)

	var tip := _make_growing_tip_with_shoot(0.0)
	TipManager._check_stall(tip, params, 0)  # init

	# Simulate stall_days + 1 days of healthy growth (0.05 m/day >> stall_rate 0.01).
	for day in range(params.stall_days + 1):
		tip.shoot_length += 0.05  # well above 0.01 m/day
		TipManager._check_stall(tip, params, (day + 1) * tpd)

	assert_eq(tip.stall_consecutive_days, 0,
		"stall counter must stay 0 when elongation exceeds stall_rate every day")
	assert_eq(tip.state, Tip.State.GROWING,
		"tip above stall_rate every day must remain GROWING")


func test_stall_rule_counter_resets_on_good_day() -> void:
	# Two consecutive stall days followed by one good day must reset the counter.
	# The tip must NOT go dormant — it needs stall_days=3 *consecutive* stall days.
	var params := IvyParams.new()
	var tpd: int = roundi(1.0 / params.sim_tick)

	var tip := _make_growing_tip_with_shoot(0.0)
	TipManager._check_stall(tip, params, 0)  # init

	# Day 0→1: stall.
	tip.shoot_length = 0.001
	TipManager._check_stall(tip, params, tpd)
	assert_eq(tip.stall_consecutive_days, 1)

	# Day 1→2: stall.
	tip.shoot_length = 0.002
	TipManager._check_stall(tip, params, 2 * tpd)
	assert_eq(tip.stall_consecutive_days, 2)

	# Day 2→3: GOOD day — resets counter to 0.
	tip.shoot_length = 0.052  # 0.05 m added this day >> stall_rate
	TipManager._check_stall(tip, params, 3 * tpd)
	assert_eq(tip.stall_consecutive_days, 0, "good day must reset the stall counter")
	assert_eq(tip.state, Tip.State.GROWING, "must still be GROWING after counter reset")

	# Day 3→4 and 4→5: two more stall days — still only 2 consecutive, not dormant yet.
	tip.shoot_length = 0.053
	TipManager._check_stall(tip, params, 4 * tpd)
	tip.shoot_length = 0.054
	TipManager._check_stall(tip, params, 5 * tpd)
	assert_eq(tip.stall_consecutive_days, 2, "counter must be 2 after reset + 2 new stall days")
	assert_eq(tip.state, Tip.State.GROWING,
		"must still be GROWING — needs stall_days=3 consecutive, not 2")


func test_stall_rule_floating_tip_is_not_checked() -> void:
	# The stall rule only fires for GROWING (not FLOATING) tips.
	var params := IvyParams.new()
	var tpd: int = roundi(1.0 / params.sim_tick)

	var tip := _make_growing_tip_with_shoot(0.0)
	tip.state = Tip.State.FLOATING  # FLOATING tip
	TipManager._check_stall(tip, params, 0)

	# Drive three day boundaries with zero growth
	for day in range(params.stall_days + 1):
		TipManager._check_stall(tip, params, (day + 1) * tpd)

	assert_ne(tip.state, Tip.State.DORMANT,
		"SD-TIP: FLOATING tips must not go dormant via the stall rule")


func test_stall_rule_initialises_baseline_on_first_call() -> void:
	# On the very first call (stall_day_last == -1), the function initialises the
	# baseline and must NOT fire dormancy, even if shoot_length is already non-zero.
	var params := IvyParams.new()
	var tip := _make_growing_tip_with_shoot(5.0)  # big head-start
	TipManager._check_stall(tip, params, 0)

	assert_eq(tip.stall_day_last, 0, "stall_day_last must be set to 0 on first call")
	assert_almost_eq(tip.stall_day_shoot, 5.0, 1e-5, "stall_day_shoot must match current shoot_length")
	assert_eq(tip.stall_consecutive_days, 0, "counter must be 0 on first call")
	assert_eq(tip.state, Tip.State.GROWING, "must remain GROWING on first call")


func test_floating_tip_is_never_retired() -> void:
	# SD-TIP-5: floating tips are exempt from retirement even at the hard cap.
	var params := IvyParams.new()
	var mgr := TipManager.new()

	for i in range(params.tip_cap_hard):
		var t := Tip.new()
		t.id = i
		t.state = Tip.State.FLOATING
		t.vigour = 0.001
		t.stream = RngStream.from_seed(i)
		mgr.tips.append(t)

	var parent := _make_parent(params.tip_cap_hard, 100.0)
	mgr.tips.append(parent)
	var pre_size := mgr.tips.size()

	mgr.queue_branch(parent, Vector3.ZERO, Vector3.UP, Vector3.BACK, 0, params)

	# No floating tip may have been retired
	for t in mgr.tips:
		if t.state == Tip.State.FLOATING:
			continue
		if t.state == Tip.State.DORMANT:
			assert_true(false, "a floating tip was incorrectly retired (SD-TIP-5 violated)")
	# No child added (no eligible retiree)
	assert_eq(mgr.tips.size(), pre_size, "no child added when all eligible non-floating tips are exempt")
