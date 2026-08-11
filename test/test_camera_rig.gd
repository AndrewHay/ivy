## Tests for CameraRig.select() — AR-SCENE-3 compliance.
##
## Also: frustum-visibility regression tests for the four canonical cameras.
## These use pure arithmetic (no viewport, no scene) and run headlessly.
##
## ─── TSCN transform convention ────────────────────────────────────────────
## main.tscn stores Transform3D in ROW-MAJOR order:
##   Transform3D(a,b,c, d,e,f, g,h,i, ox,oy,oz)
##   Row 0 = (a,b,c), Row 1 = (d,e,f), Row 2 = (g,h,i)
##   basis.z = column 2 = (c, f, i)     ← 3rd, 6th, 9th params
##   camera forward = −basis.z = (−c, −f, −i)
##
## GDScript uses column-vector form:
##   Transform3D(x_axis, y_axis, z_axis, origin)
##   basis.x = x_axis, basis.y = y_axis, basis.z = z_axis
##   camera forward = −z_axis
##
## Conversion: for TSCN (a,b,c, d,e,f, g,h,i, ox,oy,oz), the GDScript
## equivalent is Transform3D(Vector3(a,d,g), Vector3(b,e,h), Vector3(c,f,i),
## Vector3(ox,oy,oz)).
## ──────────────────────────────────────────────────────────────────────────
##
## TDD cycle notes:
##   RED  — Confirmed by running the suite after writing the test with
##          GDScript constants that matched (via the column-vector form)
##          the two broken TSCN transforms that were in main.tscn.
##          Specifically broken_top and broken_sil in
##          test_broken_cam_transforms_fail_frustum_check represent those
##          transforms.  Running the suite with _CAM_TOP_T and
##          _CAM_SILHOUETTE_T set to those broken column-vector forms
##          produced:
##            test_all_canonical_cameras_see_tower_centre FAILED (CamTop dot=0)
##            test_cam_silhouette_tower_base_below_frame_centre FAILED (ndc_y=0.241)
##          This was the verified RED failure.
##   GREEN — After reverting both transforms in main.tscn to the correct
##          values and updating these constants to match (correct column
##          vectors), all 9 tests pass.
extends GutTest

const CameraRigScript = preload("res://src/world/camera_rig.gd")

# ─────────────────────────────────────────────────────────────────────────────
# Tower geometry — derived from TowerSpec defaults (AR-TOWER).
# ─────────────────────────────────────────────────────────────────────────────
const _TOWER_H := 3.50
const _TOWER_R := 2.00

# Default vertical FOV (degrees, keep-height, Godot 4 default).
const _FOV_DEG := 75.0

# ─────────────────────────────────────────────────────────────────────────────
# Canonical camera transforms — must mirror main.tscn (AR-SCENE-3).
#
# GDScript transform constants use the column-vector constructor.
# See file header for the TSCN ↔ GDScript conversion.
# ─────────────────────────────────────────────────────────────────────────────

# CamSun — south face at y=2, z=8.  forward = (0, 0, −1).
# TSCN: Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 8)
var _CAM_SUN_T := Transform3D(
		Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0, 2, 8))

# CamShade — north face at y=2, z=−8.  forward = (0, 0, +1).
# TSCN: Transform3D(−1, 0, 0, 0, 1, 0, 0, 0, −1, 0, 2, −8)
# Deliberately the exact mirror of CamSun (same height, same distance, yawed
# 180°). LG-1 asks a human whether they can tell which side gets more sun, and
# that judgement is only sound if the two frames differ in the plant rather than
# in composition. An earlier y=3.5, z=−10 placement put the camera at the tower's
# top height and 2 m further back, so the tower sat small and low in frame and
# the two views were not comparable.
var _CAM_SHADE_T := Transform3D(
		Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0, 2, -8))

# CamTop — 45° top-down from south.  forward = (0, −0.71, −0.71).
# TSCN: Transform3D(1, 0, 0, 0, 0.70711, 0.70711, 0, −0.70711, 0.70711, 0, 7.407, 5.657)
# basis.z = col2 = (c=0, f=0.70711, i=0.70711) = (0, 0.71, 0.71); forward = −basis.z ✓
var _CAM_TOP_T := Transform3D(
		Vector3(1, 0, 0),
		Vector3(0, 0.70711, -0.70711),
		Vector3(0, 0.70711, 0.70711),
		Vector3(0, 7.407, 5.657))

# CamSilhouette — ground-level silhouette, looks slightly UP.  forward = (0, +0.24, −0.97).
# TSCN: Transform3D(1, 0, 0, 0, 0.97014, −0.24254, 0, 0.24254, 0.97014, 0, 0.5, 8)
# basis.z = col2 = (c=0, f=−0.24254, i=0.97014); forward = (0, +0.24, −0.97) ✓
var _CAM_SILHOUETTE_T := Transform3D(
		Vector3(1, 0, 0),
		Vector3(0, 0.97014, 0.24254),
		Vector3(0, -0.24254, 0.97014),
		Vector3(0, 0.5, 8))

