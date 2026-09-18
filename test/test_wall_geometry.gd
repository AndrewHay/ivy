extends GutTest

const Wall = preload("res://src/world/wall.gd")
const WallSpec = preload("res://src/world/wall_spec.gd")
const WallBuilder = preload("res://src/world/wall_builder.gd")
const WallSdf = preload("res://src/world/wall_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const BuildingCatalog = preload("res://src/world/building_catalog.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const Conv = preload("res://src/core/conv.gd")
const MaterialRegistry = preload("res://src/world/material_registry.gd")
const MainScene = preload("res://src/main/main.tscn")


func _wall_surface(dev_build: bool = true) -> SurfaceQuery:
	var wall := Wall.new()
	add_child_autofree(wall)
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	wall.build_from_spec(spec, dev_build)
	await get_tree().physics_frame
	var sq := SurfaceQuery.new()
	sq.setup(
		wall.get_world_3d().direct_space_state,
		wall,
		WallSdf.new(spec),
		wall.face_material,
		IvyParams.new()
	)
	return sq


func test_wall_builder_aabb_triangle_count_and_material() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var built := WallBuilder.build(spec, false)
	var aabb := built.mesh.get_aabb()
	assert_almost_eq(aabb.position.x, -50.0, 0.01)
	assert_almost_eq(aabb.position.y, 0.0, 0.01)
	assert_almost_eq(aabb.position.z, -0.35, 0.01)
	assert_almost_eq(aabb.size.x, 100.0, 0.01)
	assert_almost_eq(aabb.size.y, 20.0, 0.01)
	assert_almost_eq(aabb.size.z, 0.35, 0.01)
	assert_eq(built.triangle_count, 10)
	for mat_id in built.face_material:
		assert_eq(mat_id, MaterialRegistry.BRICK_WALL)


func test_wall_sdf_sign_and_outward_normals() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var sdf := WallSdf.new(spec)
	assert_lt(sdf.signed_distance(Vector3(0.0, 10.0, -0.1)), 0.0)
	assert_gt(sdf.signed_distance(Vector3(0.0, 10.0, 1.0)), 0.0)
	var built := WallBuilder.build(spec, false)
	var arrays := built.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tris := PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.size() > 0:
		for i in range(0, indices.size(), 3):
			tris.append(verts[indices[i]])
			tris.append(verts[indices[i + 1]])
			tris.append(verts[indices[i + 2]])
	else:
		for i in range(0, verts.size(), 3):
			tris.append(verts[i])
			tris.append(verts[i + 1])
			tris.append(verts[i + 2])
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n_geo := -(b - a).cross(c - a).normalized()
		var centroid := (a + b + c) / 3.0
		assert_gt(sdf.signed_distance(centroid + n_geo * 0.01), 0.0)
		assert_lt(sdf.signed_distance(centroid - n_geo * 0.01), 0.0)


func test_wall_sdf_gradient_faces_south_on_sun_face() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var sdf := WallSdf.new(spec)
	var g := sdf.gradient_normalized(Vector3(0.0, 10.0, 0.5))
	assert_gt(g.dot(Conv.SOUTH), 0.9)


func test_wall_seed_nearest_midpoint_base() -> void:
	var sq := await _wall_surface()
	var params := IvyParams.new()
	var probe := Vector3(0.0, params.ground_y_min, 0.0) + Conv.SOUTH * 8.0
	var hit := sq.nearest(probe)
	assert_almost_eq(hit.position.x, 0.0, 0.1)
	assert_almost_eq(hit.position.z, 0.0, 0.1)
	assert_true(absf(hit.position.y) <= 0.05 or absf(hit.position.y - params.ground_y_min) <= 0.05)
	assert_gt(hit.normal.dot(Conv.SOUTH), 0.9)


func test_building_catalog_wall_is_procedural() -> void:
	assert_true(BuildingCatalog.is_procedural("wall"))


func test_world_wall_wiring_null_anchors_cylinder_regression() -> void:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	var world: Node = main.get_node("World")
	world.call("load_building", "wall")
	await get_tree().physics_frame
	await get_tree().process_frame
	var params: IvyParams = main.get("params")
	var surface: SurfaceQuery = world.call("get_surface_query", params)
	assert_not_null(surface)
	assert_null(world.call("get_seed_anchors"))
	world.call("load_building", "cylinder")
	await get_tree().physics_frame
	await get_tree().process_frame
	world.set("surface", null)
	var surface2: SurfaceQuery = world.call("get_surface_query", params)
	assert_not_null(surface2)
	assert_not_null(world.call("get_seed_anchors"))
