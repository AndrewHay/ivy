extends GutTest

const DevOverlay = preload("res://src/ui/dev_overlay.gd")
const DevOverlayTooltips = preload("res://src/ui/dev_overlay_tooltips.gd")
const FieldViz = preload("res://src/ui/field_viz.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


func test_overlay_inert_lists_legacy_speed_knobs() -> void:
	# SD-TIME-2: SimClock owns speeds; legacy IvyParams fields stay exported for saves.
	assert_eq(
		IvyParams.OVERLAY_INERT,
		["speed_watch", "speed_fast", "speed_grow"],
		"legacy speed_* exports must stay marked inert"
	)


## ivy-n2l: the tuning panel covers a third of the screen, so it starts hidden; ` brings it up.
func _make_overlay() -> DevOverlay:
	var overlay := DevOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(Node.new(), IvyParams.new())
	return overlay


func test_overlay_starts_hidden() -> void:
	var overlay := _make_overlay()
	assert_false(overlay.visible, "tuning panel must be hidden until the developer asks for it")


func test_toggle_visible_shows_then_hides() -> void:
	var overlay := _make_overlay()
	overlay.toggle_visible()
	assert_true(overlay.visible, "first toggle shows the panel")
	overlay.toggle_visible()
	assert_false(overlay.visible, "second toggle hides it again")


func test_hidden_overlay_still_refreshes_without_error() -> void:
	var overlay := _make_overlay()
	overlay.refresh(SimClock.new(IvyParams.new()))
	assert_false(overlay.visible)


func test_every_overlay_param_has_tooltip() -> void:
	var params := IvyParams.new()
	var skip := {
		"resource_local_to_scene": true,
		"resource_name": true,
		"script": true,
		"dev_build": true,
	}
	for prop in params.get_property_list():
		var usage: int = prop["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var name: String = prop["name"]
		if skip.has(name):
			continue
		var tip := DevOverlayTooltips.for_param(name, name in IvyParams.OVERLAY_INERT)
		assert_false(
			tip.begins_with("No description"),
			"missing tooltip for IvyParams.%s" % name
		)
		assert_gt(tip.length(), 20, "tooltip too short for %s" % name)


func test_debug_field_cells_nonempty_after_build() -> void:
	var sim := SimRoot.new()
	var params := IvyParams.new()
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var sq := SurfaceQuery.new()
	sq.setup(null, null, TowerSdf.new(spec), PackedByteArray(), params)
	sim.setup(params, sq)
	var cells: Array = sim.env.debug_field_cells()
	assert_gt(cells.size(), 100, "tower shell should allocate many field cells")
	var row: Dictionary = cells[0]
	assert_true(row.has("d_l"))
	assert_true(row.has("crowding"))


func test_field_viz_builds_multimesh() -> void:
	var sim := SimRoot.new()
	var params := IvyParams.new()
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var sq := SurfaceQuery.new()
	sq.setup(null, null, TowerSdf.new(spec), PackedByteArray(), params)
	sim.setup(params, sq)
	var viz := FieldViz.new()
	add_child_autofree(viz)
	viz.setup(sim)
	viz.set_mode(FieldViz.Mode.D_L)
	var mm := viz.get_node("FieldVizMesh") as MultiMeshInstance3D
	assert_gt(mm.multimesh.instance_count, 100)
