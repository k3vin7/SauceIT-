extends SceneTree
## Original, in-place first-person performances. Camera and gameplay muzzle
## have no animation tracks. Positions are metres, rotations are radians.
func _initialize() -> void:
	var library := AnimationLibrary.new()
	clip(library, "idle", 2.4, true, [Vector3.ZERO, Vector3(0.002,0.004,0), Vector3.ZERO], [Vector3.ZERO, Vector3(0.006,0,0.004), Vector3.ZERO])
	clip(library, "walk", 0.64, true, [Vector3(-0.012,0,0),Vector3(0,-0.012,0.006),Vector3(0.012,0,0),Vector3(0,-0.012,0.006),Vector3(-0.012,0,0)], [Vector3(0,0,-0.015),Vector3(0.008,0,0),Vector3(0,0,0.015),Vector3(0.008,0,0),Vector3(0,0,-0.015)])
	clip(library, "run", 0.46, true, [Vector3(-0.022,-0.015,0.012),Vector3(0,-0.035,0.025),Vector3(0.022,-0.015,0.012),Vector3(0,-0.035,0.025),Vector3(-0.022,-0.015,0.012)], [Vector3(-0.025,0,-0.025),Vector3(-0.045,0,0),Vector3(-0.025,0,0.025),Vector3(-0.045,0,0),Vector3(-0.025,0,-0.025)])
	clip(library, "fire_start", 0.22, false, [Vector3.ZERO,Vector3(0,-0.009,0.032),Vector3(0,0.004,-0.006),Vector3.ZERO], [Vector3.ZERO,Vector3(-0.035,0,0.012),Vector3(0.012,0,-0.004),Vector3.ZERO])
	clip(library, "fire_loop", 0.18, true, [Vector3.ZERO,Vector3(0.002,-0.003,0.006),Vector3.ZERO], [Vector3.ZERO,Vector3(-0.007,0,0.004),Vector3.ZERO])
	clip(library, "fire_stop", 0.26, false, [Vector3.ZERO,Vector3(0,0.006,-0.012),Vector3(0,-0.002,0.004),Vector3.ZERO], [Vector3.ZERO,Vector3(0.018,0,0),Vector3(-0.006,0,0),Vector3.ZERO])
	clip(library, "shake_start", 0.18, false, [Vector3.ZERO,Vector3(-0.018,0.02,0.018),Vector3.ZERO], [Vector3.ZERO,Vector3(0,0,-0.06),Vector3.ZERO])
	clip(library, "shake_loop", 0.32, true, [Vector3(0,-0.024,0.008),Vector3(-0.009,0.035,-0.012),Vector3(0.006,-0.024,0.008),Vector3(0.009,0.035,-0.012),Vector3(0,-0.024,0.008)], [Vector3(-0.04,0,-0.035),Vector3(0.05,0,0.035),Vector3(-0.04,0,0.035),Vector3(0.05,0,-0.035),Vector3(-0.04,0,-0.035)])
	clip(library, "recover", 0.3, false, [Vector3.ZERO,Vector3(0,-0.012,0.014),Vector3(0,0.005,-0.004),Vector3.ZERO], [Vector3.ZERO,Vector3(-0.025,0,0.02),Vector3(0.01,0,-0.008),Vector3.ZERO])
	clip(library, "jump", 0.32, false, [Vector3.ZERO,Vector3(0,-0.035,0.018),Vector3(0,0.009,-0.008),Vector3.ZERO], [Vector3.ZERO,Vector3(-0.06,0,0.018),Vector3(0.02,0,-0.006),Vector3.ZERO])
	clip(library, "air", 0.9, true, [Vector3(0,0.004,0.006),Vector3(0,0.009,0.002),Vector3(0,0.004,0.006)], [Vector3(0.012,0,-0.008),Vector3(0.02,0,0.008),Vector3(0.012,0,-0.008)])
	clip(library, "land", 0.36, false, [Vector3.ZERO,Vector3(0,-0.05,0.025),Vector3(0,0.014,-0.009),Vector3.ZERO], [Vector3.ZERO,Vector3(-0.075,0,0.025),Vector3(0.025,0,-0.008),Vector3.ZERO])
	DirAccess.make_dir_recursive_absolute("res://assets/players/first_person")
	assert(ResourceSaver.save(library, "res://assets/players/first_person/movement.tres") == OK)
	print("VIEWMODEL_ANIMATIONS_BUILT clips=", library.get_animation_list().size())
	quit()

func clip(library: AnimationLibrary, label: String, seconds: float, loop: bool, positions: Array, rotations: Array) -> void:
	var animation := Animation.new()
	animation.length = seconds
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for property in ["position", "rotation"]:
		var track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, NodePath(".:" + property))
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		var values: Array = positions if property == "position" else rotations
		for index in values.size():
			animation.track_insert_key(track, seconds * float(index) / float(values.size() - 1), values[index])
	library.add_animation(label, animation)
