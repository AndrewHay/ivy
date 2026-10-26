class_name HelpPanel
extends PanelContainer

## The "?" popup: every keyboard and mouse command in one place. The rows live in
## `sections()` as plain data so a test can check them against the real bindings; if you
## change a binding in debug_camera.gd, sim_clock.gd or main.gd, change its row here too.


## One entry per section: {title: String, rows: Array of [keys, action]}.
## Dev-only keys are included only for dev builds, so a player build never advertises them.
static func sections(dev_build: bool) -> Array:
	var result: Array = [
		{
			"title": "Camera",
			"rows": [
				["Left-click", "Glide the orbit origin to the nearest surface under the cursor (wall, mesh, or ground)"],
				["Scroll", "Zoom in / out (wide pull-back and close-up detail)"],
				["Tab", "Unlock — captured mouse orbits · Lock — free cursor for HUD and buttons"],
				["W A S D or arrows", "Rotate the view up, down, left, and right"],
				["R or Home", "Reset orbit, zoom, and origin to the starting view"],
				["While planting", "Left-click plants ivy · Tab still unlocks orbit · origin click is off"],
			],
		},
		{
			"title": "Time",
			"rows": [
				["Space", "Pause / resume"],
				["1 / 2 / 3", "Watch / Fast / Grow (after planting)"],
			],
		},
		{
			"title": "Interface",
			"rows": [
				["? or F1", "Show / hide this help"],
				["Esc", "Close this help"],
				["Sun compass", "Bottom-left: the way you're looking is up; high sun is near the middle"],
			],
		},
	]
	if dev_build:
		result.append({
			"title": "Developer",
			"rows": [
				["F", "Field overlay on / off"],
				["`", "Tuning panel on / off"],
				["F9", "Save debug snapshot (highlight tool)"],
				["Shift+F9", "Quick snapshot (no highlights)"],
			],
		})
	return result


func _init() -> void:
	# Swallow clicks so a click on the popup can never reach the planting tool behind it.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Fill the panel. Separate from _init so the HUD can pass the build flavour.
func build(dev_build: bool) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	# Sits over the scene, so it must be readable: near-opaque, not the theme's see-through grey.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.11, 0.96)
	style.border_color = Color(0.65, 0.85, 0.6, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Keyboard commands"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)

	for section in sections(dev_build):
		var heading := Label.new()
		heading.text = section.title
		heading.add_theme_font_size_override("font_size", 15)
		heading.add_theme_color_override("font_color", Color(0.65, 0.85, 0.6))
		column.add_child(heading)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 28)
		grid.add_theme_constant_override("v_separation", 4)
		column.add_child(grid)
		for row in section.rows:
			var keys := Label.new()
			keys.text = row[0]
			keys.custom_minimum_size = Vector2(150, 0)
			grid.add_child(keys)
			var action := Label.new()
			action.text = row[1]
			grid.add_child(action)
