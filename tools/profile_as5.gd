extends Node

## Headless AS-5 performance probe (DESIGN.md).
##
## Usage (from project root):
##   Godot res://tools/profile_as5.tscn
##
## Phase 1 — Grow wall-clock at Grow speed with default HUD (M3 agency UI).
##   Ceiling: 150 game-days × speed_grow × 1.02 (2% headroom for PSO compile
##   spikes and OS scheduling; tick delivery stays at ~20 ticks/s).
##
## Phase 2 — Render FPS at day-150.25 full coverage, script_driven (no HUD/dev
##   overlay). AS-5 targets plant + tower rendering, not tuning chrome.

const _MAIN_SCENE := "res://src/main/main.tscn"
const _GROW_TARGET_DAY := 150.0
const _CANONICAL_DAY := 150.25
const _TICKS_PER_DAY := 24.0
const _GROW_TOLERANCE := 1.02
const _FPS_FLOOR := 60.0
const _WARMUP_FRAMES := 90
const _SAMPLE_FRAMES := 180

var _main: Node = null
var _failures: PackedStringArray = []


func _ready() -> void:
	var grow := await _measure_grow_run()
	var fps := await _measure_render_fps()
	_print_summary(grow, fps)
	if _failures.is_empty():
		print("[as5] PASS")
		get_tree().quit(0)
	else:
		for msg in _failures:
			printerr("[as5] FAIL: ", msg)
		get_tree().quit(1)


func _spawn_main(script_driven: bool) -> void:
	if _main != null:
		_main.queue_free()
		_main = null
		for _i in range(5):
			await get_tree().process_frame
	var ps := load(_MAIN_SCENE) as PackedScene
	if ps == null:
		printerr("[as5] failed to load ", _MAIN_SCENE)
		get_tree().quit(2)
		return
	_main = ps.instantiate()
	_main.set("script_driven", script_driven)
	add_child(_main)
	for _i in range(30):
		await get_tree().process_frame


func _measure_grow_run() -> Dictionary:
	await _spawn_main(false)
	var sim: Node = _main.get_node("Sim")
	var clock: SimClock = sim.get_clock()
	var tips: TipManager = sim.tips
	clock.set_speed(SimClock.Speed.GROW)

	var theory_ms: int = int(_GROW_TARGET_DAY * sim.params.speed_grow * 1000.0)
	var ceiling_ms: int = int(float(theory_ms) * _GROW_TOLERANCE)

	var t0_ms := Time.get_ticks_msec()
	var max_live := 0
	while clock.game_day < _GROW_TARGET_DAY:
		await get_tree().process_frame
		max_live = maxi(max_live, tips.live_count())

	var grow_ms := Time.get_ticks_msec() - t0_ms
	var cap_hard: int = sim.params.tip_cap_hard
	print(
		"[as5] grow day=%.2f wall_clock=%.2fs theory=%.2fs ceiling=%.2fs max_live=%d"
		% [
			clock.game_day,
			grow_ms / 1000.0,
			theory_ms / 1000.0,
			ceiling_ms / 1000.0,
			max_live,
		]
	)

	if grow_ms > ceiling_ms:
		_failures.append(
			"grow wall-clock %.1fs > ceiling %.1fs (theory %.1fs × %.0f%%)"
			% [
				grow_ms / 1000.0,
				ceiling_ms / 1000.0,
				theory_ms / 1000.0,
				(_GROW_TOLERANCE - 1.0) * 100.0,
			]
		)
	if max_live > cap_hard:
		_failures.append("max live tips %d > tip_cap_hard %d" % [max_live, cap_hard])

	return {
		"grow_ms": grow_ms,
		"max_live_tips": max_live,
		"game_day": clock.game_day,
		"ceiling_ms": ceiling_ms,
	}


func _measure_render_fps() -> Dictionary:
	await _spawn_main(true)
	var sim: Node = _main.get_node("Sim")
	var clock: SimClock = sim.get_clock()
	clock.set_speed(SimClock.Speed.PAUSE)
	if sim.has_method("set_seed_index"):
		sim.set_seed_index(2)
	if sim.has_method("reseed"):
		sim.reseed()
	var world: Node = _main.get_node("World")
	if world.has_method("set_seed_index"):
		world.set_seed_index(2)
	var ticks := int(round(_CANONICAL_DAY * _TICKS_PER_DAY))
	if sim.has_method("advance_ticks"):
		sim.advance_ticks(ticks)
	for _i in range(5):
		await get_tree().process_frame

	var cam_rig := _main.get_node_or_null("World/CameraRig")
	if cam_rig != null and cam_rig.has_method("select"):
		cam_rig.select(0)

	for _i in range(_WARMUP_FRAMES):
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		await get_tree().process_frame

	var samples_ms: PackedFloat32Array = PackedFloat32Array()
	samples_ms.resize(_SAMPLE_FRAMES)
	for i in range(_SAMPLE_FRAMES):
		var t0 := Time.get_ticks_usec()
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		await get_tree().process_frame
		samples_ms[i] = float(Time.get_ticks_usec() - t0) / 1000.0

	var worst_ms := 0.0
	var total_ms := 0.0
	var below_60 := 0
	for dt in samples_ms:
		worst_ms = maxf(worst_ms, dt)
		total_ms += dt
		if dt > 1000.0 / _FPS_FLOOR:
			below_60 += 1
	var mean_ms := total_ms / float(_SAMPLE_FRAMES)
	var mean_fps := 1000.0 / mean_ms if mean_ms > 0.0 else 0.0
	var worst_fps := 1000.0 / worst_ms if worst_ms > 0.0 else 0.0

	print(
		"[as5] render fps mean=%.1f worst=%.1f below60=%d/%d (script_driven, floor %.0f)"
		% [mean_fps, worst_fps, below_60, _SAMPLE_FRAMES, _FPS_FLOOR]
	)
	print("[as5] render frame_ms mean=%.2f worst=%.2f" % [mean_ms, worst_ms])

	if worst_fps < _FPS_FLOOR:
		_failures.append(
			"worst-case fps %.1f < floor %.0f" % [worst_fps, _FPS_FLOOR]
		)

	return {
		"mean_fps": mean_fps,
		"worst_fps": worst_fps,
		"mean_ms": mean_ms,
		"worst_ms": worst_ms,
	}


func _print_summary(grow: Dictionary, fps: Dictionary) -> void:
	print("[as5] ── summary ──")
	print(
		"[as5]   grow: %.2fs (ceiling %.2fs), max_live=%d"
		% [grow["grow_ms"] / 1000.0, grow["ceiling_ms"] / 1000.0, grow["max_live_tips"]]
	)
	print(
		"[as5]   render: mean %.1f fps, worst %.1f fps"
		% [fps["mean_fps"], fps["worst_fps"]]
	)
