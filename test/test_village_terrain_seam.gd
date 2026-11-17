## ivy-82zn.14.14 (WP1) — AC-LT-SEAM: one height function for lawn and outer hills, and the near /
## far meshes stitched on a shared join loop (replaces test_village_terrain_rim.gd and
## test_hills_mesh_toe.gd). SD-VILLAGE-TERRAIN-23, AR-LF-D6, AR-LF-D9, AR-LF-GAP-3.
extends GutTest

const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsParams = preload("res://src/playground/hills_params.gd")

const _SEED := 7

var _layout: VillageLayout
var _params: VillageTerrainParams
var _hp: HillsParams


func before_all() -> void:
	_layout = VillageLayout.generate(_SEED)
	_params = VillageTerrainParams.production()
	_hp = HillsParams.production()


func test_hills_sample_y_is_the_village_field() -> void:
	var t_seed := HillsHeightfield.terrain_seed(_layout, _hp)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var g := _layout.hamlet_centre_xz
	var worst := 0.0
	for i in range(1000):
		var a := rng.randf() * TAU
		var r := rng.randf() * 320.0
		var xz := g + Vector2(sin(a), cos(a)) * r
		var hy := HillsHeightfield.sample_y(xz, _layout, _hp, t_seed)
		var vy := VillageTerrain.sample_y(xz, _layout, _params, 0)
		worst = maxf(worst, absf(hy - vy))
	assert_eq(worst, 0.0, "HillsHeightfield.sample_y == VillageTerrain.sample_y exactly (1000 xz)")


func test_no_step_or_kink_on_seam_circles() -> void:
	var g := _layout.hamlet_centre_xz
	for r in [56.0, 64.0, _layout.lawn_radius]:
		var worst_step := 0.0
		var worst_kink := 0.0
		for k in range(360):
			var a := deg_to_rad(float(k))
			var d := Vector2(sin(a), cos(a))
			var y := func(rr: float) -> float:
				return VillageTerrain.sample_y(g + d * rr, _layout, _params, 0)
			worst_step = maxf(worst_step, absf(float(y.call(r + 0.05)) - float(y.call(r - 0.05))))
			worst_kink = maxf(worst_kink,
				absf(float(y.call(r + 1.0)) - 2.0 * float(y.call(r)) + float(y.call(r - 1.0))))
		assert_lte(worst_step, 0.07, "r %.0f step %.3f m" % [r, worst_step])
		assert_lte(worst_kink, 0.15, "r %.0f kink %.3f m" % [r, worst_kink])


func test_join_loop_lies_on_the_lawn_circle_in_azimuth_order() -> void:
	var loop: PackedVector2Array = VillageTerrain.join_loop(_layout, _params)
	assert_gt(loop.size(), 100, "join loop has points (%d)" % loop.size())
	var g := _layout.hamlet_centre_xz
	var last := -INF
	for p: Vector2 in loop:
		assert_almost_eq(p.distance_to(g), _layout.lawn_radius, 1e-3, "loop point on r_j")
		var ang := fposmod(atan2(p.y - g.y, p.x - g.x), TAU)
		assert_true(ang >= last, "loop sorted by azimuth")
		last = ang


func _vertex_map(mesh: ArrayMesh) -> Dictionary:
	## Rounded xz key -> [y, normal] for every vertex of surface 0.
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var out := {}
	for i in range(verts.size()):
		var v := verts[i]
		out[Vector2i(roundi(v.x * 1000.0), roundi(v.z * 1000.0))] = [v.y, norms[i]]
	return out


func test_near_and_far_meshes_share_join_loop_vertices() -> void:
	var near := VillageTerrain.build_mesh(_layout, _params)
	var far := HillsHeightfield.build_mesh(_layout, _hp)
	var nm := _vertex_map(near)
	var fm := _vertex_map(far)
	var loop: PackedVector2Array = VillageTerrain.join_loop(_layout, _params)
	var missing := 0
	var worst_y := 0.0
	var worst_n := 0.0
	for p: Vector2 in loop:
		var key := Vector2i(roundi(p.x * 1000.0), roundi(p.y * 1000.0))
		if not nm.has(key) or not fm.has(key):
			missing += 1
			continue
		worst_y = maxf(worst_y, absf(float(nm[key][0]) - float(fm[key][0])))
		worst_n = maxf(worst_n, ((nm[key][1] as Vector3) - (fm[key][1] as Vector3)).length())
	assert_eq(missing, 0, "every join-loop point is a vertex of both meshes")
	assert_lte(worst_y, 1e-5, "loop vertex y identical (%.6f)" % worst_y)
	assert_lte(worst_n, 1e-5, "loop vertex normal identical (%.6f)" % worst_n)


