## ivy-dsh.4 — Overhang traverse metrics at day 100 (G1–G5 + feeler cap).
##
## Seeds: 5 at y=0.05, z=0.01, x in {-4,-2,0,2,4}.
## Contract: eave_traversal_enabled=true + feeler_thinning_enabled=true (flag-ON overhang path).
## Interior filter for most metrics: |x| <= 6.
##
## OverhangSpec geometry (from overhang_spec.gd defaults):
##   wall:  x[-8,8], y[0,5.0], z[-0.4,0]      front normal +Z = SOUTH
##   slab:  y[5.0,5.3], z[-0.4,1.0]
##   soffit underside: y=5.0, z in [0,1]
##   lip face:   z = slab_projection = 1.0
##   roof top:   y = wall_height + slab_thickness = 5.3
##
## Thresholds (from ivy-dsh design + owner decisions 2026-10-18):
##   G1  >=1 interior seg with mid-z >= 0.80 (soffit-underside crawl)
##   G2  >=1 interior seg with mid-y > soffit + 0.02 (roof colonisation)
##   G3  >=1 seg with mid-z > slab_projection AND seg_b.y > seg_a.y (rising past lip)
##   G4  below-soffit off-face: p95 < 0.15, mean < 0.05, max < 0.40 (adhesion unharmed)
##   G5  traverse-sim stem >= 0.90 × plain-wall control (stem budget preserved)
##   Feeler cap: no 0.25 m x-bin with > 4 concurrent floating tips at day 100
##   segs_inside_solid == 0 (ivy-2d6 leak invariant on flag-ON path)
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

## Geometry thresholds (matching OverhangSpec defaults)
const SOFFIT_Y := 5.0        # wall_height
const SLAB_PROJECTION := 1.0 # slab_depth (z extent of eave beyond wall face)

## Metric thresholds
const G1_Z_MIN := 0.80       # soffit underside crawl: mid-z must reach here
const G2_Y_ABOVE_SOFFIT := 0.02
const G4_P95_LIMIT := 0.15
const G4_MEAN_LIMIT := 0.05
const G4_MAX_LIMIT  := 0.40
const G5_STEM_RATIO := 0.90
const FEELER_CAP := 4
const FEELER_BIN := 0.25
const FEELER_MIN_FLOAT := 0.05


## Build an overhang sim with traversal ON and 5 base seeds.
## Coroutine: awaits physics_frame AFTER build_from_spec so the ConcavePolygonShape3D
## is committed to the physics server before env.build() runs the light-bake raycasts.
## Pattern mirrors test_as1_coverage.gd _tower_sim_south().
func _make_traverse_sim() -> SimRoot:
	var ow := OverhangWall.new()
	add_child_autofree(ow)
	var spec := OverhangSpec.new()
	ow.build_from_spec(spec, true)
	await get_tree().physics_frame  # commit shape before light bake
	var params := IvyParams.new()
	params.eave_traversal_enabled = true
	params.feeler_thinning_enabled = true
	var sq := SurfaceQuery.new()
	sq.setup(
		ow.get_world_3d().direct_space_state,
		ow,
		OverhangSdf.new(spec),
		ow.face_material,
		params
	)
	var sim := SimRoot.new()
	sim.setup(params, sq, null, 0, null, false)
	for x in SEED_XS:
		sim.plant_at(Vector3(x, SEED_Y, SEED_Z), Conv.SOUTH)
	return sim


## Build a plain-wall control sim with the same 5 seeds (G5 denominator).
## Coroutine: awaits physics_frame AFTER build_from_spec so the shape is committed
## before the light bake runs.
func _make_plain_wall_sim() -> SimRoot:
	var wall := Wall.new()
	add_child_autofree(wall)
	var spec := WallSpec.new()
	spec.length = 16.0
	spec.height = 5.0
	spec.thickness = 0.4
	wall.build_from_spec(spec, true)
	await get_tree().physics_frame  # commit shape before light bake
	var params := IvyParams.new()
	var sq := SurfaceQuery.new()
	sq.setup(
		wall.get_world_3d().direct_space_state,
		wall,
		WallSdf.new(spec),
		wall.face_material,
		params
	)
	var sim := SimRoot.new()
	sim.setup(params, sq, null, 0, null, false)
	for x in SEED_XS:
		sim.plant_at(Vector3(x, SEED_Y, SEED_Z), Conv.SOUTH)
	return sim


