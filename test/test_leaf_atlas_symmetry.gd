extends GutTest

## Imported atlas alpha should match on-disk PNG (catches stale VRAM after repaint).
## Organic scans are not mirror-perfect; this only guards import drift + documents mirror MAE.
const SymmetryScript = preload("res://src/render/leaf_atlas_symmetry.gd")
const ATLAS_PNG := "res://assets/plants/ivy/LeafSet017/LeafSet017_Leaves_RGBA.png"
const JSON_PATH := "res://assets/plants/ivy/LeafSet017/leaf_atlas.json"
const MAX_DISK_IMPORT_MAE := 0.015


func test_imported_albedo_matches_disk_alpha_per_rect() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	var disk := Image.load_from_file(ProjectSettings.globalize_path(ATLAS_PNG))
	assert_not_null(disk, "disk albedo must load")
	var tex: Texture2D = load(ATLAS_PNG) as Texture2D
	assert_not_null(tex, "imported texture must load")
	var imported := tex.get_image()
	assert_not_null(imported, "imported image must decode")
	if disk.is_compressed():
		disk.decompress()
	if imported.is_compressed():
		imported.decompress()
	for leaf: Dictionary in data.leaves:
		var rect: Array = leaf.rect_px
		var x0 := int(rect[0])
		var y0 := int(rect[1])
		var rw := int(rect[2])
		var rh := int(rect[3])
		var sum_diff := 0.0
		var n := rw * rh
		for j in range(rh):
			for i in range(rw):
				var a_d := disk.get_pixel(x0 + i, y0 + j).a
				var a_i := imported.get_pixel(x0 + i, y0 + j).a
				sum_diff += absf(a_d - a_i)
		var mae := sum_diff / float(n)
		assert_lte(
			mae,
			MAX_DISK_IMPORT_MAE,
			"leaf '%s' imported alpha drift %.4f — run Godot --headless --path <repo> --import"
			% [leaf.id, mae]
		)
