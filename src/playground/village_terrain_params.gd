## VillageTerrainParams — resource schema for the generated-village terrain (landscape-first, v2).
## SD-VILLAGE-TERRAIN-22 / AR-LF-PLAYGROUND: every knob here has its production default, and both
## VillageLayout.generate(seed, params) and the terrain playground read this one resource — no
## demo fork (G7). Removed v1 fields (village hill, knolls, swell, rim, caps, fades, skirts) are
## gone; from_dict ignores them so v1 JSON still loads.
class_name VillageTerrainParams
extends Resource

const SCHEMA := "village_terrain_playground.v2"
const SCHEMA_V1 := "village_terrain_playground.v1"
const PRESET_PRODUCTION := "Production"
const PRESET_FLAT := "Flat (A/B)"
const CUSTOM_PRESET := "Custom"

## landform_offset_mode values (SD-VILLAGE-TERRAIN-18).
const OFFSET_AUTO := 0
const OFFSET_MANUAL := 1

## Knobs that only change uniforms / consumers; field_signature() leaves them out (AR-LF-D11).
const NON_FIELD_KEYS := [
	"layout_seed",
	"wanderer_follow_terrain", "camera_ground_clearance_m",
	"ground_slope_dark", "ground_slope_full_deg", "ground_height_tint", "ground_height_range_m",
	"ground_tex_on", "ground_tex_scale_m", "ground_tex_strength", "ground_tex_brightness", "ground_macro",
	"ground_saturation", "ground_normal_strength", "ground_shade_strength", "ground_shade_edge_lo", "ground_blade_tint",
	"ground_shade_edge_hi",
]

## The ground-look knobs (material only; GroundLook.apply).
const GROUND_LOOK_KEYS := [
	"ground_tex_on", "ground_tex_scale_m", "ground_tex_strength", "ground_tex_brightness", "ground_macro",
	"ground_saturation", "ground_normal_strength", "ground_shade_strength", "ground_shade_edge_lo", "ground_blade_tint",
	"ground_shade_edge_hi",
]
const PRESET_UNTEXTURED := "Untextured ground (old)"

# ── Stage ──────────────────────────────────────────────────────────────────────
## 0 = Landscape (production), 1 = Flat (A/B): sample_y ≡ 0, hills flat legacy (INV-15).
@export var variant: int = 0
## Playground layout seed (VillageLayout.generate). Used when layout.generation_seed == 0.
@export var layout_seed: int = 7

# ── Landform L (SD-VILLAGE-TERRAIN-17 §1) ─────────────────────────────────────
## Noise type: 0 fbm (production), 1 billow, 2 derivative-damped, 3 ridged (comparison only).
@export var landform_noise: int = 0
@export var landform_wavelength_m: float = 260.0
## Full 0..1 noise scale (m). 0 = no landform (detail + far ridges only).
@export var landform_height_m: float = 16.0
@export var landform_octaves: int = 2
@export var landform_persistence: float = 0.5
@export var landform_warp: float = 0.10
## Derivative-damped noise only (Quilez k).
@export var landform_ddf_k: float = 0.5

# ── Placement / offset search (SD-VILLAGE-TERRAIN-18) ─────────────────────────
@export var landform_offset_mode: int = OFFSET_AUTO
## Manual mode offset; auto mode writes the chosen value back in the playground for copy-out.
@export var landform_offset_x: float = 0.0
@export var landform_offset_z: float = 0.0
@export var landform_rot_deg: float = 0.0
## SD-VILLAGE-TERRAIN-28 §2 (2026-11-18): 64 -> 128 so the storey rule finds candidates.
@export var landform_offset_candidates: int = 128
## Storey rule (SD-28 §2): height off the hero pad that counts as storey ground (m), and the share of
## buildable ground that must reach it for a candidate to be ordered first. 0 = rule off.
@export var storey_ground_m: float = 3.5
@export var storey_ground_frac_min: float = 0.10
@export var hero_site_slope_min_deg: float = 2.0
@export var hero_site_slope_max_deg: float = 9.0
@export var hero_not_crest_m: float = 1.5
@export var hero_not_hollow_m: float = 1.5
@export var relief_span_min_m: float = 5.0
@export var relief_span_target_m: float = 6.5
@export var relief_span_max_m: float = 8.0
@export var village_slope_p95_max_deg: float = 14.0

