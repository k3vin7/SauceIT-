extends SceneTree

const OUTPUT := "res://reports/tomatina_sky_preview.png"


func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")


func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	for index in 8:
		await process_frame
	scene.set_physics_process(false)
	scene._local.player.finish_respawn(TomatinaMap.at_cell(Vector2(29.2, 226.0)) + Vector3.UP * 1.28)
	scene.debug_set_aim(-18.0, 42.0)
	for index in 10:
		await process_frame
	scene.set_process(false)
	for canvas in scene.find_children("*", "CanvasLayer", true, false):
		canvas.visible = false
	for child in scene._camera.get_children():
		child.queue_free()
	if is_instance_valid(scene._local.weapon):
		scene._local.weapon.visible = false
	if is_instance_valid(scene._local.camera_viewmodel):
		scene._local.camera_viewmodel.visible = false
	if is_instance_valid(scene._local.first_person_arms):
		scene._local.first_person_arms.visible = false
	for index in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT)
	print("TOMATINA_SKY_CAPTURE ", OUTPUT, " error=", error)
	quit(0 if error == OK else 1)
