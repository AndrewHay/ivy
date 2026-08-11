## Tower cylindrical UV generation tests (AR-TOWER-1).
##
## Three behavioral contracts:
##   1. Every vertex in the generated mesh has a UV (no surface left at the
##      zero-degenerate default).  Catches a future surface being added to the
##      builder without set_uv calls.
##   2. The horizontal (circumference) repeat count is a whole integer so the
##      wrap seam disappears.  Catches "simplifying" the round() away.
##   3. UV scale is read from TowerSpec.brick_physical_size — changing it rescales
##      the tiling.  Catches the value being hardcoded.
##   4. That scale corresponds to the material's real-world patch size (W-066).
##      Tests 1-3 all check the formula against itself and so passed while the
##      brick rendered at a 2.07x aspect distortion (W-065); this one would not.
extends GutTest

const TowerBuilder = preload("res://src/world/tower_builder.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")


## ── helpers ──────────────────────────────────────────────────────────────────

## Returns {uvs, verts} for a built spec, or null if UV channel is absent.
func _build_arrays(spec: TowerSpec) -> Dictionary:
	var result := TowerBuilder.build(spec, false)
	var arrays := result.mesh.surface_get_arrays(0)
	return {
		"uvs": arrays[Mesh.ARRAY_TEX_UV],
		"verts": arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	}


## Returns the maximum U coordinate from wall-only vertices (y < spec.height − 0.01),
## which excludes the lip.  The lip spans all 96 rings and always has integer U values
## even when rounding is broken, so mixing lip and wall vertices masks the seam bug.
func _max_wall_u(spec: TowerSpec) -> float:
	var d := _build_arrays(spec)
	if d["uvs"] == null:
		return 0.0
	var uvs := d["uvs"] as PackedVector2Array
	var verts := d["verts"] as PackedVector3Array
	var max_u := 0.0
	for i in range(verts.size()):
		if verts[i].y < spec.height - 0.01:
			if uvs[i].x > max_u:
				max_u = uvs[i].x
	return max_u


## ── Test 1: every vertex has a UV ───────────────────────────────────────────

func test_uv_array_exists_and_matches_vertex_count() -> void:
	# If set_uv is never called, Godot omits the UV channel entirely, so this
	# fails before the UV content checks even run.
	var spec := TowerSpec.new()
	var result := TowerBuilder.build(spec, false)
	var arrays := result.mesh.surface_get_arrays(0)
	assert_not_null(arrays[Mesh.ARRAY_TEX_UV],
		"UV channel must be present in the mesh (set_uv was never called)")
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(uvs.size(), verts.size(),
		"UV count must equal vertex count")


func test_lip_vertices_have_non_zero_uv() -> void:
	# Lip vertices are at y = height + lip_thickness (3.65 m by default).
	# Their V coordinate is height / brick_physical_size.y = 3.889 — never (0,0).
	# If _build_lip forgot to call set_uv, every lip vertex lands at (0,0).
	var spec := TowerSpec.new()
	var d := _build_arrays(spec)
	if d["uvs"] == null:
		fail_test("UV array is absent — set_uv was never called")
		return
	var uvs := d["uvs"] as PackedVector2Array
	var verts := d["verts"] as PackedVector3Array
	var lip_y := spec.height + spec.lip_thickness
	var lip_count := 0
	var zero_count := 0
	for i in range(verts.size()):
		if is_equal_approx(verts[i].y, lip_y):
			lip_count += 1
			if uvs[i].is_zero_approx():
				zero_count += 1
	assert_gt(lip_count, 0,
		"lip vertices must be present in the mesh")
	assert_eq(zero_count, 0,
		"no lip vertex may have a zero-degenerate UV (0,0)")


func test_outer_wall_vertices_have_non_zero_v() -> void:
	# Every wall vertex above y=0 must have v > 0.  If set_uv was skipped on
	# a wall surface the whole surface collapses to v=0.
	var spec := TowerSpec.new()
	var d := _build_arrays(spec)
	if d["uvs"] == null:
		fail_test("UV array is absent")
		return
	var uvs := d["uvs"] as PackedVector2Array
	var verts := d["verts"] as PackedVector3Array
	var above_ground_zero_v := 0
	for i in range(verts.size()):
		if verts[i].y > 0.01 and uvs[i].y < 0.001:
			above_ground_zero_v += 1
	assert_eq(above_ground_zero_v, 0,
		"wall vertices above y=0 must have v > 0 (height / brick_physical_size.y)")


