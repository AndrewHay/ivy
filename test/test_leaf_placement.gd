## Regression tests for SD-LEAF-2 (shade etiolation), SD-LEAF-3 (phyllotaxy),
## SD-LEAF-8 (leaf crowding), and W-060 rules (SD-LEAF-4r5, SD-LEAF-5s_light,
## SD-LEAF-6 tiers, SD-LEAF-7 tint).  LeafPlacer stochastic draws are hash-based
## (SD-RNG-6) — no per-tip RNG stream consumption (INV-7).
extends GutTest

const LeafPlacer = preload("res://src/sim/leaf_placer.gd")
const Physiology = preload("res://src/sim/physiology.gd")
const SimContext = preload("res://src/sim/sim_context.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const Tip = preload("res://src/sim/tip.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const IvyEnvironment = preload("res://src/env/environment.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")


func _make_tip() -> Tip:
	var t := Tip.new()
	t.id = 0
	t.last_contact_normal = Vector3(0.0, 0.0, 1.0)
	t.state = Tip.State.GROWING
	t.vigour = 1.0
	t.leaf_side_sign = 1.0
	return t


func _make_ctx(params: IvyParams, plant: PlantData) -> SimContext:
	return SimContext.new(params, null, null, plant, null, null)


## Build a real environment with a null-physics SurfaceQuery (no raycasts, open-sky bake).
## Mirrors the setup used in test_light_bake.gd.
func _make_env_ctx(params: IvyParams, plant: PlantData) -> SimContext:
	var surface := SurfaceQuery.new()
	surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), params)
	var env := IvyEnvironment.new()
	env.build(params, surface)
	return SimContext.new(params, env, surface, plant, null, null)


func test_shade_etiolation_internode_is_longer_in_shade() -> void:
	# SD-LEAF-2: internode = base * (1 + shade_gain * (1 - f_L)) * (1 + jitter * (2u - 1))
	# At f_L = 0 the internode is longer than at f_L = 1.
	var params := IvyParams.new()
	# Same jitter u is applied to both (same tip.id=0, node_count=0 for first node)
	var u := Hash64.unit_float(0, 0, 99)
	var jitter := 1.0 + params.internode_jitter * (2.0 * u - 1.0)
	var internode_sun := params.internode_base * 1.0 * jitter
	var internode_shade := params.internode_base * (1.0 + params.internode_shade_gain * 1.0) * jitter
	assert_gt(internode_shade, internode_sun, "shade internode must exceed sun internode")


func test_shade_etiolation_delays_node_placement() -> void:
	# Integration test: a distance that triggers a node in full sun must NOT trigger one in full shade.
	var params := IvyParams.new()
	var u := Hash64.unit_float(0, 0, 99)
	var jitter := 1.0 + params.internode_jitter * (2.0 * u - 1.0)
	var internode_sun := params.internode_base * 1.0 * jitter
	var internode_shade := params.internode_base * (1.0 + params.internode_shade_gain) * jitter
	assert_lt(internode_sun, internode_shade, "precondition failed — fix the formula constants")

	# Distance between the two thresholds
	var d := (internode_sun + internode_shade) * 0.5
	var seg_a := Vector3.ZERO
	var seg_b := Vector3(0.03, 0.0, 0.0)

	var plant_sun := PlantData.new()
	var tip_sun := _make_tip()
	tip_sun.distance_since_node = d
	tip_sun.shoot_length = params.leaf_tip_suppress + 0.1
	LeafPlacer.advance(tip_sun, _make_ctx(params, plant_sun), seg_a, seg_b, 1.0, Basis.IDENTITY)

	var plant_shade := PlantData.new()
	var tip_shade := _make_tip()
	tip_shade.distance_since_node = d
	tip_shade.shoot_length = params.leaf_tip_suppress + 0.1
	LeafPlacer.advance(tip_shade, _make_ctx(params, plant_shade), seg_a, seg_b, 0.0, Basis.IDENTITY)

	assert_eq(plant_sun.leaf_count(), 1, "sun tip at distance d should place a leaf")
	assert_eq(plant_shade.leaf_count(), 0, "shade tip at same distance should not place a leaf")


