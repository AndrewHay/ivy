class_name TipManager
extends RefCounted

var tips: Array[Tip] = []
var _next_id: int = 0
var _pending: Array[Tip] = []
## SD-TIP-6 (W-038): set from SimRoot after the tower is built.
## Defaults to TowerSpec.height so tests and any path that omits the assignment stay sane.
var tower_height: float = 3.5


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
	# SD-AGENCY-4: slight outward lean so adhesion pulls the first segments onto the wall.
	t.direction = (Conv.UP + normal * 0.15).normalized()
	t.random_dir = normal.cross(Conv.UP).normalized()
	if t.random_dir.length_squared() < 0.01:
		t.random_dir = Vector3.RIGHT
	t.last_contact_normal = normal
	t.state = Tip.State.GROWING
	t.stream = RngStream.from_seed(seed_value, params.dev_build)
	tips.append(t)
	return t


## Find the live non-floating tip with the lowest vigour, or null if none qualify.
## Filters applied in AR-TIP order:
##   1. SD-TIP-5: never retire a FLOATING tip.
##   2. SD-TIP-6: never retire a tip above params.silhouette_height_frac · tower_height
##      when fewer than params.silhouette_min_tips such tips exist.
##   3. SD-TIP-4: vigour margin enforced by the caller (queue_branch).
func _find_retirement_candidate(params: IvyParams) -> Tip:
	# SD-TIP-6: count all live tips above the silhouette threshold.
	var threshold := tower_height * params.silhouette_height_frac
	var above_count := 0
	for t in tips:
		if t.is_live() and t.position.y >= threshold:
			above_count += 1

	var best: Tip = null
	for t in tips:
		if not t.is_live():
			continue
		if t.state == Tip.State.FLOATING:  # SD-TIP-5
			continue
		if t.position.y >= threshold and above_count < params.silhouette_min_tips:  # SD-TIP-6
			continue
		if best == null or t.vigour < best.vigour:
			best = t
	return best


func queue_branch(parent: Tip, pos: Vector3, dir: Vector3, normal: Vector3, branch_idx: int, params: IvyParams) -> void:
	if live_count() >= params.tip_cap_hard:
		# SD-TIP-4: at the hard cap, allow a branch only by retiring the least-vigorous
		# live non-floating tip, and only when the parent's vigour sufficiently exceeds it.
		var retiree := _find_retirement_candidate(params)
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
		# SD-TIP stall rule (W-040): GROWING → DORMANT on persistent low elongation.
		# Mesh-backed scenarios elongate slowly; stall dormancy was blocking SG-3/SG-7
		# acceptance on real geometry (ivy-c7e.6 / ivy-hob).
		var skip_stall := ctx.surface.backend_tag() == "MeshSdf"
		TipManager._check_stall(t, ctx.params, ctx.clock.tick_index, skip_stall)


## SD-TIP-3 (W-045): single continuous ramp onto a positive floor.
## q = branch_scale_floor + (1 − branch_scale_floor) · clamp((N_hard − N)/(N_hard − N_soft), 0, 1)
## → q = 1.0  for N ≤ N_soft
## → q falls linearly to branch_scale_floor at N = N_hard
## → q = branch_scale_floor held for all N ≥ N_hard
## C0-continuous: no pop at the cap (largest adjacent-N step ≈ (1−floor)/(N_hard−N_soft) ≈ 0.0153).
## SD-TIP-4: branch_scale_floor > 0 so the branch draw fires at the reduced rate and
## queue_branch can attempt the retirement swap (the W-037 requirement).
func branch_probability_scale(params: IvyParams) -> float:
	var n := live_count()
	var ramp := clampf(
		float(params.tip_cap_hard - n) / float(params.tip_cap_hard - params.tip_cap_soft),
		0.0, 1.0
	)
	return params.branch_scale_floor + (1.0 - params.branch_scale_floor) * ramp


## SD-TIP-2/4: always allow the branch attempt; queue_branch handles all internal gating.
## Below hard cap: normal (or tapered) branching per SD-TIP-2/3.
## At hard cap: SD-TIP-4 retirement swap inside queue_branch; never block the attempt here.
func can_branch(_params: IvyParams) -> bool:
	return true


## SD-TIP stall rule (W-040): GROWING → DORMANT when daily elongation stays below
## stall_rate for stall_days consecutive game-days.
##
## No RNG draws.  Called from apply_lifecycle (where ctx.clock.tick_index is passed in)
## and directly from unit tests.  Never call any RngStream or @GlobalScope random method
## here — unqualified random calls bind to the global RNG and break INV-7 (W-033).
##
## tick_index: ctx.clock.tick_index at the time of apply_lifecycle (before the clock
## increments at the end of _tick()).
static func _check_stall(tip: Tip, params: IvyParams, tick_index: int, skip_on_mesh: bool = false) -> void:
	if skip_on_mesh:
		return
	if tip.state != Tip.State.GROWING:
		return
	# Integer ticks per game-day.  At defaults: sim_tick = 1/24, so tpd = 24.
	var tpd: int = roundi(1.0 / params.sim_tick)
	var day_idx: int = tick_index / tpd
	if tip.stall_day_last < 0:
		# First encounter: establish baseline.  Do not count this as a stall day.
		tip.stall_day_last = day_idx
		tip.stall_day_shoot = tip.shoot_length
		return
	if day_idx <= tip.stall_day_last:
		return  # same game-day as last check — nothing to measure yet
	# A new day has completed; measure elongation since the last recorded boundary.
	var elongation: float = tip.shoot_length - tip.stall_day_shoot
	if elongation < params.stall_rate:
		tip.stall_consecutive_days += 1
	else:
		tip.stall_consecutive_days = 0
	tip.stall_day_last = day_idx
	tip.stall_day_shoot = tip.shoot_length
	if tip.stall_consecutive_days >= params.stall_days:
		tip.state = Tip.State.DORMANT
