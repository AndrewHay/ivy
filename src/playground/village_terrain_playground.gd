## VillageTerrainPlayground — G7 algorithm playground for in-village lawn terrain.
## SD-VILLAGE-TERRAIN-9 / AR-VT-PLAYGROUND.
## Structure mirrors hills_playground.gd: knob-host wiring, camera presets,
## variants, presets, Reset, Copy settings, and the _capture_done_fn quit-hook seam.
## WP8b additions: debug relief shader, VE, disc clip, HUD, markers at sample_y,
## pond water, fog-off for top view, raking oblique camera.
extends Node3D

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrainKnobSpec = preload("res://src/playground/village_terrain_knob_spec.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")
const VillagePondSite = preload("res://src/world/village_pond_site.gd")
const KnobPanel = preload("res://src/playground/knob_panel.gd")
const PlaygroundKnobHost = preload("res://src/playground/playground_knob_host.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
const DebugCamera = preload("res://src/world/debug_camera.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const WorldFogParams = preload("res://src/world/world_fog_params.gd")
const WorldFogVolume = preload("res://src/world/world_fog_volume.gd")
const SkySun = preload("res://src/world/sky_sun.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const Solar = preload("res://src/env/solar.gd")
const VillageTerrainGrassHost = preload("res://src/playground/village_terrain_grass_host.gd")
const VillageTerrainVillageHost = preload("res://src/playground/village_terrain_village_host.gd")

## Knobs that only change village_ground.gdshader uniforms (VillageTerrain.apply_ground_material):
## they update the material in place, never the mesh (ivy-82zn.14.7).
const MATERIAL_ONLY_KNOBS := [
	"ground_slope_dark", "ground_slope_full_deg", "ground_height_tint", "ground_height_range_m",
]
## Coarse preview LUT / mesh cell (m). ~1/4 of the full-step work; shown first after a shape edit.
const _COARSE_STEP_M := 4.0
## Production grass LUT cell (VillageBackdrop._ensure_terrain_sample_lut builds it at 1.0 m).
const _GRASS_LUT_CELL_M := 1.0

## Rebuild pipeline (ivy-82zn.14.7). Each phase does at most one slice of work per frame.
## ivy-82zn.14.8: GRASS_LUT is the shared 1 m seat LUT (village and grass both bake Y from it);
## VILLAGE runs one production village build step per frame.
enum Phase { IDLE, WARM_PAD, WARM_SPINE, COARSE, FULL, GRASS_LUT, VILLAGE, GRASS_PLACE, GRASS_BUILD }

const _DEBUG_SHADER_PATH := "res://src/playground/shaders/village_terrain_debug.gdshader"
const _PRODUCTION_SHADER_PATH := "res://src/render/shaders/village_ground.gdshader"

@export var script_driven: bool = false
## Set before _ready() to override the initial variant (used by tests).
@export var _initial_variant: int = -1

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _camera: Camera3D = $Camera3D
@onready var _stage: Node3D = $Stage

var _params := VillageTerrainParams.production()
var _layout: VillageLayout
var _knob_panel: KnobPanel
var _world_fog_params: WorldFogParams = WorldFogParams.production()
var _show_ui := true
var _allow_input := true
var _last_preset := "camsun"
# Orbit camera state (ivy-82zn.14.8): every preset sets it, so input continues from the preset view.
var _orbit_yaw := 0.0
var _orbit_pitch := 0.031415927
var _orbit_radius := 8.01 * ForestPlaygroundCamera.GENERATED_RIG_SCALE
var _pivot := Vector3.ZERO
var _mouse_orbit := false
var _gliding := false
var _glide_from := Vector3.ZERO
var _glide_to := Vector3.ZERO
var _glide_elapsed := 0.0
var _glide_seconds := 0.0
## Orbit state of the last preset; R / Home return to it.
var _home_orbit: Dictionary = {}
## UI panels that shield the camera: clicks and scrolls over them never move it.
var _ui_shields: Array[Control] = []
var _world_fog_volume: FogVolume

# ── Debug-only playground vars (NOT in VillageTerrainParams; never production) ──
## Debug relief shader on (height bands + contours + slope); off = production shader.
## @export so tests can pre-set before _ready().
@export var _debug_relief_on: bool = true
## Contour line spacing in metres (debug only).
@export var _debug_contour_m: float = 0.2
## Vertical exaggeration (debug only, 1.0 = true scale, label clearly in UI).
@export var _debug_ve: float = 1.0

var _hud_label: Label
var _status_label: Label
var _debug_panel_container: Control

# ── Rebuild pipeline state (ivy-82zn.14.7) ──
## Production lawn grass on the playground terrain (Grass checkbox, default ON).
@export var _grass_on: bool = true
## Production village (cottages, path stones, pond water + bank, bushes, flowers) on the
## playground terrain (Village checkbox, default ON; ivy-82zn.14.8).
@export var _village_on: bool = true
## Shape-knob edits wait this long after the last change, so one slider drag = one rebuild.
@export var _debounce_s: float = 0.25
## Work per frame for the sliced LUT / grass builds (ms).
@export var _slice_budget_ms: float = 10.0
var _phase: int = Phase.IDLE
## Ticks (µs) at which a debounced rebuild starts; -1 = none pending.
var _rebuild_due_usec: int = -1
var _rebuild_count := 0
## Params snapshot the in-flight rebuild uses (knob edits mid-build never mix into it).
var _build_params: VillageTerrainParams
var _build_t_seed := 0
var _lut_job: Dictionary = {}
## LUT behind the mesh on screen (coarse while refining, then full resolution). HUD reads it.
var _terrain_lut: Dictionary = {}
var _shown_step_m := 0.0
var _terrain_mi: MeshInstance3D
var _grass_host: Node3D
var _grass_building: Node3D
var _grass_lut: Dictionary = {}
var _grass_ctx: VillageGrassExclusionContext
## Blade transforms per 6 m chunk for the current layout (placement does not depend on relief).
var _grass_chunks: Array = []
var _grass_chunks_layout: VillageLayout
var _grass_queue: Array = []
var _grass_queue_total := 0
var _grass_task_id := -1
var _grass_task_result: Array = []
## Rebuild number the 1 m seat LUT (_grass_lut) belongs to; a toggle after a build reuses it.
var _seat_lut_rebuild := -1
## What the in-flight seat pass builds (set when it starts; toggles only add to a fresh pass).
var _seat_village := false
var _seat_grass := false
var _village_host: Node3D
var _village_building: Node3D
var _village_step := 0
## Rebuild the shown village was seated for.
var _village_built_rebuild := -1
## Village OFF hides the host instead of freeing it: its cottage / scatter meshes keep the glTF
## pieces loaded (a reload costs ~0.2-0.3 s in one frame), and ON reuses it if still current.
var _village_off_host: Node3D
var _village_off_rebuild := -1
## Timing of the last rebuild (ms from the edit that triggered it) and the longest frame (ms).
var perf: Dictionary = {}
var _perf_t0_usec := 0
var _perf_max_frame_usec := 0

## Camera feel comes from the main game's DebugCamera constants (same drag, key step, zoom notch,
## trackpad scale and glide timing); only the zoom range is the playground's (whole lawn to stoop).
const _DRAG_RAD_PER_PIXEL := DebugCamera._DRAG_DEG_PER_PIXEL * PI / 180.0
const _KEY_RAD_PER_PRESS := DebugCamera._KEY_DEG_PER_PRESS * PI / 180.0
const _ZOOM_MIN_RADIUS := 1.5
const _ZOOM_MAX_RADIUS := 160.0
## Terrain pick: ray-march step (m) before bisection, and the fallback pivot distance (m).
const _PICK_STEP_M := 0.5
const _PICK_FALLBACK_M := 20.0

var _pond_snapshot: Variant
var _sky_sun: SkySun
## Callable(err: int) invoked after a capture save. Tests replace this to avoid
## calling get_tree().quit() from inside the GUT runner (AR-VT-PLAYGROUND §quit-hook).
var _capture_done_fn: Callable


func _ready() -> void:
	_capture_done_fn = func(err: int) -> void: get_tree().quit(0 if err == OK else err)
	_pond_snapshot = VillagePondShape.active()
	var out_path := _parse_out_arg()
	var capture_ui := _has_user_arg("--capture-ui")
	_show_ui = capture_ui or (out_path.is_empty() and not script_driven)
	_allow_input = out_path.is_empty() and not script_driven
	_setup_environment()
	_apply_cli_overrides()
	if _initial_variant >= 0:
		_params.variant = _initial_variant
	_rebuild_layout_and_stage(true)
	if _show_ui:
		_build_ui()
	_apply_camera_preset(_parse_camera_arg())
	if _camera:
		_camera.current = true
	var perf_knob := _parse_perf_knob_arg()
	if not out_path.is_empty() or not perf_knob.is_empty():
		# Capture the refined terrain (+ grass), not the coarse preview.
		await _await_refined()
		if not perf_knob.is_empty():
			# --perf-knob=name:value: one shape edit after the initial build, timings logged
			# by _finish_rebuild (ivy-82zn.14.7 evidence; also handy for reviewers).
			print("[vt-playground] initial build ", JSON.stringify(perf))
			_on_knob_changed(perf_knob[0], float(perf_knob[1]))
			if _knob_panel:
				_knob_panel.refresh_values()
			var refining_path := _parse_arg_value("--out-refining=")
			if not refining_path.is_empty():
				# Mid-refine frame: coarse preview on screen + 'rebuilding' indicator.
				var cap := 6000
				while _phase != Phase.FULL and cap > 0:
					cap -= 1
					await get_tree().process_frame
				await get_tree().process_frame
				var img := get_viewport().get_texture().get_image()
				if img != null and img.save_png(refining_path) == OK:
					print("[village-terrain-playground] saved ", refining_path)
			await _await_refined()
			if out_path.is_empty():
				get_tree().quit(0)
				return
		await get_tree().process_frame
		await get_tree().process_frame
		await _capture_png(out_path)


func _exit_tree() -> void:
	_phase = Phase.IDLE
	_rebuild_due_usec = -1
	_lut_job = {}
	_wait_grass_task()
	if _pond_snapshot != null:
		VillagePondShape.set_active(_pond_snapshot)
	if _mouse_orbit:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if _rebuild_due_usec >= 0 and t0 >= _rebuild_due_usec:
		_rebuild_due_usec = -1
		_start_rebuild()
	elif _phase != Phase.IDLE:
		_step_rebuild(int(_slice_budget_ms * 1000.0))
	_perf_max_frame_usec = maxi(_perf_max_frame_usec, Time.get_ticks_usec() - t0)
	_update_status()
	if _gliding:
		_advance_glide(_delta)


# ── Camera controls (same scheme as the main game's DebugCamera) ─────────────
# Tab = mouse-look on/off (cursor captured while on), left click = glide the orbit pivot to the
# clicked point on the terrain surface, wheel / trackpad scroll = zoom, WASD / arrows = rotate,
# R / Home = back to the last preset. Clicks and scrolls over the UI panels never reach the camera.
# The DebugCamera node itself is not used: it needs a TowerSpec and physics colliders to pick,
# and a terrain collider rebuilt per knob edit would cost a long freeze. Its statics (solve,
# clamp_pitch) and feel constants are shared instead, and picking ray-marches the terrain LUT.

## Tab is handled in `_input` (not `_unhandled_input`) so a focused slider/button cannot swallow
## it for GUI focus navigation (same as grass_wind_playground).
func _input(event: InputEvent) -> void:
	if not _allow_input:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_TAB:
			_set_mouse_orbit(not _mouse_orbit)
			if is_inside_tree():
				get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _allow_input:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or _point_over_ui(mb.position):
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by_notches(1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by_notches(-1.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT and not _mouse_orbit:
			var hit := _pick_terrain_point(mb.position)
			if hit.is_finite():
				_begin_glide_to(hit)
	elif event is InputEventPanGesture:
		# macOS trackpad two-finger scroll arrives here, never as a wheel button.
		var pan := event as InputEventPanGesture
		if not _point_over_ui(pan.position):
			_zoom_by_notches(-pan.delta.y * DebugCamera._NOTCHES_PER_PAN_UNIT)
	elif event is InputEventMouseMotion and _mouse_orbit:
		var mm := event as InputEventMouseMotion
		_orbit_yaw -= mm.relative.x * _DRAG_RAD_PER_PIXEL
		_orbit_pitch = DebugCamera.clamp_pitch(
			_orbit_pitch - mm.relative.y * _DRAG_RAD_PER_PIXEL, _orbit_radius, _current_pivot().y)
		_apply_orbit_camera()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var k := event as InputEventKey
		match k.keycode:
			KEY_LEFT, KEY_A:
				_orbit_yaw -= _KEY_RAD_PER_PRESS
			KEY_RIGHT, KEY_D:
				_orbit_yaw += _KEY_RAD_PER_PRESS
			KEY_UP, KEY_W:
				_orbit_pitch = DebugCamera.clamp_pitch(
					_orbit_pitch + _KEY_RAD_PER_PRESS, _orbit_radius, _current_pivot().y)
			KEY_DOWN, KEY_S:
				_orbit_pitch = DebugCamera.clamp_pitch(
					_orbit_pitch - _KEY_RAD_PER_PRESS, _orbit_radius, _current_pivot().y)
			KEY_R, KEY_HOME:
				_reset_camera()
				return
			_:
				return
		_apply_orbit_camera()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _mouse_orbit:
		_set_mouse_orbit(false)


func _set_mouse_orbit(on: bool) -> void:
	_mouse_orbit = on
	if _allow_input:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE)


func _point_over_ui(pos: Vector2) -> bool:
	for c in _ui_shields:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false


func _zoom_by_notches(notches: float) -> void:
	_orbit_radius = clampf(_orbit_radius * pow(DebugCamera._ZOOM_PER_NOTCH, notches),
		_ZOOM_MIN_RADIUS, _ZOOM_MAX_RADIUS)
	_apply_orbit_camera()


func _current_pivot() -> Vector3:
	if _gliding:
		return _glide_from.lerp(_glide_to, _glide_blend())
	return _pivot


func _glide_blend() -> float:
	if _glide_seconds <= 0.0:
		return 1.0
	var t := clampf(_glide_elapsed / _glide_seconds, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _begin_glide_to(world_point: Vector3) -> void:
	var from := _current_pivot()
	if from.distance_squared_to(world_point) < 0.01:
		_pivot = world_point
		_gliding = false
		_apply_orbit_camera()
		return
	_glide_from = from
	_glide_to = world_point
	_glide_elapsed = 0.0
	_glide_seconds = clampf(from.distance_to(world_point) / DebugCamera._GLIDE_METRES_PER_SEC,
		DebugCamera._GLIDE_MIN_SEC, DebugCamera._GLIDE_MAX_SEC)
	_gliding = true


func _advance_glide(delta: float) -> void:
	if not _gliding:
		return
	_glide_elapsed += delta
	if _glide_elapsed >= _glide_seconds:
		_gliding = false
		_pivot = _glide_to
	_apply_orbit_camera()


func _reset_camera() -> void:
	if _home_orbit.is_empty():
		_apply_camera_preset(_last_preset)
		return
	_orbit_yaw = _home_orbit["yaw"]
	_orbit_pitch = _home_orbit["pitch"]
	_orbit_radius = _home_orbit["radius"]
	_pivot = _home_orbit["pivot"]
	_gliding = false
	_apply_orbit_camera()


func _store_home() -> void:
	_home_orbit = {"yaw": _orbit_yaw, "pitch": _orbit_pitch, "radius": _orbit_radius, "pivot": _pivot}


func _adopt_camera_as_orbit() -> void:
	## Turn the preset's camera transform into orbit state: the pivot is where the view ray meets
	## the terrain (else the aim point's depth along the ray), so the first input does not jump.
	var xf := _camera.global_transform
	var fwd := -xf.basis.z
	var hit := _raycast_terrain(xf.origin, fwd)
	var d := xf.origin.distance_to(hit) if hit.is_finite() else -1.0
	if d < 1.0:
		d = (ForestPlaygroundCamera.aim_point() - xf.origin).dot(fwd)
		if d < 1.0:
			d = _PICK_FALLBACK_M
	_pivot = xf.origin + fwd * d
	var off := xf.origin - _pivot
	_orbit_radius = off.length()
	_orbit_pitch = asin(clampf(off.y / maxf(_orbit_radius, 1e-4), -1.0, 1.0))
	_orbit_yaw = atan2(off.x, off.z)
	_gliding = false


func _terrain_surface_y(world: Vector3) -> float:
	## Terrain Y (world) under a world point: the LUT on screen inside the lawn, else the datum.
	var o := _stage.global_position
	if _layout == null or _terrain_lut.is_empty():
		return o.y
	var local := Vector2(world.x - o.x, world.z - o.z)
	if local.distance_to(_layout.hamlet_centre_xz) >= _layout.lawn_radius:
		return o.y
	return o.y + VillageTerrain.lut_sample(_terrain_lut, local)


func _raycast_terrain(from: Vector3, dir: Vector3) -> Vector3:
	## Ray-march the terrain surface (0.5 m steps, then bisection). INF when nothing is hit.
	if from.y - _terrain_surface_y(from) <= 0.0:
		return Vector3(INF, INF, INF)
	var prev_t := 0.0
	var t := _PICK_STEP_M
	while t <= DebugCamera._PICK_RANGE:
		var p := from + dir * t
		if p.y - _terrain_surface_y(p) <= 0.0:
			var lo := prev_t
			var hi := t
			for _i in range(24):
				var mid := (lo + hi) * 0.5
				var q := from + dir * mid
				if q.y - _terrain_surface_y(q) <= 0.0:
					hi = mid
				else:
					lo = mid
			var hit := from + dir * hi
			hit.y = _terrain_surface_y(hit)
			return hit
		prev_t = t
		t += _PICK_STEP_M
	return Vector3(INF, INF, INF)


func _pick_terrain_point(screen: Vector2) -> Vector3:
	return _raycast_terrain(_camera.project_ray_origin(screen), _camera.project_ray_normal(screen))


func _setup_environment() -> void:
	_install_production_sky_sun()


func _install_production_sky_sun() -> void:
	if _sky_sun != null:
		return
	var sky := SkySun.new()
	sky.name = "SkySun"
	add_child(sky)
	var sun := get_node("DirectionalLight3D") as DirectionalLight3D
	remove_child(sun)
	sky.add_child(sun)
	sun.name = "Sun"
	remove_child(_world_env)
	sky.add_child(_world_env)
	_sky_sun = sky
	var env := _main_like_environment()
	_world_env.environment = env
	var solar := Solar.new(IvyParams.new())
	sky.setup(solar)
	sky.set_fog_model(HeroFog.FogModel.WORLD_AROUND_HERO)


func _main_like_environment() -> Environment:
	var sky_shader := load("res://src/render/sky/atmospheric_sky.gdshader") as Shader
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_shader
	sky_mat.set_shader_parameter("sky_top_color", Color(0.361, 0.561, 0.722))
	sky_mat.set_shader_parameter("sky_horizon_color", Color(0.784, 0.851, 0.91))
	sky_mat.set_shader_parameter("sky_energy", 1.4)
	sky_mat.set_shader_parameter("ground_horizon_color", Color(0.784, 0.851, 0.91))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.72)
	env.ambient_light_energy = 0.8
	return env


func _apply_cli_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_params.layout_seed = int(arg.get_slice("=", 1))
		if arg.begins_with("--variant="):
			_params.variant = int(arg.get_slice("=", 1))
		if arg.begins_with("--preset="):
			_params.apply_preset(arg.get_slice("=", 1))
		if arg.begins_with("--ve="):
			_debug_ve = float(arg.get_slice("=", 1))
		if arg.begins_with("--debug-relief="):
			_debug_relief_on = arg.get_slice("=", 1).to_lower() != "0"
		if arg.begins_with("--contour="):
			_debug_contour_m = float(arg.get_slice("=", 1))
		if arg.begins_with("--base-amplitude="):
			_params.base_amplitude_m = float(arg.get_slice("=", 1))
		if arg.begins_with("--base-feature="):
			_params.base_feature_m = float(arg.get_slice("=", 1))
		if arg.begins_with("--knoll-height="):
			_params.knoll_height_m = float(arg.get_slice("=", 1))
		if arg.begins_with("--knoll-radius="):
			_params.knoll_radius_m = float(arg.get_slice("=", 1))
		if arg.begins_with("--noise-octaves="):
			_params.noise_octaves = int(arg.get_slice("=", 1))
		if arg.begins_with("--noise-persistence="):
			_params.noise_persistence = float(arg.get_slice("=", 1))
		if arg.begins_with("--knob="):
			# --knob=name:value (repeatable): any VillageTerrainParams field (ivy-82zn.14.8).
			var kv := arg.substr("--knob=".length()).split(":")
			if kv.size() == 2 and _params.get(kv[0]) != null:
				var cur: Variant = _params.get(kv[0])
				_params.set(kv[0], int(kv[1]) if cur is int else float(kv[1]))
		if arg == "--no-village":
			_village_on = false
		if arg == "--no-grass":
			_grass_on = false


func _rebuild_layout_and_stage(sync_preview: bool = false) -> void:
	## New layout: fresh stage, then a rebuild started now (no debounce). sync_preview runs the
	## warm-up + coarse preview inside this call (startup, so LawnTerrain exists after _ready).
	_wait_grass_task()
	_layout = VillageLayout.generate(_params.layout_seed)
	VillagePondShape.set_active(VillagePondShape.at(_layout.pond_center))
	_apply_stage_datum(_params)
	_clear_stage()
	_terrain_mi = MeshInstance3D.new()
	_terrain_mi.name = "LawnTerrain"
	_terrain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(_terrain_mi)
	_rebuild_due_usec = -1
	_perf_t0_usec = Time.get_ticks_usec()
	_perf_max_frame_usec = 0
	_start_rebuild()
	if sync_preview:
		while _phase != Phase.IDLE and _phase <= Phase.COARSE:
			_step_rebuild(-1)
	_build_markers(_params)
	_apply_playground_fog()


func _clear_stage() -> void:
	for c in _stage.get_children():
		c.name = "_removing_%s" % c.name
		c.queue_free()
	_terrain_mi = null
	_grass_host = null
	_grass_building = null
	_grass_queue.clear()
	_grass_chunks.clear()
	_grass_chunks_layout = null
	_grass_ctx = null
	_terrain_lut = {}
	_village_host = null
	_village_building = null
	_village_off_host = null
	_seat_lut_rebuild = -1


# ── Rebuild pipeline (ivy-82zn.14.7) ──────────────────────────────────────────
# Shape edit → debounce → warm caches (pad table, path spine) → coarse 4 m LUT + mesh on screen
# → full-step LUT + mesh (+ HUD, markers) → 1 m grass LUT → production grass chunks, swapped in
# when complete. LUTs are VillageTerrain.lut_job_* (same cells as build_sample_lut), stepped
# _slice_budget_ms per frame, so the window keeps drawing and taking input.

func is_refining() -> bool:
	return _phase != Phase.IDLE or _rebuild_due_usec >= 0


func rebuild_status() -> String:
	if _rebuild_due_usec >= 0:
		return "Rebuild queued…"
	match _phase:
		Phase.WARM_PAD, Phase.WARM_SPINE, Phase.COARSE:
			return "Rebuilding terrain: coarse preview…"
		Phase.FULL:
			return "Refining terrain %d%%" % int(100.0 * float(_lut_job.get("progress", 0.0)))
		Phase.GRASS_LUT:
			var what := "Re-seating village" if _seat_village else "Refreshing grass"
			return "%s: heights %d%%" % [what, int(100.0 * float(_lut_job.get("progress", 0.0)))]
		Phase.VILLAGE:
			var steps: Array = VillageTerrainVillageHost.STEPS
			return "Re-seating village: %s (%d/%d)…" % [
				steps[mini(_village_step, steps.size() - 1)], _village_step + 1, steps.size()]
		Phase.GRASS_PLACE:
			return "Refreshing grass: placing blades…"
		Phase.GRASS_BUILD:
			var done := _grass_queue_total - _grass_queue.size()
			return "Refreshing grass %d%%" % int(100.0 * float(done) / float(maxi(_grass_queue_total, 1)))
	return ""


func _request_rebuild() -> void:
	## Debounced: every edit pushes the start back, so a slider drag rebuilds once at the end.
	_perf_t0_usec = Time.get_ticks_usec()
	_perf_max_frame_usec = 0
	_rebuild_due_usec = _perf_t0_usec + int(maxf(_debounce_s, 0.0) * 1000000.0)


func _is_flat() -> bool:
	return _build_params.variant == 1 or not _layout.is_generated


func _start_rebuild() -> void:
	_rebuild_count += 1
	_build_params = _params.duplicate_params()
	_build_t_seed = VillageTerrain.terrain_seed(_layout, _build_params)
	_cancel_seat()
	_lut_job = {}
	perf = {"rebuild": _rebuild_count}
	if _is_flat():
		var lut := VillageTerrain.build_sample_lut(_layout, _build_params, _build_t_seed, _COARSE_STEP_M)
		_show_mesh(VillageTerrain.build_mesh(_layout, _build_params), _build_params.terrain_mesh_step_m, lut)
		_perf_mark("coarse_ms")
		_finish_terrain()
		return
	# Static caches are keyed by the params signature; clearing keeps them from growing per edit.
	VillageTerrain.clear_knoll_centres_cache()
	_phase = Phase.WARM_PAD


func _step_rebuild(budget_usec: int) -> void:
	match _phase:
		Phase.WARM_PAD:
			# Knoll centres + cottage pad table (one frame).
			VillageTerrain.sample_y(VillageLayout.HERO_DOOR_STOOP, _layout, _build_params, _build_t_seed)
			_phase = Phase.WARM_SPINE
		Phase.WARM_SPINE:
			# Path spine (the longest single step) in its own frame, before any LUT slice.
			for poly: Variant in _layout.path_polylines():
				var pts: Array = poly as Array
				if pts.size() >= 2:
					var mid := (pts[0] as Vector2).lerp(pts[1] as Vector2, 0.5)
					VillageTerrain.sample_y(mid, _layout, _build_params, _build_t_seed)
			_lut_job = VillageTerrain.lut_job_begin(_layout, _build_params, _build_t_seed, _COARSE_STEP_M)
			_phase = Phase.COARSE
		Phase.COARSE:
			if VillageTerrain.lut_job_step(_lut_job, budget_usec):
				var lut: Dictionary = _lut_job["lut"]
				_show_mesh(VillageTerrain.mesh_from_lut(_layout, _COARSE_STEP_M, lut), _COARSE_STEP_M, lut)
				_perf_mark("coarse_ms")
				var step := maxf(_build_params.terrain_mesh_step_m, 0.1)
				_lut_job = VillageTerrain.lut_job_begin(_layout, _build_params, _build_t_seed, step)
				_phase = Phase.FULL
		Phase.FULL:
			if VillageTerrain.lut_job_step(_lut_job, budget_usec):
				var step := maxf(_build_params.terrain_mesh_step_m, 0.1)
				var lut: Dictionary = _lut_job["lut"]
				var mesh := VillageTerrain.mesh_from_lut(_layout, step, lut)
				if mesh == null:
					mesh = VillageTerrain.build_mesh(_layout, _build_params)
				_show_mesh(mesh, step, lut)
				_finish_terrain()
		Phase.GRASS_LUT:
			if VillageTerrain.lut_job_step(_lut_job, budget_usec):
				_grass_lut = _lut_job["lut"]
				_seat_lut_rebuild = _rebuild_count
				_lut_job = {}
				_after_seat_lut()
		Phase.VILLAGE:
			_step_village_build(budget_usec)
		Phase.GRASS_PLACE:
			_begin_grass_build()
		Phase.GRASS_BUILD:
			_step_grass_build(budget_usec)


func _finish_terrain() -> void:
	## Full-resolution terrain on screen: HUD + markers follow it, then grass (if on).
	_perf_mark("full_ms")
	_lut_job = {}
	_update_hud()
	_refresh_markers()
	_start_seat(_village_on, _grass_on)


func _finish_rebuild() -> void:
	if _village_on and _village_host == null and _village_building == null and _layout != null:
		# Village ticked while grass was building: seat it now (the 1 m LUT is reused).
		_start_seat(true, false)
		return
	_phase = Phase.IDLE
	perf["max_frame_ms"] = float(_perf_max_frame_usec) / 1000.0
	print("[vt-playground] rebuild #%d %s" % [_rebuild_count, JSON.stringify(perf)])


func _perf_mark(key: String) -> void:
	perf[key] = float(Time.get_ticks_usec() - _perf_t0_usec) / 1000.0


func _show_mesh(mesh: Mesh, step: float, lut: Dictionary) -> void:
	if _terrain_mi == null:
		return
	mesh.surface_set_material(0, _make_terrain_material())
	_terrain_mi.mesh = mesh
	_shown_step_m = step
	_terrain_lut = lut
	_apply_stage_datum(_build_params)


func _apply_stage_datum(params: VillageTerrainParams) -> void:
	## Mirror World (ivy-82zn.14.10 option A): the stage is lowered by the hill's hero datum, so the
	## hero ground is at world y = 0 and the camera presets frame the game's view. Re-applied with
	## every mesh shown, so hill knob edits move the village under the fixed hero.
	if _layout == null or params == null:
		return
	_stage.position = ForestPlaygroundCamera.backdrop_origin() \
		- Vector3(0.0, VillageTerrain.hero_datum_y(_layout, params), 0.0)


# ── Grass (production VillageBackdrop builder via VillageTerrainGrassHost) ────

func _start_seat(village: bool, grass: bool) -> void:
	## Seat pass after the full terrain: the shared 1 m LUT (unless this rebuild already has it),
	## then the village steps, then grass. Nothing to seat → the rebuild is done.
	_seat_village = village
	_seat_grass = grass
	if not village and not grass:
		_finish_rebuild()
		return
	if _is_flat():
		_grass_lut = {}  # production leaves blade / piece Y at datum for flat / classic
		_seat_lut_rebuild = _rebuild_count
		_after_seat_lut()
		return
	if _seat_lut_rebuild == _rebuild_count:
		_after_seat_lut()
		return
	_lut_job = VillageTerrain.lut_job_begin(_layout, _build_params, _build_t_seed, _GRASS_LUT_CELL_M)
	_phase = Phase.GRASS_LUT


func _after_seat_lut() -> void:
	if _seat_village:
		_begin_village_build()
	elif _seat_grass:
		_phase = Phase.GRASS_PLACE
	else:
		_finish_rebuild()


# ── Village (production VillageBackdrop steps via VillageTerrainVillageHost) ──

func _begin_village_build() -> void:
	var host := VillageTerrainVillageHost.new()
	host.name = "Village_building"
	host.visible = false
	_stage.add_child(host)
	host.configure(_layout, _build_params, _build_t_seed, _grass_lut)
	_village_building = host
	_village_step = 0
	_phase = Phase.VILLAGE


func _step_village_build(budget_usec: int) -> void:
	## One production build step (or one slice of it) per frame; the old village stays on screen
	## until the swap. perf["village_<step>_ms"] keeps each step's longest single frame.
	var host := _village_building as VillageTerrainVillageHost
	if host == null or not is_instance_valid(host):
		_village_building = null
		_after_village()
		return
	var t0 := Time.get_ticks_usec()
	var done := host.build_step(_village_step, budget_usec)
	var key := "village_%s_ms" % VillageTerrainVillageHost.STEPS[_village_step]
	perf[key] = maxf(float(perf.get(key, 0.0)), float(Time.get_ticks_usec() - t0) / 1000.0)
	if not done:
		return
	_village_step += 1
	if _village_step < host.step_count():
		return
	_free_village_host()
	_free_village_off_host()
	host.name = "Village"
	host.visible = true
	_village_host = host
	_village_built_rebuild = _rebuild_count
	_village_building = null
	_perf_mark("village_ms")
	_update_marker_visibility()
	_after_village()


func _after_village() -> void:
	if _seat_grass:
		_phase = Phase.GRASS_PLACE
	else:
		_finish_rebuild()


func _free_village_host() -> void:
	if _village_host != null and is_instance_valid(_village_host):
		_village_host.name = "_removing_village"
		_village_host.queue_free()
	_village_host = null


func _free_village_off_host() -> void:
	if _village_off_host != null and is_instance_valid(_village_off_host):
		_village_off_host.name = "_removing_village_off"
		_village_off_host.queue_free()
	_village_off_host = null


func _cancel_village_build() -> void:
	if _village_building != null and is_instance_valid(_village_building):
		_village_building.name = "_removing_village_building"
		_village_building.queue_free()
	_village_building = null


func _set_village(on: bool) -> void:
	_village_on = on
	if not on:
		_cancel_village_build()
		if _phase == Phase.VILLAGE:
			_after_village()
		_seat_village = false
		if _village_host != null and is_instance_valid(_village_host):
			_free_village_off_host()
			_village_host.name = "Village_off"
			_village_host.visible = false
			_village_off_host = _village_host
			_village_off_rebuild = _village_built_rebuild
		_village_host = null
		_update_marker_visibility()
		return
	if _village_off_host != null and is_instance_valid(_village_off_host) \
			and _village_off_rebuild == _rebuild_count and _rebuild_due_usec < 0 \
			and _phase <= Phase.IDLE:
		# Still seated on the terrain on screen: show it again, no rebuild.
		_village_host = _village_off_host
		_village_off_host = null
		_village_host.name = "Village"
		_village_host.visible = true
		_update_marker_visibility()
		return
	if _phase == Phase.GRASS_LUT:
		_seat_village = true  # the seat pass in flight builds the village before grass
	elif _phase == Phase.IDLE and _rebuild_due_usec < 0 and _build_params != null:
		_perf_t0_usec = Time.get_ticks_usec()
		_perf_max_frame_usec = 0
		perf = {"rebuild": _rebuild_count, "village_only": true}
		_start_seat(true, false)
	# Otherwise (grass building): _finish_rebuild starts the village when the grass is done.


func _update_marker_visibility() -> void:
	## The real village replaces the cottage slab and pond placeholder markers.
	var shown := _village_host != null and is_instance_valid(_village_host)
	for c in _stage.get_children():
		var n := str(c.name)
		if n == "PondWater" or n == "PondBank" or n.begins_with("Cottage_"):
			(c as Node3D).visible = not shown


func _begin_grass_build() -> void:
	## GRASS_PLACE, once per frame. Blade placement depends on the layout only, so it runs once
	## per layout, on a worker thread (1-2 s on seed 7); later rebuilds reuse the chunks.
	if _grass_building == null:
		var host := VillageTerrainGrassHost.new()
		host.name = "LawnGrass_building"
		host.visible = false
		_stage.add_child(host)
		_grass_building = host
	(_grass_building as VillageTerrainGrassHost).configure(_layout, _grass_lut)
	if _grass_chunks_layout != _layout or _grass_ctx == null:
		if _grass_task_id < 0:
			_grass_ctx = (_grass_building as VillageTerrainGrassHost).grass_context()
			var ctx := _grass_ctx
			var origin_xz := Vector2(_stage.global_position.x, _stage.global_position.z)
			_grass_task_result = []
			_grass_task_id = WorkerThreadPool.add_task(func() -> void:
				_grass_task_result = _bucket_grass(
					VillageScatterPositions.grass_blade_positions(ctx), origin_xz))
			return
		if not WorkerThreadPool.is_task_completed(_grass_task_id):
			return
		WorkerThreadPool.wait_for_task_completion(_grass_task_id)
		_grass_task_id = -1
		_grass_chunks = _grass_task_result
		_grass_task_result = []
		_grass_chunks_layout = _layout
		_perf_mark("grass_place_ms")
	_grass_queue = _grass_chunks.duplicate()
	_grass_queue_total = _grass_queue.size()
	_phase = Phase.GRASS_BUILD


func _wait_grass_task() -> void:
	## The placement task reads VillagePondShape.active() and the grass host's layout: finish it
	## before either changes (seed change, exit).
	if _grass_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_grass_task_id)
		_grass_task_id = -1
		_grass_task_result = []


static func _bucket_grass(tufts: Array[Transform3D], origin_xz: Vector2) -> Array:
	## Same 6 m buckets as VillageBackdrop._add_grass_blade_chunks, so feeding it one bucket at a
	## time builds the same Scatter_Grass_Blades_<ix>_<iz> nodes as one call with every blade.
	var cm := VillageBackdrop.GRASS_BLADE_CHUNK_M
	var buckets: Dictionary = {}
	for t in tufts:
		var key := Vector2i(int(floor((origin_xz.x + t.origin.x) / cm)),
			int(floor((origin_xz.y + t.origin.z) / cm)))
		if not buckets.has(key):
			buckets[key] = [] as Array[Transform3D]
		(buckets[key] as Array[Transform3D]).append(t)
	return buckets.values()


func _step_grass_build(budget_usec: int) -> void:
	var host := _grass_building as VillageTerrainGrassHost
	if host == null:
		_finish_rebuild()
		return
	var t_end := Time.get_ticks_usec() + budget_usec
	while not _grass_queue.is_empty():
		var chunk: Array[Transform3D] = _grass_queue.pop_back()
		host.add_blade_chunk(chunk, _grass_ctx.generated_grass)
		if budget_usec >= 0 and Time.get_ticks_usec() >= t_end:
			return
	host.add_accents(_grass_ctx)
	if _grass_host != null and is_instance_valid(_grass_host):
		_grass_host.name = "_removing_grass"
		_grass_host.queue_free()
	host.name = "LawnGrass"
	host.visible = true
	_grass_host = host
	_grass_building = null
	_perf_mark("grass_ms")
	_finish_rebuild()


func _cancel_grass_build() -> void:
	## While the placement task runs the hidden host stays (the task's context reads it, and it
	## has no chunks yet); the next grass build reuses it.
	if _grass_task_id < 0 and _grass_building != null and is_instance_valid(_grass_building):
		_grass_building.name = "_removing_grass_building"
		_grass_building.queue_free()
		_grass_building = null
	_grass_queue.clear()
	_seat_grass = false
	if _phase == Phase.GRASS_PLACE or _phase == Phase.GRASS_BUILD:
		_phase = Phase.IDLE
	elif _phase == Phase.GRASS_LUT and not _seat_village:
		_phase = Phase.IDLE
		_lut_job = {}


func _cancel_seat() -> void:
	## A new terrain rebuild drops any half-built village / grass (the old ones stay on screen).
	_cancel_grass_build()
	_cancel_village_build()
	_seat_village = false
	if _phase >= Phase.GRASS_LUT:
		_phase = Phase.IDLE
		_lut_job = {}


func _set_grass(on: bool) -> void:
	_grass_on = on
	if not on:
		_cancel_grass_build()
		if _grass_host != null and is_instance_valid(_grass_host):
			_grass_host.name = "_removing_grass"
			_grass_host.queue_free()
		_grass_host = null
		return
	if _phase == Phase.GRASS_LUT or _phase == Phase.VILLAGE:
		_seat_grass = true  # the seat pass in flight adds grass after the village
	elif _phase == Phase.IDLE and _rebuild_due_usec < 0 and _build_params != null:
		_perf_t0_usec = Time.get_ticks_usec()
		_perf_max_frame_usec = 0
		perf = {"rebuild": _rebuild_count, "grass_only": true}
		_start_seat(false, true)


func _make_terrain_material() -> Material:
	if _debug_relief_on:
		return _make_debug_material()
	return _make_production_material()


func _make_production_material() -> ShaderMaterial:
	## Production-like look: uses village_ground.gdshader.
	## Gentle slopes (≤ 8°) barely change PBR lighting, so village_ground.gdshader adds an
	## albedo slope-dim ramp + height tint driven by the ground_* params (ivy-82zn.14.1).
	## ivy-82zn.14.1: slope shading + height tint come from the same params as the game.
	var mat := ShaderMaterial.new()
	mat.shader = load(_PRODUCTION_SHADER_PATH) as Shader
	VillageTerrain.apply_ground_material(mat, _params)
	return mat


func _make_debug_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(_DEBUG_SHADER_PATH) as Shader
	if mat.shader == null:
		printerr("[vt-playground] debug shader not found, falling back to production")
		return _make_production_material()
	# Pass disc clip params so edge is a clean circle, not the Cartesian stair-step.
	var g := _layout.hamlet_centre_xz
	var off := ForestPlaygroundCamera.backdrop_origin()
	# g_x/g_z are in world space (stage offset applied).
	mat.set_shader_parameter("g_x", g.x + off.x)
	mat.set_shader_parameter("g_z", g.y + off.z)
	mat.set_shader_parameter("disc_r", _layout.lawn_radius)
	mat.set_shader_parameter("ve_scale", _debug_ve)
	mat.set_shader_parameter("contour_m", _debug_contour_m)
	mat.set_shader_parameter("h_range", _params.max_rise_m + 0.1)
	return mat


func _terrain_material() -> ShaderMaterial:
	if _terrain_mi == null or _terrain_mi.mesh == null:
		return null
	return _terrain_mi.mesh.surface_get_material(0) as ShaderMaterial


func _is_debug_material(mat: ShaderMaterial) -> bool:
	return mat != null and mat.shader != null and mat.shader.resource_path == _DEBUG_SHADER_PATH


func _apply_material_knobs() -> void:
	## Ground shading uniforms in place (no rebuild). The debug shader does not read them.
	var mat := _terrain_material()
	if mat != null and not _is_debug_material(mat):
		VillageTerrain.apply_ground_material(mat, _params)


func _set_debug_relief(on: bool) -> void:
	## Swap debug / production shader on the existing mesh (no rebuild).
	_debug_relief_on = on
	if _terrain_mi != null and _terrain_mi.mesh != null:
		_terrain_mi.mesh.surface_set_material(0, _make_terrain_material())


func _set_debug_contour(m: float) -> void:
	_debug_contour_m = m
	var mat := _terrain_material()
	if _is_debug_material(mat):
		mat.set_shader_parameter("contour_m", _debug_contour_m)


func _set_debug_ve(ve: float) -> void:
	_debug_ve = ve
	var mat := _terrain_material()
	if _is_debug_material(mat):
		mat.set_shader_parameter("ve_scale", _debug_ve)


# ── Terrain stats / HUD ───────────────────────────────────────────────────────

func compute_terrain_stats() -> Dictionary:
	## HUD stats from the LUT behind the mesh on screen (ivy-82zn.14.7: no extra sample_y /
	## sample_slope_deg calls — the old grid walk re-sampled ~3,000 points per edit).
	## Public so tests can call it.
	if _layout == null or _terrain_lut.is_empty():
		return {}
	return terrain_stats_from_lut(_terrain_lut, _layout.hamlet_centre_xz, _layout.lawn_radius,
		VillageLayout.HERO_DOOR_STOOP, _layout.pond_center)


static func terrain_stats_from_lut(
		lut: Dictionary, centre: Vector2, radius: float,
		hero_xz: Vector2, pond_xz: Vector2) -> Dictionary:
	## min / max height over LUT nodes inside the disc; max slope from central differences on
	## nodes whose four neighbours are also inside (LUT cell = mesh step, so it is the mesh slope);
	## hero / pond heights by bilinear lookup.
	var origin: Vector2 = lut["origin_xz"]
	var cell: float = maxf(float(lut["cell_m"]), 0.001)
	var cols: int = lut["cols"]
	var rows: int = lut["rows"]
	var data: PackedFloat32Array = lut["data"]
	var r2 := radius * radius
	var min_h := INF
	var max_h := -INF
	var max_grad2 := 0.0
	for row in range(rows):
		for col in range(cols):
			var xz := origin + Vector2(float(col) * cell, float(row) * cell)
			if xz.distance_squared_to(centre) >= r2:
				continue
			var h := data[row * cols + col]
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)
			if col < 1 or row < 1 or col > cols - 2 or row > rows - 2:
				continue
			if (xz + Vector2(cell, 0)).distance_squared_to(centre) >= r2 \
					or (xz - Vector2(cell, 0)).distance_squared_to(centre) >= r2 \
					or (xz + Vector2(0, cell)).distance_squared_to(centre) >= r2 \
					or (xz - Vector2(0, cell)).distance_squared_to(centre) >= r2:
				continue
			var dx := (data[row * cols + col + 1] - data[row * cols + col - 1]) / (2.0 * cell)
			var dz := (data[(row + 1) * cols + col] - data[(row - 1) * cols + col]) / (2.0 * cell)
			max_grad2 = maxf(max_grad2, dx * dx + dz * dz)
	return {
		"min_h": min_h if is_finite(min_h) else 0.0,
		"max_h": max_h if is_finite(max_h) else 0.0,
		"max_slope_deg": rad_to_deg(atan(sqrt(max_grad2))),
		"hero_h": VillageTerrain.lut_sample(lut, hero_xz),
		"pond_basin_h": VillageTerrain.lut_sample(lut, pond_xz),
	}


func hud_text() -> String:
	## Terrain stats from the LUT on screen, then (ivy-82zn.14.8) every knob beyond its gentle
	## limit and every knob the height caps cut short. Nothing is blocked; the HUD only says so.
	var s := compute_terrain_stats()
	var t := "(no stats)"
	if not s.is_empty():
		t = (
			"h: %.3f … %.3f m  |  slope_max: %.1f° (%.0f m grid)\nhero pad: %.3f m  |  pond basin: %.3f m"
			% [s["min_h"], s["max_h"], s["max_slope_deg"], _shown_step_m, s["hero_h"], s["pond_basin_h"]]
		)
		t += "\n" + hill_hud_line()
	var over := VillageTerrainKnobSpec.gentle_limit_violations(_params)
	if not over.is_empty():
		t += "\nBeyond gentle limits: " + ", ".join(over)
	var caps := VillageTerrainKnobSpec.relief_cap_notes(_params)
	if not caps.is_empty():
		t += "\nCapped: " + ", ".join(caps)
	return t


## Tallest cottage ridge: VillageBackdrop.WALL_TOP + Roof_RoundTiles_4x6 / 4x8 glTF max y.
const COTTAGE_RIDGE_M := VillageBackdrop.WALL_TOP + 3.7178683280944824


func hill_hud_line() -> String:
	## ivy-82zn.14.10: the hero-to-village-edge fall the human asked for, against one cottage, read
	## from the LUT on screen (no extra sampling). The outermost cottage = farthest from the stoop.
	if _layout == null or _terrain_lut.is_empty() or _layout.cottages.is_empty():
		return "hill: (no village)"
	var far_c := Vector2.ZERO
	var far_d := -1.0
	for spec: Dictionary in _layout.cottages:
		var c := spec["centre"] as Vector2
		var d := c.distance_to(VillageLayout.HERO_DOOR_STOOP)
		if d > far_d:
			far_d = d
			far_c = c
	var hero_h := VillageTerrain.lut_sample(_terrain_lut, VillageLayout.HERO_DOOR_STOOP)
	var fall := hero_h - VillageTerrain.lut_sample(_terrain_lut, far_c)
	var verdict := "≥" if fall >= COTTAGE_RIDGE_M else "<"
	return "hill: crest %.2f m  |  fall to outermost cottage %.2f m %s cottage ridge %.2f m" % [
		hero_h, fall, verdict, COTTAGE_RIDGE_M]


func _update_hud() -> void:
	if _hud_label == null:
		return
	_hud_label.text = hud_text()


func _update_status() -> void:
	if _status_label == null:
		return
	var s := rebuild_status()
	_status_label.text = s
	_status_label.get_parent().visible = not s.is_empty()


# ── Markers ───────────────────────────────────────────────────────────────────

const _MARKER_NAMES := ["HeroStandIn", "PondWater", "PondBank"]


func _refresh_markers() -> void:
	## Re-seat markers on the refined terrain (they were only built on layout change before).
	for c in _stage.get_children():
		var n := str(c.name)
		if n in _MARKER_NAMES or n.begins_with("Cottage_"):
			c.name = "_removing_%s" % n
			c.queue_free()
	_build_markers(_build_params)


func _build_markers(params: VillageTerrainParams) -> void:
	## Context markers placed ON the terrain (sample_y heights, ~10 samples).
	## Hero stoop box, pond water disc, cottage footprints.
	var t_seed := VillageTerrain.terrain_seed(_layout, params)

	# Hero stoop marker.
	var hero := VillageLayout.HERO_DOOR_STOOP
	var hero_y := VillageTerrain.sample_y(hero, _layout, params, t_seed)
	var hero_box := MeshInstance3D.new()
	hero_box.name = "HeroStandIn"
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 2.2, 1.2)
	hero_box.mesh = box
	hero_box.position = Vector3(hero.x, hero_y + 1.1, hero.y)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.88, 0.72, 0.50)
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	hero_box.material_override = hmat
	_stage.add_child(hero_box)

	# Pond: water disc at water level, bank ring.
	var pond := _layout.pond_center
	if pond != Vector2.ZERO:
		_build_pond_marker(pond, t_seed, params)

	# Cottage footprint slabs at pad height.
	var ci := 0
	for spec: Dictionary in _layout.cottages:
		if ci >= 6:
			break
		var rect := VillageBackdrop.cottage_exterior_rect(spec)
		var centre := Vector2(rect.get_center().x, rect.get_center().y)
		var sz := rect.size
		var pad_y := VillageTerrain.sample_y(centre, _layout, params, t_seed)
		var cottage := MeshInstance3D.new()
		cottage.name = "Cottage_%d" % ci
		var cm := BoxMesh.new()
		cm.size = Vector3(sz.x, 0.12, sz.y)
		cottage.mesh = cm
		cottage.position = Vector3(centre.x, pad_y + 0.06, centre.y)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.82, 0.78, 0.70)
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		cottage.material_override = cmat
		_stage.add_child(cottage)
		ci += 1
	_update_marker_visibility()