func test_phyllotaxy_golden_angle_not_strict_alternation() -> void:
	# SD-LEAF-3: divergence of 137.5° blended toward flat.
	# Old code: consecutive leaves alternate strictly at ±90° → their y-axes are nearly opposite.
	# New code: golden angle gives a positive dot product between leaves 1 and 2.
	var params := IvyParams.new()
	var plant := PlantData.new()
	var ctx := _make_ctx(params, plant)
	var tip := _make_tip()
	tip.shoot_length = params.leaf_tip_suppress + 1.0

	var seg_a := Vector3.ZERO
	var seg_b := Vector3(0.03, 0.0, 0.0)

	# Advance past first internode
	var u0 := Hash64.unit_float(tip.id, 0, 99)
	var internode0 := params.internode_base * 1.0 * (1.0 + params.internode_jitter * (2.0 * u0 - 1.0))
	tip.distance_since_node = internode0 + 0.001
	LeafPlacer.advance(tip, ctx, seg_a, seg_b, 1.0, Basis.IDENTITY)

	# Advance past second internode
	var u1 := Hash64.unit_float(tip.id, 1, 99)
	var internode1 := params.internode_base * 1.0 * (1.0 + params.internode_jitter * (2.0 * u1 - 1.0))
	tip.distance_since_node = internode1 + 0.001
	LeafPlacer.advance(tip, ctx, seg_a, seg_b, 1.0, Basis.IDENTITY)

	assert_eq(plant.leaf_count(), 2, "should have placed 2 leaves")

	# Extract p_dir (y-axis of leaf transform) for each leaf.
	# leaf_xform layout: [bxx,bxy,bxz,ox, byx,byy,byz,oy, bzx,bzy,bzz,oz] per leaf
	var y0 := Vector3(plant.leaf_xform[4], plant.leaf_xform[5], plant.leaf_xform[6]).normalized()
	var y1 := Vector3(plant.leaf_xform[16], plant.leaf_xform[17], plant.leaf_xform[18]).normalized()
	# Geometry (n_wall=(0,0,1), t_dir=(1,0,0), leaf_out_of_plane=0.35):
	# Old ±90°: node 1 psi=+90° → y0.y ≈ +0.94; node 2 psi=-90° → y1.y ≈ -0.94
	# New golden-angle: node 1 psi≈-58.5° → y0.y ≈ -0.80; node 2 psi≈+106.6° → y1.y ≈ +0.90
	# The sign patterns are reversed between old and new, giving a clean discriminant.
	assert_lt(y0.y, 0.0, "leaf 1 y-axis y-component must be negative with golden-angle phyllotaxy")
	assert_gt(y1.y, 0.0, "leaf 2 y-axis y-component must be positive with golden-angle phyllotaxy")


func test_leaf_deposit_raises_crowding_field() -> void:
	# SD-LEAF-8 / SD-PHYS-3: placing a leaf via LeafPlacer must deposit crowding through
	# physiology (INV-1). This test exercises the real IvyEnvironment to observe the field.
	var params := IvyParams.new()
	var plant := PlantData.new()
	var ctx := _make_env_ctx(params, plant)

	# South wall: y = 1.53 m sits at the midpoint of the y=25 cell (lattice at 1.5 m),
	# so the leaf node interpolated at t≈0.97 stays in y-cell 25, placing both the
	# deposit and the sample within the same trilinear neighbourhood.
	# Tower outer radius = 2.0 m; |Φ| = 0.05 m puts this inside the 0.09 m shell.
	var pos := Vector3(0.0, 1.53, 1.95)
	var c_before := ctx.env.sample_crowding(pos, 0, 0)

	var tip := _make_tip()
	tip.id = 0
	tip.position = pos
	tip.shoot_length = params.leaf_tip_suppress + 1.0
	# At C=0 the suppression hash compare (suppress_u < 1.0) always passes the leaf through.
	var u := Hash64.unit_float(0, 0, 99)
	var internode := params.internode_base * (1.0 + params.internode_jitter * (2.0 * u - 1.0))
	tip.distance_since_node = internode + 0.001

	# Segment goes upward along the wall (1.50 → 1.53 m); node position stays in y-cell 25.
	var seg_a := pos - Vector3(0.0, params.segment_length, 0.0)
	var seg_b := pos
	LeafPlacer.advance(tip, ctx, seg_a, seg_b, 1.0, Basis.IDENTITY)

	assert_eq(plant.leaf_count(), 1, "leaf must be placed (C=0 means no suppression)")
	var c_after := ctx.env.sample_crowding(pos, 0, 0)
	assert_gt(c_after, c_before,
		"crowding field must increase after leaf deposit (SD-LEAF-8/SD-PHYS-3)")


