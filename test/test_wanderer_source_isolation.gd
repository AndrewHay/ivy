extends GutTest

const FORBIDDEN := [
	"src/sim",
	"IvyParams",
	"SimClock",
	"Input.",
	"randf(",
	"randi(",
	"collision_layer",
]


func test_wanderer_sources_clean() -> void:
	var dir := DirAccess.open("res://src/presentation/wanderer/")
	assert_not_null(dir)
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".gd"):
			var text := FileAccess.get_file_as_string("res://src/presentation/wanderer/" + fn)
			for bad in FORBIDDEN:
				assert_false(text.contains(bad), "%s contains %s" % [fn, bad])
		fn = dir.get_next()
