extends Node

## One-off preview capture for snapshot annotation overlay (ivy-nrp.4 QA).

const _Overlay = preload("res://src/ui/snapshot_annotation_overlay.gd")

const _OUT := "res://.tmp/snapshots/qa_overlay_preview.png"


func _ready() -> void:
	var vp := Vector2(1280, 720)
	var win := get_window()
	if win != null:
		win.size = Vector2i(int(vp.x), int(vp.y))
	var img := Image.create(int(vp.x), int(vp.y), false, Image.FORMAT_RGB8)
	img.fill(Color(0.35, 0.38, 0.42))
	for y in range(0, int(vp.y), 40):
		for x in range(0, int(vp.x), 40):
			if (x / 40 + y / 40) % 2 == 0:
				img.set_pixel(x, y, Color(0.32, 0.35, 0.39))
	var layer := CanvasLayer.new()
	add_child(layer)
	var overlay := _Overlay.new()
	layer.add_child(overlay)
	overlay.setup(
		img,
		vp,
		[Rect2(0.35, 0.28, 0.22, 0.18), Rect2(0.58, 0.52, 0.12, 0.14)]
	)
	await get_tree().process_frame
	await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(true)
	var shot := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(_OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	shot.save_png(path)
	print("[capture-snapshot-overlay] wrote ", path)
	get_tree().quit()