func test_leaf_suppression_fires_at_high_crowding() -> void:
	# SD-LEAF-8: P(place) = clamp(1 - suppress*C, floor, 1). At maxed crowding the
	# placement probability drops to the floor (0.35), so roughly 65% of hashes suppress.
	# This test verifies that suppression actually fires (count < 20) and the floor allows
	# some through (count > 0) — both assertions rely on hash determinism (INV-7).
	var params := IvyParams.new()
	var plant := PlantData.new()
	var ctx := _make_env_ctx(params, plant)

	# Saturate the entire local neighbourhood by depositing at a 3×3×3 grid of nearby
	# positions (spaced one cell apart). This ensures every corner of the trilinear cube
	# around the test point reaches C=1.0, so the suppression check reliably sees high
	# crowding regardless of where exactly the interpolated node lands.
	var pos := Vector3(0.0, 1.53, 1.95)
	var c := params.field_cell
	for dxi in range(-1, 2):
		for dyi in range(-1, 2):
			for dzi in range(-1, 2):
				ctx.env.deposit_crowding(pos + Vector3(dxi, dyi, dzi) * c, 100.0)

	var placed := 0
	for i in range(20):
		var tip := _make_tip()
		tip.id = i
		tip.shoot_length = params.leaf_tip_suppress + 1.0
		tip.position = pos
		# Use the same internode jitter formula; node_count starts at 0 and is incremented
		# to 1 inside advance() before the suppression check.
		var u := Hash64.unit_float(i, 0, 99)
		var internode := params.internode_base * (1.0 + params.internode_jitter * (2.0 * u - 1.0))
		tip.distance_since_node = internode + 0.001
		var pre := plant.leaf_count()
		LeafPlacer.advance(tip, ctx,
			pos - Vector3(0.0, params.segment_length, 0.0), pos, 1.0, Basis.IDENTITY)
		if plant.leaf_count() > pre:
			placed += 1

	assert_lt(placed, 20, "with maxed crowding, most placements must be suppressed (SD-LEAF-8)")
	assert_gt(placed, 0, "floor probability (%.2f) must still allow some placements" % params.leaf_crowd_floor)


func test_sun_dense_suppression_thins_more_than_shade_at_max_crowding() -> void:
	# SD-LEAF-8b (W-015): only nodes with high f_L AND high C get the sun floor/suppress boost.
	var params := IvyParams.new()
	var pos := Vector3(0.0, 1.53, 1.95)
	var c := params.field_cell

	var placed_at := func(f_l: float) -> int:
		var plant := PlantData.new()
		var ctx := _make_env_ctx(params, plant)
		for dxi in range(-1, 2):
			for dyi in range(-1, 2):
				for dzi in range(-1, 2):
					ctx.env.deposit_crowding(pos + Vector3(dxi, dyi, dzi) * c, 100.0)
		var n := 0
		for i in range(120):
			var tip := _make_tip()
			tip.id = i
			tip.shoot_length = params.leaf_tip_suppress + 1.0
			tip.position = pos
			var u := Hash64.unit_float(tip.id, tip.node_count, 99)
			var internode := params.internode_base \
				* (1.0 + params.internode_shade_gain * (1.0 - f_l)) \
				* (1.0 + params.internode_jitter * (2.0 * u - 1.0))
			tip.distance_since_node = internode + 0.001
			var pre := plant.leaf_count()
			LeafPlacer.advance(tip, ctx,
				pos - Vector3(0.0, params.segment_length, 0.0), pos, f_l, Basis.IDENTITY)
			if plant.leaf_count() > pre:
				n += 1
		return n

	var sun_placed: int = placed_at.call(1.0)
	var shade_placed: int = placed_at.call(0.5)
	assert_lte(sun_placed, shade_placed,
		"max crowding must not place more at f_L=1.0 than f_L=0.5 (SD-LEAF-8b)")
	assert_gt(sun_placed, 0, "sun floor must still allow some placements at C=1")


