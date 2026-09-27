class_name ArchetypePreset
extends RefCounted

## Code-table registry of ivy wall archetype presets (ivy-68j / ivy-50f).
##
## A preset encodes ONLY the IvyParams overrides that differ from the shipped defaults,
## plus three run-level parameters (seeds, seed_y, day) that are NOT IvyParams fields.
## Non-overridden IvyParams fields always track the shipped ivy_params_default.tres so
## a default retune automatically reaches all presets.
##
## DENSE values are FROZEN (human-approved, ivy-68j.2). Do not edit them.
##
## API:
##   static func all()          -> Dictionary          # name -> ArchetypePreset
##   static func for_name(name) -> ArchetypePreset     # NOTE: not get() — shadows Object.get
##   static func names()        -> PackedStringArray
##   func build_params()        -> IvyParams
##   func apply_to(params)      -> void
##   func seed_positions(spec)  -> PackedVector3Array

var label: String
var seeds: int
var seed_y: float
var day: int
## { IvyParams-field-name -> value }. Only the 6 overridden fields:
## branch_rate, tip_cap_soft, tip_cap_hard, leaf_width_base, internode_base, leaf_cap.
var param_overrides: Dictionary


# ── Internal registry ──────────────────────────────────────────────────────
# Populated lazily in all() / for_name() via _ensure_registry().
# NOTE: We intentionally do NOT call ArchetypePreset.new() inside any static
# method of this class — doing so causes a circular-dependency compile error
# in Godot 4 GDScript. The registry is instead built from raw data tables
# using a two-step fill pattern: create via super class constructor, then fill.
static var _registry: Dictionary = {}

# Raw preset data table. Only plain-type values (no ArchetypePreset instances)
# so this can safely live as a class-level constant without any self-reference.
const _PRESETS: Array = [
	{
		"label":          "dense",
		"seeds":          7,
		"seed_y":         0.02,
		"day":            400,
		"param_overrides": {
			"branch_rate":     1.7,
			"tip_cap_soft":    360,
			"tip_cap_hard":    600,
			"leaf_width_base": 0.22,
			"internode_base":  0.02,
			"leaf_cap":        400000,
		},
	},
	{
		"label":          "mid",
		"seeds":          7,
		"seed_y":         0.02,
		"day":            150,
		"param_overrides": {
			"branch_rate":     1.0,
			"tip_cap_soft":    96,
			"tip_cap_hard":    160,
			"leaf_width_base": 0.12,
			"internode_base":  0.04,
			"leaf_cap":        60000,
		},
	},
	{
		"label":          "sparse",
		"seeds":          7,
		"seed_y":         1.5,
		"day":            150,
		"param_overrides": {
			"branch_rate":     0.3,
			"tip_cap_soft":    96,
			"tip_cap_hard":    160,
			"leaf_width_base": 0.075,
			"internode_base":  0.08,
			"leaf_cap":        20000,
		},
	},
]


## Populate _registry from _PRESETS. Called lazily from all()/for_name()
## to avoid any static-initializer ordering issues. Does NOT call
## ArchetypePreset.new() in a static context — callers outside the class
## create the instance, then _fill_from_dict() sets its fields.
static func _ensure_registry() -> void:
	if not _registry.is_empty():
		return
	# We cannot call ArchetypePreset.new() here (same-class static method
	# circular ref in Godot 4). Instead: use RefCounted.new() on the
	# preloaded script via load(), which resolves to an ArchetypePreset
	# instance safely because the script is already compiled by the time
	# any external caller can invoke _ensure_registry().
	var script := load("res://src/params/archetype_preset.gd")
	for data: Dictionary in _PRESETS:
		var p: ArchetypePreset = script.new() as ArchetypePreset
		_fill_from_dict(p, data)
		_registry[data["label"]] = p


static func _fill_from_dict(p: ArchetypePreset, data: Dictionary) -> void:
	p.label          = data["label"]
	p.seeds          = int(data["seeds"])
	p.seed_y         = float(data["seed_y"])
	p.day            = int(data["day"])
	p.param_overrides = data["param_overrides"].duplicate()


## Returns all presets as a { name: ArchetypePreset } dictionary.
static func all() -> Dictionary:
	_ensure_registry()
	return _registry


## Returns the preset for the given name. Asserts on unknown names.
## Named `for_name` (not `get`) to avoid shadowing Object.get.
static func for_name(name: String) -> ArchetypePreset:
	_ensure_registry()
	assert(_registry.has(name), "ArchetypePreset: unknown archetype '%s'" % name)
	return _registry[name]


## Returns the canonical ordered list of preset names.
static func names() -> PackedStringArray:
	return PackedStringArray(["dense", "mid", "sparse"])


## Returns a new IvyParams built from ivy_params_default.tres with this preset's
## param_overrides applied.  Non-overridden fields track the shipped defaults.
func build_params() -> IvyParams:
	var p := load("res://src/params/ivy_params_default.tres").duplicate(true) as IvyParams
	apply_to(p)
	return p


## Applies param_overrides onto an existing IvyParams instance via set().
## Used by the capture tool which already holds Main.params; leaf_cap must have
## been applied (via this or build_params) BEFORE the building is loaded —
## it sizes plant_render.gd's MultiMesh buffer once at bootstrap.
func apply_to(params: IvyParams) -> void:
	for key: String in param_overrides:
		params.set(key, param_overrides[key])


## Returns seed positions for this preset on the given WallSpec.
##
## Lifted verbatim from capture_wall_archetype.gd's seeding loop so that GUT tests
## and the screenshot capture tool grow the IDENTICAL plant from the same seeds.
## seed_positions math per ivy-50f:
##   seeds <= 1  -> [Vector3(0, seed_y, 0.01)]
##   else:         margin = half_len * 0.15; usable = half_len - margin
##                 for i in seeds: t = i/(seeds-1)*2-1; pos = Vector3(t*usable, seed_y, 0.01)
##
## spec may be null (e.g. when called from the capture tool before the wall
## node exposes its wall_spec).  Mirrors the legacy raw-override path in
## capture_wall_archetype.gd which falls back to half_len = 9.0 (half of the
## default 20 m wall spec) rather than crashing.
func seed_positions(spec: WallSpec) -> PackedVector3Array:
	var positions := PackedVector3Array()
	var half_len: float = spec.length * 0.5 if spec != null else 9.0
	if seeds <= 1:
		positions.append(Vector3(0.0, seed_y, 0.01))
	else:
		var margin: float = half_len * 0.15
		var usable: float = half_len - margin
		for i in range(seeds):
			var t: float = float(i) / float(seeds - 1) * 2.0 - 1.0  # -1..1
			positions.append(Vector3(t * usable, seed_y, 0.01))
	return positions
