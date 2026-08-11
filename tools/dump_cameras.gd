extends SceneTree

## Prints the parsed transform of every canonical camera in main.tscn.
##
## Reads the PackedScene's SceneState rather than instantiating, so it needs no
## rendering, no simulation warm-up and runs under --headless in a second.
##
## Why this exists: main.tscn stores camera transforms with the 12-float
## Transform3D(...) form, and it is not self-evident from the file whether those
## floats are basis rows or basis columns. Reasoning about it produced two
## contradictory answers, one of which agreed with the rendered frames and one
## with a unit test. This prints what Godot itself parsed, which settles it.
##
## Usage:
##   Godot --headless --script tools/dump_cameras.gd


func _initialize() -> void:
	var scene := load("res://src/main/main.tscn") as PackedScene
	if scene == null:
		push_error("could not load res://src/main/main.tscn")
		quit(1)
		return

	var state := scene.get_state()
	for i in range(state.get_node_count()):
		var path := str(state.get_node_path(i))
		if not path.contains("CameraRig/"):
			continue

		var name := state.get_node_name(i)
		var xform := Transform3D.IDENTITY
		for p in range(state.get_node_property_count(i)):
			if state.get_node_property_name(i, p) == "transform":
				xform = state.get_node_property_value(i, p)

		# Camera3D looks along its local -Z.
		var fwd := -xform.basis.z
		var origin := xform.origin
		# Where the view axis crosses the tower's vertical centre line (x=0, z=0),
		# expressed as a height. Tower spans y = 0 .. 3.5, centre y = 1.75.
		var aim_height := INF
		if absf(fwd.z) > 1e-6:
			var t := -origin.z / fwd.z
			if t > 0.0:
				aim_height = origin.y + fwd.y * t

		print("%-14s origin=(%6.3f, %6.3f, %6.3f)  forward=(%6.3f, %6.3f, %6.3f)  pitch=%+6.1f°  aims at y=%s" % [
			name,
			origin.x, origin.y, origin.z,
			fwd.x, fwd.y, fwd.z,
			rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0))),
			"%.2f" % aim_height if aim_height != INF else "never (points away)",
		])

	quit(0)