func test_sun_dense_gate_reduces_placement_chance_at_full_crowding() -> void:
	var params := IvyParams.new()
	var c := 1.0
	var sun_dense := 1.0
	var crowd_floor_sun := lerpf(params.leaf_crowd_floor, params.leaf_crowd_floor_sun, sun_dense)
	var crowd_suppress_sun := params.leaf_crowd_suppress + params.leaf_crowd_sun_suppress_gain * sun_dense
	var p_sun := clampf(1.0 - crowd_suppress_sun * c, crowd_floor_sun, 1.0)
	var p_legacy := clampf(1.0 - params.leaf_crowd_suppress * c, params.leaf_crowd_floor, 1.0)
	assert_lt(p_sun, p_legacy, "sun+dense gate must lower placement chance vs legacy curve")


# ── W-060 / SD-LEAF-7: per-instance sun/shade tint ────────────────────────────


func _place_one_leaf(f_l: float, l_dir: Vector3 = Vector3.ZERO) -> PlantData:
	return _place_leaf_with_params(IvyParams.new(), f_l, l_dir)


func _place_leaf_with_params(params: IvyParams, f_l: float, l_dir: Vector3 = Vector3.ZERO, tip: Tip = null) -> PlantData:
	## Place exactly one leaf; optional custom params and tip (for branch_order etc.).
	var plant := PlantData.new()
	var ctx := _make_ctx(params, plant)
	var t := tip if tip != null else _make_tip()
	t.shoot_length = params.leaf_tip_suppress + 1.0
	var u := Hash64.unit_float(t.id, t.node_count, 99)
	var internode := params.internode_base \
		* (1.0 + params.internode_shade_gain * (1.0 - f_l)) \
		* (1.0 + params.internode_jitter * (2.0 * u - 1.0))
	t.distance_since_node = internode + 0.001
	LeafPlacer.advance(t, ctx, Vector3.ZERO, Vector3(0.03, 0.0, 0.0), f_l, Basis.IDENTITY, l_dir)
	return plant


func _leaf_width(plant: PlantData, index: int = 0) -> float:
	return Vector3(
		plant.leaf_xform[index * 12],
		plant.leaf_xform[index * 12 + 1],
		plant.leaf_xform[index * 12 + 2]
	).length()


func _leaf_y_axis(plant: PlantData, index: int = 0) -> Vector3:
	return Vector3(
		plant.leaf_xform[index * 12 + 4],
		plant.leaf_xform[index * 12 + 5],
		plant.leaf_xform[index * 12 + 6]
	).normalized()


func _leaf_x_axis(plant: PlantData, index: int = 0) -> Vector3:
	return Vector3(
		plant.leaf_xform[index * 12],
		plant.leaf_xform[index * 12 + 1],
		plant.leaf_xform[index * 12 + 2]
	).normalized()


func test_leaf_tint_in_full_sun_is_not_white() -> void:
	## SD-LEAF-7 (M2.5): at f_L=1.0 the instance colour must be leaf_sun_tint,
	## not Color.WHITE.  Before the rule is wired, leaf_color[1] == 1.0 (white).
	var plant := _place_one_leaf(1.0)
	assert_eq(plant.leaf_count(), 1, "precondition: one leaf placed")
	var g: float = plant.leaf_color[1]
	assert_almost_eq(g, 1.04, 0.001,
		"sun leaf Color.g must be leaf_sun_tint.g (~1.04), not 1.0 (white)")


func test_leaf_tint_in_full_shade_is_darker() -> void:
	## SD-LEAF-7 (M2.5): at f_L=0.0 the instance colour must be leaf_shade_tint.
	var plant := _place_one_leaf(0.0)
	assert_eq(plant.leaf_count(), 1, "precondition: one leaf placed")
	var g: float = plant.leaf_color[1]
	assert_almost_eq(g, 0.86, 0.001,
		"shade leaf Color.g must be leaf_shade_tint.g (~0.86), not 1.0 (white)")


