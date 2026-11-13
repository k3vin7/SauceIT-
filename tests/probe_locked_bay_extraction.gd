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
	await physics_frame
	var arrival = scene._truck_arrival
	assert(is_instance_valid(arrival))
	check(not is_instance_valid(arrival.actor),"truck visible before victory")
	check(scene.get_node_or_null("FireTruck")==null,"initial truck collider remains")
	var locked := 0
	for cell in arrival.nav_backup:
		check(not scene._nav.is_walkable(cell),"bay cell accessible before victory")
		locked += 1
	check(locked==TomatinaMap.FIRE_BAY.size.x*TomatinaMap.FIRE_BAY.size.y,"not entire bay locked")
	var player = scene._local.player
	for height in [1.5,4.5]:
		var at := Vector3(arrival.bay.get_center().x,height,arrival.bay.end.y+1.0)
		var collision := KinematicCollision3D.new()
		check(player.test_move(Transform3D(Basis.IDENTITY,at),Vector3(0,0,-3),collision),"player can walk/jump into bay")
		check(collision.get_collider()==arrival.barrier,"approach does not hit bay blocker")
	player.global_position = TomatinaMap.at_cell(Vector2(26,34))+Vector3.UP*1.28
	var index: int = scene.tutorial_spawn_enemy(MayoTutorial.KIND_PRESS_KING,TomatinaMap.at_cell(Vector2(23.5,29.5)))
	var boss = scene._enemies[index]
	boss.health = 0
	boss.act = scene.PressKing.Act.DEATH
	boss.act_time = 2.0
	var cleared := [false]
	scene.stage_cleared.connect(func(): cleared[0]=true)
	scene._check_stage_clear()
	check(arrival.active and not scene._input_enabled,"victory did not start cutscene")
	arrival.present(4.0)
	check(not arrival.breached and arrival.barrier.collision_layer==1,"timer broke wall without truck contact")
	var captured := false
	var start := Time.get_ticks_msec()
	while arrival.active and Time.get_ticks_msec()-start<9000:
		await process_frame
		if "--capture" in OS.get_cmdline_user_args() and arrival.elapsed>3.8 and not captured:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/locked_bay_truck_arrival.png")
			captured = true
	check(arrival.impact_count==1 and arrival.vehicle_distance>20,"truck did not drive into wall")
	check(arrival.wall_bodies[0].position.distance_to(arrival.chunk_rests[0])>1,"wall debris did not move")
	check(arrival.arrived and not arrival.active,"arrival never completed")
	check(scene._input_enabled and not player.frozen,"controls not restored")
	check(arrival.barrier.collision_layer==0 and arrival.truck_body.collision_layer==1,"collision not switched after breach")
	scene._check_stage_clear()
	check(not cleared[0],"cutscene automatically ended stage")
	player.global_position = arrival.final_at+Vector3(0,1.28,arrival.truck_body.size.z*.5+10)
	scene.tomato_action(player.peer_id,0)
	check(not cleared[0],"E far from truck incorrectly ended stage")
	player.global_position = arrival.final_at+Vector3(arrival.truck_body.size.x*.5+1.1,1.28,0)
	player.state = MayoPlayer.State.NORMAL
	scene.tomato_action(player.peer_id,0)
	check(cleared[0],"explicit truck interaction failed")
	arrival.reset_intro()
	check(not arrival.active and not arrival.arrived and arrival.barrier.collision_layer==1,"reset failed to restore barrier")
	for cell in arrival.nav_backup:
		check(not scene._nav.is_walkable(cell),"reset left bay accessible")
	print("locked bay cells: ",locked)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("LOCKED_BAY_EXTRACTION_OK")
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
