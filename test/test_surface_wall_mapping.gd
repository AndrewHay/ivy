extends GutTest

## W-092 — surface_wall collision pieces resolve to expected MaterialRegistry ids.

const StructureBody = preload("res://src/world/structure_body.gd")
const StructureScenario = preload("res://src/world/structure_scenario.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const MaterialRegistry = preload("res://src/world/material_registry.gd")

const SIM_GLB := "res://assets/structures/surface_wall_sim.glb"
const SIM_SDF := "res://assets/structures/surface_wall_sim.sdf"


func test_surface_wall_scenario_validates() -> void:
	var scenario: StructureScenario = load(
		"res://assets/structures/scenarios/surface_wall.tres"
	) as StructureScenario
	assert_not_null(scenario, "surface_wall.tres should load")
	assert_eq(scenario.validate().size(), 0, scenario.validate())


func test_surface_wall_material_mapping() -> void:
	if not FileAccess.file_exists(SIM_GLB):
		pending("surface_wall_sim.glb not built yet")
		return
	var body := StructureBody.new()
	add_child_autofree(body)
	body.build(SIM_GLB)
	assert_gt(body.face_material.size(), 0, "expected collision pieces")
	var counts := {
		MaterialRegistry.BRICK_WALL: 0,
		MaterialRegistry.GLASS: 0,
		MaterialRegistry.WOOD: 0,
		MaterialRegistry.OPENING_REVEAL: 0,
		MaterialRegistry.INTERIOR: 0,
	}
	var mat_idx := 0
	for col in body.get_children():
		if col is CollisionShape3D:
			assert_lt(mat_idx, body.face_material.size())
			var mid: int = body.face_material[mat_idx]
			if counts.has(mid):
				counts[mid] += 1
			mat_idx += 1
	assert_gt(counts[MaterialRegistry.BRICK_WALL], 0, "brick walls present")
	assert_gt(counts[MaterialRegistry.GLASS], 0, "window panel mapped to GLASS")
	assert_gt(counts[MaterialRegistry.WOOD], 0, "closed door panel mapped to WOOD")


func test_surface_wall_raycast_shape_material_rg2() -> void:
	if not FileAccess.file_exists(SIM_GLB):
		pending("surface_wall_sim.glb not built yet")
		return
	var body := StructureBody.new()
	add_child_autofree(body)
	body.build(SIM_GLB)
	await get_tree().physics_frame
	var sdf := MeshSdf.new()
	sdf.load_from_file(SIM_SDF)
	var sq := SurfaceQuery.new()
	sq.setup(
		body.get_world_3d().direct_space_state,
		body,
		sdf,
		body.face_material,
		IvyParams.new()
	)
	var col_idx := 0
	var glass_hit := false
	var wood_hit := false
	for col in body.get_children():
		if col is CollisionShape3D:
			var mid: int = body.face_material[col_idx]
			if mid == MaterialRegistry.GLASS or mid == MaterialRegistry.WOOD:
				var shape_col := col as CollisionShape3D
				var aabb: AABB = shape_col.global_transform * shape_col.shape.get_aabb()
				var center := aabb.get_center()
				var outward := Vector3(0.0, 0.0, 1.0)
				var hit := sq.raycast(center + outward * 0.5, center - outward * 0.5)
				assert_true(hit.hit, "raycast should hit shape %d" % col_idx)
				assert_eq(hit.material_id, mid,
					"RG-2: raycast material_id must match shape index %d" % col_idx)
				if mid == MaterialRegistry.GLASS:
					glass_hit = true
				if mid == MaterialRegistry.WOOD:
					wood_hit = true
			col_idx += 1
	assert_true(glass_hit, "expected at least one GLASS raycast sample")
	assert_true(wood_hit, "expected at least one WOOD raycast sample")
