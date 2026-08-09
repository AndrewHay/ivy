extends GutTest

const Conv = preload("res://src/core/conv.gd")


func test_gravity_is_y_down() -> void:
	assert_eq(Conv.GRAVITY, Vector3(0.0, -1.0, 0.0))


func test_solar_noon_sun_vector() -> void:
	var s := Conv.solar_noon_direction(45.0)
	assert_almost_eq(s.x, 0.0, 1e-5)
	assert_gt(s.y, 0.0)
	assert_gt(s.z, 0.0)
	assert_almost_eq(s.length(), 1.0, 1e-5)


func test_tangent_basis_vertical_wall() -> void:
	var n := Vector3(0.0, 0.0, 1.0)
	var b := Conv.tangent_basis(n)
	assert_almost_eq(b.x.length(), 1.0, 1e-5)
	assert_almost_eq(b.y.length(), 1.0, 1e-5)
	assert_almost_eq(b.z.length(), 1.0, 1e-5)
	assert_almost_eq(b.x.dot(b.y), 0.0, 1e-5)
	assert_almost_eq(b.y.dot(b.z), 0.0, 1e-5)
	assert_almost_eq(b.z.dot(b.x), 0.0, 1e-5)
	var cross_uv := b.x.cross(b.y)
	assert_almost_eq(cross_uv.dot(n), 1.0, 1e-4)


func test_tangent_basis_horizontal_surface() -> void:
	var n := Vector3(0.0, 1.0, 0.0)
	var b := Conv.tangent_basis(n)
	assert_almost_eq(b.x.length(), 1.0, 1e-5)
	assert_almost_eq(b.y.length(), 1.0, 1e-5)
	assert_almost_eq(b.z.length(), 1.0, 1e-5)
	assert_almost_eq(b.x.dot(b.y), 0.0, 1e-5)
	assert_almost_eq(b.y.dot(b.z), 0.0, 1e-5)
	assert_almost_eq(b.z.dot(b.x), 0.0, 1e-5)


func test_tangent_basis_continuity_near_degenerate() -> void:
	var prev := Conv.tangent_basis(Vector3(0.01, 0.9999, 0.0).normalized())
	for i in range(20):
		var t := float(i) / 19.0
		var n := Vector3(0.0, 1.0 - t * 0.2, t * 0.2).normalized()
		var b := Conv.tangent_basis(n)
		assert_almost_eq(b.x.length(), 1.0, 1e-4)
		if i > 0:
			assert_gt(absf(prev.x.dot(b.x)), 0.5)
		prev = b
