extends GutTest

const DebugCameraScript = preload("res://src/world/debug_camera.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")


func test_zoom_out_stays_inside_lawn_disc() -> void:
	var cam := DebugCameraScript.new()
	cam.script_driven = false
	add_child_autofree(cam)
	var spec := TowerSpec.new()
	cam.setup(spec)
	cam.set_lawn_camera_bounds(Vector2(-7.0, -18.0), 56.0, 2.0)
	for _i in range(300):
		cam._zoom_by_notches(-1.0)
		cam._enforce_lawn_orbit_bounds()
	var eye := cam.global_transform.origin
	assert_lte(
		Vector2(eye.x, eye.z).distance_to(Vector2(-7.0, -18.0)), 54.01,
		"max zoom-out eye must stay inside lawn minus margin")


## Left-click glide must survive the lawn clamp that runs right after it in _apply_orbit_view.
func test_click_glide_survives_lawn_clamp() -> void:
	var cam := DebugCameraScript.new()
	cam.script_driven = false
	add_child_autofree(cam)
	cam.setup(TowerSpec.new())
	cam.set_lawn_camera_bounds(Vector2.ZERO, 56.0, 2.0)
	var target := Vector3(6.0, 0.0, 4.0)
	cam._begin_glide_to(target)
	cam._apply_orbit_view()
	assert_true(cam._gliding, "glide not cancelled by the lawn clamp")
	cam._glide_elapsed = cam._glide_seconds
	cam._process(0.0)
	assert_almost_eq(cam._pivot().x, target.x, 1e-3)
	assert_almost_eq(cam._pivot().z, target.z, 1e-3)


func test_set_orbit_pivot_resets_home_origin() -> void:
	var cam := DebugCameraScript.new()
	cam.script_driven = false
	add_child_autofree(cam)
	cam.setup(TowerSpec.new())
	var p := Vector3(3.0, 1.0, -2.0)
	cam.set_orbit_pivot(p)
	assert_eq(cam._home_origin, p)
	assert_true(cam._has_home_origin)
	assert_eq(cam._pivot(), p)
