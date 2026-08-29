class_name SeedAnchors
extends RefCounted

## SD-AGENCY-1/2/3 — derive four compass seed anchors once at load.

class Anchor:
	var compass: int = 0  # 0=N 1=E 2=S 3=W
	var available: bool = false
	var position: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP


const PROBE_Y := 0.05
const RAY_MARGIN := 0.5
const SEED_OFFSET := 0.01

const AZIMUTH_OFFSETS_DEG: Array[float] = [
	0.0, 5.0, -5.0, 10.0, -10.0, 15.0, -15.0, 20.0, -20.0, 25.0, -25.0,
]


var _anchors: Array[Anchor] = []
var _built: bool = false


func build(surface: SurfaceQuery, spec: TowerSpec) -> void:
	assert(not _built, "SeedAnchors: recomputation mid-run is forbidden (SD-AGENCY-3)")
	_built = true
	_anchors.clear()
	var radius := spec.radius_outer
	for compass in 4:
		_anchors.append(_derive_anchor(surface, radius, compass))


func get_anchors() -> Array[Anchor]:
	assert(_built, "SeedAnchors: build() must run before get_anchors()")
	return _anchors


static func compass_label(compass: int) -> String:
	match compass:
		0: return "N"
		1: return "E"
		2: return "S"
		3: return "W"
		_: return "?"


static func _outward_dir(compass: int, offset_deg: float) -> Vector3:
	var az_deg := float(compass) * 90.0 + offset_deg
	var rad := deg_to_rad(az_deg)
	return Vector3(sin(rad), 0.0, -cos(rad)).normalized()


func _derive_anchor(surface: SurfaceQuery, radius: float, compass: int) -> Anchor:
	var anchor := Anchor.new()
	anchor.compass = compass
	for offset_deg in AZIMUTH_OFFSETS_DEG:
		var outward := _outward_dir(compass, offset_deg)
		var origin := outward * (radius + RAY_MARGIN)
		origin.y = PROBE_Y
		var hit := surface.raycast(origin, Vector3(0.0, PROBE_Y, 0.0))
		if hit.hit and _is_wall_material(hit.material_id):
			anchor.available = true
			anchor.normal = hit.normal
			anchor.position = hit.position + hit.normal * SEED_OFFSET
			return anchor
	anchor.available = false
	return anchor


static func _is_wall_material(material_id: int) -> bool:
	return material_id != MaterialRegistry.OPENING_REVEAL \
		and material_id != MaterialRegistry.INTERIOR
