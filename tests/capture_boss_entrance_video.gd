extends SceneTree
## Renders the full Press King entrance for review with Godot's Movie Maker.

const CAPTURE_FPS := 30
const TAIL_FRAMES := 12


func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred(&"capture")


func capture() -> void:
	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene._player.position = TomatinaMap.at_cell(Vector2(29,35)) + Vector3.UP * 1.28
	scene._update_camera()
	var intro = scene._boss_entrance
	intro.start(intro.spawn_point())
	for _frame in ceili(intro.DURATION * CAPTURE_FPS) + TAIL_FRAMES:
		await process_frame
	quit()
