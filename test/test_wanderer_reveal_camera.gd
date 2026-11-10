extends GutTest

const WandererRevealCamera = preload("res://src/presentation/wanderer/wanderer_reveal_camera.gd")
const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")
const WandererImagePlacement = preload("res://src/presentation/wanderer/wanderer_image_placement.gd")


func _layout_rects() -> Array:
	var layout := VillageLayout.authored()
	return WandererRevealCamera.obstruction_rects(layout)


func _placement_at_house(door: Vector2, n: Vector2, aspect: float = 4.0 / 3.0) -> Dictionary:
	var p := WandererParams.production()
	return WandererImagePlacement.compute(door, n, p, aspect)


func test_phrase_bubble_eye_cleared() -> void:
	var p := WandererParams.production()
	var figure := Vector2(13.0, -8.5)
	var rects := _layout_rects()
	var out := Vector2(0.0, 1.0)
	var shot := WandererRevealCamera.compute_bubble_phrase(
		figure, out, rects, 7.0, 3.0, p.figure_height_m)
	var eye_xz := Vector2(shot["eye"].x, shot["eye"].z)
	assert_true(WandererRevealCamera.eye_outside_cottages(eye_xz, rects))
	assert_true(WandererRevealCamera.los_clear(eye_xz, figure, rects))
	assert_almost_eq(shot["eye"].y, 3.0, 0.01)


func test_reveal_front_classic_houses() -> void:
	var layout := VillageLayout.authored()
	var p := WandererParams.production()
	var rects := WandererRevealCamera.obstruction_rects(layout)
	var aspects := [4.0 / 3.0, 16.0 / 9.0, 1.0, 3.0 / 4.0]
	for spec in layout.cottages:
		var door_info := VillageBackdrop.cottage_door(spec as Dictionary)
		var door: Vector2 = door_info[0]
		var n: Vector2 = door_info[1]
		for asp in aspects:
			var pl := _placement_at_house(door, n, asp)
			var shot := WandererRevealCamera.compute_reveal_front(pl, rects, deg_to_rad(60.0), asp, door)
			var eye_xz := Vector2(shot["eye"].x, shot["eye"].z)
			assert_true(WandererRevealCamera.eye_outside_cottages(eye_xz, rects))
			assert_true(WandererRevealCamera.los_clear(eye_xz, pl["figure_xz"], rects))
			assert_ne(int(shot.get("try", -1)), -1, "reveal front must not fall back for %s" % spec.get("id", "?"))
			var P: Vector2 = pl["figure_xz"]
			var subj := [Vector3(P.x, 0, P.y), Vector3(P.x, 2, P.y)]
			for bc in WandererImagePlacement.bottom_corners_world(pl):
				subj.append(bc)
				subj.append(bc + Vector3(0, pl["size"].y, 0))
			assert_true(WandererRevealCamera.subject_in_frustum(
				shot["eye"], shot["look"], deg_to_rad(60.0), asp, subj))


func test_reveal_oblique_gap() -> void:
	var layout := VillageLayout.authored()
	var rects := WandererRevealCamera.obstruction_rects(layout)
	for spec in layout.cottages.slice(0, 3):
		var door_info := VillageBackdrop.cottage_door(spec as Dictionary)
		var door: Vector2 = door_info[0]
		var n: Vector2 = door_info[1]
		var pl := _placement_at_house(door, n)
		var asp := 16.0 / 9.0
		var shot := WandererRevealCamera.compute_reveal_oblique(pl, rects, deg_to_rad(60.0), asp, door)
		var eye_xz := Vector2(shot["eye"].x, shot["eye"].z)
		assert_true(WandererRevealCamera.eye_outside_cottages(eye_xz, rects))


func test_reveal_front_views_along_minus_n() -> void:
	var layout := VillageLayout.authored()
	var rects := WandererRevealCamera.obstruction_rects(layout)
	var spec: Dictionary = layout.cottages[0] as Dictionary
	var door_info := VillageBackdrop.cottage_door(spec)
	var door: Vector2 = door_info[0]
	var n: Vector2 = door_info[1]
	var pl := _placement_at_house(door, n)
	var shot := WandererRevealCamera.compute_reveal_front(pl, rects, deg_to_rad(60.0), 16.0 / 9.0, door)
	var eye_xz := Vector2(shot["eye"].x, shot["eye"].z)
	var P: Vector2 = pl["figure_xz"]
	var view := (P - eye_xz).normalized()
	assert_gt(view.dot(-n), 0.95)


func test_reveal_oblique_about_45_deg() -> void:
	var layout := VillageLayout.authored()
	var rects := WandererRevealCamera.obstruction_rects(layout)
	for spec_v in layout.cottages.slice(0, 3):
		var spec: Dictionary = spec_v as Dictionary
		var door_info := VillageBackdrop.cottage_door(spec)
		var pl := _placement_at_house(door_info[0], door_info[1])
		var shot := WandererRevealCamera.compute_reveal_oblique(
			pl, rects, deg_to_rad(60.0), 16.0 / 9.0, door_info[0])
		if int(shot.get("try", -1)) == -1:
			continue
		var P: Vector2 = pl["figure_xz"]
		var eye_xz := Vector2(shot["eye"].x, shot["eye"].z)
		var view := (P - eye_xz).normalized()
		var n: Vector2 = pl["normal"]
		var left: Vector2 = pl["left"]
		var oblique := -(n * cos(PI * 0.25) + left * sin(PI * 0.25)).normalized()
		assert_gt(view.dot(oblique), 0.85)
		return
	assert_true(false, "need one classic cottage with non-fallback oblique reveal")


func test_generated_seeds_1_and_7_no_fallback() -> void:
	for seed in [1, 7]:
		var layout := VillageLayout.generate(seed)
		var rects := WandererRevealCamera.obstruction_rects(layout)
		var spec: Dictionary = layout.cottages[0] as Dictionary
		var door_info := VillageBackdrop.cottage_door(spec)
		var pl := _placement_at_house(door_info[0], door_info[1])
		var shot := WandererRevealCamera.compute_reveal_front(
			pl, rects, deg_to_rad(60.0), 16.0 / 9.0, door_info[0])
		assert_ne(int(shot.get("try", -1)), -1, "seed %d must not fallback" % seed)
