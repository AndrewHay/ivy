class_name WandererIntegration
extends RefCounted

const _META_GUT_WANDERER := "ivy_gut_wanderer_integration"


static func world_runtime_enabled() -> bool:
	if not _gut_runner_active():
		return true
	return Engine.has_meta(_META_GUT_WANDERER) and Engine.get_meta(_META_GUT_WANDERER) == true


static func set_gut_wanderer_test_active(active: bool) -> void:
	if active:
		Engine.set_meta(_META_GUT_WANDERER, true)
	elif Engine.has_meta(_META_GUT_WANDERER):
		Engine.remove_meta(_META_GUT_WANDERER)


static func _gut_runner_active() -> bool:
	for arg: String in OS.get_cmdline_args():
		if arg.contains("gut_cmdln.gd") or arg.contains("addons/gut/gut_cmdln"):
			return true
	return false
