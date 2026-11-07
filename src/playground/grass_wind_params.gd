class_name GrassWindParams
extends Resource

const SCHEMA := "grass_wind_playground.v1"
const PRESET_PRODUCTION := "Production"
## Shown (disabled, not pickable) in the preset dropdown when the knobs match no preset.
const CUSTOM_PRESET := "Custom"
const FaunaConstants = preload("res://src/presentation/fauna/fauna_constants.gd")

## Production-equivalent blade density (~1 / 0.17² m⁻²).
const DEFAULT_BLADE_DENSITY_PER_M2 := 1.0 / (0.17 * 0.17)

@export var variant: int = 0

@export_group("Group A")
@export var wind_strength: float = 1.0
@export var strength_cap: float = 1.0
@export var gust_envelope_on: bool = true
@export var gust_period_sec: float = 28.0
@export var direction_deg: float = 16.6992412467622
@export var direction_meander_rad: float = 0.35
@export var direction_drift_period_sec: float = 90.0
@export var freeze_direction: bool = false
@export var flutter_period_sec: float = 1.7
@export var time_scale: float = 1.0

@export_group("Group B")
@export var gust_tile_m: float = 24.0
@export var gust_scroll_speed_m_s: float = 1.8
@export var gust_edge_lo: float = 0.38
@export var gust_edge_hi: float = 0.78

@export_group("Group C")
@export var lean_base: float = 0.10
@export var lean_gust_gain: float = 0.45
@export var flutter_amp: float = 0.04
@export var flutter_gust_base: float = 0.4
@export var flutter_space_freq: float = 1.3
@export var height_exp: float = 2.0
@export var droop_on: bool = true

@export_group("Group D — variant 1")
@export var wave_length_m: float = 24.0
@export var wave_speed_m_s: float = 1.8
@export var wave_sharpness: float = 1.0

@export_group("Group D — variant 3")
@export var spring_freq_hz: float = 1.2
@export var spring_damping: float = 3.0
@export var overshoot_gain: float = 0.25
@export var phase_spread: float = 1.0

@export_group("Group D — variant 4")
@export var front_width_m: float = 2.0
@export var front_speed_m_s: float = 3.0
@export var front_spacing_m: float = 12.0
@export var front_peak: float = 1.0

@export_group("Stage")
@export var lawn_size_m: float = 16.0
@export var blade_density_per_m2: float = DEFAULT_BLADE_DENSITY_PER_M2


func duplicate_params() -> GrassWindParams:
	return duplicate(true) as GrassWindParams


func reset_to_production() -> void:
	var fresh := GrassWindParams.new()
	var v := variant
	var lawn := lawn_size_m
	var density := blade_density_per_m2
	for prop in fresh.get_property_list():
		if prop.name == "resource_path" or prop.name.begins_with("_"):
			continue
		if prop.name in ["variant", "lawn_size_m", "blade_density_per_m2"]:
			continue
		set(prop.name, fresh.get(prop.name))
	variant = 0
	lawn_size_m = lawn
	blade_density_per_m2 = density


func to_dict() -> Dictionary:
	return {
		"variant": variant,
		"wind_strength": wind_strength,
		"strength_cap": strength_cap,
		"gust_envelope_on": gust_envelope_on,
		"gust_period_sec": gust_period_sec,
		"direction_deg": direction_deg,
		"direction_meander_rad": direction_meander_rad,
		"direction_drift_period_sec": direction_drift_period_sec,
		"freeze_direction": freeze_direction,
		"flutter_period_sec": flutter_period_sec,
		"time_scale": time_scale,
		"gust_tile_m": gust_tile_m,
		"gust_scroll_speed_m_s": gust_scroll_speed_m_s,
		"gust_edge_lo": gust_edge_lo,
		"gust_edge_hi": gust_edge_hi,
		"lean_base": lean_base,
		"lean_gust_gain": lean_gust_gain,
		"flutter_amp": flutter_amp,
		"flutter_gust_base": flutter_gust_base,
		"flutter_space_freq": flutter_space_freq,
		"height_exp": height_exp,
		"droop_on": droop_on,
		"wave_length_m": wave_length_m,
		"wave_speed_m_s": wave_speed_m_s,
		"wave_sharpness": wave_sharpness,
		"spring_freq_hz": spring_freq_hz,
		"spring_damping": spring_damping,
		"overshoot_gain": overshoot_gain,
		"phase_spread": phase_spread,
		"front_width_m": front_width_m,
		"front_speed_m_s": front_speed_m_s,
		"front_spacing_m": front_spacing_m,
		"front_peak": front_peak,
		"lawn_size_m": lawn_size_m,
		"blade_density_per_m2": blade_density_per_m2,
	}


