## Downsizes the ambientCG grass maps (2K, untracked library tier) to the committed 1K ground textures
## (ivy-82zn.17.1). Re-run after re-fetching the library:
##   godot --headless --path . -s tools/resize_ground_textures.gd
extends SceneTree

const _SRC := "res://assets/_local/ambientcg/%s/%s_2K-JPG_%s.jpg"
const _DST := "res://assets/materials/ground/%s/%s_1K_%s.jpg"
const _ASSETS := ["Grass005", "Grass004"]
## Roughness is not used: the ground stays ROUGHNESS = 1 (matte grass).
const _MAPS := ["Color", "NormalGL"]
const _SIZE := 1024


func _init() -> void:
	var failed := 0
	for id: String in _ASSETS:
		for m: String in _MAPS:
			var src := ProjectSettings.globalize_path(_SRC % [id, id, m])
			var dst := ProjectSettings.globalize_path(_DST % [id, id, m])
			var img := Image.load_from_file(src)
			if img == null or img.is_empty():
				push_error("resize_ground_textures: cannot read %s" % src)
				failed += 1
				continue
			img.resize(_SIZE, _SIZE, Image.INTERPOLATE_LANCZOS)
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			var err := img.save_jpg(dst, 0.9)
			print("[resize] %s -> %s (%d)" % [src.get_file(), dst.get_file(), err])
			if err != OK:
				failed += 1
	quit(1 if failed > 0 else 0)