func _build_pond_marker(pond: Vector2, t_seed: int, params: VillageTerrainParams) -> void:
	## Renders the pond basin context:
	## - Water disc at water level (visible below rim, above basin floor).
	## - Bank ring outline at sample_y of bank.
	var water_y := _compute_pond_water_y(pond, t_seed, params)

	# Water disc.
	var water_r := VillagePondSite.MEAN_WATER_RADIUS_M
	var water_disc := MeshInstance3D.new()
	water_disc.name = "PondWater"
	var cyl := CylinderMesh.new()
	cyl.height = 0.06
	cyl.top_radius = water_r
	cyl.bottom_radius = water_r
	cyl.radial_segments = 48
	water_disc.mesh = cyl
	water_disc.position = Vector3(pond.x, water_y, pond.y)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.20, 0.45, 0.72, 0.82)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_disc.material_override = wmat
	_stage.add_child(water_disc)

	# Bank ring (thin outline at bank_outer height to show basin edge).
	var bank_r := VillagePondSite.BANK_OUTER_M
	var rim_pt := pond + Vector2(bank_r * 0.9, 0.0)
	var rim_y := VillageTerrain.sample_y(rim_pt, _layout, params, t_seed)
	var bank_ring := MeshInstance3D.new()
	bank_ring.name = "PondBank"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = bank_r - 0.3
	ring_mesh.outer_radius = bank_r + 0.3
	ring_mesh.rings = 64
	bank_ring.mesh = ring_mesh
	bank_ring.position = Vector3(pond.x, rim_y + 0.08, pond.y)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.60, 0.50, 0.35)
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	bank_ring.material_override = rmat
	_stage.add_child(bank_ring)


