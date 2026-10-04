extends GutTest

## ivy-fs0 — StructureBody.bounds_aabb() over trimesh collision pieces.

const StructureBody = preload("res://src/world/structure_body.gd")
const MeshSdf = preload("res://src/world/mesh_sdf.gd")

const SIM_GLB := "res://assets/structures/surface_wall_sim.glb"
const SIM_SDF := "res://assets/structures/surface_wall_sim.sdf"


func _trimesh_col(name: String, size: Vector3, origin: Vector3) -> CollisionShape3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var col := CollisionShape3D.new()
	col.name = name
	col.shape = mesh.create_trimesh_shape()
	col.transform = Transform3D(Basis.IDENTITY, origin)
	return col


func test_bounds_aabb_merges_trimesh_pieces() -> void:
	var body := StructureBody.new()
	add_child_autofree(body)
	body.add_child(_trimesh_col("A", Vector3(2.0, 2.0, 2.0), Vector3.ZERO))
	body.add_child(_trimesh_col("B", Vector3(2.0, 2.0, 2.0), Vector3(4.0, 0.0, 0.0)))
	var bounds := body.bounds_aabb()
	assert_almost_eq(bounds.position, Vector3(-1.0, -1.0, -1.0), Vector3.ONE * 1e-4,
		"merged bounds should start at the -X box's min corner")
	assert_almost_eq(bounds.size, Vector3(6.0, 2.0, 2.0), Vector3.ONE * 1e-4,
		"merged bounds should span both boxes on X and neither beyond on Y/Z")


func test_bounds_aabb_ignores_shapeless_collision_shape() -> void:
	var body := StructureBody.new()
	add_child_autofree(body)
	var empty := CollisionShape3D.new()
	empty.name = "NoShape"
	body.add_child(empty)
	body.add_child(_trimesh_col("A", Vector3(2.0, 2.0, 2.0), Vector3(1.0, 0.0, 0.0)))
	var bounds := body.bounds_aabb()
	assert_almost_eq(bounds.position, Vector3(0.0, -1.0, -1.0), Vector3.ONE * 1e-4,
		"a null-shape child must not drag the merged bounds toward the origin")
	assert_almost_eq(bounds.size, Vector3(2.0, 2.0, 2.0), Vector3.ONE * 1e-4,
		"a null-shape child must not inflate the merged bounds")


func test_bounds_aabb_on_built_surface_wall() -> void:
	if not FileAccess.file_exists(SIM_GLB) or not FileAccess.file_exists(SIM_SDF):
		pending("surface_wall_sim.glb/.sdf not built yet")
		return
	var body := StructureBody.new()
	add_child_autofree(body)
	body.build(SIM_GLB)
	var pieces := 0
	for child in body.get_children():
		if child is CollisionShape3D:
			pieces += 1
	assert_gt(pieces, 0, "expected trimesh collision pieces")

	var bounds := body.bounds_aabb()
	assert_gt(bounds.get_volume(), 0.0, "built structure should have a non-empty AABB")
	for axis in 3:
		assert_true(is_finite(bounds.position[axis]) and is_finite(bounds.size[axis]),
			"bounds must be finite on axis %d" % axis)

	# The SDF bakes its mesh_aabb from the same sim GLB, so it is an independent check that
	# the merged shape bounds describe the real structure and not some degenerate box.
	var sdf := MeshSdf.new()
	sdf.load_from_file(SIM_SDF)
	var baked := sdf.bounds()
	assert_almost_eq(bounds.position, baked.position, Vector3.ONE * 1e-3,
		"bounds origin should match the baked SDF mesh_aabb")
	assert_almost_eq(bounds.size, baked.size, Vector3.ONE * 1e-3,
		"bounds extent should match the baked SDF mesh_aabb")
