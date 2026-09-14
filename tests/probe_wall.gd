extends SceneTree

# Fires continuously at ImpactWall, then releases, to check that the wall stain
# outlives the strand points that produced it.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	var wall: ContaminableObject = scene.get_node("ImpactWall")
	# Aim at the wall through the normal aim path, so _update_aim keeps
	# reproducing this direction every physics frame.
	scene.debug_aim_at(Vector3(2.35, 1.1, -0.72))
	print("landing_transition_time=%.2f s  raycast_frame_stride=%d  emit_rate=%.1f pts/s" % [
		scene.landing_transition_time, scene.raycast_frame_stride,
		scene.extend_speed / scene.point_spacing])

	var accumulator := 0.0
	for frame in 600:
		var firing := frame < 300
		if firing:
			accumulator += scene.extend_speed / 60.0
		while firing and accumulator >= scene.point_spacing:
			accumulator -= scene.point_spacing
			scene._emit_point()
		scene._simulate_points(1.0 / 60.0)
		scene._enforce_spacing_constraint()
		await physics_frame
		if frame % 30 == 0:
			var fixed := 0
			for point in scene._points:
				if point.phase == 1:
					fixed += 1
			print("t=%.2fs firing=%-5s LANDING=%3d  wall_painted_cells=%3d  wall_paint_calls=%4d  wall_uploads=%3d" % [
				frame / 60.0, str(firing), fixed, wall.painted_cell_count(),
				wall.debug_paint_calls(), wall.debug_texture_uploads()])
	quit(0)