func _compute_pond_water_y(pond: Vector2, t_seed: int, params: VillageTerrainParams) -> float:
	## Marker only (the village host builds the production water). VillageTerrain.pond_water_y with
	## the bank-outline minimum taken over every 24th outline point — 30 sample_y calls instead of
	## 720, so the marker refresh stays inside the playground's frame budget (ivy-82zn.14.10).
	var outline := VillagePondShape.at(pond).bank_outer_outline_world_xz()
	var lo := INF
	for i in range(0, outline.size(), 24):
		lo = minf(lo, VillageTerrain.sample_y(outline[i], _layout, params, t_seed))
	return VillageTerrain.pond_water_y(_layout, params, t_seed, lo)


# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	# Left panel: knob panel.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	layer.add_child(margin)
	var host := PlaygroundKnobHost.village_terrain()
	_knob_panel = KnobPanel.new()
	_knob_panel.build_from_spec(
		VillageTerrainKnobSpec.all_knobs(), _params, VillageTerrainParams.presets(), host)
	margin.add_child(_knob_panel)
	_knob_panel.knob_changed.connect(_on_knob_changed)
	_knob_panel.variant_changed.connect(_on_variant_changed)
	_knob_panel.preset_selected.connect(_on_preset_selected)
	_knob_panel.reset_requested.connect(_on_reset_production)
	_knob_panel.copy_requested.connect(_on_copy_settings)

	# Right panel: camera presets.
	layer.add_child(_make_camera_panel())

	# Bottom-left: debug controls.
	layer.add_child(_make_debug_panel())

	# Bottom strip: HUD stats.
	layer.add_child(_make_hud_panel())

	# Top centre: 'rebuilding' indicator (hidden when idle).
	layer.add_child(_make_status_panel())

	# Clicks and scrolls over any panel stay with the UI (ivy-82zn.14.8).
	_ui_shields.clear()
	_ui_shields.append(_knob_panel)
	_collect_panel_shields(layer)


