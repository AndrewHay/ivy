extends Node3D

## W-097 / W-094 — headless probe for phase-A light-bake wall-clock time.
##
## Run:
##   godot --headless res://tools/measure_light_bake.tscn
##   godot --headless res://tools/measure_light_bake.tscn -- --scenario=res://assets/structures/scenarios/square.tres

const StructureScenario = preload("res://src/world/structure_scenario.gd")
const StructureBody = preload("res://src/world/structure_body.gd")
const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const LightBake = preload("res://src/env/light_bake.gd")
const Solar = preload("res://src/env/solar.gd")

const DEFAULT_SCENARIO := "res://assets/structures/scenarios/square.tres"


func _ready() -> void:
	var scenario_path: String = _parse_scenario_arg()
	var scenario: StructureScenario = load(scenario_path) as StructureScenario
	if scenario == null:
		printerr("[measure_light_bake] failed to load ", scenario_path)
		get_tree().quit(2)
		return
	for err in scenario.validate():
		printerr("[measure_light_bake] scenario invalid: ", err)
		get_tree().quit(2)
		return

	var body := StructureBody.new()
	add_child(body)
	body.build(scenario.collision_glb, "")
	await get_tree().physics_frame

	var sdf := MeshSdf.new()
	sdf.load_from_file(scenario.sdf_path)
	if not sdf.verify_provenance(scenario.collision_glb):
		printerr("[measure_light_bake] SDF provenance mismatch")
		get_tree().quit(2)
		return

	var params := IvyParams.new()
	var surface := SurfaceQuery.new()
	surface.setup(
		body.get_world_3d().direct_space_state,
		body,
		sdf,
		body.face_material,
		params
	)
	var bounds := surface.shell_bounds(params.field_shell_halfwidth + params.field_cell)

	# AR-BUDGET / W-097 gate: coarse-grid ray bake (_bake.bake), the load stall.
	var bake := LightBake.new(params, Solar.new(params))
	var t0 := Time.get_ticks_usec()
	bake.bake(surface, bounds)
	var ray_bake_sec := float(Time.get_ticks_usec() - t0) / 1e6

	print("[measure_light_bake] scenario=", scenario.scenario_id)
	print("[measure_light_bake] coarse_cells=", bake.coarse_count())
	print("[measure_light_bake] ray_bake_sec=", "%.3f" % ray_bake_sec)
	print("[measure_light_bake] w097_trigger=", ray_bake_sec > 3.0)
	get_tree().quit(0)


func _parse_scenario_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			return arg.substr("--scenario=".length())
	return DEFAULT_SCENARIO
