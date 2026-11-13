extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsForestPlacement = preload("res://src/playground/hills_forest_placement.gd")
const ForestParams = preload("res://src/playground/forest_params.gd")
const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")


func test_v3_layout_generation_seed_drives_terrain() -> void:
	var layout1 := VillageLayout.generate(1)
	var layout12 := VillageLayout.generate(12)
	if layout1.fallback or layout12.fallback:
		pass_test("fallback skip")
		return
	assert_gt(layout1.generation_seed, 0, "seed 1 layout must store generation_seed")
	assert_gt(layout12.generation_seed, 0, "seed 12 layout must store generation_seed")
	assert_ne(layout1.generation_seed, layout12.generation_seed)
	var params := HillsParams.production()
	var t1 := HillsHeightfield.terrain_seed(layout1, params)
	var t12 := HillsHeightfield.terrain_seed(layout12, params)
	assert_ne(t1, t12, "terrain_seed must differ across village seeds")
	var probe := Vector2(5.0, -175.0)  # rework5: probe northward to ridge zone (155-190m)
	var p1 := layout1.hamlet_centre_xz + probe
	var p12 := layout12.hamlet_centre_xz + probe
	var y1 := HillsHeightfield.sample_y(p1, layout1, params, t1)
	var y12 := HillsHeightfield.sample_y(p12, layout12, params, t12)
	assert_ne(y1, y12, "hill height probes must differ for seeds 1 vs 12")


func test_backdrop_hills_match_builder_for_seed7() -> void:
	const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var backdrop := VillageScatterPositions.forest_tree_xz(layout)
	var built := HillsForestPlacement.hill_forest_transforms(layout, params, t_seed, backdrop)
	var bd := GeneratedBackdropScene.instantiate()
	bd.set_village_seed(7)
	add_child_autofree(bd)
	await get_tree().process_frame
	await get_tree().process_frame
	var hf := bd.get_node_or_null("HillForest") as MultiMeshInstance3D
	assert_not_null(hf)
	assert_eq(hf.multimesh.instance_count, built.size())
	var buf := hf.multimesh.buffer
	# Buffer stride is 12 floats (transform) + 4 when per-instance colors are enabled.
	var stride: int = buf.size() / maxi(built.size(), 1)
	assert_true(stride == 12 or stride == 16, "unexpected multimesh buffer stride %d" % stride)
	for i in range(built.size()):
		var a := built[i].origin
		var base := i * stride
		var bx: float = buf[base + 3]
		var bz: float = buf[base + 11]
		assert_almost_eq(a.x, bx, 1e-4, "forest x %d" % i)
		assert_almost_eq(a.z, bz, 1e-4, "forest z %d" % i)
