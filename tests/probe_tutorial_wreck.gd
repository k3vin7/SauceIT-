extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.push_back(message)

func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await process_frame
	world.set_process_unhandled_input(false)
	world.debug_set_input(Vector2.ZERO, false, false)
	var wreck = world.get_node_or_null("TutorialWreck")
	_check(wreck != null, "tutorial has no wreck")
	var floor_body: FloorContamination = world._floor
	var nav: StreetNav = world._nav
	# Every traversable column has thick sauce; the outer columns have real
	# collision and are excluded from the monster's routing grid.
	for sample in range(-180, 181):
		var x := float(sample) * 0.1
		var at := Vector3(x, 1.0, TutorialWreck.CENTRE_Z)
		var query := PhysicsRayQueryParameters3D.create(
			at + Vector3(0, 0, 5), at - Vector3(0, 0, 5), 1)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		if absf(x) > TutorialWreck.HALF_GAP + 0.1:
			_check(not hit.is_empty(), "no physical barrier at x=%.1f" % x)
			_check(not nav.line_is_walkable(at + Vector3(0, 0, 5), at - Vector3(0, 0, 5)), "nav crosses wreck at x=%.1f" % x)
		else:
			_check(floor_body.is_slippery_at(Vector3(x, 0, TutorialWreck.SPILL_CENTRE)), "dry escape lane at x=%.1f" % x)
	var route := nav.route(Vector3(-12, 0, -23), Vector3(-12, 0, -47))
	_check(not route.is_empty(), "the burger has no route through the gap")
	var crossed := false
	for point in route:
		if absf(point.z - TutorialWreck.CENTRE_Z) < 0.1:
			crossed = true
			_check(absf(point.x) < TutorialWreck.HALF_GAP, "route goes through a cart")
	_check(crossed, "route bypasses the passage")
	_check(world.tutorial().marker_position() != Vector3.INF, "starting stall has no marker")
	_check(not floor_body.is_slippery_at(Vector3(0, 0, TutorialWreck.CENTRE_Z)),
		"deep spill causes a fall before crossing the gap")
	world.tutorial()._pick_refill_station()
	_check(world.tutorial()._station_position.z < TutorialWreck.SPILL_BACK,
		"refill objective is on the starting side of the wreck")
	# Initial geometry and sauce are reproducible, including before a network
	# snapshot arrives. Re-seeding in an isolated floor must give the same hash.
	var expected := floor_body.cells_md5()
	var replica := FloorContamination.new()
	replica.floor_size = floor_body.floor_size
	replica.position = floor_body.position
	replica.cell_size = floor_body.cell_size
	replica.brush_radius = floor_body.brush_radius
	root.add_child(replica)
	wreck.seed_floor(replica)
	_check(replica.cells_md5() == expected, "static spill differs between worlds")
	replica.free()
	print("wreck: route points=%d, deep cells=%d, source=%s" % [
		route.size(), floor_body.deep_cell_count(), str(wreck != null)])
	if "--capture" in OS.get_cmdline_user_args():
		world.set_physics_process(false)
		world.set_process(false)
		world._player.frozen = true
		world.set_first_person(false)
		world._hud_layer.hide()
		world._camera.position = Vector3(1.5, 8.5, -18)
		world._camera.look_at(Vector3(-1, 1.5, TutorialWreck.CENTRE_Z))
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.resize(1600, 900, Image.INTERPOLATE_LANCZOS)
		shot.save_png("res://reports/tutorial_wreck.png")
	world.free()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("MAYO_TUTORIAL_WRECK_OK")
	quit(0 if failures.is_empty() else 1)