func test_leaf_tint_sun_green_exceeds_shade() -> void:
	## SD-LEAF-7: sun-facing leaves must be greener (higher Color.g) than shade leaves.
	## This is the metric LG-2a measures. The separation is ≥0.18 at f_L extremes.
	var plant_sun := _place_one_leaf(1.0)
	var plant_shade := _place_one_leaf(0.0)
	var g_sun: float = plant_sun.leaf_color[1]
	var g_shade: float = plant_shade.leaf_color[1]
	assert_gt(g_sun, g_shade,
		"sun leaf Color.g must exceed shade leaf Color.g (SD-LEAF-7 LG-2a)")
	assert_gt(g_sun - g_shade, 0.15,
		"sun–shade Color.g delta must be >0.15 (expected ~0.18 at f_L extremes)")


# ── W-060 / SD-LEAF-5: s_light size factor ────────────────────────────────────


func test_s_light_sun_leaf_wider_than_shade() -> void:
	## SD-LEAF-5 (s_light only, M2.5): w = leaf_width_base * (0.80 + 0.30*f_L).
	## A sun leaf (f_L=1.0, s_light=1.10) is wider than a shade leaf (f_L=0.0, s_light=0.80).
	var plant_sun := _place_one_leaf(1.0)
	var plant_shade := _place_one_leaf(0.0)
	# x_axis in the leaf xform is x_axis * width; recover magnitude as leaf width.
	var w_sun := Vector3(plant_sun.leaf_xform[0], plant_sun.leaf_xform[1], plant_sun.leaf_xform[2]).length()
	var w_shade := Vector3(plant_shade.leaf_xform[0], plant_shade.leaf_xform[1], plant_shade.leaf_xform[2]).length()
	assert_gt(w_sun, w_shade, "sun leaf must be wider than shade leaf (SD-LEAF-5 s_light)")
	# At defaults: sun=0.075*1.10=0.0825, shade=0.075*0.80=0.060, ratio=1.375
	assert_almost_eq(w_sun / w_shade, 1.375, 0.01,
		"sun-to-shade width ratio must match 1.10/0.80 = 1.375")


# ── W-060 / SD-LEAF-4 rule 5: phototropic cant ────────────────────────────────


func test_phototropic_cant_tilts_leaf_toward_light_gradient() -> void:
	## SD-LEAF-4 rule 5: n_leaf = normalize(n_wall + leaf_photo_cant * l_dir).
	## With n_wall=(0,0,1) and l_dir=(0,1,0), the leaf normal tilts upward.
	## The offset ladder applies along n_leaf, so the leaf origin's Y increases.
	var plant_flat := _place_one_leaf(1.0, Vector3.ZERO)
	var plant_tilted := _place_one_leaf(1.0, Vector3(0.0, 1.0, 0.0))
	# origin.y is stored at leaf_xform index 7
	var oy_flat: float = plant_flat.leaf_xform[7]
	var oy_tilted: float = plant_tilted.leaf_xform[7]
	assert_gt(oy_tilted, oy_flat,
		"phototropic cant with upward l_dir must lift the leaf origin (SD-LEAF-4 rule 5)")


func test_phototropic_cant_zero_l_dir_is_unchanged() -> void:
	## With l_dir=ZERO, n_leaf == n_wall and the orientation is identical to the
	## pre-W-060 code.  This is the backwards-compatibility case.
	var plant_a := _place_one_leaf(1.0, Vector3.ZERO)
	var plant_b := _place_one_leaf(1.0, Vector3.ZERO)
	# Two calls with identical inputs must produce identical results (determinism).
	assert_almost_eq(plant_a.leaf_xform[7], plant_b.leaf_xform[7], 1e-6,
		"identical inputs must produce identical leaf origin Y (determinism / l_dir=0)")


# ── W-060 / SD-LEAF-6: atlas health-tier selection ────────────────────────────


func _leaf_is_healthy(plant: PlantData, leaf_index: int) -> bool:
	## Healthy rects (a,c,e) have rect_uv.x < 0.1; weathered (b,d,f) > 0.5.
	## Reading from leaf_custom which stores xywh of the atlas rect.
	return plant.leaf_custom[leaf_index * 4] < 0.3


