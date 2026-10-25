## Mechanical check that committed albedo alpha in each atlas rect matches leaf_atlas.json.
## For silhouette QA, run: Godot res://tools/capture_single_leaf_card.tscn -- --id=all
extends GutTest

const AtlasScript = preload("res://src/render/leaf_atlas.gd")
const ATLAS_PNG := "res://assets/plants/ivy/LeafSet017/LeafSet017_Leaves_RGBA.png"
const JSON_PATH := "res://assets/plants/ivy/LeafSet017/leaf_atlas.json"


func test_albedo_alpha_fill_matches_json_per_leaf_id() -> void:
	var atlas := AtlasScript.new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	var img := Image.load_from_file(ATLAS_PNG)
	assert_not_null(img, "albedo atlas must load")
	for leaf: Dictionary in data.leaves:
		var lid: String = leaf.id
		var rect: Array = leaf.rect_px
		var x0: int = int(rect[0])
		var y0: int = int(rect[1])
		var rw: int = int(rect[2])
		var rh: int = int(rect[3])
		var sum := 0.0
		var n := rw * rh
		for j in range(rh):
			for i in range(rw):
				sum += img.get_pixel(x0 + i, y0 + j).a
		var measured := sum / float(n)
		var expected := atlas.alpha_fill_for(lid)
		assert_almost_eq(measured, expected, 0.02,
			"alpha_fill for leaf '%s' must match PNG (is the atlas imported / repainted?)" % lid)
