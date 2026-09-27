## ivy-hsu — mesh scenario seeds require a physics frame after collision build.
extends GutTest

const StructureBody = preload("res://src/world/structure_body.gd")
const StructureScenario = preload("res://src/world/structure_scenario.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")

const SQUARE_GLB := "res://assets/structures/square_sim.glb"
const SQUARE_SDF := "res://assets/structures/square_sim.sdf"


func _make_surface(body: StructureBody) -> SurfaceQuery:
	var sdf := MeshSdf.new()
	sdf.load_from_file(SQUARE_SDF)
	var sq := SurfaceQuery.new()
	sq.setup(
		body.get_world_3d().direct_space_state,
		body,
		sdf,
		body.face_material,
		IvyParams.new()
	)
	return sq


func _scenario_seed_ray(scenario: StructureScenario, index: int) -> Dictionary:
	var toward: Vector3 = scenario.seed_normals[index].normalized()
	var seed_pos: Vector3 = scenario.seed_positions[index]
	return {
		"from": seed_pos - toward * 3.0,
		"to": seed_pos + toward * 3.0,
	}


func test_collision_raycast_misses_same_frame_as_structure_build() -> void:
	var scenario: StructureScenario = load(
		"res://assets/structures/scenarios/square.tres"
	) as StructureScenario
	var body := StructureBody.new()
	add_child_autofree(body)
	body.build(SQUARE_GLB, "")
	var sq := _make_surface(body)
	for i in scenario.seed_positions.size():
		var ray := _scenario_seed_ray(scenario, i)
		var hit := sq.raycast(ray.from, ray.to)
		assert_false(
			hit.hit,
			"seed %d raycast must miss before physics_frame commits collision" % i
		)


func test_collision_raycast_hits_after_physics_frame() -> void:
	var scenario: StructureScenario = load(
		"res://assets/structures/scenarios/square.tres"
	) as StructureScenario
	var body := StructureBody.new()
	add_child_autofree(body)
	body.build(SQUARE_GLB, "")
	await get_tree().physics_frame
	var sq := _make_surface(body)
	for i in scenario.seed_positions.size():
		var ray := _scenario_seed_ray(scenario, i)
		var hit := sq.raycast(ray.from, ray.to)
		assert_true(
			hit.hit,
			"seed %d raycast must hit after physics_frame (pos=%s)"
			% [i, scenario.seed_positions[i]]
		)


func test_sim_root_plants_both_square_seeds_after_physics_frame() -> void:
	var scenario: StructureScenario = load(
		"res://assets/structures/scenarios/square.tres"
	) as StructureScenario
	var body := StructureBody.new()
	add_child_autofree(body)
	body.build(SQUARE_GLB, "")
	await get_tree().physics_frame
	var sim := SimRoot.new()
	sim.setup(IvyParams.new(), _make_surface(body), scenario, 0)
	assert_eq(sim.tips.tips.size(), 2, "both authored scenario seeds must anchor")
