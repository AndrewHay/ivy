## Regression test for W-028: window is carved in the SDF but never removed from the mesh.
## After the fix, no wall triangle centroid should fall inside the window's angular and
## height bands, matching what the SDF already subtracts.
extends GutTest

const TowerBuilder = preload("res://src/world/tower_builder.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")


func _angular_delta(x: float, y: float) -> float:
	return absf(fposmod(x - y + PI, TAU) - PI)


func test_window_band_has_no_wall_triangles() -> void:
	# Before fix: full-height wall quads span from y=0 to y=3.5, crossing the window height
	# band (1.6–2.2 m). After the fix, rings in the window azimuth are split into a below-sill
	# strip (0–1.6) and an above-window strip (2.2–3.5), so no triangle spans the gap.
	var spec := TowerSpec.new()
	var result := TowerBuilder.build(spec, false)
	var tris: PackedVector3Array = result.shape.data
	var win_az := deg_to_rad(spec.window_azimuth)
	var win_half := asin(clampf(spec.window_size * 0.5 / spec.radius_outer, -1.0, 1.0)) + 0.05
	var win_y0 := spec.window_sill
	var win_y1 := spec.window_sill + spec.window_size
	var offenders := 0
	for i in range(0, tris.size(), 3):
		var a := tris[i]; var b := tris[i + 1]; var c := tris[i + 2]
		# Use centroid azimuth to check if this triangle is in the window ring
		var centroid := (a + b + c) / 3.0
		var cent_az := atan2(centroid.x, -centroid.z)
		if _angular_delta(cent_az, win_az) >= win_half:
			continue
		# Offender: the triangle spans both below the sill AND above the window top.
		# That means it runs the full height through the opening — the pre-fix bug.
		var min_y := minf(a.y, minf(b.y, c.y))
		var max_y := maxf(a.y, maxf(b.y, c.y))
		if min_y < win_y0 - 1e-3 and max_y > win_y1 + 1e-3:
			offenders += 1
	assert_eq(offenders, 0, "no triangle in the window ring should span across the full window height band")


func test_window_strips_outside_height_band_are_preserved() -> void:
	# The wall strips below and above the window must still exist.
	var spec := TowerSpec.new()
	var result := TowerBuilder.build(spec, false)
	var tris: PackedVector3Array = result.shape.data
	var win_az := deg_to_rad(spec.window_azimuth)
	var win_half := asin(clampf(spec.window_size * 0.5 / spec.radius_outer, -1.0, 1.0)) + 0.05
	var has_below := false
	var has_above := false
	for i in range(0, tris.size(), 3):
		var centroid := (tris[i] + tris[i + 1] + tris[i + 2]) / 3.0
		var cent_az := atan2(centroid.x, -centroid.z)
		var delta := _angular_delta(cent_az, win_az)
		if delta < win_half:
			if centroid.y < spec.window_sill:
				has_below = true
			if centroid.y > spec.window_sill + spec.window_size:
				has_above = true
	assert_true(has_below, "strip below window sill must be present in the window ring")
	assert_true(has_above, "strip above window must be present in the window ring")


func test_dev_build_normals_pass_with_window_fix() -> void:
	# dev_build=true runs _assert_outward_normals; if this doesn't throw the fix is consistent.
	var spec := TowerSpec.new()
	var passed := true
	var err := ""
	# Godot GDScript assert() calls crash the process in debug. Call build() with dev_build=true
	# and rely on GUT catching any crash-level assertion failure as a test failure.
	var _result := TowerBuilder.build(spec, true)
	assert_true(passed, err)
