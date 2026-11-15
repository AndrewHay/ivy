extends Node

## Opens one BuildingCatalog entry in the ordinary interactive session, skipping the picker. For
## entries that are loadable by id but have no picker button (`in_picker = false`), such as the
## relief test article's four growth-surface variants (ivy-b1e.6, SD-MESH-19.5).
##
## Usage (project root; windowed, the Godot binary as the whole command):
##   /Applications/Godot.app/Contents/MacOS/Godot res://tools/open_building.tscn -- --building=relief_article
##       [--no-anchors] [--quit-after=<seconds>]
##
## The session is the one the picker starts (main.gd): HUD time controls (Space / 1 / 2 / 3),
## orbit debug camera, dev tools. By default the scenario's authored seed anchors (A1-A4 on the
## article) are planted and growth starts at Grow speed; with --no-anchors the planting tool is
## left for you to click a spot. --quit-after is for scripted checks.

const _MAIN_SCENE := "res://src/main/main.tscn"
const _BuildingCatalog = preload("res://src/world/building_catalog.gd")


func _ready() -> void:
	var id := ""
	var anchors := true
	var quit_after := -1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--building="):
			id = arg.trim_prefix("--building=")
		elif arg == "--no-anchors":
			anchors = false
		elif arg.begins_with("--quit-after="):
			quit_after = float(arg.trim_prefix("--quit-after="))
		else:
			printerr("[open-building] unknown argument ", arg)
			get_tree().quit(2)
			return
	var known := false
	for entry in _BuildingCatalog.all():
		known = known or entry.id == id
	if not known:
		printerr("[open-building] --building=<catalog id> is required; unknown: '", id, "'")
		get_tree().quit(2)
		return
	var main := (load(_MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	var picker := main.get_node_or_null("UI/BuildingPicker")
	if picker != null:
		picker.queue_free()
	await main._on_building_selected(id)
	var sim: Node = main.get_node("Sim")
	var scenario = _BuildingCatalog.scenario_for(id)
	if anchors and scenario != null and main.get("_planting_tool") != null:
		for i in scenario.seed_positions.size():
			sim._plant_scenario_seed(i)
		main._on_plant_success()
	print("[open-building] %s: %d tips planted; Space pauses, 1 / 2 / 3 set Normal / Fast / Grow" % [
		id, sim.tips.tips.size()])
	if quit_after >= 0.0:
		await get_tree().create_timer(quit_after).timeout
		print("[open-building] %s: after %.0f s, tips=%d segments=%d" % [
			id, quit_after, sim.tips.tips.size(), sim.plant.segment_count()])
		get_tree().quit(0)
