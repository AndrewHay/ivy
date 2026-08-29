extends GutTest

## INV-6 / SD-PHYS-4 — every tuning parameter must actually tune something.
##
## Written for W-042 as one of the guards M3 stresses. The dev tuning overlay takes its controls
## from the exported parameter list, so a parameter no call site reads becomes a slider that
## silently does nothing and M3/M4 iteration gets steered by it. That is W-039: `persistence_base`
## and `direction_memory` sat declared-but-unread while still producing correct numbers, because
## the literals at the call sites happened to equal the defaults.
##
## A parameter counts as read if a consumer file names it, or if `IvyParams` itself derives
## something from it — `field_sample_jitter_ratio` is reached through `field_sample_jitter()`, and
## that indirection is normal rather than a defect.
##
## Parameters whose feature does not exist yet are listed in `UNIMPLEMENTED` and asserted to be
## *exactly* that set, so the list cannot rot in either direction: a newly dead knob fails, and
## implementing one without removing it from the list fails too.
##
## AR-PARAM-3 also specifies a scan for §30 default *literals* at call sites. It is deliberately
## not implemented here — see W-085 for the measurement showing why it cannot work as written.

const PARAMS_PATH := "res://src/params/ivy_params.gd"

## Directories that consume parameters. `src/params/` is handled separately: it holds the
## declarations and the `content_hash()` name list, which reference every name trivially.
const CONSUMER_DIRS := [
	"res://src/sim/", "res://src/env/", "res://src/world/", "res://src/render/",
	"res://src/core/", "res://src/main/", "res://src/metrics/",
]

## Declared knobs whose feature is not built yet. Every one is presentation the M4 visual pass owns
## (§30 leaf and stem shaping) or a superseded M1 scaffold, and none is referenced by any consumer
## or by any `IvyParams` helper. Tracked as W-086; the M3 overlay must not offer these as live
## controls. Keep alphabetical within each group.
const UNIMPLEMENTED := IvyParams.OVERLAY_INERT

## Parameters a consumer reads without naming, with the reason. Anything added here admits the
## mechanical guard cannot see the use, so it needs a specific reason rather than just a name.
const READ_WITHOUT_NAMING := {}


func test_every_exported_parameter_is_read_or_declared_unimplemented() -> void:
	var names := _exported_names()
	assert_gt(names.size(), 30, "the exported parameter list must be non-trivial to scan")

	var sources := _consumer_sources()
	assert_gt(sources.size(), 10, "the consumer scan must find real source files")

	var dead: PackedStringArray = []
	for name in names:
		if not READ_WITHOUT_NAMING.has(name) and not _is_read(name, sources):
			dead.append(name)
	dead.sort()

	var expected := PackedStringArray(UNIMPLEMENTED)
	expected.sort()
	assert_eq(dead, expected,
		("declared-but-unread parameters must match UNIMPLEMENTED exactly (INV-6). "
			+ "Unexpected dead knobs, or an implemented one still listed: %s vs %s")
			% [str(dead), str(expected)])


func test_the_scan_fails_on_a_knob_nothing_reads() -> void:
	# The guard above only means something if a dead knob is genuinely invisible to the scan.
	# Both W-039 halves had this shape: named in the declarations and in content_hash(), nowhere
	# else. Asserting an invented name is unread proves the detector cannot pass everything.
	var sources := _consumer_sources()
	assert_false(_is_read("persistence_base_that_nothing_reads", sources),
		"an invented parameter name must read as unread")

	# And a parameter the model does use must read as read, or the detector would pass everything
	# by calling it all dead. persistence_base is the W-039 fix, so it is the sharpest probe.
	assert_true(_is_read("persistence_base", sources),
		"persistence_base must read as read (W-039 fix: Physiology.w_P takes params)")
	assert_true(_is_read("direction_memory", sources),
		"direction_memory must read as read (W-039 fix: GrowthStep blends by it)")


func test_helper_derived_parameters_count_as_read() -> void:
	# field_sample_jitter_ratio and gradient_epsilon_ratio are named only inside IvyParams, by the
	# helpers that turn them into absolute distances. Without this, the guard would report two
	# false positives and the honest UNIMPLEMENTED list would have to absorb them, which is how a
	# list like this starts lying.
	var sources := _consumer_sources()
	for name in ["field_sample_jitter_ratio", "gradient_epsilon_ratio"]:
		var named_by_consumer := false
		for text in sources.values():
			if text.contains(name):
				named_by_consumer = true
				break
		assert_false(named_by_consumer, "%s is expected to be reached only via a helper" % name)
		assert_true(_is_read(name, sources), "%s must count as read via its IvyParams helper" % name)


## ---- helpers ----

## Read = named by a consumer, or derived inside IvyParams somewhere other than its own
## declaration and the content_hash() name list.
func _is_read(name: String, sources: Dictionary) -> bool:
	for text in sources.values():
		if text.contains(name):
			return true
	for line in FileAccess.get_file_as_string(PARAMS_PATH).split("\n"):
		if not line.contains(name):
			continue
		var trimmed := line.strip_edges()
		if trimmed.begins_with("@export var " + name):
			continue
		if trimmed.begins_with("\"") or trimmed.begins_with("var names"):
			continue  # content_hash()'s name list
		return true
	return false


## Parsed from the declarations rather than a list maintained here, so a parameter added without a
## consumer is caught instead of being invisible to the test.
func _exported_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for line in FileAccess.get_file_as_string(PARAMS_PATH).split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("@export var "):
			continue
		var rest := trimmed.substr("@export var ".length())
		var cut := rest.find(":")
		if cut < 0:
			cut = rest.find(" ")
		if cut > 0:
			names.append(rest.substr(0, cut).strip_edges())
	return names


func _consumer_sources() -> Dictionary:
	var out := {}
	for dir_path in CONSUMER_DIRS:
		_collect(dir_path, out)
	return out


func _collect(path: String, out: Dictionary) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if d.current_is_dir():
			if fname != "." and fname != "..":
				_collect(path.path_join(fname) + "/", out)
		elif fname.ends_with(".gd"):
			var full := path.path_join(fname)
			out[full] = FileAccess.get_file_as_string(full)
		fname = d.get_next()
