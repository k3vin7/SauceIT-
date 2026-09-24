extends SceneTree

const SOURCE := "res://assets/enemies/Stage1_MoldyToastRusher/Stage1_MoldyToastRusher.glb"
const TARGET := "res://assets/enemies/Stage1_MoldyToastRusher/Stage1_MoldyToastRusher.scn"


func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(SOURCE, state)
	if error != OK:
		push_error("Could not parse rusher GLB: %s" % error_string(error))
		quit(1)
		return
	var root := document.generate_scene(state)
	if root == null:
		push_error("Could not generate rusher scene")
		quit(1)
		return
	var packed := PackedScene.new()
	error = packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, TARGET)
	root.free()
	if error != OK:
		push_error("Could not save rusher scene: %s" % error_string(error))
		quit(1)
		return
	print("MOLDY_TOAST_RUSHER_IMPORTED ", TARGET)
	quit(0)
