class_name GrassWindKnobSpec
extends RefCounted

const VARIANT_LABELS := [
	"0 — Current (production)",
	"1 — Travelling sine wave",
	"2 — Noise-gust lean only",
	"3 — Per-blade spring",
	"4 — Push wave",
]

## One plain-language description per variant (shown under the Variant dropdown and as the
## item tooltips). A variant is a different *algorithm* — different maths in the vertex shader.
const VARIANT_DESCRIPTIONS := [
	"What the village uses today. Each blade leans downwind by an amount that grows inside a patchy, drifting gust field (scrolling noise), plus a small fast shimmer at the tips.",
	"Replaces the patchy noise with a regular sine wave travelling along the wind direction: long rolling swells like a wheat field. Gust-noise knobs (Group B) do not apply.",
	"Production's patchy gust lean with the tip shimmer removed: calmer and heavier, whole patches heave together.",
	"Same lean target as production plus a per-blade springy ring that overshoots and settles every flutter period: an out-of-sync bouncy shiver.",
	"A narrow gust band rolls across the lawn at a steady speed so you can watch a gust physically travel through the grass, repeating every 'front spacing' metres.",
]

const VARIANT_HELP := "Variant = WHICH ALGORITHM moves the grass (different shader maths). Switching it keeps your slider values; sliders that the chosen algorithm does not use are hidden."
const PRESET_HELP := "Preset = a saved BUNDLE OF SLIDER VALUES. Picking one resets every slider to production, then applies the preset (a few presets also pick a variant). Touching any slider afterwards shows 'Custom'."


