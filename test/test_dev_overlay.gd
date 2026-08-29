extends GutTest

const DevOverlay = preload("res://src/ui/dev_overlay.gd")
const FieldViz = preload("res://src/ui/field_viz.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


func test_overlay_inert_list_covers_w086_knobs() -> void:
	assert_eq(IvyParams.OVERLAY_INERT.size(), 11)
	assert_true("stem_tip_taper" in IvyParams.OVERLAY_INERT)
	assert_true("tip_cap_m1" in IvyParams.OVERLAY_INERT)


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
