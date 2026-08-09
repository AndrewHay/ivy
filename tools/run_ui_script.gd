extends Node

## Minimal UI script runner for bootstrap. Extend verbs as Ivy gains interactive UI.

const _MAIN_SCENE := "res://src/main/main.tscn"
const _CoverageMetric = preload("res://src/metrics/coverage.gd")
## Output defaults inside the project so runs need no write access outside the
## workspace. `.tmp/` is gitignored.
const _DEFAULT_OUTDIR := "res://.tmp/ui_scripts/"


func _ready() -> void:
	var args := _parse_args()
	var script_path: String = args.get("script", "")
	# globalize_path resolves res:// and passes absolute paths through unchanged,
	# so an explicit --outdir still works.
	var outdir: String = ProjectSettings.globalize_path(
		args.get("outdir", _DEFAULT_OUTDIR)
	)
	if script_path.is_empty() or not FileAccess.file_exists(script_path):
		printerr("[ui-script] missing or invalid --script=", script_path)
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(outdir)

	var ps := load(_MAIN_SCENE) as PackedScene
	if ps == null:
		printerr("[ui-script] failed to load ", _MAIN_SCENE)
		get_tree().quit(2)
		return
	var scene_root := ps.instantiate()
	# Set before entering the tree so `_ready` sees it and never starts the clock.
	scene_root.set("script_driven", true)
	add_child(scene_root)

	for _i in range(30):
		await get_tree().process_frame

	var lines := FileAccess.get_file_as_string(script_path).split("\n")
	var step := 0
	var shot := 0
	print("[ui-script] script=", script_path, "  outdir=", outdir, "  steps=", lines.size())

	var main: Node = null
	for c in get_children():
		if c.name == "Main" or c.get_script() != null:
			main = c
			break
	if main == null:
		main = get_child(0)

	for raw in lines:
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		step += 1
		if line.begins_with("WAIT "):
			var ms := int(line.substr(5).strip_edges())
			await get_tree().create_timer(ms / 1000.0).timeout
		elif line.begins_with("SPEED "):
			var speed_name := line.substr(6).strip_edges().to_lower()
			var sim := main.get_node("Sim")
			var clock = sim.get_clock() if sim.has_method("get_clock") else null
			if clock == null:
				printerr("[ui-script] FAILED step ", step, ": no SimClock")
				get_tree().quit(1)
				return
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
					get_tree().quit(1)
					return
		elif line.begins_with("ADVANCE_DAYS "):
			var days := float(line.substr(13).strip_edges())
			var ticks := int(round(days * 24.0))
			var sim := main.get_node("Sim")
			if sim.has_method("advance_ticks"):
				sim.advance_ticks(ticks)
			for _f in range(3):
				await get_tree().process_frame
		elif line.begins_with("SET_PARAM "):
			# Live-edits IvyParams on the running Sim (W-027, AS-3b comparison, M3).
			# Makes NO RNG draws — pure property assignment. Draw sequences diverge only
			# because changed parameters (e.g. growth rate) shift when per-metre events
			# fire; the verb itself introduces nothing random.
			var sp_parts := line.split(" ", false)
			if sp_parts.size() < 3:
				printerr("[ui-script] FAILED step ", step, ": SET_PARAM requires <name> <value>")
				get_tree().quit(1)
				return
			var sp_name: String = sp_parts[1]
			var sp_value_str: String = sp_parts[2]
			var sp_sim: Node = main.get_node("Sim")
			var sp_params: IvyParams = sp_sim.get("params") as IvyParams
			if sp_params == null:
				printerr("[ui-script] FAILED step ", step, ": Sim.params is null")
				get_tree().quit(1)
				return
			var sp_current: Variant = sp_params.get(sp_name)
			if sp_current == null:
				printerr("[ui-script] FAILED step ", step, ": unknown IvyParams field '", sp_name, "'")
				get_tree().quit(1)
				return
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
			# Per-tick state checksum. Diff two runs to find the first divergent tick
			# instead of reasoning backwards from a wildly different end state.
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
		elif line.begins_with("DUMP_METRICS"):
			# DUMP_METRICS [seed_azimuth_deg]
			# Must be checked before DUMP (which begins_with("DUMP") would match DUMP_METRICS).
			# Compute bucket-occupancy coverage (SD-METRIC-1/2/3/5/6), stem-length
			# asymmetry (AS-2), and diel gate readouts (AS-3) at the current game day.
			# seed_azimuth_deg defaults to 180.0 (south seed, which is the M1 default).
			var dm_parts: PackedStringArray = line.split(" ", false)
			var dm_seed_az: float = 180.0
			if dm_parts.size() >= 2:
				dm_seed_az = float(dm_parts[1])
			var dm_sim: Node = main.get_node("Sim")
			var dm_world: Node = main.get_node("World")
			var dm_spec: TowerSpec = dm_world.get("tower_spec") as TowerSpec
			if dm_spec == null:
				printerr("[ui-script] FAILED step ", step, ": World.tower_spec is null")
				get_tree().quit(1)
				return
			var dm_plant: PlantData = dm_sim.get("plant") as PlantData
			var dm_metric: RefCounted = _CoverageMetric.new()
			dm_metric.setup(dm_spec)
			var dm_result: Dictionary = dm_metric.measure(dm_plant, dm_seed_az)
			var dm_clock: SimClock = dm_sim.get("clock") as SimClock
			var dm_day: float = dm_clock.game_day if dm_clock != null else 0.0
			print("[ui-script]   DUMP_METRICS day=%.1f seed_az=%.1f" % [dm_day, dm_seed_az])
			print("[ui-script]   COVERAGE overall=%.2f%% (target >=70%%)" % [dm_result.get("overall_pct", 0.0)])
			print("[ui-script]   COVERAGE sun_half=%.2f%% (target >=90%%)" % [dm_result.get("sun_half_pct", 0.0)])
			print("[ui-script]   COVERAGE shade_half=%.2f%% (target >=50%%)" % [dm_result.get("shade_half_pct", 0.0)])
			print("[ui-script]   COVERAGE stem_bucket=%.2f%%" % [dm_result.get("stem_bucket_pct", 0.0)])
			print("[ui-script]   COVERAGE eligible=%d  sun_elig=%d  shade_elig=%d" % [
				dm_result.get("total_eligible_buckets", 0),
				dm_result.get("sun_eligible_buckets", 0),
				dm_result.get("shade_eligible_buckets", 0)])
			print("[ui-script]   LIP_REACHED=%s" % [str(dm_result.get("lip_reached", false))])
			# AS-2: stem-length asymmetry
			print("[ui-script]   AS2 sun_stem=%.3f m  shade_stem=%.3f m  asymmetry=%.2f%% (day30 target >=20%%)" % [
				dm_result.get("sun_stem_length", 0.0),
				dm_result.get("shade_stem_length", 0.0),
				dm_result.get("stem_asymmetry_pct", 0.0)])
			# AS-2: 12-sector stem-length breakdown
			var dm_sec_stem: PackedFloat32Array = dm_result.get("sector_stem_length", PackedFloat32Array())
			var dm_sec_str: String = ""
			for s in range(dm_sec_stem.size()):
				dm_sec_str += "sec%d=%.2f " % [s, dm_sec_stem[s]]
			print("[ui-script]   SECTORS_STEM ", dm_sec_str.strip_edges())
			# AS-3(a): diel gate values at midnight and noon for the current date.
			# midnight = start_hour + 18h into the game-day (since day starts at start_hour=6)
			# noon = start_hour + 6h into the game-day
			var dm_solar: Solar = dm_sim.get("solar") as Solar
			var dm_params: IvyParams = dm_sim.get("params") as IvyParams
			if dm_solar != null and dm_params != null:
				var dm_day_int: int = int(floor(dm_day))
				var dm_noon_day: float = float(dm_day_int) + (12.0 - dm_params.start_hour) / 24.0
				var dm_midnight_day: float = float(dm_day_int) + (24.0 - dm_params.start_hour) / 24.0
				var dm_gate_noon: float = dm_solar.diel_gate(dm_noon_day)
				var dm_gate_midnight: float = dm_solar.diel_gate(dm_midnight_day)
				print("[ui-script]   AS3a gate_noon=%.4f  gate_midnight=%.4f  ratio_midnight_to_noon=%.4f (target <=0.10)" % [
					dm_gate_noon, dm_gate_midnight, dm_gate_midnight / maxf(dm_gate_noon, 1e-6)])
				print("[ui-script]   AS3a midnight_vs_daily_mean=%.4f (target <=0.15; daily mean ~1.0 by INV-3a)" % [dm_gate_midnight])
			var dm_total_len: float = dm_plant.total_length if dm_plant != null else 0.0
			var dm_leaf_n: int = dm_plant.leaf_count() if dm_plant != null else 0
			var dm_seg_n: int = dm_plant.segment_count() if dm_plant != null else 0
			# Sum leaf_area[] for total projected leaf area in m².
			var dm_leaf_area: float = 0.0
			if dm_plant != null:
				for _la in dm_plant.leaf_area:
					dm_leaf_area += _la
			var dm_wall_area: float = 43.0  # eligible wall m² (2520 buckets × 0.017 m²)
			print("[ui-script]   TOTAL_STEM_LENGTH=%.6f m  leaves=%d  segments=%d" % [
				dm_total_len, dm_leaf_n, dm_seg_n])
			print("[ui-script]   LEAF_AREA=%.4f m²  layers=%.3f (÷%.0f m²)" % [
				dm_leaf_area, dm_leaf_area / dm_wall_area, dm_wall_area])
		elif line.begins_with("DUMP_LIGHT"):
			var sim := main.get_node("Sim")
			var env = sim.env
			var probes := {
				"S y=0.2": Vector3(0.0, 0.2, 2.0),
				"S y=1.0": Vector3(0.0, 1.0, 2.0),
				"S y=1.75": Vector3(0.0, 1.75, 2.0),
				"S y=3.0": Vector3(0.0, 3.0, 2.0),
				"N y=1.75": Vector3(0.0, 1.75, -2.0),
				"E y=1.75": Vector3(2.0, 1.75, 0.0),
			}
			for label in probes:
				var pt: Vector3 = probes[label]
				var b: Basis = sim.surface.tangent_basis_at(pt)
				var g: Vector3 = env.grad_S_D_L(pt, b, 0, 0)
				print("[ui-script]   LIGHT ", label,
					" D_L=", "%.2f" % env.sample_D_L(pt, 0, 0),
					" f_L=", "%.3f" % Physiology.f_L(env.sample_D_L(pt, 0, 0), sim.params),
					" SVF=", "%.3f" % env.sample_SVF(pt, 0, 0),
					" grad=", g, " |grad|=", "%.3f" % g.length(),
					" grad.up=", "%.3f" % g.dot(Conv.UP))
			print("[ui-script]   LIGHT mean_P_bar south=", "%.2f" % env.mean_p_bar_facing(Conv.SOUTH),
				" north=", "%.2f" % env.mean_p_bar_facing(Conv.NORTH),
				" -> D_L south=", "%.2f" % (env.mean_p_bar_facing(Conv.SOUTH) * IvyEnvironment.DL_SCALE),
				" north=", "%.2f" % (env.mean_p_bar_facing(Conv.NORTH) * IvyEnvironment.DL_SCALE))
			# AS-3(c): print EWMA time-constant diagnostics so the scripted run can report tau_L.
			# alpha = exp(-dt_sim / tau_L); tau_L_implied = -dt_sim / ln(alpha).
			var dl_params: IvyParams = sim.get("params") as IvyParams
			if dl_params != null:
				var dl_dt := dl_params.sim_tick
				var dl_alpha := dl_params.light_ewma_alpha(dl_dt)
				var dl_tau := -dl_dt / log(dl_alpha) if dl_alpha > 0.0 and dl_alpha < 1.0 else dl_params.light_memory
				# Step-response preview (analytical, no simulation advance):
				# after 72 ticks (3 game-days) of zero input from D_L=1.0, value = alpha^72 = exp(-1).
				var dl_step_ratio := pow(dl_alpha, 72)
				var dl_south: float = env.sample_D_L(Vector3(0.0, 1.75, 2.0), 0, 0)
				print("[ui-script]   AS3c EWMA alpha=%.6f  tau_L_implied=%.4f days (target %.1f)" % [
					dl_alpha, dl_tau, dl_params.light_memory])
				print("[ui-script]   AS3c step_response: after 72 ticks zero-input, D_L_remaining/D_L_0=%.4f (target exp(-1)=%.4f)" % [
					dl_step_ratio, exp(-1.0)])
				print("[ui-script]   AS3c south_probe D_L=%.3f; after 3-day zero-input would be %.3f (%.1f%% of original)" % [
					dl_south, dl_south * dl_step_ratio, dl_step_ratio * 100.0])
		elif line.begins_with("DUMP"):
			var sim := main.get_node("Sim")
			var plant = sim.plant
			var tips = sim.tips
			var live := 0
			var growing := 0
			var floating := 0
			var dead := 0
			var dormant := 0
			for t in tips.tips:
				match t.state:
					Tip.State.GROWING:
						growing += 1
					Tip.State.FLOATING:
						floating += 1
					Tip.State.DEAD:
						dead += 1
					Tip.State.DORMANT:
						dormant += 1
				if t.is_live():
					live += 1
			print("[ui-script]   DUMP day=", sim.clock.game_day,
				" tick=", sim.clock.tick_index,
				" tips=", tips.tips.size(), " live=", live,
				" growing=", growing, " floating=", floating,
				" dormant=", dormant, " dead=", dead,
				" segments=", plant.segment_count(),
				" leaves=", plant.leaf_count(),
				" total_len=", plant.total_length)
			if tips.tips.size() > 0:
				var t0 = tips.tips[0]
				print("[ui-script]   DUMP tip0 pos=", t0.position, " dir=", t0.direction,
					" vigour=", t0.vigour, " budget=", t0.growth_budget,
					" segs=", t0.segment_count, " float_len=", t0.floating_length)
		elif line.begins_with("SCREENSHOT"):
			shot += 1
			var name := "%02d_capture.png" % shot
			var parts := line.split(" ", false)
			if parts.size() >= 2:
				name = parts[1]
			var path := outdir.path_join(name)
			var img: Image = get_viewport().get_texture().get_image()
			if img == null:
				printerr("[ui-script] FAILED step ", step, ": no viewport image")
				get_tree().quit(1)
				return
			var err := img.save_png(path)
			if err != OK:
				printerr("[ui-script] FAILED step ", step, ": save_png ", err)
				get_tree().quit(1)
				return
			print("[ui-script]   saved ", path, " size=", img.get_size())
		else:
			printerr("[ui-script] FAILED step ", step, ": unknown verb: ", line)
			get_tree().quit(1)
			return

	get_tree().quit(0)


func _parse_args() -> Dictionary:
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--script="):
			args["script"] = a.substr(9)
		elif a.begins_with("--outdir="):
			args["outdir"] = a.substr(9)
	return args
