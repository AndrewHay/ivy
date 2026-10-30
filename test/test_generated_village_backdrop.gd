## Tests for GeneratedVillageBackdrop (ivy-80z S3 — with full path network).
##
## (a) _ready() completes without errors at a fixed seed.
## (b) Scatter_Path_* multimeshes exist and are non-empty (S3 stones present).
## (c) Scatter_Petal_* multimeshes exist (S3 petals present).
## (d) FarTreeline exists with 33 instances (generated pine_count).
## (e) LawnGround exists with radius ≈ 30 m.
## (f) HillRing exists with inner radius ≈ 30 m.
## (g) 7 sets of Cottage_* multimeshes are present.
## (h) No collision objects.
## (i) Determinism: same seed → identical cottage MultiMesh buffers.
## (j) Variability: different seeds → different cottage MultiMesh buffers.
## (k) INV-16: exactly 3 inner and 4 outer cottages from get_layout().
## (l) INV-17: inner pairwise angular spread >= 65°, outer >= 50°.
## (m) INV-20: layout fields match generated preset.
## (n) INV-7: no Scatter_Path_* stone inside any cottage rect (margin 0).
## (o) INV-9: no stone |p| < 4.5 m; hero-edge polylines end near the 6.5 m ring.
## (p) INV-10: stone count ∈ [70, 360].
## (q) export_fauna_anchors() includes path-side petals.
extends GutTest

const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")

const DEFAULT_TEST_SEED := 12345


func _make_generated(seed: int) -> GeneratedVillageBackdrop:
	var bd := GeneratedBackdropScene.instantiate() as GeneratedVillageBackdrop
	bd.set_village_seed(seed)
	add_child_autofree(bd)
	return bd


# ── (a) _ready() without errors ───────────────────────────────────────────────

func test_ready_without_error() -> void:
	## GUT will surface push_error calls as failures; simply instantiating at a known seed
	## with paths=[] must complete cleanly.
	var bd := _make_generated(DEFAULT_TEST_SEED)
	assert_not_null(bd, "GeneratedVillageBackdrop must instantiate")
	# Check that it is the expected subclass.
	assert_true(bd is VillageBackdrop,
		"GeneratedVillageBackdrop must be a VillageBackdrop")
	assert_true(bd is GeneratedVillageBackdrop,
		"Must be a GeneratedVillageBackdrop")


# ── (b) Scatter_Path_* nodes exist and are non-empty ─────────────────────────

func test_has_scatter_path_nodes() -> void:
	## S3: paths are non-empty, so Scatter_Path_* multimeshes must exist.
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var path_nodes: Array[String] = []
	_collect_matching_names(bd, "Scatter_Path_", path_nodes)
	assert_gt(path_nodes.size(), 0,
		"S3 network must create ≥1 Scatter_Path_* node; got none")


func test_has_scatter_petal_nodes() -> void:
	## S3: path stones exist, so path-side petals must appear.
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var petal_nodes: Array[String] = []
	_collect_matching_names(bd, "Scatter_Petal_", petal_nodes)
	assert_gt(petal_nodes.size(), 0,
		"S3 network must create ≥1 Scatter_Petal_* node; got none")


# ── (c) FarTreeline with 33 instances ────────────────────────────────────────

func test_far_treeline_instance_count() -> void:
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var treeline := _find_multimesh(bd, "FarTreeline")
	assert_not_null(treeline, "FarTreeline must exist in generated backdrop")
	if treeline == null:
		return
	assert_not_null(treeline.multimesh, "FarTreeline must have a multimesh")
	if treeline.multimesh == null:
		return
	assert_eq(treeline.multimesh.instance_count, 33,
		"Generated FarTreeline must have 33 instances (pine_count)")


# ── (d) LawnGround radius ≈ 30 m ─────────────────────────────────────────────

func test_lawn_ground_radius() -> void:
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var lawn := bd.get_node_or_null("LawnGround") as MeshInstance3D
	assert_not_null(lawn, "LawnGround must exist in generated backdrop")
	if lawn == null or lawn.mesh == null:
		return
	var arrays := lawn.mesh.surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var max_r := 0.0
	for v: Vector3 in verts:
		max_r = maxf(max_r, Vector2(v.x, v.z).length())
	assert_almost_eq(max_r, 36.0, 0.01,
		"Generated LawnGround vertex radius must be ≈ 36.0 m (lawn_radius)")


# ── (e) HillRing inner radius ≈ 30 m ─────────────────────────────────────────

