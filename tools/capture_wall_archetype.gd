extends Node

## Headless-capable tool for capturing a straight-on wall-elevation screenshot
## per archetype preset (ivy-68j / ivy-agc).
##
## Promoted from a one-off prototype to a reviewed tool that drives the shared
## ArchetypePreset registry so the screenshot and the GUT band test describe the
## IDENTICAL plant (same seeds, same params, same spec — see ivy-50f deviation note).
##
## Non-headless only: screenshots need a real present; do not add --headless.
##
## Usage:
##   Godot res://tools/capture_wall_archetype.tscn -- --archetype=dense|mid|sparse
##   Godot res://tools/capture_wall_archetype.tscn -- --branch_rate=1.7 --label=dense
##
## Recognised args (OS.get_cmdline_user_args(), after --):
##
##   --archetype=NAME    Load a named ArchetypePreset (dense|mid|sparse). Applies
##                       all preset param_overrides (including leaf_cap, which MUST
##                       be set before the building is loaded — see ordering note
##                       below), uses preset.seed_positions(spec) for planting, and
##                       derives --day and --label from the preset unless overridden
##                       explicitly by the caller.
##
##   Escape-hatch raw overrides (applied AFTER --archetype, so they win on conflict;
##   also work standalone without --archetype for ad-hoc experiments):
##   --branch_rate=F     IvyParams.branch_rate override
##   --tip_cap_hard=N    IvyParams.tip_cap_hard override
##   --tip_cap_soft=N    IvyParams.tip_cap_soft override
##   --leaf_width_base=F IvyParams.leaf_width_base override
##   --internode_base=F  IvyParams.internode_base override
##   --leaf_cap=N        IvyParams.leaf_cap override — MUST be applied before the
##                       building is loaded (it sizes a fixed MultiMesh render buffer
##                       at bootstrap; changing it after has no effect on capacity).
##   --seeds=N           number of seed points evenly spaced across the wall
##   --seed_y=F          height of the seed row (default 0.02)
##   --label=STR         output filename stem (default: archetype name or "wall_archetype")
##   --day=N             game-day to advance to (default: preset.day or 150)
##
## Ordering note: leaf_cap sizes the plant_render MultiMesh at building-load time.
## apply_to(params) / raw leaf_cap override are both applied BEFORE _select_building()
## so the buffer is sized correctly at bootstrap.
##
## Every run captures TWO images per archetype (not opt-in — this is the standard QA
## artifact pair going forward, per the human's 2026-09-26 request):
##   <label>.png          full straight-on wall elevation (unchanged framing)
##   <label>_closeup.png  tight shot centred on the actual leaf centroid, so leaf
##                        shape/density/overlap is legible regardless of where on the
##                        wall this archetype's growth happens to land (dense fills the
##                        whole face so any point works; sparse/mid cluster around their
##                        seed row, so a fixed frame-center would miss the foliage).

const _MAIN_SCENE := "res://src/main/main.tscn"
const _BuildingCatalog = preload("res://src/world/building_catalog.gd")
const _Conv = preload("res://src/core/conv.gd")
const WallSpec = preload("res://src/world/wall_spec.gd")
const ArchetypePreset = preload("res://src/params/archetype_preset.gd")
const _OUTDIR := "res://.tmp/wall_archetypes/"
const _TICKS_PER_DAY := 24
const _PRESENT_TIMEOUT_MS := 4000