func _collect_panel_shields(node: Node) -> void:
	for c in node.get_children():
		if c is PanelContainer:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_STOP
			_ui_shields.append(c as Control)
		elif c is Control:
			_collect_panel_shields(c)


func _make_status_panel() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	margin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	margin.add_theme_constant_override("margin_top", 16)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var lbl := Label.new()
	lbl.name = "RebuildStatus"
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	panel.add_child(lbl)
	_status_label = lbl
	_update_status()
	return margin


func _make_camera_panel() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Camera"
	col.add_child(title)
	col.add_child(_labeled_button("CamSun", func(): _apply_camera_preset("camsun")))
	col.add_child(_labeled_button("Edge outward", func(): _apply_camera_preset("edge_outward")))
	col.add_child(_labeled_button("Edge inward", func(): _apply_camera_preset("edge_inward")))
	col.add_child(_labeled_button("Raking light", func(): _apply_camera_preset("raking")))
	col.add_child(_labeled_button("CamTop", func(): _apply_camera_preset("top")))
	col.add_child(_labeled_button("Hero approach", func(): _apply_camera_preset("hero_approach")))
	col.add_child(_labeled_button("Pond oblique", func(): _apply_camera_preset("pond_oblique")))
	col.add_child(_labeled_button("Free orbit", func(): _apply_camera_preset("orbit")))
	return margin


