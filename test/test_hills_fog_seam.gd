extends GutTest

## ivy-ska0.2: hill terrain must use engine fog (not fog_disabled + manual planar haze).

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsFogTint = preload("res://src/playground/hills_fog_tint.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const WorldFogParams = preload("res://src/world/world_fog_params.gd")


func test_hills_shader_tracks_sun_and_flat_wash() -> void:
	var text := FileAccess.get_file_as_string(
		"res://src/render/shaders/village_ground_hills.gdshader")
	assert_true(text.contains("uniform vec3  u_sun_dir"),
		"HillTerrain must use runtime sun direction (not hardcoded noon vector)")
	assert_true(text.contains("u_twilight"),
		"HillTerrain must attenuate flat sectors at twilight")
	assert_true(text.contains("flat_sector"),
		"east/west must wash to horizon tone outside north wedge")


func test_hills_terrain_shader_does_not_disable_fog() -> void:
	var text := FileAccess.get_file_as_string(
		"res://src/render/shaders/village_ground_hills.gdshader")
	assert_false(text.is_empty())
	assert_false(text.contains("fog_disabled"),
		"HillTerrain must receive engine depth + volumetric fog (no fog_disabled)")
	assert_false(text.contains("haze_t"),
		"manual planar haze must be removed; atmosphere comes from HeroFog + depth fog")


func test_world_volumetric_density_peak_is_not_a_plateau() -> void:
	var p: WorldFogParams = WorldFogParams.production()
	var at_thick := HeroFog.world_density_at_distance(p.thick_radius_m, p)
	var beyond := HeroFog.world_density_at_distance(p.thick_radius_m + 25.0, p)
	assert_lt(beyond, at_thick, "density must fall after thick radius (smooth bell, no ring)")


func test_hills_haze_monotone_matches_hero_fog_integration() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var anchor := ForestPlaygroundCamera.hero_fog_anchor_world()
	var cam := HillsFogTint.reference_camera_pos()
	var wf: WorldFogParams = WorldFogParams.production()
	var g := layout.hamlet_centre_xz
	var prev := 0.0
	for dist in [90, 130, 170, 220, 260]:
		var wp := Vector3(g.x, 2.0, g.y + float(dist))
		var h := HeroFog.haze_at_world_point(
			HeroFog.FogModel.WORLD_AROUND_HERO, cam, wp, anchor,
			layout.fog_begin, layout.fog_end, wf)
		assert_gte(h, prev - 0.001, "haze should be monotone with planar distance @ %d" % dist)
		prev = h