# ── Detail D (SD-VILLAGE-TERRAIN-17 §2) ───────────────────────────────────────
@export var base_amplitude_m: float = 0.25
@export var base_feature_m: float = 40.0
@export var noise_octaves: int = 2
@export var noise_persistence: float = 0.40
@export var warp_strength: float = 0.16

# ── Far ridges Rg (SD-VILLAGE-TERRAIN-17 §3) ──────────────────────────────────
@export var far_ridge_start_m: float = 70.0
@export var far_ridge_full_m: float = 100.0

# ── Sun corridor soft cap (SD-VILLAGE-TERRAIN-17 §4) ──────────────────────────
@export var sun_corridor_half_deg: float = 25.0
@export var sun_corridor_fade_deg: float = 10.0
@export var sun_clear_deg: float = 1.5
@export var sun_eye_height_m: float = 2.0
@export var sun_cap_soft_m: float = 2.0

# ── Fit (SD-VILLAGE-TERRAIN-19) ───────────────────────────────────────────────
@export var ring_max_slope_deg: float = 22.0
## Cottage site rejection (used by the plot sampler from WP2).
@export var max_site_slope_deg: float = 10.0
@export var hero_flat_r_m: float = 7.0
@export var hero_ring_min_m: float = 4.0
@export var hero_ring_max_m: float = 10.0
@export var pad_margin_m: float = 0.6
@export var pad_ring_min_m: float = 3.0
@export var pad_ring_max_m: float = 9.0
@export var pond_max_site_slope_deg: float = 6.0
## Water level = lowest bank point (r = BANK_OUTER_M) of the capped field − this.
@export var pond_freeboard_m: float = 0.15
## Basin floor relative to the bank level (negative).
@export var pond_depth_m: float = -0.6
@export var pond_floor_scale: float = 1.0
@export var pond_rim_extra_m: float = 1.5
@export var pond_lip_rise_m: float = 0.12
@export var pond_lip_sigma_m: float = 1.2
@export var pond_skirt_m: float = 2.0
## Kept from v1 (SD-22 "as today"); the water level now comes from pond_freeboard_m.
@export var pond_water_inset_m: float = 0.10
@export var plaza_max_tilt_deg: float = 6.0
## Plaza ring ladder [plaza_ring_m, plaza_ring_max_m] (SD-18 plaza_ring_ok, ivy-82zn.14.23).
@export var plaza_ring_m: float = 5.0
@export var plaza_ring_max_m: float = 10.0

# ── Paths (SD-VILLAGE-TERRAIN-20) ─────────────────────────────────────────────
## Open-land cap (fit zones follow the ring rule; SD-20 restated ivy-82zn.14.23).
@export var max_path_slope_deg: float = 14.0
@export var door_approach_m: float = 3.0
## A rank's best path-only layout at or under this open-land max is kept with path_cap_fallback.
@export var path_steep_accept_deg: float = 18.0
## Open-land max ≤ cap + this is accepted at once with path_cap_fallback (AR-LF-PERF P4; 0 = SD-20).
@export var path_near_miss_deg: float = 1.0

# ── Village (SD-VILLAGE-TERRAIN-21 restated 2026-11-18, human option B; generator, WP3) ───────
## Pair centre floor (exterior-rect centres) in PlotSampler and v1.
@export var cottage_min_sep_m: float = 16.0
@export var village_centre_r_max_m: float = 46.0
## Relax-ladder floor (1 m steps below cottage_min_sep_m, every attempt); clamped to ≤ the spacing.
@export var sep_ladder_floor_m: float = 14.0
## Multiplies the SD-21 primary / branch / capacity-branch lengths (1.0 = production table).
@export var path_len_scale: float = 1.0


## sep_ladder_floor_m clamped to ≤ cottage_min_sep_m (SD-22 restated 2026-11-18).
func effective_sep_ladder_floor_m() -> float:
	return minf(sep_ladder_floor_m, cottage_min_sep_m)

