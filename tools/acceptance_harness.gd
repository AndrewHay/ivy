extends Node

## W-014 headless acceptance runner for AS-1, AS-2, AS-3(a)/(b).
##
## Usage (from project root):
##   Godot res://tools/acceptance_harness.tscn
##   Godot res://tools/acceptance_harness.tscn -- --phase=metrics|as3b|all

const _DEFAULT_PARAMS: IvyParams = preload("res://src/params/ivy_params_default.tres")
const _MAIN_SCENE := "res://src/main/main.tscn"
const _Executor = preload("res://tools/ui_script_executor.gd")
const _ACCEPTANCE_SCRIPT := "res://tools/ui_scripts/m4_acceptance.txt"
const _AS3B_ON_SCRIPT := "res://tools/ui_scripts/m4_as3b_gate_on.txt"
const _AS3B_OFF_SCRIPT := "res://tools/ui_scripts/m4_as3b_gate_off.txt"
const _HARNESS_OUTDIR := "res://.tmp/harness/"
const _AS3B_REL_TOLERANCE := 0.02


func _ready() -> void:
	var failures: PackedStringArray = []
	var expected_hash: String = _DEFAULT_PARAMS.content_hash()
	print("[harness] ivy_params_default.content_hash=", expected_hash)

	var phase: String = _parse_phase_arg()
	if phase.is_empty() or phase == "all":
		failures += await _run_ui_script_phase("AS-1/2/3a", _ACCEPTANCE_SCRIPT)
		failures += await _run_as3b_phase()
	elif phase == "metrics":
		failures += await _run_ui_script_phase("AS-1/2/3a", _ACCEPTANCE_SCRIPT)
	elif phase == "as3b":
		failures += await _run_as3b_phase()
	else:
		printerr("[harness] unknown --phase=", phase, " (use all|metrics|as3b)")
		get_tree().quit(2)
		return

	if failures.is_empty():
		print("[harness] PASS")
		get_tree().quit(0)
	else:
		for msg in failures:
			printerr("[harness] FAIL: ", msg)
		get_tree().quit(1)


func _parse_phase_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="):
			return a.substr(8).strip_edges().to_lower()
	return "all"


func _run_ui_script_phase(label: String, script_res: String) -> PackedStringArray:
	var script_path := ProjectSettings.globalize_path(script_res)
	if not FileAccess.file_exists(script_path):
		return PackedStringArray(["%s: missing script %s" % [label, script_res]])
	var outdir := ProjectSettings.globalize_path(_HARNESS_OUTDIR)
	var result: Dictionary = await _run_script_in_process(script_path, outdir)
	if result.get("exit_code", 1) != OK:
		return PackedStringArray([
			"%s: script exited %d (see [ui-script] errors above)" % [label, result.get("exit_code", 1)]
		])
	var live_hash: String = result.get("params_hash", "")
	if live_hash != _DEFAULT_PARAMS.content_hash():
		return PackedStringArray([
			"%s: non-conforming params hash %s (expected %s)" % [
				label, live_hash, _DEFAULT_PARAMS.content_hash()
			]
		])
	return PackedStringArray()


func _run_as3b_phase() -> PackedStringArray:
	var on_result: Dictionary = await _run_script_in_process(
		ProjectSettings.globalize_path(_AS3B_ON_SCRIPT),
		ProjectSettings.globalize_path(_HARNESS_OUTDIR.path_join("as3b_on/"))
	)
	if on_result.get("exit_code", 1) != OK:
		return PackedStringArray(["AS-3(b): gate-on script failed with exit %d" % on_result.get("exit_code", 1)])
	var off_result: Dictionary = await _run_script_in_process(
		ProjectSettings.globalize_path(_AS3B_OFF_SCRIPT),
		ProjectSettings.globalize_path(_HARNESS_OUTDIR.path_join("as3b_off/"))
	)
	if off_result.get("exit_code", 1) != OK:
		return PackedStringArray(["AS-3(b): gate-off script failed with exit %d" % off_result.get("exit_code", 1)])
	var len_on: float = on_result.get("total_stem_length", -1.0)
	var len_off: float = off_result.get("total_stem_length", -1.0)
	if len_on < 0.0 or len_off < 0.0:
		return PackedStringArray(["AS-3(b): missing total_stem_length from simulation"])
	print("[harness] AS-3(b) day-29 stem_length gate_on=%.6f gate_off=%.6f" % [len_on, len_off])
	if not stem_lengths_within_relative_tolerance(len_on, len_off, _AS3B_REL_TOLERANCE):
		var rel: float = absf(len_on - len_off) / maxf(len_off, 1e-6)
		return PackedStringArray([
			"AS-3(b): cumulative stem length differs by %.2f%% (limit ±%.0f%%)" % [
				rel * 100.0, _AS3B_REL_TOLERANCE * 100.0
			]
		])
	print("[harness] AS-3(b) PASS (relative delta %.3f%%)" % [
		absf(len_on - len_off) / maxf(len_off, 1e-6) * 100.0
	])
	return PackedStringArray()


func _run_script_in_process(script_path: String, outdir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(outdir)
	var ps := load(_MAIN_SCENE) as PackedScene
	if ps == null:
		printerr("[harness] failed to load ", _MAIN_SCENE)
		return {"exit_code": 2}
	var scene_root := ps.instantiate()
	scene_root.set("script_driven", true)
	add_child(scene_root)
	for _i in range(30):
		await get_tree().process_frame
	var main: Node = scene_root
	var exit_code: int = await _Executor.run_script(get_tree(), main, script_path, outdir)
	var sim: Node = main.get_node_or_null("Sim")
	var params_hash := ""
	var total_stem_length := -1.0
	var game_day := -1.0
	if sim != null:
		var params: IvyParams = sim.get("params") as IvyParams
		if params != null:
			params_hash = params.content_hash()
		var plant: PlantData = sim.get("plant") as PlantData
		if plant != null:
			total_stem_length = plant.total_length
		var clock: SimClock = sim.get("clock") as SimClock
		if clock != null:
			game_day = clock.game_day
	scene_root.queue_free()
	for _f in range(3):
		await get_tree().process_frame
	return {
		"exit_code": exit_code,
		"params_hash": params_hash,
		"total_stem_length": total_stem_length,
		"game_day": game_day,
	}


static func stem_lengths_within_relative_tolerance(
	a: float, b: float, rel_tolerance: float
) -> bool:
	var denom: float = maxf(b, 1e-6)
	return absf(a - b) / denom <= rel_tolerance
