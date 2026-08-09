class_name TipManager
extends RefCounted

var tips: Array[Tip] = []
var _next_id: int = 0
var _pending: Array[Tip] = []


func live_in_id_order() -> Array[Tip]:
	var live: Array[Tip] = []
	for t in tips:
		if t.is_growing():
			live.append(t)
	return live


func live_count() -> int:
	var n := 0
	for t in tips:
		if t.is_live():
			n += 1
	return n


func refresh_vigour(ctx: SimContext) -> void:
	for t in tips:
		if not t.is_live():
			continue
		var d_l := ctx.env.sample_D_L(t.position, t.id, t.segment_count)
		var c := ctx.env.sample_crowding(t.position, t.id, t.segment_count)
		t.vigour = Physiology.f_L(d_l, ctx.params) * Physiology.f_C(c, ctx.params) * Physiology.f_S(t.floating_length, ctx.params)


func add_seed(position: Vector3, normal: Vector3, seed_value: int, params: IvyParams) -> Tip:
	var t := Tip.new()
	t.id = _next_id
	_next_id += 1
	t.position = position
	t.direction = Conv.UP
	t.random_dir = normal.cross(Conv.UP).normalized()
	if t.random_dir.length_squared() < 0.01:
		t.random_dir = Vector3.RIGHT
	t.last_contact_normal = normal
	t.state = Tip.State.GROWING
	t.stream = RngStream.from_seed(seed_value, params.dev_build)
	tips.append(t)
	return t


## Find the live non-floating tip with the lowest vigour, or null if none qualify.
## SD-TIP-5: floating tips are always exempt from retirement.
func _find_retirement_candidate() -> Tip:
	var best: Tip = null
	for t in tips:
		if not t.is_live():
			continue
		if t.state == Tip.State.FLOATING:
			continue
		if best == null or t.vigour < best.vigour:
			best = t
	return best


func queue_branch(parent: Tip, pos: Vector3, dir: Vector3, normal: Vector3, branch_idx: int, params: IvyParams) -> void:
	if live_count() >= params.tip_cap_hard:
		# SD-TIP-4: at the hard cap, allow a branch only by retiring the least-vigorous
		# live non-floating tip, and only when the parent's vigour sufficiently exceeds it.
		var retiree := _find_retirement_candidate()
		if retiree == null:
			return
		if parent.vigour <= retiree.vigour * params.retire_margin:
			return
		retiree.state = Tip.State.DORMANT
	var child := Tip.new()
	child.id = _next_id
	_next_id += 1
	child.position = pos
	child.direction = dir.normalized()
	child.random_dir = parent.random_dir
	child.branch_order = parent.branch_order + 1
	child.floating_length = parent.floating_length
	child.last_contact_normal = normal
	child.state = Tip.State.GROWING
	child.stream = parent.stream.derive(branch_idx)
	child.branch_index = branch_idx
	tips.append(child)
	_pending.append(child)


func apply_pending_branches() -> void:
	_pending.clear()


func apply_lifecycle(ctx: SimContext) -> void:
	for t in tips:
		if t.state == Tip.State.FLOATING and t.floating_length > ctx.params.max_float:
			t.state = Tip.State.DEAD
		# Strikes are counted in GrowthStep, at the point a tip actually tries to grow
		# below ground. Counting them here from position alone charges a strike every
		# tick to any tip merely resting on the clamp plane -- including a seed placed
		# at ground level, which is retired before it can emit its first segment.
		if t.position.y < ctx.params.ground_y_min:
			t.position.y = ctx.params.ground_y_min
		if t.ground_strikes >= 5:
			t.state = Tip.State.DORMANT


## SD-TIP-3: taper q that scales branch probability smoothly from 1.0 at the soft cap
## down to 0.0 at the hard cap. Below soft: returns 1.0. At/above hard: returns 0.0.
func branch_probability_scale(params: IvyParams) -> float:
	var n := live_count()
	if n < params.tip_cap_soft:
		return 1.0
	if n >= params.tip_cap_hard:
		return 0.0
	return clampf(
		float(params.tip_cap_hard - n) / float(params.tip_cap_hard - params.tip_cap_soft),
		0.0, 1.0
	)


## SD-TIP-2: below the hard cap, normal (or tapered) branching is permitted.
## SD-TIP-4 retirement is handled inside queue_branch and is not gated here.
func can_branch(params: IvyParams) -> bool:
	return live_count() < params.tip_cap_hard