func from_dict(d: Dictionary) -> void:
	for key in d.keys():
		if key == "schema" or key == "knobs":
			continue
		if has_method("get") and d[key] != null:
			var name: String = key
			if name in to_dict():
				set(name, d[key])
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


static func ordered_preset_names() -> Array:
	var names: Array = presets().keys()
	names.sort()
	names.erase("Production")
	names.insert(0, "Production")
	return names


func matches_preset(other: GrassWindParams, eps: float = 1e-5) -> bool:
	var skip := ["lawn_size_m", "blade_density_per_m2"]
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


## Which named preset the current knobs equal, or CUSTOM_PRESET if none does.
static func detect_preset_name(p: GrassWindParams) -> String:
	for name in ordered_preset_names():
		var ref := GrassWindParams.new()
		ref.variant = p.variant  # presets that don't name a variant work on any variant
		ref.apply_preset(name)
		if p.matches_preset(ref):
			return name
	return CUSTOM_PRESET


## One-line description per preset (dropdown item tooltips).
static func preset_tips() -> Dictionary:
	return {
		PRESET_PRODUCTION: "Exactly what the village uses: variant 0 with every slider at its production value.",
		"Dead calm": "Almost no wind and no gusting. The grass barely stirs.",
		"Gentle breeze": "Half-strength wind with production's gust shape.",
		"Blustery": "Strong wind, a gust every 10 s, and gusts push the grass much harder.",
		"Wheat field": "Switches to variant 1 (travelling sine wave) with long, sharp swells.",
		"Rolling gust": "Switches to variant 4 (push wave): a narrow, fast band every 14 m.",
		"Springy meadow": "Switches to variant 3 (per-blade spring) with extra overshoot.",
	}


static func presets() -> Dictionary:
	return {
		"Production": {},
		"Dead calm": {"wind_strength": 0.15, "gust_envelope_on": false},
		"Gentle breeze": {"wind_strength": 0.5},
		"Blustery": {
			"wind_strength": 1.8,
			"gust_period_sec": 10.0,
			"lean_gust_gain": 0.9,
		},
		"Wheat field": {
			"variant": 1,
			"wave_length_m": 30.0,
			"wave_speed_m_s": 2.5,
			"wave_sharpness": 2.0,
		},
		"Rolling gust": {
			"variant": 4,
			"front_width_m": 1.5,
			"front_speed_m_s": 4.0,
			"front_spacing_m": 14.0,
		},
		"Springy meadow": {
			"variant": 3,
			"spring_freq_hz": 1.5,
			"overshoot_gain": 0.35,
			"phase_spread": 1.0,
		},
	}


func to_clock_cfg() -> Dictionary:
	return {
		"wind_cycle_sec": FaunaConstants.WIND_CYCLE_SEC,
		"gust_period_sec": gust_period_sec,
		"direction_drift_period_sec": direction_drift_period_sec,
		"flutter_period_sec": flutter_period_sec,
		"direction_base_angle_rad": deg_to_rad(direction_deg),
		"direction_meander_rad": direction_meander_rad,
		"freeze_direction": freeze_direction,
		"gust_scroll_speed_m_s": gust_scroll_speed_m_s,
		"gust_tile_m": gust_tile_m,
		"wind_strength": wind_strength,
		"strength_cap": strength_cap,
		"gust_envelope_on": gust_envelope_on,
		"time_scale": time_scale,
	}


## A preset is a full recipe, not a delta: every knob goes back to production first, then the
## preset's overrides are applied. So presets never stack on whatever was dialled in before.
## The current variant is kept unless the preset names one; "Production" also returns to
## variant 0. Lawn size / density are stage settings and are never touched.
func apply_preset(name: String) -> void:
	var table := presets()
	assert(table.has(name), "Unknown preset: %s" % name)
	if name == PRESET_PRODUCTION:
		reset_to_production()
		return
	var keep_variant := variant
	reset_to_production()
	variant = keep_variant
	var overrides: Dictionary = table[name]
	for key in overrides.keys():
		set(key, overrides[key])