func _knob_min(knob: String) -> float:
	for row: Dictionary in VillageTerrainKnobSpec.all_knobs():
		if row["name"] == knob:
			return float(row["min"])
	return NAN


func test_near_mesh_keeps_every_row_at_the_knob_minimum_step() -> void:
	## ivy-82zn.14.21 F1: at terrain_mesh_step_m = knob min the old tri cap broke out of every row
	## past ~16k tris, leaving a hole and an open seam. Checked at today's r_j and WP3's 64 m.
	var step_min := _knob_min("terrain_mesh_step_m")
	assert_false(is_nan(step_min), "terrain_mesh_step_m knob exists")
	for r_j in [VillageLayout.GENERATED_LAWN_RADIUS, 64.0]:
		var layout := VillageLayout.generate(_SEED)
		layout.lawn_radius = r_j
		var p := VillageTerrainParams.production()
		p.terrain_mesh_step_m = step_min
		VillageTerrain.clear_caches()
		var near := VillageTerrain.build_mesh(layout, p)
		var tris := near.surface_get_array_len(0) / 3
		assert_lte(tris, VillageTerrain.NEAR_TRI_HARD_CAP, "r_j %.0f: near mesh within the hard cap (%d)" % [r_j, tris])
		var nm := _vertex_map(near)
		var loop: PackedVector2Array = VillageTerrain.join_loop(layout, p)
		var missing := 0
		for q: Vector2 in loop:
			if not nm.has(Vector2i(roundi(q.x * 1000.0), roundi(q.y * 1000.0))):
				missing += 1
		assert_eq(missing, 0, "r_j %.0f: every join-loop point (%d) is a lawn vertex" % [r_j, loop.size()])
		# The far mesh zips to the same loop, so the seam is closed.
		var fm := _vertex_map(VillageTerrain.build_far_mesh(layout, p))
		var far_missing := 0
		for q: Vector2 in loop:
			if not fm.has(Vector2i(roundi(q.x * 1000.0), roundi(q.y * 1000.0))):
				far_missing += 1
		assert_eq(far_missing, 0, "r_j %.0f: every join-loop point is a far vertex" % r_j)
	VillageTerrain.clear_caches()


func test_far_mesh_inner_boundary_is_the_loop_polygon() -> void:
	## Every loop segment is an edge of exactly one far-mesh triangle: no crack, no overlap.
	var far := HillsHeightfield.build_mesh(_layout, _hp)
	var arrays := far.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_gt(idx.size(), 0, "far mesh is indexed")
	var loop: PackedVector2Array = VillageTerrain.join_loop(_layout, _params)
	var loop_id := {}
	for i in range(loop.size()):
		loop_id[Vector2i(roundi(loop[i].x * 1000.0), roundi(loop[i].y * 1000.0))] = i
	var vert_loop := PackedInt32Array()
	vert_loop.resize(verts.size())
	for i in range(verts.size()):
		var key := Vector2i(roundi(verts[i].x * 1000.0), roundi(verts[i].z * 1000.0))
		vert_loop[i] = int(loop_id.get(key, -1))
	var seg_uses := {}
	for t in range(0, idx.size(), 3):
		for e in range(3):
			var a := vert_loop[idx[t + e]]
			var b := vert_loop[idx[t + (e + 1) % 3]]
			if a < 0 or b < 0:
				continue
			var n := loop.size()
			if (a + 1) % n == b or (b + 1) % n == a:
				var k := mini(a, b) * 100000 + maxi(a, b)
				seg_uses[k] = int(seg_uses.get(k, 0)) + 1
	assert_eq(seg_uses.size(), loop.size(), "every loop segment is a far-mesh edge")
	for k in seg_uses:
		assert_eq(int(seg_uses[k]), 1, "loop segment used once")
		break
	assert_lte(idx.size() / 3, 24000, "far mesh triangle budget (%d)" % (idx.size() / 3))


