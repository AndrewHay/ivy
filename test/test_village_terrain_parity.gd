## ivy-82zn.14.14 (WP1) — AC-LT-DET: same seed ⇒ identical sample_y grid hash (4 m grid, r ≤ 310 m)
## and identical chosen offset; two runs equal; game (GeneratedVillageBackdrop) vs playground
## (VillageLayout.generate(seed, params)) equal, including the far mesh on the join loop (G7 pin).
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsParams = preload("res://src/playground/hills_params.gd")
const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")

const _SEEDS: Array[int] = [1, 7, 12]


static func _grid_hash(f, g: Vector2, step: float = 4.0, r_max: float = 310.0) -> String:
	var parts := PackedFloat32Array()
	var n := int(r_max / step)
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var q := Vector2(float(ix), float(iz)) * step
			if q.length() <= r_max:
				parts.append(f.sample_y(g + q))
	return parts.to_byte_array().hex_encode().sha256_text()


func test_two_runs_identical() -> void:
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var a := VillageLayout.generate(seed)
		var b := VillageLayout.generate(seed)
		assert_eq(a.landform["offset"], b.landform["offset"], "seed %d chosen offset" % seed)
		assert_eq(a.landform["index"], b.landform["index"], "seed %d chosen candidate" % seed)
		var ha := _grid_hash(VillageTerrain.field(a, p), a.hamlet_centre_xz)
		var hb := _grid_hash(VillageTerrain.field(b, p), b.hamlet_centre_xz)
		assert_eq(ha, hb, "seed %d sample_y grid hash" % seed)


func test_playground_path_matches_production_path() -> void:
	## The playground generates with its own (production-default) params resource.
	for seed in _SEEDS:
		var game := VillageLayout.generate(seed)
		var play := VillageLayout.generate(seed, VillageTerrainParams.production())
		assert_eq(game.landform["offset"], play.landform["offset"], "seed %d offset" % seed)
		var hg := _grid_hash(VillageTerrain.field(game, VillageTerrainParams.production()),
			game.hamlet_centre_xz, 8.0)
		var hp := _grid_hash(VillageTerrain.field(play, play.terrain_params), play.hamlet_centre_xz, 8.0)
		assert_eq(hg, hp, "seed %d field hash game vs playground" % seed)


func test_game_backdrop_field_and_far_mesh_match() -> void:
	var seed := 7
	var bd := GeneratedBackdropScene.instantiate() as GeneratedVillageBackdrop
	bd.set_village_seed(seed)
	add_child_autofree(bd)
	await get_tree().process_frame
	var play := VillageLayout.generate(seed, VillageTerrainParams.production())
	var fg = bd.terrain_field()
	var fp = VillageTerrain.field(play, play.terrain_params)
	assert_not_null(fg, "game field")
	assert_eq(_grid_hash(fg, bd.get_layout().hamlet_centre_xz, 8.0), _grid_hash(fp, play.hamlet_centre_xz, 8.0),
		"game backdrop field == playground field")
	# Far mesh vertex hash on the join loop.
	var hill := bd.get_node("HillTerrain") as MeshInstance3D
	var verts: PackedVector3Array = hill.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var far_p := HillsHeightfield.build_mesh(play, HillsParams.production())
	var verts_p: PackedVector3Array = far_p.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var loop := VillageTerrain.join_loop(play, play.terrain_params)
	assert_eq(verts.size(), verts_p.size(), "far mesh vertex count")
	var a := PackedFloat32Array()
	var b := PackedFloat32Array()
	for i in range(loop.size()):
		a.append(verts[i].y)
		b.append(verts_p[i].y)
	assert_eq(a.to_byte_array().hex_encode(), b.to_byte_array().hex_encode(), "far mesh join-loop y hash")


func test_salts() -> void:
	assert_eq(VillageLayout.VILLAGE_TERRAIN_SALT, 0x7E44A1, "detail salt unchanged")
	assert_eq(VillageLayout.VILLAGE_LANDFORM_SALT, 0x7E44A2, "landform salt")


func test_terrain_seed_differs_between_seeds() -> void:
	var p := VillageTerrainParams.production()
	assert_ne(VillageTerrain.terrain_seed(VillageLayout.generate(1), p),
		VillageTerrain.terrain_seed(VillageLayout.generate(7), p), "seed 1 vs 7")
