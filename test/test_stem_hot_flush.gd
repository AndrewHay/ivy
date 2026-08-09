## Regression test for W-029: the last 0–127 segments (the actively growing tips) are
## invisible because the hot SurfaceTool is only committed when a full 128-segment chunk
## fills.  After the fix, sync_from flushes the partial chunk every call.
extends GutTest

const StemMeshBuilder = preload("res://src/render/stem_mesh.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const PlantData = preload("res://src/sim/plant_data.gd")


func _make_plant_with_segments(n: int) -> PlantData:
	var plant := PlantData.new()
	for i in range(n):
		var a := Vector3(float(i) * 0.03, 0.0, 0.0)
		var b := Vector3(float(i + 1) * 0.03, 0.0, 0.0)
		plant.append_segment(a, b, Vector3.UP, 0, 0, float(i) * 0.03)
	return plant


func test_partial_chunk_is_visible_after_sync() -> void:
	var builder := StemMeshBuilder.new()
	add_child(builder)
	builder.setup(IvyParams.new())

	var plant := _make_plant_with_segments(5)
	builder.sync_from(plant, 0)

	assert_not_null(builder._hot_instance.mesh, "hot instance mesh must not be null after partial sync")
	assert_gt(builder._hot_count, 0, "hot chunk should have segments")


func test_full_chunk_seals_and_new_hot_starts() -> void:
	var builder := StemMeshBuilder.new()
	add_child(builder)
	builder.setup(IvyParams.new())

	# Fill exactly one full chunk
	var plant := _make_plant_with_segments(StemMeshBuilder.CHUNK_SEGMENTS)
	builder.sync_from(plant, 0)

	# After sealing, _hot_count resets
	assert_eq(builder._hot_count, 0, "hot count resets after a full chunk is sealed")


func test_tip_segments_beyond_chunk_boundary_are_rendered() -> void:
	# Segments 128-132 should appear in the new hot chunk mesh
	var builder := StemMeshBuilder.new()
	add_child(builder)
	builder.setup(IvyParams.new())

	var plant := _make_plant_with_segments(StemMeshBuilder.CHUNK_SEGMENTS + 5)
	builder.sync_from(plant, 0)

	assert_not_null(builder._hot_instance.mesh, "new hot chunk is visible after crossing chunk boundary")
	assert_eq(builder._hot_count, 5)
