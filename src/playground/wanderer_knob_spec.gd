class_name WandererKnobSpec
extends RefCounted

const VARIANT_LABELS := [
	"Current (production)",
	"Eased",
	"Waddle",
	"March",
]

const VARIANT_DESCRIPTIONS := [
	"Sine walk — production village stroll.",
	"Triangle-eased stride (variant 1).",
	"Roll-heavy waddle with extra bob (variant 2).",
	"Stiff march: high arms, no bob (variant 3).",
]

const VARIANT_HELP := "Walk algorithm variant; pose() only."
const PRESET_HELP := "Preset applies a full gait recipe on top of production defaults."


static func all_knobs() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var all := [0, 1, 2, 3]
	_add_float(rows, "walk_speed_mps", "Walk speed (m/s)", "Gait", 0.0, 3.0, 0.05, all,
		"Treadmill & circuit locomotion speed.")
	_add_float(rows, "stride_length_m", "Stride length (m)", "Gait", 0.8, 2.5, 0.05, all)
	_add_float(rows, "leg_swing_deg", "Leg swing (°)", "Gait", 0.0, 45.0, 0.5, all)
	_add_float(rows, "arm_swing_deg", "Arm swing (°)", "Gait", 0.0, 45.0, 0.5, all)
	_add_float(rows, "bob_m", "Bob (m)", "Gait", 0.0, 0.12, 0.005, all)
	_add_float(rows, "torso_roll_deg", "Sway roll (°)", "Body", 0.0, 12.0, 0.25, all)
	_add_float(rows, "torso_lean_deg", "Sway lean (°)", "Body", 0.0, 12.0, 0.25, all)
	_add_float(rows, "turn_rate_deg_s", "Turn rate (°/s)", "Turn", 30.0, 540.0, 5.0, all,
		"Yaw smoothing toward path tangent.")
	_add_float(rows, "speed_ease_m", "Speed ease (m)", "Turn", 0.0, 1.5, 0.05, all,
		"Blend walk speed near route ends.")
	_add_float(rows, "idle_blend_s", "Idle blend (s)", "Turn", 0.05, 1.0, 0.01, all)
	_add_float(rows, "door_pause_s", "Door pause (s)", "Timing", 0.0, 4.0, 0.1, all)
	_add_float(rows, "inside_s", "Inside (s)", "Timing", 0.5, 30.0, 0.5, all)
	_add_float(rows, "exit_pause_s", "Exit pause (s)", "Timing", 0.0, 4.0, 0.1, all)
	_add_float(rows, "present_standoff_m", "Present standoff (m)", "Timing", 0.5, 6.0, 0.1, all)
	_add_float(rows, "image_s", "Image hold (s)", "Timing", 1.0, 15.0, 0.25, all)
	_add_float(rows, "image_fade_s", "Image fade (s)", "Timing", 0.05, 2.0, 0.05, all)
	_add_float(rows, "quote_interval_s", "Quote interval (s)", "Timing", 5.0, 60.0, 1.0, all)
	_add_float(rows, "quote_min_walk_s", "Quote min walk (s)", "Timing", 0.0, 10.0, 0.25, all)
	_add_float(rows, "bubble_base_s", "Bubble base (s)", "Bubble", 0.5, 5.0, 0.1, all)
	_add_float(rows, "bubble_s_per_char", "Bubble s/char", "Bubble", 0.0, 0.2, 0.005, all)
	_add_float(rows, "bubble_min_s", "Bubble min (s)", "Bubble", 1.0, 10.0, 0.1, all)
	_add_float(rows, "bubble_max_s", "Bubble max (s)", "Bubble", 2.0, 15.0, 0.25, all)
	_add_float(rows, "bubble_fade_in_s", "Bubble fade in (s)", "Bubble", 0.05, 1.0, 0.05, all)
	_add_float(rows, "bubble_fade_out_s", "Bubble fade out (s)", "Bubble", 0.05, 1.5, 0.05, all)
	_add_float(rows, "bubble_gap_m", "Bubble gap (m)", "Bubble", 0.1, 1.0, 0.02, all)
	_add_int(rows, "bubble_font_size", "Bubble font (px)", "Bubble", 24, 96, 2, all)
	_add_float(rows, "bubble_pixel_size", "Bubble pixel size", "Bubble", 0.003, 0.02, 0.0002, all)
	_add_int(rows, "bubble_wrap_px", "Bubble wrap (px)", "Bubble", 200, 800, 10, all)
	_add_int(rows, "bubble_max_chars", "Bubble max chars", "Bubble", 40, 280, 5, all)
	_add_float(rows, "image_height_factor", "Image height ×", "Image", 1.0, 3.0, 0.05, all)
	_add_float(rows, "image_max_width_m", "Image max width (m)", "Image", 4.0, 24.0, 0.5, all)
	_add_float(rows, "image_corner_lift_m", "Image corner lift (m)", "Image", 0.0, 0.25, 0.01, all)
	_add_int(rows, "image_max_px", "Image max px", "Image", 512, 4096, 64, all)
	_add_bool(rows, "image_depth_test", "Image depth test", "Image", all)
	return rows


static func _add_float(
		rows: Array[Dictionary], name: String, label: String, group: String,
		min_v: float, max_v: float, step: float, variants: Array, tip: String = "") -> void:
	rows.append({
		"name": name, "label": label, "group": group, "type": "float",
		"min": min_v, "max": max_v, "step": step, "variants": variants, "tip": tip,
	})


static func _add_int(
		rows: Array[Dictionary], name: String, label: String, group: String,
		min_v: int, max_v: int, step: int, variants: Array, tip: String = "") -> void:
	rows.append({
		"name": name, "label": label, "group": group, "type": "float",
		"min": float(min_v), "max": float(max_v), "step": float(step),
		"variants": variants, "tip": tip, "is_int": true,
	})


static func _add_bool(
		rows: Array[Dictionary], name: String, label: String, group: String,
		variants: Array, tip: String = "") -> void:
	rows.append({
		"name": name, "label": label, "group": group, "type": "bool",
		"variants": variants, "tip": tip,
	})
