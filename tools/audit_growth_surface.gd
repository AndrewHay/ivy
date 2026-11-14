extends Node3D

## Growth-surface audit driver — SG-9 (a)-(c), SD-OPEN-28 (ivy-b1e.2).
##
## Usage (project root):
##   Godot --headless res://tools/audit_growth_surface.tscn -- \
##       [--structures=ivy,tower,square,surface_wall] [--samples=2000] [--seed=1] [--json-dir=res://.tmp/audit]
##
## Builds each playable mesh structure the way the game does (StructureBody from the scenario's
## collision and hero GLBs, MeshSdf from its baked volume), runs tools/growth_surface_audit.gd,
## prints the report and exits 1 when any structure fails SG-9 (a)-(c), 2 on a usage or asset error.

const Audit = preload("res://tools/growth_surface_audit.gd")
const StructureBodyScript = preload("res://src/world/structure_body.gd")
const MeshSdfScript = preload("res://src/world/mesh_sdf.gd")

const SCENARIO_DIR := "res://assets/structures/scenarios/"
const DEFAULT_STRUCTURES := "ivy,tower,square,surface_wall"


func _parse_args() -> Dictionary:
	var out := {"structures": DEFAULT_STRUCTURES, "samples": "2000", "seed": "1", "json_dir": ""}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--structures="):
			out["structures"] = arg.substr(13)
		elif arg.begins_with("--samples="):
			out["samples"] = arg.substr(10)
		elif arg.begins_with("--seed="):
			out["seed"] = arg.substr(7)
		elif arg.begins_with("--json-dir="):
			out["json_dir"] = arg.substr(11)
		else:
			out["error"] = "unknown argument: %s" % arg
	return out


func _ready() -> void:
	var args := _parse_args()
	if args.has("error"):
		printerr("[audit] ", args["error"])
		get_tree().quit(2)
		return
	var summary: Array = []
	var all_pass := true
	for structure_id in String(args["structures"]).split(",", false):
		var scenario_path := SCENARIO_DIR + structure_id + ".tres"
		if not ResourceLoader.exists(scenario_path):
			printerr("[audit] no scenario %s" % scenario_path)
			get_tree().quit(2)
			return
		var scenario: Resource = load(scenario_path)
		var collision_glb: String = scenario.get("collision_glb")
		var hero_glb: String = scenario.get("hero_glb")
		var sdf_path: String = scenario.get("sdf_path")
		if hero_glb.is_empty() or not FileAccess.file_exists(collision_glb) \
				or not FileAccess.file_exists(hero_glb) or not FileAccess.file_exists(sdf_path):
			printerr("[audit] %s: missing collision, hero or sdf asset" % structure_id)
			get_tree().quit(2)
			return
		var started := Time.get_ticks_msec()
		var body: Node3D = StructureBodyScript.new()
		add_child(body)
		body.call("build", collision_glb, hero_glb)
		var sdf = MeshSdfScript.new()
		sdf.load_from_file(sdf_path)
		var pieces: Array = Audit.collect_hero_pieces(body.get_node("StructureVisual"))
		var hero_body: StaticBody3D = Audit.make_hero_body(self, pieces)
		for _i in 2:
			await get_tree().physics_frame
		var audit = Audit.new()
		audit.setup(get_world_3d().direct_space_state, pieces, sdf)
		var report: Dictionary = audit.run({"samples": int(args["samples"]), "seed": int(args["seed"])})
		print(Audit.format_report(structure_id, report))
		print("  audited in %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
		print("")
		if not String(args["json_dir"]).is_empty():
			var dir_path := ProjectSettings.globalize_path(String(args["json_dir"]))
			DirAccess.make_dir_recursive_absolute(dir_path)
			var f := FileAccess.open(dir_path.path_join(structure_id + ".json"), FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify(report, "  "))
		summary.append([structure_id, report])
		all_pass = all_pass and bool(report["pass"])
		# The playable structures overlap in world space: clear this one before the next.
		remove_child(hero_body)
		hero_body.free()
		remove_child(body)
		body.free()
		await get_tree().physics_frame

	print("[audit] summary (SG-9 provisional thresholds)")
	print("  structure      (a) p95|g|  max|g|  float%  clip%   (b) listed  missing   (c) face max  p99     inside+   result")
	for row in summary:
		var r: Dictionary = row[1]
		var a: Dictionary = r["a"]
		var b: Dictionary = r["b"]
		var c: Dictionary = r["c"]
		print("  %-13s  %s  %.4f      %.4f  %5.1f   %5.1f   %s  %4d        %4d      %s  %.4f        %.4f  %4d      %s" % [
			row[0], Audit._verdict(a["pass"]), a.get("p95_abs", NAN), a.get("max_abs", NAN),
			100.0 * a.get("float_share", 0.0), 100.0 * a.get("clip_share", 0.0),
			Audit._verdict(b["pass"]), b.get("listed", 0), b.get("unrepresented", 0),
			Audit._verdict(c["pass"]), c["face_max"], c["face_p99"], c["inside_not_negative"],
			Audit._verdict(r["pass"])])
	get_tree().quit(0 if all_pass else 1)
