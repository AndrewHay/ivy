## SG-3 / SG-5 — mesh scenario seed anchoring on collision geometry.
extends GutTest

const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const StructureBody = preload("res://src/world/structure_body.gd")
const StructureScenario = preload("res://src/world/structure_scenario.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")

const SQUARE_GLB := "res://assets/structures/square_sim.glb"
const SQUARE_SDF := "res://assets/structures/square_sim.sdf"
const ANCHOR_PHI_TOL := 0.40  # mesh SDF at h=0.05; tip is 0.01 m proud of raycast hit


func _make_square_sim(scenario: StructureScenario, seed_index: int = 0) -> SimRoot:
	var body := StructureBody.new()
	add_child_autofree(body)
	body.build(SQUARE_GLB, "")
	await get_tree().physics_frame
	var sdf := MeshSdf.new()
	sdf.load_from_file(SQUARE_SDF)
	assert_true(sdf.verify_provenance(SQUARE_GLB))
	var sq := SurfaceQuery.new()
	sq.setup(
		body.get_world_3d().direct_space_state,
		body,
		sdf,
		body.face_material,
		IvyParams.new()
	)
	var sim := SimRoot.new()
	sim.setup(IvyParams.new(), sq, scenario, seed_index)
	return sim


func test_seed_scenario_anchor_on_south_wall() -> void:
	var scenario: StructureScenario = load(
		"res://assets/structures/scenarios/square.tres"
	) as StructureScenario
	var sim := await _make_square_sim(scenario, 0)
	assert_eq(sim.tips.tips.size(), 2, "setup must plant every authored scenario seed")
	var tip = sim.tips.tips[0]
	var sdf := MeshSdf.new()
	sdf.load_from_file(SQUARE_SDF)
	var phi: float = sdf.signed_distance(tip.position)
	assert_lte(absf(phi), ANCHOR_PHI_TOL,
		"seed tip must sit on SDF surface (|Φ| ≤ %.2f); got Φ=%.4f at %s"
		% [ANCHOR_PHI_TOL, phi, tip.position])
	assert_gt(phi, -0.01, "seed tip must not be inside solid")
	assert_gt(tip.last_contact_normal.dot(Vector3(0, 0, -1)), 0.85,
		"south exterior normal expected")
	assert_lte(absf(tip.position.z - (-3.0)), 0.15,
		"tip should anchor on south face (z≈-3.0, got z=%.3f)" % tip.position.z)
	assert_gt(tip.position.x, -10.0)
	assert_lt(tip.position.x, -8.0, "seed 0 must land on west south wall segment, not door gap")


func test_seed_scenario_east_wall_seed1() -> void:
	var scenario: StructureScenario = load(
		"res://assets/structures/scenarios/square.tres"
	) as StructureScenario
	var sim := await _make_square_sim(scenario, 1)
	assert_eq(sim.tips.tips.size(), 2, "setup must plant every authored scenario seed")
	var tip = sim.tips.tips[1]
	var sdf := MeshSdf.new()
	sdf.load_from_file(SQUARE_SDF)
	var phi: float = sdf.signed_distance(tip.position)
	assert_lte(absf(phi), ANCHOR_PHI_TOL, "seed 1 |Φ| at anchor")
	assert_gt(phi, -0.01, "seed 1 must not be inside solid")
	assert_gt(tip.last_contact_normal.dot(Vector3(1, 0, 0)), 0.85,
		"east exterior normal expected")


## SG-3 regression (W-XXX): mesh scenario tips went FLOATING at tick ~205 (day ~8.5),
## accumulated float_len, and died from max_float by day 30. The growth direction on a
## flat mesh wall had a small outward-normal component that slowly pushed the tip beyond
## contact_distance, causing perpetual FLOATING and eventual death.
## Gate: ≥1 m stem length, tip not DEAD from max_float, at default params, seed 0.
func test_sg3_no_float_death_day30_seed0() -> void:
	var scenario: StructureScenario = load(
		"res://assets/structures/scenarios/square.tres"
	) as StructureScenario
	var sim := await _make_square_sim(scenario, 0)
	sim.advance_ticks(720)  # 30 days × 24 ticks/day
	var t0: Tip = sim.tips.tips[0]
	assert_ne(t0.state, Tip.State.DEAD,
		"tip-0 must not die from max_float by day 30 (SG-3); "
		+ "died with float_len=%.3f max_float=%.3f"
		% [t0.floating_length, sim.params.max_float])
	assert_gte(sim.plant.total_length, 1.0,
		"≥1 m stem required at day 30 (SG-3 gate); got %.3f m" % sim.plant.total_length)
