class_name ForestParams
extends Resource

const SCHEMA := "forest_playground.v1"
const PRESET_PRODUCTION := "Production"
const CUSTOM_PRESET := "Custom"

## Algorithm selector — see ForestKnobSpec.VARIANT_DESCRIPTIONS.
@export var variant: int = 0

@export_group("Sampling")
@export var layout_seed: int = 7
@export var tree_count: int = -1  ## -1 = layout.pine_count
@export var lcg_seed: int = 7
@export var min_sep_m: float = 3.0
@export var w_max: float = 1.45

@export_group("Wedge band")
@export var wedge_phi_half_rad: float = 0.62
@export var wedge_r_inset_m: float = 3.0
@export var wedge_r_outset_m: float = 11.0
@export var wedge_sample_frac: float = 0.84
@export var wedge_quota_frac: float = 0.72
@export var wedge_min_before_collar: int = 26
@export var back_yard_z_max: float = 5.5

@export_group("Collar / scatter box")
@export var collar_inset_m: float = 2.0
@export var collar_outer_m: float = 12.0
@export var wedge_z_max: float = 38.0
@export var wedge_x_half: float = 18.0
@export var scatter_box_x_half: float = 62.0
@export var scatter_box_z_back: float = 50.0
@export var scatter_box_z_front: float = 42.0

@export_group("CamSun corridor")
@export var camsun_corridor_on: bool = true
@export var camsun_x_half: float = 5.0
@export var camsun_z_min: float = 2.0
@export var camsun_z_max: float = 9.5
@export var camsun_corridor_y_slack: float = 7.0

@export_group("Weights")
@export var wedge_weight: float = 1.45
@export var collar_weight_lo: float = 0.55
@export var collar_weight_hi: float = 0.75
@export var scatter_weight: float = 0.06

@export_group("Tree scale")
@export var scale_min: float = 1.0
@export var scale_max: float = 1.5

## Variant 1 — distance bias toward outer band (0 = off).
@export var deep_outer_bias: float = 0.0
## Variant 2 — arc ring overrides (used when variant == 2).
@export var arc_phi_half_rad: float = 1.15
@export var arc_r_inner_offset_m: float = 6.0
@export var arc_r_outer_offset_m: float = 16.0
## Variant 3 — flank strip density beside CamSun corridor.
@export var flank_x_offset_m: float = 6.5
@export var flank_weight: float = 1.35

@export_group("Tree backdrop (CamSun)")
## Horizontal distance from CamSun camera; production band on the lawn.
@export var backdrop_cam_dist_lo_m: float = 40.0
@export var backdrop_cam_dist_hi_m: float = 55.0
@export var backdrop_phi_half_rad: float = 0.50
@export var backdrop_tree_scale_mul: float = 1.38
@export var backdrop_min_sep_m: float = 2.4
@export var backdrop_min_g_dist_m: float = 14.0
@export var backdrop_min_hero_dist_m: float = 9.0
@export var backdrop_lawn_max_g_dist_m: float = 54.0

## Production cam reference (unset = square-scenario default via ForestCamRef).
@export var cam_orbit_pivot: Vector3 = Vector3(INF, INF, INF)
@export var cam_rig_scale: float = -1.0


static func _fresh() -> ForestParams:
	var scr: Script = load("res://src/playground/forest_params.gd")
	return scr.new() as ForestParams


static func production() -> ForestParams:
	return _fresh()


func duplicate_params() -> ForestParams:
	return duplicate(true) as ForestParams


func reset_to_production() -> void:
	var fresh := _fresh()
	var keep_seed := layout_seed
	var keep_variant := variant
	for prop in fresh.get_property_list():
		if prop.name == "resource_path" or prop.name.begins_with("_"):
			continue
		if prop.name in ["layout_seed", "variant"]:
			continue
		set(prop.name, fresh.get(prop.name))
	variant = 0
	layout_seed = keep_seed


func effective_tree_count(layout: VillageLayout) -> int:
	if tree_count >= 0:
		return tree_count
	return layout.pine_count


func to_dict() -> Dictionary:
	var d := {}
	for prop in get_property_list():
		if prop.name == "resource_path" or prop.name.begins_with("_"):
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE:
			d[prop.name] = get(prop.name)
	return d


func from_dict(d: Dictionary) -> void:
	for key in d.keys():
		if key == "schema" or key == "knobs":
			continue
		if key in to_dict():
			set(key, d[key])
	if d.has("knobs"):
		from_dict(d["knobs"])


func to_json_block() -> String:
	var payload := {
		"schema": SCHEMA,
		"variant": variant,
		"knobs": to_dict(),
	}
	payload["knobs"].erase("variant")
	return JSON.stringify(payload, "\t")


func matches_preset(other: ForestParams, eps: float = 1e-5) -> bool:
	var skip := ["layout_seed", "tree_count"]
	var a := to_dict()
	var b := other.to_dict()
	for key in a.keys():
		if key in skip:
			continue
		var va: Variant = a[key]
		var vb: Variant = b[key]
		if typeof(va) == TYPE_FLOAT:
			if absf(float(va) - float(vb)) > eps:
				return false
		elif va != vb:
			return false
	return true


static func ordered_preset_names() -> Array:
	var names: Array = presets().keys()
	names.sort()
	names.erase(PRESET_PRODUCTION)
	names.insert(0, PRESET_PRODUCTION)
	return names


static func detect_preset_name(p: ForestParams) -> String:
	for name in ordered_preset_names():
		var ref := _fresh()
		ref.variant = p.variant
		ref.apply_preset(name)
		if p.matches_preset(ref):
			return name
	return CUSTOM_PRESET


static func preset_tips() -> Dictionary:
	return {
		PRESET_PRODUCTION: "Tree backdrop on the lawn 40–55 m in front of CamSun (production).",
		"Deep wedge": "Variant 1: wedge reaches R+25 with bias toward the outer trees for a back-wall read.",
		"Arc ring behind hero": "Variant 2: wide arc band R+6..R+16 behind the hero.",
		"Wedge + CamSun gap flanks": "Variant 3: corridor stays clear; dense strips frame it left and right.",
		"Tree backdrop behind the village": "Same as production: lawn band in CamSun view.",
		"Old: behind the camera": "Legacy +Z wedge behind the camera (not in CamSun).",
	}


static func presets() -> Dictionary:
	return {
		PRESET_PRODUCTION: {"variant": 0},
		"Deep wedge": {
			"variant": 1,
			"wedge_r_outset_m": 25.0,
			"deep_outer_bias": 1.0,
			"wedge_weight": 1.5,
		},
		"Arc ring behind hero": {
			"variant": 2,
			"arc_phi_half_rad": 1.15,
			"arc_r_inner_offset_m": 6.0,
			"arc_r_outer_offset_m": 16.0,
			"wedge_sample_frac": 0.95,
		},
		"Wedge + CamSun gap flanks": {
			"variant": 3,
			"flank_x_offset_m": 6.5,
			"flank_weight": 1.35,
			"camsun_corridor_on": true,
		},
		"Tree backdrop behind the village": {"variant": 4},
		"Old: behind the camera": {
			"variant": 5,
			"camsun_corridor_on": true,
		},
	}


func apply_preset(name: String) -> void:
	var table := presets()
	assert(table.has(name), "Unknown preset: %s" % name)
	if name == PRESET_PRODUCTION:
		reset_to_production()
		return
	var keep_seed := layout_seed
	reset_to_production()
	layout_seed = keep_seed
	var overrides: Dictionary = table[name]
	for key in overrides.keys():
		set(key, overrides[key])
