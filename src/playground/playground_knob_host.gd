class_name PlaygroundKnobHost
extends RefCounted

var variant_labels: Array
var variant_descriptions: Array
var variant_help: String
var preset_help: String
var _params_script: Script
var _knob_spec_script: Script


static func _fresh() -> PlaygroundKnobHost:
	var scr: Script = load("res://src/playground/playground_knob_host.gd")
	return scr.new() as PlaygroundKnobHost


static func grass_wind() -> PlaygroundKnobHost:
	var h := _fresh()
	var spec := load("res://src/playground/grass_wind_knob_spec.gd")
	h._knob_spec_script = spec
	h._params_script = load("res://src/playground/grass_wind_params.gd")
	h.variant_labels = spec.VARIANT_LABELS
	h.variant_descriptions = spec.VARIANT_DESCRIPTIONS
	h.variant_help = spec.VARIANT_HELP
	h.preset_help = spec.PRESET_HELP
	return h


static func forest() -> PlaygroundKnobHost:
	var h := _fresh()
	var spec := load("res://src/playground/forest_knob_spec.gd")
	h._knob_spec_script = spec
	h._params_script = load("res://src/playground/forest_params.gd")
	h.variant_labels = spec.VARIANT_LABELS
	h.variant_descriptions = spec.VARIANT_DESCRIPTIONS
	h.variant_help = spec.VARIANT_HELP
	h.preset_help = spec.PRESET_HELP
	return h


static func hills() -> PlaygroundKnobHost:
	var h := _fresh()
	var spec := load("res://src/playground/hills_knob_spec.gd")
	h._knob_spec_script = spec
	h._params_script = load("res://src/playground/hills_params.gd")
	h.variant_labels = spec.VARIANT_LABELS
	h.variant_descriptions = spec.VARIANT_DESCRIPTIONS
	h.variant_help = spec.VARIANT_HELP
	h.preset_help = "Preset applies a full hills recipe."
	return h


static func village_terrain() -> PlaygroundKnobHost:
	var h := _fresh()
	var spec := load("res://src/playground/village_terrain_knob_spec.gd")
	h._knob_spec_script = spec
	h._params_script = load("res://src/playground/village_terrain_params.gd")
	h.variant_labels = spec.VARIANT_LABELS
	h.variant_descriptions = spec.VARIANT_DESCRIPTIONS
	h.variant_help = spec.VARIANT_HELP
	h.preset_help = spec.PRESET_HELP
	return h


static func wanderer() -> PlaygroundKnobHost:
	var h := _fresh()
	var spec := load("res://src/playground/wanderer_knob_spec.gd")
	h._knob_spec_script = spec
	h._params_script = load("res://src/presentation/wanderer/wanderer_params.gd")
	h.variant_labels = spec.VARIANT_LABELS
	h.variant_descriptions = spec.VARIANT_DESCRIPTIONS
	h.variant_help = spec.VARIANT_HELP
	h.preset_help = spec.PRESET_HELP
	return h


func fresh_defaults() -> Resource:
	return _params_script.new()


func detect_preset_name(params: Resource) -> String:
	return _params_script.detect_preset_name(params)


func preset_tips() -> Dictionary:
	return _params_script.preset_tips()


func ordered_preset_names() -> Array:
	return _params_script.ordered_preset_names()


func custom_preset_label() -> String:
	return _params_script.CUSTOM_PRESET
