extends GutTest

const StemMeshBuilder = preload("res://src/render/stem_mesh.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


func test_stem_radius_order_and_tip_taper() -> void:
	var p := IvyParams.new()
	assert_almost_eq(StemMeshBuilder.stem_radius(p, 0, 0.15), 0.006, 1e-6,
		"order-0 segment at full tip distance uses base radius")
	assert_almost_eq(StemMeshBuilder.stem_radius(p, 0, 0.0), 0.006 * 0.35, 1e-6,
		"tip taper floor is 0.35× at shoot start")
	var r_order2 := StemMeshBuilder.stem_radius(p, 2, 0.15)
	assert_almost_eq(r_order2, 0.006 / (1.0 + 0.25 * 2.0), 1e-6,
		"branch-order taper follows SD-STEM 1/(1+0.25·o)")


func test_catmull_rom_passes_through_endpoints() -> void:
	var p0 := Vector3(0, 0, 0)
	var p1 := Vector3(1, 0, 0)
	var p2 := Vector3(2, 1, 0)
	var p3 := Vector3(3, 1, 0)
	assert_true(StemMeshBuilder.catmull_rom_point(p0, p1, p2, p3, 0.0).is_equal_approx(p1))
	assert_true(StemMeshBuilder.catmull_rom_point(p0, p1, p2, p3, 1.0).is_equal_approx(p2))
