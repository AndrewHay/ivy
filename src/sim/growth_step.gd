class_name GrowthStep
extends RefCounted

static func step_tip(tip: Tip, ctx: SimContext) -> void:
	var params := ctx.params
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
	# 3. gradients
	var basis := ctx.surface.tangent_basis_at(tip.position)
	var d_l := ctx.env.sample_D_L(tip.position, tip.id, tip.segment_count)
	var f_l := Physiology.f_L(d_l, params)
	var h := Physiology.H(d_l, params)
	var grad_l := ctx.env.grad_S_D_L(tip.position, basis, tip.id, tip.segment_count)
	var grad_c := ctx.env.grad_S_crowding(tip.position, basis, tip.id, tip.segment_count)
	var l_dir := grad_l / (grad_l.length() + params.light_gradient_scale)
	var c_dir := grad_c / (grad_c.length() + params.crowding_gradient_scale)
	var w_p := Physiology.w_P(h)
	var w_r := Physiology.w_R(h, params)
	var w_l := Physiology.w_L(f_l, params)
	var w_c := Physiology.w_C(h, params)
	var w_g := Physiology.w_G(tip.floating_length, params)
	var u := w_p * tip.direction + w_r * tip.random_dir + params.adhesion_base * a_vec
	u += w_l * l_dir - w_c * c_dir + w_g * Conv.GRAVITY
	var d_dir := u
	if u.length_squared() < 1e-8:
		d_dir = tip.direction
	else:
		d_dir = u.normalized()
	var x_trial := tip.position + d_dir * params.segment_length
	# collision
	var hit := ctx.surface.raycast(tip.position, x_trial)
	var x_new := x_trial
	var d_actual := d_dir
	if hit.hit:
		var incident := x_trial - hit.position
		var r := incident - 2.0 * incident.dot(hit.normal) * hit.normal
		x_new = hit.position + r
		d_actual = (x_new - tip.position).normalized()
		tip.last_contact_normal = hit.normal
	# ground clamp
	if x_new.y < params.ground_y_min:
		x_new.y = params.ground_y_min
		tip.ground_strikes += 1
	# float update
	if d <= params.contact_distance:
		tip.floating_length = 0.0
		tip.state = Tip.State.GROWING
	else:
		tip.floating_length += params.segment_length
		tip.state = Tip.State.FLOATING
	var seg_a := tip.position
	tip.position = x_new
	tip.direction = (tip.direction + d_actual).normalized()
	tip.shoot_length += params.segment_length
	tip.segment_count += 1
	tip.distance_since_node += params.segment_length
	ctx.plant.append_segment(seg_a, x_new, tip.last_contact_normal, tip.id, tip.branch_order, tip.shoot_length)
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
			ctx.tips.queue_branch(tip, branch_pos, branch_dir, tip.last_contact_normal, tip.branch_index, params)
			tip.branch_index += 1
	LeafPlacer.advance(tip, ctx, seg_a, x_new, f_l, basis)
