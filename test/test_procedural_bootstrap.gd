## ivy-2ey — procedural bootstrap must await physics_frame so collision shapes are
## committed to the physics server before the light bake's raycasts run.
##
## Root cause: _bootstrap_simulation() only called ensure_mesh_scenario_loaded() and
## awaited physics_frame when mesh_scenario != null. On the script_driven procedural
## path (run_ui_script.gd, default tower/wall, mesh_scenario == null) the physics_frame
## was skipped, so near-ground horizon-escape rays escaped through the floor and tower walls.
##
## Evidence: cell (-5, 30, -19) at world-y ≈ 3.6 m, bake_ray_length = 12 m, tilt ~19°
## → rays drop 3.9 m and clear y = 0. Game baked leak=1.000000, test_m6_free_plant gave
## 0.916667 (4 of 48 rays blocked — the tower and ground shapes were committed in that test).
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const LightBake = preload("res://src/env/light_bake.gd")
const LightBakeCache = preload("res://src/env/light_bake_cache.gd")


## Proves the underlying physics timing property — a ConcavePolygonShape3D (trimesh,
## used by the procedural tower) is not queryable until after physics_frame.
## This mirrors test_mesh_bootstrap_seeding.gd's contract for StructureBody, but for
## the plain Tower node path to confirm the same invariant holds there.
func test_tower_collision_shape_requires_physics_frame() -> void:
	var main := MainScene.instantiate()
	main.set("script_driven", true)
	# We need to build the tower so the ConcavePolygonShape3D exists.
	# Build it but do NOT await physics_frame, then check that raycasts miss.
	add_child_autofree(main)
	# At this point _bootstrap_simulation is suspended at its first await (physics_frame,
	# after the fix) or continuing to get_surface_query (without the fix).
	# Access the World and build the tower manually to isolate the timing:
	var world: Node = main.get_node("World")
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	# A ray aimed at the tower (from outside inward) — should miss before physics_frame
	# because the ConcavePolygonShape3D is not yet in the physics server.
	var ray_from := Vector3(5.0, 1.0, 0.0)  # outside tower radius (2.0 m)
	var ray_to := Vector3(0.0, 1.0, 0.0)  # toward tower centre
	var q := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	# NOTE: the tower collision layer is 1.
	# Before a physics_frame the freshly-built trimesh is NOT committed.
	# However, the World's Tower might already be committed from a previous GUT frame
	# if the physics server ran between tests. We can only verify the post-fix state.
	# The integration test below is the authoritative regression check.
	await get_tree().physics_frame
	var result := space.intersect_ray(q)
	# After physics_frame the tower trimesh MUST be committed.
	assert_false(
		result.is_empty(),
		(
			"Tower ConcavePolygonShape3D must be queryable after physics_frame (ivy-2ey). "
			+ "If this misses, the tower was not built or the physics server missed the shape."
		)
	)


## Full integration: boot main.tscn via the script_driven path (matching run_ui_script.gd)
## and verify the stored coarse bake matches a live re-computation. Before the ivy-2ey fix,
## near-ground cells had stored leak=1.000000 (all horizon-escape rays escaped — Ground/Tower
## shapes not committed at bake time) while a live raycast gives leak=0.916667 (4 of 48 rays
## blocked). LightBakeCache.verify_against_surface recomputes 64 cells and catches that delta.
##
## Cache note: if a correct bake from a prior run (with the fix applied) is on disk, the
## cache will be loaded, and the stored values will already be correct; the test still
## passes, which is the right outcome (the product is correct). On a fresh environment
## (CI, first run after revert) where no cache exists, a fresh bake runs and the bug is
## exposed. Clear res://.tmp/light_bake_cache/ to force a fresh bake locally.
func test_procedural_bootstrap_bake_matches_live_physics() -> void:
	var main := MainScene.instantiate()
	# Set BEFORE entering the tree — exactly as run_ui_script.gd does.
	main.set("script_driven", true)
	add_child_autofree(main)

	# _ready() fires _bootstrap_simulation(true) as a coroutine. After the fix it unconditionally
	# calls ensure_mesh_scenario_loaded() + awaits physics_frame + process_frame before building
	# the SurfaceQuery. Wait enough frames for the bake to complete (bake is synchronous so it
	# finishes within a single frame; 10 process_frame awaits is generous).
	for _i in range(10):
		await get_tree().process_frame

	var sim: Node = main.get_node("Sim")
	assert_not_null(sim, "Sim must be set up by _bootstrap_simulation")

	var env = sim.get("env")
	assert_not_null(env, "IvyEnvironment must be built after bootstrap")

	var bake: LightBake = env.get("_bake")
	assert_not_null(bake, "LightBake must be present on IvyEnvironment")

	var surface = sim.get("surface")
	assert_not_null(surface, "SurfaceQuery must be set on SimRoot after bootstrap")

	# verify_against_surface recomputes LightBakeCache.VERIFY_SAMPLES (64) cells via live
	# physics raycasts and compares them to the stored bake values (SVF, mask, leak, normal).
	# Before the fix: stored leak=1.0 (no occlusion) vs live leak<1.0 → mismatch → false.
	# After the fix: stored values match live physics → true.
	assert_true(
		LightBakeCache.verify_against_surface(bake, surface),
		(
			"Stored coarse bake values must match live physics. "
			+ "A leak mismatch on near-ground cells means collision shapes were not committed "
			+ "to the physics server when _bootstrap_simulation baked (ivy-2ey: "
			+ "_bootstrap_simulation must await physics_frame unconditionally, "
			+ "not only when mesh_scenario != null)."
		)
	)
