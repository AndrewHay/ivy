## Headless: per-azimuth hill forest counts in 58–95 m band (layout space).
extends Node

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsForestPlacement = preload("res://src/playground/hills_forest_placement.gd")
const HillsFogTint = preload("res://src/playground/hills_fog_tint.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")
const WorldFogParams = preload("res://src/world/world_fog_params.gd")

const SECTORS := 6
const R_LO := 58.0
const R_HI := 95.0


func _ready() -> void:
	var seeds: Array[int] = [1, 7, 12]
	for seed in seeds:
		_probe_seed(seed)
	get_tree().quit(0)


func _probe_seed(seed: int) -> void:
	var layout := VillageLayout.generate(seed)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	if layout.fallback:
		print("seed %d fallback" % seed)
		return
	var params := HillsParams.production()
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var backdrop := VillageScatterPositions.forest_tree_xz(layout)
	var xforms := HillsForestPlacement.hill_forest_transforms(layout, params, t_seed, backdrop)
	var g := layout.hamlet_centre_xz
	var counts := PackedInt32Array()
	counts.resize(SECTORS)
	for t in xforms:
		var p := Vector2(t.origin.x, t.origin.z)
		var rg := p.distance_to(g)
		if rg < R_LO or rg > R_HI:
			continue
		var phi := atan2(p.x - g.x, p.y - g.y)
		var sec := int(floor((phi + PI) / TAU * SECTORS)) % SECTORS
		counts[sec] += 1
	var hero := VillageLayout.HERO_DOOR_STOOP
	var centre := g
	var dir_out := (hero - centre).normalized() if hero.distance_to(centre) > 0.1 else Vector2(0, -1)
	dir_out = -dir_out
	var edge_phi := atan2(dir_out.x, dir_out.y)
	var edge_sec := int(floor((edge_phi + PI) / TAU * SECTORS)) % SECTORS
	var fwd := atan2(
		ForestPlaygroundCamera.camsun_forward().x, ForestPlaygroundCamera.camsun_forward().z)
	var cam_sec := int(floor((fwd + PI) / TAU * SECTORS)) % SECTORS
	print("=== seed %d total=%d edge_outward sec=%d count=%d ===" % [
		seed, xforms.size(), edge_sec, counts[edge_sec]])
	for s in range(SECTORS):
		print("  sector %d: %d" % [s, counts[s]])
	_edge_haze(layout, params, seed)


func _edge_haze(layout: VillageLayout, params: HillsParams, seed: int) -> void:
	var g := layout.hamlet_centre_xz
	var hero := VillageLayout.HERO_DOOR_STOOP
	var centre := g
	var lawn_r := layout.lawn_radius
	var margin := 2.0
	var allowed := maxf(lawn_r - margin, 2.0)
	var dir_out := (hero - centre).normalized() if hero.distance_to(centre) > 0.1 else Vector2(0, -1)
	dir_out = -dir_out
	var edge_out := CameraBounds.clamp_free_camera_eye(
		Vector3(centre.x + dir_out.x * allowed, 5.0, centre.y + dir_out.y * allowed),
		centre, lawn_r, margin)
	var fog_b := layout.fog_begin
	var fog_e := layout.fog_end
	var anchor := ForestPlaygroundCamera.hero_fog_anchor_world()
	var camsun := HillsFogTint.reference_camera_pos()
	var edge_cam := edge_out
	print("  haze along edge_out ray (cam=edge, WORLD_AROUND_HERO):")
	for dist in [62, 75, 88, 100, 115]:
		var wp := Vector3(
			edge_out.x + dir_out.x * dist, 2.0, edge_out.z + dir_out.y * dist)
		var wf: WorldFogParams = WorldFogParams.production()
		var h_edge := HeroFog.haze_at_world_point(
			HeroFog.FogModel.WORLD_AROUND_HERO, edge_cam, wp, anchor, fog_b, fog_e, wf)
		var h_sun := HeroFog.haze_at_world_point(
			HeroFog.FogModel.WORLD_AROUND_HERO, camsun, wp, anchor, fog_b, fog_e, wf)
		var col := HillsFogTint.color_for_world(wp, params, layout, fog_b, fog_e, camsun)
		print(
			"    d=%d haze_edge=%.3f haze_camsun=%.3f baked_rgb=(%.3f,%.3f,%.3f)" % [
				dist, h_edge, h_sun, col.r, col.g, col.b])
