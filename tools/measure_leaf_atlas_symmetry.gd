extends Node

## Headless symmetry report for each leaf rect in LeafSet017.
##   Godot --headless res://tools/measure_leaf_atlas_symmetry.tscn

const SymmetryScript = preload("res://src/render/leaf_atlas_symmetry.gd")
const JSON_PATH := "res://assets/plants/ivy/LeafSet017/leaf_atlas.json"
const ATLAS_PNG := "res://assets/plants/ivy/LeafSet017/LeafSet017_Leaves_RGBA.png"

const CARD_BG := Color(0.22, 0.24, 0.26)
## Scan silhouettes are organically asymmetric; card QA uses luma balance only.
const MAX_CARD_LUMA_MAE := 0.04


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	var tex: Texture2D = load(ATLAS_PNG) as Texture2D
	var img := tex.get_image() if tex != null else null
	if img == null:
		push_error("failed to load atlas")
		get_tree().quit(1)
		return
	for leaf: Dictionary in data.leaves:
		var rect: Array = leaf.rect_px
		var rep := SymmetryScript.measure_alpha_patch(
			img, int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])
		)
		print(
			"[symmetry] atlas %s alpha_mirror_mae=%.5f centroid_off=%+.4f"
			% [leaf.id, rep.mirror_mae, rep.centroid_x_offset]
		)
	var failed := false
	var card_path := ProjectSettings.globalize_path("res://.tmp/leaf-lookdev/leaf_card_a.png")
	if FileAccess.file_exists(card_path):
		var card := Image.load_from_file(card_path)
		if card != null:
			var luma := SymmetryScript.measure_luma_patch(card, CARD_BG)
			var ok_card := luma.mirror_mae <= MAX_CARD_LUMA_MAE
			if not ok_card:
				failed = true
			print(
				"[symmetry] leaf_card_a.png luma_mae=%.5f centroid_off=%+.4f %s"
				% [luma.mirror_mae, luma.centroid_x_offset, "FAIL" if not ok_card else "ok"]
			)
		else:
			print("[symmetry] leaf_card_a.png present but failed to load")
	else:
		print("[symmetry] skip card PNG (run capture_single_leaf_card --id=a)")
	get_tree().quit(1 if failed else 0)
