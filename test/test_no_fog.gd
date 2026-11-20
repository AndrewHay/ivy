## AR-NOFOG (ivy-82zn.14.32): the village has no fog at all, and the far edge the fog used to hide is
## closed by the far-mesh horizon skirt (AR-NOFOG-EDGE).
##
## 1. Game, classic and generated seeds 1 / 7 / 12, after SkySun.update() at noon and at twilight:
##    the live Environment has fog and volumetric fog off and no FogVolume node exists.
## 2. Village terrain playground at every camera preset; hills and forest playgrounds: same checks.
## 3. Source guard: no fog keyword in src/, scenes/, tools/, assets/shaders/.
## 4. Skirt: the far mesh reaches R_SKIRT_M, keeps the r_outer rim unchanged (field heights), eases
##    monotonically down to y_skirt = min(rim y) by r_outer + SKIRT_EASE_M, and does not lower the
##    terrain minimum.
## 5. Edge: World/Ground discard radius = R_SKIRT_M in generated mode, PlaneMesh 6000 x 6000 m,
##    village terrain playground camera far >= 4000 m.
## 6. Sky below the horizon is the far meadow colour (not the pale horizon) after SkySun.update().
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SquareScenario = preload("res://assets/structures/scenarios/square.tres")
const GameModes = preload("res://src/world/game_modes.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsTint = preload("res://src/playground/hills_tint.gd")
const VillageTerrainPlaygroundScene = preload("res://scenes/playground/village_terrain_playground.tscn")
const HillsPlaygroundScene = preload("res://scenes/playground/hills_playground.tscn")
const ForestPlaygroundScene = preload("res://scenes/playground/forest_playground.tscn")

const _SEEDS: Array[int] = [1, 7, 12]
const _GUARD_ROOTS: Array[String] = ["res://src", "res://scenes", "res://tools", "res://assets/shaders"]
const _GUARD_EXT: Array[String] = ["gd", "tscn", "tres", "gdshader", "gdshaderinc", "txt"]
const _GUARD_WORDS: Array[String] = [
	"FogVolume", "fog_enabled = true", "volumetric_fog_enabled = true", "HeroFog", "WorldFog",
	"HillsFogTint", "u_horizon_rgb", "fog_begin", "fog_end",
]
## Large seconds_per_game_day so SkySun renders the instantaneous sun (render blend 1).
const _SPD := 86400.0


# ── Helpers ───────────────────────────────────────────────────────────────────

func _count_fog_volumes(n: Node) -> int:
	var c := 1 if n is FogVolume else 0
	for ch in n.get_children():
		c += _count_fog_volumes(ch)
	return c


func _world_environments(n: Node, out: Array[Environment]) -> void:
	if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
		out.append((n as WorldEnvironment).environment)
	for ch in n.get_children():
		_world_environments(ch, out)


func _assert_no_fog(where: String) -> void:
	var envs: Array[Environment] = []
	_world_environments(get_tree().root, envs)
	var w3d := get_tree().root.get_viewport().find_world_3d()
	if w3d != null and w3d.environment != null:
		envs.append(w3d.environment)
	assert_gt(envs.size(), 0, "%s: an Environment exists" % where)
	for e in envs:
		assert_false(e.fog_enabled, "%s: fog_enabled false" % where)
		assert_false(e.volumetric_fog_enabled, "%s: volumetric_fog_enabled false" % where)
	assert_eq(_count_fog_volumes(get_tree().root), 0, "%s: no FogVolume node" % where)


func _boot_main() -> Node:
	var main := MainScene.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", SquareScenario)
	add_child_autofree(main)
	for _i in range(30):
		await get_tree().process_frame
	return main


func _noon_and_twilight_days(sky: SkySun) -> Array[float]:
	## game_day 0 is params.start_hour (Solar.hour_of_day): noon and 15 min after sunrise.
	var start: float = sky.solar.params.start_hour
	var sunrise: float = sky.solar.sunrise_hour()
	return [(12.0 - start) / 24.0, (sunrise + 0.25 - start) / 24.0]


func _check_game_at_noon_and_twilight(world: Node, tag: String) -> void:
	var sky := world.get_node("SkySun") as SkySun
	await get_tree().process_frame
	_assert_no_fog("%s after build" % tag)
	for day in _noon_and_twilight_days(sky):
		sky.update(day, _SPD)
		await get_tree().process_frame
		_assert_no_fog("%s day=%.3f" % [tag, day])


# ── 1. Game ───────────────────────────────────────────────────────────────────

func test_game_classic_has_no_fog() -> void:
	var main: Node = await _boot_main()
	var world := main.get_node("World")
	world.call("set_village_mode", GameModes.CLASSIC, 0)
	world.call("rebuild_backdrop")
	await _check_game_at_noon_and_twilight(world, "classic")


func test_game_generated_seeds_have_no_fog() -> void:
	var main: Node = await _boot_main()
	var world := main.get_node("World")
	for seed in _SEEDS:
		world.call("set_village_mode", GameModes.GENERATED, seed)
		world.call("rebuild_backdrop")
		await _check_game_at_noon_and_twilight(world, "generated seed %d" % seed)


func test_game_round_trip_has_no_fog() -> void:
	var main: Node = await _boot_main()
	var world := main.get_node("World")
	for mode in [GameModes.GENERATED, GameModes.CLASSIC, GameModes.GENERATED]:
		world.call("set_village_mode", mode, 7)
		world.call("rebuild_backdrop")
		await get_tree().process_frame
		_assert_no_fog("round trip %s" % mode)


# ── 2. Playgrounds ────────────────────────────────────────────────────────────

func test_village_terrain_playground_every_preset_has_no_fog() -> void:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	for name in pg.CAMERA_PRESETS:
		pg._apply_camera_preset(name)
		await get_tree().process_frame
		_assert_no_fog("village terrain playground preset %s" % name)


func test_hills_playground_has_no_fog() -> void:
	var pg := HillsPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_no_fog("hills playground")


func test_forest_playground_has_no_fog() -> void:
	var pg := ForestPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_no_fog("forest playground")


# ── 3. Source guard ───────────────────────────────────────────────────────────

func _scan(dir_path: String, hits: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var p := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_scan(p, hits)
		elif name.get_extension() in _GUARD_EXT:
			var src := FileAccess.get_file_as_string(p)
			for w in _GUARD_WORDS:
				if src.contains(w):
					hits.append("%s: %s" % [p, w])
		name = d.get_next()
	d.list_dir_end()


func test_no_source_file_contains_fog_keywords() -> void:
	var hits: Array[String] = []
	for root in _GUARD_ROOTS:
		_scan(root, hits)
	assert_eq(hits.size(), 0, "fog keywords left:\n%s" % "\n".join(hits))


func test_deleted_fog_scripts_are_gone() -> void:
	for p in ["res://src/world/hero_fog.gd", "res://src/world/world_fog_params.gd",
			"res://src/world/world_fog_volume.gd", "res://assets/shaders/world_hero_fog.gdshader",
			"res://src/render/shaders/hill_pine.gdshader", "res://src/playground/hills_fog_tint.gd"]:
		assert_false(FileAccess.file_exists(p), "%s deleted" % p)
	assert_true(FileAccess.file_exists("res://src/playground/hills_tint.gd"), "HillsTint kept (renamed)")


# ── 4. Skirt ──────────────────────────────────────────────────────────────────

func _far_verts(layout: VillageLayout) -> PackedVector3Array:
	var mesh := VillageTerrain.build_far_mesh(layout, VillageTerrainParams.production())
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func test_skirt_reaches_r_skirt_and_keeps_the_rim() -> void:
	var hp := HillsParams.production()
	assert_almost_eq(VillageTerrain.R_SKIRT_M, 3000.0, 1e-6, "R_SKIRT_M")
	assert_almost_eq(VillageTerrain.SKIRT_EASE_M, 600.0, 1e-6, "SKIRT_EASE_M")
	for seed in _SEEDS:
		var layout := VillageLayout.generate(seed)
		var g := layout.hamlet_centre_xz
		var f = VillageTerrain.field(layout, VillageTerrainParams.production())
		var verts := _far_verts(layout)
		var max_r := 0.0
		var rim := {}  # azimuth bucket -> rim y
		var y_skirt := INF
		for v in verts:
			var d := Vector2(v.x, v.z) - g
			max_r = maxf(max_r, d.length())
			if absf(d.length() - hp.r_outer_m) < 1e-3:
				assert_almost_eq(v.y, float(f.sample_y(Vector2(v.x, v.z))), 1e-4,
					"seed %d rim vertex at field height" % seed)
				rim[_az_key(d)] = v.y
				y_skirt = minf(y_skirt, v.y)
		assert_gte(max_r, VillageTerrain.R_SKIRT_M - 1.0, "seed %d far mesh reaches R_SKIRT_M" % seed)
		assert_eq(rim.size(), VillageTerrain.FAR_AZ_SEGS, "seed %d full rim ring" % seed)
		# Skirt rings: y between y_skirt and the rim y on its azimuth, non-increasing outwards,
		# constant y_skirt past the ease band.
		var by_az := {}
		for v in verts:
			var d := Vector2(v.x, v.z) - g
			var r := d.length()
			if r <= hp.r_outer_m + 1e-3:
				continue
			var key := _az_key(d)
			assert_true(rim.has(key), "seed %d skirt vertex on a rim azimuth" % seed)
			if not rim.has(key):
				continue
			assert_lte(v.y, float(rim[key]) + 1e-4, "seed %d skirt below its rim" % seed)
			assert_gte(v.y, y_skirt - 1e-4, "seed %d skirt above y_skirt" % seed)
			if r >= hp.r_outer_m + VillageTerrain.SKIRT_EASE_M - 1e-3:
				assert_almost_eq(v.y, y_skirt, 1e-4, "seed %d skirt flat past the ease band" % seed)
			if not by_az.has(key):
				by_az[key] = []
			by_az[key].append(Vector2(r, v.y))
		for key in by_az:
			var pts: Array = by_az[key]
			pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
			var prev := float(rim[key])
			for p: Vector2 in pts:
				assert_lte(p.y, prev + 1e-4, "seed %d skirt non-increasing outwards" % seed)
				prev = p.y


func _az_key(d: Vector2) -> int:
	var a := fposmod(atan2(d.y, d.x), TAU)
	return int(round(a / TAU * float(VillageTerrain.FAR_AZ_SEGS))) % VillageTerrain.FAR_AZ_SEGS


func test_skirt_does_not_lower_the_terrain_minimum() -> void:
	var hp := HillsParams.production()
	for seed in _SEEDS:
		var layout := VillageLayout.generate(seed)
		var g := layout.hamlet_centre_xz
		var lo_all := INF
		var lo_inside := INF
		for v in _far_verts(layout):
			lo_all = minf(lo_all, v.y)
			if Vector2(v.x, v.z).distance_to(g) <= hp.r_outer_m + 1e-3:
				lo_inside = minf(lo_inside, v.y)
		assert_almost_eq(lo_all, lo_inside, 1e-6, "seed %d skirt adds no new minimum" % seed)
		var f = VillageTerrain.field(layout, VillageTerrainParams.production())
		assert_lte(float(f.terrain_min_y()), lo_inside + 1e-6, "seed %d terrain_min_y covers the far mesh" % seed)


# ── 5. Edge ───────────────────────────────────────────────────────────────────

func test_generated_ground_discard_is_r_skirt_and_plane_is_6000() -> void:
	var main: Node = await _boot_main()
	var world := main.get_node("World")
	world.call("set_village_mode", GameModes.GENERATED, 7)
	world.call("rebuild_backdrop")
	await get_tree().process_frame
	var gm := world.get_node("Ground/GroundMesh") as MeshInstance3D
	var mat := gm.get_surface_override_material(0) as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter("village_disc_radius")), VillageTerrain.R_SKIRT_M, 1e-4,
		"generated: World/Ground discarded inside R_SKIRT_M")
	var plane := gm.mesh as PlaneMesh
	assert_not_null(plane, "World/Ground is a PlaneMesh")
	if plane != null:
		assert_eq(plane.size, Vector2(6000.0, 6000.0), "World/Ground 6000 x 6000 m")


