## Tests for VillageLayout world-scale fields and builder field-reading (ivy-80z S2b).
##
## (a) authored() world fields == classic literals (nine fields, pure data test).
## (b) Classic builder equivalence: LawnGround r≈20, HillRing inner≈20/outer≈140/h≈7.5,
##     FarTreeline count=22 radii∈[19,28].
## (c) Generated fields == INV-20 preset for seeds 1..5 (pure data).
## (d) Generated builder outputs for seed=1: LawnGround r≈30, HillRing inner≈30,
##     FarTreeline count=33 radii∈[34.2,50.4].
## (e) Bush filler range: last 10 of bush_common_positions in [bush_filler_inner, bush_filler_outer].
## (f) INV-20: pine_inner >= max outer-cottage corner distance; no pine inside grown rect (seeds 1..5).
extends GutTest

const VillageBackdropScene = preload("res://src/world/village_backdrop.tscn")


## Inline subclass: overrides _make_layout() to return a generated layout for a given seed.
class _GenBackdrop extends VillageBackdrop:
	var test_seed: int = 1
	func _make_layout() -> VillageLayout:
		return VillageLayout.generate(test_seed)


# ── Helpers ───────────────────────────────────────────────────────────────────

## All vertices of mesh surface 0.
func _mesh_verts(mesh: Mesh) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(0)
	if arrays == null:
		return PackedVector3Array()
	return arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array


## Maximum XZ distance across all vertices in the array.
func _max_xz_radius(verts: PackedVector3Array) -> float:
	return _max_xz_radius_about(Vector2.ZERO, verts)


func _max_xz_radius_about(centre: Vector2, verts: PackedVector3Array) -> float:
	var mx := 0.0
	for v in verts:
		mx = maxf(mx, Vector2(v.x, v.z).distance_to(centre))
	return mx


## Minimum XZ distance among vertices whose y is within `tol` of `target_y`.
func _min_xz_at_y(verts: PackedVector3Array, target_y: float, tol: float) -> float:
	return _min_xz_at_y_about(Vector2.ZERO, verts, target_y, tol)


func _min_xz_at_y_about(centre: Vector2, verts: PackedVector3Array, target_y: float, tol: float) -> float:
	var mn := INF
	for v in verts:
		if absf(v.y - target_y) < tol:
			mn = minf(mn, Vector2(v.x, v.z).distance_to(centre))
	return mn


## Maximum XZ distance among vertices whose y is within `tol` of `target_y`.
func _max_xz_at_y(verts: PackedVector3Array, target_y: float, tol: float) -> float:
	var mx := 0.0
	for v in verts:
		if absf(v.y - target_y) < tol:
			mx = maxf(mx, Vector2(v.x, v.z).length())
	return mx


## Forest / classic ring XZ positions (shared with VillageBackdrop._pine_positions).
func _compute_pine_xz(layout: VillageLayout) -> Array[Vector2]:
	return VillageScatterPositions.forest_tree_xz(layout)


## Farthest cottage corner distance from hamlet centre G.
func _farthest_corner_dist_from_g(spec: Dictionary, g: Vector2) -> float:
	var rect := VillageBackdrop.cottage_exterior_rect(spec)
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	var mx := 0.0
	for c: Vector2 in corners:
		mx = maxf(mx, c.distance_to(g))
	return mx


# ── (a) authored() world fields == classic literals ───────────────────────────

func test_authored_world_fields_are_classic_literals() -> void:
	var layout := VillageLayout.authored()
	assert_almost_eq(layout.lawn_radius, 20.0, 1e-6,
		"lawn_radius must be classic literal 20.0")
	assert_almost_eq(layout.hill_inner, 20.0, 1e-6,
		"hill_inner must be classic literal 20.0")
	assert_almost_eq(layout.pine_inner, 19.0, 1e-6,
		"pine_inner must be classic literal 19.0")
	assert_almost_eq(layout.pine_outer, 28.0, 1e-6,
		"pine_outer must be classic literal 28.0")
	assert_eq(layout.pine_count, 22,
		"pine_count must be classic literal 22")
	assert_almost_eq(layout.fog_begin, 9.5, 1e-6,
		"fog_begin must be classic literal 9.5")
	assert_almost_eq(layout.fog_end, 95.0, 1e-6,
		"fog_end must be classic literal 95.0")
	assert_almost_eq(layout.bush_filler_inner, 8.0, 1e-6,
		"bush_filler_inner must be classic literal 8.0")
	assert_almost_eq(layout.bush_filler_outer, 15.0, 1e-6,
		"bush_filler_outer must be classic literal 15.0")


