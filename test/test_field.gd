## SD-ENV-3/4/5, AR-FIELD — Sparse hash field read correctness.
##
## Written for W-042 as one of the guards M3 stresses. The field visualisation
## added in M3 reads the environment field directly, so errors that were theoretical
## become visible on screen. Six invariants are locked in:
##
##   1. Trilinear interpolation is exact on a linear ramp (SD-ENV-3).
##   2. Central-difference gradient recovers a known slope (SD-ENV-5).
##   3. A uniform field yields EXACTLY zero gradient (SD-EDGE-12) — not approximately,
##      because a spurious gradient in a uniform field injects phantom direction.
##   4. A read outside any allocated cell returns the fallback (SD-EDGE-15).
##   5. Shell projection maps a point 0.35 m outside the tower onto the surface (AR-FIELD-3).
##   6. No nearest-cell accessor exists on the public API (SD-ENV-3 enforced by absence).
extends GutTest

const SparseHashField = preload("res://src/env/sparse_field.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")

const CH := SparseHashField.Channel.P_BAR_L
## Distinct sentinel so a zero result cannot be mistaken for an absent fallback.
const FALLBACK := -99.0


## Allocates the eight lattice corners of a unit cube ([0..1]³, cell_size=1).
## Every cell's value equals its x-coordinate, so f(x,y,z) = x — a field that is
## linear in x and flat in y and z.  Trilinear interpolation is exact on any linear
## function, so the returned value at any interior sample must equal exactly px.
func _make_linear_ramp_field() -> SparseHashField:
	var field := SparseHashField.new(1.0)
	for ix in 2:
		for iy in 2:
			for iz in 2:
				var slot := field.ensure_cell(Vector3i(ix, iy, iz))
				field.write_slot(CH, slot, float(ix))
	return field


## Allocates the same eight corners with a constant value.
## Any central-difference gradient across this field must be exactly zero.
func _make_uniform_field(value: float) -> SparseHashField:
	var field := SparseHashField.new(1.0)
	for ix in 2:
		for iy in 2:
			for iz in 2:
				var slot := field.ensure_cell(Vector3i(ix, iy, iz))
				field.write_slot(CH, slot, value)
	return field


func test_trilinear_exact_on_linear_ramp() -> void:
	# SD-ENV-3: trilinear interpolation must recover a linear field exactly, not just
	# approximately.  For f(x,y,z)=x, the result at any (px,py,pz) in the cube is px.
	# Tolerance 1e-5 absorbs float32/float64 boundary conversion; the mathematical
	# claim is exact, not a best-effort approximation.
	var field := _make_linear_ramp_field()
	var cases := [
		[Vector3(0.5, 0.5, 0.5), 0.5],
		[Vector3(0.3, 0.7, 0.2), 0.3],
		[Vector3(0.8, 0.1, 0.9), 0.8],
		[Vector3(0.0, 0.5, 0.5), 0.0],
		[Vector3(1.0, 0.5, 0.5), 1.0],
	]
	for pair in cases:
		var p: Vector3 = pair[0]
		var expected: float = pair[1]
		var got := field.read_trilinear(CH, p, FALLBACK)
		assert_almost_eq(got, expected, 1e-5,
			"trilinear at %s must equal %.1f exactly (SD-ENV-3)" % [p, expected])


func test_central_difference_gradient_recovers_known_slope() -> void:
	# SD-ENV-5: for f(x,y,z)=x, the central-difference gradient is (1,0,0).
	# epsilon = 0.09 m matches the default gradient_epsilon (1.5 * field_cell = 1.5*0.06).
	# The tolerance is 1e-4, not exact, because the sample points are stored as float32
	# Vector3 components and the division by 2*eps compounds rounding.
	var field := _make_linear_ramp_field()
	var eps := 0.09
	var p := Vector3(0.5, 0.5, 0.5)
	var dfdx := (
		field.read_trilinear(CH, p + Vector3(eps, 0.0, 0.0), FALLBACK)
		- field.read_trilinear(CH, p - Vector3(eps, 0.0, 0.0), FALLBACK)
	) / (2.0 * eps)
	var dfdy := (
		field.read_trilinear(CH, p + Vector3(0.0, eps, 0.0), FALLBACK)
		- field.read_trilinear(CH, p - Vector3(0.0, eps, 0.0), FALLBACK)
	) / (2.0 * eps)
	var dfdz := (
		field.read_trilinear(CH, p + Vector3(0.0, 0.0, eps), FALLBACK)
		- field.read_trilinear(CH, p - Vector3(0.0, 0.0, eps), FALLBACK)
	) / (2.0 * eps)
	assert_almost_eq(dfdx, 1.0, 1e-4, "∂f/∂x must recover slope 1 for f(x)=x ramp (SD-ENV-5)")
	assert_almost_eq(dfdy, 0.0, 1e-4, "∂f/∂y must be zero for f(x)=x ramp (SD-ENV-5)")
	assert_almost_eq(dfdz, 0.0, 1e-4, "∂f/∂z must be zero for f(x)=x ramp (SD-ENV-5)")