# ── Mesh ──────────────────────────────────────────────────────────────────────
@export var terrain_mesh_step_m: float = 2.0
@export var normal_eps_m: float = 0.35

# ── Consumer toggles ──────────────────────────────────────────────────────────
@export var wanderer_follow_terrain: bool = true
## Camera eye y floored at sample_y(eye.xz) + clearance.
@export var camera_ground_clearance_m: float = 0.35

# ── Material (shared terrain_tint.gdshaderinc, AR-LF-D9) ──────────────────────
@export var ground_slope_dark: float = 0.35
@export var ground_slope_full_deg: float = 30.0
@export var ground_height_tint: float = 0.12
## Height (m) above / below y_hero where the height tint saturates (village span).
@export var ground_height_range_m: float = 8.0

# ── Ground look (ground_look.gdshaderinc, ivy-82zn.17.1; lawn + lit meadow ring) ──────────────────
## Grass textures: ambientCG Grass005 on open lawn, Grass004 under trees. Off = procedural colour only.
@export var ground_tex_on: bool = true
## Size of one texture tile on the ground (m).
@export var ground_tex_scale_m: float = 3.0
## 0 = procedural colour, 1 = texture colour.
@export var ground_tex_strength: float = 1.0
## Multiplies the texture colour (match the lawn's brightness).
@export var ground_tex_brightness: float = 1.0
## How much of the procedural large patches survives as brightness variation on the texture.
@export var ground_macro: float = 0.6
## 1 = as authored; < 1 desaturates the lawn, the lit ring and the far hills' hand-lit colour.
@export var ground_saturation: float = 0.8
## Normal-map strength of the grass texture.
@export var ground_normal_strength: float = 0.6
## Under-tree texture (Grass004) weight under a canopy.
@export var ground_shade_strength: float = 1.0
## Tree-closeness band (0 = open, 1 = trunk) over which Grass005 turns into Grass004.
@export var ground_shade_edge_lo: float = 0.15
@export var ground_shade_edge_hi: float = 0.55
## Lawn grass blades re-hued by the ground texture under their roots (ivy-82zn.17.2); 0 = own sage.
@export var ground_blade_tint: float = 1.0


# ── Constructor helpers ────────────────────────────────────────────────────────

static func _fresh() -> VillageTerrainParams:
	var scr: Script = load("res://src/playground/village_terrain_params.gd")
	return scr.new() as VillageTerrainParams


static func production() -> VillageTerrainParams:
	## Fresh resource with every field at its production default (parity target).
	return _fresh()


# ── Parameter operations ───────────────────────────────────────────────────────

func duplicate_params() -> VillageTerrainParams:
	return duplicate(true) as VillageTerrainParams


func reset_to_production() -> void:
	## Restore all fields to production defaults; keep layout_seed; variant = 0.
	var fresh := _fresh()
	var keep_seed := layout_seed
	var vals := fresh.to_dict()
	for key in vals:
		set(key, vals[key])
	variant = 0
	layout_seed = keep_seed


func to_dict() -> Dictionary:
	## Script knobs only. (v1 also emitted script / resource_* storage props; loading such a copy-out
	## with from_dict set `script` and stripped the resource, ivy-82zn.14.14.)
	var d := {}
	for prop in get_property_list():
		if prop.name.begins_with("_"):
			continue
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			d[prop.name] = get(prop.name)
	return d


func from_dict(d: Dictionary) -> void:
	## Loads v2 and v1 JSON payloads. Keys this schema does not have (the removed v1 fields) are
	## ignored (AR-LF-PLAYGROUND copy-out).
	var known := to_dict()
	for key in d.keys():
		if key == "schema" or key == "knobs":
			continue
		if key in known:
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


