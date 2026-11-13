extends SceneTree
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	scene.set_first_person(false)
	var player = scene._local.player
	player.frozen = true
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	for variant in 4:
		scene.set_character_variant(scene._local.peer_id, variant)
		camera.global_position = player.global_position + Vector3(3.2, 1.2, -4.0)
		camera.look_at(player.global_position + Vector3.UP * 0.1)
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/player_motion_%d.png" % variant)
	scene.set_first_person(true)
	scene._camera.current = true
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/player_motion_first_person.png")
	quit()
