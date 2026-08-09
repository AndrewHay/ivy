## Regression tests for SD-LEAF-2 (shade etiolation), SD-LEAF-3 (phyllotaxy),
## and SD-LEAF-8 (leaf crowding deposit and placement suppression).
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