## ── Test 2: circumference repeat count is an integer ────────────────────────
##
## These tests move the door to 270° (west) so the north seam (a=0 / a=TAU)
## appears in the generated mesh, and they examine WALL vertices only.
## The lip spans all 96 rings regardless of the door and always produces integer
## U values at a=TAU; mixing lip vertices into the max_u search masks the bug.

func test_max_u_is_integer_so_wrap_seam_disappears() -> void:
	# Door at west (270°) → ring 0 (a0=0) and ring 95 (a1=TAU) are both present.
	# Wall U at a=TAU = (TAU/TAU)*int_repeats = int_repeats, which must be an integer.
	# Without round() the raw value ~12.566 would be used, giving frac ≈ 0.566.
	var spec := TowerSpec.new()
	spec.door_azimuth = 270.0
	var max_u := _max_wall_u(spec)
	assert_gt(max_u, 1.0, "max wall U must be non-trivial")
	var frac := fmod(max_u, 1.0)
	assert_almost_eq(frac, 0.0, 0.001,
		"max wall u (%.4f) must be a whole integer — wrap seam is not hidden" % max_u)


func test_int_repeats_matches_formula() -> void:
	# Direct formula check: max wall U == roundi(TAU * r / brick_physical_size.x).
	# Default: roundi(TAU * 2.0 / 1.8) = roundi(6.981) = 7.
	var spec := TowerSpec.new()
	spec.door_azimuth = 270.0
	var expected := roundi(TAU * spec.radius_outer / spec.brick_physical_size.x)
	var max_u := _max_wall_u(spec)
	assert_almost_eq(max_u, float(expected), 0.01,
		"horizontal repeat count must be roundi(TAU*r/brick_physical_size.x) = %d" % expected)


## ── Test 3: UV scale tracks brick_physical_size ─────────────────────────────

func test_wider_physical_width_reduces_horizontal_repeats() -> void:
	# Wider brick_physical_size.x means fewer repeats around the circumference.
	# x=0.90 → roundi(12.566/0.9)=14; x=1.80 → 7.
	# If the value were hardcoded, both would return the same count.
	var spec1 := TowerSpec.new()
	spec1.brick_physical_size = Vector2(0.90, 0.90)
	spec1.door_azimuth = 270.0
	var max_u1 := _max_wall_u(spec1)

	var spec2 := TowerSpec.new()
	spec2.brick_physical_size = Vector2(1.80, 0.90)
	spec2.door_azimuth = 270.0
	var max_u2 := _max_wall_u(spec2)

	assert_gt(max_u1, max_u2,
		"wider physical brick width must produce fewer horizontal repeats")


func test_uv_scale_matches_formula_for_each_physical_width() -> void:
	# For each physical width: max_wall_u == roundi(TAU * r / brick_physical_size.x).
	for width in [0.50, 1.00, 1.80]:
		var spec := TowerSpec.new()
		spec.brick_physical_size = Vector2(width, 0.90)
		spec.door_azimuth = 270.0
		var expected := roundi(TAU * spec.radius_outer / spec.brick_physical_size.x)
		var max_u := _max_wall_u(spec)
		assert_almost_eq(max_u, float(expected), 0.01,
			"brick_physical_size.x=%.2f: expected repeat count %d, got %.3f" % [width, expected, max_u])


## ── Test 4: UV scale corresponds to Bricks094's real-world physical size ────
##
## W-066: previous tests check formula self-consistency — every one of them
## passed while the physical constant was wrong (2.07× aspect distortion).
## These tests anchor the scale to the material's *documented* dimensions so
## a material swap that reintroduces the wrong value will fail immediately.

# Bricks094 real-world patch dimensions (source: ambientcg.com API).
const BRICKS094_WIDTH_M := 1.80   # dimensionX = 180 cm
const BRICKS094_HEIGHT_M := 0.90  # dimensionY = 90 cm


