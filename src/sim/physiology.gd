class_name Physiology
extends RefCounted

static func f_L(d: float, params: IvyParams) -> float:
	var num := d / (d + params.light_K)
	var den := params.reference_DLI / (params.reference_DLI + params.light_K)
	return min(1.0, num / den)


static func f_M(_m: float) -> float:
	return 1.0


static func f_C(c: float, params: IvyParams) -> float:
	return exp(-params.crowding_decay * c)


static func f_S(floating: float, params: IvyParams) -> float:
	var r := clampf(floating / params.max_float, 0.0, 1.0)
	return 1.0 - 0.5 * r * r


static func H(d_l: float, params: IvyParams) -> float:
	return f_L(d_l, params) * f_M(1.0)


static func w_P(h: float) -> float:
	return 0.5 * (0.7 + 0.3 * h)


static func w_R(h: float, params: IvyParams) -> float:
	return params.random_base * (1.0 + 0.8 * (1.0 - h))


static func w_L(f_l: float, params: IvyParams) -> float:
	return params.light_seek_min + (params.light_seek_max - params.light_seek_min) * (1.0 - f_l)


static func w_C(h: float, params: IvyParams) -> float:
	return params.crowding_base * (0.5 + 0.5 * h)


static func w_G(floating: float, params: IvyParams) -> float:
	var r := clampf(floating / params.max_float, 0.0, 1.0)
	return pow(r, params.gravity_exponent)


static func growth_rate(tip: Tip, g_hat: float, ctx: SimContext) -> float:
	var params := ctx.params
	var d_l := ctx.env.sample_D_L(tip.position, tip.id, tip.segment_count)
	var c := ctx.env.sample_crowding(tip.position, tip.id, tip.segment_count)
	var r := params.max_growth_rate
	r *= f_L(d_l, params)
	r *= f_M(1.0)
	r *= f_C(c, params)
	r *= f_S(tip.floating_length, params)
	if params.diel_gate_enabled:
		r *= g_hat
	return r


static func accumulate_budget(tip: Tip, g_hat: float, ctx: SimContext) -> void:
	if not tip.is_live():
		return
	var r := growth_rate(tip, g_hat, ctx)
	tip.growth_budget += r * ctx.clock.dt_sim()


static func lambda_b(f_l: float, c: float, params: IvyParams) -> float:
	return params.branch_rate * pow(f_l, params.branch_light_exponent) * f_M(1.0) * pow(1.0 - c, params.branch_crowd_exponent)


static func branch_probability(f_l: float, c: float, params: IvyParams) -> float:
	return 1.0 - exp(-lambda_b(f_l, c, params) * params.segment_length)


static func deposit_stem_crowding(tip: Tip, ctx: SimContext) -> void:
	var d_l := ctx.env.sample_D_L(tip.position, tip.id, tip.segment_count)
	var amount := 0.02 * f_L(d_l, ctx.params)
	ctx.env.deposit_crowding(tip.position, amount)


## SD-LEAF-8 / SD-PHYS-3: deposit crowding proportional to predicted leaf area.
## Called from LeafPlacer so that physiology remains the sole writer to the crowding
## channel (INV-1). Deposit = k_leaf * leaf_area / cell_area.
static func deposit_leaf_crowding(position: Vector3, leaf_area: float, ctx: SimContext) -> void:
	var cell_area := ctx.params.field_cell * ctx.params.field_cell
	var amount := ctx.params.leaf_crowd_k * leaf_area / cell_area
	ctx.env.deposit_crowding(position, amount)
