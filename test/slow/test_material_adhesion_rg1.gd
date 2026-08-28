## RG-1 — per-material stem-length spread on surface_wall after 60 game-days.
extends GutTest

const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const StructureBody = preload("res://src/world/structure_body.gd")
const StructureScenario = preload("res://src/world/structure_scenario.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const MaterialRegistry = preload("res://src/world/material_registry.gd")

const SURFACE_WALL_GLB := "res://assets/structures/surface_wall_sim.glb"
const SURFACE_WALL_SDF := "res://assets/structures/surface_wall_sim.sdf"
const TICKS_PER_DAY := 24
const GAME_DAYS := 60
const MIN_STEM_PER_MATERIAL := 0.05


func _make_surface_wall_sim(seed_index: int = 0) -> SimRoot:
	var body := StructureBody.new()
	add_child_autofree(body)
	body.build(SURFACE_WALL_GLB, "")
	await get_tree().physics_frame
	var sdf := MeshSdf.new()
	sdf.load_from_file(SURFACE_WALL_SDF)
	var sq := SurfaceQuery.new()
	sq.setup(
		body.get_world_3d().direct_space_state,
		body,
		sdf,
		body.face_material,
		IvyParams.new()
	)
	var scenario: StructureScenario = load(
		"res://assets/structures/scenarios/surface_wall.tres"
	) as StructureScenario
	var sim := SimRoot.new()
	sim.setup(IvyParams.new(), sq, scenario, seed_index)
	return sim


func test_rg1_stem_length_spread_surface_wall_60_days() -> void:
	if not FileAccess.file_exists(SURFACE_WALL_GLB):
		pending("surface_wall assets not built")
		return
	var sim := await _make_surface_wall_sim(0)
	sim.advance_ticks(TICKS_PER_DAY * GAME_DAYS)
	var lengths := {
		MaterialRegistry.BRICK_WALL: sim.plant.stem_length_for_material(MaterialRegistry.BRICK_WALL),
		MaterialRegistry.WOOD: sim.plant.stem_length_for_material(MaterialRegistry.WOOD),
		MaterialRegistry.GLASS: sim.plant.stem_length_for_material(MaterialRegistry.GLASS),
	}
	var eligible: Array[float] = []
	for mat in lengths:
		if lengths[mat] >= MIN_STEM_PER_MATERIAL:
			eligible.append(lengths[mat])
	assert_gte(sim.plant.total_length, 0.5,
		"expected growth on surface_wall; total=%.2f m" % sim.plant.total_length)
	assert_gte(eligible.size(), 2,
		"need ≥2 materials with measurable stem; lengths=%s total=%.2f"
		% [lengths, sim.plant.total_length])
	var hi: float = eligible[0]
	var lo: float = eligible[0]
	for v in eligible:
		hi = maxf(hi, v)
		lo = minf(lo, v)
	var spread_pct := (hi - lo) / hi * 100.0
	assert_gte(spread_pct, 15.0,
		"RG-1: stem spread should be ≥15%%; got %.1f%% (lengths=%s)"
		% [spread_pct, lengths])
