extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")


func test_edge_outward_horizon_not_flat() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	if params.variant == 0:
		pass
	# rework4: hills are north-only. Look north (−Z direction) from the lawn edge.
	var g := layout.hamlet_centre_xz
	var lawn_r := layout.lawn_radius
	var margin := 2.0
	var allowed := maxf(lawn_r - margin, 2.0)
	## North = −Z direction in world space; phi=PI in placement coords.
	var dir_out := Vector2(0.0, -1.0)  # North
	var edge_out := CameraBounds.clamp_free_camera_eye(
		Vector3(g.x + dir_out.x * allowed, 5.0, g.y + dir_out.y * allowed),
		g, lawn_r, margin)
	var fwd := Vector3(dir_out.x, 0.0, dir_out.y)
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var max_ang := 0.0
	# rework5: hills begin at r_inner=100m from center; ridges 155-260m.
	for dist in range(80, 300, 5):
		var p := Vector2(edge_out.x + fwd.x * dist, edge_out.z + fwd.z * dist)
		var y := HillsHeightfield.sample_y(p, layout, params, t_seed)
		var dy := y - edge_out.y
		var horiz := float(dist)
		var ang := rad_to_deg(atan2(dy, horiz))
		max_ang = maxf(max_ang, ang)
	assert_gt(max_ang, 8.0, "max terrain elevation angle looking north %.2f°" % max_ang)