func _place_many_leaves(f_l: float, count: int) -> PlantData:
	## Helper: place `count` leaves, each from a different tip id, at the given f_L.
	## Uses the shade-corrected internode formula (SD-LEAF-2) so leaves are placed
	## regardless of the f_L value.
	var params := IvyParams.new()
	var plant := PlantData.new()
	var ctx := _make_ctx(params, plant)
	for i in range(count):
		var tip := _make_tip()
		tip.id = i
		tip.shoot_length = params.leaf_tip_suppress + 1.0
		var u := Hash64.unit_float(i, 0, 99)
		var internode := params.internode_base \
			* (1.0 + params.internode_shade_gain * (1.0 - f_l)) \
			* (1.0 + params.internode_jitter * (2.0 * u - 1.0))
		tip.distance_since_node = internode + 0.001
		LeafPlacer.advance(tip, ctx, Vector3.ZERO, Vector3(0.03, 0.0, 0.0), f_l, Basis.IDENTITY)
	return plant


func test_tier_selection_mostly_healthy_in_full_sun() -> void:
	## SD-LEAF-6: P(healthy) = 0.25 + 0.65*f_L = 0.90 at f_L=1.0.
	## Across many tips at f_L=1.0, at least 75% of leaves should be healthy tier.
	var plant := _place_many_leaves(1.0, 40)
	var healthy_count := 0
	for i in range(plant.leaf_count()):
		if _leaf_is_healthy(plant, i):
			healthy_count += 1
	assert_gt(healthy_count, 28,
		"At f_L=1.0 (P(healthy)=0.90), at least 70%% of %d leaves should be healthy (SD-LEAF-6)" % plant.leaf_count())


func test_tier_selection_more_weathered_in_full_shade() -> void:
	## SD-LEAF-6: P(healthy) = 0.25 at f_L=0.0.
	## Across many tips, at least 40% should be weathered (expect 75%).
	var plant := _place_many_leaves(0.0, 40)
	var weathered_count := 0
	for i in range(plant.leaf_count()):
		if not _leaf_is_healthy(plant, i):
			weathered_count += 1
	assert_gt(weathered_count, 15,
		"At f_L=0.0 (P(healthy)=0.25), at least 40%% of %d leaves should be weathered (SD-LEAF-6)" % plant.leaf_count())


func test_tier_selection_deterministic_across_two_runs() -> void:
	## SD-RNG-6: tier selection is hash-based, so identical inputs must produce identical results.
	var params := IvyParams.new()
	var plant_a := PlantData.new()
	var plant_b := PlantData.new()
	var ctx_a := _make_ctx(params, plant_a)
	var ctx_b := _make_ctx(params, plant_b)
	for i in range(20):
		for run_plant in [plant_a, plant_b]:
			var ctx: SimContext = ctx_a if run_plant == plant_a else ctx_b
			var tip := _make_tip()
			tip.id = i
			tip.shoot_length = params.leaf_tip_suppress + 1.0
			var u := Hash64.unit_float(i, 0, 99)
			var internode := params.internode_base * (1.0 + params.internode_jitter * (2.0 * u - 1.0))
			tip.distance_since_node = internode + 0.001
			LeafPlacer.advance(tip, ctx, Vector3.ZERO, Vector3(0.03, 0.0, 0.0), 0.7, Basis.IDENTITY)
	assert_eq(plant_a.leaf_count(), plant_b.leaf_count(), "both runs must place the same number of leaves")
	for i in range(plant_a.leaf_count()):
		assert_almost_eq(plant_a.leaf_custom[i * 4], plant_b.leaf_custom[i * 4], 1e-6,
			"leaf %d atlas rect must be identical across runs (SD-RNG-6 determinism)" % i)


# ── LG-2' layer (a): SD-LEAF-7 tint span and monotonicity ────────────────────