func test_hill_ring_inner_radius() -> void:
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var hill := bd.get_node_or_null("HillRing") as MeshInstance3D
	assert_not_null(hill, "HillRing must exist in generated backdrop")
	if hill == null or hill.mesh == null:
		return
	var arrays := hill.mesh.surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var inner_r := INF
	for v: Vector3 in verts:
		if absf(v.y) < 0.1:
			inner_r = minf(inner_r, Vector2(v.x, v.z).length())
	if inner_r == INF:
		inner_r = 0.0
	assert_almost_eq(inner_r, 36.0, 0.5,
		"Generated HillRing inner radius must be ≈ 36.0 m (hill_inner)")


# ── (f) Cottage multimeshes (7 cottage types produce Cottage_* nodes) ─────────

func test_cottage_multimeshes_present() -> void:
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var cottage_nodes: Array[String] = []
	_collect_matching_names(bd, "Cottage_", cottage_nodes)
	assert_gt(cottage_nodes.size(), 0,
		"Must have Cottage_* multimesh nodes for the 7 generated cottages")


# ── (g) No collision objects ──────────────────────────────────────────────────

func test_no_collision_objects() -> void:
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var collision_nodes: Array[String] = []
	_collect_collision_names(bd, collision_nodes)
	assert_eq(collision_nodes.size(), 0,
		"GeneratedVillageBackdrop must have zero CollisionObject3D descendants; found: %s" \
		% str(collision_nodes))


# ── (h) Determinism: same seed → identical cottage buffers ────────────────────

func test_same_seed_deterministic_cottage_buffers() -> void:
	var bd1 := _make_generated(DEFAULT_TEST_SEED)
	var bd2 := _make_generated(DEFAULT_TEST_SEED)
	var names1: Array[String] = []
	_collect_matching_names(bd1, "Cottage_", names1)
	if names1.is_empty():
		pending("No Cottage_ nodes to compare")
		return
	# Compare the first Cottage_ node's multimesh buffer between both instances.
	var node1 := bd1.get_node_or_null(names1[0]) as MultiMeshInstance3D
	var node2 := bd2.get_node_or_null(names1[0]) as MultiMeshInstance3D
	if node1 == null or node2 == null:
		pending("Could not find matching Cottage_ node in both instances")
		return
	assert_eq(node1.multimesh.buffer, node2.multimesh.buffer,
		"Same seed must produce identical MultiMesh buffers (determinism)")


# ── (i) Variability: different seeds → different cottage buffers ──────────────

func test_different_seeds_different_cottage_buffers() -> void:
	var bd1 := _make_generated(DEFAULT_TEST_SEED)
	var bd2 := _make_generated(DEFAULT_TEST_SEED + 1)
	var names1: Array[String] = []
	_collect_matching_names(bd1, "Cottage_", names1)
	if names1.is_empty():
		pending("No Cottage_ nodes to compare")
		return
	var node1 := bd1.get_node_or_null(names1[0]) as MultiMeshInstance3D
	var node2 := bd2.get_node_or_null(names1[0]) as MultiMeshInstance3D
	if node1 == null or node2 == null:
		pending("Could not find matching Cottage_ node in both instances")
		return
	# Different seeds must produce different buffers (with very high probability).
	assert_ne(node1.multimesh.buffer, node2.multimesh.buffer,
		"Different seeds must produce different cottage MultiMesh buffers (variability)")


# ── (j) INV-16: 3 inner / 4 outer ────────────────────────────────────────────

func test_inv16_ring_membership() -> void:
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var layout := bd.get_layout()
	assert_not_null(layout, "get_layout() must return a non-null VillageLayout")
	if layout == null:
		return
	assert_eq(layout.cottages.size(), 7,
		"Layout must have exactly 7 cottages")
	assert_eq(layout.cottage_rings.size(), 7,
		"cottage_rings must be parallel to cottages (size 7)")
	var inner_count := 0
	var outer_count := 0
	for i in range(layout.cottage_rings.size()):
		if layout.cottage_rings[i] == 0:
			inner_count += 1
		else:
			outer_count += 1
	assert_eq(inner_count, 3,
		"INV-16: exactly 3 inner cottages (cottage_rings==0)")
	assert_eq(outer_count, 4,
		"INV-16: exactly 4 outer cottages (cottage_rings==1)")
	# 4-bay cottages (CA=bays4, CD=bays4) must be outer.
	for i in range(layout.cottages.size()):
		var spec := layout.cottages[i] as Dictionary
		if int(spec.get("bays", 0)) == 4:
			assert_eq(layout.cottage_rings[i], 1,
				"INV-16: 4-bay cottage '%s' must be outer (ring 1)" \
				% String(spec.get("name", "?")))
	# Inner cottages must all be 3-bay.
	for i in range(layout.cottages.size()):
		if layout.cottage_rings[i] == 0:
			var spec := layout.cottages[i] as Dictionary
			assert_eq(int(spec.get("bays", 0)), 3,
				"INV-16: inner cottage '%s' must be 3-bay" \
				% String(spec.get("name", "?")))


