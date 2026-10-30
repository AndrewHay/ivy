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
	var mx := 0.0
	for v in verts:
		mx = maxf(mx, Vector2(v.x, v.z).length())
	return mx


## Minimum XZ distance among vertices whose y is within `tol` of `target_y`.
func _min_xz_at_y(verts: PackedVector3Array, target_y: float, tol: float) -> float:
	var mn := INF
	for v in verts:
		if absf(v.y - target_y) < tol:
			mn = minf(mn, Vector2(v.x, v.z).length())
	return mn


## Maximum XZ distance among vertices whose y is within `tol` of `target_y`.
func _max_xz_at_y(verts: PackedVector3Array, target_y: float, tol: float) -> float:
	var mx := 0.0
	for v in verts:
		if absf(v.y - target_y) < tol:
			mx = maxf(mx, Vector2(v.x, v.z).length())
	return mx


## Replicate _pine_positions LCG logic from VillageBackdrop using layout fields.
## Returns XZ positions only (no scale/rot). Used for INV-20 without scene instantiation.
func _compute_pine_xz(layout: VillageLayout) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := layout.pine_count
	var st := 7
	for i in range(n):
		# Draw 1: angle jitter
		st = VillageScatterPositions.lcg_step(st)
		var angle_jitter: float = (VillageScatterPositions.lcg_f01(st) - 0.5) * 0.5
		var angle: float = (float(i) / n) * TAU + angle_jitter
		# Draw 2: radius
		st = VillageScatterPositions.lcg_step(st)
		var r: float = lerpf(layout.pine_inner, layout.pine_outer,
			VillageScatterPositions.lcg_f01(st))
		# Draw 3: scale (consumed but not needed for XZ)
		st = VillageScatterPositions.lcg_step(st)
		# Draw 4: rotation (consumed but not needed for XZ)
		st = VillageScatterPositions.lcg_step(st)
		out.append(Vector2(cos(angle) * r, sin(angle) * r))
	return out


## Farthest corner distance from origin for a cottage spec.
func _farthest_corner_dist(spec: Dictionary) -> float:
	var rect := VillageBackdrop.cottage_exterior_rect(spec)
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	var mx := 0.0
	for c: Vector2 in corners:
		mx = maxf(mx, c.length())
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
		assert_almost_eq(layout.lawn_radius, 36.0, 1e-6,
			"lawn_radius generated %s" % tag)
		assert_almost_eq(layout.hill_inner, 36.0, 1e-6,
			"hill_inner generated %s" % tag)
		assert_almost_eq(layout.pine_inner, 34.2, 1e-6,
			"pine_inner generated %s" % tag)
		assert_almost_eq(layout.pine_outer, 50.4, 1e-6,
			"pine_outer generated %s" % tag)
		assert_eq(layout.pine_count, 33,
			"pine_count generated %s" % tag)
		assert_almost_eq(layout.fog_begin, 16.8, 1e-6,
			"fog_begin generated %s" % tag)
		assert_almost_eq(layout.fog_end, 95.0, 1e-6,
			"fog_end generated %s" % tag)
		assert_almost_eq(layout.bush_filler_inner, 8.0, 1e-6,
			"bush_filler_inner generated %s" % tag)
		assert_almost_eq(layout.bush_filler_outer, 26.4, 1e-6,
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
	var max_r := _max_xz_radius(verts)
	assert_almost_eq(max_r, 36.0, 0.01,
		"Generated LawnGround vertex radius must be 36.0 m (builder reads layout.lawn_radius)")


func test_generated_hill_inner_in_mesh() -> void:
	var bd := _GenBackdrop.new()
	bd.test_seed = 1
	add_child_autofree(bd)
	var node := bd.get_node_or_null("HillRing") as MeshInstance3D
	assert_not_null(node, "HillRing must exist in generated backdrop")
	if node == null:
		return
	var verts := _mesh_verts(node.mesh)
	var inner_r := _min_xz_at_y(verts, 0.0, 0.1)
	assert_almost_eq(inner_r, 36.0, 0.1,
		"Generated HillRing inner radius must be ≈ 36.0 m (builder reads layout.hill_inner)")


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
	assert_eq(treeline.multimesh.instance_count, 33,
		"Generated FarTreeline instance_count must be 33 (builder reads layout.pine_count)")
	var buf := treeline.multimesh.buffer
	for i in range(treeline.multimesh.instance_count):
		var ox: float = buf[i * 12 + 3]
		var oz: float = buf[i * 12 + 11]
		var r := sqrt(ox * ox + oz * oz)
		assert_gte(r, 34.2,
			"Generated pine[%d] radius %.3f must be >= 34.2 (pine_inner)" % [i, r])
		assert_lte(r, 50.4,
			"Generated pine[%d] radius %.3f must be <= 50.4 (pine_outer)" % [i, r])


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
			layout.cottages, layout.bush_filler_inner, layout.bush_filler_outer)
		assert_gte(all_bushes.size(), 10,
			"%s: must have >= 10 total bushes in output" % tag)
		# Filler bushes are always the last 10 elements (appended after per-cottage phase).
		var filler_start := all_bushes.size() - 10
		for i in range(10):
			var t: Transform3D = all_bushes[filler_start + i]
			var r := Vector2(t.origin.x, t.origin.z).length()
			assert_gte(r, layout.bush_filler_inner,
				"%s filler[%d] r=%.3f < bush_filler_inner=%.1f" \
				% [tag, i, r, layout.bush_filler_inner])
			assert_lte(r, layout.bush_filler_outer,
				"%s filler[%d] r=%.3f > bush_filler_outer=%.1f" \
				% [tag, i, r, layout.bush_filler_outer])


# ── (f) INV-20: pine_inner >= max cottage corner, no pine inside cottage ──────

func test_inv20_pine_inner_exceeds_max_corner_distance() -> void:
	## pine_inner (34.2 for generated) must be >= the farthest grown corner from origin
	## across all cottages in the generated layout. This ensures no pine can be placed
	## inside a cottage's XZ footprint (INV-20).
	for seed in [1, 2, 3, 4, 5]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var tag := "seed=%d" % seed
		var max_corner := 0.0
		for spec: Dictionary in layout.cottages:
			max_corner = maxf(max_corner, _farthest_corner_dist(spec))
		assert_gte(layout.pine_inner, max_corner,
			"%s: pine_inner=%.3f must be >= max cottage corner dist=%.3f (INV-20)" \
			% [tag, layout.pine_inner, max_corner])


func test_inv20_no_pine_inside_cottage_grown_rect() -> void:
	## All pine XZ positions computed via the layout's fields must lie outside every
	## cottage's exterior rect. Uses the same LCG sequence as VillageBackdrop._pine_positions.
	for seed in [1, 2, 3, 4, 5]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var tag := "seed=%d" % seed
		var pines := _compute_pine_xz(layout)
		assert_eq(pines.size(), layout.pine_count,
			"%s: expected %d pine positions" % [tag, layout.pine_count])
		for pi in range(pines.size()):
			var p := pines[pi]
			for spec: Dictionary in layout.cottages:
				var rect := VillageBackdrop.cottage_exterior_rect(spec)
				assert_false(rect.has_point(p),
					"%s pine[%d] at (%.2f,%.2f) is inside cottage '%s' exterior rect" \
					% [tag, pi, p.x, p.y, String(spec.get("name", "?"))])
