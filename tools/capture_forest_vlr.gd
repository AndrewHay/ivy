extends SceneTree

const _SCENE := "res://scenes/playground/forest_playground.tscn"
const _OUT_ROOT := "/Users/andrewhay/github/ivy/.tmp/vlr/forest"
const _SEEDS: Array[int] = [1, 7, 12]
const _VARIANTS: Array = [
	{"name": "production", "variant": 0, "preset": ""},
	{"name": "deep_wedge", "variant": 1, "preset": "Deep wedge"},
	{"name": "arc_ring", "variant": 2, "preset": "Arc ring behind hero"},
	{"name": "flank_gap", "variant": 3, "preset": "Wedge + CamSun gap flanks"},
]
const _CAMERAS: Array = ["camsun", "wide"]


func _initialize() -> void:
	call_deferred("_run")
	quit(0)


func _run() -> void:
	print("[forest-capture] use per-shot Godot scene runs with --out= (see bead notes)")
	quit(0)
