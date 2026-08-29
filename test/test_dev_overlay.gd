extends GutTest

const DevOverlay = preload("res://src/ui/dev_overlay.gd")
const DevOverlayTooltips = preload("res://src/ui/dev_overlay_tooltips.gd")
const FieldViz = preload("res://src/ui/field_viz.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


func test_overlay_inert_list_covers_w086_knobs() -> void:
	assert_eq(IvyParams.OVERLAY_INERT.size(), 2)
	assert_true("leaf_expand_distance" in IvyParams.OVERLAY_INERT)
	assert_true("tip_cap_m1" in IvyParams.OVERLAY_INERT)


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