func test_overhang_traverse_metrics_g1_to_g5() -> void:
	var spec := OverhangSpec.new()
	var sdf := OverhangSdf.new(spec)

	## Run traverse simulation — helper awaits physics_frame internally (bake-after-commit fix).
	var sim := await _make_traverse_sim()

	## Guard: real bake — the soffit shadow zone must be darker than the open wall face.
	## A pre-commit degenerate bake gives uniform max D_L everywhere and fails this check.
	## Soffit sample: y=4.9 (just below eave at 5.0), z=0.5 (halfway under projection).
	## Wall-face sample: y=2.5 (mid-height), z=0.01 (on the south face).
	var d_l_soffit := sim.env.sample_D_L(Vector3(0.0, 4.9, 0.5), -1, 0)
	var d_l_open   := sim.env.sample_D_L(Vector3(0.0, 2.5, 0.01), -1, 0)
	print("[traverse-metrics] guard d_l_soffit=%.4f d_l_open=%.4f" % [d_l_soffit, d_l_open])
	assert_true(d_l_soffit < d_l_open,
		"Guard [bake-commit]: soffit D_L %.4f must be < open-wall D_L %.4f (pre-commit bake is degenerate)" % [
			d_l_soffit, d_l_open])

	sim.advance_ticks(TICKS_PER_DAY * GAME_DAYS)
	var plant := sim.plant
	var tips := sim.tips

	var n_segs := plant.segment_count()
	print("[traverse-metrics] day=%d n_segs=%d total_length=%.2f" % [GAME_DAYS, n_segs, plant.total_length])

	## Collect per-segment metrics
	var g1_soffit_segs := 0         # mid-z >= G1_Z_MIN (soffit underside crawl)
	var g2_above_soffit_segs := 0   # mid-y > soffit + 0.02
	var g3_lip_traverse_segs := 0   # mid-z > slab_projection AND rising
	var off_face_below_soffit: Array = []
	var segs_inside_solid := 0

	for i in range(n_segs):
		var a := plant.seg_a[i]
		var b := plant.seg_b[i]
		var mid := (a + b) * 0.5
		## Interior filter
		if absf(mid.x) > INTERIOR_X_HALF:
			continue

		## segs_inside_solid: both endpoints must be outside the SDF
		if sdf.signed_distance(a) < 0.0 or sdf.signed_distance(b) < 0.0:
			segs_inside_solid += 1

		## G1: soffit underside crawl — mid-z >= G1_Z_MIN
		if mid.z >= G1_Z_MIN:
			g1_soffit_segs += 1

		## G2: roof colonisation — mid-y > soffit + 0.02
		if mid.y > SOFFIT_Y + G2_Y_ABOVE_SOFFIT:
			g2_above_soffit_segs += 1

		## G3 (owner-relaxed): mid-z > slab_projection AND segment is rising (b.y > a.y)
		if mid.z > SLAB_PROJECTION and b.y > a.y:
			g3_lip_traverse_segs += 1

		## G4: off-face distance for below-soffit segments
		if mid.y <= SOFFIT_Y:
			var d_a := absf(sdf.signed_distance(a))
			var d_b := absf(sdf.signed_distance(b))
			off_face_below_soffit.append(maxf(d_a, d_b))

	print("[traverse-metrics] G1=%d G2=%d G3=%d segs_inside_solid=%d" % [
		g1_soffit_segs, g2_above_soffit_segs, g3_lip_traverse_segs, segs_inside_solid])

	## segs_inside_solid invariant (ivy-2d6 leak invariant on flag-ON path)
	assert_eq(segs_inside_solid, 0,
		"ivy-2d6 leak invariant: %d seg endpoint(s) inside solid on traversal path" % segs_inside_solid)

	## G1: at least one soffit-underside segment with mid-z >= 0.80.
	## Re-tuned params (eave_traverse_light_floor=0.75, eave_approach_reach=0.40) provide
	## the speed boost needed to reach and crawl the dark soffit within 100 days (ivy-dsh.9).
	assert_gt(g1_soffit_segs, 0,
		"G1: must have >=1 interior seg with mid-z >= 0.80 (soffit underside crawl) — got %d" % g1_soffit_segs)

	## G2: at least one segment above the soffit (roof colonisation).
	assert_gt(g2_above_soffit_segs, 0,
		"G2: must have >=1 interior seg with mid-y > soffit+0.02 (roof colonisation) — got %d" % g2_above_soffit_segs)

	## G3: at least one lip-traverse segment (mid-z > slab_projection AND rising). >= 1.
	assert_gt(g3_lip_traverse_segs, 0,
		"G3: must have >=1 seg with mid-z > 1.0 AND rising (lip traverse) — got %d" % g3_lip_traverse_segs)

	## G4: below-soffit adhesion quality
	var n_g4 := off_face_below_soffit.size()
	assert_gt(n_g4, 0, "G4: expected some below-soffit interior segments")
	off_face_below_soffit.sort()
	var p95_idx: int = clampi(int(floorf(n_g4 * 0.95)), 0, n_g4 - 1)
	var g4_p95: float = off_face_below_soffit[p95_idx]
	var g4_sum: float = 0.0
	for d in off_face_below_soffit:
		g4_sum += d
	var g4_mean: float = g4_sum / float(n_g4)
	var g4_max: float = off_face_below_soffit[-1]
	print("[traverse-metrics] G4 n=%d p95=%.4f mean=%.4f max=%.4f" % [n_g4, g4_p95, g4_mean, g4_max])
	assert_lt(g4_p95, G4_P95_LIMIT,
		"G4: p95 off-face %.4f must be < %.2f" % [g4_p95, G4_P95_LIMIT])
	assert_lt(g4_mean, G4_MEAN_LIMIT,
		"G4: mean off-face %.4f must be < %.2f" % [g4_mean, G4_MEAN_LIMIT])
	assert_lt(g4_max, G4_MAX_LIMIT,
		"G4: max off-face %.4f must be < %.2f" % [g4_max, G4_MAX_LIMIT])

	## Feeler cap: check live floating tips at day 100
	var feeler_bins: Dictionary = {}  # int bin_key -> count
	var feeler_max_count := 0
	for t in tips.tips:
		if t.state != t.State.FLOATING:
			continue
		if t.floating_length <= FEELER_MIN_FLOAT:
			continue
		var bin_key := floori(t.position.x / FEELER_BIN)
		feeler_bins[bin_key] = feeler_bins.get(bin_key, 0) + 1
		feeler_max_count = maxi(feeler_max_count, feeler_bins[bin_key])
	print("[traverse-metrics] feeler_bins_occupied=%d max_per_bin=%d cap=%d" % [
		feeler_bins.size(), feeler_max_count, FEELER_CAP])
	assert_lte(feeler_max_count, FEELER_CAP,
		"Feeler cap: max feelers per 0.25 m bin is %d, must be <= %d" % [feeler_max_count, FEELER_CAP])

	## G5: stem length >= 0.90 × plain-wall control
	var traverse_stem: float = plant.total_length
	print("[traverse-metrics] traverse_stem=%.2f" % traverse_stem)

	## Disable overhang collision before plain-wall sim (M-1 pattern)
	for child in get_children():
		if child.get_script() != null and child.get_script().resource_path.contains("overhang_wall"):
			(child as StaticBody3D).collision_layer = 0
			for sh in child.get_children():
				if sh is CollisionShape3D:
					(sh as CollisionShape3D).disabled = true
	await get_tree().physics_frame

	## Helper awaits physics_frame internally after wall.build_from_spec (bake-after-commit).
	var plain_sim := await _make_plain_wall_sim()
	plain_sim.advance_ticks(TICKS_PER_DAY * GAME_DAYS)
	var plain_stem: float = plain_sim.plant.total_length
	print("[traverse-metrics] plain_stem=%.2f ratio=%.4f" % [plain_stem, traverse_stem / maxf(plain_stem, 0.001)])
	assert_true(traverse_stem >= G5_STEM_RATIO * plain_stem,
		"G5: traverse stem %.2f must be >= 0.9 * plain_wall %.2f = %.2f" % [
			traverse_stem, plain_stem, G5_STEM_RATIO * plain_stem])