func field_signature() -> int:
	## Hash of every knob that changes VillageTerrainField (AR-LF-D10). Material and consumer
	## knobs and layout_seed are left out, so a tint edit never rebuilds the field.
	## In auto mode the manual offset fields are only a copy-out of the search result (the
	## playground writes them back), so they do not change the field either.
	var auto := landform_offset_mode == OFFSET_AUTO
	var vals: Array = []
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if prop.name in NON_FIELD_KEYS:
			continue
		if auto and prop.name in ["landform_offset_x", "landform_offset_z", "landform_rot_deg"]:
			continue
		vals.append(get(prop.name))
	return hash(vals)


func matches_preset(other: VillageTerrainParams, eps: float = 1e-5) -> bool:
	## Manual-mode offsets are written back from the auto search; they are not part of a preset.
	var skip := ["layout_seed", "landform_offset_x", "landform_offset_z"]
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


# ── Presets (SD-VILLAGE-TERRAIN-22; no "Village on a hill (old)", AR-LF-D2) ──────

static func preset_tips() -> Dictionary:
	return {
		PRESET_PRODUCTION: "Landscape-first rolling hills: broad landform, village fitted into it.",
		PRESET_FLAT: "Flat lawn (sample_y ≡ 0) and flat legacy hills — A/B against production.",
		"Gentle": "Lower, longer hills (height 10 m, wavelength 300 m).",
		"Bold": "Taller, tighter hills (height 22 m, wavelength 220 m).",
		"Billow": "Billow noise: rounder lumps (soft-abs valleys), height 14 m, wavelength 400 m (matched relief).",
		"Derivative-damped": "Derivative-damped noise: smooth hollows, rougher crests.",
		"Ridged (comparison)": "Ridged noise — comparison only, expected to fail the slope ACs.",
		"Tight village (old spacing)": "Cottage spacing 8 m (only the 4 m wall gap binds), short paths (0.8), reach 37 m — the pre-WP3 village.",
		PRESET_UNTEXTURED: "Production terrain with the pre-ivy-82zn.17.1 ground: procedural colour only, no grass textures, full saturation.",
	}


static func ordered_preset_names() -> Array:
	return [
		PRESET_PRODUCTION, PRESET_FLAT, "Gentle", "Bold", "Billow", "Derivative-damped",
		"Ridged (comparison)", "Tight village (old spacing)", PRESET_UNTEXTURED,
	]


static func presets() -> Dictionary:
	return {
		PRESET_PRODUCTION: {"variant": 0},
		PRESET_FLAT: {"variant": 1},
		"Gentle": {"variant": 0, "landform_height_m": 10.0, "landform_wavelength_m": 300.0},
		"Bold": {"variant": 0, "landform_height_m": 22.0, "landform_wavelength_m": 220.0},
		# SD-VILLAGE-TERRAIN-30: matched relief. At the production scale (16 m / 260 m) billow has no
		# passing offset on any seed; 14 m / 400 m (knob max) passes on 20 / 20.
		"Billow": {"variant": 0, "landform_noise": 1, "landform_wavelength_m": 400.0, "landform_height_m": 14.0},
		"Derivative-damped": {"variant": 0, "landform_noise": 2},
		"Ridged (comparison)": {"variant": 0, "landform_noise": 3},
		"Tight village (old spacing)": {
			"variant": 0, "cottage_min_sep_m": 8.0, "sep_ladder_floor_m": 8.0, "path_len_scale": 0.8,
			"village_centre_r_max_m": 37.0,
		},
		PRESET_UNTEXTURED: untextured_ground_overrides(),
	}


## The ground before ivy-82zn.17.1 (owner picked the textured look as production, 2026-11-21).
static func untextured_ground_overrides() -> Dictionary:
	return {"variant": 0, "ground_tex_on": false, "ground_saturation": 1.0}


func apply_preset(name: String) -> void:
	var table := presets()
	assert(table.has(name), "Unknown preset: %s" % name)
	var keep_seed := layout_seed
	reset_to_production()
	layout_seed = keep_seed
	var overrides: Dictionary = table[name]
	for key in overrides.keys():
		set(key, overrides[key])


static func detect_preset_name(p: VillageTerrainParams) -> String:
	for name in ordered_preset_names():
		var ref := _fresh()
		ref.apply_preset(name)
		if p.matches_preset(ref):
			return name
	return CUSTOM_PRESET
