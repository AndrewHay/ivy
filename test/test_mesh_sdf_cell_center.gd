## SG-9(c) / ivy-b1e.3 — trilinear read must treat baked samples as cell-centre values.
extends GutTest

const MeshSdf = preload("res://src/world/mesh_sdf.gd")


func test_trilinear_zero_crossing_aligns_with_cell_centre_samples() -> void:
	# Plane x=1 with h=1: cell i stores Φ at centre (i+0.5) equal to (i+0.5) - 1.
	var sdf := MeshSdf.new()
	sdf.h = 1.0
	sdf.band = 4.0
	sdf.origin = Vector3.ZERO
	sdf.dims = Vector3i(4, 1, 1)
	sdf.mesh_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(6.0, 2.0, 2.0))
	sdf._data = PackedFloat32Array([-0.5, 0.5, 1.5, 2.5])
	# Interior zero crossing — old corner-based read returned +0.5 here (half-voxel bias).
	assert_almost_eq(sdf.signed_distance(Vector3(1.0, 0.0, 0.0)), 0.0, 0.001)
	assert_almost_eq(sdf.signed_distance(Vector3(1.0, 0.2, -0.3)), 0.0, 0.001)
