## ivy-82zn.14.8: terrain playground camera uses the main game's DebugCamera control scheme
## (Tab mouse-look, left click glides the pivot to the terrain surface, wheel / trackpad zoom,
## WASD / arrows rotate, R / Home reset); presets set the orbit state; the UI panels shield the
## camera; the HUD names knobs beyond their gentle limits.
extends GutTest

const VillageTerrainPlaygroundScene = preload("res://scenes/playground/village_terrain_playground.tscn")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const DebugCamera = preload("res://src/world/debug_camera.gd")

const _IDLE_FRAME_CAP := 3000


func _make_pg() -> Node:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	pg.set("_grass_on", false)
	pg.set("_village_on", false)
	pg.set("_debounce_s", 0.02)
	add_child_autofree(pg)
	return pg


func _await_idle(pg: Node) -> bool:
	for _i in range(_IDLE_FRAME_CAP):
		if not pg.is_refining():
			return true
		await get_tree().process_frame
	return false


func _ready_pg() -> Node:
	var pg := _make_pg()
	await get_tree().process_frame
	assert_true(await _await_idle(pg), "initial build finishes")
	pg._allow_input = true
	return pg


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _mouse(button: MouseButton, pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = pos
	return ev


func _cam(pg: Node) -> Camera3D:
	return pg.get_node("Camera3D") as Camera3D


func _screen_centre(pg: Node) -> Vector2:
	return pg.get_viewport().get_visible_rect().size * 0.5


func test_tab_toggles_mouse_look() -> void:
	var pg: Node = await _ready_pg()
	assert_false(pg._mouse_orbit, "mouse-look starts off")
	pg._input(_key(KEY_TAB))
	assert_true(pg._mouse_orbit, "Tab turns mouse-look on")
	var yaw: float = pg._orbit_yaw
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(40.0, 0.0)
	pg._unhandled_input(mm)
	assert_ne(pg._orbit_yaw, yaw, "mouse motion orbits while mouse-look is on")
	pg._input(_key(KEY_TAB))
	assert_false(pg._mouse_orbit, "Tab turns mouse-look off")


func test_wheel_and_trackpad_zoom() -> void:
	var pg: Node = await _ready_pg()
	var pos := _screen_centre(pg)
	var r0: float = pg._orbit_radius
	pg._unhandled_input(_mouse(MOUSE_BUTTON_WHEEL_UP, pos))
	assert_lt(pg._orbit_radius, r0, "wheel up zooms in")
	var r1: float = pg._orbit_radius
	pg._unhandled_input(_mouse(MOUSE_BUTTON_WHEEL_DOWN, pos))
	pg._unhandled_input(_mouse(MOUSE_BUTTON_WHEEL_DOWN, pos))
	assert_gt(pg._orbit_radius, r1, "wheel down zooms out")
	var pan := InputEventPanGesture.new()
	pan.position = pos
	pan.delta = Vector2(0.0, -2.0)
	var r2: float = pg._orbit_radius
	pg._unhandled_input(pan)
	assert_lt(pg._orbit_radius, r2, "trackpad two-finger scroll zooms")
	assert_eq(_cam(pg).global_transform,
		DebugCamera.solve(pg._current_pivot(), pg._orbit_yaw, pg._orbit_pitch, pg._orbit_radius),
		"camera follows the orbit state")


func test_wasd_arrows_rotate_and_r_home_reset() -> void:
	var pg: Node = await _ready_pg()
	pg._apply_camera_preset("hero_approach")
	var yaw0: float = pg._orbit_yaw
	var pitch0: float = pg._orbit_pitch
	var xf0 := _cam(pg).global_transform
	pg._unhandled_input(_key(KEY_A))
	assert_almost_eq(pg._orbit_yaw, yaw0 - deg_to_rad(3.0), 1e-5, "A yaws")
	pg._unhandled_input(_key(KEY_RIGHT))
	pg._unhandled_input(_key(KEY_D))
	assert_almost_eq(pg._orbit_yaw, yaw0 + deg_to_rad(3.0), 1e-5, "Right / D yaw back")
	pg._unhandled_input(_key(KEY_W))
	assert_gt(pg._orbit_pitch, pitch0, "W pitches up")
	pg._unhandled_input(_key(KEY_DOWN))
	pg._unhandled_input(_key(KEY_S))
	assert_lt(pg._orbit_pitch, pitch0 + 1e-6, "Down / S pitch down")
	pg._unhandled_input(_key(KEY_R))
	assert_almost_eq(pg._orbit_yaw, yaw0, 1e-5, "R resets yaw")
	assert_almost_eq(pg._orbit_pitch, pitch0, 1e-5, "R resets pitch")
	assert_true(_cam(pg).global_transform.origin.distance_to(xf0.origin) < 1e-3, "R restores the preset view")
	pg._unhandled_input(_key(KEY_LEFT))
	pg._unhandled_input(_key(KEY_HOME))
	assert_almost_eq(pg._orbit_yaw, yaw0, 1e-5, "Home resets too")


func test_presets_set_the_orbit_state_without_a_jump() -> void:
	var pg: Node = await _ready_pg()
	for name in ["camsun", "raking", "hero_approach", "pond_oblique", "edge_inward", "edge_outward", "orbit"]:
		pg._apply_camera_preset(name)
		var xf := _cam(pg).global_transform
		var solved := DebugCamera.solve(pg._current_pivot(), pg._orbit_yaw, pg._orbit_pitch, pg._orbit_radius)
		assert_lt(xf.origin.distance_to(solved.origin), 0.05, "%s: camera sits on its orbit" % name)
		assert_gt((-xf.basis.z).dot(-solved.basis.z), 0.999, "%s: camera looks at the pivot" % name)
		pg._unhandled_input(_key(KEY_A))
		pg._unhandled_input(_key(KEY_D))
		assert_lt(_cam(pg).global_transform.origin.distance_to(xf.origin), 0.05,
			"%s: first key press does not jump the view" % name)
	pg._apply_camera_preset("top")
	assert_gt(pg._orbit_pitch, deg_to_rad(80.0), "top preset looks steeply down")


func test_pick_hits_the_terrain_surface_not_the_datum_plane() -> void:
	var pg: Node = _make_pg()
	pg._params.base_amplitude_m = 4.0
	await get_tree().process_frame
	pg._on_knob_changed("base_amplitude_m", 4.0)
	assert_true(await _await_idle(pg), "rebuild finishes")
	pg._allow_input = true
	# Highest LUT node: look straight down on it from 25 m above.
	var lut: Dictionary = pg._terrain_lut
	var data: PackedFloat32Array = lut["data"]
	var best := 0
	for i in range(data.size()):
		if data[i] > data[best]:
			best = i
	var cols: int = lut["cols"]
	var local_xz: Vector2 = (lut["origin_xz"] as Vector2) \
		+ Vector2(float(best % cols), float(best / cols)) * float(lut["cell_m"])
	var h := VillageTerrain.lut_sample(lut, local_xz)
	assert_gt(h, 0.5, "test terrain has a raised point")
	var stage_pos: Vector3 = (pg.get_node("Stage") as Node3D).global_position
	var target := stage_pos + Vector3(local_xz.x, h, local_xz.y)
	var cam := _cam(pg)
	cam.global_position = target + Vector3(0.0, 25.0, 0.01)
	cam.look_at(target, Vector3.UP)
	var hit: Vector3 = pg._pick_terrain_point(_screen_centre(pg))
	assert_true(hit.is_finite(), "ray hits the terrain")
	assert_almost_eq(hit.y, target.y, 0.05, "pick lands on the terrain surface (h=%.2f), not y=0" % h)
	# A left click glides the pivot there.
	pg._unhandled_input(_mouse(MOUSE_BUTTON_LEFT, _screen_centre(pg)))
	assert_true(pg._gliding, "left click starts a glide")
	pg._advance_glide(5.0)
	assert_false(pg._gliding, "glide finishes")
	assert_lt(pg._pivot.distance_to(hit), 0.01, "pivot ends on the clicked terrain point")


func test_clicks_and_scrolls_over_the_knob_panel_do_not_move_the_camera() -> void:
	var pg: Node = await _ready_pg()
	pg._build_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	var rect: Rect2 = pg._knob_panel.get_global_rect()
	var pos := rect.position + Vector2(20.0, 40.0)
	assert_true(pg._point_over_ui(pos), "knob panel point counts as UI")
	assert_false(pg._point_over_ui(_screen_centre(pg) + Vector2(80.0, 0.0)), "open view is not UI")
	var r0: float = pg._orbit_radius
	var pivot0: Vector3 = pg._pivot
	pg._unhandled_input(_mouse(MOUSE_BUTTON_WHEEL_UP, pos))
	var pan := InputEventPanGesture.new()
	pan.position = pos
	pan.delta = Vector2(0.0, -2.0)
	pg._unhandled_input(pan)
	assert_eq(pg._orbit_radius, r0, "scroll over the panel does not zoom")
	pg._unhandled_input(_mouse(MOUSE_BUTTON_LEFT, pos))
	assert_false(pg._gliding, "click over the panel does not glide")
	assert_eq(pg._pivot, pivot0, "pivot unchanged")


func test_hud_names_knobs_beyond_gentle_limits() -> void:
	var pg: Node = await _ready_pg()
	assert_false(pg.hud_text().contains("gentle"), "defaults: no limit line")
	pg._params.base_amplitude_m = 5.0
	pg._params.hero_flat_r_m = 0.0
	var t: String = pg.hud_text()
	assert_string_contains(t, "base_amplitude_m")
	assert_string_contains(t, "hero_flat_r_m")
	assert_string_contains(t, "gentle")
