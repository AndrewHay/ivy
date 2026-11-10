extends GutTest

const PlaygroundScene = preload("res://scenes/playground/wanderer_playground.tscn")
const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")
const WandererImagePlacement = preload("res://src/presentation/wanderer/wanderer_image_placement.gd")


func _root() -> Node3D:
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	return root


func _assert_rendered_image(root: Node3D, az_deg: float, standoff_m: float) -> void:
	root.call("playground_set_door_azimuth_deg", az_deg)
	var p: WandererParams = root.call("playground_params")
	p.present_standoff_m = standoff_m
	root.set("_manual_image", true)
	root.set("_manual_image_idx", 0)
	root.set("_play_mode", 0)
	root.call("_sync_presentation")
	if root.get("_content").image_count() == 0:
		return
	var mi: MeshInstance3D = root.get("_image_mi")
	assert_true(mi.visible)
	var n: Vector2 = root.call("playground_door_normal")
	var pl := WandererImagePlacement.compute(Vector2.ZERO, n, p, root.get("_content").aspect(0))
	var expect: Vector3 = pl["corner"]
	var head_top := Vector3(pl["figure_xz"].x, p.figure_height_m, pl["figure_xz"].y)
	var best := INF
	var sz: Vector2 = (mi.mesh as QuadMesh).size
	var xf := mi.global_transform
	for sx in [-0.5, 0.5]:
		var corner := xf * Vector3(sx * sz.x, -0.5 * sz.y, 0.0)
		best = minf(best, corner.distance_to(expect))
		best = minf(best, corner.distance_to(head_top))
	assert_lt(best, 0.01, "bottom corner near head at az=%s" % az_deg)
	var front := mi.global_transform.basis.z.normalized()
	var front_xz := Vector2(front.x, front.z).normalized()
	assert_gt(front_xz.dot(n), 0.99)
	var slab_n := Vector3(-n.x, 0.0, -n.y).normalized()
	var img_n := -mi.global_transform.basis.z.normalized()
	assert_gt(slab_n.dot(img_n), 0.99)
	var s := p.present_standoff()
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			var corner := xf * Vector3(sx * sz.x, sy * sz.y, 0.0)
			var dist := Vector2(corner.x, corner.z).dot(n)
			assert_gte(dist, s - 1e-3)


func test_preview_corners_azimuths_and_standoffs() -> void:
	var root := await _root()
	for az in [0.0, 90.0, 180.0, 270.0]:
		for standoff in [0.3, 1.0, 2.5, 4.0]:
			_assert_rendered_image(root, az, standoff)
