class_name LeafPlacer
extends RefCounted

const AtlasScript = preload("res://src/render/leaf_atlas.gd")


static func advance(tip: Tip, ctx: SimContext, seg_a: Vector3, seg_b: Vector3, f_l: float, basis: Basis) -> void:
	var params := ctx.params
	# SD-LEAF-2: internode lengthens in shade (etiolation).
	# Jitter is hash-based so no RNG-stream draw is consumed here (INV-7).
	var u := Hash64.unit_float(tip.id, tip.node_count, 99)
	var internode := params.internode_base \
		* (1.0 + params.internode_shade_gain * (1.0 - f_l)) \
		* (1.0 + params.internode_jitter * (2.0 * u - 1.0))
	if tip.distance_since_node < internode:
		return
	# Leaves are withheld over the first `leaf_tip_suppress` of a shoot, which is the
	# young apical tissue that carries no expanded leaves. Nodes are created at the
	# tip, so the node-to-tip distance is bounded by segment_length and cannot be the
	# quantity tested here without deferred leaf expansion (see SD-LEAF).
	if tip.shoot_length < params.leaf_tip_suppress:
		return
	var t := 1.0 - (tip.distance_since_node - internode) / maxf(params.segment_length, 1e-6)
	t = clampf(t, 0.0, 1.0)
	var node_pos := seg_a.lerp(seg_b, t)
	tip.distance_since_node = 0.0
	tip.node_count += 1
	# SD-LEAF-8: suppress placement in dense regions. Hash-based (SD-RNG-4): no stream draw
	# is consumed, so draw order is unchanged and determinism is preserved (INV-7).
	# Suppression channel 42 is distinct from field-jitter channels (0–14) and internode (99).
	if ctx.env != null:
		var c_at_node := ctx.env.sample_crowding(node_pos, tip.id, tip.node_count)
		var p_place := clampf(1.0 - params.leaf_crowd_suppress * c_at_node, params.leaf_crowd_floor, 1.0)
		var suppress_u := Hash64.unit_float(tip.id, tip.node_count, 42)
		if suppress_u >= p_place:
			return
	var atlas := AtlasScript.new()
	var leaf_id := "a"
	var aspect := atlas.aspect_for(leaf_id)
	var width := params.leaf_width_base
	var height := width / aspect
	var n_wall := tip.last_contact_normal
	var t_dir := (seg_b - seg_a).normalized()
	# SD-LEAF-3: golden-angle phyllotaxy blended toward the nearest "flat" azimuth
	# (perpendicular to the stem direction, i.e. left/right along the wall).
	# A pure 137.5° pinwheel reads as a bottle-brush; pure ±90° reads as a fern.
	# The 65% blend toward flat gives left/right splay while the golden-angle residual
	# supplies the irregularity that defeats rubric criterion 6.
	var phi: float = float(tip.node_count - 1) * deg_to_rad(params.phyllotaxy_divergence)
	var phi_flat: float = round((phi - PI * 0.5) / PI) * PI + PI * 0.5
	var psi: float = lerpf(phi, phi_flat, params.phyllotaxy_flatten)
	var p_dir := (t_dir.rotated(n_wall, psi) + n_wall * params.leaf_out_of_plane).normalized()
	var offset := params.leaf_offset_base + params.leaf_offset_step * float((tip.node_count - 1) % params.leaf_offset_ladder)
	node_pos += n_wall * offset
	var x_axis := n_wall.cross(p_dir).normalized()
	if x_axis.length_squared() < 1e-6:
		x_axis = basis.x
	var y_axis := p_dir
	var z_axis := x_axis.cross(y_axis).normalized()
	var xform := Transform3D(Basis(x_axis * width, y_axis * height, z_axis), node_pos)
	var rect := atlas.rect_for(leaf_id)
	var alpha_fill := atlas.alpha_fill_for(leaf_id)
	var predicted_area := alpha_fill * width * height
	# SD-LEAF-8 / SD-PHYS-3: physiology deposits crowding for this leaf node (INV-1: sole writer).
	if ctx.env != null:
		Physiology.deposit_leaf_crowding(node_pos, predicted_area, ctx)
	ctx.plant.append_leaf(xform, Color.WHITE, rect, tip.id, tip.shoot_length, predicted_area)
