class_name OverhangSdf
extends RefCounted

## Analytic signed-distance field for the eave-wall fixture (ivy-9us).
##
## Union of two axis-aligned boxes — min(wall_sdf, slab_sdf) — exact outside the
## union.  Conforms to the SurfaceQuery backend interface (signed_distance, bounds,
## bake_identity, gradient, gradient_normalized).
##
## Surface-query backend_tag: SurfaceQuery.setup() calls backend_hint() to get "WallSdf"
## so that growth_step.gd keeps upward_base OFF and project_to_shell stays on the
## analytic path (not the TowerSdf opening-snap path).

var spec  # OverhangSpec


func _init(s) -> void:
	spec = s


## SurfaceQuery.setup() checks backend_hint() when the script is not WallSdf/MeshSdf.
## Return "WallSdf" so OverhangSdf is treated identically to the plain-wall backend.
func backend_hint() -> String:
	return "WallSdf"


# ── Geometry helpers ───────────────────────────────────────────────────────────

## Centre of the wall box.
func _wall_center() -> Vector3:
	return Vector3(0.0, spec.wall_height * 0.5, -spec.wall_thickness * 0.5)

## Half-extents of the wall box.
func _wall_half() -> Vector3:
	return Vector3(spec.wall_length * 0.5, spec.wall_height * 0.5, spec.wall_thickness * 0.5)

## Centre of the slab box.
##   y: [wall_height, wall_height + slab_thickness]
##   z: [-wall_thickness, slab_projection]
func _slab_center() -> Vector3:
	var cy: float = spec.wall_height + spec.slab_thickness * 0.5
	var cz: float = (spec.slab_projection - spec.wall_thickness) * 0.5
	return Vector3(0.0, cy, cz)

## Half-extents of the slab box.
func _slab_half() -> Vector3:
	return Vector3(
		spec.wall_length * 0.5,
		spec.slab_thickness * 0.5,
		(spec.slab_projection + spec.wall_thickness) * 0.5
	)


# ── Box SDF (unsigned / signed) ───────────────────────────────────────────────

static func _box_sdf(p: Vector3, center: Vector3, half: Vector3) -> float:
	var q := (p - center).abs() - half
	var outside := q.max(Vector3.ZERO).length()
	var inside := minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
	return outside + inside


# ── Public interface ──────────────────────────────────────────────────────────

func signed_distance(p: Vector3) -> float:
	var d_wall := _box_sdf(p, _wall_center(), _wall_half())
	var d_slab := _box_sdf(p, _slab_center(), _slab_half())
	return minf(d_wall, d_slab)


func bounds() -> AABB:
	var hl: float = spec.wall_length * 0.5
	# x: [-hl, hl], y: [0, wall_height + slab_thickness], z: [-wall_thickness, slab_projection]
	return AABB(
		Vector3(-hl, 0.0, -spec.wall_thickness),
		Vector3(spec.wall_length, spec.wall_height + spec.slab_thickness,
			spec.wall_thickness + spec.slab_projection)
	)


## Cache identity for LightBakeCache (ivy-9xp).
## Uses SpecHash so any change to OverhangSpec's exported fields invalidates cached bakes.
func bake_identity() -> PackedByteArray:
	return SpecHash.of("OverhangSdf", spec)


func gradient(p: Vector3) -> Vector3:
	const EPS := 0.001
	return Vector3(
		signed_distance(p + Vector3(EPS, 0, 0)) - signed_distance(p - Vector3(EPS, 0, 0)),
		signed_distance(p + Vector3(0, EPS, 0)) - signed_distance(p - Vector3(0, EPS, 0)),
		signed_distance(p + Vector3(0, 0, EPS)) - signed_distance(p - Vector3(0, 0, EPS))
	) / (2.0 * EPS)


func gradient_normalized(p: Vector3) -> Vector3:
	var g := gradient(p)
	if g.length_squared() < 1e-10:
		return Conv.UP
	return g.normalized()
