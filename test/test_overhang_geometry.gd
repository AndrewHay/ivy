## Geometry and SDF tests for the overhang (eave-wall) fixture (ivy-9us).
## Fast suite — no physics frame required.
extends GutTest

const OverhangSpec = preload("res://src/world/overhang_spec.gd")
const OverhangSdf = preload("res://src/world/overhang_sdf.gd")
const OverhangBuilder = preload("res://src/world/overhang_builder.gd")
const OverhangWall = preload("res://src/world/overhang_wall.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const Conv = preload("res://src/core/conv.gd")
const MaterialRegistry = preload("res://src/world/material_registry.gd")
const BuildingCatalog = preload("res://src/world/building_catalog.gd")
const MainScene = preload("res://src/main/main.tscn")


func _spec() -> OverhangSpec:
	return OverhangSpec.new()


func _sdf() -> OverhangSdf:
	return OverhangSdf.new(_spec())


# ── SDF sign tests ────────────────────────────────────────────────────────────

func test_overhang_sdf_inside_wall_body_is_negative() -> void:
	var sdf := _sdf()
	## Midpoint of wall body (y=2.5, z=-0.2 is the wall centre)
	assert_lt(sdf.signed_distance(Vector3(0.0, 2.5, -0.2)), 0.0)


func test_overhang_sdf_inside_slab_is_negative() -> void:
	var sdf := _sdf()
	## Midpoint of slab (y=5.15, z=0.3)
	assert_lt(sdf.signed_distance(Vector3(0.0, 5.15, 0.3)), 0.0)


func test_overhang_sdf_below_soffit_outside_wall_is_positive() -> void:
	var sdf := _sdf()
	## 0.5 m in front of wall face (z=0.5 > 0), height below soffit y=4.5
	assert_gt(sdf.signed_distance(Vector3(0.0, 4.5, 0.5)), 0.0)


func test_overhang_sdf_above_roof_is_positive() -> void:
	var sdf := _sdf()
	## Above the roof top (y=5.3+0.1)
	assert_gt(sdf.signed_distance(Vector3(0.0, 5.5, 0.3)), 0.0)


func test_overhang_sdf_past_eave_lip_is_positive() -> void:
	var sdf := _sdf()
	## Beyond the eave lip (z=1.1 > slab_projection=1.0)
	assert_gt(sdf.signed_distance(Vector3(0.0, 5.15, 1.1)), 0.0)


func test_overhang_sdf_union_connects_wall_and_slab() -> void:
	var sdf := _sdf()
	## Junction point: top of wall / bottom of slab at z=-0.2, y=5.0
	## Should be inside (negative) because both boxes share this corner
	assert_le(sdf.signed_distance(Vector3(0.0, 5.0, -0.2)), 0.0)


# ── Gradient / normal tests ───────────────────────────────────────────────────

func test_overhang_sdf_gradient_south_on_wall_face() -> void:
	var sdf := _sdf()
	## Point on (or just outside) the south wall face
	var g := sdf.gradient_normalized(Vector3(0.0, 2.5, 0.05))
	assert_gt(g.dot(Conv.SOUTH), 0.9)


func test_overhang_sdf_gradient_down_on_soffit() -> void:
	var sdf := _sdf()
	## Point just below the soffit underside (y=5.0, z=0.5 = midpoint of eave span)
	var g := sdf.gradient_normalized(Vector3(0.0, 4.8, 0.5))
	## Should point DOWN since the soffit is the nearest surface
	assert_lt(g.dot(Conv.UP), -0.8)


func test_overhang_sdf_gradient_up_on_roof() -> void:
	var sdf := _sdf()
	## Point just above the roof (y=5.35, z=0.3)
	var g := sdf.gradient_normalized(Vector3(0.0, 5.35, 0.3))
	assert_gt(g.dot(Conv.UP), 0.9)


# ── Mesh geometry tests ───────────────────────────────────────────────────────

func test_overhang_builder_produces_20_triangles() -> void:
	## 10 quads × 2 triangles each = 20 triangles
	var spec := _spec()
	var built := OverhangBuilder.build(spec, false)
	assert_eq(built.triangle_count, 20)


func test_overhang_builder_all_brick_material() -> void:
	var spec := _spec()
	var built := OverhangBuilder.build(spec, false)
	for mat_id in built.face_material:
		assert_eq(mat_id, MaterialRegistry.BRICK_WALL)


func test_overhang_builder_aabb_contains_wall_and_slab() -> void:
	var spec := _spec()
	var built := OverhangBuilder.build(spec, false)
	var aabb := built.mesh.get_aabb()
	## x: [-8, 8]
	assert_almost_eq(aabb.position.x, -8.0, 0.01)
	assert_almost_eq(aabb.size.x, 16.0, 0.01)
	## y: [0, 5.3]
	assert_almost_eq(aabb.position.y, 0.0, 0.01)
	assert_almost_eq(aabb.size.y, 5.3, 0.01)
	## z: [-0.4, 1.0]  → position.z=-0.4, size.z=1.4
	assert_almost_eq(aabb.position.z, -0.4, 0.01)
	assert_almost_eq(aabb.size.z, 1.4, 0.01)


func test_overhang_sdf_outward_normals() -> void:
	## Every triangle's authored normal points away from the union SDF interior.
	var spec := _spec()
	var built := OverhangBuilder.build(spec, false)
	var sdf := OverhangSdf.new(spec)
	var arrays := built.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tris := PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.size() > 0:
		for i in range(0, indices.size(), 3):
			tris.append(verts[indices[i]])
			tris.append(verts[indices[i + 1]])
			tris.append(verts[indices[i + 2]])
	else:
		for i in range(0, verts.size(), 3):
			tris.append(verts[i])
			tris.append(verts[i + 1])
			tris.append(verts[i + 2])
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n_geo := -(b - a).cross(c - a).normalized()
		var centroid := (a + b + c) / 3.0
		assert_gt(sdf.signed_distance(centroid + n_geo * 0.01), 0.0,
			"outward probe should be positive at %s n=%s" % [centroid, n_geo])
		assert_lt(sdf.signed_distance(centroid - n_geo * 0.01), 0.0,
			"inward probe should be negative at %s n=%s" % [centroid, n_geo])


func test_overhang_sdf_bounds() -> void:
	var sdf := _sdf()
	var b := sdf.bounds()
	assert_almost_eq(b.position.x, -8.0, 0.01)
	assert_almost_eq(b.position.y, 0.0, 0.01)
	assert_almost_eq(b.position.z, -0.4, 0.01)
	assert_almost_eq(b.size.x, 16.0, 0.01)
	assert_almost_eq(b.size.y, 5.3, 0.01)
	assert_almost_eq(b.size.z, 1.4, 0.01)


# ── BuildingCatalog / SurfaceQuery integration ────────────────────────────────

func test_building_catalog_overhang_is_procedural() -> void:
	assert_true(BuildingCatalog.is_procedural("overhang"))


func test_building_catalog_overhang_label() -> void:
	var found := false
	for entry in BuildingCatalog.all():
		if entry.id == "overhang":
			assert_eq(entry.label, "Eave wall")
			found = true
	assert_true(found, "expected 'overhang' entry in BuildingCatalog")


func test_overhang_backend_tag_is_wall_sdf() -> void:
	## SurfaceQuery must report "WallSdf" (not "TowerSdf") so upward_base stays OFF.
	var ow := OverhangWall.new()
	add_child_autofree(ow)
	var spec := OverhangSpec.new()
	ow.build_from_spec(spec, false)
	await get_tree().physics_frame
	var sq := SurfaceQuery.new()
	sq.setup(
		ow.get_world_3d().direct_space_state,
		ow,
		OverhangSdf.new(spec),
		ow.face_material,
		IvyParams.new()
	)
	assert_eq(sq.backend_tag(), "WallSdf")


func test_world_overhang_wiring() -> void:
	## Full-scene smoke: load_building("overhang") returns a valid SurfaceQuery
	## with tag "WallSdf" and null seed_anchors.
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	var world: Node = main.get_node("World")
	world.call("load_building", "overhang")
	await get_tree().physics_frame
	await get_tree().process_frame
	var params: IvyParams = main.get("params")
	var surface: SurfaceQuery = world.call("get_surface_query", params)
	assert_not_null(surface)
	assert_eq(surface.backend_tag(), "WallSdf")
	assert_null(world.call("get_seed_anchors"), "overhang should have no seed_anchors")
