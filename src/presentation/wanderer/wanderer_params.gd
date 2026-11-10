class_name WandererParams
extends Resource

const SCHEMA := "wanderer.v1"
const PRESET_PRODUCTION := "Production"
const CUSTOM_PRESET := "Custom"

@export_group("Figure")
@export var figure_height_m: float = 2.0
@export var walk_speed_mps: float = 2.0
@export var speed_ease_m: float = 0.3
@export var turn_rate_deg_s: float = 270.0
@export var stride_length_m: float = 1.8
@export var leg_swing_deg: float = 24.0
@export var arm_swing_deg: float = 18.0
@export var torso_roll_deg: float = 2.5
@export var torso_lean_deg: float = 4.0
@export var bob_m: float = 0.04
@export var idle_blend_s: float = 0.2
@export var walk_variant: int = 0

@export_group("Timing")
@export var door_pause_s: float = 1.0
@export var inside_s: float = 10.0
@export var exit_pause_s: float = 1.0
@export var present_standoff_m: float = 2.5
@export var leg_turn_gate_deg: float = 90.0
@export var image_s: float = 5.0
@export var image_fade_s: float = 0.3
@export var quote_interval_s: float = 20.0
@export var quote_min_walk_s: float = 3.0

@export_group("Bubble")
@export var bubble_base_s: float = 2.0
@export var bubble_s_per_char: float = 0.06
@export var bubble_min_s: float = 3.0
@export var bubble_max_s: float = 6.0
@export var bubble_fade_in_s: float = 0.2
@export var bubble_fade_out_s: float = 0.4
@export var bubble_gap_m: float = 0.4
@export var bubble_font_size: int = 48
@export var bubble_pixel_size: float = 0.0065
@export var bubble_wrap_px: int = 400
@export var bubble_max_chars: int = 140

@export_group("Image")
@export var structure_height_m: float = 3.5
@export var image_height_factor: float = 2.0
@export var image_max_width_m: float = 16.0
@export var image_corner_lift_m: float = 0.05
@export var image_max_px: int = 1024
@export var image_depth_test: bool = true
@export var hero_xz: Vector2 = Vector2.ZERO

@export_group("Routing")
@export var snap_m: float = 0.35
@export var door_snap_m: float = 1.0
@export var door_stoop_m: float = 0.5
@export var door_stand_off_m: float = 0.3
@export var bridge_max_m: float = 12.0
@export var bridge_min_ring_m: float = 5.0
@export var bridge_max_delta_r_m: float = 0.75
@export var hero_keepout_m: float = 4.5
@export var cottage_bridge_grow_m: float = 0.2
@export var pond_path_clearance_m: float = 1.5

@export_group("Content")
@export var content_dir: String = "res://wanderer_content/"
@export var quotes_file: String = "quotes.txt"
@export var max_images: int = 64

@export_group("Misc")
@export var enabled: bool = true
@export var rng_seed: int = 0
## When true, wanderer freezes while sim speed is paused. Default false: runs on wall clock at game start.
@export var pause_with_sim: bool = false


var variant: int:
	get:
		return walk_variant
	set(v):
		walk_variant = v


static func _fresh() -> WandererParams:
	var scr: Script = load("res://src/presentation/wanderer/wanderer_params.gd")
	return scr.new() as WandererParams


static func production() -> WandererParams:
	return _fresh()


func duplicate_params() -> WandererParams:
	return duplicate(true) as WandererParams


func reset_to_production() -> void:
	var fresh := _fresh()
	var keep_seed := rng_seed
	for prop in fresh.get_property_list():
		if prop.name == "resource_path" or prop.name.begins_with("_"):
			continue
		if prop.name == "rng_seed":
			continue
		set(prop.name, fresh.get(prop.name))
	rng_seed = keep_seed


func present_standoff() -> float:
	return maxf(present_standoff_m, 1.0)


func bubble_duration(text: String) -> float:
	var n := text.length()
	return clampf(bubble_base_s + bubble_s_per_char * float(n), bubble_min_s, bubble_max_s)


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
		"variant": walk_variant,
		"knobs": to_dict(),
	}
	payload["knobs"].erase("walk_variant")
	return JSON.stringify(payload, "\t")


func matches_preset(other: WandererParams, eps: float = 1e-5) -> bool:
	var skip := ["rng_seed"]
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


static func detect_preset_name(p: WandererParams) -> String:
	for name in ordered_preset_names():
		var ref := _fresh()
		ref.walk_variant = p.walk_variant
		ref.apply_preset(name)
		if p.matches_preset(ref):
			return name
	return CUSTOM_PRESET


static func preset_tips() -> Dictionary:
	return {
		PRESET_PRODUCTION: "Default village stroll: 1 m/s sine walk, production timings.",
		"Strolling": "Slower gait with eased pendulum (variant 1).",
		"Brisk": "Faster march variant.",
		"Marching": "Stiff march: arms high, no bob (variant 3).",
		"Waddle": "Roll-dominant waddle (variant 2).",
	}


static func presets() -> Dictionary:
	return {
		PRESET_PRODUCTION: {"walk_variant": 0},
		"Strolling": {
			"walk_variant": 1,
			"walk_speed_mps": 0.75,
		},
		"Brisk": {
			"walk_variant": 0,
			"walk_speed_mps": 1.35,
		},
		"Marching": {
			"walk_variant": 3,
			"walk_speed_mps": 1.0,
		},
		"Waddle": {
			"walk_variant": 2,
			"walk_speed_mps": 0.9,
		},
	}


func apply_preset(name: String) -> void:
	var table := presets()
	assert(table.has(name), "Unknown preset: %s" % name)
	if name == PRESET_PRODUCTION:
		reset_to_production()
		return
	var keep_seed := rng_seed
	reset_to_production()
	rng_seed = keep_seed
	var overrides: Dictionary = table[name]
	for key in overrides.keys():
		set(key, overrides[key])
