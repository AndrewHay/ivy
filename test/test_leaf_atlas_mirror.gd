extends GutTest

const SymmetryScript = preload("res://src/render/leaf_atlas_symmetry.gd")
const ATLAS_PNG := "res://assets/plants/ivy/LeafSet017/LeafSet017_Leaves_RGBA.png"
const JSON_PATH := "res://assets/plants/ivy/LeafSet017/leaf_atlas.json"
const MAX_MIRROR_MAE := 0.002


func test_imported_albedo_alpha_is_mirror_symmetric_per_rect() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	var tex: Texture2D = load(ATLAS_PNG) as Texture2D
	assert_not_null(tex)
	var img := tex.get_image()
	assert_not_null(img)
	for leaf: Dictionary in data.leaves:
		var rect: Array = leaf.rect_px
		var rep := SymmetryScript.measure_alpha_patch(
			img, int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])
		)
		assert_lte(
			rep.mirror_mae,
			MAX_MIRROR_MAE,
			"leaf '%s' mirror_mae %.5f — run symmetrize_leaf_atlas + --import"
			% [leaf.id, rep.mirror_mae]
		)
