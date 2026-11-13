extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsForestPlacement = preload("res://src/playground/hills_forest_placement.gd")
const ForestParams = preload("res://src/playground/forest_params.gd")
const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")
const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")

const _PARITY_SEEDS: Array[int] = [1, 7, 12, 240424020]

## rework5: offsets are north (−Z) biased to sample the new hill zone (155-260m).
const _PROBE_OFFSETS: Array[Vector2] = [
	Vector2(0.0, -155.0), Vector2(8.0, -172.0), Vector2(-6.0, -190.0),
	Vector2(12.0, -215.0), Vector2(-9.0, -245.0),
]


static func _hash_height_probes(
		layout: VillageLayout, params: HillsParams, t_seed: int) -> String:
	var g := layout.hamlet_centre_xz
	var parts: PackedStringArray = []
	for off in _PROBE_OFFSETS:
		var y := HillsHeightfield.sample_y(g + off, layout, params, t_seed)
		parts.append("%.6f" % y)
	return ",".join(parts).sha256_text()


static func _origin_from_multimesh_buffer(mm: MultiMesh, i: int) -> Vector3:
	var buf := mm.buffer
	# Derive stride from buffer size so this is correct regardless of whether
	# per-instance colour or custom data is enabled (TRANSFORM_3D = 12 floats;
	# with colours = 16; etc.).
	var stride := buf.size() / maxi(mm.instance_count, 1)
	var base := i * stride
	return Vector3(buf[base + 3], buf[base + 7], buf[base + 11])


static func _hash_forest_xz(xforms: Array) -> String:
	var parts: PackedStringArray = []
	for t in xforms:
		var tr := t as Transform3D
		parts.append("%.6f,%.6f" % [tr.origin.x, tr.origin.z])
	parts.sort()
	return "%d|%s" % [xforms.size(), "|".join(parts).sha256_text()]


static func _builder_bundle(seed: int) -> Dictionary:
	var layout := VillageLayout.generate(seed)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var backdrop := VillageScatterPositions.forest_tree_xz(layout)
	var xforms := HillsForestPlacement.hill_forest_transforms(layout, params, t_seed, backdrop)
	return {
		"layout": layout,
		"height_hash": _hash_height_probes(layout, params, t_seed),
		"forest_hash": _hash_forest_xz(xforms),
		"xforms": xforms,
	}


func test_shared_builders_deterministic_hash() -> void:
	for seed in _PARITY_SEEDS:
		var a := _builder_bundle(seed)
		if a["layout"].fallback:
			continue
		var b := _builder_bundle(seed)
		assert_eq(a["height_hash"], b["height_hash"], "seed %d height hash" % seed)
		assert_eq(a["forest_hash"], b["forest_hash"], "seed %d forest hash" % seed)


func test_per_seed_height_and_forest_hashes_differ() -> void:
	var hashes: Dictionary = {}
	for seed in [1, 12]:
		var bundle := _builder_bundle(seed)
		if bundle["layout"].fallback:
			continue
		hashes[seed] = bundle["height_hash"]
	assert_ne(hashes[1], hashes[12], "seeds 1 and 12 must differ in height probes")


static func _pack_transform_buffer(xforms: Array) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(xforms.size() * 12)
	for i in range(xforms.size()):
		var t: Transform3D = xforms[i]
		var b := i * 12
		buf[b + 0] = t.basis.x.x; buf[b + 1] = t.basis.y.x; buf[b + 2] = t.basis.z.x
		buf[b + 3] = t.origin.x
		buf[b + 4] = t.basis.x.y; buf[b + 5] = t.basis.y.y; buf[b + 6] = t.basis.z.y
		buf[b + 7] = t.origin.y
		buf[b + 8] = t.basis.x.z; buf[b + 9] = t.basis.y.z; buf[b + 10] = t.basis.z.z
		buf[b + 11] = t.origin.z
	return buf


func test_playground_builders_match_backdrop_hill_forest() -> void:
	for seed in _PARITY_SEEDS:
		var bundle := _builder_bundle(seed)
		if bundle["layout"].fallback:
			continue
		var bd := GeneratedBackdropScene.instantiate()
		bd.set_village_seed(seed)
		add_child_autofree(bd)
		await get_tree().process_frame
		await get_tree().process_frame
		var layout: VillageLayout = bd.get_layout()
		assert_eq(layout.generation_seed, seed & 0x7FFFFFFF, "seed %d generation_seed on backdrop" % seed)
		var hf := bd.get_node_or_null("HillForest") as MultiMeshInstance3D
		assert_not_null(hf, "seed %d HillForest" % seed)
		assert_eq(hf.multimesh.instance_count, bundle["xforms"].size())
		var params := HillsParams.production()
		var t_seed := HillsHeightfield.terrain_seed(layout, params)
		var backdrop := VillageScatterPositions.forest_tree_xz(layout)
		var via_layout := HillsForestPlacement.hill_forest_transforms(
			layout, params, t_seed, backdrop)
		assert_eq(
			_pack_transform_buffer(via_layout),
			_pack_transform_buffer(bundle["xforms"]),
			"seed %d builder parity" % seed)
		assert_eq(
			_hash_height_probes(layout, params, t_seed),
			bundle["height_hash"],
			"seed %d height probes match bundle" % seed)


func test_backdrop_has_hill_nodes_seed7() -> void:
	var bd := GeneratedBackdropScene.instantiate()
	bd.set_village_seed(7)
	add_child_autofree(bd)
	assert_not_null(bd.get_node_or_null("HillTerrain"))
	var hf := bd.get_node_or_null("HillForest") as MultiMeshInstance3D
	assert_not_null(hf)
	if hf != null and hf.multimesh != null:
		assert_gt(hf.multimesh.instance_count, 0)
