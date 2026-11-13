extends "res://tests/probe_network.gd"
func _make_world(view_name: String, world_name: String):
	var viewport := SubViewport.new()
	viewport.name = view_name
	viewport.own_world_3d = true
	viewport.size = Vector2i(64,64)
	root.add_child(viewport)
	var world = load("res://stage_2_tomatina.tscn").instantiate()
	world.name = world_name
	viewport.add_child(world)
	world.set_process_unhandled_input(false)
	return world
func _run() -> void:
	server_world = _make_world("ServerView","World")
	client_world = _make_world("ClientView","World")
	await physics_frame
	set_multiplayer(SceneMultiplayer.new(), ^"/root/ServerView/World")
	set_multiplayer(SceneMultiplayer.new(), ^"/root/ClientView/World")
	_check(server_world._net.host(24783,true), "entrance host failed")
	_check(client_world._net.join("127.0.0.1",24783), "entrance client failed")
	await _settled(server_world,client_world)
	_check(client_world._net.debug_state_packets > 0,"entrance peers did not connect")
	if not failures.is_empty():
		_finish()
		return
	var at: Vector3 = server_world._boss_entrance.spawn_point()
	server_world.show_combat_warning(at,Vector3.ZERO,6.2,server_world.PRESS_KING_RISE_CUE)
	server_world._net.broadcast_combat_warning(at,Vector3.ZERO,6.2,server_world.PRESS_KING_RISE_CUE)
	await _until(func(): return client_world._boss_entrance.active, 120)
	_check(client_world._boss_entrance.active and server_world._boss_entrance.active,"entrance did not start on both peers")
	_check(not client_world._input_enabled and not server_world._input_enabled,"input was not locked on both peers")
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec()-start < 7000:
		await process_frame
	_check(not client_world._boss_entrance.active and not server_world._boss_entrance.active,"entrance failed to finish")
	_check(client_world._input_enabled and server_world._input_enabled,"controls did not return on both peers")
	_check(client_world._boss_entrance.chunks[0].position.distance_to(client_world._boss_entrance.chunk_rests[0]) > 1.0,"client wall did not break")
	if failures.is_empty(): print("BOSS_ENTRANCE_NETWORK_OK")
	_finish()
