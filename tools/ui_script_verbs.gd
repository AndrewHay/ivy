class_name UiScriptVerbs
extends RefCounted

## Shared helpers for tools/run_ui_script.gd (W-027 SEED / ASSERT).

const _CoverageMetric = preload("res://src/metrics/coverage.gd")


static func compass_to_seed_index(token: String) -> int:
	match token.strip_edges().to_lower():
		"n", "north":
			return 0
		"e", "east":
			return 1
		"s", "south":
			return 2
		"w", "west":
			return 3
		_:
			if token.is_valid_int():
				return int(token)
			return -1


static func compare(actual: float, op: String, expected: float) -> bool:
	match op:
		"==":
			return is_equal_approx(actual, expected)
		"!=":
			return not is_equal_approx(actual, expected)
		"<":
			return actual < expected
		"<=":
			return actual <= expected
		">":
			return actual > expected
		">=":
			return actual >= expected
		_:
			return false


static func collect_metrics(sim: Node, world: Node, seed_azimuth_deg: float) -> Dictionary:
	var out: Dictionary = {}
	if sim == null:
		return out
	var plant: PlantData = sim.get("plant") as PlantData
	var clock: SimClock = sim.get("clock") as SimClock
	var solar: Solar = sim.get("solar") as Solar
	var params: IvyParams = sim.get("params") as IvyParams
	var tips = sim.get("tips")
	out["game_day"] = clock.game_day if clock != null else 0.0
	out["tick_index"] = float(clock.tick_index) if clock != null else 0.0
	out["tips"] = float(tips.tips.size()) if tips != null else 0.0
	out["segments"] = float(plant.segment_count()) if plant != null else 0.0
	out["leaves"] = float(plant.leaf_count()) if plant != null else 0.0
	out["total_stem_length"] = plant.total_length if plant != null else 0.0

	if world != null and plant != null:
		var spec: TowerSpec = world.get("tower_spec") as TowerSpec
		if spec != null:
			var metric: RefCounted = _CoverageMetric.new()
			metric.setup(spec, params if params != null else IvyParams.new())
			var cov: Dictionary = metric.measure(plant, seed_azimuth_deg)
			out["overall_pct"] = cov.get("overall_pct", 0.0)
			out["sun_half_pct"] = cov.get("sun_half_pct", 0.0)
			out["shade_half_pct"] = cov.get("shade_half_pct", 0.0)
			out["stem_bucket_pct"] = cov.get("stem_bucket_pct", 0.0)
			out["stem_asymmetry"] = cov.get("stem_asymmetry_pct", 0.0)
			out["sun_stem_length"] = cov.get("sun_stem_length", 0.0)
			out["shade_stem_length"] = cov.get("shade_stem_length", 0.0)
			out["lip_reached"] = 1.0 if cov.get("lip_reached", false) else 0.0

	if solar != null and params != null and clock != null:
		var day_int: int = int(floor(clock.game_day))
		var noon_day: float = float(day_int) + (12.0 - params.start_hour) / 24.0
		var midnight_day: float = float(day_int) + (24.0 - params.start_hour) / 24.0
		out["gate_noon"] = solar.diel_gate(noon_day)
		out["gate_midnight"] = solar.diel_gate(midnight_day)

	return out


static func read_metric(name: String, metrics: Dictionary) -> Variant:
	return metrics.get(name, null)
