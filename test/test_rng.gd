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
	var scan_dirs := ["res://src/sim/", "res://src/env/", "res://src/world/", "res://src/render/"]
	for dir_path in scan_dirs:
		_scan_dir(dir_path, offenders)
	assert_eq(offenders.size(), 0, str(offenders))


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
			if text.contains("randf(") or text.contains("randi(") or text.contains("RandomNumberGenerator"):
				if text.contains("stream.randf") or text.contains("stream.randi"):
					fname = d.get_next()
					continue
				offenders.append(full)
		fname = d.get_next()