# ── (b) Classic builder equivalence ──────────────────────────────────────────

func test_classic_lawn_radius_in_mesh() -> void:
	var bd := VillageBackdropScene.instantiate()
	add_child_autofree(bd)
	var node := bd.get_node_or_null("LawnGround") as MeshInstance3D
	assert_not_null(node, "LawnGround must exist in classic backdrop")
	if node == null:
		return
	var verts := _mesh_verts(node.mesh)
	assert_gt(verts.size(), 0, "LawnGround must have vertices")
	var max_r := _max_xz_radius(verts)
	assert_almost_eq(max_r, 20.0, 0.01,
		"Classic LawnGround vertex radius must be 20.0 m (builder read lawn_radius)")


func test_classic_hill_ring_in_mesh() -> void:
	var bd := VillageBackdropScene.instantiate()
	add_child_autofree(bd)
	var node := bd.get_node_or_null("HillRing") as MeshInstance3D
	assert_not_null(node, "HillRing must exist in classic backdrop")
	if node == null:
		return
	var verts := _mesh_verts(node.mesh)
	assert_gt(verts.size(), 0, "HillRing must have vertices")
	# Inner ring: vertices at y≈0 with XZ radius ≈ hill_inner=20
	var inner_r := _min_xz_at_y(verts, 0.0, 0.1)
	assert_almost_eq(inner_r, 20.0, 0.1,
		"Classic HillRing inner radius must be ≈ 20.0 m (builder read hill_inner)")
	# Outer ring: vertices at y≈7.5 with XZ radius ≈ 140
	var outer_r := _max_xz_at_y(verts, 7.5, 0.1)
	assert_almost_eq(outer_r, 140.0, 0.1,
		"Classic HillRing outer radius must be ≈ 140.0 m (unchanged)")


func test_classic_pine_count_and_radii() -> void:
	var bd := VillageBackdropScene.instantiate()
	add_child_autofree(bd)
	var treeline: MultiMeshInstance3D = null
	for child in bd.get_children():
		if child.name == "FarTreeline" and child is MultiMeshInstance3D:
			treeline = child as MultiMeshInstance3D
			break
	assert_not_null(treeline, "FarTreeline must exist in classic backdrop")
	if treeline == null:
		return
	assert_not_null(treeline.multimesh, "FarTreeline must have a multimesh")
	if treeline.multimesh == null:
		return
	assert_eq(treeline.multimesh.instance_count, 22,
		"Classic FarTreeline instance_count must be 22 (builder read pine_count)")
	var buf := treeline.multimesh.buffer
	for i in range(treeline.multimesh.instance_count):
		var ox: float = buf[i * 12 + 3]
		var oz: float = buf[i * 12 + 11]
		var r := sqrt(ox * ox + oz * oz)
		assert_gte(r, 19.0,
			"Classic pine[%d] radius %.3f must be >= 19.0 (pine_inner)" % [i, r])
		assert_lte(r, 28.0,
			"Classic pine[%d] radius %.3f must be <= 28.0 (pine_outer)" % [i, r])


# ── (c) Generated fields == INV-20 preset for seeds 1..5 ─────────────────────

func test_generated_world_fields_seeds_1_to_5() -> void:
	for seed in [1, 2, 3, 4, 5]:
		var layout := VillageLayout.generate(seed)
		var tag := "seed=%d" % seed
		if layout.fallback:
			pending("generate(%d) fell back to authored — skipping world-scale check" % seed)
			continue
		assert_almost_eq(layout.lawn_radius, VillageLayout.GENERATED_LAWN_RADIUS, 1e-6,
			"lawn_radius generated %s" % tag)
		assert_almost_eq(layout.hill_inner, VillageLayout.GENERATED_HILL_INNER, 1e-6,
			"hill_inner generated %s" % tag)
		assert_almost_eq(layout.pine_inner, VillageLayout.GENERATED_PINE_INNER, 1e-6,
			"pine_inner generated %s" % tag)
		assert_almost_eq(layout.pine_outer, VillageLayout.GENERATED_PINE_OUTER, 1e-6,
			"pine_outer generated %s" % tag)
		assert_eq(layout.pine_count, VillageLayout.GENERATED_PINE_COUNT,
			"pine_count generated %s" % tag)
		assert_almost_eq(layout.fog_begin, VillageLayout.GENERATED_FOG_BEGIN, 1e-6,
			"fog_begin generated %s" % tag)
		assert_almost_eq(layout.fog_end, 95.0, 1e-6,
			"fog_end generated %s" % tag)
		assert_almost_eq(layout.bush_filler_inner, 8.0, 1e-6,
			"bush_filler_inner generated %s" % tag)
		assert_almost_eq(layout.bush_filler_outer, VillageLayout.GENERATED_BUSH_FILLER_OUTER, 1e-6,
			"bush_filler_outer generated %s" % tag)


