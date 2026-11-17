extends SceneTree
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	for index in 3:
		await process_frame
	var enemy: MayoEnemy
	for candidate in scene._enemies:
		if candidate.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT:
			enemy = candidate
			break
	var at: Vector3 = enemy.global_position + Vector3(0, 0, 11)
	at.y = 1.28
	scene._local.player.finish_respawn(at)
	scene.debug_aim_at(enemy.global_position)
	scene.set_physics_process(false)
	for candidate in scene._enemies:
		candidate.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for index in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/tomatina_revision_combat.png")
	var slots: Array = scene.item_slots(scene._local.peer_id)
	slots[1] = 1
	scene._item_selected[scene._local.peer_id] = 1
	scene._held_tomatoes[scene._local.peer_id] = scene._make_healing_tomato(scene._local.player.global_position)
	scene._tomato_charge_started[scene._local.peer_id] = Time.get_ticks_msec() - 1200
	scene.play_support._update_arc(scene._local.player.global_position + Vector3.UP * 0.65, Vector3(0, 0.25, -1).normalized())
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/tomatina_revision_arc.png")
	scene.queue_free()
	await process_frame
	var app = load("res://app.tscn").instantiate()
	app.save_path_override = "res://reports/runtime_home/capture_settings.cfg"
	root.add_child(app)
	app._open_options()
	for index in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/tomatina_revision_options.png")
	app.queue_free()
	await process_frame
	print("REVISION_CAPTURE_OK")
	quit()
