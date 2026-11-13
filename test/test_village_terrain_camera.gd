## AC-VT11 — CameraBounds floor_y arg; eye never below terrain floor.
## WP7: ivy-82zn.4.7
extends GutTest

const CameraBounds = preload("res://src/world/camera_bounds.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")
const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")


# ── Test 1: clamp_free_camera_eye accepts floor_y and applies it ──────────────

func test_clamp_free_camera_eye_applies_floor_y() -> void:
	# Eye below floor_y → should be raised to floor_y (before existing clamps)
	var centre := Vector2.ZERO
	var radius := 20.0
	var margin := 2.0
	var floor_y := 1.5
	var eye_below_floor := Vector3(5.0, 0.2, 5.0)
	var result: Vector3 = CameraBounds.clamp_free_camera_eye(
		eye_below_floor, centre, radius, margin, floor_y)
	assert_gte(result.y, floor_y - 1e-4,
		"eye.y must be raised to floor_y when eye is below floor")


func test_clamp_free_camera_eye_floor_y_does_not_lower_eye() -> void:
	# Eye already above floor_y → floor_y should not lower it
	var centre := Vector2.ZERO
	var radius := 20.0
	var margin := 2.0
	var floor_y := 0.5
	var eye_above_floor := Vector3(5.0, 3.0, 5.0)
	var result: Vector3 = CameraBounds.clamp_free_camera_eye(
		eye_above_floor, centre, radius, margin, floor_y)
	assert_gte(result.y, floor_y - 1e-4,
		"eye.y above floor must not be changed by floor_y")
	assert_gte(result.y, eye_above_floor.y - 1e-4,
		"eye.y should not be lowered when already above floor")


func test_clamp_free_camera_eye_default_no_floor() -> void:
	# Without floor_y argument, existing behavior preserved: eye clamped to [0.05, 120]
	var centre := Vector2.ZERO
	var radius := 20.0
	var margin := 2.0
	# Call with 4 args (no floor_y) — existing signature must still work
	var eye := Vector3(5.0, 0.5, 5.0)
	var result: Vector3 = CameraBounds.clamp_free_camera_eye(eye, centre, radius, margin)
	# y should be at least 0.05 (existing MIN)
	assert_gte(result.y, 0.05 - 1e-4, "existing 0.05 floor must be preserved")


func test_clamp_free_camera_eye_floor_y_minus_inf_same_as_no_arg() -> void:
	# Explicitly passing -INF should behave the same as no floor_y
	var centre := Vector2.ZERO
	var radius := 20.0
	var margin := 2.0
	var eye := Vector3(3.0, 2.0, 3.0)
	var r_default: Vector3 = CameraBounds.clamp_free_camera_eye(eye, centre, radius, margin)
	var r_inf: Vector3 = CameraBounds.clamp_free_camera_eye(eye, centre, radius, margin, -INF)
	assert_almost_eq(r_default.y, r_inf.y, 1e-6,
		"floor_y=-INF must match no-floor-arg result")


func test_backdrop_world_xz_matches_layout_local_after_offset() -> void:
	var bd := GeneratedBackdropScene.instantiate() as GeneratedVillageBackdrop
	bd.set_village_seed(7)
	bd.global_position = Vector3(-7.0, 0.0, 3.5)
	add_child_autofree(bd)
	await get_tree().process_frame
	var layout: VillageLayout = bd.get("_layout")
	var params: VillageTerrainParams = bd.get("_terrain_params")
	var t_seed: int = bd.get("_terrain_seed")
	var local_xz := layout.hamlet_centre_xz + Vector2(4.0, -2.0)
	var expected := VillageTerrain.sample_y(local_xz, layout, params, t_seed)
	var origin := Vector2(bd.global_position.x, bd.global_position.z)
	var world_xz := local_xz + origin
	var via_world := bd.sample_terrain_y(world_xz - origin)
	assert_almost_eq(expected, via_world, 1e-4,
		"layout-local sample must match world XZ minus backdrop origin")


func test_clamp_free_camera_eye_floor_y_on_flat_terrain_unchanged() -> void:
	# On flat terrain (sample_y=0), floor_y=0+clearance=0.35
	# Eye at y=1.0 > 0.35 → no change (XZ clamp may move eye)
	var centre := Vector2.ZERO
	var radius := 20.0
	var margin := 2.0
	var floor_y := 0.35  # clearance on flat terrain
	var eye := Vector3(5.0, 1.0, 5.0)
	var result: Vector3 = CameraBounds.clamp_free_camera_eye(eye, centre, radius, margin, floor_y)
	assert_gte(result.y, floor_y - 1e-4,
		"eye above flat-terrain floor must remain above it")
