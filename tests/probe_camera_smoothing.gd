extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	scene.set_first_person(true)
	scene.debug_set_input(Vector2(0, -1), false, false)
	var last_tick := Engine.get_physics_frames()
	var last_camera: Vector3 = scene._camera.global_position
	var between_tick_moves := 0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2000:
		await process_frame
		scene._place_viewmodel()
		scene._update_camera()
		var tick := Engine.get_physics_frames()
		var current: Vector3 = scene._camera.global_position
		if tick == last_tick and current.distance_to(last_camera) > 0.00001:
			between_tick_moves += 1
		if scene._local.aim_pivot.global_position.distance_to(current) > 0.001:
			failures.append("camera and viewmodel use different origins")
		last_tick = tick
		last_camera = current
	if between_tick_moves == 0:
		failures.append("camera never moved between physics ticks")
	scene._update_aim()
	var physical_origin: Vector3 = scene._player.global_position + Vector3.UP * scene.eye_height
	if scene._local.aim_pivot.global_position.distance_to(physical_origin) > 0.001:
		failures.append("render smoothing changed authoritative muzzle origin")
	scene._player.finish_respawn(Vector3(0, 1.28, 4))
	if scene._player.render_position().distance_to(scene._player.global_position) > 0.001:
		failures.append("respawn interpolation streak")
	var one = scene._placeholder_tone(1800, 0.05, true)
	var two = scene._placeholder_tone(1800, 0.05, true)
	if one != two:
		failures.append("audio cache missed repeated tone")
	print("camera movements between physics ticks: ", between_tick_moves)
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("CAMERA_SMOOTHING_OK")
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
