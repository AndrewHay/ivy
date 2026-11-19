## ivy-9bt7 — stems on a mesh growth surface stay outside the solid.
##
## Before the fix the MeshSdf post-placement snap left the tip exactly on the face. The next
## collision ray then started on the face plane, missed the one-sided face, and the stem grew on
## inside the solid: on the relief article the first crossing came at tick 27 and 1,194 followed
## within 3 game-days. This grows the sharp relief article (default IvyParams, anchors A1-A4) for
## half a game-day and checks every node against the analytic article. The 30-day check is the
## slow probe's D3/D4 (test/slow/test_relief_article_probe.gd).
extends GutTest

const Probe = preload("res://tools/relief_article_probe.gd")
const BuildingCatalog = preload("res://src/world/building_catalog.gd")
const StructureBody = preload("res://src/world/structure_body.gd")
const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const SimClock = preload("res://src/core/sim_clock.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")

const GAME_DAYS := 0.5
## Deeper than the collision skin plus float noise; a tunnelling stem passes this in one step.
const MAX_DEPTH := 0.003


func test_no_stem_node_ends_inside_the_relief_article() -> void:
	var scenario = BuildingCatalog.scenario_for("relief_article")
	assert_not_null(scenario, "relief_article scenario")
	var body := StructureBody.new()
	add_child(body)
	body.build(scenario.collision_glb, "")
	await get_tree().physics_frame
	var sdf := MeshSdf.new()
	sdf.load_from_file(scenario.sdf_path)
	var params := IvyParams.new()
	var sq := SurfaceQuery.new()
	sq.setup(body.get_world_3d().direct_space_state, body, sdf, body.face_material, params)
	var sim := SimRoot.new()
	sim.setup(params, sq, scenario, 0)
	sim.advance_ticks(SimClock.ticks_for_game_days(GAME_DAYS, SimClock.Speed.NORMAL))
	var plant: PlantData = sim.plant
	assert_gt(plant.seg_b.size(), 1000, "the plant grew enough to judge")
	var inside := 0
	var deepest := 0.0
	for p in plant.seg_b:
		var d: float = Probe.phi(p)
		if d < -MAX_DEPTH:
			inside += 1
		deepest = minf(deepest, d)
	assert_eq(inside, 0, "%d of %d segment ends are more than %.3f m inside the solid (deepest %.4f)" % [
		inside, plant.seg_b.size(), MAX_DEPTH, deepest])
	var tips_inside := 0
	for tip in sim.tips.tips:
		if Probe.phi(tip.position) < -MAX_DEPTH:
			tips_inside += 1
	assert_eq(tips_inside, 0, "no live tip is inside the solid")
	sim.free()
	remove_child(body)
	body.free()
