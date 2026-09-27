extends Node3D

## W-097 / W-094 — headless probe for phase-A light-bake wall-clock time.
##
## Reports the cold ray bake against the warm `LightBakeCache` load for the same building, which
## is the comparison that matters since ivy-9xp made every backend cacheable.
##
## Run:
##   godot --headless res://tools/measure_light_bake.tscn
##   godot --headless res://tools/measure_light_bake.tscn -- --scenario=res://assets/structures/scenarios/square.tres
##   godot --headless res://tools/measure_light_bake.tscn -- --building=test_wall
##   godot --headless res://tools/measure_light_bake.tscn -- --building=cylinder

const StructureScenario = preload("res://src/world/structure_scenario.gd")
const StructureBody = preload("res://src/world/structure_body.gd")
const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const IvyEnvironment = preload("res://src/env/environment.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const LightBake = preload("res://src/env/light_bake.gd")
const LightBakeCache = preload("res://src/env/light_bake_cache.gd")
const Solar = preload("res://src/env/solar.gd")
const Tower = preload("res://src/world/tower.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const Wall = preload("res://src/world/wall.gd")
const WallSdf = preload("res://src/world/wall_sdf.gd")
const WallSpec = preload("res://src/world/wall_spec.gd")

const DEFAULT_SCENARIO := "res://assets/structures/scenarios/square.tres"
const WALL_SPEC := "res://src/world/wall_spec_default.tres"


func _ready() -> void:
	var params := IvyParams.new()
	var building := _parse_arg("--building=", "")
	var label := building
	var surface: SurfaceQuery
	if building.is_empty():
		label = _parse_arg("--scenario=", DEFAULT_SCENARIO).get_file().get_basename()
		surface = await _mesh_surface(params)
	else:
		surface = await _procedural_surface(building, params)
	if surface == null:
		get_tree().quit(2)
		return

	var bounds := surface.shell_bounds(params.field_shell_halfwidth + params.field_cell)
	var identity := surface.bake_identity()
	var ph := LightBakeCache.params_hash(params)
	# Measure the cold path even when an entry is already on disk, so repeated runs stay
	# comparable instead of silently reporting a hit as a bake.
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(LightBakeCache.cache_path(identity, ph))
	)

	# AR-BUDGET / W-097 gate: coarse-grid ray bake (_bake.bake), the load stall.
	var bake := LightBake.new(params, Solar.new(params))
	var t0 := Time.get_ticks_usec()
	bake.bake(surface, bounds)
	var ray_bake_sec := float(Time.get_ticks_usec() - t0) / 1e6

	LightBakeCache.save(bake, bounds, identity, ph)

	# What every subsequent load now costs instead: read the file, then recompute a sample of
	# cells to prove it belongs to this build.
	var warm := LightBake.new(params, Solar.new(params))
	t0 = Time.get_ticks_usec()
	var hit := LightBakeCache.try_load(warm, bounds, identity, ph)
	var load_sec := float(Time.get_ticks_usec() - t0) / 1e6
	t0 = Time.get_ticks_usec()
	var verified := LightBakeCache.verify_against_surface(warm, surface)
	var verify_sec := float(Time.get_ticks_usec() - t0) / 1e6

	# The load stall players and tests actually wait on is the whole `IvyEnvironment.build()`:
	# allocate, coarse bake (cached or not), fine-grid fill, warm-up. Reported alongside the
	# bake phase so it stays obvious how much of the stall the cache can and cannot remove.
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(LightBakeCache.cache_path(identity, ph))
	)
	var cold_env := IvyEnvironment.new()
	t0 = Time.get_ticks_usec()
	cold_env.build(params, surface, Solar.new(params))
	var cold_build_sec := float(Time.get_ticks_usec() - t0) / 1e6
	var warm_env := IvyEnvironment.new()
	t0 = Time.get_ticks_usec()
	warm_env.build(params, surface, Solar.new(params))
	var warm_build_sec := float(Time.get_ticks_usec() - t0) / 1e6

	print("[measure_light_bake] building=", label)
	print("[measure_light_bake] backend=", surface.backend_tag())
	print("[measure_light_bake] coarse_cells=", bake.coarse_count())
	print("[measure_light_bake] ray_bake_sec=", "%.3f" % ray_bake_sec)
	print("[measure_light_bake] w097_trigger=", ray_bake_sec > 3.0)
	print("[measure_light_bake] cache_hit=", hit, " verified=", verified)
	print("[measure_light_bake] cache_load_sec=", "%.3f" % load_sec)
	print("[measure_light_bake] cache_verify_sec=", "%.3f" % verify_sec)
	print(
		"[measure_light_bake] bake_phase_speedup=",
		"%.1fx" % (ray_bake_sec / maxf(1e-6, load_sec + verify_sec))
	)
	print("[measure_light_bake] env_build_cold_sec=", "%.3f" % cold_build_sec)
	print("[measure_light_bake] env_build_warm_sec=", "%.3f" % warm_build_sec)
	print(
		"[measure_light_bake] env_build_speedup=",
		"%.2fx" % (cold_build_sec / maxf(1e-6, warm_build_sec))
	)
	print(
		"[measure_light_bake] residual_warm_stall_sec=",
		"%.3f" % (warm_build_sec - load_sec - verify_sec),
		" (allocate + fill_field + warm_up: not cached)"
	)
	get_tree().quit(0)


func _mesh_surface(params: IvyParams) -> SurfaceQuery:
	var scenario_path := _parse_arg("--scenario=", DEFAULT_SCENARIO)
	var scenario: StructureScenario = load(scenario_path) as StructureScenario
	if scenario == null:
		printerr("[measure_light_bake] failed to load ", scenario_path)
		return null
	for err in scenario.validate():
		printerr("[measure_light_bake] scenario invalid: ", err)
		return null

	var body := StructureBody.new()
	add_child(body)
	body.build(scenario.collision_glb, "")
	await get_tree().physics_frame

	var sdf := MeshSdf.new()
	sdf.load_from_file(scenario.sdf_path)
	if not sdf.verify_provenance(scenario.collision_glb):
		printerr("[measure_light_bake] SDF provenance mismatch")
		return null

	var surface := SurfaceQuery.new()
	surface.setup(
		body.get_world_3d().direct_space_state,
		body,
		sdf,
		body.face_material,
		params
	)
	return surface


## Procedural buildings need their collision geometry built here too: the bake's occlusion rays
## go through the physics space, so a body-less surface would measure a world with no occluders.
func _procedural_surface(building: String, params: IvyParams) -> SurfaceQuery:
	var surface := SurfaceQuery.new()
	if building == "test_wall":
		var spec := load(WALL_SPEC) as WallSpec
		var wall := Wall.new()
		add_child(wall)
		wall.build_from_spec(spec, false)
		await get_tree().physics_frame
		surface.setup(
			wall.get_world_3d().direct_space_state,
			wall,
			WallSdf.new(spec),
			wall.face_material,
			params
		)
		return surface
	if building == "cylinder":
		var spec := TowerSpec.new()
		var tower := Tower.new()
		add_child(tower)
		tower.build_from_spec(spec, false)
		await get_tree().physics_frame
		surface.setup(
			tower.get_world_3d().direct_space_state,
			tower,
			TowerSdf.new(spec),
			tower.face_material,
			params
		)
		return surface
	printerr("[measure_light_bake] unknown building ", building, "; expected test_wall or cylinder")
	return null


func _parse_arg(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