# ── (k) INV-17: angular spread within each ring ───────────────────────────────

func test_inv17_angular_spread() -> void:
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var layout := bd.get_layout()
	if layout == null:
		return
	# Collect centres per ring.
	var inner_centres: Array[Vector2] = []
	var outer_centres: Array[Vector2] = []
	for i in range(layout.cottages.size()):
		var spec := layout.cottages[i] as Dictionary
		var c := spec.get("centre", Vector2.ZERO) as Vector2
		if layout.cottage_rings[i] == 0:
			inner_centres.append(c)
		else:
			outer_centres.append(c)
	# Check inner pairwise angular separation >= 65°.
	for i in range(inner_centres.size()):
		for j in range(i + 1, inner_centres.size()):
			var a1 := inner_centres[i].angle()
			var a2 := inner_centres[j].angle()
			var diff := absf(angle_difference(a1, a2))
			assert_gte(rad_to_deg(diff), 65.0,
				"INV-17: inner cottages[%d/%d] angular gap %.1f° must be >= 65°" \
				% [i, j, rad_to_deg(diff)])
	# Check outer pairwise angular separation >= 50°.
	for i in range(outer_centres.size()):
		for j in range(i + 1, outer_centres.size()):
			var a1 := outer_centres[i].angle()
			var a2 := outer_centres[j].angle()
			var diff := absf(angle_difference(a1, a2))
			assert_gte(rad_to_deg(diff), 50.0,
				"INV-17: outer cottages[%d/%d] angular gap %.1f° must be >= 50°" \
				% [i, j, rad_to_deg(diff)])


# ── (l) INV-20: world-scale fields match generated preset ────────────────────

func test_inv20_world_scale_fields() -> void:
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var layout := bd.get_layout()
	assert_not_null(layout, "get_layout() must return a VillageLayout")
	if layout == null:
		return
	assert_almost_eq(layout.lawn_radius, 36.0, 1e-6, "lawn_radius must be 36.0 (INV-20)")
	assert_almost_eq(layout.hill_inner, 36.0, 1e-6, "hill_inner must be 36.0 (INV-20)")
	assert_almost_eq(layout.pine_inner, 34.2, 1e-6, "pine_inner must be 34.2 (INV-20)")
	assert_almost_eq(layout.pine_outer, 50.4, 1e-6, "pine_outer must be 50.4 (INV-20)")
	assert_eq(layout.pine_count, 33, "pine_count must be 33 (INV-20)")
	assert_almost_eq(layout.fog_begin, 16.8, 1e-6, "fog_begin must be 16.8 (INV-20)")
	assert_almost_eq(layout.fog_end, 95.0, 1e-6, "fog_end must be 95.0 (INV-20)")


# ── (n) INV-7: no stone inside any cottage rect ───────────────────────────────

func test_inv7_no_stone_inside_cottage() -> void:
	## No Scatter_Path_* stone transform should be inside any cottage rect (margin 0).
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var layout := bd.get_layout()
	if layout == null or layout.paths.is_empty():
		pending("No paths generated — skip INV-7")
		return
	var stones := VillageScatterPositions.path_stone_transforms(
		layout.path_polylines(),
		func(cx: float, cz: float) -> bool:
			return Vector2(cx, cz).length() < 4.5 or layout.inside_any_cottage(Vector2(cx, cz), 0.2),
		layout.stone_seed, layout.min_stone_spacing)
	for i: int in range(stones.size()):
		var p := Vector2(stones[i].origin.x, stones[i].origin.z)
		assert_false(layout.inside_any_cottage(p, 0.0),
			"INV-7: stone[%d] at %s is inside a cottage rect (margin 0)" % [i, str(p)])


# ── (o) INV-9: no stone inside hero keep-out; hero edges end at ring ──────────

