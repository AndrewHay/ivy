class_name FaunaIntegration
extends RefCounted

## Gates main/world fauna wiring during GUT so mesh-building integration tests do not spawn insects.
## Fauna unit tests opt in per test method (see test/test_fauna_*.gd before_each).

const _META_GUT_FAUNA := "ivy_gut_fauna_integration"


static func world_runtime_enabled() -> bool:
	if not _gut_runner_active():
		return true
	return Engine.has_meta(_META_GUT_FAUNA) and Engine.get_meta(_META_GUT_FAUNA) == true


static func set_gut_fauna_test_active(active: bool) -> void:
	if active:
		Engine.set_meta(_META_GUT_FAUNA, true)
	elif Engine.has_meta(_META_GUT_FAUNA):
		Engine.remove_meta(_META_GUT_FAUNA)


static func _gut_runner_active() -> bool:
	for arg: String in OS.get_cmdline_args():
		if arg.contains("gut_cmdln.gd") or arg.contains("addons/gut/gut_cmdln"):
			return true
	return false
