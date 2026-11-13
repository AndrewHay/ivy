class_name HillsParams
extends Resource

const SCHEMA := "hills_playground.v2"
const PRESET_PRODUCTION := "Production"
const CUSTOM_PRESET := "Custom"

@export var variant: int = 0
@export var layout_seed: int = 7

@export_group("Annulus")
@export var r_inner_m: float = 100.0
@export var r_outer_m: float = 310.0
@export var grid_cells: int = 128
@export var azimuth_segs: int = 128

@export_group("Seam")
@export var toe_width_m: float = 12.0
@export var toe_max_lift_m: float = 0.12

@export_group("Terrain noise")
@export var base_feature_m: float = 200.0
@export var noise_octaves: int = 3
@export var noise_persistence: float = 0.5
@export var warp_strength: float = 0.34
@export var height_scale_m: float = 42.0

@export_group("Ridge layers")
@export var layer_count: int = 4
@export var layer_dist_0: float = 155.0
@export var layer_dist_1: float = 190.0
@export var layer_dist_2: float = 225.0
@export var layer_dist_3: float = 260.0
@export var layer_width_0: float = 28.0
@export var layer_width_1: float = 32.0
@export var layer_width_2: float = 36.0
@export var layer_width_3: float = 40.0
@export var layer_amp_scale_0: float = 1.05
@export var layer_amp_scale_1: float = 1.15
@export var layer_amp_scale_2: float = 0.95
@export var layer_amp_scale_3: float = 0.75

# Legacy aliases (playground JSON / old presets)
@export var layer_amp_0: float = 1.05
@export var layer_amp_1: float = 1.15
@export var layer_amp_2: float = 0.95
@export var layer_wave_0: float = 118.0
@export var layer_wave_1: float = 95.0
@export var layer_wave_2: float = 75.0
@export var layer_amplitude_m: PackedFloat32Array = PackedFloat32Array([8.0, 12.0, 13.0])
@export var layer_wavelength_m: PackedFloat32Array = PackedFloat32Array([118.0, 95.0, 75.0])
@export var near_ridge_peak_m: float = 28.0
@export var far_ridge_peak_m: float = 36.0
@export var radial_bias_power: float = 1.2

@export_group("Forest")
@export var tree_count: int = 360
@export var forest_r_min_m: float = 110.0
@export var forest_r_max_m: float = 260.0
@export var min_sep_m: float = 3.0
@export var slope_max_deg: float = 42.0
@export var slope_prefer_deg: float = 14.0
@export var hemisphere_boost_phi: float = 0.55
@export var hemisphere_boost: float = 1.30
@export var hemisphere_lo: float = 1.0
@export var backdrop_exclusion_m: float = 2.0
@export var lcg_seed: int = -1
@export var scale_min: float = 1.6
@export var scale_max: float = 2.6
@export var copse_scale_m: float = 26.0
@export var copse_threshold: float = 0.40
@export var lone_tree_rate: float = 0.07
@export var forest_green_darken: float = 0.30

@export_group("Tint")
@export var ridge_fog_tint_on: bool = true
@export var ridge_near_albedo_mul: float = 1.02
@export var ridge_far_albedo_mul: float = 0.80
@export var ridge_near_green_bias: float = 0.18
@export var ridge_far_tint_blue: float = 0.05
@export var sun_warmth: float = 0.22

@export_group("Azimuth wedge")
## Compass bearing of the hill wedge centre: 0 = north (−Z), 90 = east (+X).
@export var azimuth_centre_deg: float = 0.0
## Half-width of the hill wedge in degrees. 180 = full circle (no constraint).
@export var azimuth_half_width_deg: float = 55.0
## Angular width of the smooth falloff taper at each wedge edge.
@export var azimuth_fade_width_deg: float = 20.0

@export_group("Fog preview")
## Production: override the layout fog_begin for hill rendering (start haze at 80 m).
@export var fog_begin_m: float = 80.0
## Production: override the layout fog_end for hill rendering (full haze at 280 m).
@export var fog_end_m: float = 280.0


static func _fresh() -> HillsParams:
	var scr: Script = load("res://src/playground/hills_params.gd")
	return scr.new() as HillsParams


static func production() -> HillsParams:
	return _fresh()


func layer_dist_at(i: int) -> float:
	match i:
		0:
			return layer_dist_0
		1:
			return layer_dist_1
		2:
			return layer_dist_2
		3:
			return layer_dist_3
	return 120.0


func layer_width_at(i: int) -> float:
	match i:
		0:
			return layer_width_0
		1:
			return layer_width_1
		2:
			return layer_width_2
		3:
			return layer_width_3
	return 18.0


func layer_amp_scale_at(i: int) -> float:
	match i:
		0:
			return layer_amp_scale_0
		1:
			return layer_amp_scale_1
		2:
			return layer_amp_scale_2
		3:
			return layer_amp_scale_3
	return 0.85


# amplitude_at / wavelength_at were dead (never called outside this file); removed in rework7.


func duplicate_params() -> HillsParams:
	return duplicate(true) as HillsParams


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


func effective_fog_begin(layout: VillageLayout) -> float:
	if fog_begin_m > 0.0:
		return fog_begin_m
	return layout.fog_begin


func effective_fog_end(layout: VillageLayout) -> float:
	if fog_end_m > 0.0:
		return fog_end_m
	return layout.fog_end


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


func matches_preset(other: HillsParams, eps: float = 1e-5) -> bool:
	var skip := ["layout_seed"]
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


static func detect_preset_name(p: HillsParams) -> String:
	for name in ordered_preset_names():
		var ref := _fresh()
		ref.variant = p.variant
		ref.apply_preset(name)
		if p.matches_preset(ref):
			return name
	return CUSTOM_PRESET


static func preset_tips() -> Dictionary:
	return {
		PRESET_PRODUCTION: "Rolling hills: fBm terrain + copse forest + production tints.",
		"Flat legacy": "Pre-ivy-ska0 flat annulus ramp.",
		"High ridges": "Taller/steeper rolling preset for playground experiments.",
	}


static func ordered_preset_names() -> Array:
	var names: Array = presets().keys()
	names.sort()
	names.erase(PRESET_PRODUCTION)
	names.insert(0, PRESET_PRODUCTION)
	return names


static func presets() -> Dictionary:
	return {
		PRESET_PRODUCTION: {"variant": 0},
		"Flat legacy": {"variant": 1},
		"High ridges": {
			"variant": 2,
			"height_scale_m": 48.0,
			"layer_amp_scale_0": 1.2,
			"layer_amp_scale_1": 1.25,
			"layer_amp_scale_2": 1.1,
			"layer_amp_scale_3": 0.9,
			"copse_threshold": 0.36,
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
	# Note: height_scale_m for variant==2 is already set via overrides above; no duplicate needed.
