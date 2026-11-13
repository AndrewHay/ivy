extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")


func test_mesh_has_vertex_in_lawn_toe_band() -> void:
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var mesh := HillsHeightfield.build_mesh(layout, HillsParams.production())
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var g := layout.hamlet_centre_xz
	var lo := layout.lawn_radius
	var hi := layout.lawn_radius + 2.5
	var found := false
	for v: Vector3 in verts:
		var r := Vector2(v.x, v.z).distance_to(g)
		if r >= lo and r <= hi:
			found = true
			break
	assert_true(found, "HillTerrain mesh must include vertices in %.1f–%.1f m toe band" % [lo, hi])
