## ivy-9us — Overhang (eave-wall) growth metrics at day 100 (M1–M8).
##
## Seeds: 5 at y=0.05, z=0.01, x in {-4,-2,0,2,4}.
## Scope for M1–M7: interior |x| <= 6, below soffit (mid-y <= wall_height).
## M8 control: same spec + seeds on the plain test_wall (same sim dimensions otherwise).
##
## Thresholds (from ivy-9us.1 design):
##   M1 p95 off-face < 0.15 (adhesion_range)
##   M2 mean off-face < 0.05
##   M3 max off-face < 0.40 (max_float sag guard)
##   M4 max climb y >= soffit - 0.3  (= 4.7)
##   M5 lateral spread band [soffit-1..soffit] >= 0.6 * seed_span (0.6*8 = 4.8)
##   M6 0 segments with mid-y > soffit + 0.02  (no roof/above-eave growth)
##   M7 0 level/rising segments with mid-z > slab_projection + 0.10, and none beyond
##      projection + 0.40 (no past-eave-lip bridging; drooping tendrils allowed)
##   M8 overhang stem >= 0.90 * plain-wall stem
extends GutTest

const OverhangSpec = preload("res://src/world/overhang_spec.gd")
const OverhangSdf = preload("res://src/world/overhang_sdf.gd")
const OverhangWall = preload("res://src/world/overhang_wall.gd")
const Wall = preload("res://src/world/wall.gd")
const WallSpec = preload("res://src/world/wall_spec.gd")
const WallSdf = preload("res://src/world/wall_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const Conv = preload("res://src/core/conv.gd")

const TICKS_PER_DAY := 24
const GAME_DAYS := 100

## Seeds: x in {-4,-2,0,2,4}, y=0.05, z=0.01
const SEED_XS: Array = [-4.0, -2.0, 0.0, 2.0, 4.0]
const SEED_Y := 0.05
const SEED_Z := 0.01

## Interior filter: |x| <= 6
const INTERIOR_X_HALF := 6.0

## Metric thresholds (from design ivy-9us.1)
const ADHESION_RANGE := 0.15
const M1_P95_LIMIT := 0.15
const M2_MEAN_LIMIT := 0.05
const M3_MAX_LIMIT  := 0.40
const M8_STEM_RATIO := 0.90


## Build an overhang sim with 5 base seeds.
func _make_overhang_sim() -> SimRoot:
	var ow := OverhangWall.new()
	add_child_autofree(ow)
	var spec := OverhangSpec.new()
	ow.build_from_spec(spec, true)
	var sq := SurfaceQuery.new()
	sq.setup(
		ow.get_world_3d().direct_space_state,
		ow,
		OverhangSdf.new(spec),
		ow.face_material,
		IvyParams.new()
	)
	var sim := SimRoot.new()
	sim.setup(IvyParams.new(), sq, null, 0, null, false)
	for x in SEED_XS:
		sim.plant_at(Vector3(x, SEED_Y, SEED_Z), Conv.SOUTH)
	return sim


## Build a plain-wall sim with the same 5 base seeds (M8 control).
func _make_plain_wall_sim() -> SimRoot:
	var wall := Wall.new()
	add_child_autofree(wall)
	## Use a WallSpec matching the overhang's wall dimensions.
	var spec := WallSpec.new()
	spec.length = 16.0
	spec.height = 5.0
	spec.thickness = 0.4
	wall.build_from_spec(spec, true)
	var sq := SurfaceQuery.new()
	sq.setup(
		wall.get_world_3d().direct_space_state,
		wall,
		WallSdf.new(spec),
		wall.face_material,
		IvyParams.new()
	)
	var sim := SimRoot.new()
	sim.setup(IvyParams.new(), sq, null, 0, null, false)
	for x in SEED_XS:
		sim.plant_at(Vector3(x, SEED_Y, SEED_Z), Conv.SOUTH)
	return sim


func test_overhang_growth_metrics_m1_to_m8() -> void:
	var spec := OverhangSpec.new()
	var soffit_y: float = spec.wall_height          # 5.0
	var projection: float = spec.slab_projection     # 1.0
	var seed_span: float = (SEED_XS[-1] - SEED_XS[0]) as float  # 8.0

	## Run overhang simulation
	var sim := _make_overhang_sim()
	await get_tree().physics_frame
	sim.advance_ticks(TICKS_PER_DAY * GAME_DAYS)
	var plant := sim.plant

	## M-2: hoist OverhangSdf out of the per-segment loop.
	var sdf := OverhangSdf.new(spec)
	var slab_thickness: float = spec.slab_thickness

	## Collect interior (|x|<=6) segments below the soffit
	var off_face_below_soffit: Array[float] = []
	var max_climb_y: float = 0.0
	var spread_x_min: float = INF
	var spread_x_max: float = -INF
	var segs_above_soffit: int = 0  ## M6 spec: y > soffit+0.02 (interior)
	var segs_past_lip: int = 0      ## M7: z > proj+0.10

	## C-2 diagnostic buckets for above-soffit interior segments (ivy-9us.3 review)
	var diag_eave_lip_face: int = 0   ## z >= projection-0.15 (front face of slab, z~proj)
	var diag_slab_top: int = 0        ## y >= soffit+slab_thickness-0.10 (roof surface)
	var diag_slab_back: int = 0       ## z <= -wall_thickness+0.10 (north slab face)
	var diag_other: int = 0           ## anything else above soffit in interior
	var diag_samples: Array = []      ## first 6 positions for the handoff

	var segs_inside_solid: int = 0  ## ivy-2d6: any x, endpoint more than 5 mm inside
	var n_segs: int = plant.segment_count()
	for i in range(n_segs):
		var mid: Vector3 = (plant.seg_a[i] + plant.seg_b[i]) * 0.5
		if sdf.signed_distance(plant.seg_b[i]) < -0.005:
			segs_inside_solid += 1
		## Interior filter
		if absf(mid.x) > INTERIOR_X_HALF:
			continue
		## Track max climb (any height)
		max_climb_y = maxf(max_climb_y, mid.y)
		## M6 spec criterion: 0 interior segments with mid-y > soffit+0.02
		if mid.y > soffit_y + 0.02:
			segs_above_soffit += 1
			## Diagnostic buckets to characterise where they are
			if mid.z >= projection - 0.15:
				diag_eave_lip_face += 1
			elif mid.y >= soffit_y + slab_thickness - 0.10:
				diag_slab_top += 1
			elif mid.z <= -spec.wall_thickness + 0.10:
				diag_slab_back += 1
			else:
				diag_other += 1
			if diag_samples.size() < 6:
				diag_samples.append(mid)
		## M7: past the eave lip (10 cm margin) is only a failure for a level/rising stem
		## (a bridge standing on air) or one beyond the 0.4 m sag guard. Tendrils that
		## curl over the lip and droop are allowed.
		if mid.z > projection + 0.10:
			var drooping: bool = plant.seg_b[i].y < plant.seg_a[i].y
			if not drooping or mid.z > projection + M3_MAX_LIMIT:
				segs_past_lip += 1
		## Below-soffit scope for M1–M5
		if mid.y > soffit_y:
			continue
		## Off-face distance: absolute SDF at segment endpoints (M-2: sdf hoisted)
		var d_a: float = absf(sdf.signed_distance(plant.seg_a[i]))
		var d_b: float = absf(sdf.signed_distance(plant.seg_b[i]))
		var off := maxf(d_a, d_b)
		off_face_below_soffit.append(off)
		## Lateral spread: x extent in the eave band [soffit-1, soffit]
		if mid.y >= soffit_y - 1.0:
			spread_x_min = minf(spread_x_min, mid.x)
			spread_x_max = maxf(spread_x_max, mid.x)

	var n := off_face_below_soffit.size()
	assert_gt(n, 0, "Expected interior below-soffit segments at day %d" % GAME_DAYS)

	## M1: p95 off-face < adhesion_range
	off_face_below_soffit.sort()
	var p95_idx: int = int(floorf(n * 0.95))
	p95_idx = clampi(p95_idx, 0, n - 1)
	var m1_p95: float = off_face_below_soffit[p95_idx]
	print("[overhang-metrics] n_segs=%d interior_below=%d p95_off=%.4f" % [n_segs, n, m1_p95])
	assert_lt(m1_p95, M1_P95_LIMIT,
		"M1: p95 off-face %.4f must be < adhesion_range %.2f" % [m1_p95, M1_P95_LIMIT])

	## M2: mean off-face < 0.05
	var sum_off: float = 0.0
	for d in off_face_below_soffit:
		sum_off += d
	var m2_mean: float = sum_off / float(n)
	print("[overhang-metrics] mean_off=%.4f" % m2_mean)
	assert_lt(m2_mean, M2_MEAN_LIMIT,
		"M2: mean off-face %.4f must be < %.2f" % [m2_mean, M2_MEAN_LIMIT])

	## M3: max off-face < max_float sag guard 0.40
	var m3_max: float = off_face_below_soffit[-1]
	print("[overhang-metrics] max_off=%.4f" % m3_max)
	assert_lt(m3_max, M3_MAX_LIMIT,
		"M3: max off-face %.4f must be < %.2f (sag guard)" % [m3_max, M3_MAX_LIMIT])

	## M4: max climb >= soffit - 0.3
	var m4_threshold: float = soffit_y - 0.3
	print("[overhang-metrics] max_climb_y=%.4f soffit=%.1f threshold=%.1f" % [max_climb_y, soffit_y, m4_threshold])
	assert_true(max_climb_y >= m4_threshold,
		"M4: max climb y %.4f must be >= soffit-0.3 = %.1f" % [max_climb_y, m4_threshold])

	## M5: lateral spread in eave band >= 0.6 * seed_span
	var m5_spread: float = 0.0
	if spread_x_max >= spread_x_min:
		m5_spread = spread_x_max - spread_x_min
	var m5_threshold: float = 0.6 * seed_span
	print("[overhang-metrics] spread_x=%.4f threshold=%.4f (0.6*%.1f)" % [m5_spread, m5_threshold, seed_span])
	assert_true(m5_spread >= m5_threshold,
		"M5: lateral spread %.4f must be >= 0.6 * seed_span = %.4f" % [m5_spread, m5_threshold])

	## M6: spec criterion — 0 interior segments with mid-y > soffit+0.02
	## Diagnostic breakdown (ivy-9us.3 review finding C-2):
	##   diag_eave_lip_face: z >= projection-0.15 (front face of slab, z~proj)
	##   diag_slab_top:      y >= soffit+st-0.10  (roof surface going-around)
	##   diag_slab_back:     z <= -thickness+0.10 (north slab face)
	##   diag_other:         anything else interior above soffit
	print("[overhang-metrics] segs_above_soffit=%d (eave_lip=%d slab_top=%d slab_back=%d other=%d)" % [
		segs_above_soffit, diag_eave_lip_face, diag_slab_top, diag_slab_back, diag_other])
	if diag_samples.size() > 0:
		print("[overhang-metrics] M6 sample positions above soffit: %s" % str(diag_samples))
	assert_eq(segs_above_soffit, 0,
		"M6: %d interior segs above soffit+0.02 (eave_lip=%d slab_top=%d slab_back=%d other=%d)" % [
			segs_above_soffit, diag_eave_lip_face, diag_slab_top, diag_slab_back, diag_other])

	print("[overhang-metrics] segs_inside_solid=%d" % segs_inside_solid)
	assert_eq(segs_inside_solid, 0,
		"ivy-2d6: %d segment endpoint(s) inside the solid; tips must stay outside geometry" % segs_inside_solid)

	## M7: no segments clearly past the eave lip (10 cm margin)
	print("[overhang-metrics] segs_past_lip=%d" % segs_past_lip)
	assert_eq(segs_past_lip, 0,
		"M7: %d level/rising or >0.4 m segment(s) past eave lip; expected 0" % segs_past_lip)

	## M8: stem length >= 0.90 * plain-wall stem
	var overhang_stem: float = plant.total_length
	print("[overhang-metrics] overhang_stem=%.2f" % overhang_stem)

	## M-1 fix: disable overhang collision before plain-wall sim so the
	## control grows in clean physics space (no phantom slab ceiling).
	for child in get_children():
		if child.get_script() == OverhangWall:
			(child as StaticBody3D).collision_layer = 0
			for sh in child.get_children():
				if sh is CollisionShape3D:
					(sh as CollisionShape3D).disabled = true
	await get_tree().physics_frame

	## Run plain-wall control
	var plain_sim := _make_plain_wall_sim()
	await get_tree().physics_frame
	plain_sim.advance_ticks(TICKS_PER_DAY * GAME_DAYS)
	var plain_stem: float = plain_sim.plant.total_length
	print("[overhang-metrics] plain_stem=%.2f ratio=%.4f" % [plain_stem, overhang_stem / maxf(plain_stem, 0.001)])
	assert_true(overhang_stem >= M8_STEM_RATIO * plain_stem,
		"M8: overhang stem %.2f must be >= 0.9 * plain_wall %.2f = %.2f" % [
			overhang_stem, plain_stem, M8_STEM_RATIO * plain_stem])
