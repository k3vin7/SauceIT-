extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	# Aim straight down -Z, level. There is no cursor to warp any more.
	scene.debug_set_aim(0.0, 0.0)

	# Warm up allocations and physics before collecting the sample window.
	Input.action_press("fire_mayo")
	for _frame in 90:
		await physics_frame
	scene.debug_reset_profile()
	scene.debug_profile_enabled = true

	var max_droplet_nodes := 0
	var max_total_nodes := 0
	# Traverse the floor so new grid cells keep changing instead of repeatedly
	# painting an already-dirty stationary patch.
	Input.action_press("move_right")
	for frame in 360:
		if frame == 150:
			Input.action_release("move_right")
			Input.action_press("move_left")
		if frame == 300:
			Input.action_release("move_left")
		max_droplet_nodes = maxi(max_droplet_nodes, get_nodes_in_group("mayo_droplets").size())
		max_total_nodes = maxi(max_total_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		await physics_frame

	Input.action_release("fire_mayo")
	Input.action_release("move_left")
	scene.debug_profile_enabled = false
	var frames: int = scene.debug_profile_frames
	var total_us: int = scene.debug_timings_us.total
	print("PROFILE_CURRENT frames=%d max_points=%d rays=%d rays_per_frame=%.2f paint_calls=%d texture_uploads=%d max_droplets=%d max_nodes=%d" % [
		frames,
		scene.debug_max_points,
		scene.debug_raycast_count,
		float(scene.debug_raycast_count) / frames,
		scene._floor.debug_paint_calls(),
		scene._floor.debug_texture_uploads(),
		max_droplet_nodes,
		max_total_nodes,
	])
	for key in ["emit_follow", "point_physics", "constraint", "ribbon_update", "total"]:
		var average_us := float(scene.debug_timings_us[key]) / frames
		var share := float(scene.debug_timings_us[key]) / maxf(float(total_us), 1.0) * 100.0
		print("PROFILE_CURRENT_TIME %s avg_us=%.2f share=%.1f%%" % [key, average_us, share])
	quit(0)