func test_uniform_field_yields_exactly_zero_gradient() -> void:
	# SD-EDGE-12: a spurious gradient in a uniform field would inject phantom direction
	# into tip growth.  The central-difference NUMERATOR must be exactly 0.0, not
	# approximately — which is why assert_almost_eq is wrong here and assert_eq is right.
	#
	# For a constant field C: read_trilinear returns C * weight_sum / weight_sum = C
	# at any fully-allocated point, regardless of the weights.  C - C = 0.0 exactly
	# in IEEE 754.  This holds for any non-degenerate C (7.5 is exactly representable).
	var field := _make_uniform_field(7.5)
	var eps := 0.09
	var test_points := [Vector3(0.5, 0.5, 0.5), Vector3(0.4, 0.6, 0.3)]
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for p in test_points:
		for axis in axes:
			var v_plus := field.read_trilinear(CH, p + axis * eps, FALLBACK)
			var v_minus := field.read_trilinear(CH, p - axis * eps, FALLBACK)
			assert_eq(v_plus - v_minus, 0.0,
				"uniform field must yield EXACTLY zero central-difference numerator (SD-EDGE-12)")


func test_out_of_shell_read_returns_fallback() -> void:
	# SD-EDGE-15: the environment field is only allocated around the tower shell.
	# A read at any position outside that allocation must return the caller-supplied
	# fallback, never a fabricated value such as 0.0 — which would look like zero
	# crowding or zero light and introduce a phantom gradient back at the wall.
	var field := SparseHashField.new(0.06)
	# No cells allocated; every read must return the sentinel.
	var sentinel := 42.5
	var test_points := [
		Vector3(10.0, 10.0, 10.0),
		Vector3(-5.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.0),
		Vector3(3.0, 1.75, 0.0),
	]
	for p in test_points:
		var result := field.read_trilinear(CH, p, sentinel)
		assert_eq(result, sentinel,
			"read_trilinear outside allocated cells must return fallback (SD-EDGE-15): %s" % p)


func test_shell_projection_maps_point_to_surface() -> void:
	# AR-FIELD-3: SurfaceQuery.project_to_shell() is the guard that prevents floating
	# tips (up to max_float = 0.40 m outside the wall) from reading unallocated cells
	# and triggering a radial gradient that yanks them back at the wall.  The projected
	# point must lie on the SDF zero-set: |Φ(p_proj)| ≤ 1 mm.
	var params := IvyParams.new()
	var surface := SurfaceQuery.new()
	surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), params)
	var spec := TowerSpec.new()
	# South face of the cylinder: outward is +z, surface is at z = radius_outer.
	var outside := Vector3(0.0, spec.height * 0.5, spec.radius_outer + 0.35)
	var projected := surface.project_to_shell(outside)
	var phi := surface.signed_distance(projected)
	assert_almost_eq(phi, 0.0, 0.001,
		"project_to_shell must place a point 0.35 m outside on the surface |Φ|≤1mm (AR-FIELD-3)")


func test_no_nearest_cell_accessor_on_public_api() -> void:
	# SD-ENV-3 enforced by absence: nearest-cell sampling is the primary cause of grid
	# banding (artifact blacklist R-3).  If the method exists it will eventually be called.
	# read_trilinear must be the sole read primitive.
	var text := FileAccess.get_file_as_string("res://src/env/sparse_field.gd")
	assert_false(text.is_empty(), "sparse_field.gd must be readable by the test")
	var banned := ["read_nearest", "sample_nearest", "nearest_cell",
				   "get_nearest", "nearest_value", "read_cell_nearest"]
	for name in banned:
		assert_false(text.contains(name),
			"SparseHashField must not expose a nearest-cell read (SD-ENV-3): %s" % name)
	assert_true(text.contains("func read_trilinear"),
		"read_trilinear must be present as the sole read primitive (SD-ENV-3)")
