extends Node

## Minimal UI script runner for bootstrap. Extend verbs as Ivy gains interactive UI.

const _MAIN_SCENE := "res://src/main/main.tscn"
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