func _make_debug_panel() -> Control:
	## Debug-only controls: relief mode, contour spacing, vertical exaggeration.
	## These are NOT in VillageTerrainParams and do NOT appear in Copy Settings JSON.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	# Production lawn grass on the terrain (production builder + 1 m LUT).
	var grass_chk := CheckBox.new()
	grass_chk.name = "GrassToggle"
	grass_chk.text = "Grass"
	grass_chk.button_pressed = _grass_on
	grass_chk.toggled.connect(_set_grass)
	col.add_child(grass_chk)
	# Production village (cottages, paths + stones, pond water + bank, bushes, flowers).
	var village_chk := CheckBox.new()
	village_chk.name = "VillageToggle"
	village_chk.text = "Village"
	village_chk.button_pressed = _village_on
	village_chk.toggled.connect(_set_village)
	col.add_child(village_chk)
	var hint := Label.new()
	hint.name = "CameraHint"
	hint.text = "Tab: mouse-look · Click: move pivot · Wheel: zoom\nWASD/arrows: rotate · R/Home: reset"
	hint.add_theme_font_size_override("font_size", 11)
	col.add_child(hint)

	var title := Label.new()
	title.text = "Debug (playground only)"
	col.add_child(title)

	# Relief debug toggle (material swap only).
	var chk := CheckBox.new()
	chk.text = "Relief debug view"
	chk.button_pressed = _debug_relief_on
	chk.toggled.connect(_set_debug_relief)
	col.add_child(chk)

	# Contour spacing slider.
	var contour_row := HBoxContainer.new()
	var contour_lbl := Label.new()
	contour_lbl.text = "Contour (m):"
	contour_row.add_child(contour_lbl)
	var contour_sl := HSlider.new()
	contour_sl.min_value = 0.05
	contour_sl.max_value = 1.0
	contour_sl.step = 0.05
	contour_sl.value = _debug_contour_m
	contour_sl.custom_minimum_size = Vector2(120, 0)
	contour_sl.value_changed.connect(_set_debug_contour)
	contour_row.add_child(contour_sl)
	col.add_child(contour_row)

	# Vertical exaggeration slider (clearly labeled debug-only).
	var ve_row := HBoxContainer.new()
	var ve_lbl := Label.new()
	ve_lbl.text = "VE (debug!):"
	ve_row.add_child(ve_lbl)
	var ve_sl := HSlider.new()
	ve_sl.min_value = 1.0
	ve_sl.max_value = 8.0
	ve_sl.step = 0.5
	ve_sl.value = _debug_ve
	ve_sl.custom_minimum_size = Vector2(120, 0)
	ve_sl.value_changed.connect(_set_debug_ve)
	ve_row.add_child(ve_sl)
	col.add_child(ve_row)

	_debug_panel_container = margin
	return margin