var _CAM_NAMES := ["CamSun", "CamShade", "CamTop", "CamSilhouette"]
var _CAM_TRANSFORMS: Array[Transform3D]


func before_all() -> void:
	_CAM_TRANSFORMS = [_CAM_SUN_T, _CAM_SHADE_T, _CAM_TOP_T, _CAM_SILHOUETTE_T]


# ─────────────────────────────────────────────────────────────────────────────
# Frustum helpers (pure arithmetic — no viewport required)
# ─────────────────────────────────────────────────────────────────────────────

## World-space forward direction for a camera from its Transform3D.
## Camera3D looks along local −Z; forward = −basis.z.
static func _cam_fwd(t: Transform3D) -> Vector3:
	return -t.basis.z


## Signed NDC-Y (−1 = bottom, +1 = top) of world point p as seen by camera t
## with vertical FOV fov_deg (keep-height).
## Returns INF when p is on or behind the camera's near plane (depth ≤ 0).
static func _ndc_y(t: Transform3D, p: Vector3, fov_deg: float) -> float:
	var rel := p - t.origin
	var fwd := _cam_fwd(t)
	var depth := fwd.dot(rel)
	if depth <= 0.0:
		return INF
	var up_comp := t.basis.y.dot(rel)
	return up_comp / (depth * tan(deg_to_rad(fov_deg * 0.5)))


# ─────────────────────────────────────────────────────────────────────────────
# CameraRig.select() compliance tests
# ─────────────────────────────────────────────────────────────────────────────

func _make_rig(count: int) -> Node:
	var rig := CameraRigScript.new()
	for i in range(count):
		var cam := Camera3D.new()
		cam.current = (i == 0)
		rig.add_child(cam)
	add_child_autofree(rig)
	return rig


func test_select_makes_only_nth_camera_current() -> void:
	var rig = _make_rig(4)
	rig.select(2)
	var cameras := rig.get_children()
	assert_false(cameras[0].current, "camera 0 must not be current after select(2)")
	assert_false(cameras[1].current, "camera 1 must not be current after select(2)")
	assert_true(cameras[2].current,  "camera 2 must be current after select(2)")
	assert_false(cameras[3].current, "camera 3 must not be current after select(2)")


func test_select_index_0_activates_first_camera() -> void:
	var rig = _make_rig(4)
	for cam in rig.get_children():
		cam.current = false
	rig.select(0)
	var cameras := rig.get_children()
	assert_true(cameras[0].current,  "camera 0 must be current after select(0)")
	assert_false(cameras[1].current, "camera 1 must not be current after select(0)")


func test_select_switches_from_one_camera_to_another() -> void:
	var rig = _make_rig(4)
	rig.select(1)
	rig.select(3)
	var cameras := rig.get_children()
	assert_false(cameras[1].current, "previously selected camera 1 must be deselected")
	assert_true(cameras[3].current,  "newly selected camera 3 must be current")


func test_select_does_not_modify_transforms() -> void:
	var rig = _make_rig(2)
	var cam0 := rig.get_child(0) as Camera3D
	var cam1 := rig.get_child(1) as Camera3D
	cam0.transform = Transform3D(Basis.IDENTITY, Vector3(0, 2, 8))
	cam1.transform = Transform3D(Basis.IDENTITY, Vector3(0, 2, -8))
	var t0_before := cam0.transform
	var t1_before := cam1.transform

	rig.select(0)
	rig.select(1)
	rig.select(0)

	assert_eq(cam0.transform, t0_before, "select() must not modify camera 0 transform")
	assert_eq(cam1.transform, t1_before, "select() must not modify camera 1 transform")


# ─────────────────────────────────────────────────────────────────────────────
# Frustum-visibility regression tests
# ─────────────────────────────────────────────────────────────────────────────