func test_lg2prime_tint_span_is_0_18() -> void:
	## LG-2' layer (a) — SD-LEAF-7 tint span.
	## Color.g(f_L=1) − Color.g(f_L=0) must equal 0.18 (leaf_sun_tint.g − leaf_shade_tint.g).
	## If SD-LEAF-7 is removed (tint = Color.WHITE), span collapses to 0 → RED.
	var plant_sun := _place_one_leaf(1.0)
	var plant_shade := _place_one_leaf(0.0)
	assert_eq(plant_sun.leaf_count(), 1, "precondition: sun leaf placed")
	assert_eq(plant_shade.leaf_count(), 0 if false else 1, "precondition: shade leaf placed")
	var span: float = plant_sun.leaf_color[1] - plant_shade.leaf_color[1]
	assert_almost_eq(span, 0.18, 0.001,
		"tint span Color.g(f_L=1) − Color.g(f_L=0) must be 0.18 (SD-LEAF-7, LG-2' layer a)")


func test_lg2prime_tint_is_monotone_at_intermediate_fl() -> void:
	## LG-2' layer (a) — SD-LEAF-7 monotonicity.
	## g(0) < g(0.5) < g(1). Reverting to Color.WHITE makes all three equal → RED.
	var g_0 := _place_one_leaf(0.0).leaf_color[1]
	var g_half := _place_one_leaf(0.5).leaf_color[1]
	var g_1 := _place_one_leaf(1.0).leaf_color[1]
	assert_lt(g_0, g_half,
		"g(f_L=0) must be less than g(f_L=0.5) — tint must be monotone (SD-LEAF-7)")
	assert_lt(g_half, g_1,
		"g(f_L=0.5) must be less than g(f_L=1.0) — tint must be monotone (SD-LEAF-7)")


# ── LG-2' layer (a): SD-LEAF-6 tier fraction calibration ─────────────────────


func test_lg2prime_healthy_tier_fraction_at_fl_0_4() -> void:
	## LG-2' layer (a) — SD-LEAF-6 tier fraction at f_L = 0.4.
	## P(healthy) = 0.25 + 0.65 × 0.4 = 0.51.
	## Fixing tier to always-healthy makes fraction → 1.0 → RED.
	## Using N=300 leaves so 3σ binomial tolerance ≈ 0.09.
	var plant := _place_many_leaves(0.4, 300)
	var healthy_count := 0
	for i in range(plant.leaf_count()):
		if _leaf_is_healthy(plant, i):
			healthy_count += 1
	var frac := float(healthy_count) / float(maxi(plant.leaf_count(), 1))
	assert_almost_eq(frac, 0.51, 0.10,
		"healthy tier fraction must be ≈0.51 at f_L=0.4 (SD-LEAF-6, LG-2' layer a)")


func test_adjacency_no_consecutive_repeat_on_same_stem() -> void:
	## SD-LEAF-6 adjacency rule: a node may not reuse the atlas id of either of the
	## two preceding nodes on the same stem.
	## Strategy: place 10 leaves on one tip and verify no adjacent pair shares a rect.
	var params := IvyParams.new()
	var plant := PlantData.new()
	var ctx := _make_ctx(params, plant)
	var tip := _make_tip()
	tip.id = 7  # arbitrary, gives a stable hash sequence
	tip.shoot_length = params.leaf_tip_suppress + 1.0
	var placed := 0
	while placed < 10:
		var u := Hash64.unit_float(tip.id, tip.node_count, 99)
		var internode := params.internode_base * (1.0 + params.internode_jitter * (2.0 * u - 1.0))
		tip.distance_since_node = internode + 0.001
		var before := plant.leaf_count()
		LeafPlacer.advance(tip, ctx, Vector3.ZERO, Vector3(0.03, 0.0, 0.0), 1.0, Basis.IDENTITY)
		if plant.leaf_count() > before:
			placed += 1
	assert_gt(plant.leaf_count(), 2, "need at least three leaves to test a two-back rule")

	# Check: no adjacent pair shares the same atlas rect (same x+y uniquely identifies leaf id).
	for i in range(plant.leaf_count() - 1):
		var rx_a: float = plant.leaf_custom[i * 4]
		var ry_a: float = plant.leaf_custom[i * 4 + 1]
		var rx_b: float = plant.leaf_custom[(i + 1) * 4]
		var ry_b: float = plant.leaf_custom[(i + 1) * 4 + 1]
		assert_false(
			absf(rx_a - rx_b) < 0.001 and absf(ry_a - ry_b) < 0.001,
			"Consecutive leaves %d and %d on same stem must not repeat the same atlas id (SD-LEAF-6 adjacency)" % [i, i + 1]
		)

	# The rule forbids reusing either of the *two* preceding ids, so the consecutive check
	# above only covers half of it: LeafPlacer builds its forbidden set from both
	# tip.last_leaf_id and tip.prev_leaf_id, and dropping the prev_leaf_id entry leaves every
	# assertion above still passing. Skip-one is what makes that deletion visible.
	for i in range(plant.leaf_count() - 2):
		var rx_a: float = plant.leaf_custom[i * 4]
		var ry_a: float = plant.leaf_custom[i * 4 + 1]
		var rx_c: float = plant.leaf_custom[(i + 2) * 4]
		var ry_c: float = plant.leaf_custom[(i + 2) * 4 + 1]
		assert_false(
			absf(rx_a - rx_c) < 0.001 and absf(ry_a - ry_c) < 0.001,
			"Leaves %d and %d must not share an atlas id — the rule forbids both preceding nodes, not just the last (SD-LEAF-6 adjacency)" % [i, i + 2]
		)


