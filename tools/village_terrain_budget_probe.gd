extends SceneTree
## AC-LT-PERF budget probe (SD-VILLAGE-TERRAIN-23, AR-LF-TESTS; ivy-82zn.14.18 WP3).
##
## For each seed builds a GeneratedVillageBackdrop and reports:
##   - offset search ms (layout.terrain_diag.search_ms; AC <= 300 ms since SD-28) and generate total ms
##   - near mesh (LawnTerrain) triangles and the mesh step used (target <= 8k, hard <= 16k at r 64)
##   - far mesh (HillTerrain) triangles
##   - total backdrop triangles counted like test_triangle_budget_under_120k
##     (MeshInstance3D tris + each MultiMesh mesh once; instanced grass excluded by that rule too)
##   - grass blade count and best-of-3 grass_blade_positions build ms
## Headless is fine (no rendering). One line per seed, then a PERF summary line.
##
## Usage:
##   Godot --path <project> --headless -s res://tools/village_terrain_budget_probe.gd -- --seeds=1,7,12
##   (optional --baseline-grass-ms=<ms> prints the grass build change against a pre-change run)

const NEAR_TRI_TARGET := 8000
const NEAR_TRI_HARD := 16000
const TOTAL_TRI_CAP := 120000


func _initialize() -> void:
	_run.call_deferred()


func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback


func _mesh_tris(mesh: Mesh) -> int:
	var n := 0
	if mesh == null:
		return 0
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		if arrays != null and arrays[Mesh.ARRAY_INDEX] != null:
			n += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif arrays != null and arrays[Mesh.ARRAY_VERTEX] != null:
			n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _walk(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _grass_ctx(layout: VillageLayout) -> VillageGrassExclusionContext:
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var path_stones := VillageScatterPositions.path_stone_transforms(
		layout.path_polylines(),
		func(cx: float, cz: float) -> bool:
			return Vector2(cx, cz).distance_to(VillageLayout.HERO_DOOR_STOOP) < 4.5 \
				or layout.inside_any_cottage(Vector2(cx, cz), 0.2),
		layout.stone_seed, layout.min_stone_spacing)
	var bushes := VillageScatterPositions.bush_common_positions(
		layout.cottages, layout.bush_filler_inner, layout.bush_filler_outer, layout.hamlet_centre_xz)
	return VillageGrassExclusionContext.for_layout(
		layout.paths,
		func(p: Vector2) -> bool: return layout.inside_any_cottage(p, VillageScatterPositions.COTTAGE_MARGIN),
		path_stones, bushes, layout.hamlet_centre_xz, VillageLayout.HERO_DOOR_STOOP, true, layout.cottages)


func _run() -> void:
	var seeds: Array[int] = []
	for s in _arg("--seeds=", "1,7,12").split(","):
		seeds.append(int(s))
	var base_grass := float(_arg("--baseline-grass-ms=", "0"))
	var worst_near := 0
	var worst_total := 0
	var worst_search := 0.0
	var grass_ms_sum := 0.0
	var blades_max := 0
	for seed in seeds:
		var t0 := Time.get_ticks_usec()
		var bd := (load("res://src/world/generated_village_backdrop.tscn") as PackedScene).instantiate()
		bd.call("set_village_seed", seed)
		root.add_child(bd)
		var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var layout: VillageLayout = bd.call("get_layout")
		var tp: VillageTerrainParams = layout.terrain_params if layout.terrain_params != null \
			else VillageTerrainParams.production()
		var nodes: Array = []
		_walk(bd, nodes)
		var near := 0
		var far := 0
		var total := 0
		for n in nodes:
			if n is MeshInstance3D:
				var t := _mesh_tris((n as MeshInstance3D).mesh)
				total += t
				if n.name == "LawnTerrain":
					near = t
				elif n.name == "HillTerrain":
					far = t
			elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
				total += _mesh_tris((n as MultiMeshInstance3D).multimesh.mesh)
		var ctx := _grass_ctx(layout)
		var best := INF
		var blades := 0
		for rep in range(3):
			var tg := Time.get_ticks_usec()
			blades = VillageScatterPositions.grass_blade_positions(ctx).size()
			best = minf(best, float(Time.get_ticks_usec() - tg) / 1000.0)
		var search_ms := float(layout.terrain_diag.get("search_ms", NAN))
		print("BUDGET seed %d fb %s lawn %.0f step %.2f near_tris %d far_tris %d total_tris %d search_ms %.0f backdrop_build_ms %.0f grass_blades %d grass_ms %.0f" % [
			seed, layout.fallback, layout.lawn_radius, VillageTerrain.mesh_step(layout, tp.terrain_mesh_step_m),
			near, far, total, search_ms, build_ms, blades, best])
		worst_near = maxi(worst_near, near)
		worst_total = maxi(worst_total, total)
		worst_search = maxf(worst_search, search_ms)
		grass_ms_sum += best
		blades_max = maxi(blades_max, blades)
		bd.free()
	var grass_mean := grass_ms_sum / float(seeds.size())
	var grass_delta := "" if base_grass <= 0.0 else " grass_vs_baseline %+.1f%%" % ((grass_mean / base_grass - 1.0) * 100.0)
	print("PERF near_tris_max %d (target %d, hard %d) total_tris_max %d (cap %d) search_ms_max %.0f (<= 300, SD-28) grass_ms_mean %.0f grass_blades_max %d%s" % [
		worst_near, NEAR_TRI_TARGET, NEAR_TRI_HARD, worst_total, TOTAL_TRI_CAP, worst_search, grass_mean,
		blades_max, grass_delta])
	quit()
