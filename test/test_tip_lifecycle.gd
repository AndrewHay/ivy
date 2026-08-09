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


func test_midway_between_soft_and_hard_scale_is_half() -> void:
	var params := IvyParams.new()
	var mgr := TipManager.new()
	var mid := (params.tip_cap_soft + params.tip_cap_hard) / 2
	_fill_manager_with_growing_tips(mgr, mid)
	var q: float = mgr.branch_probability_scale(params)
	var expected := float(params.tip_cap_hard - mid) / float(params.tip_cap_hard - params.tip_cap_soft)
	assert_almost_eq(q, expected, 1e-4)


func test_can_branch_true_below_hard_cap() -> void:
	var params := IvyParams.new()
	var mgr := TipManager.new()
	# The hard cap is tip_cap_hard = 160; one below should still allow branching.
	_fill_manager_with_growing_tips(mgr, params.tip_cap_hard - 1)
	assert_true(mgr.can_branch(params), "can_branch must be true one below the hard cap")


func test_can_branch_false_at_hard_cap() -> void:
	var params := IvyParams.new()
	var mgr := TipManager.new()
	_fill_manager_with_growing_tips(mgr, params.tip_cap_hard)
	assert_false(mgr.can_branch(params), "can_branch must be false at the hard cap")


func test_queue_branch_at_hard_cap_retires_weak_tip() -> void:
	# SD-TIP-4: a branch may be created at the hard cap by retiring a weaker tip.
	var params := IvyParams.new()
	var mgr := TipManager.new()
	_fill_manager_with_growing_tips(mgr, params.tip_cap_hard, 0.1)  # 160 weak tips

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
