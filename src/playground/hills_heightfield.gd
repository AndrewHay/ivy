class_name HillsHeightfield
extends RefCounted

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsFogTint = preload("res://src/playground/hills_fog_tint.gd")
const HillsNoise = preload("res://src/playground/hills_noise.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

const W_MAX := 1.45
## Lift applied to every hill mesh vertex so the hills shader always renders above
## World/Ground (y = 0).  Without this, the flat inner zone (rise_gate = 0) sits
## at y = LAWN_GROUND_Y_OFFSET (–0.03) and the pale world_ground slab shows through.
## 5 cm is invisible at play distance but definitively wins the depth test.
const TERRAIN_BASE_LIFT := 0.05
## Gap between lawn_radius and the inner hill rise start (2× old gap of 2 m → 4 m).
const NEAR_RISE_START_EXTRA_M := 4.0
## Radius at which the near-rise gate reaches 1.0 (shifted +2 m with r_inner).
const NEAR_RISE_FULL_M := 86.0


static func terrain_seed(layout: VillageLayout, params: HillsParams) -> int:
	var norm := layout.generation_seed if layout.generation_seed > 0 else params.layout_seed
	return VillageLayout._derive(norm, VillageLayout.HILLS_TERRAIN_SALT)


static func forest_lcg_seed(layout: VillageLayout, params: HillsParams) -> int:
	if params.lcg_seed >= 0:
		return params.lcg_seed
	var norm := layout.generation_seed if layout.generation_seed > 0 else params.layout_seed
	return VillageLayout._derive(norm, VillageLayout.HILLS_FOREST_SALT)


## Signed shortest-path difference b − a, wrapped to (−PI, PI].
static func _angle_difference(a: float, b: float) -> float:
	var diff := fmod(b - a, TAU)
	if diff > PI:
		diff -= TAU
	elif diff < -PI:
		diff += TAU
	return diff


## Returns [0, 1] weight for the azimuth wedge at xz relative to hamlet centre g.
## 1.0 inside the wedge, 0.0 outside, smooth taper over azimuth_fade_width_deg.
## Convention: azimuth_centre_deg 0 = north = −Z, 90 = east = +X (matches project compass).
static func azimuth_weight(xz: Vector2, g: Vector2, params: HillsParams) -> float:
	if params.azimuth_half_width_deg >= 180.0:
		return 1.0
	var dx := xz.x - g.x
	var dz := xz.y - g.y
	if dx * dx + dz * dz < 0.01:
		return 1.0
	# phi = atan2(dx, dz): phi=0 → +Z (south), phi=PI → −Z (north).
	var phi := atan2(dx, dz)
	# Convert compass azimuth (0=north, 90=east) to phi.
	# azimuth 0° (north) → phi=PI; azimuth 90° (east) → phi=PI/2.
	var north_phi := PI - deg_to_rad(params.azimuth_centre_deg)
	var diff := absf(_angle_difference(phi, north_phi))
	var hw := deg_to_rad(params.azimuth_half_width_deg)
	var fw := maxf(deg_to_rad(params.azimuth_fade_width_deg), 0.001)
	var inner_edge := maxf(hw - fw, 0.0)
	if diff <= inner_edge:
		return 1.0
	if diff >= hw:
		return 0.0
	return 1.0 - smoothstep(inner_edge, hw, diff)


static func sample_y(xz: Vector2, layout: VillageLayout, params: HillsParams, t_seed: int) -> float:
	var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	if not layout.is_generated and params.variant == 0:
		params = params.duplicate_params()
		params.variant = 1
	if params.variant == 1:
		return _sample_y_flat_legacy(xz, layout, y_lawn)
	var g := layout.hamlet_centre_xz
	var r := xz.distance_to(g)
	if r > params.r_outer_m:
		return y_lawn
	if r < layout.lawn_radius:
		return y_lawn
	var h_core := _h_core(xz, r, layout, params, t_seed)
	# Apply north-only azimuth wedge: smoothly zero h_core outside the wedge.
	h_core *= azimuth_weight(xz, g, params)
	if r < params.r_inner_m:
		var t := clampf((r - layout.lawn_radius) / maxf(params.toe_width_m, 0.01), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		var h := lerpf(y_lawn, y_lawn + h_core, t)
		if r <= layout.lawn_radius + 0.05:
			h = minf(h, y_lawn + params.toe_max_lift_m)
		return h
	return y_lawn + h_core


static func sample_slope_deg(
		xz: Vector2, layout: VillageLayout, params: HillsParams, t_seed: int, eps_m := 0.4) -> float:
	var y0 := sample_y(xz, layout, params, t_seed)
	var yx := sample_y(xz + Vector2(eps_m, 0.0), layout, params, t_seed)
	var yz := sample_y(xz + Vector2(0.0, eps_m), layout, params, t_seed)
	var dx := (yx - y0) / eps_m
	var dz := (yz - y0) / eps_m
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))


