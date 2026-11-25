extends "res://tests/probe_network.gd"
func _run() -> void:
	if OS.get_cmdline_user_args().has("--loot"):
		await _probe_loot()
		_finish()
		return
	server_world = _make_world("ServerView", "World")
	client_world = _make_world("ClientView", "World")
	await physics_frame
	set_multiplayer(SceneMultiplayer.new(), ^"/root/ServerView/World")
	set_multiplayer(SceneMultiplayer.new(), ^"/root/ClientView/World")
	_check(server_world._net.host(24781, true), "context host failed")
	_check(client_world._net.join("127.0.0.1", 24781), "context client failed")
	await _settled(server_world, client_world)
	if not failures.is_empty():
		_finish()
		return
	var peer: int = client_world._local.peer_id
	client_world._health_hud.feedback_rows.clear()
	server_world._health_hud.feedback_rows.clear()
	server_world._net.send_enemy_shake(0, PackedInt32Array([peer]), 0.0, 0.0, 2)
	for i in 12:
		await physics_frame
	_check(client_world._health_hud.feedback_rows.is_empty(), "kill displayed an unwanted center notification on client")
	_check(server_world._health_hud.feedback_rows.is_empty(), "client kill feedback leaked to host")
	if failures.is_empty():
		print("CONTEXT_NETWORK_OK")
	_finish()


func _make_loot_world(view_name: String):
	var viewport := SubViewport.new()
	viewport.name = view_name
	viewport.own_world_3d = true
	root.add_child(viewport)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/%s/World" % view_name))
	var world = load("res://stage_2_tomatina.tscn").instantiate()
	world.name = "World"
	viewport.add_child(world)
	world.set_physics_process(false)
	world.set_process_unhandled_input(false)
	return world


func _loot_key(world, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = pressed
	if pressed:
		Input.action_press("interact")
		world._unhandled_input(event)
	else:
		Input.action_release("interact")
		world._input(event)


func _probe_loot() -> void:
	server_world = _make_loot_world("ServerView")
	await physics_frame
	var body := -1
	for index in server_world._victims.positions.size():
		var at: Vector3 = server_world._victims.positions[index]
		server_world._local.player.global_position = at + Vector3(0.65, 1.28, 0)
		server_world.debug_aim_at(at + Vector3.UP * 0.35)
		if server_world.play_support.can_search_body(server_world._local, index) \
				and server_world._victims.in_reach(server_world._local.player.global_position) == index:
			body = index
			break
	_check(body >= 0, "no corpse was reachable in the test fixture")
	if body < 0:
		return
	var stand: Vector3 = server_world._local.player.global_position
	var at: Vector3 = server_world._victims.positions[body] + Vector3.UP * 0.35
	var initial_coins: int = server_world._local.coins
	_loot_key(server_world, true)
	server_world._advance_local_loot_hold(0.4)
	_check(float(server_world.rescue_hud_state().loot_progress) > 0.0, "holding E did not show progress")
	server_world._advance_tomatina_loot(1.1)
	_check(server_world._local.coins == initial_coins, "the timer paid before the held input finished")
	_loot_key(server_world, false)
	server_world._advance_tomatina_loot(1.1)
	_check(server_world._loot_attempts.is_empty() and not server_world._victims.is_looted(body),
		"releasing E did not cancel the search")
	_loot_key(server_world, true)
	server_world._local.player.global_position = stand + Vector3.LEFT * 0.6
	server_world._advance_local_loot_hold(0.4)
	_loot_key(server_world, false)
	_check(server_world._loot_attempts.is_empty(), "moving interrupted neither the progress nor the reward")

	client_world = _make_loot_world("ClientView")
	await physics_frame
	_check(server_world._net.host(24781, true), "loot host could not open the port")
	_check(client_world._net.join("127.0.0.1", 24781), "loot guest could not join")
	_check(await _until(func():
		return server_world.shooter_ids().size() == 2 and client_world.shooter_ids().size() == 2, 240),
		"the loot guest did not get a player")
	if not failures.is_empty():
		return
	var peer: int = client_world._local.peer_id
	var guest_on_host = server_world.shooter_for(peer)
	server_world._local.player.global_position = server_world.spawn_position_for(0)
	client_world._local.player.global_position = stand
	client_world.debug_aim_at(at)
	guest_on_host.player.global_position = stand
	guest_on_host.aim_yaw = client_world._local.aim_yaw
	guest_on_host.aim_pitch = client_world._local.aim_pitch
	await _wait(2)
	var prompt: Dictionary = client_world.play_support.context_target(client_world._local)
	_check(prompt.get("kind", "") == "loot" and int(prompt.get("id", -1)) == body,
		"the expected loot prompt was absent on the guest: %s" % str(prompt))
	_check(server_world.play_support.can_search_body(guest_on_host, body),
		"the host's copy of the guest could not reach the body")
	if not failures.is_empty():
		return
	_loot_key(client_world, true)
	_check(await _until(func(): return server_world._loot_attempts.has(peer), 120), "the host did not start the guest's search")
	_loot_key(client_world, false)
	_check(await _until(func(): return not server_world._loot_attempts.has(peer), 120),
		"the host did not cancel when the guest let go")
	_loot_key(client_world, true)
	_check(await _until(func(): return server_world._loot_attempts.has(peer), 120), "the guest could not restart the search")
	client_world._advance_local_loot_hold(TomatinaVictims.LOOT_TIME)
	_loot_key(client_world, false)
	_check(await _until(func(): return server_world._loot_attempts.get(peer, {}).get("finished", false), 120),
		"the host did not receive the completed hold")
	server_world._advance_tomatina_loot(0.75)
	_check(not server_world._victims.is_looted(body), "a finished request skipped the host's hold timer")
	server_world._advance_tomatina_loot(0.25)
	var payout: int = server_world._local.coins - initial_coins
	_check(server_world._victims.is_looted(body) and payout > 0 and guest_on_host.coins == payout,
		"a full hold did not pay the team")
	server_world._net.end_of_frame(PackedInt32Array())
	var synced := await _until(func():
		return client_world._victims.is_looted(body) and client_world._local.coins == payout, 360)
	_check(synced, "the guest saw %d coins and looted=%s after %d coins were awarded" % [
		client_world._local.coins, client_world._victims.is_looted(body), payout])
	server_world.perform_context_action(peer, "loot", body)
	server_world.perform_context_action(peer, "loot_finish", body)
	server_world._advance_tomatina_loot(TomatinaVictims.LOOT_TIME)
	_check(server_world._local.coins == initial_coins + payout, "the same corpse paid twice")

	var plaza := TomatinaMap.at_cell(Vector2(30.0, 33.0)) + Vector3.UP * 1.28
	server_world._local.player.global_position = plaza
	guest_on_host.player.global_position = plaza + Vector3.FORWARD
	guest_on_host.player.begin_death()
	server_world.perform_context_action(server_world._local.peer_id, "rescue", peer)
	server_world._advance_tomatina_rescues(server_world.TOMATINA_RESCUE_TIME)
	_check(guest_on_host.player.state == MayoPlayer.State.NORMAL, "the teammate rescue did not complete")
	if failures.is_empty():
		print("TOMATINA_LOOT_OK")