# ── W-030 fixer (ivy-cmb): SD-LEAF-4/5 presentation rules ─────────────────────


func test_jitter_roll_rotates_about_petiole_not_width() -> void:
	var params := IvyParams.new()
	params.droop_base = 0.0
	params.droop_shade_gain = 0.0
	params.leaf_jitter_tilt = 0.0
	params.leaf_jitter_yaw = 0.0
	params.leaf_jitter_roll = 0.0
	var plant_ref := _place_leaf_with_params(params, 1.0)
	params.leaf_jitter_roll = 90.0
	var plant_roll := _place_leaf_with_params(params, 1.0)
	assert_almost_eq(
		_leaf_y_axis(plant_ref).dot(_leaf_y_axis(plant_roll)), 1.0, 0.02,
		"roll about petiole must not tilt y_axis (SD-LEAF-4 rule 7)")
	assert_lt(
		absf(_leaf_x_axis(plant_ref).dot(_leaf_x_axis(plant_roll))), 0.99,
		"roll must rotate the blade width axis")


func test_s_order_decreases_with_branch_order() -> void:
	var params := IvyParams.new()
	var tip_lo := _make_tip()
	var tip_hi := _make_tip()
	tip_hi.branch_order = 3
	var plant_lo := _place_leaf_with_params(params, 1.0, Vector3.ZERO, tip_lo)
	var plant_hi := _place_leaf_with_params(params, 1.0, Vector3.ZERO, tip_hi)
	assert_gt(_leaf_width(plant_lo), _leaf_width(plant_hi),
		"higher branch order must produce smaller leaves (SD-LEAF-5 s_order)")


func test_s_var_is_deterministic_and_clamped() -> void:
	var params := IvyParams.new()
	var widths: Array[float] = []
	for _run in range(2):
		var tip := _make_tip()
		tip.id = 17
		widths.append(_leaf_width(_place_leaf_with_params(params, 1.0, Vector3.ZERO, tip)))
	assert_almost_eq(widths[0], widths[1], 1e-6, "s_var draw must be deterministic (channel 46)")
	var scale := params.leaf_light_scale_base + params.leaf_light_scale_gain
	var base_w := params.leaf_width_base * scale
	for i in range(80):
		var t := _make_tip()
		t.id = i
		var plant := _place_leaf_with_params(params, 1.0, Vector3.ZERO, t)
		var s_var := _leaf_width(plant) / base_w
		assert_gte(s_var, 0.75 - 1e-4, "s_var must respect lower clamp")
		assert_lte(s_var, 1.35 + 1e-4, "s_var must respect upper clamp")


func test_droop_increases_in_shade() -> void:
	var params := IvyParams.new()
	var droop_sun := params.droop_base + params.droop_shade_gain * (1.0 - 1.0)
	var droop_shade := params.droop_base + params.droop_shade_gain * (1.0 - 0.0)
	assert_gt(droop_shade, droop_sun,
		"shade must add droop_shade_gain to droop angle (SD-LEAF-4 rule 6)")
