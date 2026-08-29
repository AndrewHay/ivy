extends GutTest

## W-012 / SD-AGENCY-2 — derived compass anchors and doorway avoidance.

const Tower = preload("res://src/world/tower.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const SeedAnchors = preload("res://src/world/seed_anchors.gd")
const MaterialRegistry = preload("res://src/world/material_registry.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


func _tower_surface() -> SurfaceQuery:
	var tower := Tower.new()
	add_child_autofree(tower)
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	tower.build_from_spec(spec, true)
	await get_tree().physics_frame
	var sq := SurfaceQuery.new()
	sq.setup(
		tower.get_world_3d().direct_space_state,
		tower,
		TowerSdf.new(spec),
		tower.face_material,
		IvyParams.new()
	)
	return sq


func test_seed_anchors_yield_four_compass_points() -> void:
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var sq := await _tower_surface()
	var anchors_obj := SeedAnchors.new()
	anchors_obj.build(sq, spec)
	var anchors: Array = anchors_obj.get_anchors()
	assert_eq(anchors.size(), 4)
	for a in anchors:
		assert_true(a.available, "compass %s should be available" % SeedAnchors.compass_label(a.compass))
		assert_gt(a.normal.length_squared(), 0.9)
		assert_gt(a.position.length(), spec.radius_inner() * 0.5)


func test_north_anchor_avoids_door_opening() -> void:
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var sq := await _tower_surface()
	var anchors_obj := SeedAnchors.new()
	anchors_obj.build(sq, spec)
	var north = anchors_obj.get_anchors()[0]
	assert_true(north.available)
	var door_probe := Vector3(0.0, 1.0, -(spec.radius_outer + 0.1))
	var door_hit := sq.raycast(door_probe, Vector3.ZERO)
	if door_hit.hit and door_hit.material_id == MaterialRegistry.OPENING_REVEAL:
		assert_gt(north.position.distance_to(door_hit.position), 0.2,
			"north anchor must be offset off the doorway (SD-AGENCY-2)")
	var verify := sq.raycast(north.position + north.normal * 0.05, north.position - north.normal * 0.2)
	assert_true(verify.hit)
	assert_ne(verify.material_id, MaterialRegistry.OPENING_REVEAL,
		"north anchor must sit on wall brick, not opening reveal")