# ── (d) Generated builder outputs for seed=1 ─────────────────────────────────

func test_generated_lawn_radius_in_mesh() -> void:
	var bd := _GenBackdrop.new()
	bd.test_seed = 1
	add_child_autofree(bd)
	var node := bd.get_node_or_null("LawnGround") as MeshInstance3D
	assert_not_null(node, "LawnGround must exist in generated backdrop")
	if node == null:
		return
	var verts := _mesh_verts(node.mesh)
	assert_gt(verts.size(), 0, "LawnGround must have vertices")
	var g := VillageLayout.VILLAGE_GREEN_G
	var max_r := _max_xz_radius_about(g, verts)
	assert_almost_eq(max_r, VillageLayout.GENERATED_LAWN_RADIUS, 0.01,
		"Generated LawnGround vertex radius must match GENERATED_LAWN_RADIUS about G")


func test_generated_hill_inner_in_mesh() -> void:
	var bd := _GenBackdrop.new()
	bd.test_seed = 1
	add_child_autofree(bd)
	var node := bd.get_node_or_null("HillRing") as MeshInstance3D
	assert_not_null(node, "HillRing must exist in generated backdrop")
	if node == null:
		return
	var verts := _mesh_verts(node.mesh)
	var g := VillageLayout.VILLAGE_GREEN_G
	var inner_r := _min_xz_at_y_about(g, verts, 0.0, 0.1)
	assert_almost_eq(inner_r, VillageLayout.GENERATED_HILL_INNER, 0.1,
		"Generated HillRing inner radius must match GENERATED_HILL_INNER about G")


func test_generated_pine_count_and_radii() -> void:
	var bd := _GenBackdrop.new()
	bd.test_seed = 1
	add_child_autofree(bd)
	var treeline: MultiMeshInstance3D = null
	for child in bd.get_children():
		if child.name == "FarTreeline" and child is MultiMeshInstance3D:
			treeline = child as MultiMeshInstance3D
			break
	assert_not_null(treeline, "FarTreeline must exist in generated backdrop")
	if treeline == null:
		return
	assert_not_null(treeline.multimesh, "FarTreeline must have a multimesh")
	if treeline.multimesh == null:
		return
	var layout := bd.get_layout()
	var placed := VillageScatterPositions.forest_tree_positions(layout).size()
	assert_eq(treeline.multimesh.instance_count, placed,
		"Generated FarTreeline instance_count must match placement output")
	assert_gte(placed, 24, "CamSun backdrop must place >=24 trees")
	var ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
	var HeroFog = preload("res://src/world/hero_fog.gd")
	var stats := ForestPlaygroundCamera.count_trees_visible_in_camsun(
		VillageScatterPositions.forest_tree_xz(layout),
		layout.fog_begin, layout.fog_end, HeroFog.FogModel.WORLD_AROUND_HERO, 0.5)
	assert_gte(stats["visible"], 12, "backdrop: >=12 CamSun trees at <=50%% hero haze")
	var buf := treeline.multimesh.buffer
	for i in range(treeline.multimesh.instance_count):
		var ox: float = buf[i * 12 + 3]
		var oz: float = buf[i * 12 + 11]
		var p := Vector2(ox, oz)
		for spec: Dictionary in layout.cottages:
			var rect := VillageBackdrop.cottage_exterior_rect(spec)
			assert_false(rect.has_point(p),
				"Generated forest[%d] must not sit inside cottage '%s'" \
				% [i, String(spec.get("name", "?"))])


# ── (e) Bush filler range for seeds 1..5 ─────────────────────────────────────

func test_generated_bush_filler_range() -> void:
	## The filler-ring 10 bushes (last 10 entries in bush_common_positions output)
	## must all lie within [bush_filler_inner, bush_filler_outer] for generated layouts.
	for seed in [1, 2, 3, 4, 5]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var tag := "seed=%d" % seed
		var all_bushes := VillageScatterPositions.bush_common_positions(
			layout.cottages, layout.bush_filler_inner, layout.bush_filler_outer,
			layout.hamlet_centre_xz)
		assert_gte(all_bushes.size(), 10,
			"%s: must have >= 10 total bushes in output" % tag)
		# Filler bushes are always the last 10 elements (appended after per-cottage phase).
		var filler_start := all_bushes.size() - 10
		var g := layout.hamlet_centre_xz
		for i in range(10):
			var t: Transform3D = all_bushes[filler_start + i]
			var r := Vector2(t.origin.x, t.origin.z).distance_to(g)
			assert_gte(r, layout.bush_filler_inner,
				"%s filler[%d] r=%.3f < bush_filler_inner=%.1f" \
				% [tag, i, r, layout.bush_filler_inner])
			assert_lte(r, layout.bush_filler_outer,
				"%s filler[%d] r=%.3f > bush_filler_outer=%.1f" \
				% [tag, i, r, layout.bush_filler_outer])