func test_default_brick_physical_size_matches_bricks094() -> void:
	# The default TowerSpec must record Bricks094's actual dimensions so that
	# swapping to a different material requires an explicit update.
	# Fails if the field reverts to a single scalar (e.g. Vector2(1.0, 1.0)).
	var spec := TowerSpec.new()
	assert_almost_eq(spec.brick_physical_size.x, BRICKS094_WIDTH_M, 0.001,
		"brick_physical_size.x must be Bricks094's 180 cm width; "
		+ "pre-fix scalar=1.0 gives 1.0 here")
	assert_almost_eq(spec.brick_physical_size.y, BRICKS094_HEIGHT_M, 0.001,
		"brick_physical_size.y must be Bricks094's 90 cm height; "
		+ "pre-fix scalar=1.0 gives 1.0 here")


func test_uv_density_matches_texture_physical_size() -> void:
	# One metre of tower-wall arc must display 1/brick_physical_size.x UV units
	# horizontally, and 1/brick_physical_size.y UV units vertically — i.e. the
	# same quantity of brick that one metre of the real Bricks094 patch depicts.
	#
	# Pre-fix (brick_physical_size = Vector2(1.0, 1.0)):
	#   horizontal: ~1.034 UV/m vs expected 0.556 UV/m → ~86% off → FAIL
	#   vertical: 1.000 UV/m vs expected 1.111 UV/m → ~10% off → FAIL
	var spec := TowerSpec.new()
	spec.door_azimuth = 270.0  # expose the north seam so max_wall_u reflects full circumference

	# ── Horizontal density ────────────────────────────────────────────────────
	var circ := TAU * spec.radius_outer
	var max_u := _max_wall_u(spec)
	var u_per_metre := max_u / circ
	var expected_u_per_metre := 1.0 / spec.brick_physical_size.x
	# 2% tolerance: integer rounding of int_repeats introduces at most 0.3% error.
	assert_almost_eq(u_per_metre, expected_u_per_metre, expected_u_per_metre * 0.02,
		("horizontal UV density %.4f UV/m must be ≈1/brick_physical_size.x (%.4f); "
		+ "pre-fix gives ~1.034 vs expected 0.556") % [u_per_metre, expected_u_per_metre])

	# ── Vertical density ──────────────────────────────────────────────────────
	var d := _build_arrays(spec)
	var uvs := d["uvs"] as PackedVector2Array
	var verts := d["verts"] as PackedVector3Array
	var expected_v_top := spec.height / spec.brick_physical_size.y
	var found := false
	for i in range(verts.size()):
		var vy := verts[i].y
		var vr := sqrt(verts[i].x * verts[i].x + verts[i].z * verts[i].z)
		if absf(vy - spec.height) < 0.01 and absf(vr - spec.radius_outer) < 0.01:
			assert_almost_eq(uvs[i].y, expected_v_top, 0.02,
				("wall-top V=%.3f must equal height/brick_physical_size.y=%.3f; "
				+ "pre-fix gives 3.5/1.0=3.5 vs correct 3.5/0.9=3.889") % [uvs[i].y, expected_v_top])
			found = true
			break
	assert_true(found, "must find a wall-top vertex at y≈height and r≈radius_outer")


func test_vertical_uv_scale_tracks_physical_height() -> void:
	# Vertical V = y / brick_physical_size.y. The top of the wall at y=3.5 m
	# must have v = 3.5 / brick_physical_size.y. A taller physical patch means
	# fewer vertical repeats over the same wall height.
	for ph in [0.50, 0.90, 2.00]:
		var spec := TowerSpec.new()
		spec.brick_physical_size = Vector2(1.80, ph)
		var d := _build_arrays(spec)
		if d["uvs"] == null:
			fail_test("UV array absent for brick_physical_size.y=%.2f" % ph)
			continue
		var uvs := d["uvs"] as PackedVector2Array
		var verts := d["verts"] as PackedVector3Array
		var expected_v := spec.height / spec.brick_physical_size.y
		var found := false
		for i in range(verts.size()):
			if is_equal_approx(verts[i].y, spec.height):
				assert_almost_eq(uvs[i].y, expected_v, 0.01,
					"wall top v must be height/brick_physical_size.y for ph=%.2f" % ph)
				found = true
				break
		assert_true(found, "must find a wall vertex at y=height for ph=%.2f" % ph)
