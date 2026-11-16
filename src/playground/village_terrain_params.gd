## VillageTerrainParams — resource schema for the in-village lawn heightfield.
## Mirrors HillsParams / ForestParams API (SD-VILLAGE-TERRAIN-2 / AR-VT-FILES).
## Production playground and VillageBackdrop both call the same static builders
## with this resource — no demo fork (SD-VILLAGE-TERRAIN-2 §production-parity).
class_name VillageTerrainParams
extends Resource

const SCHEMA := "village_terrain_playground.v1"
const PRESET_PRODUCTION := "Production"
const CUSTOM_PRESET := "Custom"
const PRESET_NO_HILL := "No hill (A/B)"

# ── Stage ──────────────────────────────────────────────────────────────────────
## 0 = rolling (production), 1 = flat legacy (sample_y ≡ 0, INV-15), 2 = high relief (A/B only).
@export var variant: int = 0
## VillageLayout.generate(seed); drives terrain + knoll LCG. Used when layout.generation_seed == 0.
@export var layout_seed: int = 7

# ── Base noise (SD-VILLAGE-TERRAIN-2 §Base) ────────────────────────────────────
## Peak magnitude of zero-mean base noise h ∈ ≈[−a,+a]. 0.0 ⇒ flat base.
## ivy-82zn.14.1: 0.64 → 0.56 (knolls now carry the tall relief; keeps open-lawn slope ≤ 8°).
## ivy-82zn.14.10 / ivy-sx7x: 0.56 → 0.30. The path-quiet multiplier was inverted (the open lawn
## got the 0.52 quiet floor, paths full amplitude); fixed, so the open lawn keeps the same
## ~0.29 m effective amplitude it had and only the 5 m path corridors are quieter now.
@export var base_amplitude_m: float = 0.30
## Primary wavelength of fbm_height_01.
@export var base_feature_m: float = 48.0
## fBm octaves.
@export var noise_octaves: int = 2
## fBm persistence.
@export var noise_persistence: float = 0.40
## Domain warp strength (breaks grid feel).
@export var warp_strength: float = 0.16
## >1 lifts relief toward G (knoll-y green), <1 dishes toward G.
@export var center_bias_gain: float = 1.10
## Optional azimuthal lift (independent of outer-hill north retune).
@export var dir_bias_gain: float = 0.0
## Azimuth of directional lift (compass: 0=north, 90=east).
@export var dir_bias_phi_deg: float = 0.0

# ── Seam (SD-VILLAGE-TERRAIN-2 §Seam) ─────────────────────────────────────────
## Radial width over which base h → 0 at r = lawn_radius (C0 rim). SD-VILLAGE-TERRAIN-6.
@export var rim_blend_m: float = 5.0
## Mechanical rim tolerance vs outer HillsHeightfield.sample_y (AC-VT8). SD-VILLAGE-TERRAIN-6.
@export var rim_eps_m: float = 0.05

# ── Caps (SD-VILLAGE-TERRAIN-2 §Caps) ─────────────────────────────────────────
## Hard clamp on positive h (A2). ivy-82zn.14.1: 0.8 → 1.6 (taller open-lawn relief).
@export var max_rise_m: float = 1.6
## Hard clamp on negative h; covers pond basin (A2). ivy-82zn.14.1: 0.6 → 0.9.
@export var max_depression_m: float = 0.9
## Mechanical ceiling on sample_slope_deg along every path polyline (A2).
## ivy-82zn.14.10: 8 → 18. The village hill falls ~8.5 m from the hero to the village edge; the
## raw hill reaches ~17° along lanes, so an 8° cap built metre-high path embankments.
@export var max_path_slope_deg: float = 18.0

# ── Hero sanctum (SD-VILLAGE-TERRAIN-2 §Hero) ─────────────────────────────────
## Flat-disc radius about HERO_DOOR_STOOP; h_target = 0 (ivy sim / planting sanctity).
@export var hero_flat_r_m: float = 7.0
## Smooth blend from flat disc to surrounding field.
@export var hero_skirt_m: float = 3.0

# ── Cottage pads (SD-VILLAGE-TERRAIN-2 §Pads) ─────────────────────────────────
## Grow cottage_exterior_rect before flattening.
@export var pad_margin_m: float = 0.6
## Pad-edge blend width.
@export var pad_skirt_m: float = 2.0
## Mechanical cap on pad skirt slope (foundation readability).
@export var pad_edge_slope_max_deg: float = 8.0

# ── Open-lawn relief envelope (ivy-82zn.14.1; were private consts in VillageTerrain) ──
## Base relief stays fully quiet within this of a grown pad rect.
@export var open_lawn_pad_quiet_m: float = 2.25
## Distance over which relief ramps back to full beyond the pad quiet band.
@export var open_lawn_pad_fade_m: float = 14.0
## Distance beyond the hero flat disc over which relief ramps to full.
@export var hero_relief_fade_m: float = 10.0
## Distance beyond the plaza rect over which relief ramps to full.
@export var plaza_relief_fade_m: float = 10.0
## Distance beyond 0.85 × pond rim over which relief ramps to full.
@export var pond_relief_fade_m: float = 12.0