func test_far_mesh_has_no_base_lift() -> void:
	var far := HillsHeightfield.build_mesh(_layout, _hp)
	var verts: PackedVector3Array = far.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var worst := 0.0
	for i in range(0, verts.size(), 97):
		var v := verts[i]
		worst = maxf(worst, absf(v.y - VillageTerrain.sample_y(Vector2(v.x, v.z), _layout, _params, 0)))
	# Float32 vertex storage: ~1e-5 m; the removed lift was 0.05 m.
	assert_lte(worst, 1e-3, "far mesh y = field sample_y (no TERRAIN_BASE_LIFT), worst %.6f" % worst)
	assert_false((HillsHeightfield as GDScript).get_script_constant_map().has("TERRAIN_BASE_LIFT"),
		"TERRAIN_BASE_LIFT removed")


func test_shared_tint_include_and_cpu_mirror() -> void:
	## AR-LF-GAP-3: both shaders apply the same slope / height factors from one include.
	var inc := FileAccess.get_file_as_string("res://src/render/shaders/terrain_tint.gdshaderinc")
	assert_true(inc.contains("terrain_slope_dim") and inc.contains("terrain_height_factor"),
		"include defines both factors")
	assert_true(inc.contains("uniform float terrain_height_ref_y"), "include owns the height reference")
	for path in ["res://src/render/shaders/village_ground.gdshader",
			"res://src/render/shaders/village_ground_hills.gdshader"]:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src.contains("terrain_tint.gdshaderinc"), "%s includes terrain_tint" % path)
		assert_true(src.contains("terrain_height_factor(v_local_y)"), "%s applies the height factor" % path)
		assert_false(src.contains("uniform float terrain_slope_dark"), "%s has no private copy" % path)
	var hills := FileAccess.get_file_as_string("res://src/render/shaders/village_ground_hills.gdshader")
	assert_true(hills.contains("u_lawn_colour * terrain_slope_dim"),
		"hills seam colour = u_lawn_colour × factors at r_j")
	# CPU mirror: flat ground at the reference height is factor 1; slopes and rises move it.
	var p := VillageTerrainParams.production()
	assert_almost_eq(VillageTerrain.terrain_tint_factor(1.0, 3.0, p, 3.0), 1.0, 1e-6, "flat at ref")
	var steep := VillageTerrain.terrain_tint_factor(cos(deg_to_rad(30.0)), 3.0, p, 3.0)
	assert_almost_eq(steep, 1.0 - p.ground_slope_dark, 1e-5, "full slope dim at ground_slope_full_deg")
	var high := VillageTerrain.terrain_tint_factor(1.0, 3.0 + p.ground_height_range_m, p, 3.0)
	assert_almost_eq(high, 1.0 + p.ground_height_tint, 1e-5, "height tint relative to the reference")


func test_lawn_and_hill_materials_get_the_same_tint_uniforms() -> void:
	var bd := (load("res://src/world/generated_village_backdrop.tscn") as PackedScene).instantiate()
	bd.set_village_seed(_SEED)
	add_child_autofree(bd)
	await get_tree().process_frame
	var lawn := bd.get_node("LawnTerrain") as MeshInstance3D
	var hill := bd.get_node("HillTerrain") as MeshInstance3D
	var lm := lawn.mesh.surface_get_material(0) as ShaderMaterial
	var hm := hill.mesh.surface_get_material(0) as ShaderMaterial
	for u in ["terrain_slope_dark", "terrain_slope_full_deg", "terrain_height_tint",
			"terrain_height_range_m", "terrain_height_ref_y"]:
		assert_eq(lm.get_shader_parameter(u), hm.get_shader_parameter(u), "uniform %s equal" % u)
	assert_almost_eq(float(lm.get_shader_parameter("terrain_height_ref_y")), bd.hero_datum_y(), 1e-5,
		"height tint referenced to y_hero")