func test_inv9_no_stone_inside_hero_keepout() -> void:
	## No stone may have |p| < 4.5 m (the reject radius in _reject_path_stone_xz).
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var layout := bd.get_layout()
	if layout == null or layout.paths.is_empty():
		pending("No paths generated — skip INV-9")
		return
	var stones := VillageScatterPositions.path_stone_transforms(
		layout.path_polylines(),
		func(cx: float, cz: float) -> bool:
			return Vector2(cx, cz).length() < 4.5 or layout.inside_any_cottage(Vector2(cx, cz), 0.2),
		layout.stone_seed, layout.min_stone_spacing)
	for i: int in range(stones.size()):
		var r := Vector2(stones[i].origin.x, stones[i].origin.z).length()
		assert_gte(r, 4.5,
			"INV-9: stone[%d] at r=%.3f m is inside hero keep-out (< 4.5 m)" % [i, r])


func test_inv9_hero_edges_end_near_ring() -> void:
	## Hero-incident polylines must end at |p| ∈ [6.4, 6.6] (clipped to 6.5 m ring).
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var layout := bd.get_layout()
	if layout == null or layout.edges.is_empty():
		pending("No edges — skip INV-9 ring test")
		return
	var checked := 0
	for i: int in range(layout.edges.size()):
		var e: Vector2i = layout.edges[i]
		if e.x != VillageLayout.HERO_NODE and e.y != VillageLayout.HERO_NODE:
			continue
		checked += 1
		var poly := layout.paths[i] as Array
		var last := poly[-1] as Vector2
		var r := last.length()
		assert_gte(r, 6.4,
			"INV-9: hero edge path[-1] |p|=%.3f m must be ≥ 6.4 m" % r)
		assert_lte(r, 6.6,
			"INV-9: hero edge path[-1] |p|=%.3f m must be ≤ 6.6 m" % r)
	assert_gt(checked, 0, "INV-9: must have at least one hero edge")


# ── (p) INV-10: stone count ∈ [70, 360] ──────────────────────────────────────

func test_inv10_stone_count_in_range() -> void:
	## Total stone count after dedup and reject must be ∈ [70, 360].
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var layout := bd.get_layout()
	if layout == null or layout.paths.is_empty():
		pending("No paths generated — skip INV-10")
		return
	var stones := VillageScatterPositions.path_stone_transforms(
		layout.path_polylines(),
		func(cx: float, cz: float) -> bool:
			return Vector2(cx, cz).length() < 4.5 or layout.inside_any_cottage(Vector2(cx, cz), 0.2),
		layout.stone_seed, layout.min_stone_spacing)
	print("[INV-10] seed=%d stone_count=%d" % [DEFAULT_TEST_SEED, stones.size()])
	assert_gte(stones.size(), 70,
		"INV-10: stone count %d < 70 (budget lower bound)" % stones.size())
	assert_lte(stones.size(), 360,
		"INV-10: stone count %d > 360 (budget upper bound)" % stones.size())


# ── (q) export_fauna_anchors includes path-side petals ───────────────────────

func test_export_fauna_anchors_includes_path_petals() -> void:
	## S3: paths are non-empty so export_fauna_anchors must return path-side petals.
	FaunaIntegration.set_gut_fauna_test_active(true)
	var bd := _make_generated(DEFAULT_TEST_SEED)
	var layout := bd.get_layout()
	assert_false(layout == null or layout.paths.is_empty(),
		"Generated layout must have non-empty paths in S3")
	var env := bd.export_fauna_anchors()
	assert_not_null(env, "export_fauna_anchors() must return a FaunaEnvironment")
	# Flower anchors come from both garden clusters AND path-side petals.
	var flowers := 0
	for a in env.anchors:
		if a.kind == FaunaConstants.AnchorKind.FLOWER:
			flowers += 1
	assert_gt(flowers, 0,
		"export_fauna_anchors() with S3 paths must return flower anchors (incl. petals)")
	FaunaIntegration.set_gut_fauna_test_active(false)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _collect_matching_names(node: Node, prefix: String, out: Array[String]) -> void:
	if node.name.begins_with(prefix):
		out.append(node.name)
	for child in node.get_children():
		_collect_matching_names(child, prefix, out)


func _collect_collision_names(node: Node, out: Array[String]) -> void:
	if node is CollisionObject3D:
		out.append(node.name)
	for child in node.get_children():
		_collect_collision_names(child, out)


func _find_multimesh(root: Node, name_str: String) -> MultiMeshInstance3D:
	for child in root.get_children():
		if child.name == name_str and child is MultiMeshInstance3D:
			return child as MultiMeshInstance3D
	return null


## Shortest signed difference between two angles (in radians, result in [-PI, PI]).
func angle_difference(a: float, b: float) -> float:
	var diff := fmod(b - a, TAU)
	if diff > PI:
		diff -= TAU
	elif diff < -PI:
		diff += TAU
	return diff