func test_village_terrain_playground_camera_far() -> void:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	var cam := pg.get_node("Camera3D") as Camera3D
	assert_gte(cam.far, 4000.0, "playground camera far >= 4000 m (sees the skirt)")


# ── 6. Sky below the horizon ──────────────────────────────────────────────────

## ivy-82zn.14.37 (review ivy-82zn.14.33 F1): the sky below the horizon must be lit with the exact
## u_sun_dir / u_twilight the HillTerrain material holds after SkySun.update (read from the material,
## not from Solar), so the flat skirt and the sky under it agree at noon as well as at dawn.
func test_sky_below_horizon_is_the_far_meadow_colour() -> void:
	var main: Node = await _boot_main()
	var world := main.get_node("World")
	world.call("set_village_mode", GameModes.GENERATED, 7)
	world.call("rebuild_backdrop")
	await get_tree().process_frame
	var hill := world.get_node_or_null("VillageBackdrop/HillTerrain") as MeshInstance3D
	assert_not_null(hill, "generated seed 7 has a HillTerrain far mesh")
	if hill == null:
		return
	var hill_mat := hill.mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(hill_mat, "HillTerrain has a ShaderMaterial")
	if hill_mat == null:
		return
	var sky := world.get_node("SkySun") as SkySun
	var env := (sky.get_node("WorldEnvironment") as WorldEnvironment).environment
	var mat := env.sky.sky_material as ShaderMaterial
	for day in _noon_and_twilight_days(sky):
		sky.update(day, _SPD)
		var sun_dir: Vector3 = hill_mat.get_shader_parameter("u_sun_dir")
		var tw: float = float(hill_mat.get_shader_parameter("u_twilight"))
		var want: Color = HillsTint.far_meadow_colour(sun_dir, tw)
		var got: Color = mat.get_shader_parameter("ground_horizon_color")
		assert_almost_eq(got.r, want.r, 1e-4, "day %.3f ground_horizon r" % day)
		assert_almost_eq(got.g, want.g, 1e-4, "day %.3f ground_horizon g" % day)
		assert_almost_eq(got.b, want.b, 1e-4, "day %.3f ground_horizon b" % day)
	assert_almost_eq(float(mat.get_shader_parameter("ground_energy")), 1.0, 1e-6, "ground energy 1")
