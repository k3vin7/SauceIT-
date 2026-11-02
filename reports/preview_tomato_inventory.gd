extends SceneTree
func _initialize():
	MayoTutorial.disabled = true
	call_deferred("run")
func run():
	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.show_key_legend = false
	scene.healing_tomato_chance = 1
	scene.enemy_at(0).health = 0
	scene._advance_healing_tomatoes(0.01)
	var item = scene._healing_tomatoes.values()[0].node
	scene._player.global_position = item.global_position + Vector3.UP
	scene.tomato_action(scene._local.peer_id,0)
	scene._local.aim_pitch = 0.5
	scene.set_physics_process(false)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/tomato_inventory_preview.png")
	quit()
