## GUT pre-run hook (wired in res://.gutconfig.json): refuse to run on an incomplete import cache.
##
## A headless `--import` that can't find Blender cancels the whole batch and still exits 0
## (first Linux run: 14 of ~2,500 files). GUT then runs anyway: every glTF load fails, each
## village backdrop build prints hundreds of errors, the suite runs many times slower, and on
## Linux it stopped printing and grew to 10 GB before it was killed. Fail fast instead, with
## a non-zero exit code and the fix in the message.
extends GutHookScript

## Abort when more than this fraction of the imported sources has no file in .godot/imported.
## A cancelled batch leaves nearly all of them missing; one odd asset that failed to import
## only logs a warning.
const MAX_MISSING_FRACTION := 0.10
const EXIT_IMPORT_INCOMPLETE := 3
const _LIST_LIMIT := 5


func run() -> void:
	var r := scan("res://")
	var total: int = r["total"]
	var missing: Array = r["missing"]
	if missing.is_empty():
		return
	var sample := ", ".join(missing.slice(0, _LIST_LIMIT))
	if total == 0 or float(missing.size()) / float(total) <= MAX_MISSING_FRACTION:
		push_warning("[gut-pre-run] %d of %d imported sources have no cache file (e.g. %s)" % [
			missing.size(), total, sample])
		return
	printerr("[gut-pre-run] ABORT: import cache incomplete: %d of %d sources have no file in "
			% [missing.size(), total]
			+ ".godot/imported (e.g. %s). Run a full `godot --headless --path . --import` first. " % sample
			+ "On Linux, set filesystem/import/blender/blender_path in Godot's editor settings, or "
			+ "the import cancels the whole batch and still exits 0 (README -> Linux hosts).")
	# GUT exits 0 after a pre-run abort (it only counts failed tests), so request the exit code
	# here and wait for the main loop to stop before GUT can quit with 0.
	Engine.get_main_loop().quit(EXIT_IMPORT_INCOMPLETE)
	await Engine.get_main_loop().create_timer(60.0).timeout
	abort()


## Walks [param root] for *.import sidecars and checks that each one's imported file exists.
## Returns {"total": int, "missing": Array[String]} (source paths). Hidden directories
## (.godot, .git, .claude, .tmp) and directories with a .gdignore are skipped, as Godot does.
static func scan(root: String) -> Dictionary:
	var out := {"total": 0, "missing": []}
	_scan_dir(root, out)
	return out


static func _scan_dir(dir_path: String, out: Dictionary) -> void:
	var d := DirAccess.open(dir_path)
	if d == null or d.file_exists(".gdignore"):
		return
	for f: String in d.get_files():
		if not f.ends_with(".import"):
			continue
		var cfg := ConfigFile.new()
		if cfg.load(dir_path.path_join(f)) != OK or not cfg.has_section("remap"):
			continue
		var targets: Array[String] = []
		for key: String in cfg.get_section_keys("remap"):
			# "path", or "path.s3tc" / "path.etc2" for VRAM-compressed textures.
			if key == "path" or key.begins_with("path."):
				targets.append(str(cfg.get_value("remap", key)))
		if targets.is_empty():
			continue  # importer "keep" / "skip": nothing is written to the cache
		out["total"] += 1
		var found := false
		for t in targets:
			if FileAccess.file_exists(t):
				found = true
				break
		if not found:
			out["missing"].append(dir_path.path_join(f.trim_suffix(".import")))
	for sub: String in d.get_directories():
		_scan_dir(dir_path.path_join(sub), out)
