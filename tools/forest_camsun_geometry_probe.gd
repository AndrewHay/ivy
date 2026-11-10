extends Node

const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")
const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const _CAM_SUN_LOCAL := Vector3(0.0, 2.0, 8.0)
const _AIM_Y := 2.0
const _RIG_SCALE_GEN := 1.35
const _FOV_DEG := 75.0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for seed in [1, 7, 12]:
		_probe_analytic_square(seed)
		await _probe_live(seed)
	get_tree().quit(0)


func _probe_analytic_square(seed: int) -> void:
	var layout := VillageLayout.generate(seed)
	if layout.fallback:
		return
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var pivot := Vector3(-7.0, 1.56, 0.0)
	var rig_pos := Vector3(pivot.x, pivot.y - _AIM_Y, pivot.z)
	var cam_pos := rig_pos + _CAM_SUN_LOCAL * _RIG_SCALE_GEN
	var fwd := Vector3(0.0, 0.0, -1.0)
	var backdrop_xz := Vector2(pivot.x, pivot.z)
	var trees := VillageScatterPositions.forest_tree_xz(layout)
	var trees_world: Array[Vector2] = []
	for p in trees:
		trees_world.append(p + backdrop_xz)
	_emit_report("analytic_square", seed, layout, pivot, rig_pos, cam_pos, fwd, trees, trees_world, backdrop_xz)


func _probe_live(seed: int) -> void:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	get_tree().root.add_child(main)
	for _i in range(35):
		await get_tree().process_frame
	main.call("apply_village_mode_live", "generated_village", seed)
	for _i in range(12):
		await get_tree().process_frame
	var world: Node3D = main.get_node("World")
	var cam := world.get_node("CameraRig/CamSun") as Camera3D
	var rig: Node3D = world.get_node("CameraRig")
	var backdrop: Node3D = world.get_node("VillageBackdrop")
	var layout: VillageLayout = backdrop.call("get_layout")
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var trees_world: Array[Vector2] = []
	for t in VillageScatterPositions.forest_tree_positions(layout):
		var w := backdrop.to_global(t.origin)
		trees_world.append(Vector2(w.x, w.z))
	var trees_layout: Array[Vector2] = VillageScatterPositions.forest_tree_xz(layout)
	var pivot: Vector3 = world.get_orbit_pivot()
	var fwd := -cam.global_transform.basis.z
	_emit_report(
		"live_main", seed, layout, pivot, rig.global_position, cam.global_position,
		fwd, trees_layout, trees_world, Vector2(backdrop.position.x, backdrop.position.z))
	main.queue_free()
	for _i in range(3):
		await get_tree().process_frame


func _emit_report(
		tag: String, seed: int, layout: VillageLayout, pivot: Vector3, rig_pos: Vector3,
		cam_pos: Vector3, fwd: Vector3, trees_layout: Array, trees_world: Array,
		backdrop_xz: Vector2) -> void:
	var g := layout.hamlet_centre_xz
	var r_lawn := layout.lawn_radius
	var hero := VillageLayout.HERO_DOOR_STOOP
	var hero_world := hero + backdrop_xz
	var wedge_layout := g + Vector2(0.0, (r_lawn - 3.0 + r_lawn + 11.0) * 0.5)
	var wedge_world := wedge_layout + backdrop_xz
	var to_wedge := Vector3(wedge_world.x - cam_pos.x, 0.0, wedge_world.y - cam_pos.y)
	var fwd_h := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var ang := 180.0
	if to_wedge.length() > 0.01:
		ang = rad_to_deg(acos(clampf(fwd_h.dot(to_wedge.normalized()), -1.0, 1.0)))
	var half_h := deg_to_rad(_FOV_DEG * 0.5)
	var in_fov := 0
	var nearest := INF
	var farthest := 0.0
	for p in trees_world:
		var wp: Vector2 = p
		var rel := Vector3(wp.x - cam_pos.x, 0.0, wp.y - cam_pos.y)
		var dist := rel.length()
		nearest = minf(nearest, dist)
		farthest = maxf(farthest, dist)
		if dist < 0.01:
			continue
		var dot := fwd_h.dot((rel / dist))
		if dot > 0.0 and acos(clampf(dot, -1.0, 1.0)) <= half_h:
			in_fov += 1
	var band_lo := r_lawn - 3.0
	var band_hi := r_lawn + 11.0
	var in_band := 0
	var band_ahead := 0
	for p in trees_layout:
		var lp: Vector2 = p
		var dg := lp - g
		var rg := dg.length()
		if rg < band_lo or rg > band_hi or absf(atan2(dg.x, dg.y)) > 0.62:
			continue
		in_band += 1
		var wp := lp + backdrop_xz
		var rel := Vector3(wp.x - cam_pos.x, 0.0, wp.y - cam_pos.y)
		if rel.length() > 0.01 and fwd_h.dot(rel.normalized()) > 0.0:
			band_ahead += 1
	print("=== forest_cam_geom [%s] seed=%d ===" % [tag, seed])
	print("  G=", g, " R=", r_lawn, " hero_layout=", hero, " hero_world=", hero_world)
	print("  pivot=", pivot, " rig=", rig_pos, " CamSun=", cam_pos)
	print("  forward_horiz=", fwd_h, " (CamSun looks toward -Z from south side)")
	print("  wedge_mid_layout=", wedge_layout, " wedge_mid_world=", wedge_world)
	print("  angle_fwd_to_wedge=%.1f deg (0=ahead, 180=behind camera)" % ang)
	print("  trees=%d in_horiz_FOV=%d nearest=%.1f farthest=%.1f" % [
		trees_world.size(), in_fov, nearest, farthest])
	print("  production_wedge_band=%d ahead_of_cam=%d fog %.0f..%.0f" % [
		in_band, band_ahead, layout.fog_begin, layout.fog_end])