func _ready() -> void:
	var args := _parse_args()
	var outdir := ProjectSettings.globalize_path(_OUTDIR)
	DirAccess.make_dir_recursive_absolute(outdir)

	var main := await _spawn_main()

	var params: IvyParams = main.get("params") as IvyParams

	# ── Step 1: apply archetype preset (if --archetype= given) ──────────────
	# IMPORTANT: leaf_cap must be set BEFORE the building is loaded (it sizes
	# plant_render.gd's MultiMesh buffer once at _bootstrap_simulation).
	var preset: ArchetypePreset = null
	if args.has("archetype"):
		preset = ArchetypePreset.for_name(args["archetype"])
		preset.apply_to(params)
		print("[capture-wall] archetype=%s applied (day=%d seeds=%d seed_y=%.3f)"
			% [preset.label, preset.day, preset.seeds, preset.seed_y])

	# ── Step 2: apply raw escape-hatch overrides on top ─────────────────────
	# These override whatever --archetype= set, or work standalone without it.
	if args.has("leaf_cap"):
		params.leaf_cap = int(args["leaf_cap"])
	if args.has("branch_rate"):
		params.branch_rate = float(args["branch_rate"])
	if args.has("tip_cap_hard"):
		params.tip_cap_hard = int(args["tip_cap_hard"])
	if args.has("tip_cap_soft"):
		params.tip_cap_soft = int(args["tip_cap_soft"])
	if args.has("leaf_width_base"):
		params.leaf_width_base = float(args["leaf_width_base"])
	if args.has("internode_base"):
		params.internode_base = float(args["internode_base"])

	print("[capture-wall] branch_rate=%.4f tip_cap_soft=%d tip_cap_hard=%d leaf_cap=%d leaf_width_base=%.4f internode_base=%.4f"
		% [params.branch_rate, params.tip_cap_soft, params.tip_cap_hard, params.leaf_cap,
			params.leaf_width_base, params.internode_base])

	# ── Step 3: load building (leaf_cap must be set before this) ─────────────
	await _select_building(main, "test_wall")
	var load_ok := await _wait_for_free_plant(main, 600000)
	if not load_ok:
		printerr("[capture-wall] wall load timed out")
		get_tree().quit(1)
		return

	# ── Step 4: get wall spec for seeding and camera ─────────────────────────
	var sim: Node = main.get_node("Sim")
	var spec: WallSpec = main.get_node("World").get("wall_spec") as WallSpec

	# ── Step 5: plant seeds ───────────────────────────────────────────────────
	if preset != null:
		# Use shared preset seeding so GUT and screenshot grow the same plant.
		for pos in preset.seed_positions(spec):
			sim.plant_at(pos, _Conv.SOUTH)
	else:
		# Legacy behaviour: raw --seeds / --seed_y args (or single midpoint).
		var seed_count: int = int(args.get("seeds", 1))
		var seed_y: float = float(args.get("seed_y", 0.02))
		var half_len: float = spec.length * 0.5 if spec != null else 9.0
		if seed_count <= 1:
			sim.plant_at(Vector3(0.0, seed_y, 0.01), _Conv.SOUTH)
		else:
			var margin := half_len * 0.15
			var usable := half_len - margin
			for i in range(seed_count):
				var t := float(i) / float(seed_count - 1) * 2.0 - 1.0
				sim.plant_at(Vector3(t * usable, seed_y, 0.01), _Conv.SOUTH)

	if main.has_method("_on_plant_success"):
		main.call("_on_plant_success")
	await _settle(5)

	# ── Step 6: advance simulation ────────────────────────────────────────────
	var day: int
	if args.has("day"):
		day = int(args["day"])
	elif preset != null:
		day = preset.day
	else:
		day = 150

	var t0 := Time.get_ticks_msec()
	# +6 ticks = "day N.25" convention (local noon at start_hour=6) for daylight screenshot.
	sim.advance_ticks(_TICKS_PER_DAY * day + 6)
	var elapsed_ms := Time.get_ticks_msec() - t0
	await _settle(10)

	var plant: PlantData = sim.get("plant") as PlantData
	var tips = sim.get("tips")
	print("[capture-wall] day=%d elapsed_ms=%d total_length=%.3f segs=%d leaves=%d tips_live=%d"
		% [day, elapsed_ms, plant.total_length, plant.segment_count(), plant.leaf_count(),
			tips.live_count()])

	# ── Step 7: capture ───────────────────────────────────────────────────────
	var label: String
	if args.has("label"):
		label = args["label"]
	elif preset != null:
		label = preset.label
	else:
		label = "wall_archetype"
	await _capture_straight_on(main, spec, outdir.path_join("%s.png" % label))
	await _capture_close_up(main, spec, plant, outdir.path_join("%s_closeup.png" % label))

	main.queue_free()
	print("[capture-wall] done")
	get_tree().quit(0)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _capture_straight_on(main: Node, spec: WallSpec, path: String) -> void:
	var world: Node3D = main.get_node("World") as Node3D
	var cam := Camera3D.new()
	cam.name = "WallElevationCam"
	cam.fov = 70.0
	world.add_child(cam)

	# Data-driven framing from wall_spec so this doesn't silently break if the
	# spec changes (e.g. a future 30×15 wall spec).
	# Assumes a 16:9 viewport for horizontal-fov estimation.
	# For the current 20×10 spec this evaluates to approximately (0, 5, 11).
	if spec != null:
		var half_w := spec.length * 0.5
		var half_h := spec.height * 0.5
		var vfov_half := deg_to_rad(cam.fov * 0.5)
		var hfov_half := atan(tan(vfov_half) * 16.0 / 9.0)
		var dist_w := half_w / tan(hfov_half)
		var dist_h := half_h / tan(vfov_half)
		var dist := maxf(dist_w, dist_h) * 1.4  # 40% margin for wall + substrate
		cam.global_position = Vector3(0.0, half_h, dist)
		cam.look_at(Vector3(0.0, half_h, 0.0), Vector3.UP)
	else:
		# Fallback to hand-tuned values for the current 20×10 wall_spec_default.
		cam.global_position = Vector3(0.0, 5.0, 11.0)
		cam.look_at(Vector3(0.0, 5.0, 0.0), Vector3.UP)
	cam.current = true

	# Swapping `current` on a Camera3D does not take effect in the renderer
	# until at least one process frame has elapsed — capture after settling.
	await _settle(3)
	if not await _present_fresh_frame():
		printerr("[capture-wall] no frame for ", path)
		cam.queue_free()
		return
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		printerr("[capture-wall] save_png failed ", err, " ", path)
	else:
		print("[capture-wall] saved ", path, " size=", img.get_size())
	cam.queue_free()


