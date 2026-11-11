class_name WorldFogVolume
extends RefCounted

const WorldFogParams = preload("res://src/world/world_fog_params.gd")
const SkySun = preload("res://src/world/sky_sun.gd")
const _SHADER := preload("res://assets/shaders/world_hero_fog.gdshader")


static func create_volume(
		anchor: Vector3, params: WorldFogParams, haze_color: Color = Color(0.88, 0.86, 0.8)) -> FogVolume:
	var fv := FogVolume.new()
	fv.name = "WorldHeroFog"
	fv.size = WorldFogParams.DEFAULT_VOLUME_SIZE
	fv.position = Vector3(anchor.x, anchor.y + fv.size.y * 0.35, anchor.z)
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	fv.material = mat
	apply_params(fv, anchor, params, haze_color)
	return fv


static func pale_shader_colors(haze_color: Color) -> Dictionary:
	var glow := Color(haze_color.r, haze_color.g, haze_color.b).lightened(0.08)
	var albedo := Color.WHITE.lerp(glow, 0.55)
	return {
		"haze_albedo": Vector3(albedo.r, albedo.g, albedo.b),
		"haze_glow": Vector3(glow.r, glow.g, glow.b),
		"glow_strength": SkySun.world_fog_glow_strength(),
	}


static func validate_shader_contract(sm: ShaderMaterial) -> Dictionary:
	var issues: PackedStringArray = []
	if sm == null:
		return {"ok": false, "issues": ["no material"]}
	var dens: float = float(sm.get_shader_parameter("max_density"))
	if dens < 0.0:
		issues.append("max_density negative")
	var ha: Variant = sm.get_shader_parameter("haze_albedo")
	if ha is Vector3:
		var v := ha as Vector3
		if v.x < 0.05 or v.y < 0.05 or v.z < 0.05:
			issues.append("haze_albedo too dark")
	elif ha is Color:
		var c := ha as Color
		if c.r < 0.05 or c.g < 0.05 or c.b < 0.05:
			issues.append("haze_albedo too dark")
	else:
		issues.append("haze_albedo missing")
	return {"ok": issues.is_empty(), "issues": issues}


static func apply_params(
		fv: FogVolume, anchor: Vector3, params: WorldFogParams, haze_color: Color = Color(0.88, 0.86, 0.8)) -> void:
	if fv == null or params == null:
		return
	fv.size = WorldFogParams.DEFAULT_VOLUME_SIZE
	fv.position = Vector3(anchor.x, anchor.y + fv.size.y * 0.25, anchor.z)
	if fv.material is ShaderMaterial:
		var sm := fv.material as ShaderMaterial
		sm.set_shader_parameter("hero_anchor", anchor)
		sm.set_shader_parameter("clear_radius", params.clear_radius_m)
		sm.set_shader_parameter("thick_radius", params.thick_radius_m)
		sm.set_shader_parameter("max_density", maxf(params.max_density, 0.0))
		sm.set_shader_parameter("falloff_kind", int(params.falloff))
		var cols := pale_shader_colors(haze_color)
		sm.set_shader_parameter("haze_albedo", cols["haze_albedo"])
		sm.set_shader_parameter("haze_glow", cols["haze_glow"])
		sm.set_shader_parameter("glow_strength", cols["glow_strength"])
