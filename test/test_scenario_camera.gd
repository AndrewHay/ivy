## W-090 — per-scenario CameraRig framing for mesh structures (AR-SCENE-3 safe).
##
## Canonical camera *local* transforms stay authored in main.tscn; only the rig
## translates so the same fixtures frame each structure's pivot.
extends GutTest

const StructureScenarioScript = preload("res://src/world/structure_scenario.gd")
const MeshSdfScript = preload("res://src/world/mesh_sdf.gd")
const SimRootScript = preload("res://src/sim/sim_root.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")

const _FOV_DEG := 75.0
const _CAM_SUN_T := Transform3D(
		Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0, 2, 8))


static func _cam_fwd(t: Transform3D) -> Vector3:
	return -t.basis.z


static func _global_cam_transform(rig_pos: Vector3, local: Transform3D) -> Transform3D:
	return Transform3D(local.basis, local.origin + rig_pos)


func test_resolve_camera_pivot_uses_explicit_export() -> void:
	var scenario := StructureScenarioScript.new()
	scenario.camera_pivot = Vector3(-7.0, 1.56, 0.0)
	assert_eq(scenario.resolve_camera_pivot(), Vector3(-7.0, 1.56, 0.0))


func test_resolve_camera_pivot_falls_back_to_sdf_aabb_center() -> void:
	var scenario := StructureScenarioScript.new()
	scenario.sdf_path = "res://assets/structures/square_sim.sdf"
	var sdf := MeshSdfScript.new()
	sdf.load_from_file(scenario.sdf_path)
	var expected := sdf.mesh_aabb.get_center()
	assert_eq(scenario.resolve_camera_pivot(), expected)


func test_square_scenario_cam_sun_frames_building_center() -> void:
	var pivot := Vector3(-7.0, 1.56, 0.0)
	var rig_pos := Vector3(pivot.x, pivot.y - 2.0, pivot.z)
	var cam_global := _global_cam_transform(rig_pos, _CAM_SUN_T)
	var dot := _cam_fwd(cam_global).dot(pivot - cam_global.origin)
	assert_gt(dot, 0.0, "CamSun must look at square pivot (dot=%.4f)" % dot)
	assert_almost_eq(cam_global.origin.y, pivot.y, 0.01,
			"CamSun aim height must match building centre")


func test_world_positions_camera_rig_on_mesh_scenario_load() -> void:
	var main_ps := load("res://src/main/main.tscn") as PackedScene
	var main := main_ps.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	var scenario: Resource = load("res://assets/structures/scenarios/square.tres")
	var world: Node = main.get_node("World")
	world.set("mesh_scenario", scenario)
	world.call("ensure_mesh_scenario_loaded")
	await get_tree().process_frame
	var rig: Node3D = main.get_node("World/CameraRig")
	assert_almost_eq(rig.position.x, -7.0, 0.01)
	assert_almost_eq(rig.position.y, 1.56 - 2.0, 0.05)
	assert_almost_eq(rig.position.z, 0.0, 0.01)


func test_tower_path_keeps_camera_rig_at_origin() -> void:
	var main_ps := load("res://src/main/main.tscn") as PackedScene
	var main := main_ps.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	var rig: Node3D = main.get_node("World/CameraRig")
	assert_eq(rig.position, Vector3.ZERO)


func test_reseed_resets_simulation_and_applies_seed_index() -> void:
	var sim := SimRootScript.new()
	var params := IvyParams.new()
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var sq := SurfaceQuery.new()
	sq.setup(null, null, TowerSdf.new(spec), PackedByteArray(), params)
	var scenario := StructureScenarioScript.new()
	scenario.seed_positions = PackedVector3Array([Vector3(-9, 1.2, -4.5), Vector3(-2.5, 1.2, 0)])
	scenario.seed_normals = PackedVector3Array([Vector3(0, 0, 1), Vector3(-1, 0, 0)])
	scenario.sdf_path = "res://assets/structures/square_sim.sdf"
	scenario.camera_pivot = Vector3(-7, 1.56, 0)
	sim.setup(params, sq, scenario, 0)
	sim.advance_ticks(24)
	var len_after := sim.plant.total_length
	sim.set_seed_index(1)
	sim.reseed()
	assert_eq(sim.clock.tick_index, 0, "reseed must reset tick index")
	assert_eq(sim.tips.tips.size(), 1, "reseed must leave one seed tip")
	assert_lt(sim.plant.total_length, len_after, "reseed must clear prior growth")
