extends GutTest

const WandererImagePlacement = preload("res://src/presentation/wanderer/wanderer_image_placement.gd")
const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")


func test_height_and_aspect() -> void:
	var p := WandererParams.production()
	var pl := WandererImagePlacement.compute(Vector2.ZERO, Vector2(0, 1), p, 4.0 / 3.0)
	assert_almost_eq(pl["size"].y, 7.0, 1e-4)
	assert_almost_eq(pl["size"].x, 7.0 * 4.0 / 3.0, 1e-3)


func test_wide_clamp() -> void:
	var p := WandererParams.production()
	var pl := WandererImagePlacement.compute(Vector2.ZERO, Vector2(0, 1), p, 4.0)
	assert_almost_eq(pl["size"].x, 16.0, 1e-3)
	assert_almost_eq(pl["size"].y, 4.0, 1e-3)


func test_worked_example_door_origin() -> void:
	var p := WandererParams.production()
	var n := Vector2(0, 1)
	var pl := WandererImagePlacement.compute(Vector2.ZERO, n, p, 4.0 / 3.0)
	var P: Vector2 = pl["figure_xz"]
	assert_almost_eq(P.x, 0.0, 1e-4)
	assert_almost_eq(P.y, 2.5, 1e-4)
	var corner: Vector3 = pl["corner"]
	assert_almost_eq(corner.x, 0.0, 1e-4)
	assert_almost_eq(corner.y, 2.05, 1e-4)
	assert_almost_eq(corner.z, 2.5, 1e-4)
	var centre: Vector3 = pl["centre"]
	assert_almost_eq(centre.x, 4.667, 0.01)
	assert_almost_eq(centre.y, 5.55, 0.01)
	assert_almost_eq(centre.z, 2.5, 1e-3)
	assert_almost_eq(float(pl["yaw"]), 0.0, 1e-4)
	assert_false(pl.has("side"))


func test_hero_xz_irrelevant() -> void:
	var p := WandererParams.production()
	var n := Vector2(1, 0).normalized()
	var pl0 := WandererImagePlacement.compute(Vector2(5, 0), n, p, 1.0)
	p.hero_xz = Vector2(0, -40)
	var pl1 := WandererImagePlacement.compute(Vector2(5, 0), n, p, 1.0)
	p.hero_xz = Vector2(100, 100)
	var pl2 := WandererImagePlacement.compute(Vector2(5, 0), n, p, 1.0)
	assert_eq(pl0, pl2)
	assert_eq(pl0, pl1)


func test_wall_distance_all_corners() -> void:
	var p := WandererParams.production()
	var door := Vector2(3.0, -2.0)
	for az_i in 16:
		var az := TAU * float(az_i) / 16.0
		var n := Vector2(sin(az), cos(az))
		for standoff in [0.3, 1.0, 2.5, 4.0]:
			p.present_standoff_m = standoff
			var s := p.present_standoff()
			var pl := WandererImagePlacement.compute(door, n, p, 4.0 / 3.0)
			var P: Vector2 = pl["figure_xz"]
			assert_almost_eq(P.x, door.x + n.x * s, 1e-3)
			assert_almost_eq(P.y, door.y + n.y * s, 1e-3)
			var front := WandererImagePlacement.quad_front_normal_xz(float(pl["yaw"]))
			assert_gt(front.dot(n), 0.999)
			var left: Vector2 = pl["left"]
			assert_gt(left.dot(n), -1e-3)
			for bc in WandererImagePlacement.bottom_corners_world(pl):
				var c: Vector3 = bc
				var dist := (Vector2(c.x, c.z) - door).dot(n)
				assert_almost_eq(dist, s, 1e-3)
			var corner: Vector3 = pl["corner"]
			assert_almost_eq(corner.y, 2.05, 1e-2)
