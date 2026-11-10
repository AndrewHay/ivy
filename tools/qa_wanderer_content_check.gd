extends SceneTree
## QA tool (ivy-ydiy.7): headless check of wanderer behaviour with missing/empty content
## and shipped content, driving the brain on a synthetic two-house graph.
## Run: Godot --headless --script res://tools/qa_wanderer_content_check.gd

const WandererBrain = preload("res://src/presentation/wanderer/wanderer_brain.gd")
const WandererRouteGraph = preload("res://src/presentation/wanderer/wanderer_route_graph.gd")
const WandererContent = preload("res://src/presentation/wanderer/wanderer_content.gd")
const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")

const DT := 1.0 / 30.0


func _graph(p: WandererParams) -> WandererRouteGraph:
	var houses: Array[Dictionary] = [
		{"name": "A", "door": Vector2(-10, 0), "normal": Vector2(1, 0)},
		{"name": "B", "door": Vector2(10, 0), "normal": Vector2(-1, 0)},
	]
	var paths: Array = [
		[Vector2(-12, 0), Vector2(-9.5, 0), Vector2(0, 0), Vector2(9.5, 0), Vector2(12, 0)],
	]
	return WandererRouteGraph.from_raw(houses, paths, p)


func _run(label: String, content_dir: String, sim_s: float) -> void:
	var p := WandererParams.production()
	p.content_dir = content_dir
	var c := WandererContent.load_from_dir(p)
	print("[qa] ", label, " dir=", content_dir, " images=", c.image_count(), " quotes=", c.quote_count())
	var b := WandererBrain.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	b.setup(p, _graph(p), c, rng)
	b.start()
	var t := 0.0
	var prev_state := b.state
	var state_t0 := 0.0
	var houses_seq: Array = []
	var states_seen := {}
	var bubbles := 0
	var prev_bubble := ""
	var walk_clock_at_bubble: Array = []
	var inside_durs: Array = []
	var show_durs: Array = []
	var last_house := -1
	while t < sim_s:
		b.tick(DT)
		t += DT
		states_seen[WandererBrain.state_name(b.state)] = true
		if b.state != prev_state:
			var dur := t - state_t0
			if prev_state == WandererBrain.State.INSIDE:
				inside_durs.append(snappedf(dur, 0.01))
			if prev_state == WandererBrain.State.SHOWING:
				show_durs.append(snappedf(dur, 0.01))
			if b.state == WandererBrain.State.DOOR_PAUSE:
				houses_seq.append(b.target_house)
			prev_state = b.state
			state_t0 = t
		if b.bubble_text != "" and prev_bubble == "":
			bubbles += 1
			if b.state == WandererBrain.State.WALKING:
				walk_clock_at_bubble.append(snappedf(t, 0.1))
		prev_bubble = b.bubble_text
	print("[qa]   sim_s=", sim_s, " cycles=", b.cycles_completed, " states=", states_seen.keys(),
		" bubbles=", bubbles)
	print("[qa]   door visits (house ids)=", houses_seq)
	print("[qa]   INSIDE durations=", inside_durs.slice(0, 6))
	print("[qa]   SHOWING durations=", show_durs.slice(0, 6))
	print("[qa]   walking-quote sim times=", walk_clock_at_bubble.slice(0, 8))


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tmp/wanderer/empty_content/"))
	_run("shipped", "res://wanderer_content/", 900.0)
	_run("missing-folder", "res://nonexistent_wanderer_xyz/", 600.0)
	_run("empty-folder", "res://.tmp/wanderer/empty_content/", 600.0)
	print("[qa] done (no crash)")
	quit(0)
