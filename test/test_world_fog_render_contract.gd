extends GutTest

const WorldFogParams = preload("res://src/world/world_fog_params.gd")
const WorldFogVolume = preload("res://src/world/world_fog_volume.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const SkySun = preload("res://src/world/sky_sun.gd")


func test_world_density_never_negative() -> void:
	var p: WorldFogParams = WorldFogParams.production()
	for d in [0.0, 15.0, 40.0, 90.0, 200.0]:
		assert_gte(HeroFog.world_density_at_distance(d, p), 0.0)


func test_fog_shader_haze_albedo_not_black() -> void:
	var fv := WorldFogVolume.create_volume(
		Vector3(-7.0, 1.0, -15.0), WorldFogParams.production(), SkySun.pale_horizon_haze_color())
	var sm := fv.material as ShaderMaterial
	var check := WorldFogVolume.validate_shader_contract(sm)
	assert_true(check["ok"], "shader contract: %s" % str(check["issues"]))
	var ha: Variant = sm.get_shader_parameter("haze_albedo")
	var glow: Variant = sm.get_shader_parameter("haze_glow")
	assert_true(ha is Vector3 or ha is Color)
	assert_true(glow is Vector3, "haze_glow must be set for pale emission")
	if glow is Vector3:
		var g := glow as Vector3
		assert_gte(g.x + g.y + g.z, 1.8, "glow should be pale horizon-toned")
	if ha is Vector3:
		var v := ha as Vector3
		assert_gte(v.x + v.y + v.z, 2.0, "haze albedo should be high (pale scatter)")