# ── Pond basin (SD-VILLAGE-TERRAIN-2 §Pond) ────────────────────────────────────
## Basin floor relative to local field (negative). AR-VT-GAP-1.
@export var pond_depth_m: float = -0.6
## Floor radius = MEAN_WATER_RADIUS_M × scale.
@export var pond_floor_scale: float = 1.0
## Rim radius = BANK_OUTER_M + extra (where basin returns to field).
@export var pond_rim_extra_m: float = 1.5
## Raised lip at rim for bank scatter read.
@export var pond_lip_rise_m: float = 0.12
## Lip Gaussian width.
@export var pond_lip_sigma_m: float = 1.2
## Blend of basin stamp into base beyond rim.
@export var pond_skirt_m: float = 2.0
## Water surface sits this far below the lip (water below lip, above floor).
@export var pond_water_inset_m: float = 0.10

# ── Plaza (SD-VILLAGE-TERRAIN-2 §Plaza) ───────────────────────────────────────
## Plaza plateau offset vs local field. 0 = gentle flattening that never blocks CamSun.
@export var plaza_relief_m: float = 0.0
## Plaza blend width.
@export var plaza_skirt_m: float = 2.0

# ── Knolls (SD-VILLAGE-TERRAIN-2 §Knoll) ─────────────────────────────────────
## Seeded additive mounds (A3 relief character).
@export var knoll_count: int = 2
## Peak per mound (clamped by max_rise_m). ivy-82zn.14.1: 0.70 → 1.00. ivy-82zn.14.5: 1.00 → 0.95
## (seeds 10 / 28 flank + base noise 8.09° / 8.12° → 7.79° / 7.82°, HEAD 7.70° / 5.54°).
@export var knoll_height_m: float = 0.95
## Mound footprint radius. ivy-82zn.14.1: 12 → 18 (wider so the taller mound stays ≤ 8°).
@export var knoll_radius_m: float = 18.0
## Min centre-to-centre spacing. ivy-82zn.14.1: 10 → 28 (stops mounds stacking into a cap crease).
@export var knoll_min_sep_m: float = 28.0
## No mound centre within this of HERO_DOOR_STOOP. ivy-82zn.14.1: 12 → 26 (keeps the mound
## flank off the hero relief fade ramp, which otherwise steepens it past 8°).
@export var knoll_hero_clear_m: float = 26.0
## Min distance from a mound centre to any path polyline (ivy-82zn.14.1; was knoll_radius_m).
@export var knoll_path_clear_m: float = 18.0
## Min distance from a mound centre to any grown cottage pad rect (ivy-82zn.14.1).
@export var knoll_pad_clear_m: float = 18.0
## Reject mound centres whose azimuth-from-G is within this of the sun E/W azimuths.
@export var knoll_sun_corridor_half_deg: float = 35.0

# ── Village swell (ivy-82zn.14.1; architect plan ivy-82zn.14.4) ──────────────
## A low-frequency field that the stamp ANCHORS read (pad heights, plaza, pond, path spine), so
## pads / plaza / paths sit at gently different heights while each stays flat. Without it every
## anchor sat at exactly 0 m and the CamSun frame was pinned to datum. 0 = off (fixer-tree terrain).
## ivy-82zn.14.10: 0.5 → 0.25. The hill now carries the anchors' height differences; a +0.4 m swell
## at the outermost cottage ate the hero-to-edge fall below one cottage on seeds 11 and 13.
@export var swell_amp_m: float = 0.25
## Swell wavelength (single octave, no warp). Long so the field stays gentle.
@export var swell_feature_m: float = 80.0
## Swell ramps from 0 to full over this beyond the hero flat disc + skirt.
@export var swell_hero_fade_m: float = 10.0
## Swell ramps to 0 over this inside the rim taper band (rim seam AC-VT8 untouched).
@export var swell_rim_fade_m: float = 12.0
## Swell scale inside the E/W sun corridors (ramps back to 1 over 15° outside them). 1 = no effect.
@export var swell_sun_corridor_gain: float = 1.0

# ── Village hill (ivy-82zn.14.10; architect plan ivy-82zn.14.9) ──────────────
# Village-scale large layer: the hero stands on a crest and the ground falls about one cottage
# (ridge 6.84 m) to the village edge. The hero stays at world y = 0; World lowers the village
# by VillageTerrain.hero_datum_y (option A datum). 0 rise = the pre-hill detail terrain.
## Crest height above the lawn rim datum (m). 0 = no hill.
@export var hill_rise_m: float = 8.5
## Profile shape: 0 = straight cone, 1 = smoothstep (flat crest shoulder and soft toe).
@export var hill_shoulder: float = 0.3
## Falloff exponent on the normalised distance: >1 broad crown, <1 quick drop then long toe.
@export var hill_falloff_pow: float = 1.0
## Hill centre moved from the hero stoop toward the hamlet centre (0 = on the hero, 1 = on G).
@export var hill_centre_shift: float = 0.0
## Extra flat crest radius beyond the hero flat disc + skirt (m).
@export var hill_crest_extra_m: float = 0.0
## Where the fall ends beyond the farthest cottage pad corner (m; negative ends it inside).
@export var hill_end_margin_m: float = 2.0
## Plaza: 1 = tilts with the hill, 0 = level terrace cut into the slope.
@export var plaza_hill_follow: float = 1.0
## Steepest bank a terrace (cottage pad, pond, level plaza) cuts into the hill (°).
@export var hill_bank_max_deg: float = 30.0

