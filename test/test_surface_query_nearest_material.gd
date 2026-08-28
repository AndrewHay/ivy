extends GutTest

## W-044 — analytic nearest() must resolve material_id from physics when available.

const Tower = preload("res://src/world/tower.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const MaterialRegistry = preload("res://src/world/material_registry.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


func test_nearest_material_matches_raycast_on_procedural_tower() -> void:
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
	var probe := Vector3(0.0, 2.0, 8.0)
	var near := sq.nearest(probe)
	assert_true(near.hit)
	var toward := (near.position - probe).normalized()
	var ray := sq.raycast(probe, near.position + toward * 0.05)
	assert_true(ray.hit, "exterior raycast should hit tower collision")
	assert_eq(
		near.material_id,
		ray.material_id,
		"W-044: nearest() material_id must match raycast face_index mapping"
	)


func test_nearest_null_physics_falls_back_to_brick_wall() -> void:
	var sq := SurfaceQuery.new()
	sq.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), IvyParams.new())
	var near := sq.nearest(Vector3(0.0, 2.0, 8.0))
	assert_true(near.hit)
	assert_eq(near.material_id, MaterialRegistry.BRICK_WALL)