func _make_hud_panel() -> Control:
	## Bottom strip: terrain stats HUD.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var lbl := Label.new()
	lbl.name = "HUDLabel"
	panel.add_child(lbl)
	_hud_label = lbl
	_update_hud()
	return margin


func _labeled_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


# ── Knob callbacks ────────────────────────────────────────────────────────────

func _on_knob_changed(name: String, value: Variant) -> void:
	if name == "layout_seed":
		_params.layout_seed = int(value)
		_rebuild_layout_and_stage()
		if _knob_panel:
			_knob_panel.refresh_values()
		return
	_params.set(name, value)
	_update_hud()  # limit lines follow the knob at once; stats follow the rebuild
	if name in MATERIAL_ONLY_KNOBS:
		_apply_material_knobs()
		return
	_request_rebuild()


func _on_variant_changed(v: int) -> void:
	_params.variant = v
	if _knob_panel:
		_knob_panel.set_variant(v)
	_request_rebuild()


func _on_preset_selected(name: String) -> void:
	_params.apply_preset(name)
	if _knob_panel:
		_knob_panel.set_variant(_params.variant)
		_knob_panel.refresh_values()
	_rebuild_layout_and_stage()


func _on_reset_production() -> void:
	var seed := _params.layout_seed
	_params.reset_to_production()
	_params.layout_seed = seed
	if _knob_panel:
		_knob_panel.set_variant(0)
		_knob_panel.refresh_values()
	_rebuild_layout_and_stage()


