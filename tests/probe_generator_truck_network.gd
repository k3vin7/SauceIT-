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
	_check(server_world._net.host(24785,true), "entrance host failed")
	_check(client_world._net.join("127.0.0.1",24785), "entrance client failed")
	await _settled(server_world,client_world)
	_check(client_world._net.debug_state_packets > 0,"entrance peers did not connect")
	if not failures.is_empty():
		_finish()
		return
	var player = server_world._local.player
	player.global_position = TomatinaMap.at_cell(TomatinaMap.SIREN_CELL)+Vector3.UP*1.28
	server_world.tomato_action(player.peer_id,0)
	print("generator start server=",server_world._horde_spawned," input=",server_world._input_enabled," normal=",player.state)
	await _until(func(): return client_world._horde_spawned,600)
	print("generator replicated client=",client_world._horde_spawned," server=",server_world._horde_spawned)
	_check(client_world._horde_spawned,"generator power state did not replicate")
	_check(client_world._siren_label.text.contains("발전기"),"client generator name incorrect")
	var remote_peer: int = client_world._local.peer_id
	server_world._shooters[remote_peer].player.global_position = TomatinaMap.at_cell(server_world.TOMATINA_HOSES[0])+Vector3.UP*1.28
	client_world._net.request_tomato_action(0)
	await _until(func(): return server_world._hose_slot_of(remote_peer)==0,120)
	_check(server_world._hose_slot_of(remote_peer)==0 and server_world._finale_elapsed < server_world.FINALE_DURATION,"remote hose did not unlock immediately")
	var at: Vector3 = server_world._truck_arrival.final_at
	server_world.show_combat_warning(at,Vector3.ZERO,6.2,server_world.TRUCK_ARRIVAL_CUE)
	server_world._net.broadcast_combat_warning(at,Vector3.ZERO,6.2,server_world.TRUCK_ARRIVAL_CUE)
	await _until(func(): return client_world._truck_arrival.active,120)
	_check(client_world._truck_arrival.active and server_world._truck_arrival.active,"arrival did not start on both peers")
	_check(not client_world._input_enabled and not server_world._input_enabled,"arrival controls were not locked")
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec()-start < 7000:
		await process_frame
	_check(client_world._truck_arrival.arrived and server_world._truck_arrival.arrived,"truck did not arrive on both peers")
	_check(client_world._input_enabled and server_world._input_enabled,"arrival controls did not return")
	_check(client_world._truck_arrival.barrier.collision_layer==0,"client barrier collision remained")
	server_world._truck_arrival.reset_intro()
	await _until(func(): return not client_world._truck_arrival.played,120)
	_check(not client_world._truck_arrival.arrived and client_world._truck_arrival.barrier.collision_layer==1,"checkpoint reset failed on client")
	if failures.is_empty(): print("GENERATOR_TRUCK_NETWORK_OK")
	_finish()