static func build_mesh(layout: VillageLayout, params: HillsParams) -> ArrayMesh:
	if params.variant == 1 or (not layout.is_generated):
		return build_flat_legacy_mesh(layout, params)
	return _build_cartesian_annulus(layout, params)


static func _build_cartesian_annulus(layout: VillageLayout, params: HillsParams) -> ArrayMesh:
	var g := layout.hamlet_centre_xz
	var t_seed := terrain_seed(layout, params)
	var outer := params.r_outer_m
	# Skirt slightly inside the lawn disc so fog-free meadow shader covers the World/Ground seam.
	var inner := maxf(layout.lawn_radius - 6.0, layout.lawn_radius * 0.88)
	# Compute step directly from the annulus area to stay within 24k triangle budget.
	# area of bounding square = (2*outer)^2; each step×step cell = 2 triangles.
	# Solve: 2 * (2*outer/step)^2 <= 20000 → step >= sqrt(8*outer^2/20000) = outer*sqrt(0.4)/100
	var annulus_area := PI * (outer * outer - inner * inner)
	var step := maxf(sqrt(2.0 * annulus_area / 20000.0), 2.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_cartesian_quads(st, layout, params, t_seed, g, inner, outer, step)
	return st.commit()


static func _append_cartesian_quads(
		st: SurfaceTool, layout: VillageLayout, params: HillsParams, t_seed: int,
		g: Vector2, inner: float, outer: float, step: float) -> int:
	var tris := 0
	var x0 := g.x - outer
	var z0 := g.y - outer
	var cols := int(ceil((2.0 * outer) / step))
	for iz in range(cols):
		for ix in range(cols):
			var ax0 := x0 + float(ix) * step
			var az0 := z0 + float(iz) * step
			var ax1 := ax0 + step
			var az1 := az0 + step
			var corners: Array[Vector2] = [
				Vector2(ax0, az0), Vector2(ax1, az0), Vector2(ax1, az1), Vector2(ax0, az1),
			]
			var inside := 0
			for p: Vector2 in corners:
				var r := p.distance_to(g)
				if r >= inner and r <= outer:
					inside += 1
			if inside < 2:
				continue
			if tris + 2 > 24000:
				return tris
			var tri_list := [[0, 1, 2], [0, 2, 3]]
			for tri in tri_list:
				for idx: int in tri:
					var p2: Vector2 = corners[idx]
					var y := sample_y(p2, layout, params, t_seed) + TERRAIN_BASE_LIFT
					var n := _vertex_normal(p2, layout, params, t_seed)
					st.set_normal(n)
					st.set_color(Color(1, 1, 1, 1))
					st.add_vertex(Vector3(p2.x, y, p2.y))
				tris += 1
	return tris


static func build_flat_legacy_mesh(layout: VillageLayout, params: HillsParams) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 64
	var c := layout.hamlet_centre_xz if layout.is_generated else Vector2.ZERO
	var inner_r := layout.hill_inner if not layout.is_generated else params.r_inner_m
	var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	_annulus_ramp(st, segs, inner_r, 140.0, y_lawn, y_lawn + 7.5, c)
	st.generate_normals()
	return st.commit()


static func _sample_y_flat_legacy(xz: Vector2, layout: VillageLayout, y_lawn: float) -> float:
	var c := layout.hamlet_centre_xz if layout.is_generated else Vector2.ZERO
	var inner_r := layout.hill_inner if not layout.is_generated else 58.0
	var r := xz.distance_to(c)
	if r < inner_r:
		return y_lawn
	if r > 140.0:
		return y_lawn
	var t := (r - inner_r) / maxf(140.0 - inner_r, 0.01)
	return lerpf(y_lawn, y_lawn + 7.5, t)


static func _polar(g: Vector2, r: float, a: float) -> Vector2:
	return g + Vector2(sin(a) * r, cos(a) * r)


static func _vertex_normal(
		p: Vector2, layout: VillageLayout, params: HillsParams, t_seed: int, eps_m := 0.35
) -> Vector3:
	var yx := sample_y(p + Vector2(eps_m, 0.0), layout, params, t_seed)
	var yxm := sample_y(p - Vector2(eps_m, 0.0), layout, params, t_seed)
	var yz := sample_y(p + Vector2(0.0, eps_m), layout, params, t_seed)
	var yzm := sample_y(p - Vector2(0.0, eps_m), layout, params, t_seed)
	var dx := (yx - yxm) / maxf(2.0 * eps_m, 0.01)
	var dz := (yz - yzm) / maxf(2.0 * eps_m, 0.01)
	if not is_finite(dx) or not is_finite(dz):
		return Vector3.UP
	var n := Vector3(-dx, 1.0, -dz)
	if n.length_squared() < 1e-12:
		return Vector3.UP
	return n.normalized()


static func _h_core(
		xz: Vector2, r: float, layout: VillageLayout, params: HillsParams, t_seed: int) -> float:
	var rise_lo := layout.lawn_radius + NEAR_RISE_START_EXTRA_M
	var rise_gate := smoothstep(rise_lo, NEAR_RISE_FULL_M, r)
	var n01 := HillsNoise.fbm_height_01(
		xz, t_seed, params.base_feature_m, params.noise_octaves,
		params.noise_persistence, params.warp_strength)
	var layer_gain := _radial_layer_gain(r, params)
	var u := (r - params.r_inner_m) / maxf(params.r_outer_m - params.r_inner_m, 0.01)
	var fade_out := 1.0 - pow(clampf(u, 0.0, 1.0), params.radial_bias_power)
	var h := n01 * params.height_scale_m * layer_gain * fade_out * rise_gate
	var bump := HillsNoise.fbm_height_01(
		xz * 0.55 + Vector2(40.0, -17.0), t_seed + 9001, params.base_feature_m * 0.65,
		2, params.noise_persistence * 0.85, params.warp_strength * 0.5)
	h += (bump - 0.45) * params.height_scale_m * 0.22 * layer_gain * rise_gate
	return maxf(h, 0.0)


static func _radial_layer_gain(r: float, params: HillsParams) -> float:
	var gain := 0.0
	for i in range(params.layer_count):
		var centre := params.layer_dist_at(i)
		var width := params.layer_width_at(i)
		var amp := params.layer_amp_scale_at(i)
		var d := (r - centre) / maxf(width, 0.01)
		gain += amp * exp(-0.5 * d * d)
	return clampf(gain, 0.12, 1.35)


static func _annulus_ramp(
		st: SurfaceTool, segs: int, inner_r: float, outer_r: float, inner_y: float, outer_y: float,
		centre_xz: Vector2) -> void:
	for i in range(segs):
		var a0 := (float(i) / segs) * TAU
		var a1 := (float(i + 1) / segs) * TAU
		var v0 := Vector3(
			centre_xz.x + cos(a0) * inner_r, inner_y, centre_xz.y + sin(a0) * inner_r)
		var v1 := Vector3(
			centre_xz.x + cos(a1) * inner_r, inner_y, centre_xz.y + sin(a1) * inner_r)
		var v2 := Vector3(
			centre_xz.x + cos(a0) * outer_r, outer_y, centre_xz.y + sin(a0) * outer_r)
		var v3 := Vector3(
			centre_xz.x + cos(a1) * outer_r, outer_y, centre_xz.y + sin(a1) * outer_r)
		st.add_vertex(v0)
		st.add_vertex(v2)
		st.add_vertex(v1)
		st.add_vertex(v1)
		st.add_vertex(v2)
		st.add_vertex(v3)
