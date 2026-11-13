extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsKnobSpec = preload("res://src/playground/hills_knob_spec.gd")


func test_production_defaults_schema() -> void:
	var p := HillsParams.production()
	assert_eq(p.variant, 0)
	assert_almost_eq(p.r_inner_m, 100.0, 1e-5)   # rework5: 2× original r_inner (was 60)
	assert_eq(p.tree_count, 360)
	assert_almost_eq(p.base_feature_m, 200.0, 1e-5)
	assert_almost_eq(p.height_scale_m, 42.0, 1e-5)  # rework5: rolling hills (was 80)
	assert_almost_eq(p.scale_min, 1.6, 1e-5)
	assert_true(p.ridge_fog_tint_on)


func test_dict_round_trip() -> void:
	var p := HillsParams.production()
	p.r_inner_m = 100.0
	p.tree_count = 200
	var d := p.to_dict()
	var q := HillsParams.production()
	q.from_dict(d)
	assert_true(p.matches_preset(q))


func test_flat_legacy_preset() -> void:
	var p := HillsParams.production()
	p.apply_preset("Flat legacy")
	assert_eq(p.variant, 1)


## MAJOR-1 regression: every HillsParams.production() float/int field that has
## a knob row must lie within [knob.min, knob.max] so Reset-to-production and
## preset round trips don't silently clamp.
func test_production_defaults_within_knob_ranges() -> void:
	var p := HillsParams.production()
	var knobs := HillsKnobSpec.all_knobs()
	var prop_names: PackedStringArray = PackedStringArray()
	for prop in p.get_property_list():
		prop_names.append(prop.name)
	var failures: PackedStringArray = PackedStringArray()
	for knob in knobs:
		if knob.get("type", "") == "bool":
			continue
		var name: String = knob["name"]
		if name in ["layout_seed", "variant"]:
			continue
		if not (name in prop_names):
			continue
		var val: float = float(p.get(name))
		var min_v: float = float(knob["min"])
		var max_v: float = float(knob["max"])
		var step: float = float(knob["step"])
		if val < min_v or val > max_v:
			failures.append("%s production=%.3f not in [%.3f, %.3f]" % [name, val, min_v, max_v])
		# Verify it snaps to step: (val - min_v) must be a near-integer multiple of step.
		if step > 1e-6:
			var offset := val - min_v
			var n_steps := roundf(offset / step)
			var snapped := min_v + n_steps * step
			if absf(snapped - val) > 1e-4:
				failures.append("%s production=%.4f does not snap cleanly to step=%.4f from min=%.4f" \
					% [name, val, step, min_v])
	assert_eq(failures.size(), 0, "Production knob range violations:\n" + "\n".join(failures))
