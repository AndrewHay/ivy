class_name LeafPlacer
extends RefCounted

const AtlasScript = preload("res://src/render/leaf_atlas.gd")


## Advance leaf placement for a single growth step.
##
## l_dir — the bounded accumulated-light gradient direction (SD-LEAF-4 rule 5).
## Computed in GrowthStep as `grad_l / (grad_l.length() + light_gradient_scale)`.
## Must come from accumulated light (never the instantaneous sun — INV-3a).
## Defaults to Vector3.ZERO when the gradient is unavailable (flat leaves on n_wall).
static func advance(
	tip: Tip,
	ctx: SimContext,
	seg_a: Vector3,
	seg_b: Vector3,
	f_l: float,
	basis: Basis,
	l_dir: Vector3 = Vector3.ZERO
) -> void:
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

	# ── SD-LEAF-6: atlas health-tier selection (W-060) ─────────────────────────
	# Hash channels (SD-RNG-6): tier=43, variant=44, variant-redraw=45.
	# Node draw order: internode(99) → suppression(42) → tier(43) → variant(44) → redraw(45).
	# All draws are hash-based — no stream draw consumed (INV-7).
	var healthy_prob := params.leaf_healthy_base + params.leaf_healthy_gain * f_l
	var u_tier := Hash64.unit_float(tip.id, tip.node_count, 43)
	var tier := "H" if u_tier < healthy_prob else "W"
	var tier_ids := atlas.ids_in_tier(tier)
	var i_var := clampi(int(floor(Hash64.unit_float(tip.id, tip.node_count, 44) * 3.0)), 0, 2)
	var chosen_id := tier_ids[i_var]
	# Adjacency rule: no reuse of either of the two preceding nodes on this stem.
	var forbidden := PackedStringArray()
	if tip.prev_leaf_id != "":
		forbidden.append(tip.prev_leaf_id)
	if tip.last_leaf_id != "":
		forbidden.append(tip.last_leaf_id)
	if chosen_id in forbidden:
		var i2 := clampi(int(floor(Hash64.unit_float(tip.id, tip.node_count, 45) * 3.0)), 0, 2)
		chosen_id = tier_ids[i2]
		if chosen_id in forbidden:
			# Deterministic terminating fallback: first id in tier order that is not forbidden.
			# Always succeeds — 3 ids in the tier, at most 2 forbidden.
			for candidate: String in tier_ids:
				if not (candidate in forbidden):
					chosen_id = candidate
					break
	tip.prev_leaf_id = tip.last_leaf_id
	tip.last_leaf_id = chosen_id
	var leaf_id := chosen_id

	var aspect := atlas.aspect_for(leaf_id)

	# ── SD-LEAF-5 s_light only (W-060) ─────────────────────────────────────────
	# w = leaf_width_base * s_light, frozen at node creation.
	# M2.5 scope: s_light only; s_order, s_age, s_var deferred to M4 / W-030.
	var s_light := params.leaf_light_scale_base + params.leaf_light_scale_gain * f_l
	var width := params.leaf_width_base * s_light
	var height := width / aspect

	var n_wall := tip.last_contact_normal
	var t_dir := (seg_b - seg_a).normalized()

	# ── SD-LEAF-4 rule 5: phototropic cant (W-060) ──────────────────────────────
	# n_leaf = normalize(n_wall + leaf_photo_cant · L̂).
	# l_dir == Vector3.ZERO when the light gradient is flat (uniform patch, SD-EDGE-12);
	# in that case n_leaf == n_wall and the leaf lies flush on the wall — acceptable.
	# l_dir must come from accumulated light, never the instantaneous sun (INV-3a).
	var n_leaf_raw := n_wall + params.leaf_photo_cant * l_dir
	var n_leaf := n_wall  # fallback: flat on wall
	if n_leaf_raw.length_squared() > 1e-6:
		n_leaf = n_leaf_raw.normalized()

	# SD-LEAF-3: golden-angle phyllotaxy blended toward the nearest "flat" azimuth
	# (perpendicular to the stem direction, i.e. left/right along the wall).
	# A pure 137.5° pinwheel reads as a bottle-brush; pure ±90° reads as a fern.
	# The 65% blend toward flat gives left/right splay while the golden-angle residual
	# supplies the irregularity that defeats rubric criterion 6.
	var phi: float = float(tip.node_count - 1) * deg_to_rad(params.phyllotaxy_divergence)
	var phi_flat: float = round((phi - PI * 0.5) / PI) * PI + PI * 0.5
	var psi: float = lerpf(phi, phi_flat, params.phyllotaxy_flatten)
	var p_dir := (t_dir.rotated(n_wall, psi) + n_wall * params.leaf_out_of_plane).normalized()

	# Normal-offset ladder (SD-LEAF-4 rule 8): push the card off the wall so the mat
	# has thickness. Two positions are tracked:
	#  - deposit_pos: offset along n_wall (unchanged from M2 baseline — crowding is simulation)
	#  - node_pos:    offset along n_leaf (presentation: the rendered card tilts with the cant)
	var offset := params.leaf_offset_base + params.leaf_offset_step * float((tip.node_count - 1) % params.leaf_offset_ladder)
	var deposit_pos := node_pos + n_wall * offset  # stable simulation position
	node_pos += n_leaf * offset                    # presentation position

	# Re-orthonormalise the card basis about n_leaf, preserving the petiole/up direction (p_dir).
	var x_axis := n_leaf.cross(p_dir).normalized()
	if x_axis.length_squared() < 1e-6:
		x_axis = basis.x
	var y_axis := p_dir
	var z_axis := x_axis.cross(y_axis).normalized()

	var xform := Transform3D(Basis(x_axis * width, y_axis * height, z_axis), node_pos)
	var rect := atlas.rect_for(leaf_id)
	var alpha_fill := atlas.alpha_fill_for(leaf_id)
	# Rendered leaf area — includes s_light; retained for render/LG-2 consumers.
	var rendered_area := alpha_fill * width * height

	# ── SD-LEAF-7 M2.5 tint (W-060) ────────────────────────────────────────────
	# color = lerp(leaf_shade_tint, leaf_sun_tint, f_L).
	# Value jitter and age lightening are deferred to M4 (SD-RNG-6 reserves channel 46
	# for value jitter when it lands).
	var tint := params.leaf_shade_tint.lerp(params.leaf_sun_tint, f_l)

	# SD-LEAF-8 / SD-PHYS-3: physiology deposits crowding for this leaf node (INV-1: sole writer).
	# The deposit uses the M2-baseline canonical area (leaf "a", no s_light) at the
	# M2-baseline deposit_pos (n_wall offset) so that appearance-layer changes
	# (tier selection, s_light, phototropic cant) do not perturb the crowding field.
	# "Leaf appearance is presentation; leaf placement is simulation." (W-060 constraints)
	if ctx.env != null:
		var deposit_area := atlas.alpha_fill_for("a") * params.leaf_width_base \
			* (params.leaf_width_base / atlas.aspect_for("a"))
		Physiology.deposit_leaf_crowding(deposit_pos, deposit_area, ctx)
	# Pass f_l as leaf_light (AR-METRIC-2). No RNG draw consumed — f_l is an existing input (INV-7).
	ctx.plant.append_leaf(xform, tint, rect, tip.id, tip.shoot_length, rendered_area, f_l)
