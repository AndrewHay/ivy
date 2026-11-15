extends Node3D

## Growth-surface audit driver — SG-9 (a)-(c), SD-OPEN-28 (ivy-b1e.2; ratified gates ivy-b1e.12).
##
## Usage (project root):
##   Godot --headless res://tools/audit_growth_surface.tscn -- \
##       [--structures=ivy,tower,square,surface_wall] [--samples=2000] [--seed=1] [--json-dir=res://.tmp/audit]
##
## or, for a candidate that is not wired into a scenario (e.g. tools/build_growth_surface.py output
## under .tmp/; AR-MESH-20.9):
##
##   Godot --headless res://tools/audit_growth_surface.tscn -- --id=ivy_candidate \
##       --collision=res://.tmp/x/ivy_sim.glb --hero=res://assets/structures/ivy_hero.glb \
##       --sdf=res://.tmp/x/ivy_sim.sdf [--samples=...] [--seed=...] [--json-dir=...]
##
## --collision, --hero and --sdf go together and replace --structures; --id names the report
## (default "custom"). Builds each structure the way the game does (StructureBody from the
## collision and hero GLBs, MeshSdf from the baked volume), runs tools/growth_surface_audit.gd,
## prints the report (gates: IMPLEMENTATION.md SD-MESH-19.4; --samples is the class W count, class R
## gets half of it) and exits 1 when any structure fails SG-9 (a)-(c), 2 on a usage or asset error.

const Audit = preload("res://tools/growth_surface_audit.gd")
const StructureBodyScript = preload("res://src/world/structure_body.gd")
const MeshSdfScript = preload("res://src/world/mesh_sdf.gd")

const SCENARIO_DIR := "res://assets/structures/scenarios/"
const DEFAULT_STRUCTURES := "ivy,tower,square,surface_wall"


func _parse_args() -> Dictionary:
	var out := {"structures": "", "samples": "2000", "seed": "1", "json_dir": "",
		"id": "", "collision": "", "hero": "", "sdf": ""}
	var keys := ["structures", "samples", "seed", "json-dir", "id", "collision", "hero", "sdf"]
	for arg in OS.get_cmdline_user_args():
		var matched := false
		for key in keys:
			var prefix: String = "--%s=" % key
			if arg.begins_with(prefix):
				out[String(key).replace("-", "_")] = arg.substr(prefix.length())
				matched = true
				break
		if not matched:
			out["error"] = "unknown argument: %s" % arg
	var explicit := 0
	for key in ["collision", "hero", "sdf"]:
		if not String(out[key]).is_empty():
			explicit += 1
	if explicit != 0 and explicit != 3:
		out["error"] = "--collision, --hero and --sdf must be given together"
	elif explicit == 3 and not String(out["structures"]).is_empty():
		out["error"] = "--structures cannot be combined with --collision/--hero/--sdf"
	elif explicit == 0 and not String(out["id"]).is_empty():
		out["error"] = "--id needs --collision, --hero and --sdf"
	out["explicit"] = explicit == 3
	if String(out["structures"]).is_empty():
		out["structures"] = DEFAULT_STRUCTURES
	if String(out["id"]).is_empty():
		out["id"] = "custom"
	return out


## [[id, collision_glb, hero_glb, sdf_path], ...], or a String error.
func _targets(args: Dictionary) -> Variant:
	if bool(args["explicit"]):
		return [[args["id"], args["collision"], args["hero"], args["sdf"]]]
	var out: Array = []
	for structure_id in String(args["structures"]).split(",", false):
		var scenario_path := SCENARIO_DIR + structure_id + ".tres"
		if not ResourceLoader.exists(scenario_path):
			return "no scenario %s" % scenario_path
		var scenario: Resource = load(scenario_path)
		out.append([structure_id, scenario.get("collision_glb"), scenario.get("hero_glb"), scenario.get("sdf_path")])
	return out


func _ready() -> void:
	var args := _parse_args()
	if args.has("error"):
		printerr("[audit] ", args["error"])
		get_tree().quit(2)
		return
	var targets: Variant = _targets(args)
	if targets is String:
		printerr("[audit] ", targets)
		get_tree().quit(2)
		return
	var summary: Array = []
	var all_pass := true
	for target in targets:
		var structure_id: String = target[0]
		var collision_glb: String = target[1]
		var hero_glb: String = target[2]
		var sdf_path: String = target[3]
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
		var two_sided: StaticBody3D = Audit.make_two_sided_proxy(self, body)
		for _i in 2:
			await get_tree().physics_frame
		var audit = Audit.new()
		audit.setup(get_world_3d().direct_space_state, pieces, sdf)
		audit.set_two_sided_proxy(two_sided)
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
		remove_child(two_sided)
		two_sided.free()
		remove_child(body)
		body.free()
		await get_tree().physics_frame

	print("[audit] summary (SG-9 ratified gates, IMPLEMENTATION.md SD-MESH-19.4)")
	print("  structure      (a)W   p95|g|  p99|g|  max|g|  absent   (a)R   proud95 float95 max|g|   (b)   listed missing   (c)   face p95  max     inside+ closure  result")
	for row in summary:
		var r: Dictionary = row[1]
		var w: Dictionary = r["a"]["walls"]
		var roof: Dictionary = r["a"]["roof"]
		var b: Dictionary = r["b"]
		var c: Dictionary = r["c"]
		var roof_txt := "none   -       -       -     "
		if roof["present"] and int(roof.get("n", 0)) > 0:
			roof_txt = "%s   %.4f  %.4f  %.4f" % [Audit._verdict(roof["pass"]), roof["clip_p95"], roof["float_p95"], roof["max_abs"]]
		print("  %-13s  %s   %.4f  %.4f  %.4f  %4d     %s   %s  %4d   %4d      %s  %.4f    %.4f  %4d    %4d   %s" % [
			row[0], Audit._verdict(w["pass"]), w.get("p95_abs", NAN), w.get("p99_abs", NAN), w.get("max_abs", NAN),
			w.get("absent", 0), roof_txt,
			Audit._verdict(b["pass"]), b.get("listed", 0), b.get("unrepresented", 0),
			Audit._verdict(c["pass"]), c["face_p95"], c["face_max"], c["inside_not_negative"],
			c.get("closure_faults", -1), Audit._verdict(r["pass"])])
	get_tree().quit(0 if all_pass else 1)
