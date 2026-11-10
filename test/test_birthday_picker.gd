extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const WandererIntegration = preload("res://src/presentation/wanderer/wanderer_integration.gd")


## Script errors only abort the failing function in a debug build (the editor breaks on them),
## so the load still "completes"; capture them to fail the test.
class ScriptErrorLog:
	extends Logger
	var errors: Array[String] = []

	func _log_error(_function: String, file: String, line: int, _code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s" % [file, line, rationale])


var _log: ScriptErrorLog


func before_each() -> void:
	_log = ScriptErrorLog.new()
	OS.add_logger(_log)


func after_each() -> void:
	OS.remove_logger(_log)
	WandererIntegration.set_gut_wanderer_test_active(false)
	# Building the generated village sets this static; later suites assume classic scale.
	VillagePresentationScale.fauna_world_scale = 1.0


## Birthday is retired from the menu (no button), but stays loadable by id.
func test_birthday_has_no_picker_button() -> void:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	var picker: Node = main.get_node("UI").get_node_or_null("BuildingPicker")
	assert_not_null(picker)
	var labels: Array[String] = []
	for n in picker.find_children("*", "Button", true, false):
		labels.append((n as Button).text)
	assert_false("Birthday" in labels, "Birthday retired from the picker")
	assert_true("Village cottage" in labels, "regular entries still listed")


## Loading Birthday by id builds the generated village before the debug camera is set up;
## the lawn-bounds clamp used to read the camera's null spec.
func test_pressing_birthday_builds_village_without_script_errors() -> void:
	WandererIntegration.set_gut_wanderer_test_active(true)
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var picker: Node = main.get_node("UI").get_node_or_null("BuildingPicker")
	assert_not_null(picker)
	picker.call("_on_entry_pressed", "birthday")
	await get_tree().process_frame
	var world: Node3D = main.get_node("World")
	assert_eq(world.get_active_building_id(), "birthday")
	assert_eq(world.get_village_mode(), GameModes.GENERATED)
	assert_not_null(world.get_wanderer_controller())
	assert_eq(_log.errors, [] as Array[String], "no script errors while loading Birthday")