const _FOREST_KEEP_CLEAR_SEEDS: Array[int] = [
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 240424020,
]


func test_forest_no_trunk_within_hero_keep_clear() -> void:
	## Pines must not sit in the CamSun south-approach corridor (hero → village view).
	for seed: int in _FOREST_KEEP_CLEAR_SEEDS:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var tag := "seed=%d" % seed
		var pines := _compute_pine_xz(layout)
		var placed := VillageScatterPositions.forest_tree_positions(layout).size()
		assert_eq(pines.size(), placed, "%s: expected %d forest positions" % [tag, placed])
		assert_gte(placed, 24, "%s: backdrop tree count" % tag)
		for i: int in pines.size():
			var p: Vector2 = pines[i]
			assert_false(
				VillageScatterPositions.forest_blocks_camsun_view(p),
				"%s forest[%d] at (%.2f,%.2f) blocks CamSun corridor" % [tag, i, p.x, p.y])


func test_forest_backdrop_in_camsun_band() -> void:
	const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
	const HeroFog = preload("res://src/world/hero_fog.gd")
	for seed_val in range(1, 11):
		var layout := VillageLayout.generate(seed_val)
		if layout.fallback:
			continue
		var tag := "seed=%d" % seed_val
		var pines := _compute_pine_xz(layout)
		var stats := ForestPlaygroundCamera.count_trees_visible_in_camsun(
			pines, layout.fog_begin, layout.fog_end, HeroFog.FogModel.WORLD_AROUND_HERO, 0.5)
		assert_gte(stats["visible"], 10,
			"%s: need >=10 visible backdrop trees (got %d)" % [tag, stats["visible"]])


static func _pine_in_hero_wedge(p: Vector2, g: Vector2, r_lawn: float) -> bool:
	if p.y <= VillageLayout.HERO_DOOR_STOOP.y + 1.0:
		return false
	var dg := p - g
	var r_g := dg.length()
	if r_g < r_lawn - 3.0 or r_g > r_lawn + 11.0:
		return false
	return absf(atan2(dg.x, dg.y)) <= 0.62


# ── (f) INV-20: pine_inner >= max cottage corner, no pine inside cottage ──────

func test_inv20_pine_inner_exceeds_max_corner_distance() -> void:
	## Hamlet fits inside lawn R on G; forest collar band uses pine_inner..pine_outer (INV-20).
	for seed in [1, 2, 3, 4, 5]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var tag := "seed=%d" % seed
		var g := layout.hamlet_centre_xz
		var max_corner := 0.0
		for spec: Dictionary in layout.cottages:
			max_corner = maxf(max_corner, _farthest_corner_dist_from_g(spec, g))
		assert_lte(max_corner, layout.lawn_radius + 0.5,
			"%s: max cottage corner from G=%.3f must fit lawn R=%.1f" \
			% [tag, max_corner, layout.lawn_radius])
		assert_lt(layout.pine_inner, layout.lawn_radius,
			"%s: pine_inner collar must sit inside lawn radius" % tag)
		assert_lte(layout.pine_inner, layout.pine_outer, "%s: pine_inner <= pine_outer" % tag)


func test_inv20_no_pine_inside_cottage_grown_rect() -> void:
	## All forest trunks must lie outside every cottage exterior rect (ivy-3l6-C).
	for seed in [1, 2, 3, 4, 5]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var tag := "seed=%d" % seed
		var pines := _compute_pine_xz(layout)
		var placed := VillageScatterPositions.forest_tree_positions(layout).size()
		assert_eq(pines.size(), placed,
			"%s: expected %d forest positions" % [tag, placed])
		for pi in range(pines.size()):
			var p := pines[pi]
			for spec: Dictionary in layout.cottages:
				var rect := VillageBackdrop.cottage_exterior_rect(spec)
				assert_false(rect.has_point(p),
					"%s forest[%d] at (%.2f,%.2f) is inside cottage '%s' exterior rect" \
					% [tag, pi, p.x, p.y, String(spec.get("name", "?"))])
