extends Node

## Builds the albedo atlas from the original scan: each leaf's cleaner half is reflected about its
## midrib and re-centred in its rect (see assets/plants/ivy/LEAF_STANDARD.md).
##   Godot --headless res://tools/symmetrize_leaf_atlas.tscn
## Then: Godot --headless --path <repo> --import

const SymmetryScript = preload("res://src/render/leaf_atlas_symmetry.gd")
const JSON_PATH := "res://assets/plants/ivy/LeafSet017/leaf_atlas.json"
const SCAN_PATH := "res://assets/plants/ivy/LeafSet017/LeafSet017_Leaves_RGBA_scan.png"
const ALBEDO_PATH := "res://assets/plants/ivy/LeafSet017/LeafSet017_Leaves_RGBA.png"
const NORMAL_SCAN := "res://assets/plants/ivy/LeafSet017/LeafSet017_2K-JPG_NormalGL_scan.jpg"
const NORMAL_PATH := "res://assets/plants/ivy/LeafSet017/LeafSet017_2K-JPG_NormalGL.jpg"
const ROUGH_SCAN := "res://assets/plants/ivy/LeafSet017/LeafSet017_2K-JPG_Roughness_scan.jpg"
const ROUGH_PATH := "res://assets/plants/ivy/LeafSet017/LeafSet017_2K-JPG_Roughness.jpg"


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	var src := Image.load_from_file(ProjectSettings.globalize_path(SCAN_PATH))
	if src == null:
		push_error("[symmetrize] failed to load scan " + SCAN_PATH)
		get_tree().quit(1)
		return
	var dst := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	dst.fill(Color(0, 0, 0, 0))
	var n_src := Image.load_from_file(ProjectSettings.globalize_path(NORMAL_SCAN))
	var r_src := Image.load_from_file(ProjectSettings.globalize_path(ROUGH_SCAN))
	var maps_ok := (
		n_src != null and r_src != null
		and n_src.get_size() == src.get_size() and r_src.get_size() == src.get_size()
	)
	if not maps_ok:
		push_warning("[symmetrize] normal/roughness scan backups missing or wrong size; albedo only")
	var flat_n := Color(0.5, 0.5, 1.0, 1.0)
	var n_dst: Image = null
	var r_dst: Image = null
	if maps_ok:
		n_dst = n_src.duplicate()
		r_dst = r_src.duplicate()
	for leaf: Dictionary in data.leaves:
		var rect: Array = leaf.rect_px
		var x0 := int(rect[0])
		var y0 := int(rect[1])
		var rw := int(rect[2])
		var rh := int(rect[3])
		var line_dir: Array = SymmetryScript.reflect_leaf_into(src, dst, x0, y0, rw, rh)
		var line: Vector4 = line_dir[0]
		var dir: int = line_dir[1]
		if maps_ok:
			SymmetryScript.reflect_with(n_src, n_dst, x0, y0, rw, rh, line, dir, true, flat_n)
			SymmetryScript.reflect_with(r_src, r_dst, x0, y0, rw, rh, line, dir, false, Color.WHITE)
		var after := SymmetryScript.measure_alpha_patch(dst, x0, y0, rw, rh)
		var fill := SymmetryScript.mean_alpha_fill(dst, x0, y0, rw, rh)
		leaf.alpha_fill = snappedf(fill, 0.000001)
		print(
			"[symmetrize] %s midrib apex_x=%.0f petiole_x=%.0f (centre %d) half=%s alpha_fill=%.4f mirror_mae=%.4f"
			% [leaf.id, line.x, line.z, rw / 2, "R" if dir > 0 else "L", fill, after.mirror_mae]
		)
	var pin_note := (
		"reference_alpha_fill_a pins leaf-a fill for crowding and coverage metrics (scan-measured); "
		+ "per-leaf alpha_fill is the measured render value."
	)
	if not data.has("reference_alpha_fill_a"):
		push_warning("[symmetrize] reference_alpha_fill_a missing — sim/metrics will follow the art")
	if not data.notes.has(pin_note):
		data.notes.append(pin_note)
	var note := "Albedo: scan leaves reflected about the midrib (cleaner half) via tools/symmetrize_leaf_atlas.tscn."
	data.notes = data.notes.filter(func(n: String) -> bool: return not n.contains("mirror-averaged"))
	if not data.notes.has(note):
		data.notes.append(note)
	_save_json(JSON_PATH, data)
	dst.save_png(ProjectSettings.globalize_path(ALBEDO_PATH))
	if maps_ok:
		n_dst.save_jpg(ProjectSettings.globalize_path(NORMAL_PATH), 0.95)
		r_dst.save_jpg(ProjectSettings.globalize_path(ROUGH_PATH), 0.95)
	print("[symmetrize] wrote ", ALBEDO_PATH, " — run Godot --headless --path <repo> --import")
	get_tree().quit(0)


func _save_json(path: String, data: Dictionary) -> void:
	var abs := ProjectSettings.globalize_path(path)
	var f := FileAccess.open(abs, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t") + "\n")