## Close-range shot centred on where the leaves actually are (leaf-origin centroid),
## not the wall's geometric centre — sparse/mid archetypes cluster growth around their
## seed row and a fixed frame would just show bare brick. Distance/fov are tuned to
## frame roughly a 2.5m x 1.4m patch: close enough that individual leaf shapes and
## overlap read clearly, wide enough to show local density/gaps rather than one leaf.
const _CLOSEUP_DIST := 1.5
const _CLOSEUP_FOV := 50.0


func _leaf_centroid(plant: PlantData, spec: WallSpec) -> Vector2:
	var n: int = plant.leaf_count()
	if n <= 0:
		# No leaves placed (shouldn't happen for any shipped archetype, but don't crash
		# a QA run over it) — fall back to the wall's geometric centre.
		var fallback_h := spec.height * 0.5 if spec != null else 5.0
		return Vector2(0.0, fallback_h)
	var sum_x := 0.0
	var sum_y := 0.0
	for i in range(n):
		var base := i * 12
		sum_x += plant.leaf_xform[base + 3]
		sum_y += plant.leaf_xform[base + 7]
	var cx := sum_x / float(n)
	var cy := sum_y / float(n)
	if spec != null:
		var half_len := spec.length * 0.5
		cx = clampf(cx, -half_len, half_len)
		cy = clampf(cy, 0.0, spec.height)
	return Vector2(cx, cy)


func _capture_close_up(main: Node, spec: WallSpec, plant: PlantData, path: String) -> void:
	var world: Node3D = main.get_node("World") as Node3D
	var centroid := _leaf_centroid(plant, spec)
	var cam := Camera3D.new()
	cam.name = "WallCloseUpCam"
	cam.fov = _CLOSEUP_FOV
	world.add_child(cam)
	cam.global_position = Vector3(centroid.x, centroid.y, _CLOSEUP_DIST)
	cam.look_at(Vector3(centroid.x, centroid.y, 0.0), Vector3.UP)
	cam.current = true

	# Same renderer quirk as _capture_straight_on: `current` needs a settled frame.
	await _settle(3)
	if not await _present_fresh_frame():
		printerr("[capture-wall] no frame for ", path)
		cam.queue_free()
		return
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		printerr("[capture-wall] save_png failed ", err, " ", path)
	else:
		print("[capture-wall] saved ", path, " size=", img.get_size(),
			" centroid=(%.2f,%.2f)" % [centroid.x, centroid.y])
	cam.queue_free()


func _spawn_main() -> Node:
	var ps := load(_MAIN_SCENE) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", false)
	add_child(main)
	_keep_window_presenting()
	await _settle(35)
	return main


func _select_building(main: Node, building_id: String) -> void:
	var ui: CanvasLayer = main.get_node("UI") as CanvasLayer
	var picker := ui.get_node_or_null("BuildingPicker")
	if picker != null:
		for btn in _find_buttons(picker):
			var entry_id := _building_id_for_label((btn as Button).text)
			if entry_id == building_id:
				(btn as Button).emit_signal("pressed")
				await _settle(5)
				return
	if main.has_method("_on_building_selected"):
		main.call("_on_building_selected", building_id)
		_dismiss_picker(ui)
	await _settle(3)


func _find_buttons(root: Node) -> Array:
	var out: Array = []
	if root is Button:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_buttons(c))
	return out


func _building_id_for_label(label: String) -> String:
	for entry in _BuildingCatalog.all():
		if entry.label == label:
			return entry.id
	return ""


func _dismiss_picker(ui: CanvasLayer) -> void:
	var picker := ui.get_node_or_null("BuildingPicker")
	if picker != null:
		picker.queue_free()


func _wait_for_free_plant(main: Node, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var ui: CanvasLayer = main.get_node_or_null("UI") as CanvasLayer
		var has_picker := ui != null and ui.get_node_or_null("BuildingPicker") != null
		var overlay := ui.get_node_or_null("LoadingOverlay") if ui != null else null
		var tool := main.get_node_or_null("World/PlantingTool")
		var hud := ui.get_node_or_null("Hud") if ui != null else null
		if not has_picker and overlay == null and tool != null and hud != null:
			await _settle(15)
			return true
		await get_tree().process_frame
	return false


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _present_fresh_frame() -> bool:
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
		return true
	var drawn := [false]
	var on_draw := func() -> void: drawn[0] = true
	RenderingServer.frame_post_draw.connect(on_draw, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + _PRESENT_TIMEOUT_MS
	while not drawn[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if RenderingServer.frame_post_draw.is_connected(on_draw):
		RenderingServer.frame_post_draw.disconnect(on_draw)
	return drawn[0]


func _keep_window_presenting() -> void:
	var w := get_window()
	if w == null:
		return
	if w.mode == Window.MODE_MINIMIZED:
		w.mode = Window.MODE_WINDOWED
	DisplayServer.window_move_to_foreground()
