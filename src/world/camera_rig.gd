class_name CameraRig
extends Node3D

const CameraBounds = preload("res://src/world/camera_bounds.gd")

var _lawn_bounds_active: bool = false
var _lawn_centre_xz: Vector2 = Vector2.ZERO
var _lawn_radius: float = 0.0
var _lawn_margin: float = CameraBounds.LAWN_EYE_MARGIN_M

## Four canonical Camera3Ds with authored transforms that are never written at runtime.
## select(index) only toggles `current` on the Camera3D children — AR-SCENE-3.
##
## Child order in main.tscn (enforced by authoring, never reshuffled):
##   0 = CamSun        — sun-facing (south) elevation
##   1 = CamShade      — shade-facing (north) elevation
##   2 = CamTop        — 45° from above (south aspect)
##   3 = CamSilhouette — ground-level silhouette (low south angle)
##
## AR-SCENE-3 invariant: this method writes ONLY the `current` flag.
## Transforms are authored constants; nothing may write them after scene load.
func set_lawn_camera_bounds(centre_xz: Vector2, lawn_radius: float, margin: float = -1.0) -> void:
	_lawn_centre_xz = centre_xz
	_lawn_radius = lawn_radius
	_lawn_margin = margin if margin >= 0.0 else CameraBounds.LAWN_EYE_MARGIN_M
	_lawn_bounds_active = lawn_radius > 0.0
	clamp_all_preset_eyes()


func clear_lawn_camera_bounds() -> void:
	_lawn_bounds_active = false


func clamp_preset_eye(index: int) -> void:
	if not _lawn_bounds_active:
		return
	var cameras := get_children()
	if index < 0 or index >= cameras.size():
		return
	var cam := cameras[index] as Camera3D
	if cam == null:
		return
	var clamped := CameraBounds.clamp_free_camera_eye(
		cam.global_position, _lawn_centre_xz, _lawn_radius, _lawn_margin)
	cam.global_position = clamped


func clamp_all_preset_eyes() -> void:
	var cameras := get_children()
	for i in range(cameras.size()):
		clamp_preset_eye(i)


func select(index: int) -> void:
	var cameras := get_children()
	for i in range(cameras.size()):
		var cam := cameras[i] as Camera3D
		if cam != null:
			cam.current = (i == index)
	clamp_preset_eye(index)
