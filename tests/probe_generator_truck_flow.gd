extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text)
func run() -> void:
	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	assert(is_instance_valid(scene._truck_arrival),"arrival script failed")
	scene.set_physics_process(false)
	var arrival = scene._truck_arrival
	check(not arrival.arrived and not is_instance_valid(arrival.actor),"fire truck exists before boss death")
	check(arrival.barrier.collision_layer == 1,"bay is not physically blocked")
	var barrier_collider := arrival.barrier.get_child(0) as CollisionShape3D
	var barrier_shape := barrier_collider.shape as BoxShape3D
	check(arrival.wall_span > arrival.bay.size.x
		and is_equal_approx(barrier_shape.size.x, arrival.sealed_wall_span),
		"extraction wall does not overlap and seal both side walls")
	var wall_returns: Array[Node] = arrival.facade.find_children(
		"ExtractionWallReturn*", "MeshInstance3D", false, false)
	check(wall_returns.size() == 2, "extraction wall is open behind an end post")
	var player_probe := CapsuleShape3D.new()
	player_probe.radius = 0.64
	player_probe.height = 2.56
	for side in [-1,1]:
		var seam_query := PhysicsShapeQueryParameters3D.new()
		seam_query.shape = player_probe
		seam_query.collision_mask = 1
		seam_query.transform = Transform3D(Basis.IDENTITY, Vector3(
			arrival.wall_at.x + float(side) * arrival.wall_span * 0.5,
			1.28, arrival.wall_at.z - arrival.WALL_RETURN_DEPTH * 0.5))
		var seam_hits: Array[Dictionary] = scene.get_world_3d().direct_space_state.intersect_shape(
			seam_query, 8)
		var hit_lock := false
		for hit in seam_hits:
			if hit.get("collider") == arrival.barrier:
				hit_lock = true
				break
		check(hit_lock, "player can enter behind the %s extraction-wall post"
			% ("left" if side < 0 else "right"))
	check(arrival.wall_bodies.size() > 64,"reinforced wall is missing its rubble apron")
	for cell in arrival.nav_backup:
		check(not scene._nav.is_walkable(cell),"bay barricade missing from navigation")
	check(scene._siren_label.text == "발전기","generator name incorrect")
	check(is_instance_valid(scene._pump_generator),"generator model missing")
	if "--capture" in OS.get_cmdline_user_args():
		scene.process_mode = Node.PROCESS_MODE_DISABLED
		scene._hud_layer.hide()
		scene._camera.global_position = scene._pump_generator.global_position+Vector3(4.8,3.1,4.5)
		scene._camera.look_at(scene._pump_generator.global_position+Vector3.UP*.9)
		scene._sync_camera_viewmodel()
		if is_instance_valid(scene._local.camera_viewmodel): scene._local.camera_viewmodel.hide()
		if is_instance_valid(scene._local.first_person_arms): scene._local.first_person_arms.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/pump_generator.png")
		var seam_target: Vector3 = arrival.wall_at + Vector3.UP * 2.4
		for side in [-1, 1]:
			var edge_x: float = arrival.wall_at.x + float(side) * arrival.wall_span * 0.5
			scene._camera.global_position = Vector3(
				edge_x - float(side) * 3.0, 1.62, arrival.wall_at.z - 7.0)
			scene._camera.look_at(seam_target + Vector3(
				float(side) * arrival.wall_span * 0.5, 0.0, -1.2))
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				"res://reports/truck_wall_inside_%s.png" % ("left" if side < 0 else "right"))
		scene._hud_layer.show()
		scene.process_mode = Node.PROCESS_MODE_INHERIT
	var player = scene._local.player
	player.global_position = TomatinaMap.at_cell(TomatinaMap.SIREN_CELL)+Vector3.UP*1.28
	scene.tomato_action(player.peer_id,0)
	check(scene._horde_spawned and scene._finale_elapsed == 0.0,"generator did not start")
	player.global_position = TomatinaMap.at_cell(scene.TOMATINA_HOSES[0])+Vector3.UP*1.28
	scene.tomato_action(player.peer_id,0)
	check(scene._hose_slot_of(player.peer_id) == 0,"water hose not usable immediately after generator")
	scene._hose_users.clear()
	var index: int = scene.tutorial_spawn_enemy(MayoTutorial.KIND_PRESS_KING,TomatinaMap.at_cell(Vector2(23.5,29.5)))
	var boss = scene._enemies[index]
	boss.health = 0.0
	boss.act = scene.PressKing.Act.DEATH
	boss.act_time = 2.0
	var cleared := [false]
	scene.stage_cleared.connect(func(): cleared[0] = true)
	scene._check_stage_clear()
	check(arrival.active and not cleared[0],"boss death did not start arrival cinematic")
	arrival.set_process(false)
	var capture := "--capture" in OS.get_cmdline_user_args()
	if capture: scene.process_mode = Node.PROCESS_MODE_DISABLED
	var frame := 0
	for time in [1.5,2.5,4.3]:
		scene._update_camera()
		arrival.present(time)
		if capture:
			await process_frame
			scene._update_camera()
			arrival.present(time)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/truck_arrival_%d.png" % frame)
		frame += 1
	# finish() waits for the bumper to physically meet the wall, which only the
	# physics step detects; this probe drives the cinematic by hand, so it breaks
	# the wall the way that contact does. probe_generator_truck_network covers
	# the real contact.
	check(not arrival.breached, "wall broke without the truck reaching it")
	arrival._break_wall(Vector3(0, 0, 10), false)
	arrival.finish()
	check(arrival.arrived and arrival.barrier.collision_layer == 0,"barricade was not opened")
	check(arrival.truck_body.collision_layer == 1 and is_instance_valid(arrival.actor),"truck did not remain after cinematic")
	check(scene._input_enabled and not player.frozen,"controls did not return")
	scene._check_stage_clear()
	check(not cleared[0],"arrival automatically ended stage")
	player.global_position = arrival.final_at+Vector3(4.0,1.28,0)
	player.state = MayoPlayer.State.NORMAL
	scene.tomato_action(player.peer_id,0)
	check(arrival.escape_active and not cleared[0],"truck interaction skipped the escape film")
	check(is_instance_valid(arrival.escape_truck) and arrival.escape_root.get_child_count() > 100,
		"escape film did not build the engine and endless road")
	arrival._finish_escape()
	check(cleared[0],"escape film completion did not end stage")
	arrival.reset_intro()
	check(not arrival.arrived and arrival.barrier.collision_layer == 1,"checkpoint failed to reset barricade")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("GENERATOR_TRUCK_FLOW_OK")
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
