extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


## Range from the muzzle to the closest point that is currently landing.
func _nearest_landing_range(scene, muzzle_flat: Vector3) -> float:
	var nearest := INF
	for point in scene._points:
		if point.phase != 2:
			continue
		var flat: Vector3 = point.position
		flat.y = 0.0
		nearest = minf(nearest, flat.distance_to(muzzle_flat))
	return nearest


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	# Aim straight down -Z, level. There is no cursor to warp any more.
	scene.debug_set_aim(0.0, 0.0)
	Input.action_press("fire_mayo")
	for _frame in 55:
		await physics_frame

	var powered_count := 0
	var falling_count := 0
	for point in scene._points:
		if point.phase == 0 and point.powered:
			powered_count += 1
		elif point.phase == 0 and not point.powered:
			falling_count += 1
	_check(powered_count > 0, "continuous fire has no newly powered tail points")
	_check(falling_count > 0, "continuous fire has no independently falling front points")
	_check(scene._air_visual.mesh != null, "air ribbon mesh was not generated")
	_check(scene._shadow_visual.mesh != null, "projected shadow mesh was not generated")

	for _frame in 75:
		await physics_frame
	var painted_cells: int = scene._floor.grid.painted_cell_count()
	_check(painted_cells > 0, "ballistic points did not paint the floor grid")

	var muzzle_flat: Vector3 = scene._muzzle.global_position
	muzzle_flat.y = 0.0
	var sustained_near := _nearest_landing_range(scene, muzzle_flat)

	Input.action_release("fire_mayo")
	var released_near := sustained_near
	for _frame in 80:
		await physics_frame
		released_near = minf(released_near, _nearest_landing_range(scene, muzzle_flat))
	_check(scene._points.size() < 45, "released strand did not drain in point-age order")
	# Pressure loss is strongest at the muzzle end, so releasing must drag the
	# trail back toward the player rather than leave a puddle at full range.
	_check(released_near < sustained_near - 0.5,
		"released strand landed at sustained range instead of retracting toward the muzzle")
	_check(get_nodes_in_group("mayo_droplets").size() == 1,
		"landing droplets created nodes instead of reusing the single pool")

	# Multiple distinct dirty writes in one frame must result in one texture upload.
	scene.set_physics_process(false)
	scene._points.clear()
	scene._floor._rebuild_grid()
	scene._floor.reset_debug_counters()
	for i in 8:
		scene._floor.paint_mayo(Vector3(-3.5 + float(i), 0.0, 3.0))
	_check(scene._floor.debug_texture_uploads() == 0, "grid uploaded during an individual paint call")
	await process_frame
	await process_frame
	_check(scene._floor.debug_texture_uploads() == 1, "grid writes were not batched to one frame upload")

	# Isolate and run the wall route with the same per-point physics code.
	scene.debug_aim_at(Vector3(2.35, 1.1, -0.72))
	var accumulator := 0.0
	for _frame in 70:
		accumulator += scene.extend_speed / 60.0
		while accumulator >= scene.point_spacing:
			accumulator -= scene.point_spacing
			scene._emit_point()
		scene._simulate_points(1.0 / 60.0)
		scene._enforce_spacing_constraint()
		await physics_frame
	var fixed_count := 0
	for point in scene._points:
		if point.phase == 1:
			fixed_count += 1
	_check(fixed_count > 0, "wall route produced no fixed points")

	# The wall stain is written at collision time, so it must outlive the points.
	var wall: ContaminableObject = scene.get_node("ImpactWall")
	var wall_cells := wall.painted_cell_count()
	_check(wall_cells > 0, "wall impacts did not paint the wall grid")
	_check(wall.debug_texture_uploads() < wall.debug_paint_calls(),
		"wall grid writes were not batched to one upload per frame")
	scene._points.clear()
	for _frame in int(scene.wall_fixed_hold_time * 60.0) + 30:
		scene._simulate_points(1.0 / 60.0)
		await physics_frame
	_check(wall.painted_cell_count() == wall_cells,
		"wall stain disappeared once its strand points expired")

	if failures.is_empty():
		print("MAYO_SMOKE_OK powered=%d falling=%d painted=%d fixed=%d wall_cells=%d retract=%.2fm" % [
			powered_count, falling_count, painted_cells, fixed_count, wall_cells,
			sustained_near - released_near
		])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