func _on_copy_settings() -> void:
	DisplayServer.clipboard_set(_params.to_json_block())


# ── Fog ───────────────────────────────────────────────────────────────────────

func _apply_playground_fog() -> void:
	if _layout == null:
		return
	if _sky_sun != null:
		_sky_sun.set_fog_depth(_layout.fog_begin, _layout.fog_end)
		_sky_sun.set_fog_anchor(ForestPlaygroundCamera.hero_fog_anchor_world())
		return
	if _world_env == null or _world_env.environment == null:
		return
	var env := _world_env.environment
	env.fog_enabled = false
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_length = 192.0
	env.volumetric_fog_sky_affect = _world_fog_params.sky_affect_cap
	env.volumetric_fog_albedo = env.fog_light_color
	var anchor := ForestPlaygroundCamera.hero_fog_anchor_world()
	var pale := SkySun.pale_horizon_haze_color(0.32, 1.0)
	if _world_fog_volume == null:
		_world_fog_volume = WorldFogVolume.create_volume(anchor, _world_fog_params, pale)
		add_child(_world_fog_volume)
	else:
		WorldFogVolume.apply_params(_world_fog_volume, anchor, _world_fog_params, pale)


func _disable_fog_for_top_view() -> void:
	## CamTop should not be fogged — fog distance is < lawn_radius from top.
	if _sky_sun != null:
		_sky_sun.set_fog_depth(500.0, 1000.0)
		return
	if _world_env != null and _world_env.environment != null:
		_world_env.environment.fog_enabled = false
		_world_env.environment.volumetric_fog_enabled = false


