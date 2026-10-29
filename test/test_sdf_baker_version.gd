extends GutTest
## ivy-vyp: every committed scenario SDF must carry the baker version MeshSdf accepts.
## A stale bake (e.g. ivy_sim.sdf at v2 after the ivy-uaq v3 bump) otherwise only fails at
## runtime in the picker with "Environment build failed".

const MeshSdfScript = preload("res://src/world/mesh_sdf.gd")
const SCENARIO_DIR := "res://assets/structures/scenarios/"
## IVYSDF1 header: magic(7) h(4) band(4) origin(12) dims(12) aabb(24) → baker version at 63.
const _VERSION_OFFSET := 63


func _scenario_paths() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(SCENARIO_DIR):
		if f.ends_with(".tres"):
			out.append(SCENARIO_DIR + f)
	return out


func test_every_scenario_sdf_has_current_baker_version() -> void:
	var checked := 0
	for path in _scenario_paths():
		var sc := load(path) as StructureScenario
		if sc == null or sc.sdf_path == "":
			continue
		var f := FileAccess.open(sc.sdf_path, FileAccess.READ)
		assert_not_null(f, "%s: cannot open sdf_path %s" % [path, sc.sdf_path])
		if f == null:
			continue
		f.seek(_VERSION_OFFSET)
		var ver := f.get_32()
		assert_eq(ver, MeshSdfScript.BAKER_VERSION,
			"%s baked with baker v%d, loader needs v%d — re-run tools/bake_mesh_sdf.py"
			% [sc.sdf_path, ver, MeshSdfScript.BAKER_VERSION])
		checked += 1
	assert_gt(checked, 0, "expected at least one scenario with an sdf_path")