# ── Mesh (SD-VILLAGE-TERRAIN-2 §Mesh) ─────────────────────────────────────────
## Lawn mesh cell size (resolution vs tri budget).
@export var terrain_mesh_step_m: float = 2.0
## Central-difference step for sample_normal.
@export var normal_eps_m: float = 0.35

# ── Consumer toggles (SD-VILLAGE-TERRAIN-2 §Consumer) ────────────────────────
## A1 — path-polyline vertices use sample_y; off-path figure Y stays datum.
@export var wanderer_follow_terrain: bool = true
## Free/orbit eye y floored at sample_y(eye.xz) + clearance (anti-knoll-clip). AR-VT-GAP-5.
@export var camera_ground_clearance_m: float = 0.35

# ── Material (SD-VILLAGE-TERRAIN-2 §Material) ─────────────────────────────────
## Lawn shader matches outer-hill rim albedo (fuzzy, pairs with ivy-ska0.1 tint tokens).
@export var rim_tint_match_on: bool = true
## village_ground.gdshader terrain_slope_dark: albedo dim at full slope (0 = off). ivy-82zn.14.1.
@export var ground_slope_dark: float = 0.35
## Slope (°) at which the full ground_slope_dark applies (linear ramp from 0°).
## ivy-82zn.14.10: 10 → 30, else the whole hill flank is uniformly dimmed 35%.
@export var ground_slope_full_deg: float = 30.0
## Height tint: albedo × (1 ± tint) at ± ground_height_range_m (rises lighter, hollows darker).
@export var ground_height_tint: float = 0.12
## Height (m) above/below the rim datum where the height tint saturates.
## ivy-82zn.14.10: 1.2 → 8.5 (= hill_rise_m), so the crest reads lighter than the village edge.
@export var ground_height_range_m: float = 8.5


# ── Constructor helpers ────────────────────────────────────────────────────────

static func _fresh() -> VillageTerrainParams:
	var scr: Script = load("res://src/playground/village_terrain_params.gd")
	return scr.new() as VillageTerrainParams


static func production() -> VillageTerrainParams:
	## Returns a fresh resource with every field at production default (parity target).
	return _fresh()


# ── Parameter operations ───────────────────────────────────────────────────────

func duplicate_params() -> VillageTerrainParams:
	return duplicate(true) as VillageTerrainParams


func reset_to_production() -> void:
	## Restore all fields to production defaults; preserve layout_seed and variant=0.
	var fresh := _fresh()
	var keep_seed := layout_seed
	for prop in fresh.get_property_list():
		if prop.name == "resource_path" or prop.name.begins_with("_"):
			continue
		if prop.name in ["layout_seed", "variant"]:
			continue
		set(prop.name, fresh.get(prop.name))
	variant = 0
	layout_seed = keep_seed


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


func matches_preset(other: VillageTerrainParams, eps: float = 1e-5) -> bool:
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


# ── Presets ───────────────────────────────────────────────────────────────────

static func preset_tips() -> Dictionary:
	return {
		PRESET_PRODUCTION: "Gentle rolling lawn with knolls, pond basin, and cottage pads.",
		"Flat legacy": "Pre-terrain flat lawn — byte-parity with classic (INV-15).",
		"High relief": "Taller amplitude and more knolls — A/B playground only.",
		PRESET_NO_HILL: "Production without the village hill (hill_rise_m 0) — A/B the hill.",
	}


static func ordered_preset_names() -> Array:
	var names: Array = presets().keys()
	names.sort()
	names.erase(PRESET_PRODUCTION)
	names.insert(0, PRESET_PRODUCTION)
	return names


static func presets() -> Dictionary:
	## SD-VILLAGE-TERRAIN-2 §Presets.
	return {
		PRESET_PRODUCTION: {"variant": 0},
		"Flat legacy": {"variant": 1},
		"High relief": {
			"variant": 2,
			# ivy-82zn.14.1: kept above the (taller) production relief so A/B still reads.
			"base_amplitude_m": 0.90,
			"knoll_count": 4,
			"knoll_height_m": 1.60,
			"max_rise_m": 2.2,
			"center_bias_gain": 1.25,
			"swell_amp_m": 0.8,
		},
		PRESET_NO_HILL: {"variant": 0, "hill_rise_m": 0.0},
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


static func detect_preset_name(p: VillageTerrainParams) -> String:
	for name in ordered_preset_names():
		var ref := _fresh()
		ref.variant = p.variant
		ref.apply_preset(name)
		if p.matches_preset(ref):
			return name
	return CUSTOM_PRESET
