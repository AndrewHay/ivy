class_name GrowthStep
extends RefCounted

const COLLISION_SKIN := 1e-3

static func apply_direction_memory(prev: Vector3, d_actual: Vector3, memory: float) -> Vector3:
	var blended := prev * memory + d_actual * (1.0 - memory)
	if blended.length_squared() < 1e-8:
		return prev
	return blended.normalized()


## T1 soffit redirect heading: the incoming heading's in-plane part plus an outward bias, so
## stems keep their sideways wander along the soffit instead of snapping onto the wall normal.
static func soffit_glide_dir(heading: Vector3, n: Vector3, out_dir: Vector3, outward_bias: float) -> Vector3:
	var out_t := out_dir - out_dir.dot(n) * n
	if out_t.length_squared() < 1e-8:
		out_t = out_dir
	out_t = out_t.normalized()
	var g := heading - heading.dot(n) * n
	if g.length_squared() > 1e-8:
		g = g.normalized()
	g += outward_bias * out_t
	if g.length_squared() < 1e-8 or g.dot(out_t) <= 0.0:
		return out_t
	return g.normalized()


static func step_tip(tip: Tip, ctx: SimContext) -> void:
	var params := ctx.params
	var traverse := params.eave_traversal_enabled and ctx.surface.backend_tag() == "WallSdf"
	# 1. correlated random
	var xi := tip.stream.rand_unit_vector()
	tip.random_dir = (tip.random_dir * (1.0 - params.random_new_mix) + xi * params.random_new_mix).normalized()
	# 2. adhesion
	var near := ctx.surface.nearest(tip.position)
	var d := near.distance
	var q := near.position
	var a_vec := Vector3.ZERO
	if d >= 1e-5:
		var falloff := maxf(0.0, 1.0 - d / params.adhesion_range)
		var a_m := ctx.surface.adhesion_suitability(near.material_id)
		a_vec = a_m * falloff * (q - tip.position) / d
	# T1/T2 state: capture the outward-horizontal wall normal while the tip is on a vertical
	# face. Used as the 'toward the eave lip' direction during soffit redirect and glide bias.
	if traverse:
		var contact_dist_now := ctx.surface.effective_contact(params.contact_distance)
		if d <= contact_dist_now and absf(near.normal.y) < 0.5:
			var h_out := Vector3(near.normal.x, 0.0, near.normal.z)
			if h_out.length_squared() > 1e-8:
				tip.climb_outward = h_out.normalized()
	# 3. gradients
	var basis := ctx.surface.tangent_basis_at(tip.position)
	var d_l := ctx.env.sample_D_L(tip.position, tip.id, tip.segment_count)
	var f_l := Physiology.f_L(d_l, params)
	var h := Physiology.H(d_l, params)
	var grad_l := ctx.env.grad_S_D_L(tip.position, basis, tip.id, tip.segment_count)
	var grad_c := ctx.env.grad_S_crowding(tip.position, basis, tip.id, tip.segment_count)
	var l_dir := grad_l / (grad_l.length() + params.light_gradient_scale)
	var c_dir := grad_c / (grad_c.length() + params.crowding_gradient_scale)
	var w_p := Physiology.w_P(h, params)
	var w_r := Physiology.w_R(h, params)
	var w_l := Physiology.w_L(f_l, params)
	var w_c := Physiology.w_C(h, params)
	var w_g := Physiology.w_G(tip.floating_length, params)
	var u := w_p * tip.direction + w_r * tip.random_dir + params.adhesion_base * a_vec
	u += w_l * l_dir - w_c * c_dir + w_g * Conv.GRAVITY
	# SD-CONV-6 gravitropism is for mesh-backed scenarios (M2.6 quoin reach). On the
	# analytic cylinder it steers tips vertical too aggressively and collapses AS-1
	# bucket coverage (ivy-bax); stall skip is already mesh-only for the same reason.
	if tip.floating_length == 0.0 and ctx.surface.backend_tag() == "MeshSdf":
		u += params.upward_base * Conv.UP
	# T2: traverse-scoped up bias and soffit glide (ivy-dsh). Only active while traverse is
	# true AND traverse_ticks > 0, so the boost is bounded to the eave region and does not
	# affect general wall-climbing stems.
	if traverse:
		var contact_thresh_t2 := ctx.surface.effective_contact(params.contact_distance)
		var on_soffit := d <= contact_thresh_t2 and near.normal.y < -0.5
		var on_roof := d <= contact_thresh_t2 and near.normal.y > 0.5
		# Early trigger (ivy-dsh.9): arm the traverse window when a soffit is close
		# straight above, so the final shadow-band approach is boosted (T5 floor) even
		# before the tip contacts the soffit. One short upward raycast per live tip-step
		# on the overhang path; no RNG; does not fire when approach_reach == 0.
		if not on_soffit and params.eave_approach_reach > 0.0:
			var up_hit := ctx.surface.raycast(
				tip.position,
				tip.position + Conv.UP * params.eave_approach_reach
			)
			if up_hit.hit and up_hit.normal.y < -0.5:
				tip.traverse_ticks = params.eave_traverse_window
		if on_soffit:
			tip.traverse_ticks = params.eave_traverse_window
		elif on_roof:
			tip.traverse_ticks = 0  # traverse done; disable up bias on the roof
		if tip.traverse_ticks > 0:
			u += params.eave_up_bias * Conv.UP
		if on_soffit and tip.climb_outward != Vector3.ZERO:
			u += params.eave_soffit_glide * tip.climb_outward
	var d_dir := u
	if u.length_squared() < 1e-8:
		d_dir = tip.direction
	else:
		d_dir = u.normalized()
	var x_trial := tip.position + d_dir * params.segment_length
	# Ground clamp runs before each collision ray: walls have open bases, so a leg that dips
	# below ground passes under the face and a later clamp would lift it up inside the wall.
	var grounded := false
	if x_trial.y < params.ground_y_min:
		x_trial.y = params.ground_y_min
		grounded = true
	# collision
	var hit := ctx.surface.raycast(tip.position, x_trial)
	var x_new := x_trial
	var d_actual := d_dir
	if hit.hit:
		var bounce := hit.position + hit.normal * COLLISION_SKIN
		if traverse and hit.normal.y < -0.5:
			# T1: soffit underside hit — redirect along soffit outward instead of reflecting
			# back down. Replaces the pure reflection for this hit only; the second raycast
			# (concave-corner clamp) and d_actual recompute run unchanged below.
			var out_dir := tip.climb_outward
			if out_dir == Vector3.ZERO:
				out_dir = Vector3(d_dir.x, 0.0, d_dir.z)
				if out_dir.length_squared() < 1e-8:
					out_dir = Conv.SOUTH
				else:
					out_dir = out_dir.normalized()
			var glide := soffit_glide_dir(d_dir, hit.normal, out_dir, params.eave_soffit_glide)
			var remaining := maxf((x_trial - hit.position).length(), 0.5 * params.segment_length)
			x_new = bounce + glide * remaining
			tip.traverse_ticks = params.eave_traverse_window
		else:
			var incident := x_trial - hit.position
			var r := incident - 2.0 * incident.dot(hit.normal) * hit.normal
			# Keep the bounce point a skin off the face: a tip left on the plane (or a float hair
			# behind it) casts its next ray from behind the face, which back-face culling misses.
			x_new = bounce + r
		if x_new.y < params.ground_y_min:
			x_new.y = params.ground_y_min
			grounded = true
		# At a concave corner the reflected leg can pass through the adjacent face.
		var hit2 := ctx.surface.raycast(bounce, x_new)
		if hit2.hit:
			x_new = hit2.position + hit2.normal * COLLISION_SKIN
		d_actual = (x_new - tip.position).normalized()
		tip.last_contact_normal = hit.normal
	if x_new.y < params.ground_y_min:
		x_new.y = params.ground_y_min
		grounded = true
	if grounded:
		tip.ground_strikes += 1
	# float update
	# SD-MESH-7: on mesh SDF surfaces, small errors in the baked gradient cause
	# cumulative outward drift — each segment adds a tiny off-wall component that
	# adhesion alone cannot fully counteract. Two layers of defence:
	#   1. Widen contact_thresh by h/2 to absorb single-step quantisation error.
	#   2. Post-placement snap: if the old position was attached (d ≤ contact_thresh)
	#      and the new endpoint drifted beyond it, project back to the nearest surface.
	#      Only fires when no wall collision intercepted the segment (hit.hit == false)
	#      and the drift is within adhesion_range (genuinely still near the wall).
	var contact_thresh := ctx.surface.effective_contact(params.contact_distance)
	# Also applied to the analytic tower (ivy-p73): there, outward wander beat the weak
	# adhesion weight and about half of all start seeds fell off the wall and died. The tower
	# snap keeps a COLLISION_SKIN off the face so the next collision ray starts in front of it.
	var backend := ctx.surface.backend_tag()
	if d <= contact_thresh and (backend == "MeshSdf" or backend == "TowerSdf") and not hit.hit:
		var near_x := ctx.surface.nearest(x_new)
		if near_x.hit and near_x.distance > contact_thresh \
				and near_x.distance < params.adhesion_range:
			x_new = near_x.position
			if backend == "TowerSdf":
				x_new += near_x.normal * COLLISION_SKIN
			d_actual = (x_new - tip.position).normalized()
	if d <= contact_thresh:
		tip.floating_length = 0.0
		tip.state = Tip.State.GROWING
	else:
		tip.floating_length += params.segment_length
		tip.state = Tip.State.FLOATING
	var seg_a := tip.position
	tip.position = x_new
	# §30 direction_memory: how much of the previous heading survives a step. The literal 50/50
	# blend this replaces was numerically identical at the default 0.50 (normalisation cancels the
	# common factor), which is what let the parameter sit dead without any test noticing.
	var mem := params.direction_memory
	tip.direction = apply_direction_memory(tip.direction, d_actual, mem)
	tip.shoot_length += params.segment_length
	tip.segment_count += 1
	tip.distance_since_node += params.segment_length
	var seg_material := MaterialRegistry.BRICK_WALL
	if hit.hit:
		seg_material = hit.material_id
	else:
		var at_end := ctx.surface.nearest(x_new)
		if at_end.hit:
			seg_material = at_end.material_id
	ctx.plant.append_segment(
		seg_a, x_new, tip.last_contact_normal, tip.id, tip.branch_order, tip.shoot_length, seg_material
	)
	Physiology.deposit_stem_crowding(tip, ctx)
	# branch — SD-TIP-2/3: apply taper scale between soft and hard cap
	if ctx.tips.can_branch(params):
		var c := ctx.env.sample_crowding(tip.position, tip.id, tip.segment_count)
		var p_b := Physiology.branch_probability(f_l, c, params)
		var branch_q := ctx.tips.branch_probability_scale(params)
		if tip.stream.randf() < p_b * branch_q:
			var angle := deg_to_rad(tip.stream.randf_range(params.branch_angle_min, params.branch_angle_max))
			var sign := 1.0 if tip.branch_index % 2 == 0 else -1.0
			var rot := Basis(tip.last_contact_normal, sign * angle)
			var branch_dir := rot * tip.direction
			var branch_pos := x_new + branch_dir * params.branch_offset
			var branch_hit := ctx.surface.raycast(x_new, branch_pos)
			if branch_hit.hit:
				branch_pos = branch_hit.position + branch_hit.normal * COLLISION_SKIN
			ctx.tips.queue_branch(tip, branch_pos, branch_dir, tip.last_contact_normal, tip.branch_index, params)
			tip.branch_index += 1
	# l_dir is the bounded accumulated-light gradient (SD-LEAF-4 rule 5, SD-RNG-6).
	# It must come from accumulated light, never the instantaneous sun (INV-3a).
	LeafPlacer.advance(tip, ctx, seg_a, x_new, f_l, basis, l_dir)
