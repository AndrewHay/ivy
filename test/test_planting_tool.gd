extends GutTest

const PlantingTool = preload("res://src/ui/planting_tool.gd")


func test_validates_low_wall_hit() -> void:
	var params := IvyParams.new()
	var hit := SurfaceQuery.Hit.new()
	hit.hit = true
	hit.position = Vector3(1.0, params.ground_y_min + 0.05, 0.0)
	hit.normal = Vector3(0.0, 0.0, 1.0)
	hit.material_id = MaterialRegistry.BRICK_WALL
	assert_eq(PlantingTool.hover_reject_reason(hit, params), "")


func test_rejects_high_wall_hit() -> void:
	var params := IvyParams.new()
	var hit := SurfaceQuery.Hit.new()
	hit.hit = true
	hit.position = Vector3(1.0, 2.0, 0.0)
	hit.normal = Vector3(0.0, 0.0, 1.0)
	hit.material_id = MaterialRegistry.BRICK_WALL
	assert_false(PlantingTool.hover_reject_reason(hit, params).is_empty())


func test_rejects_glass_and_interior() -> void:
	var params := IvyParams.new()
	for material_id in [MaterialRegistry.GLASS, MaterialRegistry.INTERIOR, MaterialRegistry.GROUND]:
		var hit := SurfaceQuery.Hit.new()
		hit.hit = true
		hit.position = Vector3(0.0, params.ground_y_min, 0.0)
		hit.normal = Vector3(0.0, 0.0, 1.0)
		hit.material_id = material_id
		assert_false(PlantingTool.hover_reject_reason(hit, params).is_empty())


func test_rejects_null_hit() -> void:
	var params := IvyParams.new()
	assert_eq(PlantingTool.hover_reject_reason(null, params), "not ready")
