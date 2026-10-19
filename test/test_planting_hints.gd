## Player-facing planting hint (ivy-yk8): the line that tells you where you may plant, in plain
## language, instead of `tips=0 | hover=no wall hit | ...` developer text.
extends GutTest

const PlantingTool = preload("res://src/ui/planting_tool.gd")
const MainScene = preload("res://src/main/main.tscn")


func _hit(y_above_ground: float, normal: Vector3, material_id: int) -> SurfaceQuery.Hit:
	var params := IvyParams.new()
	var hit := SurfaceQuery.Hit.new()
	hit.hit = true
	hit.position = Vector3(1.0, params.ground_y_min + y_above_ground, 0.0)
	hit.normal = normal
	hit.material_id = material_id
	return hit


func test_reject_code_identifies_each_rule() -> void:
	var params := IvyParams.new()
	var side := Vector3(0.0, 0.0, 1.0)
	assert_eq(PlantingTool.reject_code(null, params), PlantingTool.Reject.NOT_READY)
	assert_eq(PlantingTool.reject_code(SurfaceQuery.Hit.new(), params), PlantingTool.Reject.NO_HIT)
	assert_eq(PlantingTool.reject_code(_hit(0.05, side, MaterialRegistry.BRICK_WALL), params),
		PlantingTool.Reject.NONE)
	assert_eq(PlantingTool.reject_code(_hit(2.0, side, MaterialRegistry.BRICK_WALL), params),
		PlantingTool.Reject.TOO_HIGH)
	assert_eq(PlantingTool.reject_code(_hit(0.05, Vector3.UP, MaterialRegistry.BRICK_WALL), params),
		PlantingTool.Reject.TOO_FLAT)
	assert_eq(PlantingTool.reject_code(_hit(0.05, side, MaterialRegistry.GLASS), params),
		PlantingTool.Reject.NOT_CLIMBABLE)


## Developer tools and the dev line print these strings, so the refactor must not change them.
func test_developer_reason_strings_are_unchanged() -> void:
	var params := IvyParams.new()
	assert_eq(PlantingTool.hover_reject_reason(null, params), "not ready")
	assert_eq(PlantingTool.hover_reject_reason(SurfaceQuery.Hit.new(), params), "no wall hit")
	assert_eq(PlantingTool.hover_reject_reason(_hit(0.05, Vector3.UP, MaterialRegistry.BRICK_WALL), params),
		"normal too flat")
	assert_true(PlantingTool.hover_reject_reason(
		_hit(2.0, Vector3(0, 0, 1), MaterialRegistry.BRICK_WALL), params).begins_with("too high"))
	assert_true(PlantingTool.hover_reject_reason(
		_hit(0.05, Vector3(0, 0, 1), MaterialRegistry.GLASS), params).begins_with("material"))


func test_hints_are_plain_language_and_distinct() -> void:
	var seen := {}
	for code in PlantingTool.Reject.values():
		if code == PlantingTool.Reject.NOT_READY:
			continue  # before the tool is wired up there is nothing useful to say
		var hint: String = PlantingTool.player_hint(code)
		assert_false(hint.is_empty(), "code %d needs a hint" % code)
		for jargon in ["=", "material", "normal", "hover", "wall hit", "(", "tips"]:
			assert_false(hint.contains(jargon), "hint '%s' must not contain '%s'" % [hint, jargon])
		assert_false(seen.has(hint), "hint '%s' is shared by two different reasons" % hint)
		seen[hint] = true
	assert_string_contains(PlantingTool.player_hint(PlantingTool.Reject.NONE), "Click",
		"a valid spot must tell the player what to do")


# ── in the real HUD ─────────────────────────────────────────────────────────

func _boot() -> Node:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	main.get_node("UI/BuildingPicker")._on_entry_pressed("cylinder")
	for _i in range(900):
		if main._hud != null:
			break
		await get_tree().process_frame
	for _f in range(3):
		await get_tree().process_frame
	return main


func test_hud_shows_a_plain_hint_while_aiming() -> void:
	var main: Node = await _boot()
	var text: String = main._hud.plant_hint_text()
	assert_false(text.is_empty(), "the aiming hint must not be blank")
	assert_true(main._hud.is_plant_hint_visible())
	assert_false(text.contains("hover="), "no developer text in the player hint")
	assert_false(text.contains("tips="), "no developer text in the player hint")


func test_hint_goes_away_once_planted() -> void:
	var main: Node = await _boot()
	main._on_plant_success()
	await get_tree().process_frame
	assert_false(main._hud.is_plant_hint_visible(), "nothing to aim at after planting")
