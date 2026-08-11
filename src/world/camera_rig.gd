class_name CameraRig
extends Node3D

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
func select(index: int) -> void:
	var cameras := get_children()
	for i in range(cameras.size()):
		var cam := cameras[i] as Camera3D
		if cam != null:
			cam.current = (i == index)
