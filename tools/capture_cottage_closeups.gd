## Throwaway: two diagonal close-ups of every generated cottage, backdrop only.
## Usage (non-headless): Godot --path . --resolution 960x540 --script res://tools/capture_cottage_closeups.gd
extends SceneTree

const OUT := "res://.tmp/village/closeups/"
const BackdropScene := preload("res://src/world/village_backdrop.tscn")

var _frame := 0
var _cam: Camera3D
var _shots: Array = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var root := Node3D.new()
	get_root().add_child(root)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.8, 0.95)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.62, 0.38)
	ground.material_override = mat
	root.add_child(ground)
	root.add_child(BackdropScene.instantiate())
	_cam = Camera3D.new()
	root.add_child(_cam)
	_shots.append(["CD_inside_east", Vector3(-11.0, 1.7, 11.0), Vector3(-7.0, 1.7, 11.0)])
	_shots.append(["CD_outside_east", Vector3(-3.0, 1.7, 11.0), Vector3(-8.0, 1.9, 11.0)])
	for spec in VillageBackdrop.COTTAGES:
		var c: Vector2 = spec["centre"]
		var door: Vector2 = VillageBackdrop.cottage_door(spec)[1]
		var side := Vector2(-door.y, door.x)
		var target := Vector3(c.x, 2.5, c.y)
		for k in [1.0, -1.0]:
			var off: Vector2 = (door * k + side * 0.8) * 9.0
			_shots.append(["%s_%s" % [spec["name"], "door" if k > 0 else "back"],
				Vector3(c.x + off.x, 4.5, c.y + off.y), target])
		var ridge3: Vector3 = VillageBackdrop.cottage_transform(spec).basis.x
		var ridge := Vector2(ridge3.x, ridge3.z)
		for k in [1.0, -1.0]:
			var p: Vector2 = c + ridge * k * (float(spec["bays"]) + 6.0)
			_shots.append(["%s_end_%s" % [spec["name"], "right" if k > 0 else "left"],
				Vector3(p.x, 1.7, p.y), Vector3(c.x, 2.2, c.y)])


func _process(_delta: float) -> bool:
	_frame += 1
	var idx := _frame / 10
	if _frame % 10 == 1 and idx < _shots.size():
		_cam.look_at_from_position(_shots[idx][1], _shots[idx][2])
		_cam.make_current()
	if _frame % 10 == 9 and idx < _shots.size():
		get_root().get_viewport().get_texture().get_image().save_png(OUT + "%s.png" % _shots[idx][0])
	return _frame >= _shots.size() * 10
