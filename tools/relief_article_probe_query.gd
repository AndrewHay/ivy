extends SurfaceQuery

## SurfaceQuery that counts how many nearest() calls come back unrefined (no collision hit, so the
## trilinear SDF answer stands). Measurement only, for the relief-article probe (ivy-b1e.6,
## AR-MESH-20.5): behaviour is the parent's, call for call.

var nearest_total := 0
var nearest_unrefined := 0


func nearest(p: Vector3) -> Hit:
	var h := super.nearest(p)
	nearest_total += 1
	if not h.refined:
		nearest_unrefined += 1
	return h


func reset_counts() -> void:
	nearest_total = 0
	nearest_unrefined = 0
