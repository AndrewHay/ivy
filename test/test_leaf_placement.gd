## Regression tests for SD-LEAF-2 (shade etiolation) and SD-LEAF-3 (phyllotaxy).
extends GutTest

const LeafPlacer = preload("res://src/sim/leaf_placer.gd")
const SimContext = preload("res://src/sim/sim_context.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const Tip = preload("res://src/sim/tip.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


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
