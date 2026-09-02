extends Node

## AS-5 investigation — grow overrun + fps dip root-cause probes.
##   Godot res://tools/profile_as5_investigate.tscn

const _MAIN_SCENE := "res://src/main/main.tscn"
const _GROW_TARGET_DAY := 150.0
const _TICKS_PER_DAY := 24.0
const _SAMPLE_FRAMES := 180
const _WARMUP_FRAMES := 90

var _main: Node = null


func _ready() -> void:
	await _probe_grow_tick_delivery()
	await _probe_fps_breakdown()
	print("[as5-inv] done")
	get_tree().quit(0)


func _spawn_main(script_driven: bool) -> void:
	if _main != null:
		_main.queue_free()
		_main = null
		for _i in range(5):
			await get_tree().process_frame
	var ps := load(_MAIN_SCENE) as PackedScene
	_main = ps.instantiate()
	_main.set("script_driven", script_driven)
	add_child(_main)
	for _i in range(30):
		await get_tree().process_frame


func _probe_grow_tick_delivery() -> void:
	print("[as5-inv] === grow tick delivery (HUD on, Grow speed) ===")
	await _spawn_main(false)
	var sim: Node = _main.get_node("Sim")
	var clock: SimClock = sim.get_clock()
	clock.set_speed(SimClock.Speed.GROW)

	var t0_ms := Time.get_ticks_msec()
	var last_log_day := -1.0
	var frame_times: PackedFloat32Array = PackedFloat32Array()
	while clock.game_day < _GROW_TARGET_DAY:
		var ft0 := Time.get_ticks_usec()
		await get_tree().process_frame
		var ft_ms := (Time.get_ticks_usec() - ft0) / 1000.0
		frame_times.append(ft_ms)
		var day := clock.game_day
		if int(day / 10.0) > int(last_log_day / 10.0):
			last_log_day = day
			var elapsed := (Time.get_ticks_msec() - t0_ms) / 1000.0
			var ticks := clock.tick_index
			var eff := float(ticks) / maxf(elapsed, 0.001)
			print(
				"[as5-inv]   day=%.0f ticks=%d elapsed=%.1fs eff=%.2f ticks/s (target 20)"
				% [day, ticks, elapsed, eff]
			)

	var grow_ms := Time.get_ticks_msec() - t0_ms
	var ticks_final := clock.tick_index
	var target_ticks := int(_GROW_TARGET_DAY * _TICKS_PER_DAY)
	var eff_final := float(ticks_final) / (grow_ms / 1000.0)
	var theory_s: float = _GROW_TARGET_DAY * sim.params.speed_grow
	print(
		"[as5-inv] grow total: %.2fs theory=%.2fs ticks=%d target=%d eff=%.3f ticks/s"
		% [grow_ms / 1000.0, theory_s, ticks_final, target_ticks, eff_final]
	)
	_summarize_frame_times("grow", frame_times)

	# Pre-timer bleed: how many ticks during the 30-frame spawn warmup?
	await _spawn_main(false)
	sim = _main.get_node("Sim")
	clock = sim.get_clock()
	await get_tree().process_frame
	var ticks_after_ready := clock.tick_index
	for _i in range(29):
		await get_tree().process_frame
	print(
		"[as5-inv] spawn warmup bleed: %d ticks in 30 frames (day=%.3f)"
		% [clock.tick_index - ticks_after_ready, clock.game_day]
	)


func _probe_fps_breakdown() -> void:
	print("[as5-inv] === fps breakdown at day 150.25 ===")

	# A: full HUD path (matches first profile run end-state)
	await _spawn_main(false)
	await _advance_to_canonical()
	var hud_on := await _sample_frames("hud_on+force_draw", true, true)

	# B: script_driven — no HUD/dev overlay, same plant state via advance_ticks
	await _spawn_main(true)
	await _advance_to_canonical()
	var lean := await _sample_frames("script_driven+force_draw", true, true)

	# C: process_frame only (no force_draw) — does measurement method inflate variance?
	await _sample_frames("script_driven+process_only", false, true)

	print("[as5-inv] compare worst fps: hud=%.1f lean=%.1f" % [hud_on["worst_fps"], lean["worst_fps"]])


func _advance_to_canonical() -> void:
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
	var ticks := int(round((_GROW_TARGET_DAY + 0.25) * _TICKS_PER_DAY))
	if sim.has_method("advance_ticks"):
		sim.advance_ticks(ticks)
	for _i in range(5):
		await get_tree().process_frame
	var cam_rig := _main.get_node_or_null("World/CameraRig")
	if cam_rig != null and cam_rig.has_method("select"):
		cam_rig.select(0)


func _sample_frames(label: String, use_force_draw: bool, print_hist: bool) -> Dictionary:
	var samples: PackedFloat32Array = PackedFloat32Array()
	for _i in range(_WARMUP_FRAMES):
		if use_force_draw and RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		await get_tree().process_frame

	for _i in range(_SAMPLE_FRAMES):
		var t0 := Time.get_ticks_usec()
		if use_force_draw and RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		await get_tree().process_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)

	var sorted := samples.duplicate()
	sorted.sort()
	var n := sorted.size()
	var mean := 0.0
	for v in samples:
		mean += v
	mean /= float(n)
	var p50 := sorted[int(n * 0.50)]
	var p95 := sorted[int(n * 0.95)]
	var p99 := sorted[mini(int(n * 0.99), n - 1)]
	var worst := sorted[n - 1]
	var below_60 := 0
	for v in samples:
		if v > 1000.0 / 60.0:
			below_60 += 1
	var worst_idx := 0
	for i in range(n):
		if samples[i] >= worst - 0.001:
			worst_idx = i

	print(
		"[as5-inv] %s: mean=%.2fms p50=%.2f p95=%.2f p99=%.2f worst=%.2f (frame %d) below60=%d/%d"
		% [label, mean, p50, p95, p99, worst, worst_idx, below_60, n]
	)
	if print_hist and below_60 > 0:
		var spikes := PackedStringArray()
		for i in range(n):
			if samples[i] > 1000.0 / 60.0:
				spikes.append("%d:%.1fms" % [i, samples[i]])
				if spikes.size() >= 8:
					break
		print("[as5-inv]   first spikes: ", ", ".join(spikes))

	return {
		"mean_fps": 1000.0 / mean,
		"worst_fps": 1000.0 / worst,
		"worst_ms": worst,
		"below_60": below_60,
	}


func _summarize_frame_times(label: String, frame_times: PackedFloat32Array) -> void:
	if frame_times.is_empty():
		return
	var sorted := frame_times.duplicate()
	sorted.sort()
	var n := sorted.size()
	var mean := 0.0
	for v in frame_times:
		mean += v
	mean /= float(n)
	print(
		"[as5-inv] %s frame_ms: mean=%.2f p95=%.2f worst=%.2f"
		% [label, mean, sorted[int(n * 0.95)], sorted[n - 1]]
	)
