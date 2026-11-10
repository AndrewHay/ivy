## Frame-time breakdown for the Birthday scenario: grass and wanderer on/off,
## generated vs classic village, from the game camera and a high wide camera.
## Non-headless only: /Applications/Godot.app/Contents/MacOS/Godot res://tools/profile_birthday_fps.tscn
extends Node

const _MAIN := "res://src/main/main.tscn"
const _IVY := "res://assets/structures/scenarios/ivy.tres"
const _WARMUP := 40
const _SAMPLES := 90

var _main: Node
var _world: Node3D
var _cam: Camera3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[bday-fps] requires non-headless")
		get_tree().quit(1)
		return
	_main = (load(_MAIN) as PackedScene).instantiate()
	_main.set("script_driven", true)
	_main.set("script_building_id", "birthday")
	_main.set("mesh_scenario", load(_IVY))
	_main.set("_village_mode", "generated_village")
	_main.set("_village_seed", 7)
	add_child(_main)
	for _i in range(40):
		await get_tree().process_frame
	_world = _main.get_node("World")
	_cam = Camera3D.new()
	_world.add_child(_cam)

	await _row("generated  all on")
	_set_grass(false)
	await _row("generated  grass OFF")
	_set_grass(true)
	_set_wanderer(false)
	await _row("generated  wanderer OFF")
	_set_grass(false)
	await _row("generated  grass+wanderer OFF")
	_set_grass(true)
	_set_wanderer(true)
	print("[bday-fps] grass instances generated=%d" % _grass_instances())

	_main.call("apply_village_mode_live", "classic_village", 0)
	for _i in range(20):
		await get_tree().process_frame
	await _row("classic    all on")
	print("[bday-fps] grass instances classic=%d" % _grass_instances())
	get_tree().quit(0)


func _row(label: String) -> void:
	var line := "[bday-fps] %-30s" % label
	var rig := _world.get_node_or_null("CameraRig")
	if rig != null and rig.has_method("select"):
		rig.call("select", 0)
	line += " game_cam=%5.1f fps" % await _measure()
	var pivot: Vector3 = _world.call("get_orbit_pivot")
	_cam.look_at_from_position(pivot + Vector3(0.0, 14.0, 26.0), pivot)
	_cam.make_current()
	line += "  high_cam=%5.1f fps" % await _measure()
	print(line)


func _measure() -> float:
	var ctrl: Node = _world.call("get_wanderer_controller")
	for _i in range(_WARMUP):
		_tick(ctrl)
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var total := 0.0
	var gpu := 0.0
	var cpu_r := 0.0
	var proc := 0.0
	for _i in range(_SAMPLES):
		var t0 := Time.get_ticks_usec()
		_tick(ctrl)
		RenderingServer.force_draw(false)
		await get_tree().process_frame
		total += float(Time.get_ticks_usec() - t0) / 1000.0
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu_r += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var n := float(_SAMPLES)
	print("[bday-fps]     frame=%.1fms gpu=%.1fms render_cpu=%.1fms process=%.1fms draws=%d prims=%d" % [
		total / n, gpu / n, cpu_r / n, proc / n,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	return 1000.0 / (total / n)


func _tick(ctrl: Node) -> void:
	if ctrl != null and ctrl.process_mode != Node.PROCESS_MODE_DISABLED:
		ctrl.call("tick", 1.0 / 60.0, false)


func _grass_nodes() -> Array[Node]:
	var out: Array[Node] = []
	for n in _world.find_children("*", "MultiMeshInstance3D", true, false):
		if n.name.begins_with("Scatter_Grass"):
			out.append(n)
	return out


func _set_grass(on: bool) -> void:
	for n in _grass_nodes():
		(n as Node3D).visible = on


func _grass_instances() -> int:
	var total := 0
	for n in _grass_nodes():
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm != null:
			total += mm.instance_count
	return total


func _set_wanderer(on: bool) -> void:
	var ctrl: Node3D = _world.call("get_wanderer_controller")
	if ctrl == null:
		return
	ctrl.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	ctrl.visible = on