static func all_knobs() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	# ── Group A: wind envelope, direction, time ──────────────────────────────
	_add_float(rows, "wind_strength", "Wind strength", "A", 0.0, 3.0, 0.05, [0, 1, 2, 3, 4],
		"Overall wind strength. Scales how far every blade leans and shimmers; 0 = perfectly still grass. The Strength cap clamps the final value, so values above the cap make gusts flat-top at the cap instead of rising further.")
	_add_float(rows, "strength_cap", "Strength cap", "A", 0.0, 3.0, 0.05, [0, 1, 2, 3, 4],
		"Hard ceiling on the final wind strength after the gust envelope is applied. Production is 1.0; raise it above 1 to let strong wind exceed production's maximum.")
	_add_bool(rows, "gust_envelope_on", "Gust envelope", "A", [0, 1, 2, 3, 4],
		"On: wind strength swells and dies back smoothly over each Gust period, like real wind. Off: constant wind at the Wind strength value.")
	_add_float(rows, "gust_period_sec", "Gust period (s)", "A", 2.0, 60.0, 0.5, [0, 1, 2, 3, 4],
		"Seconds for the wind to swell up and die back once. Short = restless, gusty; long = slow tides of wind. Needs Gust envelope on.")
	_add_float(rows, "direction_deg", "Direction (°)", "A", 0.0, 360.0, 1.0, [0, 1, 2, 3, 4],
		"Heading the wind blows toward, in degrees on the ground (0° = +X, 90° = +Z). Production is about 17°.")
	_add_float(rows, "direction_meander_rad", "Direction meander", "A", 0.0, 1.5, 0.01, [0, 1, 2, 3, 4],
		"How far (radians, either side) the wind direction slowly swings around the heading. 0 = the direction never changes; 0.35 is about ±20°.")
	_add_float(rows, "direction_drift_period_sec", "Drift period (s)", "A", 5.0, 180.0, 1.0, [0, 1, 2, 3, 4],
		"Seconds for the direction to swing all the way out and back. Longer = lazier changes of direction.")
	_add_bool(rows, "freeze_direction", "Freeze direction", "A", [0, 1, 2, 3, 4],
		"Lock the wind to exactly the heading above and ignore the meander. Handy for judging one change with nothing else moving.")
	_add_float(rows, "flutter_period_sec", "Flutter period (s)", "A", 0.2, 6.0, 0.05, [0, 1, 2, 3, 4],
		"Seconds per cycle of the fast tip shimmer (variants 0, 1, 3, 4). In variant 3 it also sets how long each spring ring takes to die out. Short = jittery; long = lazy.")
	_add_float(rows, "time_scale", "Time scale", "A", 0.0, 2.0, 0.05, [0, 1, 2, 3, 4],
		"Playback speed of the whole wind simulation. 1 = real time, 0 = frozen (blades hold their pose), 0.1–0.5 = slow motion for studying movement.")
	# ── Group B: gust noise (variants 0, 2) ─────────────────────────────────
	_add_float(rows, "gust_tile_m", "Gust tile (m)", "B", 2.0, 64.0, 0.5, [0, 2],
		"Size in metres of one repeat of the gust noise. Small = many small gust patches; large = a few big wide ones.")
	_add_float(rows, "gust_scroll_speed_m_s", "Gust scroll (m/s)", "B", 0.0, 10.0, 0.1, [0, 2],
		"How fast the gust patches travel downwind. 0 = patches stay put and only pulse in strength.")
	_add_float(rows, "gust_edge_lo", "Gust edge lo", "B", 0.0, 1.0, 0.01, [0, 2],
		"Noise level where a gust starts to register; below it there is no gust. Raising it makes gusts rarer. Keep it below Gust edge hi.")
	_add_float(rows, "gust_edge_hi", "Gust edge hi", "B", 0.0, 1.0, 0.01, [0, 2],
		"Noise level where a gust reaches full strength. The gap between lo and hi sets how soft or hard the edges of a gust patch are (small gap = hard edge).")
	# ── Group C: blade maths ─────────────────────────────────────────────────
	_add_float(rows, "lean_base", "Lean base", "C", 0.0, 1.0, 0.01, [0, 1, 2, 3, 4],
		"Constant downwind lean everywhere, as a fraction of blade height at the tip, before gusts add more. 0 = grass only moves inside gusts.")
	_add_float(rows, "lean_gust_gain", "Lean gust gain", "C", 0.0, 2.0, 0.01, [0, 1, 2, 3, 4],
		"Extra lean added inside a gust, on top of Lean base. Higher = bigger contrast between calm and gusted grass. In variants 1 and 4 the 'gust' is the wave / band instead of noise.")
	_add_float(rows, "flutter_amp", "Flutter amp", "C", 0.0, 0.30, 0.005, [0, 1, 3, 4],
		"Size of the fast shimmer at blade tips, as a fraction of blade height. 0 = no shimmer. (Variant 2 has no shimmer by design.)")
	_add_float(rows, "flutter_gust_base", "Flutter gust base", "C", 0.0, 2.0, 0.05, [0, 1, 3, 4],
		"How much shimmer survives in calm areas; shimmer size scales with (this + gust). 0 = shimmer only inside gusts.")
	_add_float(rows, "flutter_space_freq", "Flutter space freq", "C", 0.0, 6.0, 0.1, [0, 1, 3, 4],
		"How much the shimmer's timing differs between neighbouring blades across the ground. 0 = everyone shimmers in sync; high = busy, noisy sparkle.")
	_add_float(rows, "height_exp", "Height exponent", "C", 1.0, 4.0, 0.1, [0, 1, 2, 3, 4],
		"How the bend is spread up the blade. 1 = bends evenly along the whole blade; 2 (production) = base stays planted and the tip does most of the moving; 4 = only the very tip moves.")
	_add_bool(rows, "droop_on", "Droop on", "C", [0, 1, 2, 3, 4],
		"On: a strongly leaning blade also dips down a little (its length is roughly conserved), so strong wind looks like bending rather than sliding sideways.")
	# ── Group D: per-variant knobs ───────────────────────────────────────────
	_add_float(rows, "wave_length_m", "Wave length (m)", "D", 2.0, 64.0, 0.5, [1],
		"Distance between wave crests. Short = tight ripples; long = broad swells.")
	_add_float(rows, "wave_speed_m_s", "Wave speed (m/s)", "D", 0.0, 10.0, 0.1, [1],
		"How fast the crests travel downwind. 0 = frozen ripples.")
	_add_float(rows, "wave_sharpness", "Wave sharpness", "D", 0.3, 6.0, 0.1, [1],
		"Shapes the waves. 1 = smooth sine; higher = narrow sharp crests with flat calm in between.")
	_add_float(rows, "spring_freq_hz", "Spring freq (Hz)", "D", 0.2, 5.0, 0.05, [3],
		"How fast each blade rings, in bounces per second.")
	_add_float(rows, "spring_damping", "Spring damping", "D", 0.0, 12.0, 0.1, [3],
		"How quickly the bounce fades within each flutter period. 0 = barely fades; high = one quick wobble then still.")
	_add_float(rows, "overshoot_gain", "Overshoot gain", "D", 0.0, 1.0, 0.01, [3],
		"Size of the bounce as a fraction of the lean. 0 = no spring (looks like variant 2); 1 = bounce as big as the lean itself.")
	_add_float(rows, "phase_spread", "Phase spread", "D", 0.0, 1.0, 0.05, [3],
		"How out-of-sync blades are with each other. 0 = the whole lawn bounces in unison; 1 = every blade on its own random phase.")
	_add_float(rows, "front_width_m", "Front width (m)", "D", 0.3, 12.0, 0.1, [4],
		"Thickness of the gust band. Narrow = a thin crisp line; wide = a broad push.")
	_add_float(rows, "front_speed_m_s", "Front speed (m/s)", "D", 0.2, 15.0, 0.1, [4],
		"How fast the band travels downwind.")
	_add_float(rows, "front_spacing_m", "Front spacing (m)", "D", 2.0, 64.0, 0.5, [4],
		"Distance between successive bands. If larger than the lawn you only ever see one band at a time.")
	_add_float(rows, "front_peak", "Front peak", "D", 0.0, 2.0, 0.05, [4],
		"How hard blades react at the centre of the band (1 = a full gust; above 1 exaggerates). Between bands the lean falls back to Lean base.")
	# ── Stage ────────────────────────────────────────────────────────────────
	_add_float(rows, "lawn_size_m", "Lawn size (m)", "Stage", 4.0, 40.0, 0.5, [0, 1, 2, 3, 4],
		"Side length of the square test lawn. Rebuilds the grass (brief pause) and affects performance.")
	_add_float(rows, "blade_density_per_m2", "Blade density (/m²)", "Stage", 20.0, 400.0, 1.0, [0, 1, 2, 3, 4],
		"Blades per square metre. Production is about 35. Rebuilds the grass (brief pause) and affects performance.")
	return rows


static func _add_float(
		rows: Array[Dictionary],
		name: String,
		label: String,
		group: String,
		min_v: float,
		max_v: float,
		step: float,
		variants: Array,
		tip: String = "") -> void:
	rows.append({
		"name": name,
		"label": label,
		"group": group,
		"type": "float",
		"min": min_v,
		"max": max_v,
		"step": step,
		"variants": variants,
		"tip": tip,
	})


static func _add_bool(
		rows: Array[Dictionary],
		name: String,
		label: String,
		group: String,
		variants: Array,
		tip: String = "") -> void:
	rows.append({
		"name": name,
		"label": label,
		"group": group,
		"type": "bool",
		"variants": variants,
		"tip": tip,
	})