## Permanent regression proof — always passes in both states.
##
## Documents that two specific broken transforms (the ones that caused the
## W-CAM defects) fail the frustum checks.  Hard-coded inline so this test
## keeps working as a record even when the class-level constants are updated.
##
## broken_top — TSCN: Transform3D(1,0,0, 0,0.70711,−0.70711, 0,0.70711,0.70711, …)
##   basis.z = col2 = (0, −0.71, 0.71); forward = (0, +0.71, −0.71) → UP at sky.
##   Dot with direction to tower centre = 0  (camera plane tangent to tower).
##
## broken_sil — TSCN: Transform3D(1,0,0, 0,0.97014,0.24254, 0,−0.24254,0.97014, …)
##   basis.z = col2 = (0, 0.24, 0.97); forward = (0, −0.24, −0.97) → tilts DOWN.
##   Tower base projects above frame centre (ndc_y ≈ +0.241).
func test_broken_cam_transforms_fail_frustum_check() -> void:
	var tower_c    := Vector3(0.0, _TOWER_H * 0.5, 0.0)
	var tower_base := Vector3(0.0, 0.0, 0.0)

	# Broken CamTop: forward = (0, +0.71, −0.71) → looks UP at sky.
	# GDScript column form of TSCN(1,0,0, 0,0.70711,−0.70711, 0,0.70711,0.70711, …):
	#   basis.x=(1,0,0), basis.y=(0,0.70711,0.70711), basis.z=(0,−0.70711,0.70711)
	var broken_top := Transform3D(
			Vector3(1, 0, 0),
			Vector3(0, 0.70711,  0.70711),
			Vector3(0, -0.70711, 0.70711),
			Vector3(0, 7.407, 5.657))
	var dot := _cam_fwd(broken_top).dot(tower_c - broken_top.origin)
	assert_false(dot > 0.0,
			"broken CamTop: tower centre must NOT be in front (dot=%.4f, expected ≤ 0)" % dot)

	# Broken CamSilhouette: forward = (0, −0.24, −0.97) → tilts DOWN.
	# GDScript column form of TSCN(1,0,0, 0,0.97014,0.24254, 0,−0.24254,0.97014, …):
	#   basis.y=(0,0.97014,−0.24254), basis.z=(0,0.24254,0.97014)
	var broken_sil := Transform3D(
			Vector3(1, 0, 0),
			Vector3(0, 0.97014, -0.24254),
			Vector3(0, 0.24254,  0.97014),
			Vector3(0, 0.5, 8))
	var ny := _ndc_y(broken_sil, tower_base, _FOV_DEG)
	assert_true(ny > 0.0,
			"broken CamSilhouette: tower base must project ABOVE frame centre (ndc_y=%.3f, expected > 0)" % ny)


## Each canonical camera must have the tower centre strictly in front (depth > 0).
## Fails for CamTop when a broken transform makes forward point at the sky (dot ≤ 0).
func test_all_canonical_cameras_see_tower_centre() -> void:
	var tower_c := Vector3(0.0, _TOWER_H * 0.5, 0.0)
	for i in range(_CAM_TRANSFORMS.size()):
		var t: Transform3D = _CAM_TRANSFORMS[i]
		var dot := _cam_fwd(t).dot(tower_c - t.origin)
		assert_true(dot > 0.0,
				"%s: tower centre must be in front (dot=%.4f)" % [_CAM_NAMES[i], dot])


## Angular offset between each camera's look direction and the vector to the
## tower centre must be less than 30° — well inside the 75° vertical FOV.
func test_all_canonical_cameras_tower_centre_within_30_degrees() -> void:
	var tower_c := Vector3(0.0, _TOWER_H * 0.5, 0.0)
	for i in range(_CAM_TRANSFORMS.size()):
		var t: Transform3D = _CAM_TRANSFORMS[i]
		var fwd   := _cam_fwd(t)
		var to_tc := (tower_c - t.origin).normalized()
		var angle := rad_to_deg(acos(clampf(fwd.dot(to_tc), -1.0, 1.0)))
		assert_true(angle < 30.0,
				"%s: tower centre is %.1f° off-axis (max 30°)" % [_CAM_NAMES[i], angle])


## Tower base (y = 0) and top (y = TOWER_H) must both project within the vertical
## frame (|ndc_y| < 0.95) and span at least 20% of frame height.
## Returns INF when the camera points away from the tower (depth ≤ 0).
func test_all_canonical_cameras_tower_fits_vertically() -> void:
	var tower_base := Vector3(0.0, 0.0, 0.0)
	var tower_top  := Vector3(0.0, _TOWER_H, 0.0)
	for i in range(_CAM_TRANSFORMS.size()):
		var t: Transform3D = _CAM_TRANSFORMS[i]
		var ny_base := _ndc_y(t, tower_base, _FOV_DEG)
		var ny_top  := _ndc_y(t, tower_top,  _FOV_DEG)
		assert_true(absf(ny_base) < 0.95,
				"%s: tower base outside vertical frame (ndc_y=%.3f)" % [_CAM_NAMES[i], ny_base])
		assert_true(absf(ny_top) < 0.95,
				"%s: tower top outside vertical frame (ndc_y=%.3f)" % [_CAM_NAMES[i], ny_top])
		assert_true(absf(ny_top - ny_base) >= 0.20,
				"%s: tower spans only %.0f%% of frame height (min 20%%)" \
				% [_CAM_NAMES[i], absf(ny_top - ny_base) * 100.0])


## CamSilhouette is a ground-level shot; the camera must look slightly upward so
## the tower base falls in the lower half of the frame (ndc_y < 0).
## Fails for a broken transform where the camera tilts down (tower base above centre).
func test_cam_silhouette_tower_base_below_frame_centre() -> void:
	var ny := _ndc_y(_CAM_SILHOUETTE_T, Vector3(0.0, 0.0, 0.0), _FOV_DEG)
	assert_true(ny < 0.0,
			"CamSilhouette tower base must be below frame centre (ndc_y=%.3f)" % ny)
