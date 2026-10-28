extends GutTest

## Ensures every script in the fast GUT directory loads and extends GutTest.
## GUT itself skips unloadable scripts and can still exit 0 (ivy-t3o).

const _TEST_DIR := "res://test"
const _GUT_TEST_BASE := "res://addons/gut/test.gd"


func test_all_fast_suite_scripts_parse_and_extend_gut_test() -> void:
	var failures: PackedStringArray = []
	var dir := DirAccess.open(_TEST_DIR)
	assert_not_null(dir, "res://test must exist")

	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.ends_with(".gd") and entry_name.begins_with("test_"):
			var path := _TEST_DIR.path_join(entry_name)
			var reason := _load_failure_reason(path)
			if not reason.is_empty():
				failures.append("%s — %s" % [path, reason])
		entry_name = dir.get_next()
	dir.list_dir_end()

	assert_eq(
		failures.size(),
		0,
		"Fast-suite scripts that failed inventory (parse error or not GutTest):\n" + "\n".join(failures)
	)


func _load_failure_reason(path: String) -> String:
	var loaded: Variant = GutUtils.WarningsManager.load_script_using_custom_warnings(
		path,
		GutUtils.warnings_when_loading_test_scripts
	)
	if loaded == null:
		return "failed to load (parse error or missing file)"
	if not loaded is GDScript:
		return "loaded resource is not GDScript"
	if not _extends_gut_test(loaded as GDScript):
		return "does not extend GutTest"
	return ""


func _extends_gut_test(script: GDScript) -> bool:
	var base: Variant = script.get_base_script()
	while base != null:
		if base is GDScript and (base as GDScript).resource_path == _GUT_TEST_BASE:
			return true
		base = (base as GDScript).get_base_script() if base is GDScript else null
	return false
