extends GutTest

const RngStream = preload("res://src/core/rng_stream.gd")
const Hash64 = preload("res://src/core/hash64.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")

func test_stream_reproducible() -> void:
	var a := RngStream.from_seed(42)
	var b := RngStream.from_seed(42)
	for _i in range(10):
		assert_eq(a.randf(), b.randf())


func test_derive_independence() -> void:
	var parent := RngStream.from_seed(100)
	var child0 := parent.derive(0)
	var child1 := parent.derive(1)
	var a := child0.randf()
	var b := child1.randf()
	assert_ne(a, b)
	var parent_copy := RngStream.from_seed(100)
	assert_eq(parent_copy.randf(), parent.randf())


func test_jitter_vec3_deterministic_and_bounded() -> void:
	var v0 := Hash64.jitter_vec3(7, 3, 1)
	var v1 := Hash64.jitter_vec3(7, 3, 1)
	assert_eq(v0, v1)
	assert_lte(v0.length(), 1.0 + 1e-6)


func test_derived_draws_come_from_the_stream_not_the_global_rng() -> void:
	# An unqualified `randf()` inside RngStream binds to the @GlobalScope built-in —
	# the process-global RNG, seeded randomly at startup — instead of the class method.
	# Callers using `stream.randf()` stay correct, so the only visible symptom is that
	# helpers built on top of it stop being reproducible, which silently breaks INV-7.
	var a := RngStream.from_seed(7).rand_unit_vector()
	var b := RngStream.from_seed(7).rand_unit_vector()
	assert_eq(a, b, "rand_unit_vector must be reproducible from an identical seed")
	assert_almost_eq(a.length(), 1.0, 1e-6, "rand_unit_vector must be unit length")

	var probe := RngStream.from_seed(7)
	assert_almost_eq(
		a.z, 1.0 - 2.0 * probe.randf(), 1e-9, "z must derive from the stream's first draw"
	)

	assert_eq(
		RngStream.from_seed(9).normal_std(),
		RngStream.from_seed(9).normal_std(),
		"normal_std must be reproducible from an identical seed"
	)


func test_no_stray_random_outside_rng_stream() -> void:
	var offenders: PackedStringArray = []
	for dir_path in _stray_random_scan_dirs():
		_scan_dir(dir_path, offenders)
	assert_eq(offenders.size(), 0, str(offenders))


func test_stray_random_detector_flags_unqualified_randf_with_qualified_calls() -> void:
	var text := "if tip.stream.randf() < p:\n\tvar x := randf()\n"
	assert_true(
		_text_has_stray_random(text),
		"unqualified randf must flag even when stream.randf is present in the same file"
	)


func test_stray_random_detector_flags_randf_range() -> void:
	var text := "var angle := deg_to_rad(randf_range(0.0, 1.0))\n"
	assert_true(_text_has_stray_random(text), "unqualified randf_range must be flagged")


func test_stray_random_detector_ignores_qualified_calls() -> void:
	var text := "if tip.stream.randf() < p:\n\tvar x := tip.stream.randf_range(0.0, 1.0)\n"
	assert_false(_text_has_stray_random(text))


func test_stray_random_scan_dirs_include_core_params_main() -> void:
	var dirs := _stray_random_scan_dirs()
	for expected in ["res://src/core/", "res://src/params/", "res://src/main/"]:
		assert_true(expected in dirs, "scan must include %s" % expected)


func test_stray_random_w033_shaped_defect_in_core_would_be_caught() -> void:
	## W-033 lived in src/core/rng_stream.gd (excluded). Same defect in any other
	## scanned file must be caught — self.randf() is fine, bare randf() is not.
	var w033_shape := """
func normal_std() -> float:
	var u1: float = max(randf(), 1e-8)
	var u2: float = self.randf()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)
"""
	assert_true(_text_has_stray_random(w033_shape))


var _stray_rand_res: Array[RegEx] = []


func _stray_random_scan_dirs() -> Array[String]:
	return [
		"res://src/core/",
		"res://src/params/",
		"res://src/main/",
		"res://src/sim/",
		"res://src/env/",
		"res://src/world/",
		"res://src/render/",
	]


func _stray_rand_patterns() -> Array[RegEx]:
	if _stray_rand_res.is_empty():
		for pat in ["(?<![.\\w])randf\\(", "(?<![.\\w])randi\\(", "(?<![.\\w])randf_range\\("]:
			var re := RegEx.new()
			re.compile(pat)
			_stray_rand_res.append(re)
	return _stray_rand_res


func _text_has_stray_random(text: String) -> bool:
	for re in _stray_rand_patterns():
		if re.search(text) != null:
			return true
	return text.contains("RandomNumberGenerator")


func _scan_dir(path: String, offenders: PackedStringArray) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if d.current_is_dir():
			if fname != "." and fname != "..":
				_scan_dir(path.path_join(fname) + "/", offenders)
		elif fname.ends_with(".gd"):
			var full := path.path_join(fname)
			if full.ends_with("rng_stream.gd") or full.ends_with("hash64.gd"):
				fname = d.get_next()
				continue
			var text := FileAccess.get_file_as_string(full)
			if _text_has_stray_random(text):
				offenders.append(full)
		fname = d.get_next()
