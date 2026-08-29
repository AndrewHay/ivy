class_name UiScriptExecutor
extends RefCounted

## Shared UI-script verb dispatcher for run_ui_script.gd and acceptance_harness.gd.

const _CoverageMetric = preload("res://src/metrics/coverage.gd")
const _LeafColourMetric = preload("res://src/metrics/leaf_colour_metric.gd")
const _BlacklistAssertions = preload("res://src/metrics/blacklist.gd")
const _UiScriptVerbs = preload("res://tools/ui_script_verbs.gd")
const _PRESENT_TIMEOUT_MS := 4000


static func present_fresh_frame(tree: SceneTree) -> bool:
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
		return true
	var drawn := [false]
	var on_draw := func() -> void: drawn[0] = true
	RenderingServer.frame_post_draw.connect(on_draw, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + _PRESENT_TIMEOUT_MS
	while not drawn[0] and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	if RenderingServer.frame_post_draw.is_connected(on_draw):
		RenderingServer.frame_post_draw.disconnect(on_draw)
	return drawn[0]


static func run_script(
	tree: SceneTree,
	main: Node,
	script_path: String,
	outdir: String
) -> int:
	var lines := FileAccess.get_file_as_string(script_path).split("\n")
	var step := 0
	var shot := 0
	print("[ui-script] script=", script_path, "  outdir=", outdir, "  steps=", lines.size())
	for raw in lines:
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		step += 1
		var err := await _dispatch_line(tree, main, line, step, shot, outdir)
		if err != OK:
			return err
		if line.begins_with("SCREENSHOT"):
			shot += 1
	return OK


static func _dispatch_line(
	tree: SceneTree,
	main: Node,
	line: String,
	step: int,
	shot: int,
	outdir: String
) -> int:
	if line.begins_with("WAIT "):
		var ms := int(line.substr(5).strip_edges())
		await tree.create_timer(ms / 1000.0).timeout
	elif line.begins_with("SPEED "):
		var speed_name := line.substr(6).strip_edges().to_lower()
		var sim := main.get_node("Sim")
		var clock = sim.get_clock() if sim.has_method("get_clock") else null
		if clock == null:
			printerr("[ui-script] FAILED step ", step, ": no SimClock")
			return 1
		match speed_name:
			"pause":
				clock.set_speed(clock.Speed.PAUSE)
			"watch":
				clock.set_speed(clock.Speed.WATCH)
			"fast":
				clock.set_speed(clock.Speed.FAST)
			"grow":
				clock.set_speed(clock.Speed.GROW)
			_:
				printerr("[ui-script] FAILED step ", step, ": unknown speed ", speed_name)
				return 1
	elif line.begins_with("ADVANCE_DAYS "):
		var days := float(line.substr(13).strip_edges())
		var ticks := int(round(days * 24.0))
		var sim := main.get_node("Sim")
		if sim.has_method("advance_ticks"):
			sim.advance_ticks(ticks)
		for _f in range(3):
			await tree.process_frame
	elif line.begins_with("CAMERA "):
		var cam_name := line.substr(7).strip_edges().to_lower()
		var cam_rig := main.get_node_or_null("World/CameraRig")
		if cam_rig == null or not cam_rig.has_method("select"):
			printerr("[ui-script] FAILED step ", step, ": World/CameraRig has no select() method")
			return 1
		var cam_index := -1
		match cam_name:
			"sun", "0": cam_index = 0
			"shade", "1": cam_index = 1
			"top", "2": cam_index = 2
			"silhouette", "3": cam_index = 3
			_:
				if cam_name.is_valid_int():
					cam_index = int(cam_name)
		if cam_index < 0:
			printerr("[ui-script] FAILED step ", step, ": unknown camera '", cam_name, "'")
			return 1
		cam_rig.select(cam_index)
		print("[ui-script]   CAMERA ", cam_name, " (index=", cam_index, ")")
	elif line.begins_with("SEED "):
		var seed_token := line.substr(5).strip_edges()
		var seed_idx := _UiScriptVerbs.compass_to_seed_index(seed_token)
		if seed_idx < 0:
			printerr("[ui-script] FAILED step ", step, ": unknown SEED '", seed_token, "'")
			return 1
		var sim := main.get_node("Sim")
		var world := main.get_node("World")
		if world.has_method("set_seed_index"):
			world.set_seed_index(seed_idx)
		if not sim.has_method("set_seed_index") or not sim.has_method("reseed"):
			printerr("[ui-script] FAILED step ", step, ": Sim missing set_seed_index/reseed")
			return 1
		sim.set_seed_index(seed_idx)
		sim.reseed()
		print("[ui-script]   SEED ", seed_token, " (index=", seed_idx, ")")
	elif line.begins_with("ASSERT "):
		var assert_parts: PackedStringArray = line.split(" ", false)
		if assert_parts.size() < 4:
			printerr("[ui-script] FAILED step ", step, ": ASSERT requires <metric> <op> <value> [seed_azimuth_deg]")
			return 1
		var metric_name: String = assert_parts[1]
		var op: String = assert_parts[2]
		var expected: float = float(assert_parts[3])
		var seed_az: float = 180.0
		if assert_parts.size() >= 5:
			seed_az = float(assert_parts[4])
		var assert_sim: Node = main.get_node("Sim")
		var assert_world: Node = main.get_node("World")
		var metrics: Dictionary = _UiScriptVerbs.collect_metrics(assert_sim, assert_world, seed_az)
		var actual_v: Variant = _UiScriptVerbs.read_metric(metric_name, metrics)
		if actual_v == null:
			printerr("[ui-script] FAILED step ", step, ": unknown ASSERT metric '", metric_name, "'")
			return 1
		var actual: float = float(actual_v)
		if not _UiScriptVerbs.compare(actual, op, expected):
			printerr("[ui-script] FAILED step ", step, ": ASSERT ", metric_name, " ", op, " ", expected,
				" (actual=", actual, ")")
			return 1
		print("[ui-script]   ASSERT ", metric_name, " ", op, " ", expected, " (actual=", actual, ")")
	elif line.begins_with("SET_PARAM "):
		var sp_parts := line.split(" ", false)
		if sp_parts.size() < 3:
			printerr("[ui-script] FAILED step ", step, ": SET_PARAM requires <name> <value>")
			return 1
		var sp_name: String = sp_parts[1]
		var sp_value_str: String = sp_parts[2]
		var sp_sim: Node = main.get_node("Sim")
		var sp_params: IvyParams = sp_sim.get("params") as IvyParams
		if sp_params == null:
			printerr("[ui-script] FAILED step ", step, ": Sim.params is null")
			return 1
		var sp_current: Variant = sp_params.get(sp_name)
		if sp_current == null:
			printerr("[ui-script] FAILED step ", step, ": unknown IvyParams field '", sp_name, "'")
			return 1
		var sp_typed: Variant
		match typeof(sp_current):
			TYPE_BOOL:
				sp_typed = sp_value_str.to_lower() == "true"
			TYPE_INT:
				sp_typed = int(sp_value_str)
			_:
				sp_typed = float(sp_value_str)
		sp_params.set(sp_name, sp_typed)
		print("[ui-script]   SET_PARAM ", sp_name, "=", sp_typed, " (was ", sp_current, ")")
	elif line.begins_with("TRACE "):
		var days := float(line.substr(6).strip_edges())
		var sim := main.get_node("Sim")
		for _t in range(int(round(days * 24.0))):
			sim.advance_ticks(1)
			var t0 = sim.tips.tips[0]
			print("[trace] tick=", sim.clock.tick_index,
				" tips=", sim.tips.tips.size(),
				" segs=", sim.plant.segment_count(),
				" len=%.9f" % sim.plant.total_length,
				" t0pos=%.9f,%.9f,%.9f" % [t0.position.x, t0.position.y, t0.position.z],
				" t0vig=%.9f" % t0.vigour,
				" t0state=", t0.state)
	elif line.begins_with("DUMP_LEAF_COLOUR"):
		return await _dump_leaf_colour(main, line, step)
	elif line.begins_with("DUMP_BLACKLIST"):
		return _dump_blacklist(main, step)
	elif line.begins_with("DUMP_METRICS"):
		return _dump_metrics(main, line, step)
	elif line.begins_with("DUMP_LIGHT"):
		return _dump_light(main, step)
	elif line.begins_with("DUMP"):
		return _dump(main)
	elif line.begins_with("SCREENSHOT"):
		var name := "%02d_capture.png" % (shot + 1)
		var parts := line.split(" ", false)
		if parts.size() >= 2:
			name = parts[1]
		var path := outdir.path_join(name)
		if not await present_fresh_frame(tree):
			printerr("[ui-script] FAILED step ", step, ": no frame rendered within ", _PRESENT_TIMEOUT_MS, " ms")
			return 1
		var img: Image = tree.root.get_viewport().get_texture().get_image()
		if img == null:
			printerr("[ui-script] FAILED step ", step, ": no viewport image")
			return 1
		var save_err := img.save_png(path)
		if save_err != OK:
			printerr("[ui-script] FAILED step ", step, ": save_png ", save_err)
			return 1
		print("[ui-script]   saved ", path, " size=", img.get_size())
	else:
		printerr("[ui-script] FAILED step ", step, ": unknown verb: ", line)
		return 1
	return OK


static func _dump_metrics(main: Node, line: String, step: int) -> int:
	var dm_parts: PackedStringArray = line.split(" ", false)
	var dm_seed_az: float = 180.0
	if dm_parts.size() >= 2:
		dm_seed_az = float(dm_parts[1])
	var dm_sim: Node = main.get_node("Sim")
	var dm_world: Node = main.get_node("World")
	var dm_spec: TowerSpec = dm_world.get("tower_spec") as TowerSpec
	if dm_spec == null:
		printerr("[ui-script] FAILED step ", step, ": World.tower_spec is null")
		return 1
	var dm_plant: PlantData = dm_sim.get("plant") as PlantData
	var dm_params_early: IvyParams = dm_sim.get("params") as IvyParams
	var dm_metric: RefCounted = _CoverageMetric.new()
	dm_metric.setup(dm_spec, dm_params_early if dm_params_early != null else IvyParams.new())
	var dm_result: Dictionary = dm_metric.measure(dm_plant, dm_seed_az)
	var dm_clock: SimClock = dm_sim.get("clock") as SimClock
	var dm_day: float = dm_clock.game_day if dm_clock != null else 0.0
	print("[ui-script]   DUMP_METRICS day=%.1f seed_az=%.1f" % [dm_day, dm_seed_az])
	print("[ui-script]   COVERAGE overall=%.2f%% (target >=70%%)" % [dm_result.get("overall_pct", 0.0)])
	print("[ui-script]   COVERAGE sun_half=%.2f%% (target >=90%%)" % [dm_result.get("sun_half_pct", 0.0)])
	print("[ui-script]   COVERAGE shade_half=%.6f%% (target >=50%%)" % [dm_result.get("shade_half_pct", 0.0)])
	print("[ui-script]   LIP_REACHED=%s" % [str(dm_result.get("lip_reached", false))])
	print("[ui-script]   AS2 asymmetry=%.2f%%" % [dm_result.get("stem_asymmetry_pct", 0.0)])
	var dm_total_len: float = dm_plant.total_length if dm_plant != null else 0.0
	print("[ui-script]   TOTAL_STEM_LENGTH=%.6f m" % dm_total_len)
	return OK


static func _dump_blacklist(main: Node, step: int) -> int:
	var sim: Node = main.get_node("Sim")
	var plant: PlantData = sim.get("plant") as PlantData
	var tips: TipManager = sim.get("tips") as TipManager
	var surface: SurfaceQuery = sim.get("surface") as SurfaceQuery
	var params: IvyParams = sim.get("params") as IvyParams
	if plant == null or tips == null or surface == null or params == null:
		printerr("[ui-script] FAILED step ", step, ": DUMP_BLACKLIST missing sim state")
		return 1
	var seed_pos := Vector3.ZERO
	if tips.tips.size() > 0:
		seed_pos = tips.tips[0].position
	var world: Node = main.get_node("World")
	var spec: TowerSpec = world.get("tower_spec") as TowerSpec
	var bl: Dictionary = _BlacklistAssertions.measure(plant, tips, surface, params, seed_pos, spec)
	print("[ui-script]   BLACKLIST hard_pass=%s" % str(bl.get("hard_pass", false)))
	print("[ui-script]   BLACKLIST direction_fourfold=%.4f (screen fail >%.2f)"
		% [bl.get("direction_fourfold_ratio", 0.0), _BlacklistAssertions.FOURFOLD_FAIL_RATIO])
	print("[ui-script]   BLACKLIST density_fft_peak_ratio=%.4f (screen)" % bl.get("density_fft_peak_ratio", 0.0))
	print("[ui-script]   BLACKLIST coplanar_pairs=%d (screen)" % bl.get("coplanar_pair_count", 0))
	print("[ui-script]   BLACKLIST item7=%s — %s"
		% [bl.get("item7_status", "?"), bl.get("item7_detail", "")])
	for msg in bl.get("hard_failures", PackedStringArray()):
		printerr("[ui-script]   BLACKLIST FAIL: ", msg)
	var fail_count: int = bl.get("hard_failures", PackedStringArray()).size()
	if fail_count > 0:
		print("[ui-script]   BLACKLIST hard_failures=%d (report-only until canonical run is clean)" % fail_count)
	return OK


static func _dump(main: Node) -> int:
	var sim := main.get_node("Sim")
	var plant = sim.plant
	var tips = sim.tips
	print("[ui-script]   DUMP day=", sim.clock.game_day,
		" tick=", sim.clock.tick_index,
		" tips=", tips.tips.size(),
		" segments=", plant.segment_count(),
		" leaves=", plant.leaf_count(),
		" total_len=", plant.total_length)
	return OK


static func _dump_light(main: Node, step: int) -> int:
	var sim := main.get_node("Sim")
	var env = sim.env
	print("[ui-script]   LIGHT mean_P_bar south=", "%.2f" % env.mean_p_bar_facing(Conv.SOUTH))
	return OK


static func _dump_leaf_colour(main: Node, line: String, step: int) -> int:
	var dlc_parts: PackedStringArray = line.split(" ", false)
	var dlc_seed_az: float = 180.0
	if dlc_parts.size() >= 2:
		dlc_seed_az = float(dlc_parts[1])
	var dlc_sim: Node = main.get_node("Sim")
	var dlc_world: Node = main.get_node("World")
	var dlc_spec: TowerSpec = dlc_world.get("tower_spec") as TowerSpec
	if dlc_spec == null:
		printerr("[ui-script] FAILED step ", step, ": World.tower_spec is null")
		return 1
	var dlc_params: IvyParams = dlc_sim.get("params") as IvyParams
	var dlc_plant: PlantData = dlc_sim.get("plant") as PlantData
	var dlc_metric: RefCounted = _LeafColourMetric.new()
	dlc_metric.setup(dlc_spec, dlc_params)
	var dlc_result: Dictionary = dlc_metric.measure(dlc_plant, dlc_seed_az)
	print("[ui-script]   DUMP_LEAF_COLOUR LG2a Δg=%.5f" % dlc_result.get("lg2a_delta", 0.0))
	return OK
