extends GutTest

## SG-8 — interior/exterior light separation on surface_wall (open door).

const StructureBody = preload("res://src/world/structure_body.gd")
const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const LightBake = preload("res://src/env/light_bake.gd")
const Solar = preload("res://src/env/solar.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")

const SIM_GLB := "res://assets/structures/surface_wall_sim.glb"
const SIM_SDF := "res://assets/structures/surface_wall_sim.sdf"


func _build_bake() -> Dictionary:
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
	var bounds := sdf.mesh_aabb.grow(params.field_shell_halfwidth)
	bake.bake(sq, bounds)
	return {"bake": bake, "sq": sq, "params": params}


func _direct_sun_hours(bake: LightBake, point: Vector3, normal: Vector3) -> int:
	var hours := 0
	for h in LightBake.HOURS:
		if bake.visibility_at(point, h, normal) > 0.5:
			hours += 1
	return hours


func test_sg8_interior_exterior_svf_separation() -> void:
	if not FileAccess.file_exists(SIM_GLB):
		pending("surface_wall not built")
		return
	var d := await _build_bake()
	var bake: LightBake = d.bake
	var sq: SurfaceQuery = d.sq
	# South wall matched pair (x=0 bay, ~1.5 m height).
	var ext_hit := sq.raycast(Vector3(0.0, 1.5, 6.0), Vector3(0.0, 1.5, 0.0))
	assert_true(ext_hit.hit, "exterior south raycast")
	var int_hit := sq.raycast(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, 5.0))
	assert_true(int_hit.hit, "interior south raycast")
	var ext_on := ext_hit.position
	var int_on := int_hit.position
	var ext_n := ext_hit.normal
	var int_n := int_hit.normal
	var ext_svf := bake.svf_at(ext_on, ext_n)
	var int_svf := bake.svf_at(int_on, int_n)
	gut.p("SG-8 south wall SVF exterior=%.3f interior=%.3f delta=%.3f"
		% [ext_svf, int_svf, ext_svf - int_svf])
	assert_lte(int_svf, 0.10, "interior SVF should be ≤0.10")
	assert_gte(ext_svf - int_svf, 0.25, "exterior−interior SVF should be ≥0.25")
	var ext_hours := _direct_sun_hours(bake, ext_on, ext_n)
	var int_hours := _direct_sun_hours(bake, int_on, int_n)
	gut.p("SG-8 direct-sun hours exterior=%d interior=%d" % [ext_hours, int_hours])
	assert_gte(ext_hours, 4, "sun-facing exterior should have ≥4 direct-sun hours")
	assert_lte(int_hours, 1, "deep interior should have ≤1 direct-sun hour")
