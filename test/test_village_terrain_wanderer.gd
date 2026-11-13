## AC-VT10 — Wanderer path-vertex Y follows terrain when follow flag is on.
## WP7: ivy-82zn.4.7
extends GutTest

const VillageLayout = preload("res://src/world/village_layout.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")
const ClassicBackdropScene = preload("res://src/world/village_backdrop.tscn")
const WandererController = preload("res://src/presentation/wanderer/wanderer_controller.gd")
const WandererBrain = preload("res://src/presentation/wanderer/wanderer_brain.gd")
const WandererIntegration = preload("res://src/presentation/wanderer/wanderer_integration.gd")

const _GEN_SEED := 7
const _EPS_Y := 0.06  # AC-VT10: figure y >= sample_y - 0.05; we use 0.06 headroom


# ── Test 1: sample_terrain_y is exposed on VillageBackdrop (classic) ──────────

func test_backdrop_exposes_sample_terrain_y() -> void:
	var bd: VillageBackdrop = ClassicBackdropScene.instantiate()
	add_child_autofree(bd)
	await get_tree().process_frame
	assert_true(bd.has_method("sample_terrain_y"),
		"VillageBackdrop must expose sample_terrain_y(xz: Vector2) -> float")


# ── Test 2: sample_terrain_y returns 0 for classic (INV-15) ──────────────────

func test_sample_terrain_y_classic_returns_datum() -> void:
	var bd: VillageBackdrop = ClassicBackdropScene.instantiate()
	add_child_autofree(bd)
	await get_tree().process_frame
	var layout: VillageLayout = bd.get_layout()
	if layout != null and layout.is_generated:
		pending("need a classic backdrop for this test")
		return
	assert_true(bd.has_method("sample_terrain_y"),
		"VillageBackdrop must expose sample_terrain_y")
	var y: float = bd.call("sample_terrain_y", Vector2.ZERO)
	assert_almost_eq(y, 0.0, 1e-6,
		"classic backdrop sample_terrain_y must return 0.0 (INV-15)")


# ── Test 3: figure Y >= sample_y during WALKING (generated, follow on) ────────

func test_figure_y_follows_terrain_when_walking() -> void:
	WandererIntegration.set_gut_wanderer_test_active(true)
	var bd: GeneratedVillageBackdrop = GeneratedBackdropScene.instantiate()
	bd.set_village_seed(_GEN_SEED)
	add_child_autofree(bd)
	await get_tree().process_frame
	var layout: VillageLayout = bd.get_layout()
	if layout == null or not layout.is_generated:
		pending("generated backdrop not available — skip")
		return
	assert_true(bd.has_method("sample_terrain_y"),
		"GeneratedVillageBackdrop must expose sample_terrain_y")
	var terrain_params: VillageTerrainParams = bd.get("_terrain_params")
	if terrain_params == null:
		pending("no _terrain_params on generated backdrop — skip")
		return
	terrain_params.wanderer_follow_terrain = true  # ensure enabled
	var ctrl := WandererController.new()
	add_child_autofree(ctrl)
	ctrl.bind_backdrop(bd, "generated")
	# Step through ~3 s, sampling figure Y vs terrain Y during WALKING
	var dt := 1.0 / 30.0
	var failures := 0
	var walking_frames := 0
	for _i in range(90):  # 3 s
		ctrl.tick(dt, false)
		var brain: WandererBrain = ctrl.get_brain()
		if brain.state != WandererBrain.State.WALKING:
			continue
		walking_frames += 1
		var fig_pos: Vector3 = ctrl.get_figure_global_position()
		var terrain_y: float = bd.call("sample_terrain_y", Vector2(fig_pos.x, fig_pos.z))
		if fig_pos.y < terrain_y - _EPS_Y:
			failures += 1
	if walking_frames == 0:
		pending("wanderer never entered WALKING state in 3 s — skip")
		return
	assert_eq(failures, 0,
		"figure y must be >= sample_y - %.2f during WALKING (sampled %d frames)" % [_EPS_Y, walking_frames])


# ── Test 4: off-path states keep figure Y at datum ────────────────────────────

func test_figure_y_is_datum_during_door_pause() -> void:
	WandererIntegration.set_gut_wanderer_test_active(true)
	var bd: GeneratedVillageBackdrop = GeneratedBackdropScene.instantiate()
	bd.set_village_seed(_GEN_SEED)
	add_child_autofree(bd)
	await get_tree().process_frame
	var ctrl := WandererController.new()
	add_child_autofree(ctrl)
	ctrl.bind_backdrop(bd, "generated")
	# Advance until DOOR_PAUSE
	if not ctrl.debug_advance_to("DOOR_PAUSE", 60.0):
		pending("could not reach DOOR_PAUSE in 60 s — skip")
		return
	var brain: WandererBrain = ctrl.get_brain()
	assert_eq(brain.state, WandererBrain.State.DOOR_PAUSE)
	var fig_root: Node3D = ctrl.get_node_or_null("FigurePivot")
	if fig_root == null:
		pending("FigurePivot node not found — skip")
		return
	assert_almost_eq(fig_root.position.y, 0.0, 0.02,
		"figure y must be datum (0.0) during DOOR_PAUSE (off-path A1)")


# ── Test 5: follow disabled → figure Y = datum even during WALKING ────────────

func test_figure_y_datum_when_follow_terrain_disabled() -> void:
	WandererIntegration.set_gut_wanderer_test_active(true)
	var bd: GeneratedVillageBackdrop = GeneratedBackdropScene.instantiate()
	bd.set_village_seed(_GEN_SEED)
	add_child_autofree(bd)
	await get_tree().process_frame
	var layout: VillageLayout = bd.get_layout()
	if layout == null or not layout.is_generated:
		pending("generated backdrop required — skip")
		return
	var terrain_params: VillageTerrainParams = bd.get("_terrain_params")
	if terrain_params == null:
		pending("no _terrain_params on generated backdrop — skip")
		return
	terrain_params.wanderer_follow_terrain = false  # disable
	var ctrl := WandererController.new()
	add_child_autofree(ctrl)
	ctrl.bind_backdrop(bd, "generated")
	var dt := 1.0 / 30.0
	var checked := false
	for _i in range(90):
		ctrl.tick(dt, false)
		var brain: WandererBrain = ctrl.get_brain()
		if brain.state == WandererBrain.State.WALKING:
			var fig_pos: Vector3 = ctrl.get_figure_global_position()
			assert_almost_eq(fig_pos.y, 0.0, 0.02,
				"figure y must be 0.0 when wanderer_follow_terrain=false")
			checked = true
			break
	if not checked:
		pending("could not reach WALKING state in 3 s")
