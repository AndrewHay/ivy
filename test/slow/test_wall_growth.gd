## T5 — procedural wall ivy growth from midpoint seed fallback.
extends GutTest

const Wall = preload("res://src/world/wall.gd")
const WallSpec = preload("res://src/world/wall_spec.gd")
const WallSdf = preload("res://src/world/wall_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const Conv = preload("res://src/core/conv.gd")

const TICKS_PER_DAY := 24
const GAME_DAYS := 30


func _make_wall_sim() -> SimRoot:
	var wall := Wall.new()
	add_child_autofree(wall)
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	wall.build_from_spec(spec, true)
	var sq := SurfaceQuery.new()
	sq.setup(
		wall.get_world_3d().direct_space_state,
		wall,
		WallSdf.new(spec),
		wall.face_material,
		IvyParams.new()
	)
	var sim := SimRoot.new()
	sim.setup(IvyParams.new(), sq, null, 0, null, true)
	return sim


func test_wall_growth_from_midpoint_seed() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var sim := await _make_wall_sim()
	await get_tree().physics_frame
	sim.advance_ticks(TICKS_PER_DAY * GAME_DAYS)
	assert_gt(sim.plant.total_length, 0.0, "expected growth on procedural wall")
	assert_gt(sim.tips.tips.size(), 0)
	var seeded := sim.tips.tips[0]
	assert_gt(seeded.last_contact_normal.dot(Conv.SOUTH), 0.9)
	var on_sun_side := false
	for tip in sim.tips.tips:
		if tip.is_live() and tip.position.z > -spec.thickness:
			on_sun_side = true
			break
	assert_true(on_sun_side, "at least one live tip should remain on the sun-facing side")