# ── Cameras ───────────────────────────────────────────────────────────────────

func _apply_camera_preset(name: String) -> void:
	## Every preset lands in the orbit state (pivot, yaw, pitch, radius), so the DebugCamera
	## controls carry on from the preset view, and R / Home come back to it.
	_set_camera_preset_view(name)
	if name != "orbit":
		_adopt_camera_as_orbit()
	_apply_orbit_camera()
	_store_home()


func _set_camera_preset_view(name: String) -> void:
	_last_preset = name
	var aim := ForestPlaygroundCamera.aim_point()

	# Restore normal fog for most presets; disable for top.
	if name != "top":
		_apply_playground_fog()
	else:
		_disable_fog_for_top_view()

	if name == "orbit":
		_orbit_yaw = 0.0
		_orbit_pitch = 0.031415927
		_orbit_radius = 8.01 * ForestPlaygroundCamera.GENERATED_RIG_SCALE
		_pivot = aim
		_gliding = false
		return
	match name:
		"edge_outward", "edge-outward":
			_apply_edge_outward()
		"edge_inward", "edge-inward":
			_apply_edge_inward()
		"top", "camtop":
			_apply_top_camera()
		"raking", "raking_light", "rake":
			_apply_raking_camera()
		"hero_approach", "hero-approach":
			_apply_hero_approach()
		"pond_oblique", "pond-oblique":
			_apply_pond_oblique()
		_:
			ForestPlaygroundCamera.apply_camsun(_camera)


func _apply_orbit_camera() -> void:
	if _camera == null:
		return
	var pivot := _current_pivot()
	_orbit_pitch = DebugCamera.clamp_pitch(_orbit_pitch, _orbit_radius, pivot.y)
	_camera.global_transform = DebugCamera.solve(pivot, _orbit_yaw, _orbit_pitch, _orbit_radius)


func _apply_top_camera() -> void:
	var off := ForestPlaygroundCamera.backdrop_origin()
	var g := _layout.hamlet_centre_xz
	var gc := Vector3(g.x + off.x, 0.0, g.y + off.z)
	_camera.global_position = gc + Vector3(0.0, 75.0, 0.001)
	_camera.look_at(gc, Vector3.FORWARD)
	_camera.fov = 45.0


func _apply_raking_camera() -> void:
	## Low-angle oblique: eye at lawn edge ~3 m high, looking across the centre.
	## Long shadows make even subtle bumps obvious (primary feel-judging view).
	var off := ForestPlaygroundCamera.backdrop_origin()
	var g := _layout.hamlet_centre_xz
	var lawn_r := _layout.lawn_radius
	# Eye from south-west (azimuth ~225°, low elevation).
	var az_rad := deg_to_rad(225.0)
	var eye_xz := g + Vector2(sin(az_rad), cos(az_rad)) * (lawn_r - 2.0)
	var eye := Vector3(eye_xz.x + off.x, 3.5, eye_xz.y + off.z)
	var centre := Vector3(g.x + off.x, 0.0, g.y + off.z)
	# Look toward the opposite (north-east) edge for maximum cross-terrain view.
	var look_xz := g + Vector2(sin(az_rad + PI), cos(az_rad + PI)) * lawn_r * 0.5
	var look := Vector3(look_xz.x + off.x, 0.5, look_xz.y + off.z)
	_camera.global_position = eye
	_camera.look_at(look, Vector3.UP)
	_camera.fov = 75.0


func _apply_edge_outward() -> void:
	var off := ForestPlaygroundCamera.backdrop_origin()
	var hero := VillageLayout.HERO_DOOR_STOOP
	var g := _layout.hamlet_centre_xz
	var lawn_r := _layout.lawn_radius
	var margin := 2.0
	var allowed := maxf(lawn_r - margin, 2.0)
	var dir_in := (hero - g).normalized() if hero.distance_to(g) > 0.1 else Vector2(0, -1)
	var dir_out := -dir_in
	var edge := Vector3(
		g.x + dir_out.x * allowed, 5.0, g.y + dir_out.y * allowed) + off
	var look := Vector3(
		edge.x + dir_out.x * 150.0, 1.5, edge.z + dir_out.y * 150.0)
	_camera.global_position = edge
	_camera.look_at(look, Vector3.UP)


func _apply_edge_inward() -> void:
	var off := ForestPlaygroundCamera.backdrop_origin()
	var hero := VillageLayout.HERO_DOOR_STOOP
	var g := _layout.hamlet_centre_xz
	var dir_in := (hero - g).normalized()
	var lawn_r := _layout.lawn_radius
	var edge := Vector3(g.x + dir_in.x * (lawn_r - 2.0), 5.0, g.y + dir_in.y * (lawn_r - 2.0)) + off
	var look := Vector3(hero.x, 1.2, hero.y) + off
	_camera.global_position = edge
	_camera.look_at(look, Vector3.UP)


func _apply_hero_approach() -> void:
	## Eye on hero approach path ~12 m out, 1.6 m high, looking at stoop.
	var off := ForestPlaygroundCamera.backdrop_origin()
	var hero := VillageLayout.HERO_DOOR_STOOP
	var g := _layout.hamlet_centre_xz
	var to_hero := (hero - g).normalized() if hero.distance_to(g) > 0.1 else Vector2(0, -1)
	var eye_xz := hero - to_hero * 12.0
	var eye := Vector3(eye_xz.x + off.x, 1.6, eye_xz.y + off.z)
	var target := Vector3(hero.x + off.x, 0.8, hero.y + off.z)
	_camera.global_position = eye
	_camera.look_at(target, Vector3.UP)
	_camera.fov = 60.0


func _apply_pond_oblique() -> void:
	## 30° oblique view looking into the basin from ~20 m out at 4 m height.
	var off := ForestPlaygroundCamera.backdrop_origin()
	var pond := _layout.pond_center
	if pond == Vector2.ZERO:
		_apply_camera_preset("top")
		return
	var hero := VillageLayout.HERO_DOOR_STOOP
	var dir := (pond - hero).normalized() if pond.distance_to(hero) > 0.1 else Vector2(1, 0)
	var dist := 22.0
	var eye_xz := pond - dir * dist
	## ivy-82zn.14.10: heights relative to the pond's ground (the village sits below world 0 on the
	## hill); same view as before on flat ground (eye 4.3 m above the basin, target 0.3 m below).
	var ground := _terrain_surface_y(Vector3(pond.x + off.x, 0.0, pond.y + off.z))
	var eye := Vector3(eye_xz.x + off.x, ground + 4.0, eye_xz.y + off.z)
	var target := Vector3(pond.x + off.x, ground - 0.3, pond.y + off.z)
	_camera.global_position = eye
	_camera.look_at(target, Vector3.UP)
	_camera.fov = 55.0


# ── CLI helpers ───────────────────────────────────────────────────────────────

func _has_user_arg(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


func _parse_out_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return arg.get_slice("=", 1)
	return ""


func _parse_arg_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


func _parse_perf_knob_arg() -> Array:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf-knob="):
			var kv := arg.get_slice("=", 1).split(":")
			if kv.size() == 2:
				return [kv[0], kv[1]]
	return []


func _await_refined() -> void:
	var cap := 6000
	while is_refining() and cap > 0:
		cap -= 1
		await get_tree().process_frame


func _parse_camera_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camera="):
			return arg.get_slice("=", 1).to_lower()
	return "camsun"


func _capture_png(path: String) -> void:
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var err: Error = ERR_CANT_CREATE
	if img != null:
		err = img.save_png(path)
	if err == OK:
		print("[village-terrain-playground] saved ", path)
	else:
		printerr("[village-terrain-playground] save failed ", err)
	_capture_done_fn.call(err)
