extends GutTest

## W-096 — enclosed interior reads dim, not black; exterior wall unchanged.

const StructureBody = preload("res://src/world/structure_body.gd")
const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const LightBake = preload("res://src/env/light_bake.gd")
const Solar = preload("res://src/env/solar.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")

const SIM_GLB := "res://assets/structures/surface_wall_sim.glb"
const SIM_SDF := "res://assets/structures/surface_wall_sim.sdf"


func test_deep_interior_has_leak_light_not_black() -> void:
	if not FileAccess.file_exists(SIM_GLB):
		pending("surface_wall not built")
		return
	var params := IvyParams.new()
	var body := StructureBody.new()
	add_child_autofree(body)
	body.build(SIM_GLB)
	await get_tree().physics_frame
	var sdf := MeshSdf.new()
	sdf.load_from_file(SIM_SDF)
	var sq := SurfaceQuery.new()
	sq.setup(
		body.get_world_3d().direct_space_state,
		body,
		sdf,
		body.face_material,
		params
	)
	var bake := LightBake.new(params, Solar.new(params))
	bake.bake(sq, sdf.mesh_aabb.grow(params.field_shell_halfwidth))
	var ext_hit := sq.raycast(Vector3(0.0, 1.5, 6.0), Vector3(0.0, 1.5, 0.0))
	var int_hit := sq.raycast(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, 5.0))
	assert_true(ext_hit.hit and int_hit.hit)
	var ext_on := ext_hit.position
	var int_on := int_hit.position
	var ext_n := ext_hit.normal
	var int_n := int_hit.normal
	var int_svf := bake.svf_at(int_on, int_n)
	var int_leak := bake.leak_at(int_on, int_n)
	var ext_svf := bake.svf_at(ext_on, ext_n)
	assert_lt(int_svf, 0.12, "interior face should be starved of sky (low SVF)")
	assert_gt(int_leak, 0.02, "interior face should have horizon escape toward open door")
	var room_p := bake.daily_mean_p(int_n, int_svf, 0.0, int_leak)
	var ext_p := bake.daily_mean_p(
		ext_n,
		ext_svf,
		bake.visibility_at(ext_on, 12, ext_n),
		bake.leak_at(ext_on, ext_n)
	)
	assert_gt(room_p, 0.0, "interior must not be exactly black (W-096)")
	assert_lt(room_p, ext_p * 0.35, "interior leak must stay much dimmer than exterior sun wall")
